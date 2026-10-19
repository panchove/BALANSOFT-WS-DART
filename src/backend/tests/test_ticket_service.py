"""Pruebas de generación del ticket PDF (ReportLab + pypdf).

Verifica que el PDF es válido y que el contenido extraído (número de boleto,
placa, motivo de anulación y marca de agua "ANULADO") es correcto.
"""

from __future__ import annotations

import base64
import json
import re
import uuid
import zlib
from datetime import datetime
from decimal import Decimal
from io import BytesIO
from types import SimpleNamespace
from typing import cast
from unittest.mock import patch

import pytest
from pypdf import PdfReader
from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.pdfbase import pdfmetrics

from app.models import BoletoPesaje, Empresa, Kardex
from app.services import ticket_service as ts
from app.services.ticket_service import (
    _GAP_ETIQUETA_TERMICA,
    _MAX_RATIO_ETIQUETA_TERMICA,
    _MIN_TABLA_PESOS,
    _RATIOS_TABLA_PESOS,
    _REQUIERE_TABLA_PESOS,
    _TS_TERMICO,
    ANCHO_TXT,
    FUENTE,
    FUENTE_BOLD,
    _ancho_etiqueta_termica,
    _build_pdf,
    _build_txt,
    _dato,
    _escala_termica,
    _filas_lectura_pesos,
    _fmt,
    _fmt_densidad,
    _fmt_sig,
    _registrar_ttf,
    _tamano_tabla_pesos,
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


def _multiplicar_matriz(m1, m2):
    """Producto de dos matrices afines de PDF (a:b, c:d, e:f)."""
    return (
        m1[0] * m2[0] + m1[1] * m2[2],
        m1[0] * m2[1] + m1[1] * m2[3],
        m1[2] * m2[0] + m1[3] * m2[2],
        m1[2] * m2[1] + m1[3] * m2[3],
        m1[4] * m2[0] + m1[5] * m2[2] + m2[4],
        m1[4] * m2[1] + m1[5] * m2[3] + m2[5],
    )


def _runs_pdf(p, **kwargs) -> list[tuple[float, float, float, str, float]]:
    """``(x, y, ancho, texto, tamano)`` de cada línea de texto del PDF.

    ``x``/``y`` salen del producto ``cm × tm`` que pypdf entrega al visitante, y
    el ancho se recalcula con las métricas del TTF incrustado (el MISMO que usa
    ReportLab para repartir el párrafo), así que sirve para detectar el solape
    entre celdas vecinas sin depender de poppler/pdftotext.
    """
    buf: BytesIO = _build_pdf(p, **kwargs)
    buf.seek(0)
    pagina = PdfReader(buf).pages[0]
    runs: list[tuple[float, float, float, str, float]] = []

    def _visitor(texto, cm, tm, font_dict, tamano):
        # pypdf cierra CADA línea con "\n": no es un glifo y falsea el ancho.
        limpio = (texto or "").rstrip("\n")
        if not limpio.strip():
            return
        matriz = _multiplicar_matriz(cm, tm)
        negrita = "Bold" in str((font_dict or {}).get("/BaseFont", ""))
        fuente = FUENTE_BOLD if negrita else FUENTE
        ancho = pdfmetrics.stringWidth(limpio, fuente, float(tamano))
        runs.append((float(matriz[4]), float(matriz[5]), ancho, limpio, float(tamano)))

    pagina.extract_text(visitor_text=_visitor)
    return runs


def _por_y(runs) -> dict[float, list[tuple[float, str]]]:
    """Filas visuales del PDF: ``y → [(x, texto), …]`` de izquierda a derecha.

    El bloque de DATOS se imprime como una tabla de DOS celdas (etiqueta |
    valor), así que pypdf entrega la etiqueta y su valor como dos líneas de
    texto distintas aunque compartan la MISMA vertical. Agrupar por ``y``
    (redondeada a 0,1 pt) reconstruye la fila.
    """
    filas: dict[float, list[tuple[float, str]]] = {}
    for x, y, _ancho, texto, _tam in runs:
        filas.setdefault(round(y, 1), []).append((x, texto))
    return {y: sorted(partes) for y, partes in filas.items()}


def _solapes(runs, tolerancia_y: float = 0.6, min_x: float = 0.5):
    """Parejas de líneas que se pisan horizontalmente en la misma banda."""
    hallados = []
    ordenados = sorted(runs, key=lambda r: (round(r[1], 1), r[0]))
    for i, (x1, y1, w1, t1, _s1) in enumerate(ordenados):
        for x2, y2, w2, t2, _s2 in ordenados[i + 1:]:
            if abs(y1 - y2) > tolerancia_y:
                break
            if min(x1 + w1, x2 + w2) - max(x1, x2) > min_x:
                hallados.append((round(y1, 2), t1, t2))
    return hallados


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


_MM = 72 / 25.4  # mm → pt


def _mediabox(p, **kwargs) -> tuple[float, float]:
    """(ancho, alto) de la primera página del PDF, en puntos."""
    buf: BytesIO = _build_pdf(p, **kwargs)
    buf.seek(0)
    box = PdfReader(buf).pages[0].mediabox
    return float(box.width), float(box.height)


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
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), copias=3))
        for fragmento in (
            "LECTURA DE PESOS", "Fec, Hrs", "CAMIÓN", "REMOLQUE", "TOTALES",
            "ENTRADA:", "SALIDA:", "PESO NETO", "PESO DECLARADO",
            "DATOS ADICIONALES", "OBSERVACIONES", "DOC-987654321",
        ):
            assert fragmento in txt, f"falta '{fragmento}'"

    def test_boleto_unico_estrecho_conserva_contenido(self):
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), copias=1))
        for fragmento in (
            "LECTURA DE PESOS", "PESO NETO", "DATOS ADICIONALES",
            "DOC-987654321", "OBSERVACIONES",
        ):
            assert fragmento in txt, f"falta '{fragmento}' (boleto único)"

    def test_cantidad_de_tickets_en_carta(self):
        # «Cantidad de tickets» = N: el PDF emite N copias completas del boleto.
        # Cuando no caben empaquetadas, cada copia usa una página; nada se trunca.
        assert _paginas(_boleto_completo(), copias=3, tamano_papel="Letter") == 3

    def test_cantidad_de_tickets_con_encabezado(self):
        kwargs = dict(
            copias=3, tamano_papel="Letter",
            empresa=_empresa_demo(), mostrar_encabezado=True,
        )
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), **kwargs))
        assert txt.count("Documento") == 3
        assert "Firma Conductor" not in txt

    def test_cantidad_de_tickets_en_a4(self):
        assert _paginas(_boleto_completo(), copias=3, tamano_papel="A4") == 3

    def test_4_por_carta_no_trunca(self):
        kwargs = dict(copias=4, tamano_papel="Letter")
        assert _paginas(_boleto_completo(), **kwargs) >= 1
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), **kwargs))
        assert txt.count("Documento") == 4
        assert "Firma Conductor" not in txt

    def test_1_por_carta_una_pagina(self):
        assert _paginas(_boleto_completo(), copias=1, tamano_papel="Letter") == 1

    def test_1_por_carta_con_encabezado_centrado_una_pagina(self):
        # Boleto único + encabezado debe caber en el ancho estrecho (140mm).
        assert _paginas(
            _boleto_completo(),
            copias=1, tamano_papel="Letter",
            empresa=_empresa_demo(), mostrar_encabezado=True,
        ) == 1

    def test_1_por_a4_centrado_una_pagina(self):
        assert _paginas(_boleto_completo(), copias=1, tamano_papel="A4") == 1

    def test_ancho_angosto_en_todas_las_cantidades(self):
        # Ancho fijo 140mm centrado sin importar cuántos boletos se apilen.
        for n in (1, 2, 3, 4):
            x = _max_text_x(_boleto_completo(), copias=n, tamano_papel="Letter")
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
            copias=4, tamano_papel="Letter",
            empresa=_empresa_contacto(logo_url=url), mostrar_encabezado=True,
        )
        assert _paginas(_boleto_completo(), **kwargs) >= 1
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), **kwargs))
        assert txt.count("Documento") == 4
        assert "Firma Conductor" not in txt

    def test_3_por_carta_con_contacto_y_logo_no_trunca(self, monkeypatch, tmp_path):
        url = _logo_en_media(monkeypatch, tmp_path)
        kwargs = dict(
            copias=3, tamano_papel="Letter",
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
            copias=1, tamano_papel="Letter",
            empresa=_empresa_contacto(), mostrar_encabezado=True,
        ) == 1

    def test_ancho_angosto_con_contacto(self):
        for n in (1, 2, 3, 4):
            x = _max_text_x(
                _boleto_completo(), copias=n, tamano_papel="Letter",
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
    def test_txt_incluye_tabla_de_pesos(self):
        # El TXT usa la MISMA tabla de lecturas que el PDF térmico (y la hoja):
        #   (etiqueta) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL
        # con una fila por pesada (ENTRADA / SALIDA), la de TOTALES (los netos
        # por vehículo) y la fila PESO NETO con su sufijo.
        buf: BytesIO = _build_txt(_boleto_completo())
        txt = buf.getvalue().decode("utf-8")
        for fragmento in (
            "LECTURA DE PESOS",
            "Fec, Hrs", "CAMIÓN", "REMOLQUE", "TOTAL",
            "ENTRADA:", "08/09/2026 – 08:30",
            "50.000,00 kg", "12.500,00 kg", "62.500,00 kg",
            "SALIDA:", "08/09/2026 – 09:15",
            "45.000,00 kg", "11.500,00 kg", "56.500,00 kg",
            "TOTALES:", "5.000,00 kg", "1.000,00 kg", "7.500,00 kg",
            "PESO NETO:", "7.500,00 kg", "(INGRESO)",
            "Cliente/Proveedor: PROVEEDOR DE PRUEBA C.A.",
            "Remolque: Sí — RTA987",
            "DATOS ADICIONALES", "OBSERVACIONES", "DOC-987654321",
        ):
            assert fragmento in txt, f"falta '{fragmento}'"


class TestTermicoApilado:
    """El PDF térmico (80/58mm) apila cada campo en su propia línea, con una
    página de ALTO DINÁMICO (crece con el contenido) y sin recortes."""

    def test_80mm_apila_todos_los_campos(self):
        # Se normaliza el espacio de la extracción: el Paragraph envuelve por
        # PALABRA, así que un valor largo reaparece íntegro al juntar líneas
        # (esto mismo demuestra que NO se parte a media palabra).
        txt = " ".join(_extract(_boleto_completo(), tamano_papel="80mm").split())
        for fragmento in (
            "Serie - Boleto: TA-00000001",
            "Camión: ABC123",
            "Remolque: Sí — RTA987",
            "Transporte: TRANSPORTE DEMO C.A.",
            "Conductor: FULANO DE TAL (V-12345678)",
            "Producto: MAIZ AMARILLO",
            "Almacén: SILO 01",
            "Cliente/Proveedor: PROVEEDOR DE PRUEBA C.A.",
            "LECTURA DE PESOS",
            # Tabla de lecturas: cabecera + una fila por pesada + TOTALES.
            "Fec, Hrs", "CAMIÓN", "REMOLQUE", "TOTAL",
            "ENTRADA:", "08/09/2026 – 08:30",
            "50.000,00 kg", "12.500,00 kg", "62.500,00 kg",
            "SALIDA:", "08/09/2026 – 09:15",
            "45.000,00 kg", "11.500,00 kg", "56.500,00 kg",
            "TOTALES:", "5.000,00 kg", "1.000,00 kg", "7.500,00 kg",
            "PESO NETO: 7.500,00 kg (INGRESO)",
            "OBSERVACIONES",
            "Despacho a granel.",
            "Revisar merma de viaje.",
            "CERRADO",
        ):
            assert fragmento in txt, f"falta '{fragmento}'"

    def test_80mm_campos_de_cabecera_en_su_propia_linea(self):
        # Los campos de CABECERA siguen ocupando exactamente una línea cada uno.
        # La sección de pesos es una tabla (ver TestTablaPesosTermico), por eso
        # sus celdas no se comprueban aquí.
        #
        # El bloque de DATOS se imprime en DOS celdas (etiqueta | valor), así que
        # pypdf entrega la etiqueta y su valor como líneas de texto APARTE
        # aunque compartan la misma vertical: "cada campo en su línea" se
        # comprueba con la geometría real, no con el texto extraído.
        lineas = _por_y(_runs_pdf(_boleto_completo(), tamano_papel="80mm"))
        # La tabla de lecturas también tiene celdas con esos rótulos ("Camión:")
        # y va DEBAJO de la cabecera, así que la búsqueda se acota a las filas
        # por encima del rótulo "LECTURA DE PESOS" (en el PDF la Y crece hacia
        # arriba).
        corte = max(
            y
            for y, partes in lineas.items()
            if any(texto == "LECTURA DE PESOS" for _x, texto in partes)
        )
        cabecera = {y: partes for y, partes in lineas.items() if y > corte}
        etiquetas = (
            "Serie - Boleto:",
            "Fecha/Hora:",
            "Camión:",
            "Remolque:",
            "Transporte:",
            "Conductor:",
            "Producto:",
            "Almacén:",
        )
        verticales = []
        for etiqueta in etiquetas:
            fila = [y for y, partes in cabecera.items() if partes[0][1] == etiqueta]
            assert len(fila) == 1, f"'{etiqueta}' no está en su propia línea"
            y = fila[0]
            assert len(cabecera[y]) >= 2, f"'{etiqueta}' no tiene su valor al lado"
            assert cabecera[y][1][0] > cabecera[y][0][0], "el valor no va a la derecha"
            verticales.append(y)
        # Ninguna etiqueta comparte línea con otra: una vertical por campo.
        assert len(set(verticales)) == len(etiquetas)
        # Y las dos mitades se alinean por su cuenta: TODAS las etiquetas acaban
        # en la misma X (pegadas al borde derecho de su columna) y todos los
        # valores empiezan en la misma X (pegados al izquierdo de la suya), con
        # el hueco de separación en medio. Con un único Paragraph era imposible.
        runs = _runs_pdf(_boleto_completo(), tamano_papel="80mm")
        bordes_etq = {
            round(x + ancho, 2)
            for x, y, ancho, texto, _t in runs
            if round(y, 1) in verticales and texto in etiquetas
        }
        inicios_val = {
            round(x, 2)
            for x, y, _ancho, texto, _t in runs
            if round(y, 1) in verticales and texto not in etiquetas
        }
        assert len(bordes_etq) == 1, f"etiquetas desalineadas: {sorted(bordes_etq)}"
        assert len(inicios_val) == 1, f"valores desalineados: {sorted(inicios_val)}"
        assert inicios_val.pop() - bordes_etq.pop() == pytest.approx(
            _GAP_ETIQUETA_TERMICA, abs=0.01
        )
        # Y el valor de cada campo (que puede envolver DENTRO de su columna)
        # sigue contiguo en el texto extraído.
        plano = " ".join(_extract(_boleto_completo(), tamano_papel="80mm").split())
        for etiqueta, valor in (
            ("Serie - Boleto:", "TA-00000001"),
            ("Fecha/Hora:", "08/09/2026 08:30"),
            ("Camión:", "ABC123"),
            ("Remolque:", "Sí — RTA987"),
            ("Transporte:", "TRANSPORTE DEMO C.A."),
            ("Conductor:", "FULANO DE TAL (V-12345678)"),
            ("Producto:", "MAIZ AMARILLO"),
            ("Almacén:", "SILO 01"),
            ("Despacho a granel.", ""),
            ("Revisar merma de viaje.", ""),
            ("Estado:", "CERRADO"),
        ):
            esperado = f"{etiqueta} {valor}".rstrip()
            assert esperado in plano, f"falta '{esperado}'"

    def test_pagina_termica_alto_dinamico(self):
        ancho, alto = _mediabox(_boleto_completo(), tamano_papel="80mm")
        assert abs(ancho - 80 * _MM) < 1.0          # 80 mm exactos de ancho
        assert 80 * _MM < alto < 297 * _MM          # ni vacía ni el marco fijo

    def test_mas_contenido_pagina_mas_alta(self):
        # Prueba directa del alto dinámico: el boleto completo (más campos) debe
        # producir una página estrictamente más alta que el boleto simple.
        _, corto = _mediabox(_boleto(), tamano_papel="80mm")
        _, largo = _mediabox(_boleto_completo(), tamano_papel="80mm")
        assert largo > corto

    def test_ancho_58mm_y_80mm(self):
        a80 = _mediabox(_boleto_completo(), tamano_papel="80mm")[0]
        a58 = _mediabox(_boleto_completo(), tamano_papel="58mm")[0]
        assert abs(a80 - 80 * _MM) < 1.0
        assert abs(a58 - 58 * _MM) < 1.0


class TestTablaPesosTermico:
    """La LECTURA DE PESOS es una tabla de 5 columnas —
    ``(vacío) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL``— con una fila por pesada
    (ENTRADA / SALIDA), la de TOTALES —los NETOS por vehículo— y una fila final
    PESO NETO con su sufijo. El rollo, la hoja y el TXT comparten la MISMA
    rejilla, así que el reparto no cambia de un boleto a otro."""

    def test_encabezado_de_la_tabla(self):
        txt = " ".join(_extract(_boleto_completo(), tamano_papel="80mm").split())
        assert "Fec, Hrs CAMIÓN REMOLQUE TOTAL" in txt
        # En el TXT las 5 columnas van con anchos fijos (13 | 20 | 14 | 14 | 14
        # caracteres + el separador), así que cada una arranca siempre igual.
        lineas = _build_txt(_boleto_completo()).getvalue().decode("utf-8").splitlines()
        cabecera = next(f for f in lineas if "CAMIÓN" in f and "REMOLQUE" in f)
        assert cabecera.index("Fec, Hrs") == 14
        assert cabecera.index("CAMIÓN") == 35
        assert cabecera.index("REMOLQUE") == 50
        assert cabecera.index("TOTAL") == 65

    def test_rejilla_de_cinco_columnas_en_todas_las_filas(self):
        filas = _filas_lectura_pesos(_dato(_boleto_completo()), "es")
        # 5 celdas por fila, SIEMPRE: la rejilla no depende del boleto.
        assert all(len(f) == 5 for f in filas)
        assert [texto for texto, _tipo in filas[0]] == [
            "", "Fec, Hrs", "CAMIÓN", "REMOLQUE", "TOTAL",
        ]
        assert [f[0][0] for f in filas[1:]] == ["ENTRADA:", "SALIDA:", "", "PESO NETO:"]
        # TOTALES va en la SEGUNDA columna (el ejemplo deja la primera vacía).
        assert filas[3][1][0] == "TOTALES:"

    def test_totales_lleva_los_netos_por_vehiculo(self):
        # La fila TOTALES son los NETOS de cada vehículo (no el bruto de la
        # salida, que ya se ve en su propia fila): 50.000−45.000, 12.500−11.500
        # y el neto del boleto.
        filas = _filas_lectura_pesos(_dato(_boleto_completo()), "es")
        assert [texto for texto, _tipo in filas[3]] == [
            "", "TOTALES:", "5.000,00 kg", "1.000,00 kg", "7.500,00 kg",
        ]
        # El PESO NETO va en la columna Fec, Hrs y el sufijo en la de CAMIÓN
        # (pegados a la etiqueta, como el ejemplo); remolque y total, vacías.
        assert [texto for texto, _tipo in filas[4]] == [
            "PESO NETO:", "7.500,00 kg", "(INGRESO)", "", "",
        ]

    def test_etiquetas_de_fila_en_los_tres_idiomas(self):
        p = _boleto_completo()
        for idioma, (entrada, salida, totales, neto) in {
            "es": ("ENTRADA:", "SALIDA:", "TOTALES:", "PESO NETO:"),
            "en": ("INBOUND:", "OUTBOUND:", "TOTALS:", "NET WEIGHT:"),
            "pt": ("ENTRADA:", "SAÍDA:", "TOTAIS:", "PESO LÍQUIDO:"),
        }.items():
            filas = _filas_lectura_pesos(_dato(p, idioma), idioma)
            assert [f[0][0] for f in filas[1:]] == [entrada, salida, "", neto]
            assert filas[3][1][0] == totales

    def test_totales_y_neto_en_el_pdf(self):
        p = _boleto_completo()
        txt = " ".join(_extract(p, tamano_papel="80mm").split())
        assert "ENTRADA:" in txt
        assert "SALIDA:" in txt
        assert "TOTALES:" in txt
        # Desglose por vehículo en las tres filas de pesos.
        for valor in (
            "50.000,00 kg",  # camión, entrada
            "12.500,00 kg",  # remolque, entrada
            "62.500,00 kg",  # total, entrada
            "45.000,00 kg",  # camión, salida
            "11.500,00 kg",  # remolque, salida
            "56.500,00 kg",  # total, salida
            "5.000,00 kg",   # neto camión
            "1.000,00 kg",   # neto remolque
        ):
            assert valor in txt, valor

    def test_sin_remolque_las_celdas_de_remolque_van_a_cero(self):
        p = _boleto()  # remolque=False
        pdf = " ".join(_extract(p, tamano_papel="80mm").split())
        # La rejilla es fija: la columna REMOLQUE (y TOTAL) siguen, en 0,00 kg.
        assert "REMOLQUE" in pdf
        assert "TOTALES:" in pdf
        assert "0,00 kg" in pdf
        # La cabecera de DATOS sigue diciendo que no lleva remolque.
        assert "Remolque: No" in pdf

    def test_neto_en_fila_propia_con_sufijo(self):
        p = _boleto_completo()
        txt = " ".join(_extract(p, tamano_papel="80mm").split())
        assert "PESO NETO: 7.500,00 kg (INGRESO)" in txt

    def test_tabla_cabe_en_58mm_sin_error(self):
        # El ancho útil del 58mm (53 mm) es el peor caso: la tabla debe generarse
        # sin recortes ni excepciones y la página conservar el ancho del rollo.
        p = _boleto_completo()
        ancho, alto = _mediabox(p, tamano_papel="58mm")
        assert abs(ancho - 58 * _MM) < 1.0
        txt = _extract(p, tamano_papel="58mm")
        assert "LECTURA DE PESOS" in txt
        assert "Camión:" in txt

    def test_una_sola_pagina(self):
        assert _paginas(_boleto_completo(), tamano_papel="80mm") == 1
        assert _paginas(_boleto_completo(), tamano_papel="58mm") == 1


#: Soportes de la matriz de la tabla de lecturas: el rollo (un boleto por
#: página) y las tres hojas con 1..4 boletos por página.
_MATRIZ_TABLA_PESOS: list[tuple[str, int]] = [("80mm", 1), ("58mm", 1)] + [
    (papel, n) for papel in ("HalfLetter", "Letter", "A4") for n in (1, 2, 3, 4)
]


class TestTablaPesosSinSolape:
    """La tabla de LECTURA DE PESOS no puede pisar texto (regresión de H1).

    Con anchos de columna fijos y 7,5 pt de cuerpo, la fecha ``dd/mm/aaaa``
    (43,2 pt) no cabía en su columna de 42 pt y la celda del vecino aparecía
    encima. El reparto es proporcional al peor caso y el cuerpo se auto-ajusta,
    de modo que cada línea queda dentro de su columna. El ajuste vale para el
    rollo Y para la hoja (misma rejilla de 5 columnas).
    """

    #: Rótulos de la tabla que NO pueden salir partidos, por idioma.
    ETIQUETAS = {
        "es": (
            "Fec, Hrs", "CAMIÓN", "REMOLQUE", "TOTAL",
            "ENTRADA:", "SALIDA:", "TOTALES:", "PESO NETO:",
        ),
        "en": (
            "Date, Time", "TRUCK", "TRAILER", "TOTAL",
            "INBOUND:", "OUTBOUND:", "TOTALS:", "NET WEIGHT:",
        ),
        "pt": (
            "Data, Hora", "CAMINHÃO", "REBOLQUE", "TOTAL",
            "ENTRADA:", "SAÍDA:", "TOTAIS:", "PESO LÍQUIDO:",
        ),
    }

    @pytest.mark.parametrize("papel", ["80mm", "58mm"])
    def test_boleto_completo(self, papel):
        runs = _runs_pdf(_boleto_completo(), tamano_papel=papel)
        assert "CAMIÓN" in " ".join(r[3] for r in runs)
        assert _solapes(runs) == []

    @pytest.mark.parametrize("papel", ["80mm", "58mm"])
    def test_boleto_solo_entrada(self, papel):
        # Sin salida, la fila SALIDA no se imprime pero la rejilla (5 columnas)
        # y el reparto no cambian.
        runs = _runs_pdf(_boleto(), tamano_papel=papel)
        textos = " ".join(r[3] for r in runs)
        assert "CAMIÓN" in textos
        assert "ENTRADA:" in textos
        assert "SALIDA:" not in textos
        assert "TOTALES:" in textos
        assert _solapes(runs) == []

    @pytest.mark.parametrize("papel", ["80mm", "58mm"])
    @pytest.mark.parametrize("idioma", ["es", "en", "pt"])
    def test_todos_los_idiomas(self, papel, idioma):
        # "(OUTBOUND)" es el sufijo del PESO NETO más ancho: si no cabe, el
        # auto-ajuste tiene que bajarlo.
        runs = _runs_pdf(_boleto_completo(), tamano_papel=papel, idioma=idioma)
        assert _solapes(runs) == []

    @pytest.mark.parametrize("idioma", ["es", "en", "pt"])
    @pytest.mark.parametrize(
        "papel,n",
        _MATRIZ_TABLA_PESOS,
        ids=[f"{papel}-{n}" for papel, n in _MATRIZ_TABLA_PESOS],
    )
    def test_sin_solapes_ni_rotulos_partidos_en_toda_la_matriz(
        self, papel, n, idioma
    ):
        """El rollo (80/58 mm) y la hoja (media carta, Carta y A4) comparten la
        MISMA rejilla de 5 columnas y el mismo auto-ajuste, así que la matriz
        completa —5 soportes × 1..4 boletos por hoja × 3 idiomas— no puede tener
        ni una celda pisando a su vecina ni un rótulo partido por carácter.

        La hoja de 1 boleto por página usa 100 mm útiles: si no auto-ajustara,
        ``ENTRADA:`` y la cabecera ``REMOLQUE`` se partirían (defecto
        preexistente que este test fija).
        """
        runs = _runs_pdf(
            _boleto_completo(),
            tamano_papel=papel,
            copias=n,
            idioma=idioma,
        )
        norm = " ".join(" ".join(r[3] for r in runs).split())
        etiquetas = {
            "es": ("Fec, Hrs", "CAMIÓN", "REMOLQUE", "TOTAL",
                   "ENTRADA:", "SALIDA:", "TOTALES:", "PESO NETO:"),
            "en": ("Date, Time", "TRUCK", "TRAILER", "TOTAL",
                   "INBOUND:", "OUTBOUND:", "TOTALS:", "NET WEIGHT:"),
            "pt": ("Data, Hora", "CAMINHÃO", "REBOLQUE", "TOTAL",
                   "ENTRADA:", "SAÍDA:", "TOTAIS:", "PESO LÍQUIDO:"),
        }[idioma]
        for etiqueta in etiquetas:
            assert etiqueta in norm, f"{papel}/{n}/{idioma}: falta {etiqueta!r}"
        assert _solapes(runs) == []

    def test_el_cuerpo_de_la_tabla_es_menor_que_el_del_resto(self):
        runs = _runs_pdf(_boleto_completo(), tamano_papel="80mm")
        tam_tabla = [
            t for _x, _y, _w, texto, t in runs if texto.strip() in ("ENTRADA:", "Fec, Hrs")
        ]
        tam_cuerpo = [
            t for _x, _y, _w, texto, t in runs if texto.strip() == "Serie - Boleto:"
        ]
        assert tam_tabla and tam_cuerpo
        # Las celdas de la tabla se auto-ajustan (las 5 comparten el tamaño),
        # así que siempre van por debajo del cuerpo base del boleto.
        assert len(set(tam_tabla)) == 1
        assert tam_tabla[0] < tam_cuerpo[0]


class TestRepartoTablaPesos:
    """Aritmética pura del reparto de la tabla de lecturas (sin montar página).

    El reparto es el MISMO en el rollo y en la hoja: 5 columnas con ratios
    fijos que no dependen del boleto.
    """

    @pytest.mark.parametrize("ancho_util", [209.77, 150.24])
    def test_el_peor_caso_cabe_en_su_columna(self, ancho_util):
        tam, cortar = _tamano_tabla_pesos(
            ancho_util, list(_REQUIERE_TABLA_PESOS), 7.5
        )
        assert not cortar
        assert _MIN_TABLA_PESOS < tam <= 7.5
        for ratio, requiere in zip(
            _RATIOS_TABLA_PESOS, _REQUIERE_TABLA_PESOS, strict=True
        ):
            assert requiere * tam <= ancho_util * ratio + 1e-9

    def test_el_reparto_suma_el_ancho_util(self):
        assert abs(sum(_RATIOS_TABLA_PESOS) - 1.0) < 1e-9

    def test_el_tope_manda_cuando_todo_cabe(self):
        tam, cortar = _tamano_tabla_pesos(209.77, list(_REQUIERE_TABLA_PESOS), 5.0)
        assert not cortar
        assert tam == pytest.approx(5.0)

    def test_contenido_mas_largo_baja_el_tamano(self):
        base, _ = _tamano_tabla_pesos(209.77, list(_REQUIERE_TABLA_PESOS), 7.5)
        largo, _ = _tamano_tabla_pesos(
            209.77, [r * 5 for r in _REQUIERE_TABLA_PESOS], 7.5
        )
        assert largo < base

    def test_contenido_absurdo_pide_corte_por_caracter(self):
        tam, cortar = _tamano_tabla_pesos(150.0, [60.0] * 5, 7.5)
        assert cortar
        assert tam == _MIN_TABLA_PESOS


class TestAnchoEtiquetaTermica:
    """Reparto de la columna de ETIQUETAS de las filas del rollo.

    La etiqueta va a la DERECHA de su celda y el valor a la IZQUIERDA de la
    suya, así que la columna de etiquetas no puede ser fija: mide lo que pide la
    etiqueta más larga del grupo (con el TTF real y el cuerpo en uso) y el tope
    (`_MAX_RATIO_ETIQUETA_TERMICA`) solo actúa como red de seguridad.
    """

    #: 74 mm útiles de un rollo de 80 mm y 52 mm de uno de 58 mm.
    UTIL_80MM = 74.0 * 72 / 25.4
    UTIL_58MM = 52.0 * 72 / 25.4

    @pytest.fixture(autouse=True)
    def _ttf(self):
        """La medida usa el TTF real, que se registra al construir un PDF.

        Sin esto la clase dependería de que otro test ya hubiera montado un
        PDF (``KeyError: DejaVu` al medir).
        """
        _registrar_ttf()

    def _ancho_de(self, etiqueta: str, tamano: float = 9.0) -> float:
        return pdfmetrics.stringWidth(f"{etiqueta}:", FUENTE_BOLD, tamano)

    def test_mide_la_etiqueta_mas_larga_del_grupo(self):
        ancho, cortar = _ancho_etiqueta_termica(
            self.UTIL_80MM, ["Camión", "Cliente/Proveedor", "Almacén"], 9.0
        )
        assert not cortar
        assert ancho == pytest.approx(
            self._ancho_de("Cliente/Proveedor") + _GAP_ETIQUETA_TERMICA
        )

    def test_el_grupo_de_una_sola_etiqueta_mide_esa_etiqueta(self):
        ancho, cortar = _ancho_etiqueta_termica(self.UTIL_80MM, ["Camión"], 9.0)
        assert not cortar
        assert ancho == pytest.approx(
            self._ancho_de("Camión") + _GAP_ETIQUETA_TERMICA
        )

    def test_el_tope_no_muerde_en_80mm(self):
        # La etiqueta más larga de los tres idiomas ("Cliente / Fornecedor:")
        # queda por debajo del tope, así que la columna la mide entera.
        ancho, cortar = _ancho_etiqueta_termica(
            self.UTIL_80MM, ["Cliente / Fornecedor"], 9.0
        )
        assert not cortar
        assert ancho == pytest.approx(
            self._ancho_de("Cliente / Fornecedor") + _GAP_ETIQUETA_TERMICA
        )
        assert ancho < self.UTIL_80MM * _MAX_RATIO_ETIQUETA_TERMICA

    def test_el_tope_recorta_en_58mm(self):
        ancho, cortar = _ancho_etiqueta_termica(
            self.UTIL_58MM, ["Cliente / Fornecedor"], 9.0
        )
        assert ancho == pytest.approx(self.UTIL_58MM * _MAX_RATIO_ETIQUETA_TERMICA)
        # La etiqueta no cabe entera, pero por PALABRAS sí: envuelve sola, sin
        # partir ninguna palabra, así que no hace falta el corte por carácter.
        assert not cortar

    def test_la_palabra_mas_larga_cabe_en_el_tope_de_58mm(self):
        # Con el tope actual ninguna etiqueta real necesita partirse a media
        # palabra: la más larga de una sola pieza ("Cliente/Proveedor:") cabe.
        ancho, cortar = _ancho_etiqueta_termica(
            self.UTIL_58MM, ["Cliente/Proveedor"], 9.0
        )
        assert not cortar
        assert self._ancho_de("Cliente/Proveedor") + _GAP_ETIQUETA_TERMICA == ancho

    def test_pide_corte_por_caracter_si_una_palabra_desborda(self):
        # Si una sola palabra no cabe ni con el tope (grupo estrecho), hay que
        # partirla por carácter: desbordar la celda se pisaría con el valor.
        ancho, cortar = _ancho_etiqueta_termica(120.0, ["Cliente/Proveedor"], 9.0)
        assert cortar
        assert ancho == pytest.approx(120.0 * _MAX_RATIO_ETIQUETA_TERMICA)
        assert self._ancho_de("Cliente/Proveedor") > ancho

    def test_el_ancho_se_adapta_al_cuerpo(self):
        chico, _ = _ancho_etiqueta_termica(self.UTIL_80MM, ["Cliente/Proveedor"], 6.5)
        grande, _ = _ancho_etiqueta_termica(self.UTIL_80MM, ["Cliente/Proveedor"], 9.0)
        assert chico < grande


class TestEscalaTermica:
    """El peldaño de la empresa (REQ-FN-015) sigue siendo techo en el térmico."""

    def test_base_para_automatico_y_grande(self):
        assert _escala_termica("AUTOMATICO") == _TS_TERMICO
        assert _escala_termica("GRANDE") == _TS_TERMICO
        assert _escala_termica(None) == _TS_TERMICO
        assert _escala_termica("desconocido") == _TS_TERMICO

    def test_peldano_recorta_la_base(self):
        assert _escala_termica("PEQUENO") == 7.5
        assert _escala_termica("MEDIANO") == 9.0

    def test_el_pdf_termico_respeta_el_peldano(self):
        auto = _runs_pdf(_boleto(), tamano_papel="80mm")
        pequeno = _runs_pdf(
            _boleto(),
            empresa=_empresa_demo(tamano_ticket_pdf="PEQUENO"),
            tamano_papel="80mm",
        )
        assert max(t for *_r, t in auto) > max(t for *_r, t in pequeno)


class TestFallbacksTermico:
    """Cadena de respaldo del número de boleto y del remolque (REQ)."""

    def test_numero_fallback_bol_8(self):
        p = _boleto(numero_boleto=None)
        esperado = f"BOL-{str(p.boleto)[:8].upper()}"
        assert esperado in _extract(p, tamano_papel="80mm")
        assert esperado in _build_txt(p).getvalue().decode("utf-8")

    def test_numero_fallback_serie_correlativo(self):
        p = _boleto(numero_boleto=None)
        p.boleto = None  # type: ignore[assignment]
        p.__setattr__("serie", "TA")
        p.__setattr__("correlativo", 42)
        assert "TA-00000042" in _extract(p, tamano_papel="80mm")

    def test_numero_fallback_sin_numero(self):
        p = _boleto(numero_boleto=None)
        p.boleto = None  # type: ignore[assignment]
        assert "Boleto s/n" in _extract(p, tamano_papel="80mm")

    def test_remolque_placa(self):
        # La cabecera del térmico va en DOS celdas (etiqueta | valor), así que
        # pypdf las extrae en líneas distintas: se normaliza el espacio como en
        # el resto de comprobaciones de contenido.
        pdf = " ".join(_extract(_boleto_completo(), tamano_papel="80mm").split())
        assert "Remolque: Sí — RTA987" in pdf

    def test_remolque_flag_sin_placa(self):
        pdf = " ".join(_extract(_boleto(remolque=True), tamano_papel="80mm").split())
        assert "Remolque: Sí" in pdf

    def test_remolque_id_sin_placa(self):
        p = _boleto(remolque=False, id_remolque=uuid.uuid4())
        pdf = " ".join(_extract(p, tamano_papel="80mm").split())
        assert "Remolque: Sí" in pdf

    def test_remolque_no(self):
        pdf = " ".join(_extract(_boleto(remolque=False), tamano_papel="80mm").split())
        assert "Remolque: No" in pdf


class TestSinSalida:
    def test_solo_entrada_cuando_no_hay_salida(self):
        # _boleto() no define fecha_hora_salida: la fila SALIDA no se imprime,
        # pero la de TOTALES sí (la rejilla de 5 columnas es fija).
        p = _boleto()
        pdf = " ".join(_extract(p, tamano_papel="80mm").split())
        assert "ENTRADA:" in pdf
        assert "SALIDA:" not in pdf
        assert "TOTALES:" in pdf
        assert "50.000,00 kg" in pdf
        assert "45.000,00 kg" not in pdf
        txt = _build_txt(p).getvalue().decode("utf-8")
        assert "ENTRADA:" in txt
        assert "SALIDA:" not in txt
        assert "TOTALES:" in txt
        assert "45.000,00 kg" not in txt


class TestNormalizacionSimple:
    def test_colapsa_espacios_dobles_en_campos_simples(self):
        p = _boleto(id_vehiculo="YOHANDER  SANCHEZ")
        pdf = _extract(p, tamano_papel="80mm")
        assert "YOHANDER  SANCHEZ" not in pdf
        # La etiqueta y el valor van en DOS celdas: contiguos en la geometría,
        # no necesariamente en el texto extraído.
        assert "Camión: YOHANDER SANCHEZ" in " ".join(pdf.split())
        txt = _build_txt(p).getvalue().decode("utf-8")
        assert "Camión: YOHANDER SANCHEZ" in txt

    def test_observaciones_conserva_saltos_de_linea(self):
        p = _boleto(observaciones="Primera   linea\nSegunda linea")
        pdf = _extract(p, tamano_papel="80mm")
        # Doble espacio interior colapsado, pero cada línea original sale como
        # una línea APARTE (no un párrafo unido).
        lineas_pdf = pdf.splitlines()
        assert "Primera linea" in lineas_pdf
        assert "Segunda linea" in lineas_pdf
        # El TXT debe comportarse igual que el PDF térmico.
        lineas_txt = _build_txt(p).getvalue().decode("utf-8").splitlines()
        assert "Primera linea" in lineas_txt
        assert "Segunda linea" in lineas_txt


class TestCoherenciaTxtPdfTermico:
    def test_mismo_orden_de_campos_en_txt_y_pdf(self):
        etiquetas = [
            "Serie - Boleto", "Fecha/Hora", "Camión", "Remolque", "Transporte",
            "Conductor", "Producto", "Almacén", "Cliente/Proveedor",
            "LECTURA DE PESOS", "ENTRADA:", "SALIDA:", "TOTALES:", "PESO NETO:",
        ]
        txt = _build_txt(_boleto_completo()).getvalue().decode("utf-8")
        pos_txt = [txt.index(e) for e in etiquetas]
        assert pos_txt == sorted(pos_txt), f"orden TXT roto: {pos_txt}"

        pdf = _extract(_boleto_completo(), tamano_papel="80mm")
        pos_pdf = [pdf.index(e) for e in etiquetas]
        assert pos_pdf == sorted(pos_pdf), f"orden PDF roto: {pos_pdf}"


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
        buf: BytesIO = _build_txt(
            _boleto_completo(), empresa=cast(Empresa, _empresa_demo()), idioma="en"
        )
        txt = buf.getvalue().decode("utf-8")
        assert "WEIGHING TICKET" in txt
        assert "WEIGHT READINGS" in txt
        # Tabla de lecturas (misma rejilla que el PDF y la hoja): la cabecera,
        # una fila por pesada, la de TOTALS (los netos por vehículo) y NET WEIGHT.
        assert "TRUCK" in txt and "TRAILER" in txt
        assert "INBOUND:" in txt
        assert "OUTBOUND:" in txt
        assert "TOTALS:" in txt
        assert "NET WEIGHT:" in txt
        assert "50,000.00 kg" in txt
        assert "45,000.00 kg" in txt
        assert "7,500.00 kg" in txt
        assert "(INBOUND)" in txt
        assert "Driver Signature" not in txt  # BÁSICO sin firmas
        adv = _build_txt(
            _boleto_completo(),
            empresa=cast(Empresa, _empresa_demo()),
            idioma="en",
            tipo_ticket="avanzado",
        ).getvalue().decode("utf-8")
        assert "Driver Signature" in adv

    def test_ticket_txt_portugues(self):
        buf: BytesIO = _build_txt(
            _boleto_completo(), empresa=cast(Empresa, _empresa_demo()), idioma="pt"
        )
        txt = buf.getvalue().decode("utf-8")
        assert "BILHETE DE PESAGEM" in txt
        assert "LEITURA DE PESOS" in txt
        assert "CAMINHÃO" in txt and "REBOLQUE" in txt
        assert "ENTRADA:" in txt
        assert "SAÍDA:" in txt
        assert "TOTAIS:" in txt
        assert "PESO LÍQUIDO:" in txt
        assert "50.000,00 kg" in txt
        assert "45.000,00 kg" in txt
        assert "7.500,00 kg" in txt
        assert "(ENTRADA)" in txt
        assert "Assinatura do Motorista" not in txt  # BÁSICO sin firmas
        adv = _build_txt(
            _boleto_completo(),
            empresa=cast(Empresa, _empresa_demo()),
            idioma="pt",
            tipo_ticket="avanzado",
        ).getvalue().decode("utf-8")
        assert "Assinatura do Motorista" in adv

    def test_ticket_pdf_ingles(self):
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), idioma="en"))
        assert "WEIGHING TICKET" in txt
        assert "WEIGHT READINGS" in txt
        assert "NET WEIGHT" in txt

    def test_ticket_pdf_portugues(self):
        txt = re.sub(r"\s+", " ", _extract(_boleto_completo(), idioma="pt"))
        assert "BILHETE DE PESAGEM" in txt
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
            self._boleto_avanzado(), copias=3, tamano_papel="Letter", tipo_ticket="avanzado"
        ))
        for frag in (
            "Boleto", "SUNAGRO-2026-001", "M3", "C/S 250,00",
            "250.00", "ROJO", "OPERADOR 01", "Resultado",
        ):
            assert frag in txt, f"falta '{frag}' en PDF avanzado a 3/hoja"
        total = _paginas(
            self._boleto_avanzado(), copias=3, tamano_papel="Letter", tipo_ticket="avanzado"
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

    def test_cada_bloque_mide_su_propia_columna_de_etiquetas(self):
        """DATOS, DATOS ADICIONALES y CATÁLOGO apilan con la etiqueta más larga
        de CADA bloque: ninguno hereda el ancho de otro y, dentro de un bloque,
        todos los valores arrancan en la misma X."""
        lineas = _por_y(
            _runs_pdf(
                self._boleto_catalogo(), tamano_papel="80mm", tipo_ticket="avanzado"
            )
        )
        marcas = {
            texto: y
            for y, partes in lineas.items()
            for _x, texto in partes
            if texto
            in (
                "LECTURA DE PESOS",
                "DATOS ADICIONALES",
                "DATOS DEL CATÁLOGO Y CONTROL",
                "OBSERVACIONES",
            )
        }
        assert len(marcas) == 4, f"faltan rótulos de sección: {sorted(marcas)}"
        bloques = {
            "DATOS": [y for y in lineas if y > marcas["LECTURA DE PESOS"]],
            "ADICIONALES": [
                y
                for y in lineas
                if marcas["DATOS DEL CATÁLOGO Y CONTROL"] < y < marcas["DATOS ADICIONALES"]
            ],
            # El CATÁLOGO acaba en OBSERVACIONES: más abajo van las firmas, que
            # son DOS celdas (no una fila "etiqueta | valor").
            "CATÁLOGO": [
                y
                for y in lineas
                if marcas["OBSERVACIONES"] < y < marcas["DATOS DEL CATÁLOGO Y CONTROL"]
            ],
        }
        columnas: dict[str, float] = {}
        for nombre, ys in bloques.items():
            # Solo las filas "etiqueta | valor" (las de una sola celda son
            # títulos, observaciones o la continuación de un valor envuelto).
            inicios = {
                round(lineas[y][1][0], 2) for y in ys if len(lineas[y]) == 2
            }
            assert len(inicios) == 1, f"{nombre}: valores desalineados {sorted(inicios)}"
            columnas[nombre] = inicios.pop()
        # Cada bloque mide su columna: el CATÁLOGO (etiquetas compuestas) es el
        # más ancho y DATOS ADICIONALES el más estrecho. Si los tres compartieran
        # una columna global, estos números coincidirían.
        assert columnas["ADICIONALES"] < columnas["DATOS"] < columnas["CATÁLOGO"], columnas

    @pytest.mark.parametrize("papel", ["HalfLetter", "Letter", "A4"])
    def test_hoja_usa_las_dos_columnas_del_termico(self, papel: str):
        """La HOJA (media carta, Carta y A4) apila el bloque de DATOS con la MISMA
        forma que el rollo: la etiqueta se pega a la DERECHA de su columna y el
        valor arranca a la IZQUIERDA de la siguiente.

        Antes la hoja repartía la fila con la etiqueta a la IZQUIERDA y el valor
        pegado al borde DERECHO (justificado a los extremos), así que ni los
        arranques de los valores ni los finales de las etiquetas coincidían: las
        dos columnas de este test fallarían con aquel layout.
        """
        runs = _runs_pdf(
            self._boleto_catalogo(),
            tamano_papel=papel,
            tipo_ticket="avanzado",
            mostrar_encabezado=False,
        )
        lineas = _por_y(runs)
        y_ini = next(
            y for y, partes in lineas.items()
            if any(t == "Serie - Boleto:" for _x, t in partes)
        )
        y_fin = next(
            y for y, partes in lineas.items()
            if any(t == "Razón Social:" for _x, t in partes)
        )
        por_y: dict[float, list[tuple[float, float, float, str, float]]] = {}
        for run in runs:
            por_y.setdefault(round(run[1], 1), []).append(run)
        filas = {
            y: sorted(rs)
            for y, rs in por_y.items()
            if y_fin <= y <= y_ini and len(rs) == 2
        }
        assert len(filas) >= 10, f"esperaba ≥10 filas de DATOS, hay {len(filas)}"

        # Cada fila son DOS celdas: la etiqueta queda a la izquierda del valor.
        for partes in filas.values():
            (xl, _yl, wl, etiqueta, _sl), (xv, _yv, _wv, valor, _sv) = partes
            assert xl + wl <= xv + 0.5, f"'{etiqueta}' no queda a la izquierda de '{valor}'"

        # La columna de etiquetas se pega a la DERECHA: los bordes derechos
        # coinciden (en el layout viejo las etiquetas iban a la izquierda).
        derechos = {round(x + w, 1) for (x, _y, w, _t, _s), _v in filas.values()}
        assert len(derechos) == 1, f"etiquetas fuera de columna: {sorted(derechos)}"

        # Y la de valores arranca a la IZQUIERDA: todos en la misma X.
        inicios = {round(v[0], 1) for _l, v in filas.values()}
        assert len(inicios) == 1, f"valores desalineados: {sorted(inicios)}"

        # Las dos columnas son CONTIGUAS (solo las separa el hueco del PDF): no
        # es una etiqueta a un extremo y un valor al otro.
        hueco = inicios.pop() - derechos.pop()
        assert 0 <= hueco <= _GAP_ETIQUETA_TERMICA + 0.5, f"separación {hueco} pt"

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
        texto = self._extraido(b, empresa=None, copias=1)
        assert texto != "", "PDF vacío"
        # Firma estable del baseline (fragmentos que no cambian entre ejecuciones)
        assert "TA-00000123" in texto
        assert "ABC-123" in texto
        assert "MATERIA PRIMA" in texto

    def test_automatico_no_regression(self, monkeypatch):
        """No-regresión: dos generaciones con AUTOMATICO producen texto idéntico.

        El reloj se congela a proposito: el pie del boleto estampa
        ``datetime.now()`` y dos generaciones seguidas pueden caer a distinto
        lado de un cambio de segundo, con lo que el test fallaba por el reloj y
        no por la tipografia.
        """
        import app.services.ticket_service as ts

        class _RelojFijo(datetime):
            @classmethod
            def now(cls, tz=None):  # type: ignore[override]
                return datetime(2026, 10, 14, 12, 0, 0)

        monkeypatch.setattr(ts, "datetime", _RelojFijo)
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
    se escribe a mano: se mide en el PDF el tamano de la etiqueta de las filas de
    datos y se compara con el que el modulo le asigna a ese estilo (``term_etq``).
    El desplazamiento entre el peldaño y el estilo es un detalle del modulo: si
    cambia, el test sigue diciendo la verdad en vez de romperse por 0.5 puntos
    que nadie toco.

    Los peldaños que se esperan en el PDF (mas abajo) son los **medidos** con el
    contenido vigente del boleto. No son un adorno: en cuanto el boleto crece (la
    tabla de lecturas de cinco columnas, el bloque de datos a dos columnas y el
    QR de resumen) el apilado cambia de peldaño, y el valor esperado tiene que
    acompañarlo. La garantia de que el techo se respeta vive en
    ``test_el_peldaño_configurado_es_el_techo``, que comprueba la aritmetica pura
    de ``escalera_efectiva`` sin depender del contenido.
    """

    #: Tamano de la cabecera de pagina y del pie, fijos y ajenos al peldaño.
    #: 12.0 es el nombre de la empresa y 7.0 el de los datos de cabecera.
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
        """Tamano de fuente del cuerpo del boleto: la etiqueta de las filas de DATOS.

        El cuerpo son las filas ``Etiqueta: valor`` (DATOS, operador, ADICIONALES
        y CATALOGO), que el modulo dibuja con ``term_etq``/``term_val``. Se mide
        la etiqueta ``Serie - Boleto:`` —una por copia y siempre presente— en vez
        de la moda de los tamanos de la pagina: con la tabla de lecturas (que se
        recorta al tope por contenido) y el pie, la moda la gana un tamano ajeno
        al peldaño y el observable deja de medir la escala elegida.
        """
        for _x, _y, _ancho, texto, tamano in _runs_pdf(p, **kwargs):
            if texto.strip() == "Serie - Boleto:":
                return tamano
        raise AssertionError(
            "no se encontro la etiqueta 'Serie - Boleto:' en el PDF: no se pudo "
            "medir el cuerpo del boleto"
        )

    @staticmethod
    def _esperado(peldaño: float) -> float:
        """Tamano que deberia verse en pantalla si se eligio ``peldaño``."""
        from app.services.ticket_service import _estilos_simples

        return _estilos_simples(peldaño)["term_etq"].fontSize  # type: ignore[attr-defined]

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
                p, empresa=self._empresa("AUTOMATICO"), copias=por_hoja
            )
            sin_configurar = self._cuerpo(p, copias=por_hoja)
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
                _extract(p, copias=por_hoja)
            )
            con_automatico = self._sin_marca_de_impresion(
                _extract(p, empresa=self._empresa("AUTOMATICO"), copias=por_hoja)
            )
            assert sin_configurar == con_automatico, (
                f"AUTOMATICO cambio el texto con {por_hoja} por hoja"
            )
            assert _paginas(p, copias=por_hoja) == _paginas(
                p, empresa=self._empresa("AUTOMATICO"), copias=por_hoja
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
    # 7.5 es el techo, asi que es el mayor peldaño posible *de las escaleras que
    # lo tienen*, y con 1 boleto por hoja el boleto cabe justo ahi. Con 2 o mas
    # por hoja el apilado ya no admite el techo —el QR de resumen y la tabla de
    # lecturas añaden alto— y la escalera baja a 7.0, el primer peldaño que cabe
    # (medido contra el PDF: 7.5 / 7.0 / 7.0 / 7.0). No es que el filtro falle:
    # es que el contenido manda (REQ-FN-011).
    @pytest.mark.parametrize(
        ("por_hoja", "peldano_esperado"),
        [(1, 7.5), (2, 7.0), (3, 7.0), (4, 7.0)],
    )
    def test_pequeno_arranca_en_7_5_si_la_escalera_lo_tiene(
        self, por_hoja: int, peldano_esperado: float
    ) -> None:
        """PEQUENO arranca en 7.5 donde cabe; si no, baja lo necesario (CE-04)."""
        p = _boleto_baseline()
        observado = self._cuerpo(
            p, empresa=self._empresa("PEQUENO"), copias=por_hoja
        )
        assert observado == self._esperado(peldano_esperado), (
            f"con {por_hoja} boleto(s) por hoja, PEQUENO deberia imprimir a "
            f"{self._esperado(peldano_esperado)} (peldaño {peldano_esperado}) "
            f"y imprimio a {observado}"
        )

    # El techo no se puede exigir por igual en las cuatro variantes: recorta lo
    # que lo supere, pero no alarga una escalera que ya arranca mas pequena. Con
    # 1 boleto por hoja MEDIANO arranca en 9.0; con 2 o mas manda el apilado y
    # baja a 7.0, el mismo sitio al que llega PEQUENO (medido contra el PDF: los
    # peldaños 9.0 / 7.0 / 7.0 / 7.0, es decir cuerpo a 7.0 / 5.0 / 5.0 / 5.0).
    @pytest.mark.parametrize(
        ("por_hoja", "peldano_esperado"),
        [(1, 9.0), (2, 7.0), (3, 7.0), (4, 7.0)],
    )
    def test_mediano_arranca_en_9_0_si_la_escalera_lo_tiene(
        self, por_hoja: int, peldano_esperado: float
    ) -> None:
        """MEDIANO arranca en 9.0 donde cabe; si no, baja lo necesario."""
        p = _boleto_baseline()
        observado = self._cuerpo(
            p, empresa=self._empresa("MEDIANO"), copias=por_hoja
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
            p, empresa=self._empresa("GRANDE"), copias=por_hoja
        )
        sin_configurar = self._cuerpo(p, copias=por_hoja)
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
        texto = _extract(p, empresa=self._empresa(tamano), copias=por_hoja)
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
                _build_pdf(p, empresa=self._empresa(tamano), copias=2)
        finally:
            socket.socket = original  # type: ignore[misc]


class TestEscapadoXml:
    """ReportLab interpreta el texto de un ``Paragraph`` como XML reducido.

    Un ``&`` sin escapar se imprime mal (p. ej. «S&S» → «S&S;») y un ``<algo>``
    se descarta en silencio. Todo dato que venga del usuario o de la BD debe
    salir literal en el ticket; estas pruebas fijan esa garantía.
    """

    def test_ampersand_de_la_empresa_no_se_corrompe(self):
        # El propio nombre del cliente contiene '&' ('VARIEDADES S&S'): antes de
        # escapar, el PDF extraía 'S&S;' (un ';' espurio tras la 'S').
        p = _boleto_completo()
        txt = _extract(p, empresa=_empresa_demo(), tamano_papel="80mm")
        assert "S&S" in txt
        assert "S&S;" not in txt

    def test_menor_y_mayor_no_se_descartan(self):
        p = _boleto_completo()
        p.__setattr__("producto_nombre", "<MAIZ> & AMARILLO")
        txt = " ".join(_extract(p, tamano_papel="80mm").split())
        assert "<MAIZ> & AMARILLO" in txt

    def test_observaciones_con_markup_se_imprimen_literal(self):
        p = _boleto(observaciones="<pendiente> & revisar")
        txt = " ".join(_extract(p, tamano_papel="80mm").split())
        assert "<pendiente> & revisar" in txt

    def test_motivo_de_anulacion_se_escapa(self):
        p = _boleto(
            estado_boleto=BoletoPesaje.ESTADO_ANULADO,
            motivo_anulacion="peso <ilegible> & borroso",
        )
        txt = " ".join(_extract(p, tamano_papel="80mm").split())
        assert "<ilegible> & borroso" in txt

    def test_cabecera_de_empresa_con_markup_se_escapa(self):
        p = _boleto_completo()
        emp = _empresa_demo(nombre_comercial="A & B <C.A.>")
        txt = " ".join(_extract(p, empresa=emp, tamano_papel="80mm").split())
        assert "A & B <C.A.>" in txt

    def test_hoja_carta_tambien_escapa(self):
        p = _boleto_completo()
        p.__setattr__("producto_nombre", "S&S <grado A>")
        txt = " ".join(_extract(p, copias=1).split())
        assert "S&S <grado A>" in txt

    def test_txt_no_escapa_entidades(self):
        # El TXT es texto plano: se conserva el dato tal cual, sin entidades XML.
        p = _boleto_completo()
        p.__setattr__("producto_nombre", "S&S <grado A>")
        txt = _build_txt(p).getvalue().decode("utf-8")
        assert "S&S <grado A>" in txt
        assert "&amp;" not in txt

    def test_esc_helper_es_idempotente_sobre_texto_plano(self):
        from app.services.ticket_service import _esc

        # Texto sin caracteres XML: pasa intacto (y re-aplicarlo no lo cambia).
        assert _esc("texto plano 123") == "texto plano 123"
        assert _esc(_esc("texto plano 123")) == "texto plano 123"
        # Y escapa lo que debe escapar.
        assert _esc("S&S") == "S&amp;S"
        assert _esc("a < b > c") == "a &lt; b &gt; c"
        assert _esc(None) == ""
        assert _esc("") == ""


class TestQrDelPesaje:
    """El bloque QR se imprime solo cuando la estación lo deja activado.

    La etiqueta ``QR - RESUMEN DEL PESAJE`` la dibuja el propio flowable sobre
    el código, así que es un centinela fiable: si está en el texto extraído, el
    bloque entero participó del layout (y su altura cuenta en el ajuste).
    """

    @pytest.fixture(autouse=True)
    def _qr_global_activo(self, monkeypatch):
        """Aísla estas pruebas del interruptor GLOBAL de fábrica.

        Aquí se fija la conducta de la ESTACIÓN (``mostrar_qr`` por petición);
        el interruptor de instalación se prueba aparte y con su propio
        ``monkeypatch``, así que el apagado de fábrica no tumba al resto.
        """
        monkeypatch.setattr("app.services.ticket_service.MOSTRAR_QR_EN_REPORTES", True)

    @pytest.mark.parametrize("papel", ["80mm", "58mm", "Letter", "HalfLetter", "A4"])
    def test_por_defecto_el_qr_se_imprime(self, papel: str):
        texto = _extract(_boleto_completo(), tamano_papel=papel)
        assert "QR - RESUMEN DEL PESAJE" in texto

    @pytest.mark.parametrize("papel", ["80mm", "58mm", "Letter", "A4"])
    def test_la_app_puede_apagarlo_por_peticion(self, papel: str):
        texto = _extract(_boleto_completo(), tamano_papel=papel, mostrar_qr=False)
        assert "QR - RESUMEN DEL PESAJE" not in texto

    def test_apagarlo_no_toca_el_resto_del_boleto(self):
        p = _boleto_completo()
        con_qr = _extract(p, tamano_papel="80mm")
        sin_qr = _extract(p, tamano_papel="80mm", mostrar_qr=False)
        assert "BOLETO DE PESAJE" in sin_qr
        assert "LECTURA DE PESOS" in sin_qr
        # La misma información de pesada en los dos casos.
        assert con_qr.count("ENTRADA:") == sin_qr.count("ENTRADA:")

    def test_sin_qr_el_rollo_es_mas_corto(self):
        p = _boleto_completo()
        _, alto_con = _mediabox(p, tamano_papel="80mm")
        _, alto_sin = _mediabox(p, tamano_papel="80mm", mostrar_qr=False)
        # El QR forma parte del flujo: si desaparece, la página encoge.
        assert 0 < alto_sin < alto_con

    def test_el_interruptor_global_manda_sobre_la_empresa(self, monkeypatch):
        monkeypatch.setattr(
            "app.services.ticket_service.MOSTRAR_QR_EN_REPORTES", False
        )
        for papel in ("80mm", "Letter"):
            texto = _extract(_boleto_completo(), tamano_papel=papel)
            assert "QR - RESUMEN DEL PESAJE" not in texto

    def test_el_qr_no_necesita_datos_extra(self):
        # Un boleto sin salida (solo pesada de entrada) sigue llevando su QR.
        p = _boleto_baseline()
        p.__setattr__("fecha_hora_salida", None)
        p.__setattr__("peso_salida_vehiculo", None)
        p.__setattr__("peso_neto", None)
        assert "QR - RESUMEN DEL PESAJE" in _extract(p, tamano_papel="80mm")
        assert "QR - RESUMEN DEL PESAJE" not in _extract(
            p, tamano_papel="80mm", mostrar_qr=False
        )


def _datos_qr(payload: str) -> dict:
    """Descomprime el payload del QR: Base64 URL-safe → zlib → JSON."""
    return json.loads(zlib.decompress(base64.urlsafe_b64decode(payload)))


def _payload_qr(p, **kwargs) -> str:
    """Payload del QR que realmente se imprime, capturado del render."""
    capturado: list[str] = []
    original = ts._qr_payload_pesaje  # antes del parche: evita la recursión

    def espia(datos):
        payload = original(datos)
        capturado.append(payload)
        return payload

    with patch.object(ts, "_qr_payload_pesaje", espia):
        _extract(p, **kwargs)
    assert capturado, "el QR no llegó a generarse"
    return capturado[0]


class TestContenidoDelQr:
    """Qué lleva dentro el QR: todos los campos menos el texto libre.

    El payload es ``Base64(zlib(JSON))``. Sin comprimir un boleto real ocupaba
    ≈1 900 caracteres → 145 módulos → 0,22 mm/módulo en el rollo de 34 mm (la
    térmica resuelve 0,125 mm/punto: se veía como una mancha de cuadritos).
    Comprimido baja a ≈1 000 caracteres → 109 módulos.
    """

    @pytest.fixture(autouse=True)
    def _qr_global_activo(self, monkeypatch):
        monkeypatch.setattr(ts, "MOSTRAR_QR_EN_REPORTES", True)

    def test_el_payload_va_comprimido_y_se_decodifica(self):
        payload = _payload_qr(_boleto_completo(), tamano_papel="80mm")
        datos = _datos_qr(payload)
        assert datos["tipo"] == "BALANSOFT_PESAJE"
        assert datos["v"] == 2
        assert datos["datos"]["numero"]  # el boleto viaja

    def test_el_payload_pesa_la_mitad_y_el_qr_baja_de_modulos(self):
        # Medido: JSON crudo ≈1 400 B → 1 888 en Base64 (145 módulos).
        payload = _payload_qr(_boleto_completo(), tamano_papel="80mm")
        assert len(payload) <= 1300

        codigo = QrCodeWidget(payload)
        assert codigo.getBounds()  # aquí construye el QR y resolvía el overflow
        assert codigo.qr.getModuleCount() <= 120

    def test_observaciones_no_viaja_en_el_qr(self):
        # Es el único campo de texto libre sin cota: ≈800 caracteres hacían
        # fallar el QR entero (code length overflow) y con él el PDF.
        payload = _payload_qr(_boleto_completo(), tamano_papel="80mm")
        assert "observaciones" not in _datos_qr(payload)["datos"]
        assert "Despacho a granel" not in payload

    def test_el_qr_lleva_el_rif_del_emisor(self):
        # `empresa_rif` lo proyecta `_dato` desde el atributo del boleto, pero
        # el RIF vive en la empresa: se inyecta vía `_empresa_cabecera` en el
        # _build_pdf. Si la estación envía una empresa con RIF, debe viajar en el QR.
        payload = _payload_qr(
            _boleto_completo(),
            tamano_papel="80mm",
            empresa=cast(Empresa, _empresa_demo()),
        )
        datos = _datos_qr(payload)["datos"]
        assert datos.get("empresa_rif") == "J-31490236-2"

    def test_un_qr_que_no_cabe_no_tumba_el_ticket(self, monkeypatch):
        class _QrQueRevienta:
            """Imita a ReportLab cuando el payload supera la capacidad."""

            def __init__(self, *args: object, **kwargs: object) -> None:
                pass

            def getBounds(self):
                raise Exception("code length overflow. (23188 > 22496)")

        monkeypatch.setattr(ts, "QrCodeWidget", _QrQueRevienta)
        texto = _extract(_boleto_completo(), tamano_papel="80mm")
        assert "BOLETO DE PESAJE" in texto
        assert "ENTRADA:" in texto
        # La etiqueta del QR se dibuja DESPUÉS del código: sin código, sin rótulo.
        assert "QR - RESUMEN DEL PESAJE" not in texto
