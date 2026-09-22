"""Generación del ticket/boleto de pesaje.

Dos formatos:
  - PDF: boleto visual completo (formato Carta).
  - TXT: ticket sencillo en texto plano según WORKFLOW / MODEL.

Si el boleto está ANULADO se imprime con marca de agua 'ANULADO' (solo PDF).
"""

from __future__ import annotations

import glob
import io
import os
from datetime import datetime
from decimal import Decimal, InvalidOperation
from typing import Any

from fastapi.responses import StreamingResponse
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import (
    Image,
    KeepTogether,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

from app.core.config import settings
from app.models import BoletoPesaje, Empresa
from app.services.weighing_service import normalizar_estado

# ─────────────────────────────────────────────────────────────────────────────
# Paleta y constantes (PDF)
# ─────────────────────────────────────────────────────────────────────────────
AZUL_MARINO = colors.HexColor("#1A365D")
AZUL_PRIMARIO = colors.HexColor("#2B6CB0")
AZUL_CLARO = colors.HexColor("#EBF4FF")
GRIS_TEXTO = colors.HexColor("#2D3748")
GRIS_MEDIO = colors.HexColor("#718096")
GRIS_SUAVE = colors.HexColor("#F7FAFC")
GRIS_BORDE = colors.HexColor("#CBD5E0")
GRIS_ENCABEZADO = colors.HexColor("#EDF2F7")
ROJO_ANULADO = colors.HexColor("#C53030")
VERDE_OK = colors.HexColor("#2F855A")
AMBAR_PENDIENTE = colors.HexColor("#B7791F")
MORADO_PROCESO = colors.HexColor("#6B46C1")

FUENTE = "DejaVu"
FUENTE_BOLD = "DejaVu-Bold"
_FUENTES_REGISTRADAS = False

ANCHO_UTIL = 180 * mm
ESPACIO = 4 * mm


# ─────────────────────────────────────────────────────────────────────────────
# Formateo de números y fechas
# ─────────────────────────────────────────────────────────────────────────────
def _fmt(v: Decimal | float | int | str | None, decimales: int = 2) -> str:
    """Formatea número con separador de miles latino y coma decimal."""
    if v is None or v == "":
        return "0,00"
    try:
        if isinstance(v, Decimal):
            num = float(v)
        elif isinstance(v, (int, float)):
            num = float(v)
        else:
            num = float(str(v).replace(",", "."))
    except (ValueError, InvalidOperation):
        return str(v)
    formato = f"{{:,.{decimales}f}}"
    return formato.format(num).replace(",", "X").replace(".", ",").replace("X", ".")


def _fmt_dt(dt: datetime | None) -> str:
    return dt.strftime("%d/%m/%Y %H:%M") if dt else "—"


def _fmt_peso_html(v: Decimal | float | None) -> str:
    """Devuelve el peso formateado; en rojo si es negativo."""
    txt = _fmt(v)
    try:
        if v is not None and float(v) < 0:
            return f'<font color="#C53030"><b>{txt}</b></font>'
    except (TypeError, ValueError):
        pass
    return txt


def _dato(p: BoletoPesaje) -> dict[str, Any]:
    pe_vehiculo = p.peso_entrada_vehiculo or Decimal("0")
    pe_remolque = p.peso_entrada_remolque or Decimal("0")
    ps_vehiculo = p.peso_salida_vehiculo or Decimal("0")
    ps_remolque = p.peso_salida_remolque or Decimal("0")

    remolque_txt = "—"
    if getattr(p, "remolque", None):
        placa_rem = getattr(p, "placa_remolque", None) or getattr(p, "remolque_placa", None)
        remolque_txt = f"Sí — {placa_rem}" if placa_rem else "Sí"

    # Datos legibles de catálogos (sin UUIDs técnicos)
    producto_txt = getattr(p, "producto", None) or getattr(p, "producto_nombre", None) or "—"
    conductor_txt = getattr(p, "conductor", None) or getattr(p, "conductor_nombre", None) or getattr(p, "id_conductor", None) or "—"
    transporte_txt = getattr(p, "transporte", None) or getattr(p, "transporte_nombre", None) or "—"
    tercero_txt = getattr(p, "razon_social", None) or getattr(p, "tercero_nombre", None) or "—"
    almacen_txt = getattr(p, "almacen", None) or getattr(p, "almacen_nombre", None) or "—"

    return {
        "numero": p.numero_boleto or (f"BOL-{str(p.boleto)[:8].upper()}" if getattr(p, "boleto", None) else "Boleto s/n"),
        "fecha_hora": _fmt_dt(p.fecha_hora_entrada),
        "camion": p.id_vehiculo or "—",
        "remolque": remolque_txt,
        "producto": producto_txt,
        "conductor": conductor_txt,
        "transporte": transporte_txt,
        "razon_social": tercero_txt,
        "almacen": almacen_txt,
        "pe_vehiculo": pe_vehiculo,
        "pe_remolque": pe_remolque,
        "ps_vehiculo": ps_vehiculo,
        "ps_remolque": ps_remolque,
        "total_entrada": pe_vehiculo + pe_remolque,
        "total_salida": ps_vehiculo + ps_remolque,
        "neto": p.peso_neto or Decimal("0"),
        "declarado": p.peso_neto_declarado or Decimal("0"),
        "diferencia": p.peso_diferencia,
        "desviacion": p.porcentaje_desviacion,
        "documento": p.documento or "—",
        "unidades": p.unidades,
        "densidad": p.densidad,
        "litros": p.litros,
        "observaciones": (p.observaciones or "").strip(),
        "estado": normalizar_estado(p.estado_boleto),
        "motivo_anulacion": p.motivo_anulacion,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Fuentes (PDF)
# ─────────────────────────────────────────────────────────────────────────────
def _registrar_ttf() -> None:
    """Registra DejaVu Sans (regular + bold) una sola vez."""
    global _FUENTES_REGISTRADAS
    if _FUENTES_REGISTRADAS:
        return

    base = bold = None
    candidatas = [
        (
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        ),
    ]
    for reg, bld in candidatas:
        if os.path.exists(reg):
            base, bold = reg, bld if os.path.exists(bld) else reg
            break

    if base is None:
        halls = glob.glob("/usr/share/fonts/**/DejaVuSans.ttf", recursive=True)
        if halls:
            base = halls[0]
            bold = halls[0].replace("DejaVuSans.ttf", "DejaVuSans-Bold.ttf")
            if not os.path.exists(bold):
                bold = base

    if base:
        pdfmetrics.registerFont(TTFont(FUENTE, base))
        pdfmetrics.registerFont(TTFont(FUENTE_BOLD, bold))
        try:
            pdfmetrics.registerFontFamily(
                FUENTE, normal=FUENTE, bold=FUENTE_BOLD,
                italic=FUENTE, boldItalic=FUENTE_BOLD,
            )
        except Exception:
            pass
    else:
        pdfmetrics.registerFont(TTFont(FUENTE, "Helvetica"))
        pdfmetrics.registerFont(TTFont(FUENTE_BOLD, "Helvetica-Bold"))

    _FUENTES_REGISTRADAS = True


# ─────────────────────────────────────────────────────────────────────────────
# Encabezado empresa
# ─────────────────────────────────────────────────────────────────────────────
def _empresa_cabecera(empresa: Empresa | None) -> dict[str, Any]:
    if empresa is None:
        return {"nombre": "", "rif": "", "direccion": "", "telefono": "",
                "email": "", "logo": None}

    nombre = (empresa.nombre_comercial or empresa.nombre_fiscal or "").strip()
    logo = None
    logo_url = getattr(empresa, "logo_url", None)
    if logo_url:
        rel = str(logo_url).lstrip("/")
        if rel.startswith("media/"):
            rel = rel[len("media/"):]
        candidato = os.path.join(settings.media_dir, rel)
        if os.path.isfile(candidato):
            logo = candidato

    return {
        "nombre": nombre,
        "rif": (empresa.rif_nit or "").strip(),
        "direccion": (empresa.direccion or "").strip(),
        "telefono": (empresa.telefono or "").strip(),
        "email": (empresa.email or "").strip(),
        "logo": logo,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Estilos de párrafo (PDF)
# ─────────────────────────────────────────────────────────────────────────────
def _estilos() -> dict[str, ParagraphStyle]:
    es = getSampleStyleSheet()
    return {
        "empresa": ParagraphStyle(
            "empresa", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=12.5, leading=14, textColor=AZUL_MARINO,
        ),
        "info": ParagraphStyle(
            "info", parent=es["Normal"], fontName=FUENTE,
            fontSize=8, leading=10, textColor=GRIS_TEXTO,
        ),
        "titulo": ParagraphStyle(
            "titulo", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=11, leading=13, textColor=AZUL_MARINO,
            alignment=TA_RIGHT,
        ),
        "ticket_num": ParagraphStyle(
            "ticket_num", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=18, leading=20, textColor=AZUL_PRIMARIO,
            alignment=TA_RIGHT,
        ),
        "label": ParagraphStyle(
            "label", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=7, leading=9, textColor=GRIS_MEDIO,
            alignment=TA_LEFT,
        ),
        "valor": ParagraphStyle(
            "valor", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=10.5, leading=13, textColor=GRIS_TEXTO,
            alignment=TA_LEFT,
        ),
        "seccion": ParagraphStyle(
            "seccion", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=8.5, leading=10, textColor=AZUL_MARINO,
        ),
        "normal": ParagraphStyle(
            "normal", parent=es["Normal"], fontName=FUENTE,
            fontSize=9, leading=12, textColor=GRIS_TEXTO,
        ),
        "celda": ParagraphStyle(
            "celda", parent=es["Normal"], fontName=FUENTE,
            fontSize=9.5, leading=11, textColor=GRIS_TEXTO,
        ),
        "celda_r": ParagraphStyle(
            "celda_r", parent=es["Normal"], fontName=FUENTE,
            fontSize=9.5, leading=11, textColor=GRIS_TEXTO,
            alignment=TA_RIGHT,
        ),
        "celda_enc": ParagraphStyle(
            "celda_enc", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=8.5, leading=10, textColor=colors.white,
            alignment=TA_CENTER,
        ),
        "celda_enc_l": ParagraphStyle(
            "celda_enc_l", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=8.5, leading=10, textColor=colors.white,
            alignment=TA_LEFT,
        ),
        "pnt": ParagraphStyle(
            "pnt", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=11, leading=13, textColor=colors.white,
            alignment=TA_CENTER,
        ),
        "anulado": ParagraphStyle(
            "anulado", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=10.5, leading=13, textColor=ROJO_ANULADO,
        ),
        "firma": ParagraphStyle(
            "firma", parent=es["Normal"], fontName=FUENTE,
            fontSize=8.5, leading=11, textColor=GRIS_TEXTO,
            alignment=TA_CENTER,
        ),
        "kardex_k": ParagraphStyle(
            "kardex_k", parent=es["Normal"], fontName=FUENTE,
            fontSize=9, leading=11, textColor=GRIS_TEXTO,
            alignment=TA_LEFT,
        ),
        "kardex_v": ParagraphStyle(
            "kardex_v", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=9.5, leading=11, textColor=GRIS_TEXTO,
            alignment=TA_RIGHT,
        ),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Componentes visuales (PDF)
# ─────────────────────────────────────────────────────────────────────────────
def _color_estado(estado: str) -> colors.Color:
    mapa = {
        "COMPLETADO": VERDE_OK,
        "CERRADO": AZUL_PRIMARIO,
        "PENDIENTE": AMBAR_PENDIENTE,
        "EN_PROCESO": MORADO_PROCESO,
        "ANULADO": ROJO_ANULADO,
    }
    return mapa.get((estado or "").upper(), colors.HexColor("#4A5568"))


def _badge_estado(estado: str, st: dict[str, ParagraphStyle]) -> Table:
    color = _color_estado(estado)
    p = Paragraph(
        f'<font color="white"><b>{estado}</b></font>',
        ParagraphStyle("badge", parent=st["normal"], fontSize=8.5,
                       alignment=TA_CENTER, leading=10),
    )
    t = Table([[p]], colWidths=[34 * mm], rowHeights=[7 * mm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), color),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
    ]))
    return t


def _tarjeta(label: str, valor: str, st: dict[str, ParagraphStyle]) -> Table:
    contenido = [
        [Paragraph(label.upper(), st["label"])],
        [Paragraph(valor, st["valor"])],
    ]
    t = Table(contenido, colWidths=[41 * mm], rowHeights=[6 * mm, 12 * mm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), GRIS_SUAVE),
        ("BOX", (0, 0), (-1, -1), 0.6, GRIS_BORDE),
        ("LINEABOVE", (0, 0), (-1, 0), 2, AZUL_PRIMARIO),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, 0), 4),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 0),
        ("TOPPADDING", (0, 1), (-1, 1), 0),
        ("BOTTOMPADDING", (0, 1), (-1, 1), 4),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]))
    return t


# ─────────────────────────────────────────────────────────────────────────────
# Construcción del PDF
# ─────────────────────────────────────────────────────────────────────────────
def _build_pdf(p: BoletoPesaje, empresa: Empresa | None = None) -> io.BytesIO:
    d = _dato(p)
    cab = _empresa_cabecera(empresa)
    anulado = (d["estado"] or "").upper() == "ANULADO"
    buf = io.BytesIO()

    _registrar_ttf()
    st = _estilos()

    def _on_page(cnv: canvas.Canvas, doc: SimpleDocTemplate) -> None:
        cnv.saveState()
        if anulado:
            cnv.setFillColor(ROJO_ANULADO)
            cnv.setFillAlpha(0.15)
            cnv.setFont(FUENTE_BOLD, 80)
            cnv.translate(letter[0] / 2, letter[1] / 2)
            cnv.rotate(45)
            cnv.drawCentredString(0, 0, "ANULADO")
            cnv.setFillAlpha(1)
        cnv.setFont(FUENTE, 7)
        cnv.setFillColor(GRIS_MEDIO)
        cnv.drawString(15 * mm, 10 * mm,
                       f"Impreso: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}")
        cnv.drawRightString(letter[0] - 15 * mm, 10 * mm,
                            f"Boleto N° {d['numero']}")
        cnv.setStrokeColor(GRIS_BORDE)
        cnv.setLineWidth(0.4)
        cnv.line(15 * mm, 14 * mm, letter[0] - 15 * mm, 14 * mm)
        cnv.restoreState()

    doc = SimpleDocTemplate(
        buf,
        pagesize=letter,
        rightMargin=15 * mm,
        leftMargin=15 * mm,
        topMargin=14 * mm,
        bottomMargin=18 * mm,
        title=f"Boleto de Pesaje {d['numero']}",
        author=cab["nombre"] or "Sistema de Pesaje",
    )

    elementos: list[Any] = []

    # 1. ENCABEZADO INSTITUCIONAL
    izq_lineas: list[Any] = []
    if cab["nombre"]:
        izq_lineas.append(Paragraph(cab["nombre"], st["empresa"]))
    for etiqueta, valor in [
        ("RIF", cab["rif"]),
        ("Dirección", cab["direccion"]),
        ("Teléfono", cab["telefono"]),
        ("Email", cab["email"]),
    ]:
        if valor:
            izq_lineas.append(Paragraph(f"<b>{etiqueta}:</b> {valor}", st["info"]))

    if cab["logo"]:
        try:
            logo_img = Image(cab["logo"], width=22 * mm, height=16 * mm,
                             kind="proportional")
        except Exception:
            logo_img = Paragraph("", st["info"])
    else:
        logo_img = Paragraph("", st["info"])

    bloque_izq = Table([[logo_img, izq_lineas]], colWidths=[24 * mm, 88 * mm])
    bloque_izq.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (0, 0), 0),
        ("RIGHTPADDING", (0, 0), (0, 0), 4),
        ("LEFTPADDING", (1, 0), (1, 0), 0),
        ("RIGHTPADDING", (1, 0), (1, 0), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))

    bloque_der = [
        Paragraph("BOLETO DE PESAJE DE BALANZA", st["titulo"]),
        Spacer(1, 1 * mm),
        Paragraph(f"N° {d['numero']}", st["ticket_num"]),
        Spacer(1, 2.5 * mm),
        _badge_estado(d["estado"], st),
    ]
    der_wrapper = Table([[bloque_der]], colWidths=[68 * mm])
    der_wrapper.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("ALIGN", (0, 0), (-1, -1), "RIGHT"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))

    cabecera = Table([[bloque_izq, der_wrapper]], colWidths=[112 * mm, 68 * mm])
    cabecera.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ("LINEBELOW", (0, 0), (-1, -1), 1.2, AZUL_MARINO),
    ]))
    elementos.append(cabecera)
    elementos.append(Spacer(1, ESPACIO))

    # 2. TARJETAS MÉTRICAS
    tarjetas = Table(
        [[
            _tarjeta("Fecha y Hora", d["fecha_hora"], st), "",
            _tarjeta("Placa / Vehículo", d["camion"], st), "",
            _tarjeta("Remolque / Chuto", d["remolque"], st), "",
            _tarjeta("Doc. Control / Guía", d["documento"], st),
        ]],
        colWidths=[41 * mm, 3 * mm, 41 * mm, 3 * mm, 41 * mm, 3 * mm, 41 * mm],
        rowHeights=[18 * mm],
    )
    tarjetas.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    elementos.append(tarjetas)
    elementos.append(Spacer(1, ESPACIO))

    # 2.1 DATOS DE LA OPERACIÓN (Producto, Conductor, Transporte, Cliente, Almacén)
    info_izq = [
        [Paragraph("DATOS DE OPERACIÓN", st["seccion"]), ""],
        [Paragraph("Producto", st["kardex_k"]), Paragraph(d["producto"], st["kardex_v"])],
        [Paragraph("Conductor", st["kardex_k"]), Paragraph(d["conductor"], st["kardex_v"])],
        [Paragraph("Transporte", st["kardex_k"]), Paragraph(d["transporte"], st["kardex_v"])],
    ]
    tabla_info_izq = Table(info_izq, colWidths=[35 * mm, 52 * mm])
    tabla_info_izq.setStyle(TableStyle([
        ("SPAN", (0, 0), (1, 0)),
        ("BACKGROUND", (0, 0), (-1, 0), GRIS_ENCABEZADO),
        ("BOX", (0, 0), (-1, -1), 0.6, GRIS_BORDE),
        ("INNERGRID", (0, 1), (-1, -1), 0.3, GRIS_BORDE),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
    ]))

    info_der = [
        [Paragraph("CLIENTE / ALMACÉN", st["seccion"]), ""],
        [Paragraph("Razón Social", st["kardex_k"]), Paragraph(d["razon_social"], st["kardex_v"])],
        [Paragraph("Almacén", st["kardex_k"]), Paragraph(d["almacen"], st["kardex_v"])],
        [Paragraph("Boleto N°", st["kardex_k"]), Paragraph(d["numero"], st["kardex_v"])],
    ]
    tabla_info_der = Table(info_der, colWidths=[35 * mm, 52 * mm])
    tabla_info_der.setStyle(TableStyle([
        ("SPAN", (0, 0), (1, 0)),
        ("BACKGROUND", (0, 0), (-1, 0), GRIS_ENCABEZADO),
        ("BOX", (0, 0), (-1, -1), 0.6, GRIS_BORDE),
        ("INNERGRID", (0, 1), (-1, -1), 0.3, GRIS_BORDE),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
    ]))

    bloque_operativo = Table([[tabla_info_izq, "", tabla_info_der]],
                             colWidths=[87 * mm, 6 * mm, 87 * mm])
    bloque_operativo.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    elementos.append(bloque_operativo)
    elementos.append(Spacer(1, ESPACIO))

    # 3. TABLA DE PESAJES + PNT
    tiene_remolque = bool(d["pe_remolque"]) or bool(d["ps_remolque"])

    if tiene_remolque:
        encabezados = ["CONCEPTO", "VEHÍCULO", "REMOLQUE", "TOTAL (kg)"]
        fila_entrada = [
            Paragraph("Peso Entrada / Bruto", st["celda"]),
            Paragraph(_fmt_peso_html(d["pe_vehiculo"]), st["celda_r"]),
            Paragraph(_fmt_peso_html(d["pe_remolque"]), st["celda_r"]),
            Paragraph(_fmt_peso_html(d["total_entrada"]), st["celda_r"]),
        ]
        fila_salida = [
            Paragraph("Peso Salida / Tara", st["celda"]),
            Paragraph(_fmt_peso_html(d["ps_vehiculo"]), st["celda_r"]),
            Paragraph(_fmt_peso_html(d["ps_remolque"]), st["celda_r"]),
            Paragraph(_fmt_peso_html(d["total_salida"]), st["celda_r"]),
        ]
        col_widths = [66 * mm, 38 * mm, 38 * mm, 38 * mm]
    else:
        encabezados = ["CONCEPTO", "VEHÍCULO", "TOTAL (kg)"]
        fila_entrada = [
            Paragraph("Peso Entrada / Bruto", st["celda"]),
            Paragraph(_fmt_peso_html(d["pe_vehiculo"]), st["celda_r"]),
            Paragraph(_fmt_peso_html(d["total_entrada"]), st["celda_r"]),
        ]
        fila_salida = [
            Paragraph("Peso Salida / Tara", st["celda"]),
            Paragraph(_fmt_peso_html(d["ps_vehiculo"]), st["celda_r"]),
            Paragraph(_fmt_peso_html(d["total_salida"]), st["celda_r"]),
        ]
        col_widths = [90 * mm, 45 * mm, 45 * mm]

    fila_enc = [
        Paragraph(encabezados[0], st["celda_enc_l"]),
        *[Paragraph(h, st["celda_enc"]) for h in encabezados[1:]],
    ]

    tabla_pesos = Table(
        [fila_enc, fila_entrada, fila_salida],
        colWidths=col_widths,
        rowHeights=[8 * mm, 9 * mm, 9 * mm],
    )
    tabla_pesos.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), AZUL_MARINO),
        ("GRID", (0, 0), (-1, -1), 0.4, GRIS_BORDE),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("LEFTPADDING", (0, 1), (0, -1), 10),
        ("RIGHTPADDING", (0, 1), (0, -1), 6),
        ("RIGHTPADDING", (1, 1), (-1, -1), 10),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, GRIS_SUAVE]),
    ]))
    elementos.append(tabla_pesos)

    pnt_cell = Paragraph(
        f'PESO NETO TOTAL (PNT): &nbsp;<font size="12">{_fmt_peso_html(d["neto"])} kg</font>',
        st["pnt"],
    )
    pnt = Table([[pnt_cell]], colWidths=[ANCHO_UTIL], rowHeights=[11 * mm])
    pnt.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), AZUL_PRIMARIO),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("BOX", (0, 0), (-1, -1), 0.6, AZUL_MARINO),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    elementos.append(pnt)
    elementos.append(Spacer(1, ESPACIO))

    # 4. BLOQUE COMPARATIVO
    desv = d["desviacion"]
    desv_txt = f"{_fmt(desv)} %" if desv is not None else "—"
    dif_txt = _fmt_peso_html(d["diferencia"]) + " kg" if d["diferencia"] is not None else "—"

    izq_filas = [
        [Paragraph("ANÁLISIS DE DESVIACIÓN", st["seccion"]), ""],
        [Paragraph("Peso Neto Declarado (PND)", st["kardex_k"]),
         Paragraph(f"{_fmt_peso_html(d['declarado'])} kg", st["kardex_v"])],
        [Paragraph("Diferencia (PNT − PND)", st["kardex_k"]),
         Paragraph(dif_txt, st["kardex_v"])],
        [Paragraph("% Desviación / Tolerancia", st["kardex_k"]),
         Paragraph(desv_txt, st["kardex_v"])],
    ]
    izq_tabla = Table(izq_filas, colWidths=[46 * mm, 41 * mm])
    izq_tabla.setStyle(TableStyle([
        ("SPAN", (0, 0), (1, 0)),
        ("BACKGROUND", (0, 0), (-1, 0), GRIS_ENCABEZADO),
        ("BOX", (0, 0), (-1, -1), 0.6, GRIS_BORDE),
        ("INNERGRID", (0, 1), (-1, -1), 0.3, GRIS_BORDE),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
    ]))

    der_filas: list[list[Any]] = [
        [Paragraph("KARDEX / DATOS VOLUMÉTRICOS", st["seccion"]), ""],
    ]
    if d["densidad"] is not None:
        der_filas.append([
            Paragraph("Densidad", st["kardex_k"]),
            Paragraph(str(d["densidad"]).replace(".", ","), st["kardex_v"]),
        ])
    if d["unidades"] is not None:
        der_filas.append([
            Paragraph("Unidades transportadas", st["kardex_k"]),
            Paragraph(_fmt(d["unidades"], 0), st["kardex_v"]),
        ])
    if d["litros"] is not None:
        der_filas.append([
            Paragraph("Volumen (Litros)", st["kardex_k"]),
            Paragraph(_fmt_peso_html(d["litros"]) + " L", st["kardex_v"]),
        ])
    while len(der_filas) < 4:
        der_filas.append([Paragraph("", st["kardex_k"]),
                          Paragraph("", st["kardex_v"])])

    der_tabla = Table(der_filas, colWidths=[46 * mm, 41 * mm])
    der_tabla.setStyle(TableStyle([
        ("SPAN", (0, 0), (1, 0)),
        ("BACKGROUND", (0, 0), (-1, 0), GRIS_ENCABEZADO),
        ("BOX", (0, 0), (-1, -1), 0.6, GRIS_BORDE),
        ("INNERGRID", (0, 1), (-1, -1), 0.3, GRIS_BORDE),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
    ]))

    comparativo = Table([[izq_tabla, "", der_tabla]],
                        colWidths=[87 * mm, 6 * mm, 87 * mm])
    comparativo.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    elementos.append(comparativo)
    elementos.append(Spacer(1, ESPACIO))

    # 5. OBSERVACIONES
    obs_txt = d["observaciones"] or "Sin observaciones."
    obs_parrafo = Paragraph(obs_txt.replace("\n", "<br/>"), st["normal"])

    obs_tabla = Table(
        [
            [Paragraph("OBSERVACIONES", st["seccion"])],
            [obs_parrafo],
        ],
        colWidths=[ANCHO_UTIL],
    )
    obs_tabla.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), GRIS_ENCABEZADO),
        ("BOX", (0, 0), (-1, -1), 0.6, GRIS_BORDE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, 0), 5),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 5),
        ("TOPPADDING", (0, 1), (-1, 1), 6),
        ("BOTTOMPADDING", (0, 1), (-1, 1), 6),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
    ]))
    elementos.append(obs_tabla)

    if anulado:
        elementos.append(Spacer(1, ESPACIO))
        motivo = d["motivo_anulacion"] or "No especificado"
        aviso = Table(
            [[Paragraph(
                f"<b>DOCUMENTO ANULADO</b> — Motivo: {motivo}",
                st["anulado"],
            )]],
            colWidths=[ANCHO_UTIL],
        )
        aviso.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#FFF5F5")),
            ("BOX", (0, 0), (-1, -1), 1, ROJO_ANULADO),
            ("TOPPADDING", (0, 0), (-1, -1), 8),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ]))
        elementos.append(aviso)

    # 6. FIRMAS
    elementos.append(Spacer(1, 12 * mm))
    firma_izq = Paragraph(
        "___________________________________________<br/>"
        "<b>Operador de Balanza</b><br/>"
        "<font size=7 color='#718096'>Nombre y Firma</font>",
        st["firma"],
    )
    firma_der = Paragraph(
        "___________________________________________<br/>"
        "<b>Conductor / Transportista</b><br/>"
        "<font size=7 color='#718096'>Nombre y Firma</font>",
        st["firma"],
    )
    firmas = Table([[firma_izq, firma_der]], colWidths=[90 * mm, 90 * mm])
    firmas.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    elementos.append(KeepTogether(firmas))

    doc.build(elementos, onFirstPage=_on_page, onLaterPages=_on_page)
    return buf


# ─────────────────────────────────────────────────────────────────────────────
# TXT — Ticket sencillo
# ─────────────────────────────────────────────────────────────────────────────
ANCHO_TXT = 100  # caracteres por línea


def _linea(caracter: str = "-") -> str:
    return caracter * ANCHO_TXT


def _centrar(txt: str, ancho: int = ANCHO_TXT) -> str:
    return txt.center(ancho)


def _campo(etiqueta: str, valor: str, ancho_etq: int = 18) -> str:
    """Devuelve 'Etiqueta:        valor' alineado a la izquierda."""
    return f"{etiqueta + ':':<{ancho_etq}} {valor}"


def _campo_derecha(etiqueta: str, valor: str,
                   ancho_total: int = ANCHO_TXT) -> str:
    """Etiqueta a la izquierda, valor a la derecha."""
    izq = etiqueta + ":"
    return f"{izq}{valor:>{ancho_total - len(izq)}}"


def _build_txt(p: BoletoPesaje, empresa: Empresa | None = None) -> io.BytesIO:
    """Genera el ticket sencillo en texto plano (UTF-8)."""
    d = _dato(p)
    cab = _empresa_cabecera(empresa)
    anulado = (d["estado"] or "").upper() == "ANULADO"

    # ── Lectura: entrada y salida ────────────────────────────────────────────
    # Se asume que existen los atributos de balanza; si no, se dejan vacíos.
    bal_entrada = getattr(p, "balanza_entrada", None) or "BALANZA PRINCIPAL"
    bal_salida = getattr(p, "balanza_salida", None) or "BALANZA PRINCIPAL"
    hora_entrada = getattr(p, "fecha_hora_entrada", None)
    hora_salida = getattr(p, "fecha_hora_salida", None)

    # ── Datos adicionales ────────────────────────────────────────────────────
    guia_sunagro = getattr(p, "guia_sunagro", None) or "—"
    medida = getattr(p, "medida", None) or "Litros"
    resultado = getattr(p, "resultado", None)
    resultado_txt = _fmt(resultado) if resultado is not None else "—"

    # ── Encabezado ───────────────────────────────────────────────────────────
    lineas: list[str] = []
    lineas.append(_linea("="))
    if cab["nombre"]:
        lineas.append(_centrar(cab["nombre"].upper()))
    if cab["rif"]:
        lineas.append(_centrar(f"RIF: {cab['rif']}"))
    if cab["direccion"]:
        lineas.append(_centrar(cab["direccion"]))
    if cab["telefono"] or cab["email"]:
        contacto = " | ".join(filter(None, [cab["telefono"], cab["email"]]))
        lineas.append(_centrar(contacto))
    lineas.append(_linea("="))
    lineas.append(_centrar("BOLETO DE PESAJE DE BALANZA"))
    lineas.append(_linea("="))
    lineas.append("")

    # ── DATOS ────────────────────────────────────────────────────────────────
    lineas.append("-- DATOS --")
    lineas.append(_campo("Serie - Boleto", d["numero"]))
    lineas.append(_campo("Fecha/Hora", d["fecha_hora"]))
    lineas.append(_campo("Camión", d["camion"]))
    lineas.append(_campo("Remolque", "Sí" if d["remolque"] not in ("—", "No aplica") else "No"))
    lineas.append(_campo("Transporte", getattr(p, "transporte", "—") or "—"))
    lineas.append(_campo("Conductor", getattr(p, "conductor", "—") or "—"))
    lineas.append(_campo("Producto", getattr(p, "producto", "—") or "—"))
    lineas.append(_campo("Almacén", getattr(p, "almacen", "—") or "—"))
    lineas.append(_campo("Selección", getattr(p, "seleccion", "—") or "—"))
    lineas.append(_campo("Razón Social", getattr(p, "razon_social", "—") or "—"))
    lineas.append("")

    # ── LECTURA ──────────────────────────────────────────────────────────────
    lineas.append("-- LECTURA --")
    # Encabezado de columnas
    col_bal = 22
    col_fecha = 18
    col_num = 15
    encabezado = (
        f"{'':<{col_bal}}"
        f"{'Fecha/Hora':>{col_fecha}}"
        f"{'Peso Camión':>{col_num}}"
        f"{'Peso Remolque':>{col_num}}"
        f"{'Peso Total':>{col_num}}"
    )
    lineas.append(encabezado)

    def _fila_lectura(etiqueta: str, balanza: str,
                      fecha: datetime | None,
                      pc: Decimal | None, pr: Decimal | None,
                      pt: Decimal | None) -> str:
        bal_txt = f"{etiqueta}: {balanza}"
        return (
            f"{bal_txt:<{col_bal}}"
            f"{_fmt_dt(fecha):>{col_fecha}}"
            f"{_fmt(pc):>{col_num}}"
            f"{_fmt(pr):>{col_num}}"
            f"{_fmt(pt):>{col_num}}"
        )

    lineas.append(_fila_lectura(
        "Balanza Entrada", bal_entrada, hora_entrada,
        d["pe_vehiculo"], d["pe_remolque"], d["total_entrada"],
    ))
    lineas.append(_fila_lectura(
        "Balanza Salida", bal_salida, hora_salida,
        d["ps_vehiculo"], d["ps_remolque"], d["total_salida"],
    ))

    # Separador + Peso Neto
    ancho_num = col_num * 3
    lineas.append(
        f"{'':<{col_bal + col_fecha}}"
        f"{'-' * ancho_num}"
    )
    lineas.append(
        f"{'Peso Neto:':>{col_bal + col_fecha}}"
        f"{_fmt(d['pe_vehiculo'] - d['ps_vehiculo']):>{col_num}}"
        f"{_fmt(d['pe_remolque'] - d['ps_remolque']):>{col_num}}"
        f"{_fmt(d['neto']):>{col_num}}"
    )
    lineas.append(
        f"{'Peso Declarado / Diferencia:':>{col_bal + col_fecha}}"
        f"{_fmt(d['declarado']):>{col_num}}"
        f"{_fmt(d['diferencia']):>{col_num}}"
    )
    lineas.append("")

    # ── DATOS ADICIONALES ────────────────────────────────────────────────────
    lineas.append("-- DATOS ADICIONALES --")
    lineas.append(_campo("Documento", d["documento"]))
    lineas.append(_campo("Guía SUNAGRO", str(guia_sunagro)))
    linea_med = (
        f"{'Medida:':<12}{medida:<14}"
        f"{'Unidades:':<12}{_fmt(d['unidades'], 0) if d['unidades'] is not None else '—':<16}"
        f"{'Densidad:':<12}{str(d['densidad']).replace('.', ',') if d['densidad'] is not None else '—':<16}"
        f"{'Resultado:':<12}{resultado_txt}"
    )
    lineas.append(linea_med)
    lineas.append("")

    # ── OBSERVACIONES ────────────────────────────────────────────────────────
    lineas.append("-- OBSERVACIONES --")
    obs = d["observaciones"] or ""
    if obs:
        for linea in obs.splitlines():
            # Partir en trozos de ANCHO_TXT
            for i in range(0, len(linea), ANCHO_TXT):
                lineas.append(linea[i:i + ANCHO_TXT])
    else:
        lineas.append("Sin observaciones.")
    lineas.append("")

    # ── ESTADO ESPECIAL ──────────────────────────────────────────────────────
    if anulado:
        lineas.append(_linea("="))
        motivo = d["motivo_anulacion"] or "No especificado"
        lineas.append(_centrar("*** DOCUMENTO ANULADO ***"))
        lineas.append(_centrar(f"Motivo: {motivo}"))
        lineas.append(_linea("="))
        lineas.append("")

    # ── PIE ──────────────────────────────────────────────────────────────────
    lineas.append(_linea("-"))
    lineas.append(f"Estado: {d['estado']}")
    lineas.append(f"Impreso: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}")
    lineas.append(_linea("-"))

    contenido = "\n".join(lineas)
    return io.BytesIO(contenido.encode("utf-8"))


# ─────────────────────────────────────────────────────────────────────────────
# API pública
# ─────────────────────────────────────────────────────────────────────────────
def _platypus_pdf(p: BoletoPesaje, empresa: Empresa | None = None) -> io.BytesIO:
    """Alias retrocompatible."""
    return _build_pdf(p, empresa=empresa)


def generar_ticket_pdf(
    p: BoletoPesaje, empresa: Empresa | None = None
) -> StreamingResponse:
    """Devuelve la respuesta PDF del ticket con marca de agua si está ANULADO."""
    buf = _build_pdf(p, empresa=empresa)
    buf.seek(0)
    nombre = f"ticket_{p.numero_boleto or p.boleto}.pdf"
    return StreamingResponse(
        buf,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nombre}"'},
    )


def generar_ticket_txt(
    p: BoletoPesaje, empresa: Empresa | None = None
) -> StreamingResponse:
    """Devuelve el ticket sencillo en texto plano (UTF-8)."""
    buf = _build_txt(p, empresa=empresa)
    buf.seek(0)
    nombre = f"ticket_{p.numero_boleto or p.boleto}.txt"
    return StreamingResponse(
        buf,
        media_type="text/plain; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{nombre}"'},
    )