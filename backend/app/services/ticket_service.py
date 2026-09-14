"""Generación del ticket/boleto de pesaje en PDF.

- Formato de ticket según MODEL.md (datos, lectura, adicionales, observaciones).
- Si el boleto está ANULADO se imprime con marca de agua 'ANULADO'.
"""

from __future__ import annotations

import io
from datetime import datetime
from decimal import Decimal

from fastapi.responses import StreamingResponse
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from app.models import BoletoPesaje
from app.services.weighing_service import normalizar_estado


def _fmt(v: Decimal | float | int | str | None) -> str:
    if v is None:
        return "0.00"
    if isinstance(v, Decimal):
        return f"{v:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    if isinstance(v, (int, float)):
        return f"{float(v):,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return str(v)


def _fmt_dt(dt: datetime | None) -> str:
    return dt.strftime("%d/%m/%Y %H:%M") if dt else ""


def _dato(p: BoletoPesaje) -> dict:
    peso_entrada_vehiculo = p.peso_entrada_vehiculo or Decimal("0")
    peso_entrada_remolque = p.peso_entrada_remolque or Decimal("0")
    peso_salida_vehiculo = p.peso_salida_vehiculo
    peso_salida_remolque = p.peso_salida_remolque
    return {
        "numero": p.numero_boleto or str(p.boleto)[:8].upper(),
        "fecha_hora": _fmt_dt(p.fecha_hora_entrada),
        "camion": p.id_vehiculo or "-",
        "remolque": "Si" if p.remolque else "No",
        "peso_entrada_vehiculo": peso_entrada_vehiculo,
        "peso_entrada_remolque": peso_entrada_remolque,
        "peso_salida_vehiculo": peso_salida_vehiculo,
        "peso_salida_remolque": peso_salida_remolque,
        "neto": p.peso_neto,
        "declarado": p.peso_neto_declarado,
        "diferencia": p.peso_diferencia,
        "desviacion": p.porcentaje_desviacion,
        "documento": p.documento or "-",
        "medida": "Litros",
        "unidades": p.unidades,
        "densidad": p.densidad,
        "litros": p.litros,
        "observaciones": p.observaciones,
        "estado": normalizar_estado(p.estado_boleto),
        "motivo_anulacion": p.motivo_anulacion,
    }


def _registrar_ttf() -> None:
    """Registra una fuente TTF con soporte de tildes/ñ si está disponible."""
    import glob
    import os

    candidatas = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    base = None
    for c in candidatas:
        if os.path.exists(c):
            base = c
            break
    if base is None:
        halls = glob.glob("/usr/share/fonts/**/DejaVuSans.ttf", recursive=True)
        if halls:
            base = halls[0]
    if base:
        pdfmetrics.registerFont(TTFont("DejaVu", base))
    else:
        pdfmetrics.registerFont(TTFont("DejaVu", "Arial"))


def _build_pdf(p: BoletoPesaje) -> io.BytesIO:
    """Compat: genera el PDF usando platypus (ver _platypus_pdf)."""
    return _platypus_pdf(p)


def _platypus_pdf(p: BoletoPesaje) -> io.BytesIO:
    """Genera el PDF con platypus y dibuja la marca de agua en cada página."""
    d = _dato(p)
    anulado = d["estado"] == "ANULADO"
    buf = io.BytesIO()

    _registrar_ttf()

    def _on_page(cnv: canvas.Canvas, doc: SimpleDocTemplate) -> None:
        if anulado:
            cnv.saveState()
            cnv.setFont("DejaVu", 60)
            cnv.setFillColor(colors.Color(1, 0, 0, alpha=0.18))
            cnv.translate(letter[0] / 2, letter[1] / 2)
            cnv.rotate(45)
            cnv.drawCentredString(0, 0, "ANULADO")
            cnv.restoreState()
        cnv.setFont("DejaVu", 8)
        cnv.drawString(18 * mm, 8 * mm, f"Generado: {_fmt_dt(p.fecha_hora_entrada)}")

    doc = SimpleDocTemplate(
        buf,
        pagesize=letter,
        rightMargin=18 * mm,
        leftMargin=18 * mm,
        topMargin=18 * mm,
        bottomMargin=18 * mm,
    )
    es = getSampleStyleSheet()
    st_titulo = ParagraphStyle(
        "titulo", parent=es["Title"], fontSize=16, spaceAfter=2, fontName="DejaVu"
    )
    st_n = ParagraphStyle(
        "normal", parent=es["Normal"], fontSize=10, leading=13, fontName="DejaVu"
    )

    elementos = [
        Paragraph("Boleto de Pesaje", st_titulo),
        Paragraph(f"Serie - Boleto: {d['numero']}", st_n),
        Paragraph(
            f"Fecha/Hora: {d['fecha_hora']} &nbsp; Camión: {d['camion']} &nbsp; "
            f"Remolque: {d['remolque']}",
            st_n,
        ),
        Spacer(1, 2 * mm),
    ]

    filas = [
        ["Documento", d["documento"]],
        ["Peso Entrada (Camión + Remolque)", _fmt(p.peso_total_entrada)],
        ["Peso Salida (Camión + Remolque)", _fmt(p.peso_total_salida)],
        ["Peso Neto Total (PNT)", _fmt(d["neto"])],
        ["Peso Neto Declarado (PND)", _fmt(d["declarado"])],
        ["Diferencia (PNT - PND)", _fmt(d["diferencia"])],
        ["% Desviación", _fmt(d["desviacion"]) if d["desviacion"] is not None else "-"],
    ]
    if d["densidad"] is not None:
        filas.append(["Densidad", str(d["densidad"]).replace(".", ",")])
    if d["unidades"] is not None:
        filas.append(["Unidades", _fmt(d["unidades"])])
    if d["litros"] is not None:
        filas.append(["Litros", _fmt(d["litros"])])
    filas.append(["Estado", d["estado"]])

    tabla = Table(filas, colWidths=[70 * mm, 80 * mm])
    tabla.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.4, colors.grey),
                ("FONT", (0, 0), (-1, -1), "DejaVu", 9),
                ("FONTSIZE", (1, 0), (1, -1), 11),
                ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#F0F0F0")),
            ]
        )
    )
    elementos.append(tabla)

    obs = (d["observaciones"] or "").strip()
    if obs:
        elementos.append(Spacer(1, 4 * mm))
        elementos.append(Paragraph("Observaciones:", st_n))
        for linea in obs.splitlines():
            elementos.append(Paragraph(linea, st_n))

    if anulado:
        elementos.append(Spacer(1, 4 * mm))
        elementos.append(
            Paragraph(
                f"<b>DOCUMENTO ANULADO — Motivo: {d['motivo_anulacion'] or '-'}</b>",
                ParagraphStyle("a", parent=st_n, fontSize=11, textColor=colors.red),
            )
        )

    elementos.append(Spacer(1, 8 * mm))
    elementos.append(Paragraph("Firma:", st_n))
    elementos.append(Spacer(1, 14 * mm))
    elementos.append(Paragraph("______________________", st_n))

    doc.build(elementos, onFirstPage=_on_page, onLaterPages=_on_page)
    return buf


def generar_ticket_pdf(p: BoletoPesaje) -> StreamingResponse:
    """Devuelve la respuesta PDF del ticket con marca de agua si está ANULADO."""
    buf = _platypus_pdf(p)
    buf.seek(0)
    nombre = f"ticket_{p.numero_boleto or p.boleto}.pdf"
    return StreamingResponse(
        buf,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nombre}"'},
    )