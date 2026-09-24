"""Pruebas de generación del ticket PDF (ReportLab + pypdf).

Verifica que el PDF es válido y que el contenido extraído (número de boleto,
placa, motivo de anulación y marca de agua "ANULADO") es correcto.
"""

from __future__ import annotations

import re
import uuid
from datetime import datetime
from decimal import Decimal
from io import BytesIO
from types import SimpleNamespace

from pypdf import PdfReader

from app.models import BoletoPesaje
from app.services.ticket_service import (
    _build_pdf,
    _build_txt,
    _fmt,
    _fmt_densidad,
    _fmt_sig,
    generar_ticket_pdf,
)


def _extract(p, **kwargs) -> str:
    buf: BytesIO = _build_pdf(p, **kwargs)
    buf.seek(0)
    return "\n".join(page.extract_text() or "" for page in PdfReader(buf).pages)


def _paginas(p, **kwargs) -> int:
    buf: BytesIO = _build_pdf(p, **kwargs)
    buf.seek(0)
    return len(PdfReader(buf).pages)


def _max_text_x(p, **kwargs) -> float:
    """Mayor coordenada X (pt) en la que se dibuja texto en el PDF.

    Permite comprobar si el boleto único está centrado/estrecho en la hoja
    (debe quedar muy a la izquierda de 612pt) frente al modo de tiras que
    llena el ancho completo.
    """
    buf: BytesIO = _build_pdf(p, **kwargs)
    buf.seek(0)
    max_x = 0.0
    for page in PdfReader(buf).pages:
        def vis(text: str, cm, tm, font_dict, font_size) -> None:
            nonlocal max_x
            max_x = max(max_x, tm[4] + len(text) * 0.5)
        page.extract_text(visitor_text=vis)
    return max_x


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


def _boleto_completo() -> BoletoPesaje:
    """Boleto CERRADO con remolque, declarado/diferencia/desviación, datos
    adicionales y observaciones multilínea (el peor caso de contenido)."""
    p = _boleto(
        remolque=True,
        id_remolque=uuid.uuid4(),
        fecha_hora_salida=datetime(2026, 9, 8, 9, 15),
        peso_entrada_remolque=Decimal("12500"),
        peso_salida_remolque=Decimal("11500"),
        peso_neto=Decimal("7500"),
        peso_neto_declarado=Decimal("7425"),
        peso_diferencia=Decimal("75"),
        porcentaje_desviacion=Decimal("1.0101"),
        peso_total_entrada=Decimal("62500"),
        peso_total_salida=Decimal("55000"),
        documento="DOC-987654321",
        densidad=Decimal("0.92000000"),
        litros=Decimal("250000"),
        unidades=None,
        observaciones="Despacho a granel.\nRevisar merma de viaje.",
        tipo_tercero="PROVEEDOR",
    )
    # Atributos resolubles que en producción inyecta _enriquecer_pesaje_ticket
    # (no son columnas de BoletoPesaje; se fijan vía __setattr__ por mypy).
    p.__setattr__("balanza_nombre", "BALANZA PRINCIPAL")
    p.__setattr__("tercero_nombre", "PROVEEDOR DE PRUEBA C.A.")
    p.__setattr__("transporte_nombre", "TRANSPORTE DEMO C.A.")
    p.__setattr__("conductor_nombre", "FULANO DE TAL (V-12345678)")
    p.__setattr__("producto_nombre", "MAIZ AMARILLO")
    p.__setattr__("almacen_nombre", "SILO 01")
    p.__setattr__("placa_remolque", "RTA987")
    p.__setattr__("remolque_placa", "RTA987")
    return p


def _empresa_demo() -> SimpleNamespace:
    return SimpleNamespace(
        nombre_comercial="VARIEDADES S&S",
        nombre_fiscal="",
        rif_nit="J-31490236-2",
    )


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
        assert "boleto de pesaje" in txt.lower()

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


class TestLayoutNuevo:
    def test_pdf_incluye_zonas_del_layout(self):
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), boletos_por_hoja=3))
        for fragmento in (
            "LECTURA DE PESOS", "Peso Camion", "Peso Remolque", "Peso Total",
            "PESO NETO", "PESO DECLARADO", "DATOS ADICIONALES",
            "OBSERVACIONES", "DOC-987654321",
        ):
            assert fragmento in txt, f"falta '{fragmento}'"

    def test_boleto_unico_estrecho_conserva_contenido(self):
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), boletos_por_hoja=1))
        for fragmento in (
            "LECTURA DE PESOS", "PESO NETO", "DATOS ADICIONALES",
            "DOC-987654321", "OBSERVACIONES",
        ):
            assert fragmento in txt, f"falta '{fragmento}' (boleto único)"

    def test_3_por_carta_una_pagina(self):
        assert _paginas(_boleto_completo(), boletos_por_hoja=3, tamano_papel="Letter") == 1

    def test_3_por_carta_con_encabezado_una_pagina(self):
        assert _paginas(
            _boleto_completo(),
            boletos_por_hoja=3, tamano_papel="Letter",
            empresa=_empresa_demo(), mostrar_encabezado=True,
        ) == 1

    def test_3_por_a4_una_pagina(self):
        assert _paginas(_boleto_completo(), boletos_por_hoja=3, tamano_papel="A4") == 1

    def test_4_por_carta_una_pagina(self):
        assert _paginas(_boleto_completo(), boletos_por_hoja=4, tamano_papel="Letter") == 1

    def test_1_por_carta_una_pagina(self):
        assert _paginas(_boleto_completo(), boletos_por_hoja=1, tamano_papel="Letter") == 1

    def test_1_por_carta_con_encabezado_centrado_una_pagina(self):
        # Boleto único + encabezado debe caber en el ancho estrecho (140mm).
        assert _paginas(
            _boleto_completo(),
            boletos_por_hoja=1, tamano_papel="Letter",
            empresa=_empresa_demo(), mostrar_encabezado=True,
        ) == 1

    def test_1_por_a4_centrado_una_pagina(self):
        assert _paginas(_boleto_completo(), boletos_por_hoja=1, tamano_papel="A4") == 1

    def test_ancho_angosto_en_todas_las_cantidades(self):
        # Ancho fijo 140mm centrado sin importar cuántos boletos se apilen.
        for n in (1, 2, 3, 4):
            x = _max_text_x(_boleto_completo(), boletos_por_hoja=n, tamano_papel="Letter")
            assert x < 500.0, f"{n} por hoja ocupa demasiado ancho: {x:.1f}pt"

    def test_termico_una_pagina(self):
        assert _paginas(_boleto_completo(), tamano_papel="80mm") == 1


class TestTxtNuevo:
    def test_txt_incluye_tabla_de_lecturas(self):
        buf: BytesIO = _build_txt(_boleto_completo())
        txt = buf.getvalue().decode("utf-8")
        for fragmento in (
            "LECTURA DE PESOS", "Fecha/Hora", "Peso Camion", "Peso Remolque",
            "Peso Total", "Balanza Entrada: BALANZA PRINCIPAL",
            "PESO NETO", "PESO DECLARADO / DIFERENCIA", "DESVIACIÓN",
            "DATOS ADICIONALES", "OBSERVACIONES", "DOC-987654321",
        ):
            assert fragmento in txt, f"falta '{fragmento}'"


class TestFormato:
    def test_fmt_decimal_con_comas(self):
        assert _fmt(Decimal("12345.67")) == "12.345,67"

    def test_fmt_float(self):
        assert _fmt(1234.5) == "1.234,50"

    def test_fmt_none(self):
        assert _fmt(None) == "0,00"

    def test_fmt_str_passthrough(self):
        assert _fmt("abc") == "abc"

    def test_fmt_sig_positivo(self):
        assert _fmt_sig(Decimal("75")) == "+75,00"
        assert _fmt_sig(Decimal("-75")) == "-75,00"
        assert _fmt_sig(Decimal("0")) == "0,00"
        assert _fmt_sig(None) == ""

    def test_fmt_densidad(self):
        assert _fmt_densidad(Decimal("0.92")) == "0,92"
        assert _fmt_densidad(Decimal("1.6")) == "1,6"
        assert _fmt_densidad(None) is None
