"""Subida de archivos (fotos de catálogos: camión, remolque, conductor).

Guarda el archivo en ``settings.media_dir`` y devuelve la URL pública
``/media/...`` que el frontend usa para guardar en ``foto_url`` /
``foto_real_url`` de las entidades de catálogo.

Las imágenes se comprimen antes de escribirse (H10): se redimensionan a un
máximo de 1600 px y se re-codifican a JPEG, de modo que el consumo de disco
por estación no depende de la resolución de la cámara del operador.
"""

from __future__ import annotations

import logging
import os
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel

from app.api.dependencies import get_current_empresa
from app.core.config import settings
from app.core.image_compress import comprimir_imagen
from app.models import Empresa

router = APIRouter(prefix="/api/v1/files", tags=["Archivos"])
log = logging.getLogger(__name__)


class FileUploadOut(BaseModel):
    url: str
    filename: str
    # H10: KB del archivo realmente escrito y si hubo compresión.
    tamano_kb: int = 0
    comprimido: bool = False


@router.post("/upload", response_model=FileUploadOut, status_code=201)
async def upload_file(
    file: UploadFile = File(...),
    carpeta: str | None = None,
    empresa: Empresa = Depends(get_current_empresa),
) -> FileUploadOut:
    if file.content_type not in settings.allowed_image_types:
        raise HTTPException(
            status_code=400,
            detail=f"Tipo de archivo no permitido: {file.content_type}. "
            f"Permitidos: {', '.join(settings.allowed_image_types)}",
        )
    raw = await file.read()
    if len(raw) > settings.max_image_bytes:
        raise HTTPException(status_code=400, detail="El archivo supera el tamaño máximo de 10 MB")

    sub_dir = (carpeta or "uploads").strip("/").replace("..", "")
    dest_dir = os.path.join(settings.media_dir, sub_dir)
    os.makedirs(dest_dir, exist_ok=True)
    ext = os.path.splitext(file.filename or "foto.jpg")[1] or ".jpg"

    contenido, ext_nueva = comprimir_imagen(raw)
    comprimido = ext_nueva != "" and len(contenido) < len(raw)
    if ext_nueva:
        ext = ext_nueva

    filename = f"{uuid.uuid4().hex}{ext}"
    filepath = os.path.join(dest_dir, filename)
    with open(filepath, "wb") as f:
        f.write(contenido)
    if comprimido:
        log.info(
            "Imagen comprimida %s: %.0f KB -> %.0f KB", file.filename, len(raw) / 1024, len(contenido) / 1024
        )

    return FileUploadOut(
        url=f"/media/{sub_dir}/{filename}",
        filename=filename,
        tamano_kb=len(contenido) // 1024,
        comprimido=comprimido,
    )