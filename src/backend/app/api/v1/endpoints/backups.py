"""Rutas de respaldo de estación (REQ-NF-BKP-001/002/003).

Snapshot portable del catálogo + operativo de la empresa (JSON gzip). Solo
existe en el rol ``local`` (estación). La restauración es exclusiva de ADMIN
y exige confirmación explícita; la descarga y el listado también son ADMIN.
Cualquier usuario autenticado local puede disparar el respaldo automático por
inactividad (el kiosco opera como OPERADOR).
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, require_admin
from app.core.database import get_db
from app.models import Empresa, Usuario
from app.schemas import BackupOut, BackupRestoreRequest, BackupRestoreResponse
from app.services.backup_service import BackupError, BackupService

router = APIRouter(prefix="/api/v1/backups", tags=["Backups"])

logger = logging.getLogger(__name__)

_SERVICE = BackupService()


@router.post("/auto", response_model=BackupOut)
async def crear_automatico(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Crea un snapshot por inactividad (REQ-NF-BKP-001).

    Cualquier usuario autenticado de la estación puede dispararlo; el backend
    resuelve el ``id_empresa`` del token (nunca del body).
    """
    try:
        info = await _SERVICE.crear(db, empresa, motivo="auto")
    except Exception:
        # Se loguea la causa real (permisos, disco, serialización…): el 500
        # genérico sin traza dejó sin diagnóstico los fallos de producción.
        logger.exception("No se pudo crear el respaldo automático de %s", empresa.id_empresa)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No se pudo crear el respaldo automático.",
        ) from None
    return info.to_dict()


@router.get("", response_model=list[BackupOut])
async def listar_respaldos(
    empresa: Empresa = Depends(get_current_empresa),
    _admin: Usuario = Depends(require_admin),
) -> list[dict]:
    """Lista los snapshots de la empresa (más recientes primero). Solo ADMIN."""
    return [b.to_dict() for b in _SERVICE.listar(empresa.id_empresa)]


@router.get("/{archivo}/download")
async def descargar_respaldo(
    archivo: str,
    empresa: Empresa = Depends(get_current_empresa),
    _admin: Usuario = Depends(require_admin),
) -> FileResponse:
    """Descarga el snapshot comprimido. Solo ADMIN."""
    try:
        ruta = _SERVICE.ruta_archivo(empresa.id_empresa, archivo)
    except BackupError as e:
        raise HTTPException(status_code=400, detail=str(e)) from None
    return FileResponse(
        ruta, media_type="application/gzip", filename=ruta.name
    )


@router.post("/{archivo}/restore", response_model=BackupRestoreResponse)
async def restaurar_respaldo(
    archivo: str,
    body: BackupRestoreRequest,
    empresa: Empresa = Depends(get_current_empresa),
    _admin: Usuario = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Restaura el snapshot (REQ-NF-BKP-002/003). Solo ADMIN.

    Exige ``confirmar=true``. El servicio crea SIEMPRE un respaldo de
    seguridad previo y nunca sobrescribe registros existentes.
    """
    if not body.confirmar:
        raise HTTPException(
            status_code=400,
            detail=(
                "Debe confirmar la restauración (confirmar=true). Se creará "
                "un respaldo de seguridad previo."
            ),
        )
    try:
        resultado = await _SERVICE.restaurar(db, empresa, archivo)
    except BackupError as e:
        raise HTTPException(status_code=400, detail=str(e)) from None
    return {"archivo": archivo, **resultado}