"""Identidad local: vínculo singleton con la cuenta del servidor.

docs/MANEJO_DB.md §6.2 y §8: la máquina guarda el id_cuenta y la licencia
cacheados para operar offline. SQLAlchemy garantiza una sola fila (PK booleana
forzada a TRUE); el backend resuelve "get or create" sobre esa fila.
"""

from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user
from app.core.database import get_db
from app.models import Empresa, IdentidadLocal, Usuario
from app.schemas import IdentidadOut, IdentidadUpdate
from app.services.license_service import sincronizar_licencia_e_identidad

router = APIRouter(prefix="/api/v1/identity", tags=["Identidad"])

_IDENTIDAD_ROW = True


async def _get_identidad(
    db: AsyncSession, *, create_if_missing: bool = False
) -> IdentidadLocal | None:
    result = await db.execute(
        select(IdentidadLocal).where(IdentidadLocal.id.is_(_IDENTIDAD_ROW))
    )
    identidad = result.scalar_one_or_none()
    if identidad is None and create_if_missing:
        identidad = IdentidadLocal(id=_IDENTIDAD_ROW)
        db.add(identidad)
    return identidad


@router.get("", response_model=IdentidadOut)
async def get_identidad(
    refresh: bool = Query(False, description="Revalida en vivo contra el LM si es True"),
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> IdentidadLocal:
    identidad = await _get_identidad(db)
    if refresh and empresa:
        identidad = await sincronizar_licencia_e_identidad(
            db, empresa, force_remote=True
        )
    if identidad is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Identidad local no configurada aún.",
        )
    return identidad


@router.put("", response_model=IdentidadOut)
async def set_identidad(
    payload: IdentidadUpdate,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> IdentidadLocal:
    if current_user.rol != "ADMIN":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo el ADMIN puede configurar la identidad local.",
        )
    identidad = await _get_identidad(db, create_if_missing=True)
    assert identidad is not None
    data = payload.model_dump(exclude_unset=True)
    for campo, valor in data.items():
        if valor is not None:
            setattr(identidad, campo, valor)

    # Espejar cambios principales a la empresa
    if payload.rif_nit:
        empresa.rif_nit = payload.rif_nit
    if payload.nombre_fiscal:
        empresa.nombre_fiscal = payload.nombre_fiscal
    if payload.nombre_comercial:
        empresa.nombre_comercial = payload.nombre_comercial
    if payload.licencia_key:
        empresa.licencia_key = payload.licencia_key
    if payload.licencia_tier:
        empresa.licencia_tier = payload.licencia_tier
    if payload.licencia_status:
        empresa.licencia_status = payload.licencia_status

    identidad.ultima_validacion = datetime.now(UTC).replace(tzinfo=None)
    identidad.updated_at = datetime.now(UTC).replace(tzinfo=None)

    await db.commit()
    await db.refresh(identidad)
    return identidad