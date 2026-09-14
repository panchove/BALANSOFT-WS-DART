"""Pruebas de generación del ticket PDF (ReportLab + pypdf).

Verifica que el PDF es válido y que el contenido extraído (número de boleto,
placa, motivo de anulación y marca de agua "ANULADO") es correcto.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from io import BytesIO

from pypdf import PdfReader

from app.models import BoletoPesaje
from app.services.ticket_service import _build_pdf, _fmt, generar_ticket_pdf


def _extract(p) -> str:
    buf: BytesIO = _build_pdf(p)
    buf.seek(0)
    return "\n".join(page.extract_text() or "" for page in PdfReader(buf).pages)


def _boleto(**overrides) -> BoletoPesaje:
    base = dict(
        boleto=uuid.uuid4(),
        numero_boleto="TA-00000001",
        id_empresa=uuid.uuid4(),
        id_vehiculo="ABC123",
        remolque=False,
        fecha_hora_entrada=datetime(2026, 9, 8, 8, 30),
        peso_entrada_vehiculo=Decimal("50000"),
        peso_entrada_remolque=None,
        peso_salida_vehiculo=Decimal("45000"),
        peso_salida_remolque=None,
        peso_neto=Decimal("5000"),
        peso_neto_declarado=Decimal("5000"),
        peso_diferencia=Decimal("0"),
        porcentaje_desviacion=Decimal("0"),
        documento="G-001",
        densidad=Decimal("1.6"),
        litros=Decimal("3125"),
        unidades=Decimal("1"),
        observaciones="Observación de prueba",
        estado_boleto=BoletoPesaje.ESTADO_CERRADO,
        motivo_anulacion=None,
        peso_total_entrada=Decimal("50000"),
        peso_total_salida=Decimal("45000"),
    )
    base.update(overrides)
    return BoletoPesaje(**base)


class TestGeneracionPDF:
    def test_genera_pdf_valido(self):
        data = _build_pdf(_boleto()).getvalue()
        assert len(data) > 100
        assert data.startswith(b"%PDF")

    def test_streaming_response(self):
        resp = generar_ticket_pdf(_boleto())
        assert resp.media_type == "application/pdf"
        assert 'filename="ticket_TA-00000001.pdf"' in resp.headers["Content-Disposition"]

    def test_contenido_incluye_numero_y_placa(self):
        txt = _extract(_boleto())
        assert "TA-00000001" in txt
        assert "ABC123" in txt
        assert "Boleto de Pesaje" in txt

    def test_observaciones_se_dibujan(self):
        txt = _extract(_boleto())
        assert "Observación de prueba" in txt

    def test_cerrado_no_lleva_anulado(self):
        txt = _extract(_boleto())
        assert "DOCUMENTO ANULADO" not in txt
        # El estado normal debe mostrarse como CERRADO
        assert "CERRADO" in txt


class TestAnuladoWatermark:
    def test_anulado_contiene_palabra_y_motivo(self):
        p = _boleto(
            estado_boleto=BoletoPesaje.ESTADO_ANULADO,
            motivo_anulacion="Error de tipeo en la placa del camion de entrega",
        )
        txt = _extract(p)
        assert "ANULADO" in txt
        assert "DOCUMENTO ANULADO" in txt
        assert "Error de tipeo en la placa" in txt


class TestFormato:
    def test_fmt_decimal_con_comas(self):
        assert _fmt(Decimal("12345.67")) == "12.345,67"

    def test_fmt_float(self):
        assert _fmt(1234.5) == "1.234,50"

    def test_fmt_none(self):
        assert _fmt(None) == "0.00"

    def test_fmt_str_passthrough(self):
        assert _fmt("abc") == "abc"
