"""Generación del ticket/boleto de pesaje.

FUENTE DE VERDAD DEL LAYOUT: widget ``TicketPreviewDialog`` (Flutter).
  Archivo: frontend/lib/presentation/widgets/ticket_preview_dialog.dart
  Función: _buildSingleTicketBlock() (hoja Carta/A4) / _buildTicketTermico() (rollo)

Cualquier cambio estructural (añadir/quitar campos, cambiar orden) debe
aplicarse PRIMERO en ese widget y LUEGO aquí.

Zonas del boleto de hoja (Carta/A4):
  DATOS → LECTURA DE PESOS (tabla) → PESO DECLARADO / DIFERENCIA / DESVIACIÓN →
  DATOS ADICIONALES → OBSERVACIONES → Firmas.
En rollo térmico (80mm/58mm) se usa la variante compacta: los campos van
apilados "Etiqueta: valor" ALINEADOS A LA DERECHA con la etiqueta en negrita,
y la LECTURA DE PESOS es una tabla de 5 columnas con la misma rejilla que la
hoja (``_filas_lectura_pesos``):
  (etiqueta) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL
con una fila por pesada (ENTRADA / SALIDA), la de TOTALES (los netos por
vehículo) y una fila final PESO NETO con su sufijo (INGRESO / DESPACHO).

Formatos:
  - PDF : la cantidad de tickets (``copias``) imprime N copias idénticas; la
          escala tipográfica se ajusta de forma adaptativa para que cada boleto
          quepa cabalmente en su franja, sin cortarse.
  - TXT : misma estructura en texto plano UTF-8, mismo orden.

Si el boleto está ANULADO se imprime con marca de agua 'ANULADO' (solo PDF).

Encabezado de empresa (hoja Carta/A4):
  - CON logo → tabla [logo | datos] SIN línea divisoria entre ambos.
  - SIN logo → solo texto alineado a la izquierda.

Versión: 0.4.2-dev.56
Fecha: 2026-10-19
Estado: Vigente
Norma: ISO/IEC 17025 / OIML R 76-1 / ISO/IEC 25010
Fuente: Sistema BALANSOFT-WS
Autor: Lead Architect
"""

from __future__ import annotations

import base64
import glob
import io
import json
import logging
import os
import sys
import zlib
from collections.abc import Iterable, Mapping, Sequence
from datetime import datetime
from decimal import Decimal
from typing import Any, cast
from xml.sax.saxutils import escape as _xml_escape

from fastapi.responses import StreamingResponse
from reportlab.graphics import renderPDF
from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.graphics.shapes import Drawing
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import (
    Flowable,
    Frame,
    Image,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

from app.core.config import settings
from app.core.formato import formatear_numero
from app.core.i18n import t, traducir_estado_boleto
from app.models import BoletoPesaje, Empresa, Kardex
from app.services.weighing_service import normalizar_estado

log = logging.getLogger("balansoft_ws.ticket")

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

#: Escala tipográfica base del ticket térmico (80mm/58mm).
#:
#: El térmico NO usa la escalera de la hoja: la página crece con el contenido
#: (alto dinámico), así que no hay que encoger la letra para que "quepa".
#: Con ts = 9.5 el cuerpo sale a 9 pt (ts - 0.5).
#: El peldaño configurado por la empresa (``tamano_ticket_pdf``) actúa como
#: **techo** aquí también: PEQUENO/MEDIANO reducen el térmico, GRANDE/AUTOMATICO
#: no lo tocan (mismo criterio que `TECHOS_PELDANO` en la hoja). Por eso la base
#: tiene que quedar POR ENCIMA de los dos techos (7.5 y 9.0): con una base de
#: 7 pt, `min(_TS_TERMICO, techo)` devolvía 7 para PEQUENO, MEDIANO y
#: AUTOMATICO, y el ajuste tipográfico por empresa (REQ-FN-015) quedaba inerte
#: en el rollo.
_TS_TERMICO = 9.5

#: Tamaño de la ETIQUETA y del VALOR de las filas "Etiqueta | valor" del bloque
#: de datos, RELATIVO a la escala base ``ts`` de cada formato.
#:
#: Estas dos filas del bloque de datos (DATOS, operador, DATOS ADICIONALES y
#: CATÁLOGO) se imprimen igual en el rollo térmico (80/58 mm) y en la hoja
#: (media carta, carta y A4), así que **este es el único sitio donde se ajusta
#: el tamaño de ese bloque**: cambiar estos dos números mueve todos los formatos
#: a la vez. Por defecto la etiqueta va más pequeña que el valor.
#:
#: El interlineado de la etiqueta se recorta en la misma medida (para que la
#: fila NO crezca, porque el alto lo manda el valor) y `_fila_t` compensa la
#: línea base con relleno superior: ReportLab baja la primera línea de una celda
#: según el TAMAÑO de la fuente —el ``leading`` no la mueve—, así que sin esa
#: corrección una etiqueta más pequeña quedaría unos puntos por encima de su
#: valor en vez de compartir la vertical.
_DS_TAM_ETIQ_FILA: float = -2
_DS_TAM_VALOR_FILA: float = -3

#: Aire (pt) arriba y abajo de cada fila "Etiqueta | valor" en la HOJA (media
#: carta, carta y A4). El rollo térmico va a 0 (cada milímetro cuenta y la
#: página crece con el contenido); la hoja conserva así su ritmo vertical de
#: siempre, de modo que la escalera tipográfica no cambia de peldaño.
_PADDING_FILA_HOJA: float = 1.0

#: Ancho que exige cada columna de la tabla LECTURA DE PESOS, en pt de texto por
#: pt de tamaño de fuente: el token más ancho que puede caer en ella.
#:
#: La tabla tiene el MISMO eje de columnas en el rollo térmico y en la hoja
#: (Etiqueta | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL); ``_RATIOS_TABLA_PESOS``
#: reparte el ancho útil con estas proporciones y por eso el reparto NO depende
#: de los datos del boleto: todos los boletos de una misma empresa salen con la
#: tabla igual.
_REQUIERE_TABLA_PESOS: tuple[float, ...] = (
    8.3000,  # Etiqueta: "PESO NETO:" / "TOTALES:" en negrita
    9.0000,  # Fec, Hrs
    5.3496,  # CAMIÓN
    5.2808,  # REMOLQUE
    5.7256,  # TOTAL
)

#: Interruptor GLOBAL del bloque QR en los reportes.
#:
#: ``True``  → el QR se imprime al final de cada boleto (térmico y hoja) cuando
#:             además la estación lo tiene activado en su configuración de
#:             «Diseño de ticket» (``mostrar_qr``), que es el valor por defecto.
#: ``False`` → el QR se omite por completo del PDF, sin importar lo que pida la
#:             estación (apagado de fábrica para toda la instalación).
#:
#: Se deja como constante de módulo para poder apagar el QR de una instalación
#: entera sin tocar la lógica de layout ni los flujos de la API. El control del
#: día a día es ``mostrar_qr`` (llega como ``?mostrar_qr=`` desde la app).
MOSTRAR_QR_EN_REPORTES: bool = True

#: Campos que viajan dentro del QR.
#:
#: El QR físico tiene un límite de densidad práctica: cada campo extra sube la
#: versión del código y encoge el módulo impreso hasta que ni la térmica (0,125
#: mm/punto) ni una cámara de gama media lo leen. Por eso el payload NO se
#: empaqueta como JSON crudo en Base64 (≈1 900 caracteres, 145 módulos, 0,22
#: mm/módulo) sino **comprimido con zlib antes del Base64** (≈1 000 caracteres,
#: 109 módulos, 0,29 mm/módulo) y con los valores vacíos descartados.
#:
#: ``observaciones`` queda FUERA a propósito: es el único campo de texto libre
#: multilínea sin cota de longitud y, con ~800 caracteres, desbordaba la
#: capacidad máxima del QR (2 953 B en el nivel L) y hacía fallar el PDF
#: completo. El texto se sigue imprimiendo en el boleto (DATOS ADICIONALES).
#:
#: Claves en el mismo orden en que se empaquetan. Si necesitas más datos, añade
#: la clave aquí y puebla su valor en `_dato`.
_CAMPOS_QR_PESAJE: tuple[str, ...] = (
    # ── Identificación del boleto ────────────────────────────────────────
    "numero",
    "fecha_hora",
    "estado",
    # ── Vehículo y transporte ────────────────────────────────────────────
    "camion",
    "color_camion",
    "remolque",
    "remolque_tipo",
    "remolque_tara",
    "transporte",
    "transporte_codigo",
    "transporte_rif",
    # ── Conductor ────────────────────────────────────────────────────────
    "conductor",
    "conductor_cedula",
    "conductor_telefono",
    "conductor_licencia",
    # ── Producto / almacén / cliente ─────────────────────────────────────
    "producto",
    "producto_codigo",
    "producto_unidad",
    "almacen",
    "almacen_codigo",
    "seleccion",
    "razon_social",
    "tercero_codigo",
    "tercero_rif",
    "categoria_nombre",
    "categoria_codigo",
    # ── Lecturas de peso ─────────────────────────────────────────────────
    "hora_entrada",
    "hora_salida",
    "balanza",
    "pe_v",
    "pe_r",
    "pte",
    "ps_v",
    "ps_r",
    "pts",
    "neto_camion",
    "neto_remolque",
    "neto",
    "declarado",
    "diferencia",
    "desviacion",
    # ── Datos adicionales ────────────────────────────────────────────────
    "documento",
    "guia_sunagro",
    "medida",
    "flete",
    "costo_flete_raw",
    "unidades_raw",
    "densidad_raw",
    # ── Empresa emisora ──────────────────────────────────────────────────
    "empresa_rif",
    "empresa_nombre",
    # ── Operación ────────────────────────────────────────────────────────
    "operador",
    "peso_manual",
    # "observaciones": fuera del QR (texto libre sin cota, desbordaba el código).
)


def _qr_payload_pesaje(d: Mapping[str, Any]) -> str:
    """Payload del QR: JSON reducido → UTF-8 → zlib → Base64 URL-safe.

    Base64 hace que el QR contenga solo caracteres ``A-Z a-z 0-9 - _``, que son
    los que mejor se imprimen y escanean; la contrapartida (+33 %) se compensa
    comprimiendo el JSON con zlib ANTES de codificarlo. Un boleto real pasa de
    ≈1 900 caracteres (145 módulos, 0,22 mm/módulo en el rollo) a ≈1 000
    (109 módulos, 0,29 mm/módulo), y ``observaciones`` queda fuera del payload
    porque es el único campo de longitud libre (ver ``_CAMPOS_QR_PESAJE``).

    Para leerlo::

        json.loads(zlib.decompress(base64.urlsafe_b64decode(payload)))

    El JSON descomprimido es ``{"tipo": "BALANSOFT_PESAJE", "v": 2, "datos":
    {...}}`` con los campos no vacíos; los Decimal y datetime viajan como
    ``str`` (``default=str``), así que el lector no debe asumir tipos numéricos.
    """
    resumen = {clave: d.get(clave) for clave in _CAMPOS_QR_PESAJE}
    # Se descartan los valores vacíos para no inflar el QR con ruido.
    resumen = {k: v for k, v in resumen.items() if v not in (None, "")}
    json_min = json.dumps(
        {"tipo": "BALANSOFT_PESAJE", "v": 2, "datos": resumen},
        ensure_ascii=False,
        separators=(",", ":"),
        default=str,
    ).encode("utf-8")
    return base64.urlsafe_b64encode(zlib.compress(json_min, 9)).decode("ascii")


class _QrPesajeFlowable(Flowable):
    """QR imprimible con el resumen del pesaje (JSON + zlib + Base64).

    El QR es creado *dentro* de ``draw()`` (no en __init__) para poder
    atrapar cualquier ``Exception`` que reporte ReportLab cuando el payload
    supera la capacidad máxima del código (2953 bytes en nivel L) y, en
    lugar de fallar el PDF entero, el boleto se imprime sin ese bloque.
    """

    # ReportLab no publica tipos y sus defaults (``width=400, height=200``) son
    # enteros, así que el chequeo estático da por enteras estas medidas. Son
    # PUNTOS con decimales y válidos en tiempo de ejecución, así que se le
    # declara la intención con ``cast`` (que no toca el valor real).
    def __init__(self, datos: Mapping[str, Any], tamano: float = 32 * mm):
        super().__init__()
        self.tamano = tamano
        self.payload = _qr_payload_pesaje(datos)
        self.qr = QrCodeWidget(self.payload)
        self.width = 0
        self.height = cast(int, self.tamano + 13)

    def wrap(self, availWidth: float, availHeight: float) -> tuple[float, float]:
        self.width = cast(int, availWidth)
        return availWidth, self.height

    def draw(self) -> None:
        """Dibuja el código QR y su rótulo.

        Si el payload no cabe en un código QR nivel L, se registra un warning
        y la sección queda en blanco (el boleto sigue imbiéndose sin error 500).
        """
        self.canv.saveState()
        try:
            # Instanciar y medir QR dentro de draw() para poder atrapar overflow.
            w = QrCodeWidget(self.payload)
            w.getBounds()  # aquí puede lanzar Exception "code length overflow"
            qr_w = max(float(w.getBounds()[2] - w.getBounds()[0]), 1.0)
            qr_h = max(float(w.getBounds()[3] - w.getBounds()[1]), 1.0)
            escala = min(self.tamano / qr_w, self.tamano / qr_h)
            dibujo = Drawing(
                cast(int, qr_w * escala),
                cast(int, qr_h * escala),
                transform=[escala, 0, 0, escala, 0, 0],
            )
            dibujo.add(w)
            x = (self.width - qr_w * escala) / 2
            renderPDF.draw(dibujo, self.canv, x, 0)
            self.canv.setFillColor(GRIS_TEXTO)
            self.canv.setFont(FUENTE_BOLD, 6.5)
            self.canv.drawCentredString(
                self.width / 2, self.tamano + 3, "QR - RESUMEN DEL PESAJE"
            )
        except Exception:  # noqa: BLE001 - ReportLab lanza pelado (overflow)
            log.warning(
                "QR del pesaje no dibujado (%d caracteres de payload)",
                len(self.payload),
                exc_info=True,
            )
        finally:
            self.canv.restoreState()


#: Reparto del ancho útil de la tabla de lecturas (5 columnas).
_RATIOS_TABLA_PESOS: tuple[float, ...] = tuple(
    requerido / sum(_REQUIERE_TABLA_PESOS)
    for requerido in _REQUIERE_TABLA_PESOS
)

#: Reparto del ancho útil de la tabla de lecturas para la HOJA (media carta,
#: Carta y A4). La hoja tiene 100 mm de ancho útil, así que no necesita apretar
#: las columnas como el rollo: aquí la etiqueta pesa más y las columnas
#: numéricas se reparten con más aire.
_RATIOS_TABLA_PESOS_HOJA: tuple[float, ...] = (
    0.30,  # Etiqueta (ENTRADA / SALIDA / TOTALES / PESO NETO)
    0.22,  # Fec, Hrs
    0.16,  # CAMIÓN
    0.16,  # REMOLQUE
    0.16,  # TOTAL
)

#: Margen de seguridad del auto-ajuste de la tabla (2 %): evita que un redondeo
#: de las métricas deje el texto justo en el borde de la columna.
_HOLGURA_TABLA_PESOS = 0.98

#: Tamaño de fuente del que no se baja la tabla (a cambio se permite el corte
#: por carácter, que nunca desborda). Con contenido real no se alcanza:
#: 80 mm → ~6,4 pt y 58 mm → ~4,37 pt. El suelo va por debajo del ajuste del
#: 58 mm a propósito: con un mínimo de 4.5 pt el reparto no bajaba de 4.5, no
#: cabía y activaba el corte por carácter (rótulos partidos), que es lo que el
#: ejemplo del cliente evita.
_MIN_TABLA_PESOS = 3.8

#: Tope del ancho de la columna de ETIQUETAS de las filas del rollo, como
#: fracción del ancho útil de la fila. El valor se queda con lo demás.
#:
#: Es una RED DE SEGURIDAD: el ancho normal sale de medir la etiqueta más larga
#: del grupo, y en 80 mm el tope no llega a morder (la etiqueta más larga de
#: todos los idiomas, ``Cliente / Fornecedor:``, mide 109,6 pt con el hueco ≈
#: 52 % de los 209,8 pt útiles). En 58 mm sí manda: es lo que deja al valor
#: ~1/3 del ancho para que las etiquetas compuestas del catálogo no se coman la
#: fila entera. Con 0.67 la PALABRA más larga que puede salir
#: (``Cliente/Proveedor:`` = 94,9 pt) cabe holgada en el tope de 58 mm (98,8 pt),
#: así que ninguna etiqueta necesita partirse por carácter: las que no caben se
#: envuelven por palabra dentro de su celda.
_MAX_RATIO_ETIQUETA_TERMICA = 0.67

#: Separación (pt) entre la etiqueta y su valor en las filas del rollo.
#:
#: Sin ella las dos mitades de la fila se tocan: la etiqueta, alineada a la
#: derecha, termina exactamente donde empieza el valor (que se alinea a la
#: izquierda) y sale ``Cliente/Proveedor:PROVEEDOR …``.
_GAP_ETIQUETA_TERMICA = 3.0


def _ancho_etiqueta_termica(
    ancho_util: float,
    etiquetas: Iterable[str],
    tamano: float,
) -> tuple[float, bool]:
    """Ancho (pt) de la columna de ETIQUETAS de un grupo de filas del rollo.

    Es lo que ocupa la etiqueta MÁS LARGA del grupo —``Cliente/Proveedor:`` en
    es, ``Cliente / Fornecedor:`` en pt— con la negrita y el cuerpo en uso, más
    el hueco que la separa de su valor. Nunca pasa del tope
    (``_MAX_RATIO_ETIQUETA_TERMICA``): por muy larga que sea una etiqueta, el
    valor conserva la mayor parte del ancho, que es donde van las cadenas
    largas (conductor, razón social).

    Devuelve ``(ancho, cortar)``. ``cortar`` avisa de que alguna etiqueta trae
    una PALABRA que no cabe ni con el tope: esa sí hay que partirla por carácter
    (feo, pero desbordar la celda se pisaría con el valor; mismo criterio que
    `_tamano_tabla_pesos`). Las etiquetas compuestas que no caben enteras pero
    sí por palabras se envuelven solas, de modo que con el tope actual no se
    alcanza: la palabra más larga que puede salir (``Cliente/Proveedor:`` =
    94,9 pt a 9 pt) cabe en el tope de un rollo de 58 mm (98,8 pt).

    Se mide con el TTF real, así que la columna se adapta sola si cambia la
    tipografía base del térmico (``_TS_TERMICO``) o el idioma del ticket. El
    ancho se calcula POR GRUPO —DATOS, PESO MANUAL, datos adicionales y
    catálogo— porque son bloques visualmente separados y no tiene sentido que
    las filas de DATOS hereden el ancho de una etiqueta compuesta del catálogo.
    """
    completas = [f"{e}:" for e in etiquetas]
    necesario = max(
        (pdfmetrics.stringWidth(e, FUENTE_BOLD, tamano) for e in completas),
        default=0.0,
    ) + _GAP_ETIQUETA_TERMICA
    tope = ancho_util * _MAX_RATIO_ETIQUETA_TERMICA
    palabra = max(
        (pdfmetrics.stringWidth(p, FUENTE_BOLD, tamano) for e in completas for p in e.split()),
        default=0.0,
    )
    return min(necesario, tope), palabra > tope


def _esc(texto: Any) -> str:
    """Escapa ``&``/``<``/``>`` para el mini-XML de ReportLab.

    ReportLab interpreta el texto de un ``Paragraph`` como XML reducido: un
    ``&`` sin escapar se imprime mal (p. ej. «S&S» → «S&S;») y un ``<algo>`` se
    descarta en silencio. Todo dato que venga del usuario o de la BD debe pasar
    por aquí antes de llegar a un Paragraph. Las marcas de formato
    intencionales (``<b>``, ``<br/>``) se construyen FUERA de esta función.
    """
    if texto is None:
        return ""
    return _xml_escape(str(texto))


def _tamano_tabla_pesos(
    ancho_util: float,
    requiere: Sequence[float],
    tope: float,
    ratios: Sequence[float] = _RATIOS_TABLA_PESOS,
) -> tuple[float, bool]:
    """Tamaño de fuente de la tabla LECTURA DE PESOS que evita solapes.

    ``requiere[i]`` es el token más ancho de la columna ``i`` (a 1 pt) en el
    boleto que se está pintando; se compara con el peor caso de
    :data:`_REQUIERE_TABLA_PESOS` para que el reparto fijo de
    :data:`_RATIOS_TABLA_PESOS` no se quede corto.

    Devuelve ``(tamano, cortar)``. El ancho por columna NO se ajusta (layout
    estable entre boletos) y el tamaño es común a las 5 columnas: manda la más
    exigente. ``cortar`` pide ``wordWrap='CJK'`` cuando ni con
    :data:`_MIN_TABLA_PESOS` cabe (contenido patológico): partir por carácter es
    feo, pero no desborda jamás la columna.

    Lo usan el rollo térmico y la hoja: en la hoja de 1 boleto por página el
    ancho útil (100 mm) es tan estrecho como el del rollo, así que el mismo
    ajuste evita que el rótulo ``ENTRADA:`` o la cabecera ``REMOLQUE`` se
    partan por la mitad.
    """
    ancho_col = [ancho_util * r for r in ratios]
    ajustado = _HOLGURA_TABLA_PESOS * min(
        (
            ancho / max(real, plantilla)
            for ancho, real, plantilla in zip(
                ancho_col, requiere, _REQUIERE_TABLA_PESOS, strict=False
            )
        ),
        default=tope,
    )
    if ajustado >= _MIN_TABLA_PESOS:
        return min(ajustado, tope), False
    return _MIN_TABLA_PESOS, True


def _estilos_celda_pesos(
    bases: dict[str, ParagraphStyle], tam: float, cortar: bool
) -> dict[str, ParagraphStyle]:
    """Los 4 estilos de celda de la tabla de pesos, al tamaño ``tam``.

    Los tipos son los que devuelve :func:`_filas_lectura_pesos` —``hdr``
    (cabecera), ``lab`` (etiqueta), ``val`` y ``val_bold``— y cada formato pasa
    sus estilos base (el rollo va más apretado y con la etiqueta regular; la
    hoja, con la etiqueta en negrita). ``cortar`` pide el corte por carácter
    (mismo criterio que :func:`_tamano_tabla_pesos`).
    """
    return {
        tipo: ParagraphStyle(
            f"{getattr(base, 'name', tipo)}_{tam:.2f}",
            parent=base,
            fontSize=tam,
            leading=tam + 0.6,
            wordWrap="CJK" if cortar else getattr(base, "wordWrap", None),
        )
        for tipo, base in bases.items()
    }


def _anchos_requeridos_pesos(
    filas: Sequence[Sequence[tuple[str, str]]], columnas: int
) -> list[float]:
    """Token más ancho (a 1 pt) de cada columna de la tabla de pesos.

    Recorre el contenido REAL que se va a pintar —no la plantilla— y devuelve
    lo que necesita cada columna para que ninguna palabra se parta. Va con
    :func:`_tamano_tabla_pesos`, que compara contra el peor caso plantilla.
    """
    requiere = [0.0] * columnas
    for fila in filas:
        for i, (texto, tipo) in enumerate(fila):
            if not texto:
                continue
            fuente = FUENTE_BOLD if tipo in ("hdr", "val_bold") else FUENTE
            for token in texto.split():
                requiere[i] = max(requiere[i], pdfmetrics.stringWidth(token, fuente, 1.0))
    return requiere


# ─────────────────────────────────────────────────────────────────────────────
# Contenido COMPARTIDO de la tabla LECTURA DE PESOS (PDF hoja, PDF térmico,
# TXT y espejo en el preview de Flutter)
# ─────────────────────────────────────────────────────────────────────────────

#: Separador de fecha y hora DENTRO de la tabla, con espacios alrededor.
#:
#: Es un guion medio (U+2013, "en dash"), como el ejemplo del cliente
#: (``12/10/2026 – 18:57``); existe en WinAnsi, así que ni el PDF ni el TXT lo
#: pierden. El bloque de DATOS sigue con su ``_fmt_dt`` (espacio).
_SEPARADOR_FECHA_HORA = " \u2013 "


def _fmt_dt_tabla(dt: datetime | None) -> str:
    """Fecha y hora de la columna ``Fec, Hrs``: ``dd/mm/aaaa – HH:MM``."""
    if dt is None:
        return "—"
    return f"{dt:%d/%m/%Y}{_SEPARADOR_FECHA_HORA}{dt:%H:%M}"


def _celda_peso(valor: Any, idioma: str) -> str:
    """Celda de peso de la tabla: ``'12.345,67 kg'``, o vacía si no hay dato."""
    return "" if valor is None else f"{_fmt(valor, lang=idioma)} kg"


def _filas_lectura_pesos(
    d: dict[str, Any], idioma: str
) -> list[list[tuple[str, str]]]:
    """Contenido de la tabla LECTURA DE PESOS, igual en los 3 formatos.

    Reproduce la rejilla del ejemplo del cliente (:file:`lectura_peso_format_ejemp.ods`):
    la primera columna lleva la ETIQUETA de la fila —o va vacía—, la segunda la
    fecha y hora, y las tres últimas los kilos de CAMIÓN, REMOLQUE y TOTAL::

        (vacío)     Fec, Hrs              CAMIÓN        REMOLQUE      TOTAL
        ENTRADA:    12/10/2026 – 18:57    4.850,00 kg   3.650,00 kg   8.500,00 kg
        SALIDA:     12/10/2026 – 18:59      674,00 kg     410,00 kg   1.084,00 kg
        (vacío)     TOTALES:              4.176,00 kg   3.240,00 kg   7.416,00 kg
        PESO NETO:  7.416,00 kg  (INGRESO)

    Tres detalles que NO son obvios:

    * la fila SALIDA solo sale si el boleto ya tiene salida, y la de TOTALES
      lleva los NETOS por vehículo (lo que el cliente rotula "TOTALES"): el
      bruto de cada pesada ya se ve en su propia fila;
    * ``TOTALES`` va en la SEGUNDA columna, como el ejemplo (que deja la
      primera vacía);
    * el PESO NETO y su sufijo van PEGADOS a la etiqueta —el valor en la
      columna ``Fec, Hrs`` y ``(INGRESO)``/``(DESPACHO)`` en la de CAMIÓN, con
      las de remolque y total vacías, tal como el ejemplo—, así que el rótulo
      queda siempre a la izquierda.

    Cada celda es ``(texto, tipo)`` y el tipo —``hdr``, ``lab``, ``val``,
    ``val_bold``— elige el estilo en cada formato.
    """
    neto = d["neto"] if d["neto"] is not None else Decimal("0")
    sufijo = (
        f"({t('despacho', idioma)})" if neto < 0
        else (f"({t('ingreso', idioma)})" if neto > 0 else "")
    )
    filas: list[list[tuple[str, str]]] = [
        [
            ("", "hdr"),
            (t("col_fecha_hora", idioma), "hdr"),
            (t("col_camion", idioma), "hdr"),
            (t("col_remolque", idioma), "hdr"),
            (t("col_total", idioma), "hdr"),
        ],
        [
            (f"{t('col_entrada', idioma)}:", "lab"),
            (_fmt_dt_tabla(d["hora_entrada"]), "val"),
            (_celda_peso(d["pe_v"], idioma), "val"),
            (_celda_peso(d["pe_r"], idioma), "val"),
            (_celda_peso(d["pte"], idioma), "val"),
        ],
    ]
    if d["hora_salida"] is not None:
        filas.append([
            (f"{t('col_salida', idioma)}:", "lab"),
            (_fmt_dt_tabla(d["hora_salida"]), "val"),
            (_celda_peso(d["ps_v"], idioma), "val"),
            (_celda_peso(d["ps_r"], idioma), "val"),
            (_celda_peso(d["pts"], idioma), "val"),
        ])
    filas.append([
        ("", "lab"),
        (f"{t('col_totales', idioma)}:", "lab"),
        (_celda_peso(d["neto_camion"], idioma), "val"),
        (_celda_peso(d["neto_remolque"], idioma), "val"),
        (_celda_peso(neto, idioma), "val"),
    ])
    filas.append([
        (f"{t('peso_neto', idioma)}:", "lab"),
        (f"{_fmt(abs(neto), lang=idioma)} kg", "val_bold"),
        (sufijo, "val_bold"),
        ("", "val"),
        ("", "val"),
    ])
    return filas


# ─────────────────────────────────────────────────────────────────────────────
# Escalera tipográfica del boleto (REQ-FN-010, REQ-FN-011, REQ-FN-015)
# ─────────────────────────────────────────────────────────────────────────────

#: Escalas candidatas por cantidad de boletos en la hoja, de mayor a menor.
#:
#: Se mueve aqui, a nivel de modulo, y no dentro de ``_build_pdf`` para que la
#: escalera sea una constante nombrada y se pueda comprobar sin arrancar
#: ReportLab. Los valores son los que tenia el literal local antes de este
#: cambio; moverlos aqui no altera el comportamiento (REQ-FN-012).
_ESCALAS_ACTUALES: dict[int, list[float]] = {
    1: [10.5, 10.0, 9.5, 9.0, 8.5, 8.0, 7.5, 7.0, 6.5, 6.0, 5.5],
    2: [9.5,  9.0, 8.5, 8.0, 7.5, 7.0, 6.5, 6.0, 5.5, 5.0],
    3: [8.5,  8.0, 7.5, 7.0, 6.5, 6.0, 5.5, 5.0, 4.5, 4.0],
    4: [8.0,  7.5, 7.0, 6.5, 6.0, 5.5, 5.0, 4.5, 4.0],
}

#: Techo por peldaño configurado (REQ-FN-015).
#:
#: ``AUTOMATICO`` y ``GRANDE`` no aparecen a proposito: no filtran. ``AUTOMATICO``
#: porque es el comportamiento vigente y debe quedar intacto (REQ-FN-012), y
#: ``GRANDE`` porque la escalera ya arranca en su maximo, asi que "mas grande"
#: solo puede significar "igual que hoy" (CE-05).
TECHOS_PELDANO: dict[str, float] = {
    "PEQUENO": 7.5,
    "MEDIANO": 9.0,
}


def escalera_efectiva(
    hoy: dict[int, list[float]],
    paso_configurado: str | None,
) -> dict[int, list[float]]:
    """Escalera de escalas con el peldaño configurado como techo.

    Con ``AUTOMATICO``, ``GRANDE`` o cualquier valor desconocido devuelve ``hoy``
    **sin copiar**: son los casos en los que no hay nada que filtrar, y evitar la copia
    trabajo por boleto en el camino caliente de la impresion.

    Con un peldaño configurado, descarta de cada escalera las escalas que lo
    superan. El ultimo elemento (el piso, que garantiza que el auto-fit siempre
    termine en una escala existente) nunca se descarta, porque todos los pisos
    estan por debajo de cualquier techo.

    Puro a proposito: no toca ReportLab ni la base de datos, asi que se puede
    comprobar con aritmetica y sin montar una pagina.
    """
    techo = TECHOS_PELDANO.get((paso_configurado or "").upper())
    if techo is None:
        return hoy
    return {n: [e for e in peldanos if e <= techo] for n, peldanos in hoy.items()}


def _escala_termica(valor_configurado: str | None) -> float:
    """Escala tipográfica del boleto térmico (80/58 mm).

    El rollo térmico no tiene escalera: la página crece con el contenido, así
    que aquí no hay auto-fit. El peldaño configurado por la empresa
    (``empresas.tamano_ticket_pdf``, REQ-FN-015) sigue mandando como **techo**,
    igual que en la hoja: PEQUENO/MEDIANO reducen el cuerpo impreso;
    GRANDE/AUTOMATICO (y cualquier valor desconocido) dejan la base.
    """
    techo = TECHOS_PELDANO.get((valor_configurado or "").upper())
    if techo is None:
        return _TS_TERMICO
    return min(_TS_TERMICO, techo)


# ─────────────────────────────────────────────────────────────────────────────
# Formateo de números y fechas
# ─────────────────────────────────────────────────────────────────────────────
def _fmt(v: Decimal | float | int | str | None, decimales: int = 2, lang: str = "es") -> str:
    """Formatea número con los separadores del idioma.

    Ejemplos: 15000.50 → '15.000,50' (es/pt) · '15,000.50' (en)
    Espejo de _formatNumber() en Flutter (TicketPreviewDialog).
    """
    return formatear_numero(v, decimales, lang)


def _fmt_dt(dt: datetime | None) -> str:
    """Formato dd/MM/yyyy HH:mm — idéntico a _formatDate() en Flutter."""
    return dt.strftime("%d/%m/%Y %H:%M") if dt else "—"


def _fmt_sig(v: Decimal | float | int | None, decimales: int = 2, lang: str = "es") -> str:
    """Formatea un número con su signo explícito ('+'), como la diferencia.

    Espejo de _fmtConSigno() en Flutter: +1.234,50 / -1.234,50 / 0,00.
    _fmt ya incluye el signo '-' para los negativos.
    """
    if v is None:
        return ""
    f = _fmt(v, decimales, lang)
    if v > 0:
        return f"+{f}"
    return f


def _fmt_densidad(v: Decimal | float | None, lang: str = "es") -> str | None:
    """Densidad con hasta 8 decimales sin ceros finales ('0,92' / '0.92')."""
    if v is None:
        return None
    s = _fmt(v, decimales=8, lang=lang)
    decimal_sep = "." if lang == "en" else ","
    s = s.rstrip("0").rstrip(decimal_sep)
    return s or "0"


# ─────────────────────────────────────────────────────────────────────────────
# Extracción de datos del boleto
# FUENTE: TicketPreviewDialog._buildSingleTicketBlock (Flutter)
# Solo se incluyen los campos que aparecen en esa función.
# ─────────────────────────────────────────────────────────────────────────────
def _normalizar_simple(valor: Any) -> str:
    """Normaliza un campo SIMPLE (nombres, razón social, producto, …).

    Colapsa espacios dobles/múltiples y saltos de línea a un solo espacio
    (REQ: "YOHANDER  SANCHEZ" → "YOHANDER SANCHEZ"). NO usar en campos
    multi-línea como las observaciones, que deben conservar sus saltos.
    """
    if valor is None:
        return ""
    return " ".join(str(valor).split())


def _numero_boleto(p: BoletoPesaje, idioma: str = "es") -> str:
    """Número de boleto con fallback robusto (REQ: fallbacks robustos).

    Cadena de respaldo:
      numero_boleto → numero → BOL-{boleto[:8]} → {serie}-{correlativo:08d}
      → texto traducible "Sin número".

    Todos los accesos van con ``getattr`` para que funcione aunque el atributo
    no exista en la proyección (los datos llegan de _enriquecer_pesaje_ticket).
    """
    numero = (getattr(p, "numero_boleto", None) or "").strip()
    if not numero:
        numero = (getattr(p, "numero", None) or "").strip()
    if not numero and getattr(p, "boleto", None):
        # BOL + primeros 8 caracteres del UUID/identificador interno, en mayúsculas.
        numero = f"BOL-{str(p.boleto)[:8].upper()}"
    if not numero:
        serie = (getattr(p, "serie", None) or "").strip()
        correlativo = getattr(p, "correlativo", None)
        if serie and correlativo is not None:
            try:
                numero = f"{serie}-{int(correlativo):08d}"
            except (ValueError, TypeError, ArithmeticError):
                numero = ""
    return numero or t("boleto_sin_numero", idioma)


def _remolque_txt(p: BoletoPesaje, idioma: str = "es") -> str:
    """Texto del campo Remolque con fallback robusto (REQ: fallbacks robustos).

    - Si hay placa (``placa_remolque``/``remolque_placa``) → "Sí — {placa}".
    - Si hay ``id_remolque`` (remolque asignado sin placa cargada) → "Sí".
    - Si ``remolque`` es True → "Sí".
    - En cualquier otro caso → "No".

    Motivo: _enriquecer_pesaje_ticket fija ``placa_remolque`` siempre que el
    boleto tenga ``id_remolque``, aunque la columna booleana ``remolque`` venga
    en False/None. Antes el ticket ocultaba un remolque asignado con placa.
    """
    placa = _normalizar_simple(
        getattr(p, "placa_remolque", None) or getattr(p, "remolque_placa", None)
    )
    tiene_flag = bool(getattr(p, "remolque", None))
    tiene_id = bool(getattr(p, "id_remolque", None))
    if placa:
        return f"{t('si', idioma)} — {placa}"
    if tiene_flag or tiene_id:
        return t("si", idioma)
    return t("no", idioma)


def _dato(p: BoletoPesaje, idioma: str = "es") -> dict[str, Any]:
    """Extrae los campos usados por la previsualización Flutter.

    Referencia: TicketPreviewDialog._buildSingleTicketBlock
    NO añadir campos que no estén en ese widget.
    """
    # Remolque: "Sí [— placa]" o "No"  (Flutter: w.remolque ? (w.remolquePlaca ?? ...) : 'No')
    remolque_txt = _remolque_txt(p, idioma)
    # Flag booleano (misma lógica que _remolque_txt) para decidir si la tabla de
    # lecturas del térmico muestra las filas Remolque/Total.
    tiene_remolque = bool(
        _normalizar_simple(getattr(p, "placa_remolque", None))
        or _normalizar_simple(getattr(p, "remolque_placa", None))
        or getattr(p, "remolque", None)
        or getattr(p, "id_remolque", None)
    )

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

    # Observaciones: NUNCA colapsar todas con \s+; normalizar cada línea por
    # separado conservando los saltos de línea originales (REQ: normalización).
    obs_raw = (getattr(p, "observaciones", None) or "").strip()
    observaciones = "\n".join(
        _normalizar_simple(linea) for linea in obs_raw.splitlines()
    )

    return {
        # ── Datos del boleto (orden exacto del widget Flutter) ───────────────
        "numero":       _numero_boleto(p, idioma),
        "fecha_hora":   _fmt_dt(p.fecha_hora_entrada),
        "camion":       _normalizar_simple(p.id_vehiculo or t("sin_placa", idioma)),
        "color_camion": _normalizar_simple(getattr(p, "color_camion", None)),
        "remolque":     remolque_txt,
        "tiene_remolque": tiene_remolque,
        "transporte":   _normalizar_simple(
            getattr(p, "transporte_nombre", None)
            or getattr(p, "transporte", None)
            or getattr(p, "id_transporte", None)
            or t("na", idioma)
        ),
        "conductor":    _normalizar_simple(
            getattr(p, "conductor_nombre", None)
            or getattr(p, "conductor", None)
            or getattr(p, "id_conductor", None)
            or t("na", idioma)
        ),
        "producto":     _normalizar_simple(
            getattr(p, "producto_nombre", None)
            or getattr(p, "producto", None)
            or getattr(p, "id_producto", None)
            or t("na", idioma)
        ),
        "almacen":      _normalizar_simple(
            getattr(p, "almacen_nombre", None)
            or getattr(p, "almacen", None)
            or getattr(p, "id_almacen", None)
            or t("na", idioma)
        ),
        "seleccion":    seleccion or t("na", idioma),
        "razon_social": _normalizar_simple(
            getattr(p, "razon_social", None)
            or getattr(p, "tercero_nombre", None)
            or getattr(p, "id_tercero", None)
            or t("na", idioma)
        ),
        # ── Lecturas de peso (tabla: Balanza|Fecha/Hora|Camion|Remolque|Total)
        "hora_entrada":  p.fecha_hora_entrada,
        "hora_salida":   getattr(p, "fecha_hora_salida", None),
        "balanza":       _normalizar_simple(balanza),
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
        "documento":     _normalizar_simple(p.documento),
        "guia_sunagro":  _normalizar_simple(getattr(p, "guia_sunagro", None)),
        "medida":        _normalizar_simple(getattr(p, "medida", None)),
        "flete":         _normalizar_simple(getattr(p, "flete", None)),
        "costo_flete_raw": getattr(p, "costo_flete", None),
        "unidades_raw":  (p.unidades or p.litros),
        "densidad_raw":  getattr(p, "densidad", None),
        "unidades_txt":  (
            _fmt(p.unidades or p.litros, lang=idioma)
            if (p.unidades or p.litros) is not None
            else None
        ),
        "densidad_txt":  _fmt_densidad(getattr(p, "densidad", None), idioma),
        # ── Metadatos ────────────────────────────────────────────────────────
        "observaciones":    observaciones,
        "estado":           normalizar_estado(p.estado_boleto),
        "motivo_anulacion": _normalizar_simple(p.motivo_anulacion),
        "peso_manual":      bool(getattr(p, "es_peso_manual", False)),
        "operador":         _normalizar_simple(getattr(p, "creado_por", None)),
        # ── Entidades maestro y control (inyectados por _enriquecer_pesaje_ticket)
        "empresa_rif":       getattr(p, "empresa_rif", None),
        "tercero_codigo":    getattr(p, "tercero_codigo", None),
        "tercero_rif":       getattr(p, "tercero_rif", None),
        "conductor_cedula":  getattr(p, "conductor_cedula", None),
        "conductor_telefono": getattr(p, "conductor_telefono", None),
        "conductor_licencia": getattr(p, "conductor_licencia", None),
        "transporte_codigo": getattr(p, "transporte_codigo", None),
        "transporte_rif":    getattr(p, "transporte_rif", None),
        "remolque_tipo":     getattr(p, "tipo_remolque", None),
        "remolque_tara":     getattr(p, "tara_habitual", None),
        "categoria_nombre":  getattr(p, "categoria_nombre", None),
        "categoria_codigo":  getattr(p, "categoria_codigo", None),
        "producto_codigo":   getattr(p, "producto_codigo", None),
        "producto_unidad":   getattr(p, "producto_unidad", None),
        "producto_kardex":   bool(getattr(p, "producto_kardex", False)),
        "almacen_codigo":    getattr(p, "almacen_codigo", None),
        "almacen_capacidad": getattr(p, "almacen_capacidad", None),
        "almacen_stock":     getattr(p, "almacen_stock", None),
        "balanza_codigo":    getattr(p, "balanza_codigo", None),
        "balanza_capacidad": getattr(p, "balanza_capacidad", None),
        "balanza_division":  getattr(p, "balanza_division", None),
        "kardex_mov":        getattr(p, "kardex_mov", None),
        "kardex_valor":      getattr(p, "kardex_valor", None),
        "sincronizado":      bool(getattr(p, "sincronizado", False)),
    }


def _pares_avanzado(d: dict[str, Any], idioma: str = "es") -> list[tuple[str, str]]:
    """Todos los campos del formulario de pesaje, para el ticket AVANZADO.

    Devuelve pares (etiqueta, valor) incluyendo vacíos, de modo que el layout
    avanzado refleje absolutamente toda la información que capturó el formulario
    (no solo los 3-4 campos que ya tenía).
    """
    costo = d.get("costo_flete_raw")
    un = d.get("unidades_raw")
    dens = d.get("densidad_raw")
    dens_txt = _fmt_densidad(dens, idioma) or ""
    pares: list[tuple[str, str]] = [
        (f"{t('documento', idioma)}:", d["documento"] or ""),
        ("Guía SUNAGRO:", d.get("guia_sunagro") or ""),
        ("Medida:", d.get("medida") or ""),
        ("Flete:", d.get("flete") or ""),
        ("Costo Flete:", _fmt(costo, lang=idioma) if costo is not None else ""),
        (f"{t('unidades', idioma)}:", _fmt(un, lang=idioma) if un is not None else ""),
        (f"{t('densidad', idioma)}:", dens_txt),
        (
            "Resultado:",
            _fmt(un * dens, lang=idioma) if un is not None and dens is not None else "",
        ),
    ]
    operador = d.get("operador")
    if operador:
        pares.append((f"{t('operador', idioma)}:", operador))
    return pares


def _pares_catalogo(
    d: dict[str, Any],
    idioma: str = "es",
    rif_empresa: str = "",
) -> list[tuple[str, str]]:
    """Datos de las entidades maestro (empresa, tercero, conductor, transporte,
    remolque, categoría, producto, almacén, balanza) y de los registros de
    control derivados (kardex, sincronización) para el bloque 'DATOS DEL
    CATÁLOGO Y CONTROL' del ticket AVANZADO.

    Solo incluye filas con valor, para que el reporte muestre toda la
    información disponible sin rellenar de vacíos la impresión.
    """
    pares: list[tuple[str, str]] = []

    def _ag(lab: str, val: str | None) -> None:
        val = (val or "").strip()
        if val:
            pares.append((lab, val))

    def _ag_num(lab: str, val: object, unidad: str = "") -> None:
        # No formatear si no hay dato numérico real.
        if val is None:
            return
        try:
            dec_val = Decimal(str(val))
        except (ValueError, TypeError, ArithmeticError):
            return
        if dec_val != dec_val:  # NaN
            return
        texto = f"{_fmt(dec_val, lang=idioma)}"
        if unidad:
            texto += f" {unidad}"
        pares.append((lab, texto))

    _ag(f"RIF {t('empresa', idioma)}:", rif_empresa)
    _ag(f"{t('codigo', idioma)} {t('cliente_proveedor', idioma)}:", d.get("tercero_codigo"))
    _ag(f"{t('rif', idioma)} {t('cliente_proveedor', idioma)}:", d.get("tercero_rif"))
    _ag(f"{t('codigo', idioma)} {t('transporte', idioma)}:", d.get("transporte_codigo"))
    _ag(f"{t('rif', idioma)} {t('transporte', idioma)}:", d.get("transporte_rif"))
    _ag(
        f"{t('conductor', idioma)} {t('cedula', idioma)}:",
        d.get("conductor_cedula"),
    )
    _ag(
        f"{t('telefono', idioma)} {t('conductor', idioma)}:",
        d.get("conductor_telefono"),
    )
    _ag(
        f"{t('licencia', idioma)} {t('conductor', idioma)}:",
        d.get("conductor_licencia"),
    )
    _ag(t("tipo_remolque", idioma), d.get("remolque_tipo"))
    _ag_num(t("tara", idioma), d.get("remolque_tara"), "kg")

    cat = " - ".join(p for p in (d.get("categoria_codigo"), d.get("categoria_nombre")) if p)
    _ag(t("categoria", idioma), cat or None)
    _ag(f"{t('codigo', idioma)} {t('producto', idioma)}:", d.get("producto_codigo"))
    _ag(f"{t('unidad', idioma)} {t('producto', idioma)}:", d.get("producto_unidad"))
    _ag(
        f"{t('kardex', idioma)} {t('producto', idioma)}:",
        d.get("producto_kardex") and t("sincronizado_si", idioma)
        or t("sincronizado_no", idioma),
    )
    _ag(f"{t('codigo', idioma)} {t('almacen', idioma)}:", d.get("almacen_codigo"))
    _ag_num(f"{t('capacidad', idioma)} {t('almacen', idioma)}", d.get("almacen_capacidad"), "t")
    _ag_num(f"{t('stock', idioma)} {t('almacen', idioma)}", d.get("almacen_stock"), "t")
    _ag(f"{t('codigo', idioma)} {t('balanza', idioma)}:", d.get("balanza_codigo"))
    _ag_num(f"{t('capacidad', idioma)} {t('balanza', idioma)}", d.get("balanza_capacidad"), "kg")
    _ag_num(f"{t('division', idioma)}", d.get("balanza_division"), "kg")

    kardex_id = d.get("kardex_mov")
    kardex_val = d.get("kardex_valor")
    if kardex_id is not None and kardex_val is not None:
        mov = t("despacho", idioma) if int(kardex_id) >= Kardex.RANGO_NEGATIVO_DESDE else t("ingreso", idioma)
        _ag(t("kardex", idioma), f"{mov} {_fmt(Decimal(kardex_val), lang=idioma)} kg")
    _ag(
        t("sincronizado", idioma),
        t("sincronizado_si", idioma) if d.get("sincronizado") else t("sincronizado_no", idioma),
    )
    return pares


# ─────────────────────────────────────────────────────────────────────────────
# Fuentes TTF (PDF)
# ─────────────────────────────────────────────────────────────────────────────
def _registrar_ttf() -> None:
    """Registra DejaVu Sans (regular + bold) una sola vez.

    Busca las fuentes en rutas de Linux y Windows (incluyendo el bundle
    de PyInstaller). Si no se encuentra DejaVu, usa las fuentes Type1
    built-in de ReportLab (Helvetica) reasignando los nombres de módulo,
    ya que ``TTFont()`` solo acepta rutas de archivo ``.ttf``.
    """
    global _FUENTES_REGISTRADAS, FUENTE, FUENTE_BOLD
    if _FUENTES_REGISTRADAS:
        return

    base = bold = None
    candidatas = [
        # Linux (Debian/Ubuntu)
        (
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        ),
    ]

    # Windows: buscar en fuentes del sistema y bundle de PyInstaller
    if sys.platform == "win32" or os.name == "nt":
        windir = os.environ.get("WINDIR", r"C:\Windows")
        rutas_extra = [
            os.path.join(windir, "Fonts"),
        ]
        # Bundle de PyInstaller (fuentes embebidas)
        if getattr(sys, "frozen", False):
            meipass = getattr(sys, "_MEIPASS", "")
            if meipass:
                rutas_extra.append(os.path.join(meipass, "fonts"))
                rutas_extra.append(meipass)
        # Directorio del módulo actual (por si las fuentes están junto al .py)
        rutas_extra.append(os.path.dirname(os.path.abspath(__file__)))
        for directorio in rutas_extra:
            candidatas.append((
                os.path.join(directorio, "DejaVuSans.ttf"),
                os.path.join(directorio, "DejaVuSans-Bold.ttf"),
            ))

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
        # Fallback: usar las fuentes Type1 built-in de ReportLab.
        # TTFont() exige una ruta de archivo .ttf; Helvetica es Type1 y
        # ya viene registrada en ReportLab, así que reasignamos los
        # nombres de módulo para que todo el código PDF use Helvetica.
        FUENTE = "Helvetica"
        FUENTE_BOLD = "Helvetica-Bold"

    _FUENTES_REGISTRADAS = True


# ─────────────────────────────────────────────────────────────────────────────
# Cabecera de empresa
# ─────────────────────────────────────────────────────────────────────────────
def _ruta_logo(empresa: Empresa | None) -> str | None:
    """Ruta en disco del logo de la empresa (``/media/...`` → media_dir).

    Devuelve ``None`` si no hay logo, si la URL es externa (el backend no la
    descarga) o si el archivo ya no existe en el servidor. Nunca revienta: un
    logo roto no puede tumbar la impresión de un boleto.
    """
    if empresa is None:
        return None
    url = (getattr(empresa, "logo_url", None) or "").strip()
    if not url or url.startswith(("http://", "https://")):
        return None
    # /media/<subcarpeta>/<archivo>  ->  <MEDIA_DIR>/<subcarpeta>/<archivo>
    rel = url.split("/media/", 1)[-1].split("?", 1)[0] if "/media/" in url else url.lstrip("/")
    rel = os.path.normpath(rel).lstrip(os.sep)
    if rel.startswith(".."):
        return None
    ruta = os.path.join(settings.media_dir, rel)
    return ruta if os.path.isfile(ruta) else None


def _logo_flowable(
    ruta: str | None, ancho_util: float, alto_max: float = 12 * mm, ancho_max: float = 45 * mm
) -> Image | None:
    """Logo centrado con proporción preservada; ``None`` si no se puede usar."""
    if not ruta:
        return None
    try:
        iw, ih = ImageReader(ruta).getSize()
        if iw <= 0 or ih <= 0:
            return None
        escala = min(ancho_max / iw, alto_max / ih)
        img = Image(ruta, width=iw * escala, height=ih * escala)
        img.hAlign = "CENTER"
        return img
    except Exception:  # noqa: BLE001 - imagen ilegible/unsupported: sin logo
        return None


def _linea_contacto(
    cab: Mapping[str, object], idioma: str, con_email: bool = True
) -> str:
    """Datos de contacto del emisor en una línea: ``Tel.: X · Dirección: Y``.

    Se omite lo que la empresa no tenga guardado. Para el ticket térmico
    (``con_email=False``) se deja fuera el email para no gastar ancho.
    """
    partes: list[str] = []
    telefono = cab.get("telefono")
    direccion = cab.get("direccion")
    email = cab.get("email")
    if telefono:
        partes.append(f'{t("etiqueta_telefono", idioma)}: {telefono}')
    if direccion:
        partes.append(f'{t("etiqueta_direccion", idioma)}: {direccion}')
    if con_email and email:
        partes.append(str(email))
    return "  ·  ".join(partes)


def _empresa_cabecera(empresa: Empresa | None) -> dict[str, str]:
    """Datos de la empresa para el encabezado del boleto.

    Nombre, RIF y datos de contacto (teléfono, dirección, email) más la ruta del
    logo, para que el comprobante identifique a la estación que lo emite. Todos
    los valores quedan como ``str`` (vacíos si faltan); el logo vacío indica que
    no hay imagen que incrustar.
    """
    # getattr: los datos de contacto son opcionales y el servicio tolera un
    # Empresa projections parcial (p. ej. en pruebas o selects reducidos).
    if empresa is None:
        return {"nombre": "", "rif": "", "telefono": "", "direccion": "", "email": "", "logo": ""}
    return {
        "nombre":    (empresa.nombre_comercial or empresa.nombre_fiscal or "").strip(),
        "rif":       (empresa.rif_nit or "").strip(),
        "telefono":  (getattr(empresa, "telefono", None) or "").strip(),
        "direccion": " ".join((getattr(empresa, "direccion", None) or "").split()),
        "email":     (getattr(empresa, "email", None) or "").strip(),
        "logo":      _ruta_logo(empresa) or "",
    }


# ─────────────────────────────────────────────────────────────────────────────
# Tamaños de papel (PDF)
# ─────────────────────────────────────────────────────────────────────────────
_TAMANOS: dict[str, tuple[float, float]] = {
    "Letter":     letter,                        # 216 × 279 mm
    # Media carta vertical: 5,5 × 8,5 pulgadas. En horizontal, la opción
    # orientacion="landscape" invierte estas dimensiones automáticamente.
    "HalfLetter": (letter[0] / 2, letter[1]),    # 139,7 × 215,9 mm
    "A4":         (210 * mm, 297 * mm),
    "80mm":       (80  * mm, 297 * mm),          # rollo térmico
    "58mm":       (58  * mm, 297 * mm),          # rollo térmico estrecho
}


# ─────────────────────────────────────────────────────────────────────────────
# Estilos de párrafo (PDF)
# FUENTE: TicketPreviewDialog._buildSingleTicketBlock (Flutter)
# ─────────────────────────────────────────────────────────────────────────────
def _tamano_estilo(base: ParagraphStyle, tamano: float, nombre: str) -> ParagraphStyle:
    """Clona un estilo con tamaño e interlineado proporcionales."""
    anterior = max(float(getattr(base, "fontSize", tamano) or tamano), 0.1)
    leading_anterior = float(getattr(base, "leading", anterior + 1) or anterior + 1)
    leading = max(tamano, leading_anterior * tamano / anterior)
    return ParagraphStyle(
        f"{getattr(base, 'name', 'estilo')}_{nombre}_{tamano:.2f}",
        parent=base,
        fontSize=tamano,
        leading=leading,
    )


def _config_tamanos_formato(
    configuracion: Mapping[str, Any] | None,
    tamano_papel: str,
) -> dict[str, dict[str, float]]:
    """Normaliza los tamaños por formato y sección.

    Estructura admitida:
    {
      "80mm": {
        "boleto_pesaje": {"titulo_pt": 10, "texto_pt": 8},
        "lectura_peso": {"titulo_pt": 8, "texto_pt": 6},
        "datos_adicionales": {"titulo_pt": 8, "texto_pt": 7}
      }
    }
    Los valores son puntos tipográficos. Se ignoran claves/valores inválidos.
    """
    if not isinstance(configuracion, Mapping):
        return {}
    aliases = {
        "Carta": "Letter", "carta": "Letter", "LETTER": "Letter",
        "Media carta": "HalfLetter", "Media Carta": "HalfLetter",
        "media carta": "HalfLetter", "Half Letter": "HalfLetter",
        "A4": "A4", "80mm": "80mm", "58mm": "58mm",
    }
    clave_formato = aliases.get(tamano_papel, tamano_papel)
    por_formato = configuracion.get(clave_formato)
    if por_formato is None:
        # Acepta también la etiqueta visible de la interfaz aunque internamente
        # el generador use Letter/HalfLetter.
        por_formato = configuracion.get(tamano_papel, {})
    if not isinstance(por_formato, Mapping):
        return {}
    resultado: dict[str, dict[str, float]] = {}
    for seccion in ("boleto_pesaje", "lectura_peso", "datos_adicionales"):
        valores = por_formato.get(seccion, {})
        if not isinstance(valores, Mapping):
            continue
        limpios: dict[str, float] = {}
        for clave in ("titulo_pt", "texto_pt"):
            valor_crudo = valores.get(clave)
            # Una clave ausente o explícitamente nula significa "usar el estilo
            # predeterminado"; no convertir None a float.
            if valor_crudo is None:
                continue
            try:
                valor = float(valor_crudo)
            except (TypeError, ValueError, OverflowError):
                continue
            # Evita tamaños ilegibles o capaces de desbordar el documento.
            if 4.0 <= valor <= 24.0:
                limpios[clave] = valor
        if limpios:
            resultado[seccion] = limpios
    return resultado


def _estilos_simples(ts: float = 10.5) -> dict[str, ParagraphStyle]:
    """Estilos para el layout 2 columnas idéntico al widget Flutter.

    ts = tamaño base de texto; lo elige ``_build_pdf`` subiendo o bajando por
    la escalera hasta que el boleto cabe en el alto disponible de una página.

    Los estilos del bloque de datos (``term_*``) forman DOS columnas: la
    etiqueta (``term_etq``, negrita) se pega al borde DERECHO de su celda y el
    valor (``term_val`` / ``term_val_bold``) al borde IZQUIERDO de la siguiente,
    con ``_GAP_ETIQUETA_TERMICA`` de aire entre ambas. Cada mitad tiene su propia
    alineación, así que se pueden mover por separado; una sola —como cuando toda
    la fila era un ``Paragraph``— movería las dos. Los usan el rollo térmico y
    la hoja por igual: el tamaño de la etiqueta y del valor se ajusta con
    ``_DS_TAM_ETIQ_FILA`` / ``_DS_TAM_VALOR_FILA`` (ver el changelog del final
    del módulo).
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
        # Teléfono / dirección / email — centrado, gris, un punto menor que el RIF
        "contacto_c": ParagraphStyle(
            "contacto_c", parent=es["Normal"],
            fontName=FUENTE, fontSize=ts - 1.5, leading=ts + 0.5,
            alignment=TA_CENTER, textColor=GRIS_MEDIO,
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
        # Etiqueta de la fila de la TABLA de lecturas (columna 1): izquierda,
        # negrita. Las filas "Etiqueta | valor" (DATOS, operador, ADICIONALES y
        # CATÁLOGO) ya no usan `label_l`: van con `term_etq`/`term_val`, que
        # alinean la etiqueta a la DERECHA en los dos formatos (rollo y hoja).
        "label_l": ParagraphStyle(
            "label_l", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts - 0.5, leading=ts + 1.5,
            alignment=TA_LEFT, textColor=colors.black,
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
        # Aviso de peso escrito manualmente (sin báscula) — negrita, rojo
        "peso_manual_c": ParagraphStyle(
            "peso_manual_c", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts, leading=ts + 1.5,
            alignment=TA_CENTER, textColor=colors.HexColor("#C62828"),
        ),
        # ── Estilos del ticket térmico (80mm/58mm) ───────────────────────────
        # Fila "Etiqueta | valor" en DOS celdas con alineación independiente:
        #
        #     |   Etiqueta: |valor            |
        #       TA_RIGHT      TA_LEFT
        #
        # La etiqueta se pega a la derecha de su celda (contra el separador
        # imaginario) y el valor arranca pegado a la izquierda de la suya. Con
        # UNA sola alineación por fila —como cuando toda la línea era un único
        # Paragraph— no se puede mover cada mitad por separado: esto es lo que
        # sustituye a `term_linea`/`term_linea_bold`.
        #
        # `splitLongWords=0` hace que el wrap sea POR PALABRA y no por carácter:
        # una etiqueta o un valor largo se envuelve completo a la siguiente
        # línea, jamás partido a media palabra. Cada celda envuelve DENTRO de su
        # columna, así que las dos mitades nunca se pisan.
        "term_etq": ParagraphStyle(
            "term_etq", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts + _DS_TAM_ETIQ_FILA,
            # Interlineado recortado en la MISMA medida en que la etiqueta es más
            # pequeña que el valor: la fila no crece (el alto lo manda el leading
            # del valor) y `_fila_t` compensa la línea base por el hueco que
            # queda. Ver `_DS_TAM_ETIQ_FILA`.
            leading=(ts + 1.5) + (_DS_TAM_ETIQ_FILA - _DS_TAM_VALOR_FILA),
            alignment=TA_RIGHT, textColor=colors.black,
            splitLongWords=0,
        ),
        # Valor de la fila, alineado a la IZQUIERDA (normal)
        "term_val": ParagraphStyle(
            "term_val", parent=es["Normal"],
            fontName=FUENTE, fontSize=ts + _DS_TAM_VALOR_FILA, leading=ts + 1.5,
            alignment=TA_LEFT, textColor=colors.black,
            splitLongWords=0,
        ),
        # Valor de la fila resaltada (Serie - Boleto)
        "term_val_bold": ParagraphStyle(
            "term_val_bold", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts + _DS_TAM_VALOR_FILA, leading=ts + 1.5,
            alignment=TA_LEFT, textColor=colors.black,
            splitLongWords=0,
        ),
        # Encabezados de sección del térmico (LECTURA DE PESOS, OBSERVACIONES, …)
        "term_seccion": ParagraphStyle(
            "term_seccion", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts - 0.5, leading=ts + 1,
            alignment=TA_CENTER, textColor=colors.black,
            splitLongWords=0,
        ),
        # Observaciones térmicas — gris, pequeño, respeta saltos de línea
        "term_obs": ParagraphStyle(
            "term_obs", parent=es["Normal"],
            fontName=FUENTE, fontSize=ts - 0.5, leading=ts + 0.5,
            alignment=TA_LEFT, textColor=GRIS_MEDIO,
            splitLongWords=0,
        ),
        # Pie del térmico — pequeño, gris
        "term_pie": ParagraphStyle(
            "term_pie", parent=es["Normal"],
            fontName=FUENTE, fontSize=ts - 0.5, leading=ts - 0.5,
            alignment=TA_LEFT, textColor=GRIS_MEDIO,
            splitLongWords=0,
        ),
        # Línea con el nombre de empresa debajo del título (Caso B, solo térmico)
        "term_titulo_empresa": ParagraphStyle(
            "term_titulo_empresa", parent=es["Normal"],
            fontName=FUENTE, fontSize=ts - 1, leading=ts,
            alignment=TA_CENTER, textColor=GRIS_TEXTO,
            splitLongWords=0,
        ),
        # ── Tabla de lecturas de peso del térmico (5 columnas) ───────────────
        # (Etiqueta | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL). El estilo base va un
        # punto y medio por debajo del cuerpo; el tamaño REAL lo pone
        # `_tamano_tabla_pesos` (las 5 columnas comparten uno).
        "term_tab_hdr": ParagraphStyle(
            "term_tab_hdr", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts - 2, leading=ts - 0.5,
            alignment=TA_CENTER, textColor=colors.black,
            splitLongWords=0,
        ),
        "term_tab_lab": ParagraphStyle(
            "term_tab_lab", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts - 2, leading=ts - 0.5,
            alignment=TA_LEFT, textColor=colors.black,
            splitLongWords=0,
        ),
        "term_tab_val": ParagraphStyle(
            "term_tab_val", parent=es["Normal"],
            fontName=FUENTE, fontSize=ts - 2, leading=ts - 0.5,
            alignment=TA_RIGHT, textColor=colors.black,
            splitLongWords=0,
        ),
        "term_tab_val_bold": ParagraphStyle(
            "term_tab_val_bold", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts - 2, leading=ts - 0.5,
            alignment=TA_RIGHT, textColor=colors.black,
            splitLongWords=0,
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
    idioma: str = "es",
) -> Table:
    """Recuadro rojo 'DOCUMENTO ANULADO' + motivo (espejo del bloque TXT)."""
    motivo = d["motivo_anulacion"] or t("no_especificado", idioma)
    texto = (
        f'<font color="#C53030"><b>{t("doc_anulado", idioma)}</b></font><br/>'
        f'<font size="8">{_esc(t("motivo", idioma))}: {_esc(motivo)}</font>'
    )
    t_elem = Table([[Paragraph(texto, st["obs"])]], colWidths=[ancho_util])
    t_elem.setStyle(TableStyle([
        ("BOX", (0, 0), (-1, -1), 1, ROJO_ANULADO),
        ("TOPPADDING",    (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("LEFTPADDING",   (0, 0), (-1, -1), 5),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 5),
        ("VALIGN",        (0, 0), (-1, -1), "TOP"),
    ]))
    return t_elem


def _build_boleto_simple(
    d: dict[str, Any],
    cab: dict[str, str],
    st: dict[str, ParagraphStyle],
    ancho_util: float,
    mostrar_encabezado: bool = True,
    mostrar_detalles: bool = True,
    compact: bool = False,
    idioma: str = "es",
    tipo_ticket: str = "simple",
    configuracion_tamanos: Mapping[str, Any] | None = None,
    mostrar_qr: bool = True,
) -> list[Any]:
    """Construye la lista de flowables de UN boleto con i18n."""
    cfg = configuracion_tamanos or {}
    cfg_boleto = cfg.get("boleto_pesaje", {}) if isinstance(cfg, Mapping) else {}
    cfg_lectura = cfg.get("lectura_peso", {}) if isinstance(cfg, Mapping) else {}
    cfg_adicionales = cfg.get("datos_adicionales", {}) if isinstance(cfg, Mapping) else {}

    # Estilos independientes: cambiar una sección no modifica las otras.
    if isinstance(cfg_boleto, Mapping):
        if cfg_boleto.get("titulo_pt") is not None:
            st["titulo_c"] = _tamano_estilo(st["titulo_c"], float(cfg_boleto["titulo_pt"]), "boleto_titulo")
        if cfg_boleto.get("texto_pt") is not None:
            tam = float(cfg_boleto["texto_pt"])
            for clave in ("term_etq", "term_val", "term_val_bold"):
                st[clave] = _tamano_estilo(st[clave], tam, f"boleto_{clave}")

    if isinstance(cfg_lectura, Mapping):
        if cfg_lectura.get("titulo_pt") is not None:
            tam = float(cfg_lectura["titulo_pt"])
            st["lectura_titulo"] = _tamano_estilo(
                st["term_seccion"] if compact else st["seccion_c"], tam, "lectura_titulo"
            )
        else:
            st["lectura_titulo"] = st["term_seccion"] if compact else st["seccion_c"]
        if cfg_lectura.get("texto_pt") is not None:
            tam = float(cfg_lectura["texto_pt"])
            for clave in ("term_tab_hdr", "term_tab_lab", "term_tab_val", "term_tab_val_bold",
                          "tab_hdr", "label_l", "tab_val", "tab_val_bold"):
                if clave in st:
                    st[clave] = _tamano_estilo(st[clave], tam, f"lectura_{clave}")
    else:
        st["lectura_titulo"] = st["term_seccion"] if compact else st["seccion_c"]

    if isinstance(cfg_adicionales, Mapping):
        if cfg_adicionales.get("titulo_pt") is not None:
            tam = float(cfg_adicionales["titulo_pt"])
            st["adicionales_titulo"] = _tamano_estilo(
                st["term_seccion"] if compact else st["seccion_c"], tam, "adicionales_titulo"
            )
        else:
            st["adicionales_titulo"] = st["term_seccion"] if compact else st["seccion_c"]
    else:
        st["adicionales_titulo"] = st["term_seccion"] if compact else st["seccion_c"]

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

    # ── 1. Encabezado empresa ─────────────────────────────────────────────────
    # Layout horizontal:
    #   CON logo → tabla [logo | datos] SIN línea divisoria vertical.
    #     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    #       LOGO    VARIEDADES S&S - RIF: J-12345678-9
    #               [Dirección] - Tel.: ... - email
    #     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    #   SIN logo → solo el texto alineado a la izquierda.
    if mostrar_encabezado and cab["nombre"]:
        els: list[Any] = []
        logo = None if compact else _logo_flowable(
            cab["logo"], ancho_util, alto_max=14 * mm, ancho_max=20 * mm
        )

        # Bloque de texto derecho (nombre + RIF / dirección + contacto).
        rif_txt = f'{t("etiqueta_rif", idioma)}: {cab["rif"]}' if cab["rif"] else ""
        linea1 = " - ".join(x for x in [cab["nombre"], rif_txt] if x)

        partes_contacto: list[str] = []
        if cab["direccion"]:
            partes_contacto.append(cab["direccion"])
        if cab["telefono"]:
            partes_contacto.append(
                f'{t("etiqueta_telefono", idioma)}: {cab["telefono"]}'
            )
        # En térmico el email no cabe: se omite para no partir la línea.
        if not compact and cab["email"]:
            partes_contacto.append(cab["email"])
        linea2 = " - ".join(partes_contacto)

        # Estilos del bloque derecho, alineados a la izquierda (no centrados).
        base_l1 = st["empresa_c"]
        estilo_l1 = ParagraphStyle(
            "emp_l1", parent=base_l1,
            alignment=TA_LEFT,
            fontSize=getattr(base_l1, "fontSize") - 1.5,  # noqa: B009 - no declarado en los stubs de reportlab
            leading=getattr(base_l1, "leading") - 1,  # noqa: B009
        )
        estilo_l2 = ParagraphStyle(
            "emp_l2", parent=st["contacto_c"], alignment=TA_LEFT,
        )

        texto_derecha: list[Any] = [Paragraph(_esc(linea1), estilo_l1)]
        if linea2:
            texto_derecha.append(Spacer(1, 0.4 * mm))
            texto_derecha.append(Paragraph(_esc(linea2), estilo_l2))

        if logo is not None:
            # ── CON logo: tabla [logo | datos] SIN línea divisoria ──
            cabecera = Table(
                [[logo, texto_derecha]],
                colWidths=[ancho_util * 0.22, ancho_util * 0.78],
            )
            cabecera.setStyle(TableStyle([
                ("VALIGN",    (0, 0), (-1, -1), "MIDDLE"),
                ("ALIGN",     (0, 0), (0, 0),   "CENTER"),
                ("ALIGN",     (1, 0), (1, 0),   "LEFT"),
                ("LEFTPADDING",   (0, 0), (-1, -1), 0),
                ("RIGHTPADDING",  (0, 0), (-1, -1), 8),
                ("TOPPADDING",    (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
                # Nota: SIN LINEAFTER → sin línea divisoria vertical entre logo y datos.
            ]))
            els.append(cabecera)
        else:
            # ── SIN logo: solo el texto alineado a la izquierda ──
            els.extend(texto_derecha)

        els.append(Spacer(1, 1.0 * mm))
        els.append(_hr_negro(1.0))
        els.append(Spacer(1, 1.2 * mm))
    else:
        els = []

    # ── 2. Título ─────────────────────────────────────────────────────────────
    els.append(Paragraph(t("titulo_boleto", idioma), st["titulo_c"]))
    els.append(Spacer(1, 0.8 * mm))
    els.append(_hr_gris())
    els.append(Spacer(1, 1.2 * mm))

    # ── Fila "Etiqueta | valor" (DOS celdas con alineación independiente) ────
    # La usan TANTO el rollo térmico (80/58 mm) COMO la hoja (media carta,
    # carta y A4): la misma forma en todos los formatos.
    #
    #     |      Etiqueta: |valor                  |
    #        TA_RIGHT         TA_LEFT
    #
    # La etiqueta (negrita) se alinea a la DERECHA de su celda y el valor a la
    # IZQUIERDA de la suya, así que cada mitad se mueve por su cuenta. Un solo
    # Paragraph movía las dos mitades con la misma variable de alineación: era
    # imposible pedir "etiqueta a la derecha, valor a la izquierda". Las celdas
    # son Paragraphs (envuelven por palabra dentro de su columna), no cadenas
    # sueltas, así que nunca se pisan.
    #
    # El reparto es POR GRUPO (``_apilar_t``): la columna de la etiqueta mide lo
    # que pide la etiqueta MÁS LARGA del grupo y el valor se queda con todo lo
    # demás, de modo que todos los valores del grupo arrancan en la misma
    # vertical.
    #
    # Los estilos (``term_etq``/``term_val``/``term_val_bold``) son COMPARTIDOS:
    # un solo ajuste de tamaño del bloque de datos vale para el rollo y para la
    # hoja.
    #
    # `fontSize` existe en tiempo de ejecución pero no en los stubs.
    cuerpo_fila = float(getattr(st["term_etq"], "fontSize", 0.0))

    def _fila_t(
        etiqueta: str,
        valor: str,
        ancho_etq: float,
        bold: bool = False,
        estilo_etq: ParagraphStyle | None = None,
        padding_y: float = 0.0,
    ) -> Table:
        """Fila "Etiqueta | valor" con las dos mitades independientes.

        La etiqueta se pega al borde DERECHO de su celda y el valor al IZQUIERDO
        de la suya, con ``_GAP_ETIQUETA_TERMICA`` de aire entre ambos (sin ese
        hueco se tocarían: "Cliente/Proveedor:PROVEEDOR …").

        ``ancho_etq`` es el ancho de la columna de etiquetas, que comparten
        todas las filas del mismo grupo (lo calcula ``_apilar_t``).

        - ``bold=True`` (Serie - Boleto): valor en negrita.
        - ``bold=False``: etiqueta en negrita y valor en texto normal.
        - ``estilo_etq``: estilo de la etiqueta (por defecto ``term_etq``); el
          grupo cuya etiqueta más larga no cabe en su columna pasa la variante
          que la parte por carácter.
        - ``padding_y``: aire arriba y abajo de la fila. El rollo va a 0 (cada
          milímetro cuenta) y la hoja a 1 pt, que es su ritmo de siempre.
        """
        estilo_val = st["term_val_bold"] if bold else st["term_val"]
        estilo_lab = estilo_etq or st["term_etq"]
        # La línea base de la primera línea de un Paragraph cae a ``descent`` del
        # borde superior de su celda, y ``descent`` solo depende del TAMAÑO (el
        # ``leading`` no la mueve): medido, la línea base baja tantos puntos como
        # puntos MÁS GRANDE sea la fuente. Sin corregirlo, la mitad que va más
        # pequeña queda por encima de su compañera y las dos celdas dejan de
        # compartir la vertical (pypdf las entrega como dos líneas distintas).
        #
        # La corrección es SIMÉTRICA porque ``_DS_TAM_ETIQ_FILA`` y
        # ``_DS_TAM_VALOR_FILA`` pueden dejar la etiqueta más pequeña que el
        # valor o al revés: se rellena por arriba la celda de fuente MÁS PEQUEÑA
        # —la que tiene la línea base más alta— con la diferencia de tamaños.
        # El ``leading`` de la etiqueta ya viene recortado en esa misma
        # diferencia (ver ``_estilos_simples``), así que la fila NO crece.
        tam_lab = float(getattr(estilo_lab, "fontSize", 0.0))
        tam_val = float(getattr(estilo_val, "fontSize", 0.0))
        desfase = tam_val - tam_lab
        baja_lab = max(0.0, desfase)
        baja_val = max(0.0, -desfase)
        fila = Table(
            [[
                Paragraph(f"{_esc(etiqueta)}:", estilo_lab),
                Paragraph(_esc(valor), estilo_val),
            ]],
            colWidths=[ancho_etq, ancho_util - ancho_etq],
        )
        fila.setStyle(TableStyle([
            ("VALIGN",        (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING",   (0, 0), (-1, -1), 0),
            ("RIGHTPADDING",  (0, 0), (-1, -1), 0),
            # Celda de la etiqueta: el relleno de arriba la baja hasta su valor.
            ("TOPPADDING",    (0, 0), (0, 0), padding_y + baja_lab),
            ("BOTTOMPADDING", (0, 0), (0, 0), padding_y),
            # Celda del valor: el mismo relleno cuando es ella la que va más
            # pequeña (etiqueta más grande que el valor).
            ("TOPPADDING",    (1, 0), (1, 0), padding_y + baja_val),
            ("BOTTOMPADDING", (1, 0), (1, 0), padding_y),
            ("RIGHTPADDING",  (0, 0), (0, 0), _GAP_ETIQUETA_TERMICA),
        ]))
        return fila

    def _apilar_t(
        pares: Sequence[tuple[str, str, bool]], padding_y: float = 0.0
    ) -> None:
        """Apila un grupo de filas "Etiqueta | valor".

        Las filas de un mismo grupo comparten la columna de etiquetas —la que
        pide la más larga del grupo— para que sus valores arranquen todos en la
        misma vertical. ``padding_y`` se pasa a cada fila.
        """
        ancho_etq, cortar = _ancho_etiqueta_termica(
            ancho_util, (etq for etq, _valor, _bold in pares), cuerpo_fila
        )
        estilo_etq = st["term_etq"]
        if cortar:
            # La etiqueta más larga del grupo no cabe ni con el tope: se parte
            # por carácter. Es feo, pero desbordar la celda se pisaría con el
            # valor (mismo criterio que la tabla de lecturas).
            estilo_etq = ParagraphStyle(
                "term_etq_cjk", parent=estilo_etq, wordWrap="CJK"
            )
        for etq, valor, bold in pares:
            els.append(_fila_t(etq, valor, ancho_etq, bold, estilo_etq, padding_y))

    def _apilar_adicionales(
        pares: Sequence[tuple[str, str, bool]], padding_y: float = 0.0
    ) -> None:
        """Pinta las filas adicionales con su tamaño independiente."""
        tam = cfg_adicionales.get("texto_pt") if isinstance(cfg_adicionales, Mapping) else None
        if tam is None:
            _apilar_t(pares, padding_y=padding_y)
            return
        originales = {k: st[k] for k in ("term_etq", "term_val", "term_val_bold")}
        try:
            for clave, estilo in originales.items():
                st[clave] = _tamano_estilo(estilo, float(tam), f"adicionales_{clave}")
            _apilar_t(pares, padding_y=padding_y)
        finally:
            st.update(originales)

    # ═══════════════════════ VARIANTE COMPACTA (térmico) ═════════════════════
    if compact:
        # ── 3. DATOS ──────────────────────────────────────────────────────────
        pares_datos: list[tuple[str, str, bool]] = [
            (t("serie_boleto", idioma), d["numero"], True),
            (t("fecha_hora", idioma),   d["fecha_hora"], False),
            (t("camion", idioma),       d["camion"], False),
        ]
        if tipo_ticket == "avanzado" and d.get("color_camion"):
            pares_datos.append((t("camion_color", idioma), d["color_camion"], False))
        pares_datos += [
            (t("remolque", idioma),   d["remolque"], False),
            (t("transporte", idioma), d["transporte"], False),
            (t("conductor", idioma),  d["conductor"], False),
            (t("producto", idioma),   d["producto"], False),
            (t("almacen", idioma),    d["almacen"], False),
            (t("cliente_proveedor", idioma), d["razon_social"], False),
        ]
        _apilar_t(pares_datos)

        # ── 4. LECTURA DE PESOS ───────────────────────────────────────────────
        els.append(Spacer(1, 1.5 * mm))
        els.append(_hr_negro(1.0))
        els.append(Spacer(1, 0.8 * mm))
        els.append(Paragraph(t("lectura_pesos", idioma), st["lectura_titulo"]))
        els.append(Spacer(1, 0.8 * mm))
        els.append(_hr_gris())
        els.append(Spacer(1, 1.2 * mm))

        # Tabla de lecturas de peso (MISMO contenido que la hoja y el TXT):
        #   (etiqueta) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL
        # con una fila por pesada (ENTRADA / SALIDA), la de TOTALES (los netos
        # por vehículo) y el PESO NETO.
        #
        # NADA se solapa: el ancho se reparte con _RATIOS_TABLA_PESOS y el
        # tamaño de fuente lo fija _tamano_tabla_pesos() a partir de las 5
        # columnas, de modo que ni la fecha "dd/mm/aaaa" ni la cabecera
        # "REMOLQUE" se partan, ni en 80 mm ni en 58 mm.
        filas_raw = _filas_lectura_pesos(d, idioma)

        # Tamaño de la tabla: la columna más exigente manda y todas comparten
        # tamaño, así que la más estrecha manda de verdad. Con el tope de
        # ts-2 (antes fijo) la tabla ya baja a lo que cada rollo permite.
        requiere = _anchos_requeridos_pesos(filas_raw, 5)
        # `fontSize` existe en tiempo de ejecución pero no en los stubs.
        tope_tab = float(getattr(st["term_tab_val"], "fontSize", 0.0))
        # El tamaño se calcula con los MISMOS ratios que reparten las columnas
        # en la `Table` de abajo (`_RATIOS_TABLA_PESOS`, el reparto del rollo):
        # midiendo con otro reparto, la columna que manda no es la que manda.
        tam_tab, cortar = _tamano_tabla_pesos(ancho_util, requiere, tope_tab)
        st_tab = _estilos_celda_pesos(
            {
                "hdr": st["term_tab_hdr"],
                "lab": st["term_tab_lab"],
                "val": st["term_tab_val"],
                "val_bold": st["term_tab_val_bold"],
            },
            tam_tab,
            cortar,
        )

        def _celda_term(texto: str, tipo: str = "val") -> Paragraph:
            return Paragraph(_esc(texto) or "", st_tab[tipo])

        filas_tab = [
            [_celda_term(texto_raw, tipo) for texto_raw, tipo in fila_raw]
            for fila_raw in filas_raw
        ]
        idx_neto_t = len(filas_tab) - 1
        tabla_pesos = Table(
            filas_tab,
            colWidths=[ancho_util * r for r in _RATIOS_TABLA_PESOS],
        )
        tabla_pesos.setStyle(TableStyle([
            ("VALIGN",        (0, 0), (-1, -1), "TOP"),
            ("TOPPADDING",    (0, 0), (-1, -1), 1.5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 1.5),
            ("LEFTPADDING",   (0, 0), (-1, -1), 0),
            ("RIGHTPADDING",  (0, 0), (-1, -1), 0),
            # Línea bajo la cabecera y sobre PESO NETO (espejo de la hoja).
            ("LINEBELOW",     (0, 0), (-1, 0), 0.5, colors.HexColor("#999999")),
            ("LINEABOVE",     (0, idx_neto_t), (-1, idx_neto_t), 0.5,
             colors.HexColor("#999999")),
        ]))
        els.append(tabla_pesos)
        els.append(Spacer(1, 0.8 * mm))
        els.append(_hr_negro(1.0))

        # ── 4b. PESO MANUAL ───────────────────────────────────────────────────
        if d["peso_manual"]:
            els.append(Paragraph(t("peso_manual", idioma), st["term_seccion"]))
            if d.get("operador"):
                els.append(Spacer(1, 0.5 * mm))
                _apilar_t([(t("operador", idioma), d["operador"], False)])
            els.append(Spacer(1, 0.8 * mm))

        # ── 5. AVANZADO: datos adicionales + catálogo y control ───────────────
        if tipo_ticket == "avanzado":
            pares_adv = _pares_avanzado(d, idioma)
            if pares_adv:
                els.append(Spacer(1, 0.8 * mm))
                els.append(Paragraph(t("datos_adicionales", idioma), st["adicionales_titulo"]))
                els.append(Spacer(1, 0.8 * mm))
                els.append(_hr_gris())
                els.append(Spacer(1, 1.0 * mm))
                _apilar_adicionales([
                    (lab.rstrip(":"), val, False) for lab, val in pares_adv
                ])
                els.append(Spacer(1, 0.8 * mm))
                els.append(_hr_negro(1.0))

            pares_cat = _pares_catalogo(d, idioma, rif_empresa=cab["rif"])
            if pares_cat:
                els.append(Spacer(1, 0.8 * mm))
                els.append(Paragraph(t("datos_catalogo", idioma), st["term_seccion"]))
                els.append(Spacer(1, 0.8 * mm))
                els.append(_hr_gris())
                els.append(Spacer(1, 1.0 * mm))
                _apilar_t([
                    (lab.rstrip(":"), val, False) for lab, val in pares_cat
                ])
                els.append(Spacer(1, 0.8 * mm))
                els.append(_hr_negro(1.0))

        # ── 6. OBSERVACIONES (respetando los saltos de línea originales) ─────
        if mostrar_detalles and d["observaciones"]:
            els.append(Spacer(1, 1.0 * mm))
            els.append(Paragraph(t("observaciones", idioma), st["term_seccion"]))
            els.append(Spacer(1, 0.6 * mm))
            els.append(_hr_gris())
            els.append(Spacer(1, 0.8 * mm))
            for obs_linea in d["observaciones"].splitlines():
                # Una línea vacía dentro del texto se conserva como espacio
                # (un Paragraph vacío podría medir 0 y "comerse" el salto).
                els.append(Paragraph(_esc(obs_linea) if obs_linea else " ", st["term_obs"]))
            els.append(Spacer(1, 0.8 * mm))

        # ── 6b. ANULADO (bloque rojo, espejo del TXT) ─────────────────────────
        if (d["estado"] or "").upper() == "ANULADO":
            els.append(Spacer(1, 1.0 * mm))
            els.append(_bloque_anulado(d, st, ancho_util, idioma=idioma))
            els.append(Spacer(1, 0.8 * mm))

        # ── 7. Firmas (solo AVANZADO) ─────────────────────────────────────────
        if tipo_ticket == "avanzado":
            els.append(Spacer(1, 4 * mm))
            firma_izq = Paragraph(
                f"_______________________<br/><b>{t('firma_operador', idioma)}</b>", st["firma_c"],
            )
            firma_der = Paragraph(
                f"_______________________<br/><b>{t('firma_conductor', idioma)}</b>", st["firma_c"],
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

        # ── Pie (dentro del flujo para que el alto dinámico lo incluya) ──────
        # En hoja el pie se dibuja con canvas; en térmico la página crece con
        # el contenido, así que el pie debe ser un flowable más para no quedar
        # fuera de la página medida.
        els.append(Spacer(1, 1.2 * mm))
        els.append(_hr_gris())
        els.append(Paragraph(
            f"{t('estado', idioma)}: "
            f"{_esc(traducir_estado_boleto(d['estado'], idioma))}",
            st["term_pie"],
        ))
        els.append(Paragraph(
            f"{t('impreso', idioma)}: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}",
            st["term_pie"],
        ))
        # En rollo térmico el QR forma parte del flujo, para que el alto dinámico
        # del papel crezca y el código nunca quede cortado al final del ticket.
        # Se imprime solo si la estación lo tiene activado en «Diseño de ticket»
        # y el interruptor global del módulo lo permite.
        if MOSTRAR_QR_EN_REPORTES and mostrar_qr:
            tamano_qr = 29 * mm if ancho_util < 60 * mm else 34 * mm
            els.append(Spacer(1, 1.5 * mm))
            els.append(_QrPesajeFlowable(d, tamano=tamano_qr))
        return els

    # ═══════════════════════ VARIANTE HOJA (Carta/A4) ════════════════════════
    # ── 3. DATOS ──────────────────────────────────────────────────────────────
    # Misma forma que el rollo térmico: la etiqueta se pega a la derecha de su
    # columna y el valor arranca a la izquierda de la suya (la columna la mide
    # `_apilar_t` con la etiqueta más larga del propio grupo).
    pares_datos_hoja: list[tuple[str, str, bool]] = [
        (t("serie_boleto", idioma), d["numero"], True),
        (t("fecha_hora", idioma),   d["fecha_hora"], False),
        (t("camion", idioma),       d["camion"], False),
    ]
    if tipo_ticket == "avanzado" and d.get("color_camion"):
        pares_datos_hoja.append((t("camion_color", idioma), d["color_camion"], False))
    pares_datos_hoja += [
        (t("remolque", idioma),   d["remolque"], False),
        (t("transporte", idioma), d["transporte"], False),
        (t("conductor", idioma),  d["conductor"], False),
        (t("producto", idioma),   d["producto"], False),
        (t("almacen", idioma),    d["almacen"], False),
        (t("seleccion", idioma),  d["seleccion"], False),
        (t("razon_social", idioma), d["razon_social"], False),
    ]
    _apilar_t(pares_datos_hoja, padding_y=_PADDING_FILA_HOJA)

    # ── 4. LECTURA DE PESOS (tabla) ───────────────────────────────────────────
    els.append(Spacer(1, 1.5 * mm))
    els.append(_hr_negro(1.0))
    els.append(Spacer(1, 0.8 * mm))
    els.append(Paragraph(t("lectura_pesos", idioma), st["lectura_titulo"]))
    els.append(Spacer(1, 0.8 * mm))
    els.append(_hr_gris())
    els.append(Spacer(1, 1.2 * mm))

    # ── Tabla de lecturas de peso (la MISMA rejilla que el rollo) ────────────
    # 5 columnas: (etiqueta) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL, con una
    # fila por pesada (ENTRADA / SALIDA), la de TOTALES (los netos por
    # vehículo) y el PESO NETO. La hoja añade después sus dos filas de control
    # (declarado / desviación), que el rollo no lleva.
    filas_raw = _filas_lectura_pesos(d, idioma)

    # El tamaño lo fija el ancho útil, igual que en el rollo: el boleto de hoja
    # mide 100 mm de ancho, así que sin auto-ajuste se partían por la mitad el
    # rótulo "ENTRADA:" y las cabeceras. El tope es el cuerpo (ts - 0.5), que
    # es lo que medía la tabla anterior.
    requiere = _anchos_requeridos_pesos(filas_raw, 5)
    # rama hoja
    tope_tab = float(getattr(st["tab_val"], "fontSize", 0.0))
    tam_tab, cortar = _tamano_tabla_pesos(
        ancho_util, requiere, tope_tab, _RATIOS_TABLA_PESOS_HOJA
    )
    st_tab = _estilos_celda_pesos(
        {
            "hdr": st["tab_hdr"],
            "lab": st["label_l"],
            "val": st["tab_val"],
            "val_bold": st["tab_val_bold"],
        },
        tam_tab,
        cortar,
    )

    def _celda_tab(texto: str, tipo: str = "val") -> Paragraph:
        return Paragraph(_esc(texto) or "", st_tab[tipo])

    rows = [
        [_celda_tab(texto_raw, tipo) for texto_raw, tipo in fila_raw]
        for fila_raw in filas_raw
    ]
    idx_neto = len(rows) - 1

    if d["declarado"] is not None:
        rows.append([
            _celda_tab(f"{t('peso_declarado_diferencia', idioma)}:", "lab"),
            _celda_tab(""), _celda_tab(""),
            _celda_tab(_fmt(d["declarado"], lang=idioma), "val_bold"),
            _celda_tab(_fmt_sig(d["diferencia"], lang=idioma), "val_bold"),
        ])
        if d["desviacion"] is not None:
            rows.append([
                _celda_tab(f"{t('desviacion', idioma)}:", "lab"),
                _celda_tab(""), _celda_tab(""), _celda_tab(""),
                _celda_tab(f"{_fmt(d['desviacion'], lang=idioma)} %", "val_bold"),
            ])

    tabla = Table(rows, colWidths=[ancho_util * r for r in _RATIOS_TABLA_PESOS_HOJA])
    estilo_tabla = [
        ("VALIGN",        (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING",    (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
        ("LEFTPADDING",   (0, 0), (-1, -1), 0),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 0),
        ("LINEBELOW",     (0, 0), (-1, 0), 0.5, colors.HexColor("#999999")),
        ("LINEABOVE",     (0, idx_neto), (-1, idx_neto), 0.5, colors.HexColor("#999999")),
    ]
    tabla.setStyle(TableStyle(estilo_tabla))
    els.append(tabla)
    els.append(Spacer(1, 1.0 * mm))
    els.append(_hr_negro(1.0))

    # ── 4b. PESO MANUAL (escrito a mano, sin báscula) ─────────────────────────
    if d["peso_manual"]:
        els.append(Spacer(1, 0.8 * mm))
        els.append(Paragraph(t("peso_manual", idioma), st["peso_manual_c"]))
        if d.get("operador"):
            els.append(Spacer(1, 0.5 * mm))
            _apilar_t(
                [(t("operador", idioma), d["operador"], False)],
                padding_y=_PADDING_FILA_HOJA,
            )
        els.append(Spacer(1, 0.8 * mm))

    # ── 5. DATOS ADICIONALES ─────────────────────────────────────────────────
    if tipo_ticket == "avanzado":
        dats_adic = _pares_avanzado(d, idioma)
    else:
        dats_adic = []
        if d["documento"]:
            dats_adic.append((f"{t('documento', idioma)}:", d["documento"]))
        if d.get("unidades_txt") is not None:
            dats_adic.append((f"{t('unidades', idioma)}:", d["unidades_txt"]))
        if d.get("densidad_txt") is not None:
            dats_adic.append((f"{t('densidad', idioma)}:", d["densidad_txt"]))

    if dats_adic:
        els.append(Spacer(1, 1.2 * mm))
        els.append(Paragraph(t("datos_adicionales", idioma), st["adicionales_titulo"]))
        els.append(Spacer(1, 0.8 * mm))
        els.append(_hr_gris())
        els.append(Spacer(1, 1.0 * mm))
        _apilar_adicionales(
            [(lab.rstrip(":"), val, False) for lab, val in dats_adic],
            padding_y=_PADDING_FILA_HOJA,
        )
        els.append(Spacer(1, 1.0 * mm))
        els.append(_hr_negro(1.0))

    # ── 5b. DATOS DEL CATÁLOGO Y CONTROL (solo AVANZADO) ─────────────────────
    if tipo_ticket == "avanzado":
        pares_cat = _pares_catalogo(d, idioma, rif_empresa=cab["rif"])
        if pares_cat:
            els.append(Spacer(1, 1.2 * mm))
            els.append(Paragraph(t("datos_catalogo", idioma), st["seccion_c"]))
            els.append(Spacer(1, 0.8 * mm))
            els.append(_hr_gris())
            els.append(Spacer(1, 1.0 * mm))
            _apilar_t(
                [(lab.rstrip(":"), val, False) for lab, val in pares_cat],
                padding_y=_PADDING_FILA_HOJA,
            )
            els.append(Spacer(1, 1.0 * mm))
            els.append(_hr_negro(1.0))

    # ── 6. OBSERVACIONES ──────────────────────────────────────────────────────
    if mostrar_detalles and d["observaciones"]:
        els.append(Spacer(1, 1.2 * mm))
        els.append(Paragraph(t("observaciones", idioma), st["seccion_c"]))
        els.append(Spacer(1, 0.8 * mm))
        els.append(_hr_gris())
        els.append(Spacer(1, 1.0 * mm))
        els.append(Paragraph(_esc(d["observaciones"]), st["obs"]))

    # ── 6b. ANULADO (bloque rojo, espejo del TXT) ─────────────────────────────
    if (d["estado"] or "").upper() == "ANULADO":
        els.append(Spacer(1, 1.2 * mm))
        els.append(_bloque_anulado(d, st, ancho_util, idioma=idioma))

    # ── 7. Firmas (solo AVANZADO: el BÁSICO va sin firmas para ser compacto) ──
    if tipo_ticket == "avanzado":
        els.append(Spacer(1, 4 * mm))
        firma_izq = Paragraph(
            f"________________________<br/><b>{t('firma_operador', idioma)}</b>", st["firma_c"],
        )
        firma_der = Paragraph(
            f"________________________<br/><b>{t('firma_conductor', idioma)}</b>", st["firma_c"],
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

    # El QR se imprime debajo de cada boleto, incluso en Carta/A4/Media carta,
    # cuando la estación lo tiene activado en «Diseño de ticket». Su altura
    # entra en la medición previa, por lo que el autoajuste puede reducir la
    # escala (o el número de copias por página) en lugar de recortar el QR.
    if MOSTRAR_QR_EN_REPORTES and mostrar_qr:
        els.append(Spacer(1, 2 * mm))
        els.append(_QrPesajeFlowable(d, tamano=38 * mm))

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
    copias: int = 1,
    tamano_papel: str = "Letter",
    orientacion: str = "portrait",
    mostrar_encabezado: bool = True,
    mostrar_detalles: bool = True,
    idioma: str = "es",
    tipo_ticket: str = "simple",
    configuracion_tamanos: Mapping[str, Any] | None = None,
    mostrar_qr: bool = True,
) -> io.BytesIO:
    """PDF con ``copias`` tickets idénticos (una copia por página) e i18n.

    ``copias`` es la cantidad de tickets a imprimir del mismo boleto. El boleto
    no promete apilado por hoja: cada copia usa una página completa (Carta/A4/
    media carta) o un tramo del rollo térmico, y el autoajuste tipográfico
    garantiza que una copia nunca se recorte.
    """
    # Acepta tanto las claves internas como los nombres visibles de la interfaz.
    tamano_papel = {
        "Carta": "Letter",
        "carta": "Letter",
        "Media carta": "HalfLetter",
        "media carta": "HalfLetter",
        "Media Carta": "HalfLetter",
        "A4": "A4",
        "80mm": "80mm",
        "58mm": "58mm",
    }.get(tamano_papel, tamano_papel)
    d   = _dato(p, idioma)
    cab = _empresa_cabecera(empresa)
    # El RIF del emisor NO es columna del boleto: llega por la empresa. `_dato`
    # ya lo proyecta, pero hasta aquí nadie lo poblaba, así que el campo
    # `empresa_rif` del QR salía vacío y el filtro de vacíos lo descartaba.
    d["empresa_rif"] = cab["rif"]
    anulado = (d["estado"] or "").upper() == "ANULADO"
    if configuracion_tamanos is None:
        configuracion_tamanos = getattr(empresa, "configuracion_tamanos_boleto", None)
    configuracion_formato = _config_tamanos_formato(configuracion_tamanos, tamano_papel)

    _registrar_ttf()

    # ── Tamaño de página ─────────────────────────────────────────────────────
    pagina = _TAMANOS.get(tamano_papel, letter)
    if orientacion == "landscape":
        pagina = (pagina[1], pagina[0])

    ancho_pag = pagina[0]
    alto_pag  = pagina[1]

    # Cantidad de tickets a imprimir: cada copia es un ticket completo y el PDF
    # emite EXACTAMENTE ``copias``. En hoja el bloque de abajo empaqueta tantas
    # copias por página como quepan a una escala legible y el resto fluye a
    # páginas siguientes; en rollo térmico cada copia es un tramo de alto
    # dinámico. OJO: ``n`` es también el número de copias que se apilan al medir,
    # así que tiene que valer exactamente ``copias``; inflarlo imprime boletos de
    # más (con ``int(copias * 1.3)`` una petición de 4 copias emitía 5 tickets).
    n = max(1, copias)

    # ── Geometría de frames ───────────────────────────────────────────────────
    mg_lat  = 10 * mm    # margen izquierdo / derecho
    mg_top  = 10 * mm    # margen superior
    mg_bot  = 10 * mm    # margen inferior (pie de página)
    gap     = 4  * mm    # separación entre tickets (zona de corte)

    compact = tamano_papel in ("80mm", "58mm")

    # ═══════════════════ TÉRMICO: página de alto dinámico ═══════════════════
    # El rollo térmico NO tiene un alto fijo de 297 mm: la página crece con el
    # contenido medido por wrap() para que nada se recorte, nada se solape y no
    # haya saltos de palabra. Los formatos de hoja conservan su altura fija y
    # aprovechan todo el ancho útil.
    if compact:
        # 80mm → 74mm útiles (3mm por lado; se conserva el formato validado).
        # 58mm → 55mm útiles (1,5mm por lado) para dar más espacio a la tabla
        # sin reducir más la tipografía ni partir etiquetas innecesariamente.
        mg_lat = 1.5 * mm if tamano_papel == "58mm" else 3 * mm
        mg_top = 3 * mm
        mg_bot = 5 * mm
        ancho_frame = ancho_pag - 2 * mg_lat
        margen_frame = mg_lat

        st_term = _estilos_simples(
            _escala_termica(getattr(empresa, "tamano_ticket_pdf", "AUTOMATICO"))
        )
        flowables = _build_boleto_simple(
            d, cab, st_term, ancho_frame,
            mostrar_encabezado=mostrar_encabezado,
            mostrar_detalles=mostrar_detalles,
            compact=True,
            idioma=idioma,
            tipo_ticket=tipo_ticket,
            configuracion_tamanos=configuracion_formato,
            mostrar_qr=mostrar_qr,
        )
        # Altura real: cada flowable reporta su alto al hacer wrap con el ancho
        # final; la suma es el alto del contenido. Dentro del Frame el ancho no
        # cambia, así que el re-wrap es determinista y mide igual.
        alto_contenido = 0.0
        for fb in flowables:
            _, h = fb.wrap(ancho_frame, 10 ** 7)
            alto_contenido += h
        alto_pag = mg_top + alto_contenido + mg_bot
        alto_frame = alto_contenido + 4  # + topPadding(2) + bottomPadding(2)

        buf = io.BytesIO()
        cnv = canvas.Canvas(buf, pagesize=(ancho_pag, alto_pag))
        cnv.setTitle(f"Boleto de Pesaje {d['numero']}")
        cnv.setAuthor(cab["nombre"] or t("sistema_pesaje", idioma))

        # Un tramo de rollo (página) por cada copia solicitada.
        for c in range(n):
            if c:
                cnv.showPage()
            # Marca de agua ANULADO proporcional al alto medido de la página
            # (un 72 pt fijo se saldría de un rollo corto).
            if anulado:
                cnv.saveState()
                cnv.setFillColor(ROJO_ANULADO)
                cnv.setFillAlpha(0.12)
                cnv.setFont(FUENTE_BOLD, min(72, alto_pag * 0.45))
                cnv.translate(ancho_pag / 2, alto_pag / 2)
                cnv.rotate(45)
                cnv.drawCentredString(0, 0, t("doc_anulado", idioma))
                cnv.restoreState()

            frame = Frame(
                x1=margen_frame,
                y1=mg_bot,
                width=ancho_frame,
                height=alto_frame,
                leftPadding=0, rightPadding=0,
                topPadding=2, bottomPadding=2,
                showBoundary=0,
            )
            # addFromList consume la lista: la medición previa se usa solo en la
            # primera copia y el contenido se reconstruye para las siguientes.
            fl = flowables if c == 0 else _build_boleto_simple(
                d, cab, st_term, ancho_frame,
                mostrar_encabezado=mostrar_encabezado,
                mostrar_detalles=mostrar_detalles,
                compact=True,
                idioma=idioma,
                tipo_ticket=tipo_ticket,
                configuracion_tamanos=configuracion_formato,
                mostrar_qr=mostrar_qr,
            )
            frame.addFromList(fl, cnv)
        cnv.save()
        return buf

    # Hoja (media carta/Carta/A4): mantener ancho fijo centrado de 100 mm
    # (coherente con los tests de ancho angosto y con la escalera tipográfica).
    mg_lat  = 10 * mm    # margen izquierdo / derecho
    mg_top  = 10 * mm   # margen superior
    mg_bot  = 10 * mm   # margen inferior (pie de página)
    gap     = 4  * mm    # separación entre tickets (zona de corte)
    ANCHO_TICKET = 100  # mm, ancho fijo del boleto centrado
    centrado = (
        (ancho_pag - 2 * mg_lat) > ANCHO_TICKET * mm
    )
    ancho_frame = ANCHO_TICKET * mm if centrado else (ancho_pag - 2 * mg_lat)
    margen_frame = (ancho_pag - ancho_frame) / 2 if centrado else mg_lat

    # ── Escala tipográfica y empaquetado por página (el AVANZADO nunca se trunca) ─
    # El boleto AVANZADO trae mucho contenido: si con la cantidad de tickets
    # solicitada no cabe ni a la escala mínima, se reduce el número de copias por
    # página y las copias restantes fluyen a páginas siguientes. Nada se descarta.
    #
    # La escalera se filtra por el peldaño que tenga configurado la empresa: es un
    # **techo** sobre el punto de partida, no un reemplazo. Filtrar y no reemplazar
    # es lo que mantiene las dos garantias a la vez: con 4 copias la escalera
    # vigente ya baja sola hasta 5.5, y si el filtro la reemplazara, GRANDE
    # dejaria de ser "igual que hoy" (CE-05); si no filtrara, PEQUENO no tendria
    # ningun efecto visible (CE-04).
    escala_candidatas = escalera_efectiva(
        _ESCALAS_ACTUALES,
        getattr(empresa, "tamano_ticket_pdf", "AUTOMATICO"),
    )

    st: dict[str, ParagraphStyle] = _estilos_simples(10.5)
    n_fit = 0
    for n_try in range(n, 0, -1):
        alto_try = (alto_pag - mg_top - mg_bot - gap * (n_try - 1)) / n_try
        cand = escala_candidatas.get(n_try, escala_candidatas[1])
        for ts in cand:
            st_probe = _estilos_simples(ts)
            flowables_probe = _build_boleto_simple(
                d, cab, st_probe, ancho_frame,
                mostrar_encabezado=mostrar_encabezado,
                mostrar_detalles=mostrar_detalles,
                compact=compact,
                idioma=idioma,
                tipo_ticket=tipo_ticket,
                configuracion_tamanos=configuracion_formato,
                mostrar_qr=mostrar_qr,
            )
            # El Frame reserva topPadding=2 + bottomPadding=2: medir contra la
            # altura útil, o el último flowable (firmas) se recorta.
            if _caben(flowables_probe, ancho_frame, alto_try - 4):
                n_fit, st = n_try, st_probe
                break
        if n_fit:
            break
    if not n_fit:
        n_fit = 1
        st = _estilos_simples(escala_candidatas[1][-1])
    alto_frame = (alto_pag - mg_top - mg_bot - gap * (n_fit - 1)) / n_fit

    # ── Canvas: una página por bloque de hasta n_fit tickets ───────────────
    buf = io.BytesIO()
    cnv = canvas.Canvas(buf, pagesize=pagina)
    cnv.setTitle(f"Boleto de Pesaje {d['numero']}")
    cnv.setAuthor(cab["nombre"] or t("sistema_pesaje", idioma))

    pendientes = n
    while pendientes > 0:
        por_pagina = min(n_fit, pendientes)

        # Marca de agua ANULADO (45°, semitransparente)
        if anulado:
            cnv.saveState()
            cnv.setFillColor(ROJO_ANULADO)
            cnv.setFillAlpha(0.12)
            cnv.setFont(FUENTE_BOLD, 72)
            cnv.translate(ancho_pag / 2, alto_pag / 2)
            cnv.rotate(45)
            cnv.drawCentredString(0, 0, t("doc_anulado", idioma))
            cnv.restoreState()

        # Pie de página (fecha de impresión + estado + número de boleto)
        cnv.saveState()
        cnv.setFont(FUENTE, 7)
        cnv.setFillColor(GRIS_MEDIO)
        izq = f"{t('impreso', idioma)}: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}   {t('estado', idioma)}: {traducir_estado_boleto(d['estado'], idioma)}"
        der = f"{t('col_boleto', idioma)} N° {d['numero']}"
        cnv.drawString(margen_frame, mg_bot / 2, izq)
        # Evitar solapes: si el derecho se pisa con el izquierdo, bajarlo
        try:
            from reportlab.pdfbase import pdfmetrics
            w_izq = pdfmetrics.stringWidth(izq, FUENTE, 7)
            x_der = margen_frame + ancho_frame - pdfmetrics.stringWidth(der, FUENTE, 7)
            if x_der < margen_frame + w_izq + 4:
                cnv.drawRightString(margen_frame + ancho_frame, mg_bot / 4, der)
            else:
                cnv.drawRightString(margen_frame + ancho_frame, mg_bot / 2, der)
        except Exception:
            cnv.drawRightString(margen_frame + ancho_frame, mg_bot / 2, der)
        cnv.restoreState()

        # ── Dibujar cada ticket en su Frame ──────────────────────────────────
        for i in range(por_pagina):
            y1_frame = mg_bot + (por_pagina - 1 - i) * (alto_frame + gap)

            frame = Frame(
                x1=margen_frame,
                y1=y1_frame,
                width=ancho_frame,
                height=alto_frame,
                leftPadding=0, rightPadding=0,
                topPadding=2,  bottomPadding=2,
                showBoundary=0,
            )

            flowables = _build_boleto_simple(
                d, cab, st, ancho_frame,
                mostrar_encabezado=mostrar_encabezado,
                mostrar_detalles=mostrar_detalles,
                compact=compact,
                idioma=idioma,
                tipo_ticket=tipo_ticket,
                configuracion_tamanos=configuracion_formato,
                mostrar_qr=mostrar_qr,
            )
            frame.addFromList(flowables, cnv)

            if i < por_pagina - 1:
                y_corte = y1_frame + alto_frame + gap / 2
                cnv.saveState()
                cnv.setStrokeColor(GRIS_MEDIO)
                cnv.setLineWidth(0.4)
                cnv.setDash(4, 3)
                cnv.line(margen_frame, y_corte, margen_frame + ancho_frame, y_corte)
                cnv.setDash()
                cnv.setFont(FUENTE, 8)
                cnv.setFillColor(GRIS_MEDIO)
                cnv.drawString(margen_frame, y_corte + 1 * mm, "✂")
                cnv.restoreState()

        pendientes -= por_pagina
        if pendientes > 0:
            cnv.showPage()

    cnv.save()
    return buf



# ─────────────────────────────────────────────────────────────────────────────
# Helpers TXT
# ─────────────────────────────────────────────────────────────────────────────
def _linea(char: str = "-") -> str:
    return char * ANCHO_TXT


def _centrar(texto: str) -> str:
    return texto.center(ANCHO_TXT)


def _centrar_partido(texto: str, ancho: int = ANCHO_TXT) -> list[str]:
    """Como ``_centrar`` pero parte el texto largo en varias líneas centradas.

    Necesario para la línea de contacto (teléfono · dirección · email), que con
    una dirección real se pasa del ancho del ticket.
    """
    palabras = texto.split()
    if not palabras:
        return []
    lineas: list[str] = []
    actual = ""
    for palabra in palabras:
        if not actual:
            actual = palabra
        elif len(actual) + 1 + len(palabra) <= ancho:
            actual = f"{actual} {palabra}"
        else:
            lineas.append(actual.center(ancho))
            actual = palabra
    if actual:
        lineas.append(actual.center(ancho))
    return lineas


def _partir_ancho(texto: str, ancho: int) -> list[str]:
    """Parte un bloque de texto en líneas de a lo más ``ancho`` columnas."""
    palabras = texto.split()
    if not palabras:
        return [""]
    lineas: list[str] = []
    actual = ""
    for palabra in palabras:
        if not actual:
            actual = palabra
        elif len(actual) + 1 + len(palabra) <= ancho:
            actual = f"{actual} {palabra}"
        else:
            lineas.append(actual)
            actual = palabra
    if actual:
        lineas.append(actual)
    return lineas


def _campo_apilado_txt(etiqueta: str, valor: str) -> list[str]:
    """'Etiqueta: valor' en una frase, partida por PALABRAS (espejo del PDF
    térmico apilado). Devuelve una o más líneas; con valor vacío queda
    'Etiqueta:' sola. La separación por palabras colapsa espacios dobles sin
    partir el contenido a media palabra."""
    linea = f"{etiqueta}: {valor}".strip()
    return _partir_ancho(linea, ANCHO_TXT)


# ─────────────────────────────────────────────────────────────────────────────
# Construcción del TXT
# FUENTE: TicketPreviewDialog._buildSingleTicketBlock (Flutter)
# Misma estructura que el PDF térmico: campos apilados y la LECTURA DE PESOS
# como tabla de 5 columnas —(vacío) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL— con
# una fila por pesada, la de TOTALES (los netos por vehículo) y PESO NETO.
# ─────────────────────────────────────────────────────────────────────────────
def _build_txt(
    p: BoletoPesaje,
    empresa: Empresa | None = None,
    mostrar_encabezado: bool = True,
    mostrar_detalles: bool = True,
    idioma: str = "es",
    tipo_ticket: str = "simple",
) -> io.BytesIO:
    """Ticket en texto plano con el mismo layout que el PDF e i18n."""
    d   = _dato(p, idioma)
    cab = _empresa_cabecera(empresa)
    anulado = (d["estado"] or "").upper() == "ANULADO"

    lineas: list[str] = []

    def _apilar(etiqueta: str, valor: str) -> None:
        """Apila 'Etiqueta: valor' partido por palabras (espejo del PDF
        térmico: cada campo en su propia línea, sin columnas)."""
        lineas.extend(_campo_apilado_txt(etiqueta, valor))

    # ── 1. Encabezado empresa ─────────────────────────────────────────────────
    # SIN separador '|' entre [LOGO] y datos (para no introducir una línea
    # vertical en TXT que no está en el PDF).
    lineas.append(_linea("="))
    if mostrar_encabezado and cab["nombre"]:
        ancho_logo = 10
        ancho_der = ANCHO_TXT - ancho_logo - 1
        logo_txt = "[LOGO]".center(ancho_logo)

        rif_txt = f'{t("etiqueta_rif", idioma)}: {cab["rif"]}' if cab["rif"] else ""
        linea1 = " - ".join(x for x in [cab["nombre"], rif_txt] if x)

        partes_contacto: list[str] = []
        if cab["direccion"]:
            partes_contacto.append(cab["direccion"])
        if cab["telefono"]:
            partes_contacto.append(
                f'{t("etiqueta_telefono", idioma)}: {cab["telefono"]}'
            )
        if cab["email"]:
            partes_contacto.append(cab["email"])
        linea2 = " - ".join(partes_contacto)

        tiene_logo_txt = bool(cab["logo"])
        if tiene_logo_txt:
            # CON logo: [LOGO] y datos en columnas separadas por espacios.
            lineas.append("━" * ANCHO_TXT)
            renglones = [linea1, linea2] if linea2 else [linea1]
            for i, bloque in enumerate(renglones):
                for j, parte in enumerate(_partir_ancho(bloque, ancho_der)):
                    prefijo = f"{logo_txt} " if i == 0 and j == 0 else f"{' ' * ancho_logo} "
                    lineas.append(f"{prefijo}{parte}")
            lineas.append("━" * ANCHO_TXT)
            lineas.append("")
        else:
            # SIN logo: solo texto alineado a la izquierda.
            if linea1:
                lineas.extend(_partir_ancho(linea1, ANCHO_TXT))
            if linea2:
                lineas.extend(_partir_ancho(linea2, ANCHO_TXT))
            lineas.append("")

        # ── 2. Título ─────────────────────────────────────────────────────────────
        lineas.append(_centrar(t("titulo_boleto", idioma)))
        lineas.append(_linea("-"))
        lineas.append("")

    # ── 3. DATOS (apilado, mismo orden que el PDF térmico) ────────────────────
    _apilar(t("serie_boleto", idioma), d["numero"])
    _apilar(t("fecha_hora", idioma),     d["fecha_hora"])
    _apilar(t("camion", idioma),         d["camion"])
    if tipo_ticket == "avanzado" and d.get("color_camion"):
        _apilar(t("camion_color", idioma), d["color_camion"])
    _apilar(t("remolque", idioma),       d["remolque"])
    _apilar(t("transporte", idioma),     d["transporte"])
    _apilar(t("conductor", idioma),      d["conductor"])
    _apilar(t("producto", idioma),       d["producto"])
    _apilar(t("almacen", idioma),        d["almacen"])
    _apilar(t("cliente_proveedor", idioma), d["razon_social"])
    lineas.append("")

    # ── 4. LECTURA DE PESOS (tabla, misma estructura que el PDF térmico) ──────
    lineas.append(_linea("="))
    lineas.append(_centrar(t("lectura_pesos", idioma)))
    lineas.append(_linea("-"))

    # Columnas: (etiqueta) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL
    # (anchos en caracteres; la suma + separadores cabe en ANCHO_TXT=100).
    anchos_txt = (13, 20, 14, 14, 14)

    def _fila_txt(celdas: list[str]) -> str:
        """Fila de la tabla de lecturas con columnas alineadas a la izquierda."""
        partes = [c.ljust(a) for c, a in zip(celdas, anchos_txt, strict=False)]
        return " ".join(partes).rstrip()

    # Espejo del PDF térmico: misma rejilla y mismos datos (`_filas_lectura_pesos`),
    # así que aquí solo hay que pintar las celdas.
    filas_txt = _filas_lectura_pesos(d, idioma)
    for i, fila_raw in enumerate(filas_txt):
        # La línea va justo ANTES del PESO NETO, como el LINEABOVE del PDF.
        if i == len(filas_txt) - 1:
            lineas.append(_linea("-"))
        lineas.append(_fila_txt([texto for texto, _ in fila_raw]))
    lineas.append(_linea("="))
    lineas.append("")

    # ── 5b. PESO MANUAL (escrito a mano, sin báscula) ─────────────────────────
    if d["peso_manual"]:
        lineas.append(_centrar(t("peso_manual", idioma)))
        if d.get("operador"):
            _apilar(t("operador", idioma), d["operador"])
        lineas.append("")

    # ── 6. DATOS ADICIONALES ──────────────────────────────────────────────────
    if tipo_ticket == "avanzado":
        pares_txt = _pares_avanzado(d, idioma)
        tiene_dats_adic = True
    else:
        pares_txt = []
        if d["documento"]:
            pares_txt.append((f"{t('documento', idioma)}:", d["documento"]))
        if d.get("unidades_txt") is not None:
            pares_txt.append((f"{t('unidades', idioma)}:", d["unidades_txt"]))
        if d.get("densidad_txt") is not None:
            pares_txt.append((f"{t('densidad', idioma)}:", d["densidad_txt"]))
        tiene_dats_adic = bool(pares_txt)
    if tiene_dats_adic:
        lineas.append(_linea("="))
        lineas.append(_centrar(t("datos_adicionales", idioma)))
        lineas.append(_linea("-"))
        for etiqueta, valor in pares_txt:
            _apilar(etiqueta.rstrip(":"), valor)
        lineas.append(_linea("="))
        lineas.append("")

    # ── 6b. DATOS DEL CATÁLOGO Y CONTROL (solo AVANZADO) ─────────────────────
    if tipo_ticket == "avanzado":
        pares_cat_txt = _pares_catalogo(d, idioma, rif_empresa=cab["rif"])
        if pares_cat_txt:
            lineas.append(_linea("="))
            lineas.append(_centrar(t("datos_catalogo", idioma)))
            lineas.append(_linea("-"))
            for lab, val in pares_cat_txt:
                _apilar(lab.rstrip(":"), val)
            lineas.append(_linea("="))
            lineas.append("")

    # ── 7. OBSERVACIONES (respeta saltos de línea; wrap por palabra) ─────────
    if mostrar_detalles and d["observaciones"]:
        lineas.append(_linea("="))
        lineas.append(_centrar(t("observaciones", idioma)))
        lineas.append(_linea("-"))
        for obs_linea in d["observaciones"].splitlines():
            if obs_linea:
                lineas.extend(_partir_ancho(obs_linea, ANCHO_TXT))
            else:
                lineas.append("")
        lineas.append("")

    # ── ANULADO ───────────────────────────────────────────────────────────────
    if anulado:
        lineas.append(_linea("*"))
        motivo = d["motivo_anulacion"] or t("no_especificado", idioma)
        lineas.append(_centrar(t("doc_anulado_banner", idioma)))
        lineas.append(_centrar(f"{t('motivo', idioma)}: {motivo}"))
        lineas.append(_linea("*"))
        lineas.append("")

    # ── 8. Firmas (solo AVANZADO) ─────────────────────────────────────────────
    if tipo_ticket == "avanzado":
        ancho_col = ANCHO_TXT // 2
        lineas.append(
            f"{'_' * 24}".center(ancho_col) + f"{'_' * 24}".center(ancho_col)
        )
        lineas.append(
            t("firma_operador", idioma).center(ancho_col) + t("firma_conductor", idioma).center(ancho_col)
        )
        lineas.append("")

    # ── Pie ───────────────────────────────────────────────────────────────────
    lineas.append(_linea("-"))
    lineas.append(f"{t('estado', idioma)}: {traducir_estado_boleto(d['estado'], idioma)}")
    lineas.append(f"{t('impreso', idioma)}: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}")
    lineas.append(_linea("-"))

    return io.BytesIO("\n".join(lineas).encode("utf-8"))


# ─────────────────────────────────────────────────────────────────────────────
# API pública
# ─────────────────────────────────────────────────────────────────────────────
def generar_ticket_pdf(
    p: BoletoPesaje,
    empresa: Empresa | None = None,
    copias: int = 1,
    tamano_papel: str = "Letter",
    orientacion: str = "portrait",
    mostrar_encabezado: bool = True,
    mostrar_detalles: bool = True,
    idioma: str = "es",
    tipo_ticket: str = "simple",
    configuracion_tamanos: Mapping[str, Any] | None = None,
    mostrar_qr: bool = True,
) -> StreamingResponse:
    """Retorna el PDF del boleto con layout fiel a TicketPreviewDialog (Flutter) e i18n.

    ``copias`` es la cantidad de tickets a imprimir del mismo boleto.
    """
    buf = _build_pdf(
        p,
        empresa=empresa,
        copias=copias,
        tamano_papel=tamano_papel,
        orientacion=orientacion,
        mostrar_encabezado=mostrar_encabezado,
        mostrar_detalles=mostrar_detalles,
        idioma=idioma,
        tipo_ticket=tipo_ticket,
        configuracion_tamanos=configuracion_tamanos,
        mostrar_qr=mostrar_qr,
    )
    buf.seek(0)
    nombre = f"ticket_{p.numero_boleto or p.boleto}.pdf"
    return StreamingResponse(
        buf,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nombre}"'},
    )


def generar_ticket_txt(
    p: BoletoPesaje,
    empresa: Empresa | None = None,
    idioma: str = "es",
    tipo_ticket: str = "simple",
) -> StreamingResponse:
    """Retorna el ticket en texto plano con layout fiel a TicketPreviewDialog (Flutter) e i18n."""
    buf = _build_txt(p, empresa=empresa, idioma=idioma, tipo_ticket=tipo_ticket)
    buf.seek(0)
    nombre = f"ticket_{p.numero_boleto or p.boleto}.txt"
    return StreamingResponse(
        buf,
        media_type="text/plain; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{nombre}"'},
    )


# ═════════════════════════════════════════════════════════════════════════════
# CAMBIOS APLICADOS A ESTE MÓDULO (reescritura del ticket térmico + coherencia TXT)
# ─────────────────────────────────────────────────────────────────────────────
# Objetivo (REQ): el ticket debe imprimirse LIMPIO en todos los formatos
# (80mm/58mm térmico, Carta/A4): sin campos solapados, sin cortar palabras a
# media letra, sin recortes, sin campos omitidos y con PDF y TXT coherentes.
#
# 1. Fallbacks robustos (REQ "fallbacks robustos"):
#    - `_numero_boleto()`: numero_boleto → numero → "BOL-{boleto[:8]}" →
#      "{serie}-{correlativo:08d}" → "Boleto s/n"; todo con getattr.
#    - `_remolque_txt()`: placa_remolque → remolque_placa → "Sí — {placa}";
#      id_remolque/flag remolque → "Sí"; si no, "No". Antes se ocultaba un
#      remolque asignado con placa cuando la columna booleana venía en False.
#    - `_normalizar_simple()` colapsa espacios dobles en campos SIMPLES
#      ("YOHANDER  SANCHEZ" → "YOHANDER SANCHEZ"). NO se aplica a observaciones.
#
# 2. Normalización de observaciones (REQ "normalización"): cada línea se
#    normaliza por separado y se conservan los saltos de línea. Nada de un
#    `\s+` genérico sobre todo el texto.
#
# 3. `_dato()`: usa la cadena de respaldo del número y del remolque; el resto
#    de campos simples se normalizan. Orden idéntico al widget Flutter.
#
# 4. Estilos térmicos (`_estilos_simples`): `term_etq`, `term_val`,
#    `term_val_bold`, `term_seccion`, `term_obs`, `term_pie`,
#    `term_titulo_empresa`, todos con `splitLongWords=0` → wrap POR PALABRA
#    (nunca parte una palabra). `term_etq` (negrita) pega la etiqueta al borde
#    DERECHO de su celda y `term_val`/`term_val_bold` el valor al borde
#    IZQUIERDO de la suya: cada mitad con su propia alineación.
#
# 5. `_build_boleto_simple(compact=True)`: campos APILADOS de DOS celdas
#    ("Etiqueta: | valor"), la etiqueta en negrita pegada a la DERECHA de su
#    celda y el valor a la IZQUIERDA de la suya (ver 11). La LECTURA DE PESOS
#    sigue siendo una
#    TABLA DE 5 COLUMNAS —(vacío) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL— con
#    una fila por pesada (ENTRADA / SALIDA), la de TOTALES (los NETOS por
#    vehículo) y una fila final PESO NETO con sufijo (INGRESO/DESPACHO) en
#    negrita; observaciones una línea por renglón; pie (estado + impreso) como
#    flowables DENTRO del flujo para que el alto dinámico lo incluya. Caso B
#    del título: si `titulo_boleto` NO menciona "BALANSOFT", se añade una
#    línea centrada con la empresa (solo térmico, sin concatenar claves
#    i18n). La HOJA (media carta/Carta/A4) imprime el bloque de DATOS con la
#    MISMA forma de DOS columnas que el rollo (ver 11); su ritmo vertical no
#    cambia porque las filas llevan `padding_y=1.0` (el térmico va a 0).
#
# 6. `_build_pdf()`: rama temprana para 80/58mm con PÁGINA DE ALTO DINÁMICO.
#    Márgenes 80mm→3mm (74mm útiles, sin cambios), 58mm→1,5mm (55mm útiles),
#    top 3mm, bottom 5mm; se mide el contenido con `flowable.wrap(ancho, ∞)`,
#    la página se crea con `pagesize=(ancho, mg_top+contenido+mg_bot)` y se dibuja
#    en un Frame del alto exacto. La marca de agua ANULADO escala a
#    `min(72, alto_pag*0.45)`. Media carta es 5,5×8,5 pulgadas en vertical; las
#    hojas usan el ancho disponible con márgenes laterales de 8mm.
#
# 7. `_build_txt()`: mismo layout que el PDF térmico. Campos apilados
#    (`_campo_apilado_txt`, wrap por palabra a ANCHO_TXT=100) y la MISMA tabla
#    de 5 columnas de la LECTURA DE PESOS, con anchos en caracteres y celdas
#    alineadas a la izquierda. Observaciones: una entrada por línea original,
#    partida por palabras (antes se troceaba por carácter). Orden de campos,
#    fallbacks y tratamiento de observaciones idénticos al PDF térmico.
#    NOTA: el TXT NO se alinea a la derecha (los textos planos no tienen
#    alineación a la derecha sin rellenar con espacios a mano, lo que
#    rompería el ancho de ANCHO_TXT). Si se quisiera, habría que reescribir
#    `_campo_apilado_txt` para devolver la línea con `.rjust(ANCHO_TXT)`.
#
# 8. `_esc()` (via `xml.sax.saxutils.escape`): TODO dato de usuario/BD que entra
#    en un `Paragraph` se escapa (nombres, direcciones, email, observaciones,
#    motivo de anulación y valores de las tablas). El marcado INTENCIONAL
#    (`<b>`, `<br/>`, `<font>`) se construye fuera de `_esc`. El TXT conserva el
#    texto crudo (no es XML).
#
# 9. Tabla de la LECTURA DE PESOS SIN SOLAPE (medido con `pdftotext -bbox`): el
#    reparto de columnas no depende de los datos del boleto. `_REQUIERE_TABLA_PESOS`
#    fija el peor caso (pt de texto por pt de cuerpo) de cada columna ("PESO
#    LÍQUIDO:" en pt, "12/10/2026", "(OUTBOUND)" en negrita, "REMOLQUE" en
#    negrita y "999.999,99"); `_RATIOS_TABLA_PESOS` lo normaliza a 1.0 y
#    `_tamano_tabla_pesos()` devuelve el mayor tamaño ÚNICO para las 5 columnas
#    que respeta el ancho útil con holgura (`_HOLGURA_TABLA_PESOS` = 0.98). Si ni
#    al mínimo (`_MIN_TABLA_PESOS` = 3.8 pt) cabe, activa el corte por carácter
#    (`wordWrap='CJK'`). El mínimo queda POR DEBAJO del ajuste que pide el 58 mm
#    (≈4,37 pt): con el suelo antiguo (4.5 pt) el reparto no bajaba de 4.5, no
#    cabía en el ancho útil y activaba el corte por carácter, que es justo lo que
#    el ejemplo del cliente no quiere. El MISMO eje de columnas y el mismo
#    auto-ajuste usan el
#    rollo (≈6.3 pt a 80 mm, ≈4,37 pt a 58 mm) y la hoja (100 mm de ancho útil).
#    Contenido, estilos y rejilla salen de `_filas_lectura_pesos()` para los dos
#    formatos y para el TXT.
#
# 10. `_escala_termica()`: aplica el techo de `tamano_ticket_pdf` (spec 001,
#     PEQUENO 7.5 / MEDIANO 9.0 pt; GRANDE y AUTOMATICO sin techo) sobre
#     `_TS_TERMICO`, para que el ajuste tipográfico por empresa siga aplicando
#     al rollo además del tamaño de la tabla.
#
# 11. EL BLOQUE DE DATOS SON DOS COLUMNAS INDEPENDIENTES (pedido explícito):
#     antes `_linea_t` construía UN solo Paragraph con toda la línea
#     ("Serie Boleto: TA-00000002") y una única alineación, así que una sola
#     variable `ALIGN RIGHT`/`ALIGN LEFT` movía la etiqueta Y el valor a la
#     vez. Ahora cada fila es una `Table` de 2 celdas:
#
#         |           Etiqueta: |valor                |
#                 TA_RIGHT         TA_LEFT
#
#     - `_fila_t(etiqueta, valor, ancho_etq, bold, estilo_etq)`: celda 0 =
#       etiqueta (`term_etq`, negrita, TA_RIGHT) y celda 1 = valor (`term_val`
#       normal, líder de grupo `term_val_bold`). Las celdas son `Paragraph`, así
#       que envuelven por palabra DENTRO de su columna y nunca se pisan.
#       `colWidths=[ancho_etq, ancho_util - ancho_etq]` y la celda de etiqueta
#       lleva `RIGHTPADDING=_GAP_ETIQUETA_TERMICA` (3 pt) para no tocarse.
#     - `_ancho_etiqueta_termica(ancho_util, etiquetas, tamano)`: la columna de
#       etiquetas mide lo que pide la etiqueta MÁS LARGA del grupo (con la
#       negrita y el cuerpo en uso) + el hueco; nunca pasa del tope
#       `_MAX_RATIO_ETIQUETA_TERMICA` (0.67 del ancho útil). Devuelve
#       `(ancho, cortar)`: si la PALABRA más larga del grupo tampoco cabe en el
#       tope, `_apilar_t` usa la variante `wordWrap="CJK"` (partida por
#       carácter) en lugar de desbordar la celda; con el tope actual no se
#       alcanza en ningún idioma.
#     - El ancho se mide POR GRUPO (`_apilar_t`): DATOS, operador, DATOS
#       ADICIONALES y CATÁLOGO traen etiquetas de longitudes muy distintas.
#       Medido a 80 mm (es): DATOS 97,9 pt (la fija `Cliente/Proveedor:`),
#       ADICIONALES 82,9 y CATÁLOGO 136,0 (las compuestas del catálogo). Con
#       una sola columna global todos los grupos heredarían el peor ancho.
#     - `_linea_t` se elimina: sus 11 puntos de llamada se agrupan en los 4
#       `_apilar_t` (DATOS, operador, ADICIONALES y CATÁLOGO), que miden la
#       columna UNA vez por grupo y reutilizan el ancho en todas sus filas.
#     - `_TS_TERMICO` = 9.5 pt: el grueso del pedido. Con la etiqueta a la
#       derecha sobre 9 pt de cuerpo, `Cliente/Proveedor:` mide 94,9 pt y a
#       58 mm el 55 % del ancho útil (81,1 pt) la obligaba a partirse por
#       carácter, así que el tope sube a 0.67 (98,8 pt a 58 mm). El techo de
#       `tamano_ticket_pdf` (PEQUENO 7.5 / MEDIANO 9.0) se aplica ENCIMA, de
#       modo que el ajuste por empresa sigue mandando en el rollo.
#     - `_fila_t`/`_apilar_t` los usan los DOS formatos: el rollo térmico
#       (80/58 mm) y la hoja (media carta, Carta y A4). La hoja repartía la
#       fila a los extremos (etiqueta a la IZQUIERDA y valor pegado al borde
#       DERECHO), con lo que ni los arranques de los valores ni los finales de
#       las etiquetas coincidían; ahora imprime la misma forma que el rollo. El
#       único ajuste propio de la hoja es `padding_y=1.0` (su ritmo vertical de
#       siempre: el térmico va a 0 y la página crece con el contenido).
#     - El TAMAÑO del bloque se ajusta en un solo sitio: `_DS_TAM_ETIQ_FILA`
#       (etiqueta) y `_DS_TAM_VALOR_FILA` (valor) son RELATIVOS a la escala
#       `ts` de cada formato, y valen para el rollo y para la hoja. La línea
#       base no depende del `leading` sino del TAMAÑO, así que con la etiqueta
#       más pequeña `_fila_t` la baja con relleno superior y se le recorta el
#       `leading` en la misma medida: las dos mitades comparten la vertical sin
#       que la fila crezca.
#
# Casos cubiertos por los tests (tests/test_ticket_service.py):
#   - Térmico 80mm/58mm: cada campo en DOS celdas (la etiqueta en su línea, el
#     valor a la derecha) medido con la GEOMETRÍA real del PDF (`_por_y`), con
#     los bordes derechos de las etiquetas y los inicios de los valores
#     alineados, y las tres columnas de etiquetas (DATOS/ADICIONALES/CATÁLOGO)
#     distintas entre sí.
#   - Hoja media carta/Carta/A4: el bloque de DATOS sale como DOS columnas
#     contiguas (etiquetas con el mismo borde derecho, valores con el mismo
#     arranque, separadas solo por `_GAP_ETIQUETA_TERMICA`); los tres papeles
#     se cubren por parametrización.
#   - `_ancho_etiqueta_termica`: mide la etiqueta más larga del grupo, respeta
#     el tope, avisa del corte por carácter y nunca reserva de más.
#   - Alto dinámico: más contenido ⇒ página estrictamente más alta.
#   - Fallback del número (BOL-8 / serie-correlativo / s/n) y del remolque
#     (placa / flag / id / No).
#   - Sin salida: solo se imprime el bloque Entrada.
#   - Normalización: espacios dobles colapsados; observaciones multi-línea.
#   - Sin solape: la tabla térmica no se cruza en 80 ni 58 mm (es/en/pt) y el
#     reparto de columnas es estable ante datos extremos.
#   - Techo de `tamano_ticket_pdf` en el rollo (PEQUENO/MEDIANO/GRANDE).
#   - Escapado XML de datos con `&`/`<`/`>`.
#   - Coherencia TXT↔PDF térmico: mismo orden de campos y misma tabla.
#   - i18n es/en/pt intactas (el bloque de datos no añade claves nuevas).
#
# i18n: se añadió la clave `col_fecha_hora` (es/en/pt) para la cabecera "Fec,
# Hrs" de la tabla térmica, en `app/core/i18n.py` y en las traducciones de
# Flutter. El resto de claves usadas (cliente_proveedor, col_entrada,
# col_salida, vehiculo, peso_neto, ingreso, despacho, si/no, etc.) ya existían.
# ═════════════════════════════════════════════════════════════════════════════