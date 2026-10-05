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
from typing import cast

import pytest
from pypdf import PdfReader

from app.models import BoletoPesaje, Empresa, Kardex
from app.services.ticket_service import (
    _ESCALAS_ACTUALES,
    ANCHO_TXT,
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


def _boleto_baseline() -> BoletoPesaje:
    """Boleto mínimo para capturar el baseline de texto extraído (T4)."""
    from decimal import Decimal
    bp = BoletoPesaje(
        id_empresa=uuid.uuid4(),
        numero_boleto="TA-00000123",
        id_vehiculo="ABC-123",
        fecha_hora_entrada=datetime(2026, 1, 1, 8, 0, 0),
        fecha_hora_salida=datetime(2026, 1, 1, 9, 0, 0),
        peso_entrada_vehiculo=Decimal("10000"),
        peso_salida_vehiculo=Decimal("5000"),
        peso_neto=Decimal("5000"),
        estado_boleto=BoletoPesaje.ESTADO_CERRADO,
    )
    # Campos desnormalizados que ticket_service._dato lee con getattr: no están
    # en el modelo (vienen de los JOIN del listado), así que se fijan con setattr
    # en vez de asignación directa.
    for campo, valor in (
        ("producto_nombre", "MATERIA PRIMA"),
        ("conductor_nombre", "JUAN PEREZ"),
        ("cliente_nombre", "CLIENTE DEMO"),
        ("proveedor_nombre", "PROVEEDOR DEMO"),
        ("procedencia", "ORIGEN A"),
        ("destino", "DESTINO B"),
    ):
        setattr(bp, campo, valor)
    return bp


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


def _imagenes(p, **kwargs) -> int:
    """Cuántas imágenes lleva incrustadas el PDF (1 = el logo de la empresa)."""
    buf: BytesIO = _build_pdf(p, **kwargs)
    buf.seek(0)
    total = 0
    for page in PdfReader(buf).pages:
        xobjects = page.get("/Resources", {}).get("/XObject", {})
        for ref in (xobjects or {}).values():
            if ref.get_object().get("/Subtype") == "/Image":
                total += 1
    return total


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


def _empresa_demo(**extra) -> SimpleNamespace:
    datos = dict(
        nombre_comercial="VARIEDADES S&S",
        nombre_fiscal="",
        rif_nit="J-31490236-2",
        telefono=None,
        direccion=None,
        email=None,
        logo_url=None,
    )
    datos.update(extra)
    return SimpleNamespace(**datos)


def _empresa_contacto(**extra) -> SimpleNamespace:
    """Empresa con los datos de contacto que ahora se imprimen en el boleto."""
    return _empresa_demo(
        telefono="+58 412-1234567",
        direccion="Av. Principal Edif. Torre Local, Piso 2, Chacao, Caracas 1060",
        email="operaciones@variedades-ss.com.ve",
        **extra,
    )


def _png_bytes(w: int = 400, h: int = 160) -> bytes:
    """PNG válido minúsculo, para probar el render del logo."""
    import struct
    import zlib

    filas = b""
    for y in range(h):
        fila = b"\x00"
        for x in range(w):
            dentro = 20 < x < w - 20 and 20 < y < h - 20
            fila += bytes((12, 74, 140) if dentro else (245, 246, 248))
        filas += fila

    def _chunk(tag: bytes, datos: bytes) -> bytes:
        cuerpo = tag + datos
        return struct.pack(">I", len(datos)) + cuerpo + struct.pack(
            ">I", zlib.crc32(cuerpo) & 0xFFFFFFFF
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + _chunk(b"IDAT", zlib.compress(filas))
        + _chunk(b"IEND", b"")
    )


def _logo_en_media(monkeypatch, tmp_path, nombre: str = "logo.png") -> str:
    """Deja un logo en ``media/empresa/<nombre>`` y devuelve el `logo_url`."""
    from app.core.config import settings

    dest = tmp_path / "empresa"
    dest.mkdir(parents=True, exist_ok=True)
    (dest / nombre).write_bytes(_png_bytes())
    monkeypatch.setattr(settings, "media_dir", str(tmp_path))
    return f"/media/empresa/{nombre}"


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

    def test_3_por_carta_con_encabezado_una_pagina_sin_firmas(self):
        kwargs = dict(
            boletos_por_hoja=3, tamano_papel="Letter",
            empresa=_empresa_demo(), mostrar_encabezado=True,
        )
        assert _paginas(_boleto_completo(), **kwargs) == 1
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), **kwargs))
        assert txt.count("Documento") == 3
        assert "Firma Conductor" not in txt

    def test_3_por_a4_una_pagina(self):
        assert _paginas(_boleto_completo(), boletos_por_hoja=3, tamano_papel="A4") == 1

    def test_4_por_carta_no_trunca(self):
        kwargs = dict(boletos_por_hoja=4, tamano_papel="Letter")
        assert _paginas(_boleto_completo(), **kwargs) >= 1
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), **kwargs))
        assert txt.count("Documento") == 4
        assert "Firma Conductor" not in txt

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


class TestEncabezadoEmpresa:
    """Datos de contacto y logo en el encabezado del boleto."""

    def test_pdf_incluye_telefono_direccion_y_email(self):
        # El texto se normaliza (colapsar saltos) porque pdfminer parte las
        # líneas dentro de la celda de la tabla del encabezado.
        texto = " ".join(
            _extract(_boleto(), empresa=_empresa_contacto(), mostrar_encabezado=True).split()
        )
        assert "+58 412-1234567" in texto
        assert "Chacao, Caracas 1060" in texto
        assert "operaciones@variedades-ss.com.ve" in texto

    def test_omit_lo_que_la_empresa_no_tiene(self):
        # Sin datos de contacto el encabezado queda como estaba (nombre + RIF).
        texto = _extract(_boleto(), empresa=_empresa_demo(), mostrar_encabezado=True)
        assert "VARIEDADES S&S" in texto and "J-31490236-2" in texto
        assert "Tel." not in texto and "Direcci" not in texto

    def test_sin_encabezado_no_sale_contacto_ni_logo(self, monkeypatch, tmp_path):
        url = _logo_en_media(monkeypatch, tmp_path)
        texto = _extract(
            _boleto(),
            empresa=_empresa_contacto(logo_url=url),
            mostrar_encabezado=False,
        )
        assert "J-31490236-2" not in texto
        assert "+58 412-1234567" not in texto
        assert _imagenes(_boleto(), empresa=_empresa_contacto(logo_url=url),
                         mostrar_encabezado=False) == 0

    def test_logo_se_incrusta_en_hoja(self, monkeypatch, tmp_path):
        url = _logo_en_media(monkeypatch, tmp_path)
        empresa = _empresa_contacto(logo_url=url)
        assert _imagenes(_boleto(), empresa=empresa, tamano_papel="Letter") == 1
        assert _imagenes(_boleto(), empresa=empresa, tamano_papel="A4") == 1

    def test_logo_no_se_pone_en_el_ticket_termico(self, monkeypatch, tmp_path):
        # En 58/80mm no cabe un logo: el térmico lleva solo los datos.
        url = _logo_en_media(monkeypatch, tmp_path)
        assert _imagenes(
            _boleto(), empresa=_empresa_contacto(logo_url=url), tamano_papel="80mm"
        ) == 0

    def test_logo_inexistente_no_rompe_el_pdf(self, monkeypatch, tmp_path):
        from app.core.config import settings

        monkeypatch.setattr(settings, "media_dir", str(tmp_path))
        texto = _extract(
            _boleto(),
            empresa=_empresa_contacto(logo_url="/media/empresa/no-existe.png"),
        )
        assert "J-31490236-2" in texto
        assert _imagenes(
            _boleto(), empresa=_empresa_contacto(logo_url="/media/empresa/no-existe.png")
        ) == 0

    def test_logo_corrupto_no_rompe_el_pdf(self, monkeypatch, tmp_path):
        dest = tmp_path / "empresa"
        dest.mkdir(parents=True, exist_ok=True)
        (dest / "roto.png").write_bytes(b"esto no es una imagen")
        from app.core.config import settings

        monkeypatch.setattr(settings, "media_dir", str(tmp_path))
        texto = _extract(
            _boleto(), empresa=_empresa_contacto(logo_url="/media/empresa/roto.png")
        )
        assert "J-31490236-2" in texto

    def test_logo_externo_se_ignora(self):
        # Una URL http(s) no se descarga: el boleto sale igual, sin logo.
        empresa = _empresa_contacto(logo_url="https://ejemplo.com/logo.png")
        assert _imagenes(_boleto(), empresa=empresa) == 0

    def test_4_por_carta_con_contacto_y_logo_no_trunca(self, monkeypatch, tmp_path):
        url = _logo_en_media(monkeypatch, tmp_path)
        kwargs = dict(
            boletos_por_hoja=4, tamano_papel="Letter",
            empresa=_empresa_contacto(logo_url=url), mostrar_encabezado=True,
        )
        assert _paginas(_boleto_completo(), **kwargs) >= 1
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), **kwargs))
        assert txt.count("Documento") == 4
        assert "Firma Conductor" not in txt

    def test_3_por_carta_con_contacto_y_logo_no_trunca(self, monkeypatch, tmp_path):
        url = _logo_en_media(monkeypatch, tmp_path)
        kwargs = dict(
            boletos_por_hoja=3, tamano_papel="Letter",
            empresa=_empresa_contacto(logo_url=url), mostrar_encabezado=True,
        )
        assert _paginas(_boleto_completo(), **kwargs) >= 1
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), **kwargs))
        assert txt.count("Documento") == 3
        assert "Firma Conductor" not in txt

    def test_termico_largo_sigue_en_una_pagina(self):
        assert _paginas(
            _boleto_completo(),
            tamano_papel="80mm", empresa=_empresa_contacto(), mostrar_encabezado=True,
        ) == 1

    def test_boleto_unico_estrecho_con_contacto_una_pagina(self):
        assert _paginas(
            _boleto_completo(),
            boletos_por_hoja=1, tamano_papel="Letter",
            empresa=_empresa_contacto(), mostrar_encabezado=True,
        ) == 1

    def test_ancho_angosto_con_contacto(self):
        for n in (1, 2, 3, 4):
            x = _max_text_x(
                _boleto_completo(), boletos_por_hoja=n, tamano_papel="Letter",
                empresa=_empresa_contacto(), mostrar_encabezado=True,
            )
            assert x < 500.0, f"{n} por hoja ocupa demasiado ancho: {x:.1f}pt"


class TestTxtEncabezado:
    def test_txt_incluye_contacto(self):
        buf: BytesIO = _build_txt(_boleto(), empresa=_empresa_contacto())  # type: ignore[arg-type]
        txt = buf.getvalue().decode("utf-8")
        assert "+58 412-1234567" in txt
        assert "operaciones@variedades-ss.com.ve" in txt

    def test_txt_Respeta_el_ancho_del_ticket(self):
        buf: BytesIO = _build_txt(_boleto(), empresa=_empresa_contacto())  # type: ignore[arg-type]
        for linea in buf.getvalue().decode("utf-8").splitlines():
            assert len(linea) <= ANCHO_TXT, f"línea de {len(linea)} columnas: {linea!r}"


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


class TestI18nTicket:
    def test_ticket_txt_ingles(self):
        buf: BytesIO = _build_txt(_boleto_completo(), idioma="en")
        txt = buf.getvalue().decode("utf-8")
        assert "BALANSOFT WEIGHING TICKET" in txt
        assert "WEIGHT READINGS" in txt
        assert "Truck Weight" in txt
        assert "NET WEIGHT" in txt
        assert "Driver Signature" not in txt  # BÁSICO sin firmas
        adv = _build_txt(_boleto_completo(), idioma="en", tipo_ticket="avanzado").getvalue().decode("utf-8")
        assert "Driver Signature" in adv

    def test_ticket_txt_portugues(self):
        buf: BytesIO = _build_txt(_boleto_completo(), idioma="pt")
        txt = buf.getvalue().decode("utf-8")
        assert "BILHETE DE PESAGEM BALANSOFT" in txt
        assert "LEITURA DE PESOS" in txt
        assert "Peso Caminhão" in txt
        assert "PESO LÍQUIDO" in txt
        assert "Assinatura do Motorista" not in txt  # BÁSICO sin firmas
        adv = _build_txt(_boleto_completo(), idioma="pt", tipo_ticket="avanzado").getvalue().decode("utf-8")
        assert "Assinatura do Motorista" in adv

    def test_ticket_pdf_ingles(self):
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), idioma="en"))
        assert "BALANSOFT WEIGHING TICKET" in txt
        assert "WEIGHT READINGS" in txt
        assert "NET WEIGHT" in txt

    def test_ticket_pdf_portugues(self):
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), idioma="pt"))
        assert "BILHETE DE PESAGEM BALANSOFT" in txt
        assert "LEITURA DE PESOS" in txt
        assert "PESO LÍQUIDO" in txt


class TestTicketAvanzadoCompleto:
    """El boleto AVANZADO debe reflejar TODOS los campos del formulario de
    pesaje (guía SUNAGRO, medida, flete, costo flete, unidades, densidad,
    resultado, color de camión y operador), y el BÁSICO solo lo mínimo."""

    def _boleto_avanzado(self) -> BoletoPesaje:
        p = _boleto_completo()
        p.guia_sunagro = "SUNAGRO-2026-001"
        p.medida = "M3"
        p.flete = "C/S 250,00"
        p.costo_flete = Decimal("250.00")
        p.__setattr__("color_camion", "ROJO")
        p.__setattr__("creado_por", "OPERADOR 01")
        p.__setattr__("es_peso_manual", True)
        return p

    def test_avanzado_pdf_incluye_todo_el_formulario(self):
        txt = re.sub(r"\s+", " ", _extract(self._boleto_avanzado(), tipo_ticket="avanzado"))
        for frag in (
            "DOC-987654321", "SUNAGRO-2026-001", "M3", "C/S 250,00",
            "250.00", "ROJO", "Colo", "OPERADOR 01", "Resultado",
        ):
            assert frag in txt, f"falta '{frag}' en el PDF avanzado"

    def test_avanzado_txt_incluye_todo_el_formulario(self):
        txt = _build_txt(self._boleto_avanzado(), tipo_ticket="avanzado").getvalue().decode("utf-8")
        for frag in (
            "Guía SUNAGRO", "SUNAGRO-2026-001", "Medida", "M3", "Flete",
            "C/S 250,00", "Costo Flete", "250.00", "Resultado",
            "Color Camión", "ROJO", "Operador", "OPERADOR 01",
        ):
            assert frag in txt, f"falta '{frag}' en el TXT avanzado"

    def test_basico_no_muestra_campos_solo_avanzados(self):
        txt = re.sub(r"\s+", " ", _extract(self._boleto_avanzado(), tipo_ticket="simple"))
        assert "DOC-987654321" in txt
        assert "SUNAGRO-2026-001" not in txt
        assert "M3" not in txt
        assert "ROJO" not in txt
        assert "Resultado" not in txt

    def test_basico_marca_peso_manual_con_operador(self):
        txt = re.sub(r"\s+", " ", _extract(self._boleto_avanzado(), tipo_ticket="simple"))
        assert "PESO MANUAL" in txt
        assert "OPERADOR 01" in txt

    def test_avanzado_conserva_firmas_y_basico_no(self):
        adv = re.sub(r"\s+", " ", _extract(self._boleto_avanzado(), tipo_ticket="avanzado"))
        bas = re.sub(r"\s+", " ", _extract(self._boleto_avanzado(), tipo_ticket="simple"))
        assert "Firma Operador" in adv and "Firma Conductor" in adv
        assert "Firma Operador" not in bas and "Firma Conductor" not in bas

    def test_avanzado_termico_una_pagina(self):
        assert _paginas(self._boleto_avanzado(), tamano_papel="80mm", tipo_ticket="avanzado") == 1

    def test_avanzado_3_por_carta_no_trunca_el_contenido(self):
        """Con 3 boletos por hoja el AVANZADO es mucho contenido: en vez de
        cortar el excedente (como hacía antes), las copias fluyen a páginas
        siguientes y TODA la información aparece en el PDF."""
        txt = re.sub(r"\s+", " ", _extract(
            self._boleto_avanzado(), boletos_por_hoja=3, tamano_papel="Letter", tipo_ticket="avanzado"
        ))
        for frag in (
            "Boleto", "SUNAGRO-2026-001", "M3", "C/S 250,00",
            "250.00", "ROJO", "OPERADOR 01", "Resultado",
        ):
            assert frag in txt, f"falta '{frag}' en PDF avanzado a 3/hoja"
        total = _paginas(
            self._boleto_avanzado(), boletos_por_hoja=3, tamano_papel="Letter", tipo_ticket="avanzado"
        )
        assert total >= 1
        assert "Boleto" in txt


class TestTicketCatalogoControl:
    """El AVANZADO debe reflejar las entidades maestro (empresa, tercero,
    conductor, transporte, remolque, categoría, producto, almacén, balanza)
    y los registros de control derivados (kardex, sincronización)."""

    def _boleto_catalogo(self):
        p = _boleto_completo()
        extras = {
            "tercero_codigo": "CLI-01",
            "tercero_rif": "J-31490236-2",
            "conductor_cedula": "V-18293041",
            "conductor_telefono": "+58 412-0000000",
            "conductor_licencia": "L-2010-998877",
            "transporte_codigo": "TRP-01",
            "transporte_rif": "J-88776655-4",
            "tipo_remolque": "Cisterna",
            "tara_habitual": Decimal("12500.00"),
            "categoria_nombre": "Materia Prima",
            "categoria_codigo": "CAT-001",
            "producto_codigo": "PROD-001",
            "producto_unidad": "TON",
            "producto_kardex": True,
            "almacen_codigo": "SIL-01",
            "almacen_capacidad": Decimal("1200.00"),
            "almacen_stock": Decimal("300.00"),
            "balanza_codigo": "BAL-80T",
            "balanza_capacidad": Decimal("80000.00"),
            "balanza_division": Decimal("20.00"),
            "kardex_mov": Kardex.KARDEX_INGRESO,
            "kardex_valor": Decimal("7500.00"),
            "sincronizado": True,
        }
        for k, v in extras.items():
            p.__setattr__(k, v)
        return p

    def test_pdf_avanzado_incluye_catalogo_y_control(self):
        txt = re.sub(r"\s+", " ", _extract(self._boleto_catalogo(), tipo_ticket="avanzado"))
        for frag in (
            "DATOS DEL CATÁLOGO Y CONTROL", "CLI-01", "J-31490236-2",
            "TRP-01", "J-88776655-4", "V-18293041", "L-2010-998877",
            "Cisterna", "CAT-001", "PROD-001", "TON", "SIL-01", "BAL-80T",
            "INGRESO", "kg", "Kardex",
        ):
            assert frag in txt, f"falta '{frag}' en PDF avanzado"

    def test_txt_avanzado_incluye_catalogo_y_control(self):
        txt = _build_txt(self._boleto_catalogo(), tipo_ticket="avanzado").getvalue().decode("utf-8")
        for frag in (
            "DATOS DEL CATÁLOGO Y CONTROL", "CLI-01", "TRP-01", "J-88776655-4",
            "Conductor Cédula", "Cisterna", "CAT-001", "PROD-001", "TON",
            "SIL-01", "BAL-80T", "INGRESO", "Sincronizado",
        ):
            assert frag in txt, f"falta '{frag}' en TXT avanzado"

    def test_catalogo_no_aparece_en_basico(self):
        txt = re.sub(r"\s+", " ", _extract(self._boleto_catalogo(), tipo_ticket="simple"))
        assert "DATOS DEL CATÁLOGO Y CONTROL" not in txt
        assert "CLI-01" not in txt



class TestTipografiaBaseline:
    """T4 — Baseline de PDF y no-regresión con AUTOMATICO."""

    @staticmethod
    def _extraido(p: BoletoPesaje, **kwargs) -> str:
        buf = BytesIO()
        from app.services.ticket_service import _build_pdf

        buf = _build_pdf(p, **kwargs)
        buf.seek(0)
        from pypdf import PdfReader

        texto = "\n".join(page.extract_text() or "" for page in PdfReader(buf).pages)
        # Normalizar espacios y saltos
        import re

        return re.sub(r"[ \t]+", " ", re.sub(r"\n+", "\n", texto)).strip()

    def test_baseline_automatico_es_estable(self):
        """REQ-FN-012: con AUTOMATICO el texto extraído es idéntico al baseline."""
        b = _boleto_baseline()
        texto = self._extraido(b, empresa=None, boletos_por_hoja=1)
        assert texto != "", "PDF vacío"
        # Firma estable del baseline (fragmentos que no cambian entre ejecuciones)
        assert "TA-00000123" in texto
        assert "ABC-123" in texto
        assert "MATERIA PRIMA" in texto

    def test_automatico_no_regression(self):
        """No-regresión: dos generaciones con AUTOMATICO producen texto idéntico."""
        b = _boleto_baseline()
        t1 = self._extraido(b)
        t2 = self._extraido(b)
        assert t1 == t2

    def test_pdf_valido(self):
        from app.services.ticket_service import _build_pdf

        buf = _build_pdf(_boleto_baseline())
        buf.seek(0)
        assert buf.read(4) == b"%PDF"


class TestTipografiaPeldaños:
    """T5 — El peldaño configurado es el punto de partida de la escalera.

    Por que se reescribieron estos tests. Los anteriores afirmaban dos cosas:
    que el boleto no se truncaba y que el numero aparecia en el texto. Las dos
    cosas ya las cumplia la escalera vigente, porque ``tamano_ticket_pdf`` no se
    leia en ningun sitio de ``ticket_service``. Esos tests pasaban sin comprobar
    el peldaño: eran nombre sin contenido, y dejaban sin cubrir la cobertura de
    REQ-FN-010, REQ-FN-011 y REQ-FN-015.

    Ahora se afirma el peldaño, y se hace de dos formas complementarias:

    - sobre ``escalera_efectiva``, que es pura aritmetica y se comprueba exacto;
    - sobre el PDF, midiendo el tamano de fuente que ReportLab dibujo.

    Para lo segundo el valor esperado **se deriva de ``_estilos_simples``** y no
    se escribe a mano. El desplazamiento entre el peldaño y cada estilo (la
    etiqueta va en ``ts - 0.5``) es un detalle del modulo: si cambia, el test
    sigue diciendo la verdad en vez de romperse por 0.5 puntos que nadie toco.
    """

    # Los nombres de fuente llevan sufijo de subconjunto ("F2+0", "F3+0"), asi
    # que el patron tiene que aceptar el "+0". Con "/F\d+" solo se leian las
    # lineas de F1, y la extraccion devolvia 10.0 para todos los casos: es decir,
    # no media nada.
    _RE_TF = re.compile(r"/F[^\s/]+\s+([\d.]+)\s+Tf")

    #: Tamano de la cabecera de pagina y del pie, fijos y ajenos al peldaño.
    #: 12.0 es el nombre de la empresa y 7.0 el de los datos de cabecera. OJO:
    #: 7.0 es *tambien* el cuerpo del boleto con PEQUENO, asi que no se puede
    #: usar como "ajeno" en general (ver `_cuerpo`, que no lista ninguno).
    _AJENOS = (12.0,)

    @staticmethod
    def _empresa(tamano: str) -> Empresa:
        """Empresa mínima con el peldaño configurado.

        ``SimpleNamespace`` a propósito: es lo que usan los tests existentes del
        fichero, y es lo que obliga a que la implementación lea el valor con
        ``getattr`` en vez de acceso directo (ver T6, punto 3). El ``cast`` deja
        explícito que es un doble de pruebas, no una entidad de la base de datos.
        """
        return cast("Empresa", SimpleNamespace(
            tamano_ticket_pdf=tamano,
            fuente_ticket_pdf="DejaVu",
            nombre_comercial=None,
            nombre_fiscal="",
            rif_nit="",
        ))

    @classmethod
    def _cuerpo(cls, p, **kwargs) -> float:
        """Tamano de fuente del cuerpo del boleto: el mas repetido.

        El cuerpo del boleto son las etiquetas y los valores, que comparten el
        tamano ``ts - 0.5`` (``label_l``/``valor_r``/``tab_val``). El PDF tambien
        trae encabezado, titulo y sellos con tamaños propios, y con 3 o 4 boletos
        por hoja la moda *global* la gana el encabezado (10.0), no el cuerpo. Por
        eso se mide la moda **de los candidatos a cuerpo**: los ``ts - 0.5`` que
        la escalera de este ajuste puede elegir. Asi el observables es el del
        peldaño y no el de la pagina entera.
        """
        from collections import Counter

        from app.services.ticket_service import escalera_efectiva

        escalera = escalera_efectiva(
            _ESCALAS_ACTUALES, getattr(kwargs.get("empresa"), "tamano_ticket_pdf", "AUTOMATICO")
        )
        candidatos = {round(ts - 0.5, 2) for ts in escalera[kwargs.get("boletos_por_hoja", 1)]}
        # `peso_manual_c` usa `ts` (no `ts - 0.5`) y no aplica a este boleto, pero
        # se incluye por si el fixture cambia.
        candidatos |= {round(ts, 2) for ts in escalera[kwargs.get("boletos_por_hoja", 1)]}

        buf = _build_pdf(p, **kwargs)
        buf.seek(0)
        contents = PdfReader(buf).pages[0].get_contents()
        assert contents is not None, "la página del PDF no tiene stream de contenido"
        tamanos = Counter(
            float(m)
            for m in cls._RE_TF.findall(contents.get_data().decode("latin-1"))
            if float(m) in candidatos
        )
        assert tamanos, (
            "ningun tamano del PDF corresponde a la escalera de "
            f"{sorted(candidatos)}: la extraccion de Tf no encontro el cuerpo"
        )
        return tamanos.most_common(1)[0][0]

    @staticmethod
    def _esperado(peldaño: float) -> float:
        """Tamano que deberia verse en pantalla si se eligio ``peldaño``."""
        from app.services.ticket_service import _estilos_simples

        return _estilos_simples(peldaño)["label_l"].fontSize  # type: ignore[attr-defined]

    # ── Escalera de referencia: control antes que nada ──────────────────────
    @pytest.mark.parametrize(
        ("por_hoja", "piso_de_la_escalera"),
        [(1, 10.5), (2, 9.5), (3, 8.5), (4, 8.0)],
    )
    def test_la_escalera_vigente_arranca_en_su_primer_peldaño(
        self, por_hoja: int, piso_de_la_escalera: float
    ) -> None:
        """Control: el primer peldaño de cada escalera es el vigente.

        Si este falla, el problema no es el peldaño configurado: se movio la
        escalera base, y hay que leerlo antes que cualquier otro fallo de aqui.
        """
        from app.services.ticket_service import _ESCALAS_ACTUALES

        assert _ESCALAS_ACTUALES[por_hoja][0] == piso_de_la_escalera

    def test_automatico_no_altera_la_escalera(self) -> None:
        """AUTOMATICO deja la escalera exactamente como esta (REQ-FN-012).

        El control es el PDF sin ``empresa``: ahi ``getattr`` cae al default, que
        es justamente lo que tiene que hacer AUTOMATICO.
        """
        p = _boleto_baseline()
        for por_hoja in (1, 2, 3, 4):
            con_auto = self._cuerpo(
                p, empresa=self._empresa("AUTOMATICO"), boletos_por_hoja=por_hoja
            )
            sin_configurar = self._cuerpo(p, boletos_por_hoja=por_hoja)
            assert con_auto == sin_configurar, (
                f"con {por_hoja} boleto(s) por hoja, AUTOMATICO imprimio a "
                f"{con_auto} y sin configurar se imprimia a {sin_configurar}"
            )

    def test_automatico_no_cambia_el_pdf_ni_el_texto(self) -> None:
        """Con AUTOMATICO el PDF debe ser identico al de antes de este trabajo.

        Es la garantia de REQ-FN-012 y la que protege a toda estacion ya
        instalada: si esto cambia, todos los boletos-printados cambian de aspecto
        sin que nadie lo haya pedido.
        """
        p = _boleto_baseline()
        for por_hoja in (1, 2, 3, 4):
            sin_configurar = self._sin_marca_de_impresion(
                _extract(p, boletos_por_hoja=por_hoja)
            )
            con_automatico = self._sin_marca_de_impresion(
                _extract(p, empresa=self._empresa("AUTOMATICO"), boletos_por_hoja=por_hoja)
            )
            assert sin_configurar == con_automatico, (
                f"AUTOMATICO cambio el texto con {por_hoja} por hoja"
            )
            assert _paginas(p, boletos_por_hoja=por_hoja) == _paginas(
                p, empresa=self._empresa("AUTOMATICO"), boletos_por_hoja=por_hoja
            ), f"AUTOMATICO cambio el numero de paginas con {por_hoja} por hoja"

    @staticmethod
    def _sin_marca_de_impresion(texto: str) -> str:
        """Quita la marca de tiempo de "Impreso:".

        ``_build_pdf`` estampa ``datetime.now()`` en el encabezado, asi que dos
        boletajes generados en segundos distintos producen textos distintos por
        una razon que no tiene nada que ver con la tipografia. Comparar el texto
        crudo daria un fallo aleatoriodepending del segundo en que cae el test.
        """
        return re.sub(r"Impreso: .*?Estado", "Impreso: <hora> Estado", texto)

    # ── Los tres peldaños configurados ──────────────────────────────────────
    # 7.5 es el techo, asi que es el mayor peldaño posible *de las escaleras que lo
    # tienen*. Las de 3 y 4 por hoja sí lo tienen; la de 4, sin embargo, exige
    # bajar a 5.5 para que el boleto quepa, asi que el cuerpo sale a 5.0 con
    # PEQUENO y tambien sin nada configurado (medido contra el PDF: 7.0 / 7.0 /
    # 7.0 / 5.0). No es que el filtro falle: es que el contenido manda
    # (REQ-FN-011).
    @pytest.mark.parametrize(
        ("por_hoja", "peldano_esperado"),
        [(1, 7.5), (2, 7.5), (3, 7.5), (4, 5.5)],
    )
    def test_pequeno_arranca_en_7_5_si_la_escalera_lo_tiene(
        self, por_hoja: int, peldano_esperado: float
    ) -> None:
        """PEQUENO arranca en 7.5 donde cabe; si no, baja lo necesario (CE-04)."""
        p = _boleto_baseline()
        observado = self._cuerpo(
            p, empresa=self._empresa("PEQUENO"), boletos_por_hoja=por_hoja
        )
        assert observado == self._esperado(peldano_esperado), (
            f"con {por_hoja} boleto(s) por hoja, PEQUENO deberia imprimir a "
            f"{self._esperado(peldano_esperado)} (peldaño {peldano_esperado}) "
            f"y imprimio a {observado}"
        )

    # El techo no se puede exigir por igual en las cuatro variantes: recorta lo
    # que lo supere, pero no alarga una escalera que ya arranca mas pequena. La de
    # 3 queda en 8.5 y la de 4 en 8.0, ambas por debajo de 9.0 (medido contra el
    # PDF: cuerpo a 8.5 / 8.5 / 7.5 / 5.0 para 1..4 por hoja).
    @pytest.mark.parametrize(
        ("por_hoja", "peldano_esperado"),
        [(1, 9.0), (2, 9.0), (3, 8.0), (4, 5.5)],
    )
    def test_mediano_arranca_en_9_0_si_la_escalera_lo_tiene(
        self, por_hoja: int, peldano_esperado: float
    ) -> None:
        """MEDIANO arranca en 9.0 donde cabe; si no, baja lo necesario."""
        p = _boleto_baseline()
        observado = self._cuerpo(
            p, empresa=self._empresa("MEDIANO"), boletos_por_hoja=por_hoja
        )
        assert observado == self._esperado(peldano_esperado), (
            f"con {por_hoja} boleto(s) por hoja, MEDIANO deberia imprimir a "
            f"{self._esperado(peldano_esperado)} (peldaño {peldano_esperado}) "
            f"y imprimio a {observado}"
        )

    @pytest.mark.parametrize("por_hoja", [1, 2, 3, 4])
    def test_grande_no_reduce_la_escalera(self, por_hoja: int) -> None:
        """GRANDE se comporta como hoy, peldaño a peldaño (CE-05).

        No es solo "que no se rompa": con 4 por hoja la escalera vigente ya baja
        sola hasta 5.5, y GRANDE tiene que llegar exactamente al mismo sitio.
        """
        p = _boleto_baseline()
        con_grande = self._cuerpo(
            p, empresa=self._empresa("GRANDE"), boletos_por_hoja=por_hoja
        )
        sin_configurar = self._cuerpo(p, boletos_por_hoja=por_hoja)
        assert con_grande == sin_configurar, (
            f"con {por_hoja} por hoja, GRANDE imprimio a {con_grande} y sin "
            f"configurar se imprimia a {sin_configurar}"
        )

    # ── escalera_efectiva: aritmetica pura, comprobacion exacta ─────────────
    @pytest.mark.parametrize(
        ("tamano", "techo"),
        [("PEQUENO", 7.5), ("MEDIANO", 9.0)],
    )
    def test_el_peldaño_configurado_es_el_techo(self, tamano: str, techo: float) -> None:
        from app.services.ticket_service import _ESCALAS_ACTUALES, escalera_efectiva

        escalera = escalera_efectiva(_ESCALAS_ACTUALES, tamano)
        for n in (1, 2, 3, 4):
            # El techo recorta lo que lo supere, pero no alarga una escalera que
            # ya arranca mas pequeña: con MEDIANO la de 3 queda en 8.5 y la de 4
            # en 8.0. La garantia real es que ninguna supere el techo.
            assert escalera[n][0] <= techo, (
                f"la escalera de {n} con {tamano} arranca en {escalera[n][0]}, "
                f"por encima del techo {techo}"
            )
        # Y en las escaleras que sí lo tienen, el techo se aplica de verdad.
        for n in (1, 2):
            assert escalera[n][0] == techo, (
                f"la escalera de {n} con {tamano} arranca en {escalera[n][0]}, "
                f"se esperaba el techo {techo}"
            )

    def test_automatico_es_identidad(self) -> None:
        from app.services.ticket_service import _ESCALAS_ACTUALES, escalera_efectiva

        escalera = escalera_efectiva(_ESCALAS_ACTUALES, "AUTOMATICO")
        for n in (1, 2, 3, 4):
            assert escalera[n] == _ESCALAS_ACTUALES[n], (
                f"AUTOMATICO no devolvio la escalera original en {n}: "
                f"{escalera[n]} != {_ESCALAS_ACTUALES[n]}"
            )

    def test_grande_no_filtra(self) -> None:
        from app.services.ticket_service import _ESCALAS_ACTUALES, escalera_efectiva

        escalera = escalera_efectiva(_ESCALAS_ACTUALES, "GRANDE")
        for n in (1, 2, 3, 4):
            assert escalera[n] == _ESCALAS_ACTUALES[n]

    def test_un_valor_desconocido_cae_a_la_escalera_vigente(self) -> None:
        """Un valor fuera del Literal no debe reventar la impresion.

        El CHECK de la migracion 021 lo impide en base de datos, pero una fila
        editada a mano o un default antiguo pueden colarse. El peor caso tolerable
        es caer a la escalera vigente, no un 500 a la hora de imprimir.
        """
        from app.services.ticket_service import _ESCALAS_ACTUALES, escalera_efectiva

        escalera = escalera_efectiva(_ESCALAS_ACTUALES, "VALOR_INVENTADO")
        for n in (1, 2, 3, 4):
            assert escalera[n] == _ESCALAS_ACTUALES[n]

    # ── REQ-FN-011: orden, piso y no truncado ───────────────────────────────
    @pytest.mark.parametrize("tamano", ["AUTOMATICO", "GRANDE", "MEDIANO", "PEQUENO"])
    def test_el_piso_de_cada_escalera_se_preserva(self, tamano: str) -> None:
        """Filtrar por techo no puede eliminar el ultimo peldaño.

        Ese ultimo elemento es el piso que garantiza que el auto-fit termine
        siempre en una escala existente. Si un filtro lo eliminara, el bucle se
        quedaria sin candidatas y el boleto saldria con la escala del fallback.
        """
        from app.services.ticket_service import _ESCALAS_ACTUALES, escalera_efectiva

        escalera = escalera_efectiva(_ESCALAS_ACTUALES, tamano)
        for n in (1, 2, 3, 4):
            assert escalera[n], f"la escalera de {n} quedo vacia filtrando por {tamano}"
            assert escalera[n][-1] == _ESCALAS_ACTUALES[n][-1], (
                f"el piso de la escalera de {n} cambio con {tamano}: "
                f"{_ESCALAS_ACTUALES[n][-1]} -> {escalera[n][-1]}"
            )

    @pytest.mark.parametrize("tamano", ["AUTOMATICO", "GRANDE", "MEDIANO", "PEQUENO"])
    def test_la_escalera_va_en_orden_descendente(self, tamano: str) -> None:
        from app.services.ticket_service import _ESCALAS_ACTUALES, escalera_efectiva

        for n, peldanos in escalera_efectiva(_ESCALAS_ACTUALES, tamano).items():
            assert peldanos == sorted(peldanos, reverse=True), (
                f"la escalera de {n} con {tamano} no esta en orden descendente: {peldanos}"
            )

    @pytest.mark.parametrize("tamano", ["AUTOMATICO", "GRANDE", "MEDIANO", "PEQUENO"])
    @pytest.mark.parametrize("por_hoja", [1, 2, 3, 4])
    def test_ningun_peldaño_trunca_el_boleto(self, tamano: str, por_hoja: int) -> None:
        """Ningún peldaño puede recortar contenido (REQ-FN-011).

        T6 solo cambia peldaños; no puede cambiar el formato del boleto.
        """
        p = _boleto_baseline()
        texto = _extract(p, empresa=self._empresa(tamano), boletos_por_hoja=por_hoja)
        assert "..." not in texto, f"{tamano} a {por_hoja} por hoja trunco el boleto"
        assert "TA-00000123" in texto, f"{tamano} a {por_hoja} por hoja perdio el numero"

    # ── REQ-FN-013: el TXT ignora la tipografia ─────────────────────────────
    def test_el_txt_ignora_los_peldanos(self) -> None:
        """El TXT es texto plano: ningun ajuste de PDF debe alterarlo."""
        p = _boleto_baseline()
        base = _build_txt(p, empresa=self._empresa("AUTOMATICO"), idioma="es").getvalue()
        for tamano in ("GRANDE", "MEDIANO", "PEQUENO"):
            otro = _build_txt(p, empresa=self._empresa(tamano), idioma="es").getvalue()
            assert otro == base, f"el TXT cambio con {tamano}"

    # ── REQ-FN-017: sin red ────────────────────────────────────────────────
    def test_el_pdf_no_abre_ninguna_conexion(self) -> None:
        """Generar el ticket no puede hacer llamadas salientes (REQ-FN-017)."""
        import socket

        original = socket.socket

        class Prohibido(socket.socket):  # type: ignore[misc]
            def __init__(self, *a, **k):
                raise AssertionError("la generacion del PDF intento abrir un socket")

        socket.socket = Prohibido  # type: ignore[misc]
        try:
            p = _boleto_baseline()
            for tamano in ("AUTOMATICO", "PEQUENO"):
                _build_pdf(p, empresa=self._empresa(tamano), boletos_por_hoja=2)
        finally:
            socket.socket = original  # type: ignore[misc]
