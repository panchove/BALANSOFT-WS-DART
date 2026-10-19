"""Pruebas de compresión de imágenes y subida de archivos (H10)."""

from __future__ import annotations

import io

from PIL import Image

from app.core.image_compress import comprimir_imagen


def _jpeg(ancho: int, alto: int) -> bytes:
    """JPEG con ruido determinista (compresible de verdad, no uniforme)."""
    img = Image.new("RGB", (ancho, alto))
    pixeles = img.load()
    assert pixeles is not None
    for x in range(0, ancho, 3):
        for y in range(0, alto, 3):
            pixeles[x, y] = ((x * 7 + y * 13) % 256, (x * 3) % 256, (y * 5) % 256)
    buffer = io.BytesIO()
    img.save(buffer, format="JPEG", quality=95)
    return buffer.getvalue()


def _png_con_alfa(ancho: int, alto: int) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGBA", (ancho, alto), (10, 20, 30, 128)).save(buffer, format="PNG")
    return buffer.getvalue()


class TestComprimirImagen:
    def test_redimensiona_gran_jpeg(self):
        original = _jpeg(3000, 2000)
        salida, ext = comprimir_imagen(original)
        assert ext == ".jpg"
        assert len(salida) < len(original)
        with Image.open(io.BytesIO(salida)) as img:
            assert max(img.size) == 1600

    def test_respeta_max_lado_personalizado(self):
        salida, _ = comprimir_imagen(_jpeg(1200, 900), max_lado=400)
        with Image.open(io.BytesIO(salida)) as img:
            assert max(img.size) == 400

    def test_png_con_alfa_se_conserva_png(self):
        salida, ext = comprimir_imagen(_png_con_alfa(2400, 1600))
        assert ext == ".png"
        with Image.open(io.BytesIO(salida)) as img:
            assert img.mode == "RGBA"
            assert max(img.size) == 1600

    def test_no_empeora_si_no_ahorra(self):
        # PNG diminuto y uniforme: re-codificar a JPEG ocuparía más.
        original = io.BytesIO()
        Image.new("RGB", (8, 8), (250, 250, 250)).save(original, format="PNG")
        salida, ext = comprimir_imagen(original.getvalue())
        assert ext == ""
        assert salida == original.getvalue()

    def test_bytes_invalidos_devuelve_original(self):
        datos = b"esto no es una imagen"
        salida, ext = comprimir_imagen(datos)
        assert salida == datos
        assert ext == ""

    def test_orientacion_exif_se_aplica(self):
        original = _jpeg(800, 400)
        img = Image.open(io.BytesIO(original))
        exif = img.getexif()
        exif[0x0112] = 6  # rotar 90° al visualizar
        buffer = io.BytesIO()
        img.save(buffer, format="JPEG", quality=90, exif=exif)

        salida, _ = comprimir_imagen(buffer.getvalue())
        with Image.open(io.BytesIO(salida)) as result:
            assert result.size[0] < result.size[1]