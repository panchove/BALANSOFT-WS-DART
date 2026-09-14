"""Ruta de exportación a Excel / PDF."""

from __future__ import annotations

from datetime import date, datetime
from io import BytesIO

from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse
from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa
from app.core.database import get_db
from app.models import BoletoPesaje, Empresa
from app.services.report_service import ReportService

router = APIRouter(prefix="/api/v1/reports", tags=["Reports"])

_SERVICE = ReportService()


@router.get("/export/excel")
async def export_to_excel(
    fecha_desde: date = Query(..., description="Fecha inicio (YYYY-MM-DD)"),
    fecha_hasta: date = Query(..., description="Fecha fin (YYYY-MM-DD)"),
    vehicle_id: str | None = Query(None, description="Filtrar por placa"),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> StreamingResponse:
    """Exporta pesajes a un archivo Excel (.xlsx)."""

    from datetime import datetime

    start = datetime(fecha_desde.year, fecha_desde.month, fecha_desde.day)
    end = datetime(fecha_hasta.year, fecha_hasta.month, fecha_hasta.day, 23, 59, 59)

    stmt = select(BoletoPesaje).where(
        BoletoPesaje.id_empresa == empresa.id_empresa,
        BoletoPesaje.fecha_hora_entrada >= start,
        BoletoPesaje.fecha_hora_entrada <= end,
        BoletoPesaje.estado_boleto != BoletoPesaje.ESTADO_ANULADO,
    )
    if vehicle_id:
        stmt = stmt.where(BoletoPesaje.id_vehiculo == vehicle_id)

    stmt = stmt.order_by(BoletoPesaje.fecha_hora_entrada.desc())
    rows = (await db.execute(stmt)).scalars().all()

    wb = Workbook()
    ws = wb.active
    ws.title = "BoletoPesajes"

    # Estilos
    header_font = Font(bold=True, color="FFFFFF")
    header_fill = PatternFill(start_color="2F5496", end_color="2F5496", fill_type="solid")
    header_align = Alignment(horizontal="center", vertical="center")

    headers = [
        "Boleto",
        "Fecha Entrada",
        "Fecha Salida",
        "Vehículo",
        "Conductor",
        "Producto",
        "Peso Entrada",
        "Peso Salida",
        "Peso Bruto",
        "Peso Tara",
        "Peso Neto",
        "Estado",
    ]

    for col, header in enumerate(headers, 1):
        cell = ws.cell(row=1, column=col, value=header)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = header_align

    for row_idx, p in enumerate(rows, 2):
        ws.cell(row=row_idx, column=1, value=str(p.boleto)[:8])
        ws.cell(row=row_idx, column=2, value=p.fecha_hora_entrada.isoformat() if p.fecha_hora_entrada else "")
        ws.cell(row=row_idx, column=3, value=p.fecha_hora_salida.isoformat() if p.fecha_hora_salida else "")
        ws.cell(row=row_idx, column=4, value=p.id_vehiculo or "")
        ws.cell(row=row_idx, column=5, value=p.id_conductor or "")
        ws.cell(row=row_idx, column=6, value=str(p.id_producto) if p.id_producto else "")
        ws.cell(row=row_idx, column=7, value=float(p.peso_entrada_vehiculo) if p.peso_entrada_vehiculo else 0)
        ws.cell(row=row_idx, column=8, value=float(p.peso_salida_vehiculo) if p.peso_salida_vehiculo else 0)
        ws.cell(row=row_idx, column=9, value=float(p.peso_bruto) if p.peso_bruto else 0)
        ws.cell(row=row_idx, column=10, value=float(p.peso_tara) if p.peso_tara else 0)
        ws.cell(row=row_idx, column=11, value=float(p.peso_neto) if p.peso_neto else 0)
        ws.cell(row=row_idx, column=12, value=p.estado_boleto)

    # Ajustar anchos de columna
    for col_idx in range(1, len(headers) + 1):
        ws.column_dimensions[ws.cell(row=1, column=col_idx).column_letter].width = 18

    # Fila de resumen
    total_row = len(rows) + 3
    ws.cell(row=total_row, column=1, value="RESUMEN").font = Font(bold=True)
    ws.cell(row=total_row + 1, column=1, value=f"Total pesajes: {len(rows)}")
    ws.cell(
        row=total_row + 2, column=1,
        value=f"Período: {fecha_desde.isoformat()} al {fecha_hasta.isoformat()}",
    )

    buffer = BytesIO()
    wb.save(buffer)
    buffer.seek(0)

    filename = f"pesajes_{fecha_desde}_{fecha_hasta}.xlsx"
    return StreamingResponse(
        buffer,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )


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

    wb = Workbook()
    ws = wb.active
    ws.title = "Kardex"

    ws.cell(row=1, column=1, value="BALANSOFT - KARDEX DE INVENTARIO").font = Font(bold=True)
    ws.cell(row=1, column=4, value=f"Saldo inicial: {data['saldo_inicial']}")
    ws.cell(row=1, column=5, value=f"Saldo actual: {data['saldo_actual']}")

    headers = ["Fecha", "ID Movimiento", "Producto", "Almacen", "Valor", "Stock", "Ref"]
    header_font = Font(bold=True, color="FFFFFF")
    header_fill = PatternFill(start_color="2F5496", end_color="2F5496", fill_type="solid")
    for col, header in enumerate(headers, 1):
        cell = ws.cell(row=3, column=col, value=header)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="center")

    for row_idx, m in enumerate(data["movimientos"], 4):
        ws.cell(row=row_idx, column=1, value=m["fecha"])
        ws.cell(row=row_idx, column=2, value=m["id_movimiento"])
        ws.cell(row=row_idx, column=3, value=m["id_producto"])
        ws.cell(row=row_idx, column=4, value=m["id_almacen"])
        ws.cell(row=row_idx, column=5, value=m["valor"])
        ws.cell(row=row_idx, column=6, value=m["stock"])
        ws.cell(row=row_idx, column=7, value=m["boleto"] or m["documento"])

    for col_idx in range(1, len(headers) + 1):
        ws.column_dimensions[ws.cell(row=3, column=col_idx).column_letter].width = 20

    buffer = BytesIO()
    wb.save(buffer)
    buffer.seek(0)

    filename = f"kardex_{fecha_desde}_{fecha_hasta}.xlsx"
    return StreamingResponse(
        buffer,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )


@router.get("/export/kardex/pdf")
async def export_kardex_pdf(
    fecha_desde: date = Query(..., description="Fecha inicio (YYYY-MM-DD)"),
    fecha_hasta: date = Query(..., description="Fecha fin (YYYY-MM-DD)"),
    id_producto: str | None = Query(None),
    id_almacen: str | None = Query(None),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> StreamingResponse:
    """Exporta movimientos de kardex del período a PDF."""
    desde, hasta = _kardex_desde_hasta(fecha_desde, fecha_hasta)
    data = await _SERVICE.kardex_detalle(db, empresa, desde, hasta, id_producto, id_almacen)

    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=letter)
    styles = getSampleStyleSheet()

    elements = [Paragraph("BALANSOFT - KARDEX DE INVENTARIO", styles["Title"])]
    elements.append(Paragraph(
        f"Período: {fecha_desde} al {fecha_hasta} "
        f"| Saldo inicial: {data['saldo_inicial']} | Saldo actual: {data['saldo_actual']}",
        styles["Normal"],
    ))
    elements.append(Spacer(1, 8))

    rows = [["Fecha", "ID Mov.", "Producto", "Almacen", "Valor", "Stock", "Ref"]]
    for m in data["movimientos"]:
        rows.append([
            m["fecha"],
            str(m["id_movimiento"]),
            m["id_producto"],
            m["id_almacen"],
            f"{m['valor']:,.2f}",
            f"{m['stock']:,.2f}",
            (m["boleto"] or m["documento"] or "")[:14],
        ])

    table = Table(rows, repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#2F5496")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
            ]
        )
    )
    elements.append(table)
    doc.build(elements)
    buffer.seek(0)

    filename = f"kardex_{fecha_desde}_{fecha_hasta}.pdf"
    return StreamingResponse(
        buffer,
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )
