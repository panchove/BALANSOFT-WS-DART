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

Encabezado de empresa (hoja Carta/A4):
  - CON logo → tabla [logo | datos] SIN línea divisoria entre ambos.
  - SIN logo → solo texto alineado a la izquierda.
"""

from __future__ import annotations

import glob
import io
import os
from collections.abc import Mapping
from datetime import datetime
from decimal import Decimal
from typing import Any

from fastapi.responses import StreamingResponse
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
def _dato(p: BoletoPesaje, idioma: str = "es") -> dict[str, Any]:
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
        remolque_txt = (
            f"{t('si', idioma)} — {placa}" if placa else t("si", idioma)
        )
    else:
        remolque_txt = t("no", idioma)

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
            or (
                f"BOL-{str(p.boleto)[:8].upper()}"
                if getattr(p, "boleto", None)
                else t("boleto_sin_numero", idioma)
            )
        ),
        "fecha_hora":   _fmt_dt(p.fecha_hora_entrada),
        "camion":       (p.id_vehiculo or t("sin_placa", idioma)),
        "color_camion": getattr(p, "color_camion", None),
        "remolque":     remolque_txt,
        "transporte":   (
            getattr(p, "transporte_nombre", None)
            or getattr(p, "transporte", None)
            or getattr(p, "id_transporte", None)
            or t("na", idioma)
        ),
        "conductor":    (
            getattr(p, "conductor_nombre", None)
            or getattr(p, "conductor", None)
            or getattr(p, "id_conductor", None)
            or t("na", idioma)
        ),
        "producto":     (
            getattr(p, "producto_nombre", None)
            or getattr(p, "producto", None)
            or getattr(p, "id_producto", None)
            or t("na", idioma)
        ),
        "almacen":      (
            getattr(p, "almacen_nombre", None)
            or getattr(p, "almacen", None)
            or getattr(p, "id_almacen", None)
            or t("na", idioma)
        ),
        "seleccion":    seleccion or t("na", idioma),
        "razon_social": (
            getattr(p, "razon_social", None)
            or getattr(p, "tercero_nombre", None)
            or getattr(p, "id_tercero", None)
            or t("na", idioma)
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
        "guia_sunagro":  getattr(p, "guia_sunagro", None),
        "medida":        getattr(p, "medida", None),
        "flete":         getattr(p, "flete", None),
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
        "observaciones":    (p.observaciones or "").strip(),
        "estado":           normalizar_estado(p.estado_boleto),
        "motivo_anulacion": p.motivo_anulacion,
        "peso_manual":      bool(getattr(p, "es_peso_manual", False)),
        "operador":         getattr(p, "creado_por", None),
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
        # Aviso de peso escrito manualmente (sin báscula) — negrita, rojo
        "peso_manual_c": ParagraphStyle(
            "peso_manual_c", parent=es["Normal"],
            fontName=FUENTE_BOLD, fontSize=ts, leading=ts + 1.5,
            alignment=TA_CENTER, textColor=colors.HexColor("#C62828"),
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
        f'<font size="8">{t("motivo", idioma)}: {motivo}</font>'
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
) -> list[Any]:
    """Construye la lista de flowables de UN boleto con i18n."""
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

        texto_derecha: list[Any] = [Paragraph(linea1, estilo_l1)]
        if linea2:
            texto_derecha.append(Spacer(1, 0.4 * mm))
            texto_derecha.append(Paragraph(linea2, estilo_l2))

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

    # ═══════════════════════ VARIANTE COMPACTA (térmico) ═════════════════════
    if compact:
        els.append(_fila(f"{t('serie_boleto', idioma)}:", d["numero"], bold=True))
        els.append(_fila(f"{t('fecha_hora', idioma)}:",     d["fecha_hora"]))
        els.append(_fila(f"{t('camion', idioma)}:",         d["camion"]))
        if tipo_ticket == "avanzado" and d.get("color_camion"):
            els.append(_fila(f"{t('camion_color', idioma)}:", d["color_camion"]))
        els.append(_fila(f"{t('remolque', idioma)}:",       d["remolque"]))
        els.append(_fila(f"{t('transporte', idioma)}:",     d["transporte"]))
        els.append(_fila(f"{t('conductor', idioma)}:",      d["conductor"]))
        els.append(_fila(f"{t('producto', idioma)}:",       d["producto"]))
        els.append(_fila(f"{t('almacen', idioma)}:",        d["almacen"]))
        els.append(_fila(f"{t('cliente_proveedor', idioma)}:", d["razon_social"]))

        els.append(Spacer(1, 1.5 * mm))
        els.append(_hr_negro(1.0))
        els.append(Spacer(1, 0.8 * mm))
        els.append(Paragraph(t("lectura_pesos", idioma), st["seccion_c"]))
        els.append(Spacer(1, 0.8 * mm))
        els.append(_hr_gris())
        els.append(Spacer(1, 1.2 * mm))

        fecha_e = _fmt_dt(d["hora_entrada"])
        peso_e  = f"{_fmt(d['pte'], lang=idioma)} kg"
        els.append(_fila(f"{t('col_entrada', idioma)}:", f"{fecha_e}   {peso_e}"))
        if d["hora_salida"] is not None:
            fecha_s = _fmt_dt(d["hora_salida"])
            peso_s  = f"{_fmt(d['pts'], lang=idioma)} kg"
            els.append(_fila(f"{t('col_salida', idioma)}:", f"{fecha_s}   {peso_s}"))

        els.append(Spacer(1, 0.8 * mm))
        els.append(_hr_gris())
        els.append(Spacer(1, 1.0 * mm))
        neto_val = d["neto"] if d["neto"] is not None else Decimal("0")
        neto_abs = abs(neto_val)
        sufijo = f" ({t('despacho', idioma)})" if neto_val < 0 else (f" ({t('ingreso', idioma)})" if neto_val > 0 else "")
        els.append(_fila(f"{t('peso_neto', idioma)}:", f"{_fmt(neto_abs, lang=idioma)} kg{sufijo}", bold=True))
        els.append(Spacer(1, 0.8 * mm))
        els.append(_hr_negro(1.0))

        if d["peso_manual"]:
            els.append(Paragraph(t("peso_manual", idioma), st["peso_manual_c"]))
            if d.get("operador"):
                els.append(Spacer(1, 0.5 * mm))
                els.append(_fila(f"{t('operador', idioma)}:", d["operador"]))
            els.append(Spacer(1, 0.8 * mm))

        if tipo_ticket == "avanzado":
            pares_adv = _pares_avanzado(d, idioma)
            if pares_adv:
                els.append(Spacer(1, 0.8 * mm))
                els.append(Paragraph(t("datos_adicionales", idioma), st["seccion_c"]))
                els.append(Spacer(1, 0.8 * mm))
                els.append(_hr_gris())
                els.append(Spacer(1, 1.0 * mm))
                for lab, val in pares_adv:
                    els.append(_fila(lab, val))
                els.append(Spacer(1, 0.8 * mm))
                els.append(_hr_negro(1.0))

            pares_cat = _pares_catalogo(d, idioma, rif_empresa=cab["rif"])
            if pares_cat:
                els.append(Spacer(1, 0.8 * mm))
                els.append(Paragraph(t("datos_catalogo", idioma), st["seccion_c"]))
                els.append(Spacer(1, 0.8 * mm))
                els.append(_hr_gris())
                els.append(Spacer(1, 1.0 * mm))
                for lab, val in pares_cat:
                    els.append(_fila(lab, val))
                els.append(Spacer(1, 0.8 * mm))
                els.append(_hr_negro(1.0))

        if mostrar_detalles and d["observaciones"]:
            els.append(Spacer(1, 1.0 * mm))
            els.append(Paragraph(f'Obs: {d["observaciones"]}', st["obs"]))

        if (d["estado"] or "").upper() == "ANULADO":
            els.append(Spacer(1, 1.0 * mm))
            els.append(_bloque_anulado(d, st, ancho_util, idioma=idioma))

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
        return els

    # ═══════════════════════ VARIANTE HOJA (Carta/A4) ════════════════════════
    # ── 3. DATOS ──────────────────────────────────────────────────────────────
    els.append(_fila(f"{t('serie_boleto', idioma)}:", d["numero"], bold=True))
    els.append(_fila(f"{t('fecha_hora', idioma)}:",     d["fecha_hora"]))
    els.append(_fila(f"{t('camion', idioma)}:",         d["camion"]))
    if tipo_ticket == "avanzado" and d.get("color_camion"):
        els.append(_fila(f"{t('camion_color', idioma)}:", d["color_camion"]))
    els.append(_fila(f"{t('remolque', idioma)}:",       d["remolque"]))
    els.append(_fila(f"{t('transporte', idioma)}:",     d["transporte"]))
    els.append(_fila(f"{t('conductor', idioma)}:",      d["conductor"]))
    els.append(_fila(f"{t('producto', idioma)}:",       d["producto"]))
    els.append(_fila(f"{t('almacen', idioma)}:",        d["almacen"]))
    els.append(_fila(f"{t('seleccion', idioma)}:",      d["seleccion"]))
    els.append(_fila(f"{t('razon_social', idioma)}:",   d["razon_social"]))

    # ── 4. LECTURA DE PESOS (tabla) ───────────────────────────────────────────
    els.append(Spacer(1, 1.5 * mm))
    els.append(_hr_negro(1.0))
    els.append(Spacer(1, 0.8 * mm))
    els.append(Paragraph(t("lectura_pesos", idioma), st["seccion_c"]))
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

    balanza_entrada = f"{t('balanza_entrada', idioma)}: {d['balanza']}".rstrip()
    rows = [
        [_celda("", centro=True), _celda(t("fecha_hora", idioma), centro=True),
         _celda(t("peso_camion", idioma), centro=True), _celda(t("peso_remolque", idioma), centro=True),
         _celda(t("peso_total", idioma), centro=True)],
        [_lab_tab(balanza_entrada), _celda(_fmt_dt(d["hora_entrada"])),
         _celda(_fmt(d["pe_v"], lang=idioma)), _celda(_fmt(d["pe_r"], lang=idioma)), _celda(_fmt(d["pte"], lang=idioma))],
    ]
    hay_salida = d["hora_salida"] is not None
    if hay_salida:
        rows.append([
            _lab_tab(f"{t('balanza_salida', idioma)}: {d['balanza']}".rstrip()),
            _celda(_fmt_dt(d["hora_salida"])),
            _celda(_fmt(d["ps_v"] or Decimal("0"), lang=idioma)),
            _celda(_fmt(d["ps_r"] or Decimal("0"), lang=idioma)),
            _celda(_fmt(d["pts"], lang=idioma)),
        ])

    neto_val = d["neto"] if d["neto"] is not None else Decimal("0")
    just = f" ({t('despacho', idioma)})" if neto_val < 0 else (f" ({t('ingreso', idioma)})" if neto_val > 0 else "")
    rows.append([
        _lab_tab(f"{t('peso_neto', idioma)}{just}:"),
        _celda(""), _celda(_fmt(d["neto_camion"], lang=idioma), bold=True),
        _celda(_fmt(d["neto_remolque"], lang=idioma), bold=True),
        _celda(_fmt(neto_val, lang=idioma), bold=True),
    ])
    idx_neto = len(rows) - 1

    if d["declarado"] is not None:
        rows.append([
            _lab_tab(f"{t('peso_declarado_diferencia', idioma)}:"),
            _celda(""), _celda(""),
            _celda(_fmt(d["declarado"], lang=idioma), bold=True),
            _celda(_fmt_sig(d["diferencia"], lang=idioma), bold=True),
        ])
        if d["desviacion"] is not None:
            rows.append([
                _lab_tab(f"{t('desviacion', idioma)}:"),
                _celda(""), _celda(""), _celda(""),
                _celda(f"{_fmt(d['desviacion'], lang=idioma)} %", bold=True),
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

    # ── 4b. PESO MANUAL (escrito a mano, sin báscula) ─────────────────────────
    if d["peso_manual"]:
        els.append(Spacer(1, 0.8 * mm))
        els.append(Paragraph(t("peso_manual", idioma), st["peso_manual_c"]))
        if d.get("operador"):
            els.append(Spacer(1, 0.5 * mm))
            els.append(_fila(f"{t('operador', idioma)}:", d["operador"]))
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
        els.append(Paragraph(t("datos_adicionales", idioma), st["seccion_c"]))
        els.append(Spacer(1, 0.8 * mm))
        els.append(_hr_gris())
        els.append(Spacer(1, 1.0 * mm))
        for par in dats_adic:
            els.append(_fila(par[0], par[1]))
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
            for lab, val in pares_cat:
                els.append(_fila(lab, val))
            els.append(Spacer(1, 1.0 * mm))
            els.append(_hr_negro(1.0))

    # ── 6. OBSERVACIONES ──────────────────────────────────────────────────────
    if mostrar_detalles and d["observaciones"]:
        els.append(Spacer(1, 1.2 * mm))
        els.append(Paragraph(t("observaciones", idioma), st["seccion_c"]))
        els.append(Spacer(1, 0.8 * mm))
        els.append(_hr_gris())
        els.append(Spacer(1, 1.0 * mm))
        els.append(Paragraph(d["observaciones"], st["obs"]))

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
    idioma: str = "es",
    tipo_ticket: str = "simple",
) -> io.BytesIO:
    """PDF con N tickets de altura exacta por página usando Frames fijos con i18n."""
    d   = _dato(p, idioma)
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

    ANCHO_TICKET = 100  # mm, ancho fijo del boleto centrado
    centrado = (
        not compact
        and (ancho_pag - 2 * mg_lat) > ANCHO_TICKET * mm
    )
    ancho_frame = ANCHO_TICKET * mm if centrado else (ancho_pag - 2 * mg_lat)
    margen_frame = (ancho_pag - ancho_frame) / 2 if centrado else mg_lat

    # ── Escala tipográfica y boletos por página (el AVANZADO nunca se trunca) ─
    # El boleto AVANZADO trae mucho contenido: si con el boletosPorHoja
    # solicitado no cabe ni a la escala mínima, se reduce la cantidad por página
    # y las copias restantes fluyen a páginas siguientes. Nada se descarta.
    escala_candidatas = {
        1: [10.5, 10.0, 9.5, 9.0, 8.5, 8.0, 7.5, 7.0, 6.5, 6.0, 5.5],
        2: [9.5,  9.0, 8.5, 8.0, 7.5, 7.0, 6.5, 6.0, 5.5, 5.0],
        3: [8.5,  8.0, 7.5, 7.0, 6.5, 6.0, 5.5, 5.0, 4.5, 4.0],
        4: [8.0,  7.5, 7.0, 6.5, 6.0, 5.5, 5.0, 4.5, 4.0],
    }

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
        cnv.drawString(
            margen_frame, mg_bot / 2,
            f"{t('impreso', idioma)}: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}   {t('estado', idioma)}: {traducir_estado_boleto(d['estado'], idioma)}",
        )
        cnv.drawRightString(
            margen_frame + ancho_frame, mg_bot / 2,
            f"{t('col_boleto', idioma)} N° {d['numero']}",
        )
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
    idioma: str = "es",
    tipo_ticket: str = "simple",
) -> io.BytesIO:
    """Ticket en texto plano con el mismo layout que el PDF e i18n."""
    d   = _dato(p, idioma)
    cab = _empresa_cabecera(empresa)
    anulado = (d["estado"] or "").upper() == "ANULADO"

    lineas: list[str] = []

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

    # ── 3. DATOS ──────────────────────────────────────────────────────────────
    lineas.append(_campo_txt(t("serie_boleto", idioma), d["numero"]))
    lineas.append(_campo_txt(t("fecha_hora", idioma),     d["fecha_hora"]))
    lineas.append(_campo_txt(t("camion", idioma),         d["camion"]))
    if tipo_ticket == "avanzado" and d.get("color_camion"):
        lineas.append(_campo_txt(t("camion_color", idioma), d["color_camion"]))
    lineas.append(_campo_txt(t("remolque", idioma),       d["remolque"]))
    lineas.append(_campo_txt(t("transporte", idioma),     d["transporte"]))
    lineas.append(_campo_txt(t("conductor", idioma),      d["conductor"]))
    lineas.append(_campo_txt(t("producto", idioma),       d["producto"]))
    lineas.append(_campo_txt(t("almacen", idioma),        d["almacen"]))
    lineas.append(_campo_txt(t("seleccion", idioma),      d["seleccion"]))
    lineas.append(_campo_txt(t("razon_social", idioma),   d["razon_social"]))
    lineas.append("")

    # ── 4. LECTURA DE PESOS (tabla de columnas) ───────────────────────────────
    lineas.append(_linea("="))
    lineas.append(_centrar(t("lectura_pesos", idioma)))
    lineas.append(_linea("-"))
    lineas.append(
        f"{'':<34}{t('fecha_hora', idioma):>16} {t('peso_camion', idioma):>13} {t('peso_remolque', idioma):>13} {t('peso_total', idioma):>13}"
    )
    lineas.append(_fila_lectura_txt(
        f"{t('balanza_entrada', idioma)}: {d['balanza']}".rstrip(),
        _fmt_dt(d["hora_entrada"]),
        _fmt(d["pe_v"], lang=idioma), _fmt(d["pe_r"], lang=idioma), _fmt(d["pte"], lang=idioma),
    ))
    if d["hora_salida"] is not None:
        lineas.append(_fila_lectura_txt(
            f"{t('balanza_salida', idioma)}: {d['balanza']}".rstrip(),
            _fmt_dt(d["hora_salida"]),
            _fmt(d["ps_v"] or Decimal("0"), lang=idioma),
            _fmt(d["ps_r"] or Decimal("0"), lang=idioma),
            _fmt(d["pts"], lang=idioma),
        ))
    lineas.append(_linea("-"))

    # ── 5. Peso Neto / Declarado / Diferencia / Desviación ────────────────────
    neto_val = d["neto"] if d["neto"] is not None else Decimal("0")
    just = f" ({t('despacho', idioma)})" if neto_val < 0 else (f" ({t('ingreso', idioma)})" if neto_val > 0 else "")
    lineas.append(_fila_neto_txt(
        f"{t('peso_neto', idioma)}{just}:",
        _fmt(d["neto_camion"], lang=idioma), _fmt(d["neto_remolque"], lang=idioma), _fmt(neto_val, lang=idioma),
    ))
    if d["declarado"] is not None:
        lineas.append(_fila_neto_txt(
            f"{t('peso_declarado_diferencia', idioma)}:",
            " ", _fmt(d["declarado"], lang=idioma), _fmt_sig(d["diferencia"], lang=idioma),
        ))
        if d["desviacion"] is not None:
            lineas.append(_fila_neto_txt(
                f"{t('desviacion', idioma)}:", " ", " ", f"{_fmt(d['desviacion'], lang=idioma)} %",
            ))
    lineas.append(_linea("="))
    lineas.append("")

    # ── 5b. PESO MANUAL (escrito a mano, sin báscula) ─────────────────────────
    if d["peso_manual"]:
        lineas.append(_centrar(t("peso_manual", idioma)))
        if d.get("operador"):
            lineas.append(_campo_txt(t("operador", idioma), d["operador"]))
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
            lineas.append(_campo_txt(etiqueta.rstrip(":"), valor))
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
                lineas.append(_campo_txt(lab.rstrip(":"), val))
            lineas.append(_linea("="))
            lineas.append("")

    # ── 7. OBSERVACIONES ──────────────────────────────────────────────────────
    if mostrar_detalles and d["observaciones"]:
        lineas.append(_linea("="))
        lineas.append(_centrar(t("observaciones", idioma)))
        lineas.append(_linea("-"))
        for obs_linea in d["observaciones"].splitlines():
            for chunk_start in range(0, max(1, len(obs_linea)), ANCHO_TXT - 5):
                lineas.append(obs_linea[chunk_start:chunk_start + ANCHO_TXT - 5])
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
    boletos_por_hoja: int = 1,
    tamano_papel: str = "Letter",
    orientacion: str = "portrait",
    mostrar_encabezado: bool = True,
    mostrar_detalles: bool = True,
    idioma: str = "es",
    tipo_ticket: str = "simple",
) -> StreamingResponse:
    """Retorna el PDF del boleto con layout fiel a TicketPreviewDialog (Flutter) e i18n."""
    buf = _build_pdf(
        p,
        empresa=empresa,
        boletos_por_hoja=boletos_por_hoja,
        tamano_papel=tamano_papel,
        orientacion=orientacion,
        mostrar_encabezado=mostrar_encabezado,
        mostrar_detalles=mostrar_detalles,
        idioma=idioma,
        tipo_ticket=tipo_ticket,
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