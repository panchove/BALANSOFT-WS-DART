"""Compresión de imágenes antes de persistirlas (H10 de ACTUAR.md).

Las fotos de pesaje llegan desde cámaras y teléfonos con resoluciones de
varios megapíxeles (3-8 MB). Este módulo las redimensiona y re-codifica para
que el volumen por estación sea manejable sin perder el valor probatorio de
la imagen.

Reglas:
* se respeta la orientación EXIF, así la foto queda "derecha" al visualizarla;
* si el lado mayor supera ``MAX_LADO`` px se reescala proporcionalmente;
* se re-codifica a JPEG con calidad ``CALIDAD``; los PNG con canal alfa se
  conservan como PNG optimizado;
* si el resultado no es más pequeño que el original, se devuelve el original
  tal cual (no se degrada la calidad a propósito).
"""

from __future__ import annotations

import io
import logging

from PIL import Image, ImageOps

log = logging.getLogger(__name__)

MAX_LADO = 1600
CALIDAD = 80
_UMBRAL_COMPRESION = 0.98  # solo usar la salida si ahorra más del 2 %


def comprimir_imagen(
    datos: bytes,
    *,
    max_lado: int = MAX_LADO,
    calidad: int = CALIDAD,
) -> tuple[bytes, str]:
    """Redimensiona/re-codifica ``datos``.

    Devuelve ``(bytes, extension)``. Si Pillow no puede interpretar la
    imagen (formato no soportado o archivo corrupto) devuelve el original y
    la extensión vacía.
    """
    try:
        with Image.open(io.BytesIO(datos)) as img:
            orientada = ImageOps.exif_transpose(img)
            tiene_alfa = img.mode in ("RGBA", "LA") or (
                img.mode == "P" and "transparency" in img.info
            )
            if tiene_alfa:
                convertida = orientada.convert("RGBA")
                if max(convertida.size) > max_lado:
                    convertida.thumbnail((max_lado, max_lado), Image.Resampling.LANCZOS)
                buffer = io.BytesIO()
                convertida.save(buffer, format="PNG", optimize=True)
                salida, extension = buffer.getvalue(), ".png"
            else:
                convertida = orientada.convert("RGB")
                if max(convertida.size) > max_lado:
                    convertida.thumbnail((max_lado, max_lado), Image.Resampling.LANCZOS)
                buffer = io.BytesIO()
                convertida.save(buffer, format="JPEG", quality=calidad, optimize=True)
                salida, extension = buffer.getvalue(), ".jpg"
    except Exception as exc:  # imagen corrupta o formato no soportado
        log.warning("No se pudo comprimir la imagen (%s); se guarda el original", exc)
        return datos, ""

    if len(salida) >= len(datos) * _UMBRAL_COMPRESION:
        return datos, ""
    return salida, extension