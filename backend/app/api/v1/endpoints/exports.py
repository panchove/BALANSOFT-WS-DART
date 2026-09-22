"""Ruta de exportación a Excel / PDF.

Correcciones aplicadas:
  - Resolver `fecha_desde`/`fecha_hasta` cuando solo se pasa `fecha`.
  - Encabezado institucional con logo en Excel y PDF (consistente con el ticket).
  - Formato latino (1.234,56) en números.
  - Join con Producto / Conductor / Transporte para mostrar nombres humanos.
  - Fuente DejaVu en PDF para acentos y ñ.
  - `colWidths` explícitos en tablas PDF para evitar desborde.
  - `HTTPException` importado a nivel de módulo.
  - Orientación Vertical/Horizontal para Kardex PDF.
"""

from __future__ import annotations

import glob
import os
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from io import BytesIO

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from openpyxl import Workbook
from openpyxl.drawing.image import Image as XLImage
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import landscape, letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    Image,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa
from app.core.config import settings
from app.core.database import get_db
from app.models import BoletoPesaje, Conductor, Empresa, Producto
from app.services.report_service import ReportService

router = APIRouter(prefix="/api/v1/reports", tags=["Reports"])

_SERVICE = ReportService()

# ─────────────────────────────────────────────────────────────────────────────
# Paleta y fuentes
# ─────────────────────────────────────────────────────────────────────────────
AZUL_MARINO = colors.HexColor("#1A365D")
AZUL_PRIMARIO = colors.HexColor("#2B6CB0")
GRIS_SUAVE = colors.HexColor("#F7FAFC")
GRIS_BORDE = colors.HexColor("#CBD5E0")
GRIS_ENCABEZADO = colors.HexColor("#EDF2F7")
ROJO_ANULADO = colors.HexColor("#C53030")

FUENTE = "DejaVu"
FUENTE_BOLD = "DejaVu-Bold"
_FUENTES_REGISTRADAS = False


def _registrar_ttf() -> None:
    """Registra DejaVu Sans una sola vez."""
    global _FUENTES_REGISTRADAS
    if _FUENTES_REGISTRADAS:
        return
    base = bold = None
    reg = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    bld = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    if os.path.exists(reg):
        base, bold = reg, bld if os.path.exists(bld) else reg
    else:
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
# Helpers de formato
# ─────────────────────────────────────────────────────────────────────────────
def _fmt(v: Decimal | float | int | str | None, decimales: int = 2) -> str:
    """Formato latino: 1.234,56."""
    if v is None or v == "":
        return "0,00"
    try:
        num = float(v)
    except (ValueError, InvalidOperation, TypeError):
        return str(v)
    formato = f"{{:,.{decimales}f}}"
    return formato.format(num).replace(",", "X").replace(".", ",").replace("X", ".")


def _fmt_fecha(v: str | datetime | date | None, con_hora: bool = False) -> str:
    """Devuelve dd/mm/YYYY [HH:MM]."""
    if v is None or v == "":
        return "—"
    if isinstance(v, str):
        try:
            v = datetime.fromisoformat(v.replace("Z", "+00:00"))
        except ValueError:
            return v[:19] if len(v) >= 10 else v
    if isinstance(v, date) and not isinstance(v, datetime):
        v = datetime(v.year, v.month, v.day)
    return v.strftime("%d/%m/%Y %H:%M" if con_hora else "%d/%m/%Y")


def _empresa_info(empresa: Empresa | None) -> dict:
    if empresa is None:
        return {"nombre": "", "rif": "", "direccion": "", "telefono": "",
                "email": "", "logo": None}
    nombre = (empresa.nombre_comercial or empresa.nombre_fiscal or "").strip()
    logo = None
    if getattr(empresa, "logo_url", None):
        rel = empresa.logo_url.lstrip("/")
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


def _nombre_movimiento(id_mov) -> str:
    """'INGRESO (10)' / 'DESPACHO (60)' a partir de int o str."""
    try:
        n = int(id_mov)
    except (TypeError, ValueError):
        return str(id_mov)
    tipo = "INGRESO" if n < 50 else "DESPACHO"
    return f"{tipo} ({n})"


def _resolver_periodo(
    fecha: date | None,
    fecha_desde: date | None,
    fecha_hasta: date | None,
) -> tuple[datetime, datetime, date, date]:
    """Devuelve (start, end, desde_date, hasta_date) resolviendo los None."""
    if fecha:
        start = datetime(fecha.year, fecha.month, fecha.day)
        end = datetime(fecha.year, fecha.month, fecha.day, 23, 59, 59)
        return start, end, fecha, fecha
    if fecha_desde and fecha_hasta:
        start = datetime(fecha_desde.year, fecha_desde.month, fecha_desde.day)
        end = datetime(fecha_hasta.year, fecha_hasta.month, fecha_hasta.day, 23, 59, 59)
        return start, end, fecha_desde, fecha_hasta
    raise HTTPException(
        status_code=400,
        detail="Debe proveer 'fecha' o 'fecha_desde' y 'fecha_hasta'",
    )


# ─────────────────────────────────────────────────────────────────────────────
# Excel: encabezado institucional + tabla
# ─────────────────────────────────────────────────────────────────────────────
def _excel_header_institucional(
    ws,
    empresa_info: dict,
    titulo: str,
    subtitulo: str | None = None,
    num_columnas: int = 7,
) -> int:
    """Escribe encabezado institucional. Devuelve fila donde empieza la tabla."""
    fila_inicio_tabla = 1
    if empresa_info["logo"]:
        try:
            img = XLImage(empresa_info["logo"])
            img.width = 90
            img.height = 60
            ws.add_image(img, "A1")
            fila_inicio_tabla = max(fila_inicio_tabla, 4)
        except Exception:
            pass

    celda = ws.cell(row=1, column=2, value=empresa_info["nombre"] or "—")
    celda.font = Font(bold=True, size=14, color="1A365D")
    celda.alignment = Alignment(horizontal="left", vertical="center")

    linea = " | ".join(filter(None, [
        f"RIF: {empresa_info['rif']}" if empresa_info["rif"] else "",
        f"Tel: {empresa_info['telefono']}" if empresa_info["telefono"] else "",
        empresa_info["email"] or "",
    ]))
    if linea:
        ws.cell(row=2, column=2, value=linea).font = Font(size=9, color="4A5568")
    if empresa_info["direccion"]:
        ws.cell(row=3, column=2, value=empresa_info["direccion"]).font = Font(
            size=9, color="4A5568")

    fila_titulo = fila_inicio_tabla + 1
    celda_titulo = ws.cell(row=fila_titulo, column=1, value=titulo)
    celda_titulo.font = Font(bold=True, size=12, color="1A365D")
    ws.merge_cells(
        start_row=fila_titulo, start_column=1,
        end_row=fila_titulo, end_column=num_columnas,
    )
    celda_titulo.alignment = Alignment(horizontal="left")

    fila_sub = fila_titulo + 1
    if subtitulo:
        ws.cell(row=fila_sub, column=1, value=subtitulo).font = Font(
            size=9, color="4A5568")
        ws.merge_cells(
            start_row=fila_sub, start_column=1,
            end_row=fila_sub, end_column=num_columnas,
        )
        return fila_sub + 2
    return fila_sub + 1


def _excel_escribir_tabla(
    ws, fila_inicio: int, headers: list[str], filas: list[list],
    anchos: list[int] | None = None,
) -> int:
    """Escribe encabezado + filas con estilo. Devuelve última fila usada."""
    header_font = Font(bold=True, color="FFFFFF", size=10)
    header_fill = PatternFill(start_color="1A365D", end_color="1A365D", fill_type="solid")
    header_align = Alignment(horizontal="center", vertical="center", wrap_text=True)
    borde = Border(
        left=Side(style="thin", color="CBD5E0"),
        right=Side(style="thin", color="CBD5E0"),
        top=Side(style="thin", color="CBD5E0"),
        bottom=Side(style="thin", color="CBD5E0"),
    )

    for col, header in enumerate(headers, 1):
        c = ws.cell(row=fila_inicio, column=col, value=header)
        c.font = header_font
        c.fill = header_fill
        c.alignment = header_align
        c.border = borde

    for i, fila in enumerate(filas):
        r = fila_inicio + 1 + i
        for col, valor in enumerate(fila, 1):
            c = ws.cell(row=r, column=col, value=valor)
            c.border = borde
            c.alignment = Alignment(vertical="center", wrap_text=True)
            if isinstance(valor, (int, float, Decimal)):
                c.number_format = "#,##0.00"

    if anchos is None:
        anchos = [18] * len(headers)
    for i, w in enumerate(anchos, 1):
        ws.column_dimensions[get_column_letter(i)].width = w

    return fila_inicio + len(filas)


# ─────────────────────────────────────────────────────────────────────────────
# PDF: encabezado institucional + estilos
# ─────────────────────────────────────────────────────────────────────────────
def _pdf_estilos() -> dict[str, ParagraphStyle]:
    es = getSampleStyleSheet()
    return {
        "empresa": ParagraphStyle(
            "empresa", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=13, leading=15, textColor=AZUL_MARINO,
        ),
        "info": ParagraphStyle(
            "info", parent=es["Normal"], fontName=FUENTE,
            fontSize=8, leading=10, textColor=colors.HexColor("#2D3748"),
        ),
        "titulo": ParagraphStyle(
            "titulo", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=13, leading=15, textColor=AZUL_MARINO,
            alignment=TA_CENTER,
        ),
        "subtitulo": ParagraphStyle(
            "subtitulo", parent=es["Normal"], fontName=FUENTE,
            fontSize=9, leading=11, textColor=colors.HexColor("#4A5568"),
            alignment=TA_CENTER,
        ),
        "seccion": ParagraphStyle(
            "seccion", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=9, leading=11, textColor=AZUL_MARINO,
        ),
        "celda": ParagraphStyle(
            "celda", parent=es["Normal"], fontName=FUENTE,
            fontSize=7.5, leading=9, textColor=colors.HexColor("#2D3748"),
        ),
        "celda_r": ParagraphStyle(
            "celda_r", parent=es["Normal"], fontName=FUENTE,
            fontSize=7.5, leading=9, textColor=colors.HexColor("#2D3748"),
            alignment=TA_RIGHT,
        ),
        "celda_enc": ParagraphStyle(
            "celda_enc", parent=es["Normal"], fontName=FUENTE_BOLD,
            fontSize=7.5, leading=9, textColor=colors.white,
            alignment=TA_CENTER,
        ),
    }


def _pdf_header_institucional(empresa_info: dict, st: dict, is_landscape: bool = False) -> Table:
    """Encabezado con logo + datos empresa."""
    izq: list = []
    if empresa_info["nombre"]:
        izq.append(Paragraph(empresa_info["nombre"], st["empresa"]))
    for etiqueta, valor in [
        ("RIF", empresa_info["rif"]),
        ("Dirección", empresa_info["direccion"]),
        ("Teléfono", empresa_info["telefono"]),
        ("Email", empresa_info["email"]),
    ]:
        if valor:
            izq.append(Paragraph(f"<b>{etiqueta}:</b> {valor}", st["info"]))

    if empresa_info["logo"]:
        try:
            logo = Image(empresa_info["logo"], width=22 * mm, height=16 * mm,
                         kind="proportional")
        except Exception:
            logo = Paragraph("", st["info"])
    else:
        logo = Paragraph("", st["info"])

    text_width = (219.4 * mm if is_landscape else 156 * mm)
    tabla = Table([[logo, izq]], colWidths=[24 * mm, text_width])
    tabla.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ("LINEBELOW", (0, 0), (-1, -1), 1.2, AZUL_MARINO),
    ]))
    return tabla


# ─────────────────────────────────────────────────────────────────────────────
# RUTA: Excel de pesajes
# ─────────────────────────────────────────────────────────────────────────────
@router.get("/export/excel")
async def export_to_excel(
    fecha: date | None = Query(None, description="Fecha para reporte diario (YYYY-MM-DD)"),
    fecha_desde: date | None = Query(None, description="Fecha inicio (YYYY-MM-DD)"),
    fecha_hasta: date | None = Query(None, description="Fecha fin (YYYY-MM-DD)"),
    vehicle_id: str | None = Query(None, description="Filtrar por placa"),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> StreamingResponse:
    """Exporta pesajes a un archivo Excel (.xlsx)."""
    start, end, desde_txt, hasta_txt = _resolver_periodo(fecha, fecha_desde, fecha_hasta)

    # Join con Producto y Conductor para mostrar nombres humanos
    stmt = (
        select(
            BoletoPesaje,
            Producto.nombre.label("nombre_producto"),
            Conductor.nombre.label("nombre_conductor"),
        )
        .outerjoin(Producto, BoletoPesaje.id_producto == Producto.id_producto)
        .outerjoin(Conductor, BoletoPesaje.id_conductor == Conductor.id_conductor)
        .where(
            BoletoPesaje.id_empresa == empresa.id_empresa,
            BoletoPesaje.fecha_hora_entrada >= start,
            BoletoPesaje.fecha_hora_entrada <= end,
            BoletoPesaje.estado_boleto != BoletoPesaje.ESTADO_ANULADO,
        )
    )
    if vehicle_id:
        stmt = stmt.where(BoletoPesaje.id_vehiculo == vehicle_id)
    stmt = stmt.order_by(BoletoPesaje.fecha_hora_entrada.desc())
    rows = (await db.execute(stmt)).all()

    emp = _empresa_info(empresa)
    wb = Workbook()
    ws = wb.active
    ws.title = "BoletoPesajes"

    fila_tabla = _excel_header_institucional(
        ws, emp,
        titulo="REPORTE DE PESAJE DE VEHÍCULOS",
        subtitulo=f"Período: {_fmt_fecha(desde_txt)} al {_fmt_fecha(hasta_txt)} | "
                  f"Total: {len(rows)} pesajes",
        num_columnas=12,
    )

    headers = [
        "Boleto", "Fecha Entrada", "Fecha Salida", "Vehículo", "Conductor",
        "Producto", "Peso Entrada", "Peso Salida", "Peso Bruto", "Peso Tara",
        "Peso Neto", "Estado",
    ]
    filas = []
    for p, nombre_producto, nombre_conductor in rows:
        filas.append([
            p.numero_boleto or str(p.boleto)[:8].upper(),
            _fmt_fecha(p.fecha_hora_entrada, con_hora=True),
            _fmt_fecha(p.fecha_hora_salida, con_hora=True),
            p.id_vehiculo or "—",
            nombre_conductor or (p.id_conductor or "—"),
            nombre_producto or (str(p.id_producto) if p.id_producto else "—"),
            float(p.peso_entrada_vehiculo) if p.peso_entrada_vehiculo else 0.0,
            float(p.peso_salida_vehiculo) if p.peso_salida_vehiculo else 0.0,
            float(p.peso_bruto) if p.peso_bruto else 0.0,
            float(p.peso_tara) if p.peso_tara else 0.0,
            float(p.peso_neto) if p.peso_neto else 0.0,
            p.estado_boleto or "—",
        ])
    _excel_escribir_tabla(
        ws, fila_tabla, headers, filas,
        anchos=[14, 18, 18, 12, 22, 24, 14, 14, 14, 14, 14, 12],
    )

    buffer = BytesIO()
    wb.save(buffer)
    buffer.seek(0)
    filename = f"pesajes_{desde_txt}_{hasta_txt}.xlsx"
    return StreamingResponse(
        buffer,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ─────────────────────────────────────────────────────────────────────────────
# RUTA: Kardex Excel
# ─────────────────────────────────────────────────────────────────────────────
def _kardex_desde_hasta(fecha_desde: date, fecha_hasta: date) -> tuple[datetime, datetime]:
    return (
        datetime(fecha_desde.year, fecha_desde.month, fecha_desde.day),
        datetime(fecha_hasta.year, fecha_hasta.month, fecha_hasta.day, 23, 59, 59),
    )


@router.get("/export/kardex/excel")
async def export_kardex_excel(
    fecha_desde: date = Query(..., description="Fecha inicio (YYYY-MM-DD)"),
    fecha_hasta: date = Query(..., description="Fecha fin (YYYY-MM-DD)"),
    id_producto: str | None = Query(None),
    id_almacen: str | None = Query(None),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> StreamingResponse:
    """Exporta movimientos de kardex del período a Excel (.xlsx)."""
    desde, hasta = _kardex_desde_hasta(fecha_desde, fecha_hasta)
    data = await _SERVICE.kardex_detalle(db, empresa, desde, hasta, id_producto, id_almacen)

    emp = _empresa_info(empresa)
    wb = Workbook()
    ws = wb.active
    ws.title = "Kardex"

    subtitulo = (
        f"Período: {_fmt_fecha(fecha_desde)} al {_fmt_fecha(fecha_hasta)} | "
        f"Saldo inicial: {_fmt(data['saldo_inicial'])} | "
        f"Saldo actual: {_fmt(data['saldo_actual'])} | "
        f"Movimientos: {len(data['movimientos'])}"
    )
    fila_tabla = _excel_header_institucional(
        ws, emp,
        titulo="KARDEX DE INVENTARIO",
        subtitulo=subtitulo,
        num_columnas=8,
    )

    headers = [
        "Fecha", "Movimiento", "Código", "Producto",
        "Almacén", "Valor", "Stock", "Referencia",
    ]
    filas = []
    for m in data["movimientos"]:
        ref = m.get("numero_boleto") or m.get("documento") or "—"
        filas.append([
            _fmt_fecha(m.get("fecha"), con_hora=False),
            _nombre_movimiento(m.get("id_movimiento")),
            m.get("codigo_producto") or "—",
            m.get("nombre_producto") or "—",
            m.get("nombre_almacen") or "—",
            float(m.get("valor") or 0),
            float(m.get("stock") or 0),
            str(ref),
        ])
    _excel_escribir_tabla(
        ws, fila_tabla, headers, filas,
        anchos=[12, 14, 12, 30, 24, 14, 14, 18],
    )

    buffer = BytesIO()
    wb.save(buffer)
    buffer.seek(0)
    filename = f"kardex_{fecha_desde}_{fecha_hasta}.xlsx"
    return StreamingResponse(
        buffer,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ─────────────────────────────────────────────────────────────────────────────
# RUTA: Kardex PDF
# ─────────────────────────────────────────────────────────────────────────────
@router.get("/export/kardex/pdf")
async def export_kardex_pdf(
    fecha_desde: date = Query(..., description="Fecha inicio (YYYY-MM-DD)"),
    fecha_hasta: date = Query(..., description="Fecha fin (YYYY-MM-DD)"),
    id_producto: str | None = Query(None),
    id_almacen: str | None = Query(None),
    orientacion: str = Query("V", description="Orientacion: V o H"),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> StreamingResponse:
    """Exporta movimientos de kardex del período a PDF."""
    desde, hasta = _kardex_desde_hasta(fecha_desde, fecha_hasta)
    data = await _SERVICE.kardex_detalle(db, empresa, desde, hasta, id_producto, id_almacen)

    _registrar_ttf()
    st = _pdf_estilos()
    emp = _empresa_info(empresa)

    is_landscape = orientacion.upper() == "H"
    page_size = landscape(letter) if is_landscape else letter

    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=page_size,
        leftMargin=12 * mm,
        rightMargin=12 * mm,
        topMargin=12 * mm,
        bottomMargin=14 * mm,
        title="Kardex de Inventario",
        author=emp["nombre"] or "Sistema",
    )

    elementos: list = []
    elementos.append(_pdf_header_institucional(emp, st, is_landscape))
    elementos.append(Spacer(1, 4 * mm))
    elementos.append(Paragraph("KARDEX DE INVENTARIO", st["titulo"]))
    elementos.append(Spacer(1, 1.5 * mm))
    subtitulo = (
        f"Período: {_fmt_fecha(fecha_desde)} al {_fmt_fecha(fecha_hasta)} &nbsp;|&nbsp; "
        f"Saldo inicial: <b>{_fmt(data['saldo_inicial'])}</b> &nbsp;|&nbsp; "
        f"Saldo actual: <b>{_fmt(data['saldo_actual'])}</b> &nbsp;|&nbsp; "
        f"Movimientos: {len(data['movimientos'])}"
    )
    elementos.append(Paragraph(subtitulo, st["subtitulo"]))
    elementos.append(Spacer(1, 4 * mm))

    headers = ["Fecha", "Movimiento", "Código", "Producto",
               "Almacén", "Valor", "Stock", "Referencia"]
    filas: list = [[Paragraph(h, st["celda_enc"]) for h in headers]]
    for m in data["movimientos"]:
        ref = m.get("numero_boleto") or m.get("documento") or "—"
        filas.append([
            Paragraph(_fmt_fecha(m.get("fecha")), st["celda"]),
            Paragraph(_nombre_movimiento(m.get("id_movimiento")), st["celda"]),
            Paragraph(m.get("codigo_producto") or "—", st["celda"]),
            Paragraph(m.get("nombre_producto") or "—", st["celda"]),
            Paragraph(m.get("nombre_almacen") or "—", st["celda"]),
            Paragraph(_fmt(m.get("valor")), st["celda_r"]),
            Paragraph(_fmt(m.get("stock")), st["celda_r"]),
            Paragraph(str(ref), st["celda"]),
        ])

    if is_landscape:
        # Anchos para Letter Horizontal (279.4mm - 24mm de márgenes = 255mm)
        col_widths = [
            24 * mm,   # Fecha
            28 * mm,   # Movimiento
            24 * mm,   # Código
            60 * mm,   # Producto
            45 * mm,   # Almacén
            22 * mm,   # Valor
            22 * mm,   # Stock
            30 * mm,   # Referencia
        ]
        # Ajuste de las columnas del pie para landscape
        pie_widths = [85 * mm, 85 * mm, 85 * mm]
    else:
        # Anchos para Letter Vertical (215.9mm - 24mm de márgenes = 191.9mm)
        col_widths = [
            18 * mm,   # Fecha
            22 * mm,   # Movimiento
            18 * mm,   # Código
            38 * mm,   # Producto
            30 * mm,   # Almacén
            20 * mm,   # Valor
            20 * mm,   # Stock
            26 * mm,   # Referencia
        ]
        pie_widths = [64 * mm, 64 * mm, 64 * mm]

    tabla = Table(filas, colWidths=col_widths, repeatRows=1)
    tabla.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), AZUL_MARINO),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("GRID", (0, 0), (-1, -1), 0.4, GRIS_BORDE),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, GRIS_SUAVE]),
        ("ALIGN", (5, 1), (6, -1), "RIGHT"),
    ]))
    elementos.append(tabla)
    elementos.append(Spacer(1, 4 * mm))

    pie = Table(
        [[
            Paragraph(f"<b>Saldo inicial:</b> {_fmt(data['saldo_inicial'])}", st["seccion"]),
            Paragraph(f"<b>Saldo actual:</b> {_fmt(data['saldo_actual'])}", st["seccion"]),
            Paragraph(f"<b>Movimientos:</b> {len(data['movimientos'])}", st["seccion"]),
        ]],
        colWidths=pie_widths,
    )
    pie.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), GRIS_ENCABEZADO),
        ("BOX", (0, 0), (-1, -1), 0.5, GRIS_BORDE),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
    ]))
    elementos.append(pie)

    def _on_page(cnv, d_):
        cnv.saveState()
        cnv.setFont(FUENTE, 7)
        cnv.setFillColor(colors.HexColor("#718096"))
        cnv.drawString(12 * mm, 8 * mm,
                       f"Impreso: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}")
        cnv.drawRightString(page_size[0] - 12 * mm, 8 * mm, f"Página {d_.page}")
        cnv.restoreState()

    doc.build(elementos, onFirstPage=_on_page, onLaterPages=_on_page)
    buffer.seek(0)

    filename = f"kardex_{fecha_desde}_{fecha_hasta}_{orientacion.upper()}.pdf"
    return StreamingResponse(
        buffer,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
