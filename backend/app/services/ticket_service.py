"""Generación del ticket/boleto de pesaje.

FUENTE DE VERDAD DEL LAYOUT: widget ``TicketPreviewDialog`` (Flutter).
  Archivo: frontend/lib/presentation/widgets/ticket_preview_dialog.dart
  Función: _buildSingleTicketBlock() (hoja Carta/A4) / _buildTicketTermico() (rollo)

Cualquier cambio estructural (añadir/quitar campos, cambiar orden) debe
aplicarse PRIMERO en ese widget y LUEGO aquí.

Zonas del boleto de hoja (Carta/A4):
  DATOS → LECTURA DE PESOS (tabla Balanza|Fecha/Hora|Camion|Remolque|Total) →
  PESO NETO / PESO DECLARADO / DIFERENCIA / DESVIACIÓN →
  DATOS ADICIONALES → OBSERVACIONES → Firmas.
En rollo térmico (80mm/58mm) se usa la variante compacta sin columnas.

Formatos:
  - PDF : N tickets por hoja. La escala tipográfica se elige de forma
          adaptativa para que cada ticket quepa EXACTO en su franja
          (alto = (alto_hoja - margen_v*2 - gap*(n-1)) / n) sin cortarse.
  - TXT : misma estructura en texto plano UTF-8, mismo orden.

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
    Frame,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

from app.models import BoletoPesaje, Empresa
from app.services.weighing_service import normalizar_estado

# ─────────────────────────────────────────────────────────────────────────────
# Paleta mínima — solo lo que se usa en el layout simple
# ─────────────────────────────────────────────────────────────────────────────
ROJO_ANULADO = colors.HexColor("#C53030")
GRIS_TEXTO   = colors.HexColor("#2D3748")
GRIS_MEDIO   = colors.HexColor("#718096")

FUENTE      = "DejaVu"
FUENTE_BOLD = "DejaVu-Bold"
_FUENTES_REGISTRADAS = False

# Ancho de línea para TXT (caracteres)
ANCHO_TXT = 100


# ─────────────────────────────────────────────────────────────────────────────
# Formateo de números y fechas
# ─────────────────────────────────────────────────────────────────────────────
def _fmt(v: Decimal | float | int | str | None, decimales: int = 2) -> str:
    """Formatea número con separador de miles latino y coma decimal.

    Ejemplo: 15000.50 → '15.000,50'
    """
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
    fmt_str = f"{{:,.{decimales}f}}"
    return fmt_str.format(num).replace(",", "X").replace(".", ",").replace("X", ".")


def _fmt_dt(dt: datetime | None) -> str:
    """Formato dd/MM/yyyy HH:mm — idéntico a _formatDate() en Flutter."""
    return dt.strftime("%d/%m/%Y %H:%M") if dt else "—"


def _fmt_sig(v: Decimal | float | int | None, decimales: int = 2) -> str:
    """Formatea un número con su signo explícito ('+'), como la diferencia.

    Espejo de _fmtConSigno() en Flutter: +1.234,50 / -1.234,50 / 0,00.
    _fmt ya incluye el signo '-' para los negativos.
    """
    if v is None:
        return ""
    f = _fmt(v, decimales)
    if v > 0:
        return f"+{f}"
    return f


def _fmt_densidad(v: Decimal | float | None) -> str | None:
    """Densidad con hasta 8 decimales sin ceros finales ('0,92'), coma latina."""
    if v is None:
        return None
    s = _fmt(v, decimales=8)
    s = s.rstrip("0").rstrip(",")
    return s or "0"


# ─────────────────────────────────────────────────────────────────────────────
# Extracción de datos del boleto
# FUENTE: TicketPreviewDialog._buildSingleTicketBlock (Flutter)
# Solo se incluyen los campos que aparecen en esa función.
# ─────────────────────────────────────────────────────────────────────────────
def _dato(p: BoletoPesaje) -> dict[str, Any]:
    """Extrae los campos usados por la previsualización Flutter.

    Referencia: TicketPreviewDialog._buildSingleTicketBlock
    NO añadir campos que no estén en ese widget.
    """
    # Remolque: "Sí [— placa]" o "No"  (Flutter: w.remolque ? (w.remolquePlaca ?? ...) : 'No')
    tiene_remolque = bool(getattr(p, "remolque", None))
    if tiene_remolque:
        placa = (
            getattr(p, "placa_remolque", None)
            or getattr(p, "remolque_placa", None)
            or getattr(p, "id_remolque", None)
        )
        remolque_txt = f"Sí — {placa}" if placa else "Sí"
    else:
        remolque_txt = "No"

    p_ent_v  = p.peso_entrada_vehiculo or Decimal("0")
    p_ent_r  = p.peso_entrada_remolque or Decimal("0")
    p_sal_v  = p.peso_salida_vehiculo
    p_sal_r  = p.peso_salida_remolque

    peso_entrada = p_ent_v + p_ent_r
    peso_salida  = (p_sal_v or Decimal("0")) + (p_sal_r or Decimal("0"))
    neto_camion  = p_ent_v - (p_sal_v or Decimal("0"))
    neto_remolq  = p_ent_r - (p_sal_r or Decimal("0"))

    balanza = (
        getattr(p, "balanza_nombre", None)
        or getattr(p, "balanza_desc", None)
        or getattr(p, "id_balanza", None)
        or ""
    )
    seleccion = (getattr(p, "tipo_tercero", None) or "").strip().upper()

    return {
        # ── Datos del boleto (orden exacto del widget Flutter) ───────────────
        "numero":       (
            p.numero_boleto
            or (f"BOL-{str(p.boleto)[:8].upper()}" if getattr(p, "boleto", None) else "Boleto s/n")
        ),
        "fecha_hora":   _fmt_dt(p.fecha_hora_entrada),
        "camion":       (p.id_vehiculo or "Sin Placa"),
        "remolque":     remolque_txt,
        "transporte":   (
            getattr(p, "transporte_nombre", None)
            or getattr(p, "transporte", None)
            or getattr(p, "id_transporte", None)
            or "N/A"
        ),
        "conductor":    (
            getattr(p, "conductor_nombre", None)
            or getattr(p, "conductor", None)
            or getattr(p, "id_conductor", None)
            or "N/A"
        ),
        "producto":     (
            getattr(p, "producto_nombre", None)
            or getattr(p, "producto", None)
            or getattr(p, "id_producto", None)
            or "N/A"
        ),
        "almacen":      (
            getattr(p, "almacen_nombre", None)
            or getattr(p, "almacen", None)
            or getattr(p, "id_almacen", None)
            or "N/A"
        ),
        "seleccion":    seleccion or "N/A",
        "razon_social": (
            getattr(p, "razon_social", None)
            or getattr(p, "tercero_nombre", None)
            or getattr(p, "id_tercero", None)
            or "N/A"
        ),
        # ── Lecturas de peso (tabla: Balanza|Fecha/Hora|Camion|Remolque|Total)
        "hora_entrada":  p.fecha_hora_entrada,
        "hora_salida":   getattr(p, "fecha_hora_salida", None),
        "balanza":       str(balanza).strip(),
        "pe_v":          p_ent_v,
        "pe_r":          p_ent_r,
        "pte":           peso_entrada,
        "ps_v":          p_sal_v,
        "ps_r":          p_sal_r,
        "pts":           peso_salida,
        "neto_camion":   neto_camion,
        "neto_remolque": neto_remolq,
        "neto":          (p.peso_neto or Decimal("0")),
        # ── Declarado / diferencia / desviación ───────────────────────────────
        "declarado":     getattr(p, "peso_neto_declarado", None),
        "diferencia":    getattr(p, "peso_diferencia", None),
        "desviacion":    getattr(p, "porcentaje_desviacion", None),
        # ── Datos adicionales ─────────────────────────────────────────────────
        "documento":     (p.documento or "").strip(),
        "unidades_txt":  (
            _fmt(p.unidades or p.litros) if (p.unidades or p.litros) is not None else None
        ),
        "densidad_txt":  _fmt_densidad(getattr(p, "densidad", None)),
        # ── Metadatos ────────────────────────────────────────────────────────
        "observaciones":    (p.observaciones or "").strip(),
        "estado":           normalizar_estado(p.estado_boleto),
        "motivo_anulacion": p.motivo_anulacion,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Fuentes TTF (PDF)
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
            bold_path = halls[0].replace("DejaVuSans.ttf", "DejaVuSans-Bold.ttf")
            bold = bold_path if os.path.exists(bold_path) else base

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
        # Fallback a fuentes estándar de ReportLab
        pdfmetrics.registerFont(TTFont(FUENTE, "Helvetica"))
        pdfmetrics.registerFont(TTFont(FUENTE_BOLD, "Helvetica-Bold"))

    _FUENTES_REGISTRADAS = True


# ─────────────────────────────────────────────────────────────────────────────
# Cabecera de empresa
# ─────────────────────────────────────────────────────────────────────────────
def _empresa_cabecera(empresa: Empresa | None) -> dict[str, str]:
    """Devuelve nombre y RIF de la empresa para el encabezado del boleto."""
    if empresa is None:
        return {"nombre": "", "rif": ""}
    return {
        "nombre": (empresa.nombre_comercial or empresa.nombre_fiscal or "").strip(),
        "rif":    (empresa.rif_nit or "").strip(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Tamaños de papel (PDF)
# ─────────────────────────────────────────────────────────────────────────────
_TAMANOS: dict[str, tuple[float, float]] = {
    "Letter":     letter,                        # 216 × 279 mm
    "HalfLetter": (letter[0], letter[1] / 2),    # 216 × 139 mm
    "A4":         (210 * mm, 297 * mm),
    "80mm":       (80  * mm, 297 * mm),          # rollo térmico
    "58mm":       (58  * mm, 297 * mm),          # rollo térmico estrecho
}


# ─────────────────────────────────────────────────────────────────────────────
# Estilos de párrafo (PDF)
# FUENTE: TicketPreviewDialog._buildSingleTicketBlock (Flutter)
# ─────────────────────────────────────────────────────────────────────────────
def _estilos_simples(ts: float = 10.5) -> dict[str, ParagraphStyle]:
    """Estilos para el layout 2 columnas idéntico al widget Flutter.

    ts = tamaño base de texto; se escala según boletos_por_hoja:
      1 boleto → 10.5 pt  |  2 → 9.5 pt  |  3 → 9.0 pt  |  4 → 8.5 pt
    """
    es = getSampleStyleSheet()
    return {
        # Nombre empresa — centrado, negrita, ligeramente más grande
        "empresa_c": ParagraphStyle(
            "empresa_c", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts + 2, leading=ts + 3.5,
            alignment=TA_CENTER, textColor=colors.black,
        ),
        # RIF — centrado, gris, pequeño
        "rif_c": ParagraphStyle(
            "rif_c", parent=es["Normal"],
            fontName=FUENTE, fontSize=ts - 1, leading=ts + 1,
            alignment=TA_CENTER, textColor=GRIS_TEXTO,
        ),
        # Título "BOLETO DE PESAJE DE BALANSOFT"
        "titulo_c": ParagraphStyle(
            "titulo_c", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts + 1, leading=ts + 2.5,
            alignment=TA_CENTER, textColor=colors.black,
        ),
        # Encabezados de sección ("LECTURA DE PESOS")
        "seccion_c": ParagraphStyle(
            "seccion_c", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts - 0.5, leading=ts + 1,
            alignment=TA_CENTER, textColor=colors.black,
        ),
        # Etiqueta izquierda — negrita
        "label_l": ParagraphStyle(
            "label_l", parent=es["Normal"],
            fontName=FUENTE, fontSize=ts - 0.5, leading=ts + 1.5,  # <-- FUENTE en lugar de FUENTE_BOLD
            alignment=TA_LEFT, textColor=colors.black,
        ),
        # Valor derecha — normal, gris
        "valor_r": ParagraphStyle(
            "valor_r", parent=es["Normal"],
            fontName=FUENTE, fontSize=ts - 0.5, leading=ts + 1.5,
            alignment=TA_RIGHT, textColor=GRIS_TEXTO,
        ),
        # Valor derecha — negrita (filas resaltadas: Boleto, Peso Neto)
        "valor_bold_r": ParagraphStyle(
            "valor_bold_r", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts - 0.5, leading=ts + 1.5,
            alignment=TA_RIGHT, textColor=colors.black,
        ),
        # Cabecera de la tabla de lecturas — negrita, centrado
        "tab_hdr": ParagraphStyle(
            "tab_hdr", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts - 0.5, leading=ts + 0.5,
            alignment=TA_CENTER, textColor=colors.black,
        ),
        # Celda numérica de la tabla de lecturas — derecha
        "tab_val": ParagraphStyle(
            "tab_val", parent=es["Normal"],
            fontName=FUENTE, fontSize=ts - 0.5, leading=ts + 0.5,
            alignment=TA_RIGHT, textColor=GRIS_TEXTO,
        ),
        # Celda numérica resaltada (PESO NETO / DECLARADO / DIFERENCIA)
        "tab_val_bold": ParagraphStyle(
            "tab_val_bold", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts - 0.5, leading=ts + 0.5,
            alignment=TA_RIGHT, textColor=colors.black,
        ),
        # Observaciones — cursiva, gris, pequeño
        "obs": ParagraphStyle(
            "obs", parent=es["Normal"],
            fontName=FUENTE, fontSize=ts - 1.5, leading=ts,
            alignment=TA_LEFT, textColor=GRIS_MEDIO,
        ),
        # Firmas — centrado
        "firma_c": ParagraphStyle(
            "firma_c", parent=es["Normal"],
            fontName=FUENTE, fontSize=ts - 2, leading=ts + 1,
            alignment=TA_CENTER, textColor=GRIS_TEXTO,
        ),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Render de UN boleto (PDF flowables)
# FUENTE: TicketPreviewDialog._buildSingleTicketBlock (Flutter)
# ─────────────────────────────────────────────────────────────────────────────
def _bloque_anulado(
    d: dict[str, Any],
    st: dict[str, ParagraphStyle],
    ancho_util: float,
) -> Table:
    """Recuadro rojo 'DOCUMENTO ANULADO' + motivo (espejo del bloque TXT)."""
    motivo = d["motivo_anulacion"] or "No especificado"
    texto = (
        f'<font color="#C53030"><b>DOCUMENTO ANULADO</b></font><br/>'
        f'<font size="8">Motivo: {motivo}</font>'
    )
    t = Table([[Paragraph(texto, st["obs"])]], colWidths=[ancho_util])
    t.setStyle(TableStyle([
        ("BOX", (0, 0), (-1, -1), 1, ROJO_ANULADO),
        ("TOPPADDING",    (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("LEFTPADDING",   (0, 0), (-1, -1), 5),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 5),
        ("VALIGN",        (0, 0), (-1, -1), "TOP"),
    ]))
    return t


def _build_boleto_simple(
    d: dict[str, Any],
    cab: dict[str, str],
    st: dict[str, ParagraphStyle],
    ancho_util: float,
    mostrar_encabezado: bool = True,
    mostrar_detalles: bool = True,
    compact: bool = False,
) -> list[Any]:
    """Construye la lista de flowables de UN boleto.

    Hoja (Carta/A4, ``compact=False``) — espejo de
    TicketPreviewDialog._buildSingleTicketBlock (Flutter):
      Encabezado empresa → Título → DATOS (10 filas) →
      LECTURA DE PESOS (tabla Balanza|Fecha/Hora|Camion|Remolque|Total) →
      PESO NETO / PESO DECLARADO / DIFERENCIA / DESVIACIÓN →
      DATOS ADICIONALES → OBSERVACIONES → Firmas.

    Rollo térmico (``compact=True``) — espejo de _buildTicketTermico (Flutter):
      layout antiguo de 2 columnas sin desglose por camión/remolque.

    IMPORTANTE: Si se modifica el widget en Flutter, actualizar esta función.
    """
    col_l = ancho_util * 0.38   # etiqueta  38 %
    col_r = ancho_util * 0.62   # valor     62 %

    # ── Helpers ──────────────────────────────────────────────────────────────
    def _hr_negro(grosor: float = 1.0) -> Table:
        """Línea horizontal negra (Divider color: Colors.black en Flutter)."""
        t = Table([[""]], colWidths=[ancho_util], rowHeights=[0.5])
        t.setStyle(TableStyle([
            ("LINEBELOW", (0, 0), (-1, -1), grosor, colors.black),
            ("TOPPADDING",    (0, 0), (-1, -1), 0),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
        ]))
        return t

    def _hr_gris() -> Table:
        """Línea horizontal gris (Divider color: Colors.black45 en Flutter)."""
        t = Table([[""]], colWidths=[ancho_util], rowHeights=[0.5])
        t.setStyle(TableStyle([
            ("LINEBELOW", (0, 0), (-1, -1), 0.5, colors.HexColor("#999999")),
            ("TOPPADDING",    (0, 0), (-1, -1), 0),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
        ]))
        return t

    def _fila(etiqueta: str, valor: str, bold: bool = False) -> Table:
        """Una fila label | valor (padding vertical ~1.2 pt, igual que Flutter)."""
        st_v = st["valor_bold_r"] if bold else st["valor_r"]
        t = Table(
            [[Paragraph(etiqueta, st["label_l"]), Paragraph(valor, st_v)]],
            colWidths=[col_l, col_r],
        )
        t.setStyle(TableStyle([
            ("VALIGN",        (0, 0), (-1, -1), "TOP"),
            ("TOPPADDING",    (0, 0), (-1, -1), 1),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
            ("LEFTPADDING",   (0, 0), (-1, -1), 0),
            ("RIGHTPADDING",  (0, 0), (-1, -1), 0),
        ]))
        return t

    # ── 1. Encabezado empresa ─────────────────────────────────────────────────
    if mostrar_encabezado and cab["nombre"]:
        els: list[Any] = [
            Paragraph(cab["nombre"], st["empresa_c"]),
        ]
        if cab["rif"]:
            els.append(Paragraph(f'RIF: {cab["rif"]}', st["rif_c"]))
        els.append(Spacer(1, 1.0 * mm))
        els.append(_hr_negro(1.0))
        els.append(Spacer(1, 1.2 * mm))
    else:
        els = []

    # ── 2. Título ─────────────────────────────────────────────────────────────
    els.append(Paragraph("BOLETO DE PESAJE DE BALANSOFT", st["titulo_c"]))
    els.append(Spacer(1, 0.8 * mm))
    els.append(_hr_gris())
    els.append(Spacer(1, 1.2 * mm))

    # ═══════════════════════ VARIANTE COMPACTA (térmico) ═════════════════════
    if compact:
        els.append(_fila("Serie - Boleto:", d["numero"], bold=True))
        els.append(_fila("Fecha/Hora:",     d["fecha_hora"]))
        els.append(_fila("Camión:",         d["camion"]))
        els.append(_fila("Remolque:",       d["remolque"]))
        els.append(_fila("Transporte:",     d["transporte"]))
        els.append(_fila("Conductor:",      d["conductor"]))
        els.append(_fila("Producto:",       d["producto"]))
        els.append(_fila("Almacén:",        d["almacen"]))
        els.append(_fila("Cliente/Proveedor:", d["razon_social"]))

        els.append(Spacer(1, 1.5 * mm))
        els.append(_hr_negro(1.0))
        els.append(Spacer(1, 0.8 * mm))
        els.append(Paragraph("LECTURA DE PESOS", st["seccion_c"]))
        els.append(Spacer(1, 0.8 * mm))
        els.append(_hr_gris())
        els.append(Spacer(1, 1.2 * mm))

        fecha_e = _fmt_dt(d["hora_entrada"])
        peso_e  = f"{_fmt(d['pte'])} kg"
        els.append(_fila("Entrada:", f"{fecha_e}   {peso_e}"))
        if d["hora_salida"] is not None:
            fecha_s = _fmt_dt(d["hora_salida"])
            peso_s  = f"{_fmt(d['pts'])} kg"
            els.append(_fila("Salida:", f"{fecha_s}   {peso_s}"))

        els.append(Spacer(1, 0.8 * mm))
        els.append(_hr_gris())
        els.append(Spacer(1, 1.0 * mm))
        neto_val = d["neto"] if d["neto"] is not None else Decimal("0")
        neto_abs = abs(neto_val)
        sufijo = " (DESPACHO)" if neto_val < 0 else (" (INGRESO)" if neto_val > 0 else "")
        els.append(_fila("PESO NETO:", f"{_fmt(neto_abs)} kg{sufijo}", bold=True))
        els.append(Spacer(1, 0.8 * mm))
        els.append(_hr_negro(1.0))

        if mostrar_detalles and d["observaciones"]:
            els.append(Spacer(1, 1.0 * mm))
            els.append(Paragraph(f'Obs: {d["observaciones"]}', st["obs"]))

        if (d["estado"] or "").upper() == "ANULADO":
            els.append(Spacer(1, 1.0 * mm))
            els.append(_bloque_anulado(d, st, ancho_util))

        els.append(Spacer(1, 4 * mm))
        firma_izq = Paragraph(
            "_______________________<br/><b>Firma Operador</b>", st["firma_c"],
        )
        firma_der = Paragraph(
            "_______________________<br/><b>Firma Conductor</b>", st["firma_c"],
        )
        firmas = Table(
            [[firma_izq, firma_der]],
            colWidths=[ancho_util / 2, ancho_util / 2],
        )
        firmas.setStyle(TableStyle([
            ("ALIGN",         (0, 0), (-1, -1), "CENTER"),
            ("VALIGN",        (0, 0), (-1, -1), "TOP"),
            ("TOPPADDING",    (0, 0), (-1, -1), 0),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
            ("LEFTPADDING",   (0, 0), (-1, -1), 0),
            ("RIGHTPADDING",  (0, 0), (-1, -1), 0),
        ]))
        els.append(firmas)
        return els

    # ═══════════════════════ VARIANTE HOJA (Carta/A4) ════════════════════════
    # ── 3. DATOS ──────────────────────────────────────────────────────────────
    els.append(_fila("Serie - Boleto:", d["numero"], bold=True))
    els.append(_fila("Fecha/Hora:",     d["fecha_hora"]))
    els.append(_fila("Camión:",         d["camion"]))
    els.append(_fila("Remolque:",       d["remolque"]))
    els.append(_fila("Transporte:",     d["transporte"]))
    els.append(_fila("Conductor:",      d["conductor"]))
    els.append(_fila("Producto:",       d["producto"]))
    els.append(_fila("Almacén:",        d["almacen"]))
    els.append(_fila("Selección:",      d["seleccion"]))
    els.append(_fila("Razón Social:",   d["razon_social"]))

    # ── 4. LECTURA DE PESOS (tabla) ───────────────────────────────────────────
    els.append(Spacer(1, 1.5 * mm))
    els.append(_hr_negro(1.0))
    els.append(Spacer(1, 0.8 * mm))
    els.append(Paragraph("LECTURA DE PESOS", st["seccion_c"]))
    els.append(Spacer(1, 0.8 * mm))
    els.append(_hr_gris())
    els.append(Spacer(1, 1.2 * mm))

    def _celda(texto: str, bold: bool = False, centro: bool = False) -> Paragraph:
        est = st["tab_hdr"] if centro else (st["tab_val_bold"] if bold else st["tab_val"])
        return Paragraph(texto or "", est)

    def _lab_tab(texto: str) -> Paragraph:
        return Paragraph(texto, st["label_l"])

    col_bal = ancho_util * 0.32
    col_feh = ancho_util * 0.26
    col_num = ancho_util * 0.14

    balanza_entrada = f"Balanza Entrada: {d['balanza']}".rstrip()
    rows = [
        [_celda("", centro=True), _celda("Fecha/Hora", centro=True),
         _celda("Peso Camion", centro=True), _celda("Peso Remolque", centro=True),
         _celda("Peso Total", centro=True)],
        [_lab_tab(balanza_entrada), _celda(_fmt_dt(d["hora_entrada"])),
         _celda(_fmt(d["pe_v"])), _celda(_fmt(d["pe_r"])), _celda(_fmt(d["pte"]))],
    ]
    hay_salida = d["hora_salida"] is not None
    if hay_salida:
        rows.append([
            _lab_tab(f"Balanza Salida: {d['balanza']}".rstrip()),
            _celda(_fmt_dt(d["hora_salida"])),
            _celda(_fmt(d["ps_v"] or Decimal("0"))),
            _celda(_fmt(d["ps_r"] or Decimal("0"))),
            _celda(_fmt(d["pts"])),
        ])

    neto_val = d["neto"] if d["neto"] is not None else Decimal("0")
    just = " (DESPACHO)" if neto_val < 0 else (" (INGRESO)" if neto_val > 0 else "")
    rows.append([
        _lab_tab(f"PESO NETO{just}:"),
        _celda(""), _celda(_fmt(d["neto_camion"]), bold=True),
        _celda(_fmt(d["neto_remolque"]), bold=True),
        _celda(_fmt(neto_val), bold=True),
    ])
    idx_neto = len(rows) - 1

    if d["declarado"] is not None:
        rows.append([
            _lab_tab("PESO DECLARADO / DIFERENCIA:"),
            _celda(""), _celda(""),
            _celda(_fmt(d["declarado"]), bold=True),
            _celda(_fmt_sig(d["diferencia"]), bold=True),
        ])
        if d["desviacion"] is not None:
            rows.append([
                _lab_tab("DESVIACIÓN:"),
                _celda(""), _celda(""), _celda(""),
                _celda(f"{_fmt(d['desviacion'])} %", bold=True),
            ])

    tabla = Table(rows, colWidths=[col_bal, col_feh, col_num, col_num, col_num])
    estilo_tabla = [
        ("VALIGN",        (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING",    (0, 0), (-1, -1), 1),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
        ("LEFTPADDING",   (0, 0), (-1, -1), 0),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 0),
        ("LINEBELOW",     (0, 0), (-1, 0), 0.5, colors.HexColor("#999999")),
        ("LINEABOVE",     (0, idx_neto), (-1, idx_neto), 0.5, colors.HexColor("#999999")),
    ]
    tabla.setStyle(TableStyle(estilo_tabla))
    els.append(tabla)
    els.append(Spacer(1, 1.0 * mm))
    els.append(_hr_negro(1.0))

    # ── 5. DATOS ADICIONALES ─────────────────────────────────────────────────
    dats_adic = [
        ("Documento:", d["documento"]) if d["documento"] else None,
        ("Unidades:", d["unidades_txt"]) if d["unidades_txt"] is not None else None,
        ("Densidad:", d["densidad_txt"]) if d["densidad_txt"] is not None else None,
    ]
    if any(x is not None for x in dats_adic):
        els.append(Spacer(1, 1.2 * mm))
        els.append(Paragraph("DATOS ADICIONALES", st["seccion_c"]))
        els.append(Spacer(1, 0.8 * mm))
        els.append(_hr_gris())
        els.append(Spacer(1, 1.0 * mm))
        for par in dats_adic:
            if par is not None:
                els.append(_fila(par[0], par[1]))
        els.append(Spacer(1, 1.0 * mm))
        els.append(_hr_negro(1.0))

    # ── 6. OBSERVACIONES ──────────────────────────────────────────────────────
    if mostrar_detalles and d["observaciones"]:
        els.append(Spacer(1, 1.2 * mm))
        els.append(Paragraph("OBSERVACIONES", st["seccion_c"]))
        els.append(Spacer(1, 0.8 * mm))
        els.append(_hr_gris())
        els.append(Spacer(1, 1.0 * mm))
        els.append(Paragraph(d["observaciones"], st["obs"]))

    # ── 6b. ANULADO (bloque rojo, espejo del TXT) ─────────────────────────────
    if (d["estado"] or "").upper() == "ANULADO":
        els.append(Spacer(1, 1.2 * mm))
        els.append(_bloque_anulado(d, st, ancho_util))

    # ── 7. Firmas ─────────────────────────────────────────────────────────────
    els.append(Spacer(1, 4 * mm))
    firma_izq = Paragraph(
        "________________________<br/><b>Firma Operador</b>", st["firma_c"],
    )
    firma_der = Paragraph(
        "________________________<br/><b>Firma Conductor</b>", st["firma_c"],
    )
    firmas = Table(
        [[firma_izq, firma_der]],
        colWidths=[ancho_util / 2, ancho_util / 2],
    )
    firmas.setStyle(TableStyle([
        ("ALIGN",         (0, 0), (-1, -1), "CENTER"),
        ("VALIGN",        (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING",    (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
        ("LEFTPADDING",   (0, 0), (-1, -1), 0),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 0),
    ]))
    els.append(firmas)

    return els


# ─────────────────────────────────────────────────────────────────────────────
# Construcción del PDF completo
# ─────────────────────────────────────────────────────────────────────────────
def _caben(flowables: list[Any], ancho: float, alto: float) -> bool:
    """¿Cabe toda la lista de flowables en un rectángulo de alto fijo?

    Pide a cada elemento su tamaño real (``wrap``) y va acumulando la altura;
    si en algún punto supera ``alto``, no cabe. Es la medición previa al
    dibujado para elegir la escala tipográfica y garantizar que ningún
    ticket se corte ni desborde la página.
    """
    usado = 0.0
    for f in flowables:
        try:
            _, h = f.wrap(ancho, alto)
        except Exception:
            return False
        if h > alto - usado:
            return False
        usado += h
    return True


def _build_pdf(
    p: BoletoPesaje,
    empresa: Empresa | None = None,
    boletos_por_hoja: int = 1,
    tamano_papel: str = "Letter",
    orientacion: str = "portrait",
    mostrar_encabezado: bool = True,
    mostrar_detalles: bool = True,
) -> io.BytesIO:
    """PDF con N tickets de altura exacta por página usando Frames fijos.

    Cada ticket ocupa exactamente (alto_pagina - mg_v*2 - gap*(n-1)) / n
    puntos de alto y la escala tipográfica se ajusta (adaptativa) para que
    todo el contenido del boleto quepa en esa franja sin cortes.

    Modo de ancho fijo: en hojas de papel normal (Letter/A4...) el boleto se
    imprime SIEMPRE estrecho (140mm) y centrado, sin importar cuántos boletos
    se apilen (1..4 por hoja), para que coincida 1:1 con la previsualización.
    En rollo térmico (80mm/58mm) el ancho es el del propio papel.

    Referencia layout: TicketPreviewDialog (Flutter) → _buildSingleTicketBlock
    (hoja) y _buildTicketTermico (rollo térmico compacto).
    - tamano_papel: Letter | HalfLetter | A4 | 80mm | 58mm
    - orientacion:  portrait | landscape
    - boletos_por_hoja: 1..4 (térmicos forzados a 1)
    """
    d   = _dato(p)
    cab = _empresa_cabecera(empresa)
    anulado = (d["estado"] or "").upper() == "ANULADO"

    _registrar_ttf()

    # ── Tamaño de página ─────────────────────────────────────────────────────
    pagina = _TAMANOS.get(tamano_papel, letter)
    if orientacion == "landscape":
        pagina = (pagina[1], pagina[0])

    ancho_pag = pagina[0]
    alto_pag  = pagina[1]

    # Térmico → siempre 1 ticket por hoja
    n = boletos_por_hoja if tamano_papel not in ("80mm", "58mm") else 1

    # ── Geometría de frames ───────────────────────────────────────────────────
    mg_lat  = 10 * mm    # margen izquierdo / derecho
    mg_top  = 10 * mm    # margen superior
    mg_bot  = 10 * mm    # margen inferior (pie de página)
    gap     = 4  * mm    # separación entre tickets (zona de corte)

    compact = tamano_papel in ("80mm", "58mm")

    # Ancho del boleto: SIEMPRE estrecho y centrado (140mm) en hojas de papel
    # normal (Letter/A4...), sin importar cuántos boletos se apilen (1..4),
    # para que el impreso coincida 1:1 con la previsualización.
    # Térmico (80mm/58mm): el ancho es el del propio rollo (ancho_pag - 2*mg_lat).
    # Se evita el centrado solo si la hoja es tan angosta como el ticket
    # (HalfLetter) para no quedar con márgenes negativos.
    ANCHO_TICKET = 100  # mm, ancho fijo del boleto centrado
    centrado = (
        not compact
        and (ancho_pag - 2 * mg_lat) > ANCHO_TICKET * mm
    )
    ancho_frame = ANCHO_TICKET * mm if centrado else (ancho_pag - 2 * mg_lat)
    margen_frame = (ancho_pag - ancho_frame) / 2 if centrado else mg_lat

    # Altura disponible dividida en N frames iguales — cada ticket ocupa
    # exactamente su franja: (alto_hoja - mg_v*2 - gap*(n-1)) / n
    alto_frame  = (alto_pag - mg_top - mg_bot - gap * (n - 1)) / n

    # ── Escala tipográfica adaptativa ─────────────────────────────────────────
    # Se elige el tamaño más grande de la lista que permite que el boleto
    # COMPLETO quepa en su franja (medido con _caben), garantizando que ningún
    # ticket se corte ni desborde aunque el contenido crezca (obs largas, etc.),
    # sin depender de estimaciones manuales de alto por ticket.
    escala_candidatas = {
        1: [10.5, 10.0, 9.5, 9.0, 8.5, 8.0, 7.5, 7.0, 6.5, 6.0, 5.5],
        2: [9.5,  9.0, 8.5, 8.0, 7.5, 7.0, 6.5, 6.0, 5.5, 5.0],
        3: [8.5,  8.0, 7.5, 7.0, 6.5, 6.0, 5.5, 5.0, 4.5, 4.0],
        4: [8.0,  7.5, 7.0, 6.5, 6.0, 5.5, 5.0, 4.5, 4.0],
    }.get(n, [10.5, 10.0, 9.5, 9.0, 8.5, 8.0, 7.5, 7.0, 6.5, 6.0, 5.5])

    st = None
    for ts in escala_candidatas:
        st_probe = _estilos_simples(ts)
        flowables_probe = _build_boleto_simple(
            d, cab, st_probe, ancho_frame,
            mostrar_encabezado=mostrar_encabezado,
            mostrar_detalles=mostrar_detalles,
            compact=compact,
        )
        if _caben(flowables_probe, ancho_frame, alto_frame):
            st = st_probe
            break
    if st is None:
        # Caso extremo (p. ej. observaciones gigantes): usar la menor escala.
        st = _estilos_simples(escala_candidatas[-1])

    # ── Canvas ───────────────────────────────────────────────────────────────
    buf = io.BytesIO()
    cnv = canvas.Canvas(buf, pagesize=pagina)
    cnv.setTitle(f"Boleto de Pesaje {d['numero']}")
    cnv.setAuthor(cab["nombre"] or "Sistema de Pesaje")

    # Marca de agua ANULADO (45°, semitransparente)
    if anulado:
        cnv.saveState()
        cnv.setFillColor(ROJO_ANULADO)
        cnv.setFillAlpha(0.12)
        cnv.setFont(FUENTE_BOLD, 72)
        cnv.translate(ancho_pag / 2, alto_pag / 2)
        cnv.rotate(45)
        cnv.drawCentredString(0, 0, "ANULADO")
        cnv.restoreState()

    # Pie de página (fecha de impresión + estado + número de boleto)
    cnv.saveState()
    cnv.setFont(FUENTE, 7)
    cnv.setFillColor(GRIS_MEDIO)
    cnv.drawString(
        margen_frame, mg_bot / 2,
        f"Impreso: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}   Estado: {d['estado']}",
    )
    cnv.drawRightString(
        margen_frame + ancho_frame, mg_bot / 2,
        f"Boleto N° {d['numero']}",
    )
    cnv.restoreState()

    # ── Dibujar cada ticket en su Frame ──────────────────────────────────────
    # Los frames se numeran de arriba (i=0) a abajo (i=n-1).
    # y1 es la esquina inferior del frame en coordenadas ReportLab (origen abajo).
    for i in range(n):
        y1_frame = mg_bot + (n - 1 - i) * (alto_frame + gap)

        frame = Frame(
            x1=margen_frame,
            y1=y1_frame,
            width=ancho_frame,
            height=alto_frame,
            leftPadding=0, rightPadding=0,
            topPadding=2,  bottomPadding=2,
            showBoundary=0,  # cambiar a 1 para depuración visual
        )

        flowables = _build_boleto_simple(
            d, cab, st, ancho_frame,
            mostrar_encabezado=mostrar_encabezado,
            mostrar_detalles=mostrar_detalles,
            compact=compact,
        )
        frame.addFromList(flowables, cnv)

        # Línea de corte entre tickets (excepto tras el último)
        if i < n - 1:
            y_corte = y1_frame + alto_frame + gap / 2
            cnv.saveState()
            cnv.setStrokeColor(GRIS_MEDIO)
            cnv.setLineWidth(0.4)
            cnv.setDash(4, 3)
            cnv.line(margen_frame, y_corte, margen_frame + ancho_frame, y_corte)
            cnv.setDash()  # restaurar línea sólida
            cnv.setFont(FUENTE, 8)
            cnv.setFillColor(GRIS_MEDIO)
            cnv.drawString(margen_frame, y_corte + 1 * mm, "✂")
            cnv.restoreState()

    cnv.save()
    return buf


# ─────────────────────────────────────────────────────────────────────────────
# Helpers TXT
# ─────────────────────────────────────────────────────────────────────────────
def _linea(char: str = "-") -> str:
    return char * ANCHO_TXT


def _centrar(texto: str) -> str:
    return texto.center(ANCHO_TXT)


def _campo_txt(etiqueta: str, valor: str) -> str:
    """'Etiqueta:    valor' — valor alineado a la derecha (espejo del PDF)."""
    izq    = f"{etiqueta}:"
    espacio = max(1, ANCHO_TXT - len(izq) - len(valor))
    return f"{izq}{' ' * espacio}{valor}"


def _fila_lectura_txt(label: str, fecha: str, cam: str, rem: str, tot: str) -> str:
    """Fila de la tabla de lecturas — columnas fijas alineadas (espejo del PDF)."""
    return f"{label:<34}{fecha:>16} {cam:>13} {rem:>13} {tot:>13}"


def _fila_neto_txt(label: str, cam: str, rem: str, tot: str) -> str:
    """Fila con solo las tres columnas numéricas (Neto / Declarado / Desviación)."""
    return f"{label:<34}{'':>16} {cam:>13} {rem:>13} {tot:>13}"


# ─────────────────────────────────────────────────────────────────────────────
# Construcción del TXT
# FUENTE: TicketPreviewDialog._buildSingleTicketBlock (Flutter)
# Misma estructura que el PDF — sin columnas de camión/remolque/total.
# ─────────────────────────────────────────────────────────────────────────────
def _build_txt(
    p: BoletoPesaje,
    empresa: Empresa | None = None,
    mostrar_encabezado: bool = True,
    mostrar_detalles: bool = True,
) -> io.BytesIO:
    """Ticket en texto plano con el mismo layout que el PDF (hoja Carta/A4).

    Referencia: TicketPreviewDialog._buildSingleTicketBlock (Flutter).
    IMPORTANTE: Si se modifica ese widget, actualizar esta función.
    """
    d   = _dato(p)
    cab = _empresa_cabecera(empresa)
    anulado = (d["estado"] or "").upper() == "ANULADO"

    lineas: list[str] = []

    # ── 1. Encabezado empresa ─────────────────────────────────────────────────
    lineas.append(_linea("="))
    if mostrar_encabezado and cab["nombre"]:
        lineas.append(_centrar(cab["nombre"].upper()))
        if cab["rif"]:
            lineas.append(_centrar(f"RIF: {cab['rif']}"))
        lineas.append(_linea("="))

    # ── 2. Título ─────────────────────────────────────────────────────────────
    lineas.append(_centrar("BOLETO DE PESAJE DE BALANSOFT"))
    lineas.append(_linea("-"))
    lineas.append("")

    # ── 3. DATOS ──────────────────────────────────────────────────────────────
    lineas.append(_campo_txt("Serie - Boleto", d["numero"]))
    lineas.append(_campo_txt("Fecha/Hora",     d["fecha_hora"]))
    lineas.append(_campo_txt("Camión",         d["camion"]))
    lineas.append(_campo_txt("Remolque",       d["remolque"]))
    lineas.append(_campo_txt("Transporte",     d["transporte"]))
    lineas.append(_campo_txt("Conductor",      d["conductor"]))
    lineas.append(_campo_txt("Producto",       d["producto"]))
    lineas.append(_campo_txt("Almacén",        d["almacen"]))
    lineas.append(_campo_txt("Selección",      d["seleccion"]))
    lineas.append(_campo_txt("Razón Social",   d["razon_social"]))
    lineas.append("")

    # ── 4. LECTURA DE PESOS (tabla de columnas) ───────────────────────────────
    lineas.append(_linea("="))
    lineas.append(_centrar("LECTURA DE PESOS"))
    lineas.append(_linea("-"))
    lineas.append(
        f"{'':<34}{'Fecha/Hora':>16} {'Peso Camion':>13} {'Peso Remolque':>13} {'Peso Total':>13}"
    )
    lineas.append(_fila_lectura_txt(
        f"Balanza Entrada: {d['balanza']}".rstrip(),
        _fmt_dt(d["hora_entrada"]),
        _fmt(d["pe_v"]), _fmt(d["pe_r"]), _fmt(d["pte"]),
    ))
    if d["hora_salida"] is not None:
        lineas.append(_fila_lectura_txt(
            f"Balanza Salida: {d['balanza']}".rstrip(),
            _fmt_dt(d["hora_salida"]),
            _fmt(d["ps_v"] or Decimal("0")),
            _fmt(d["ps_r"] or Decimal("0")),
            _fmt(d["pts"]),
        ))
    lineas.append(_linea("-"))

    # ── 5. Peso Neto / Declarado / Diferencia / Desviación ────────────────────
    neto_val = d["neto"] if d["neto"] is not None else Decimal("0")
    just = " (DESPACHO)" if neto_val < 0 else (" (INGRESO)" if neto_val > 0 else "")
    lineas.append(_fila_neto_txt(
        f"PESO NETO{just}:",
        _fmt(d["neto_camion"]), _fmt(d["neto_remolque"]), _fmt(neto_val),
    ))
    if d["declarado"] is not None:
        lineas.append(_fila_neto_txt(
            "PESO DECLARADO / DIFERENCIA:",
            " ", _fmt(d["declarado"]), _fmt_sig(d["diferencia"]),
        ))
        if d["desviacion"] is not None:
            lineas.append(_fila_neto_txt(
                "DESVIACIÓN:", " ", " ", f"{_fmt(d['desviacion'])} %",
            ))
    lineas.append(_linea("="))
    lineas.append("")

    # ── 6. DATOS ADICIONALES ──────────────────────────────────────────────────
    if d["documento"] or d["unidades_txt"] is not None or d["densidad_txt"] is not None:
        lineas.append(_linea("="))
        lineas.append(_centrar("DATOS ADICIONALES"))
        lineas.append(_linea("-"))
        if d["documento"]:
            lineas.append(_campo_txt("Documento", d["documento"]))
        if d["unidades_txt"] is not None:
            lineas.append(_campo_txt("Unidades", d["unidades_txt"]))
        if d["densidad_txt"] is not None:
            lineas.append(_campo_txt("Densidad", d["densidad_txt"]))
        lineas.append(_linea("="))
        lineas.append("")

    # ── 7. OBSERVACIONES ──────────────────────────────────────────────────────
    if mostrar_detalles and d["observaciones"]:
        lineas.append(_linea("="))
        lineas.append(_centrar("OBSERVACIONES"))
        lineas.append(_linea("-"))
        for obs_linea in d["observaciones"].splitlines():
            for chunk_start in range(0, max(1, len(obs_linea)), ANCHO_TXT - 5):
                lineas.append(obs_linea[chunk_start:chunk_start + ANCHO_TXT - 5])
        lineas.append("")

    # ── ANULADO ───────────────────────────────────────────────────────────────
    if anulado:
        lineas.append(_linea("*"))
        motivo = d["motivo_anulacion"] or "No especificado"
        lineas.append(_centrar("*** DOCUMENTO ANULADO ***"))
        lineas.append(_centrar(f"Motivo: {motivo}"))
        lineas.append(_linea("*"))
        lineas.append("")

    # ── 8. Firmas ─────────────────────────────────────────────────────────────
    ancho_col = ANCHO_TXT // 2
    lineas.append(
        f"{'_' * 24}".center(ancho_col) + f"{'_' * 24}".center(ancho_col)
    )
    lineas.append(
        "Firma Operador".center(ancho_col) + "Firma Conductor".center(ancho_col)
    )
    lineas.append("")

    # ── Pie ───────────────────────────────────────────────────────────────────
    lineas.append(_linea("-"))
    lineas.append(f"Estado: {d['estado']}")
    lineas.append(f"Impreso: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}")
    lineas.append(_linea("-"))

    return io.BytesIO("\n".join(lineas).encode("utf-8"))


# ─────────────────────────────────────────────────────────────────────────────
# API pública — firmas NO SE MODIFICAN (llamadas desde pesajes.py)
# ─────────────────────────────────────────────────────────────────────────────
def generar_ticket_pdf(
    p: BoletoPesaje,
    empresa: Empresa | None = None,
    boletos_por_hoja: int = 1,
    tamano_papel: str = "Letter",
    orientacion: str = "portrait",
    mostrar_encabezado: bool = True,
    mostrar_detalles: bool = True,
) -> StreamingResponse:
    """Retorna el PDF del boleto con layout fiel a TicketPreviewDialog (Flutter)."""
    buf = _build_pdf(
        p,
        empresa=empresa,
        boletos_por_hoja=boletos_por_hoja,
        tamano_papel=tamano_papel,
        orientacion=orientacion,
        mostrar_encabezado=mostrar_encabezado,
        mostrar_detalles=mostrar_detalles,
    )
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
    """Retorna el ticket en texto plano con layout fiel a TicketPreviewDialog (Flutter)."""
    buf = _build_txt(p, empresa=empresa)
    buf.seek(0)
    nombre = f"ticket_{p.numero_boleto or p.boleto}.txt"
    return StreamingResponse(
        buf,
        media_type="text/plain; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{nombre}"'},
    )