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

from app.models import BoletoPesaje, Kardex
from app.services.ticket_service import (
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

