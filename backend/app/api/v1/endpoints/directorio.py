"""Rutas del módulo DIRECTORIO: transportes, conductores y terceros."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user, require_catalog_manager
from app.core.database import get_db
from app.models import Empresa, Usuario
from app.schemas import (
    ConductorCreate,
    ConductorOut,
    TerceroCreate,
    TerceroOut,
    TransporteCreate,
    TransporteOut,
)
from app.services.catalog_service import CatalogService

router = APIRouter(prefix="/api/v1", tags=["Directorio"])
_SERVICE = CatalogService()


# ---------------------------------------------------------------------------
# Transportes
# ---------------------------------------------------------------------------


@router.get("/transportes", response_model=list[TransporteOut])
async def list_transportes(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[TransporteOut]:
    rows = await _SERVICE.list_by_name(db, empresa.id_empresa, "transportes")
    return [TransporteOut(**r) for r in rows]


@router.post("/transportes", response_model=TransporteOut, dependencies=[Depends(require_catalog_manager)])
async def create_transporte(
    payload: TransporteCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> TransporteOut:
    row = await _SERVICE.create(
        db, empresa.id_empresa, "transportes", payload.model_dump(),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return TransporteOut(**row)


@router.put("/transportes/{id_transporte}", response_model=TransporteOut, dependencies=[Depends(require_catalog_manager)])
async def update_transporte(
    id_transporte: uuid.UUID,
    payload: TransporteCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> TransporteOut:
    data = payload.model_dump(exclude={"id_transporte"})
    row = await _SERVICE.update(
        db, empresa.id_empresa, "transportes", str(id_transporte), data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return TransporteOut(**row)


@router.delete("/transportes/{id_transporte}", status_code=204, dependencies=[Depends(require_catalog_manager)])
async def delete_transporte(
    id_transporte: uuid.UUID,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _SERVICE.delete(
        db, empresa.id_empresa, "transportes", str(id_transporte),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )


# ---------------------------------------------------------------------------
# Conductores
# ---------------------------------------------------------------------------


@router.get("/conductores", response_model=list[ConductorOut])
async def list_conductores(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[ConductorOut]:
    rows = await _SERVICE.list_by_name(db, empresa.id_empresa, "conductores")
    return [ConductorOut(**r) for r in rows]


@router.post("/conductores", response_model=ConductorOut, dependencies=[Depends(require_catalog_manager)])
async def create_conductor(
    payload: ConductorCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ConductorOut:
    row = await _SERVICE.create(
        db, empresa.id_empresa, "conductores", payload.model_dump(),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return ConductorOut(**row)


@router.put("/conductores/{cedula_dni}", response_model=ConductorOut, dependencies=[Depends(require_catalog_manager)])
async def update_conductor(
    cedula_dni: str,
    payload: ConductorCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ConductorOut:
    data = payload.model_dump(exclude={"cedula_dni"})
    row = await _SERVICE.update(
        db, empresa.id_empresa, "conductores", cedula_dni, data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return ConductorOut(**row)


@router.delete("/conductores/{cedula_dni}", status_code=204, dependencies=[Depends(require_catalog_manager)])
async def delete_conductor(
    cedula_dni: str,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _SERVICE.delete(db, empresa.id_empresa, "conductores", cedula_dni,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )


# ---------------------------------------------------------------------------
# Terceros
# ---------------------------------------------------------------------------


@router.get("/terceros", response_model=list[TerceroOut])
async def list_terceros(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[TerceroOut]:
    rows = await _SERVICE.list_by_name(db, empresa.id_empresa, "terceros")
    return [TerceroOut(**r) for r in rows]


@router.post("/terceros", response_model=TerceroOut, dependencies=[Depends(require_catalog_manager)])
async def create_tercero(
    payload: TerceroCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> TerceroOut:
    row = await _SERVICE.create(db, empresa.id_empresa, "terceros", payload.model_dump(),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return TerceroOut(**row)


@router.put("/terceros/{id_tercero}", response_model=TerceroOut, dependencies=[Depends(require_catalog_manager)])
async def update_tercero(
    id_tercero: uuid.UUID,
    payload: TerceroCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> TerceroOut:
    data = payload.model_dump(exclude={"id_tercero"})
    row = await _SERVICE.update(
        db, empresa.id_empresa, "terceros", str(id_tercero), data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return TerceroOut(**row)


@router.delete("/terceros/{id_tercero}", status_code=204, dependencies=[Depends(require_catalog_manager)])
async def delete_tercero(
    id_tercero: uuid.UUID,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _SERVICE.delete(db, empresa.id_empresa, "terceros", str(id_tercero),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )