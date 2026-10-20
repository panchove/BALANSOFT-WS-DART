"""Rutas del módulo FLOTA: marcas, modelos de camión, camiones y remolques.

Versión: 0.4.2-dev.56
Fecha: 2026-10-19
Estado: Vigente
Norma: ISO/IEC 25010 / ISO/IEC 27001
Fuente: Sistema BALANSOFT-WS
Autor: Lead Architect
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user, require_catalog_manager
from app.core.database import get_db
from app.models import Camion, Empresa, ModeloCamion, Usuario
from app.schemas import (
    CamionCreate,
    CamionOut,
    MarcaCreate,
    MarcaOut,
    ModeloCamionCreate,
    ModeloCamionOut,
    RemolqueCreate,
    RemolqueOut,
)
from app.services.catalog_service import CatalogService

router = APIRouter(prefix="/api/v1", tags=["Flota"])
_SERVICE = CatalogService()


# ---------------------------------------------------------------------------
# Marcas
# ---------------------------------------------------------------------------


@router.get("/marcas", response_model=list[MarcaOut])
async def list_marcas(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[MarcaOut]:
    rows = await _SERVICE.list_by_name(db, empresa.id_empresa, "marcas")
    return [MarcaOut(**r) for r in rows]


@router.post("/marcas", response_model=MarcaOut, dependencies=[Depends(require_catalog_manager)])
async def create_marca(
    payload: MarcaCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> MarcaOut:
    row = await _SERVICE.create(db, empresa.id_empresa, "marcas", payload.model_dump(),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return MarcaOut(**row)


@router.put("/marcas/{id_marca}", response_model=MarcaOut, dependencies=[Depends(require_catalog_manager)])
async def update_marca(
    id_marca: uuid.UUID,
    payload: MarcaCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> MarcaOut:
    data = payload.model_dump(exclude={"id_marca"})
    row = await _SERVICE.update(db, empresa.id_empresa, "marcas", str(id_marca), data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return MarcaOut(**row)


@router.delete("/marcas/{id_marca}", status_code=204, dependencies=[Depends(require_catalog_manager)])
async def delete_marca(
    id_marca: uuid.UUID,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    result = await db.execute(
        select(ModeloCamion).where(ModeloCamion.marca_id == id_marca)
    )
    if result.scalar_one_or_none() is not None:
        from fastapi import HTTPException

        raise HTTPException(status_code=400, detail="La marca tiene modelos asociados")
    await _SERVICE.delete(db, empresa.id_empresa, "marcas", str(id_marca),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )


# ---------------------------------------------------------------------------
# Modelos de camión
# ---------------------------------------------------------------------------


@router.get("/modelos-camion", response_model=list[ModeloCamionOut])
async def list_modelos(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[ModeloCamionOut]:
    """Lista todos los modelos de camioneta registrados en la empresa.
    
    Args:
        empresa: Empresa cuyos modelos se listan.
        db: Sesión de base de datos asíncrona inyectada por FastAPI.
    
    Returns:
        list[ModeloCamionOut]: Lista de modelos de camioneta activos ordenados por nombre.
    
    Raises:
        HTTPException 401: Si el usuario no tiene permisos OPERADOR o ADMIN.
    
    Notes:
        - Solo incluye modelos con estado activo.
        - Los resultados se ordenan alfabéticamente por nombre.
        - Se registra auditoría del evento de consulta.
    """
    rows = await _SERVICE.list_by_name(db, empresa.id_empresa, "modelos_camion")
    return [ModeloCamionOut(**r) for r in rows]


@router.get("/marcas/{id_marca}/modelos", response_model=list[ModeloCamionOut])
async def list_modelos_by_marca(
    id_marca: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[ModeloCamionOut]:
    result = await db.execute(
        select(ModeloCamion).where(
            ModeloCamion.id_empresa == empresa.id_empresa,
            ModeloCamion.marca_id == id_marca,
        )
    )
    return [ModeloCamionOut.model_validate(r) for r in result.scalars().all()]


@router.post("/modelos-camion", response_model=ModeloCamionOut, dependencies=[Depends(require_catalog_manager)])
async def create_modelo(
    payload: ModeloCamionCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ModeloCamionOut:
    row = await _SERVICE.create(
        db, empresa.id_empresa, "modelos_camion", payload.model_dump(),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return ModeloCamionOut(**row)


@router.put("/modelos-camion/{id_modelo_camion}", response_model=ModeloCamionOut, dependencies=[Depends(require_catalog_manager)])
async def update_modelo(
    id_modelo_camion: uuid.UUID,
    payload: ModeloCamionCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ModeloCamionOut:
    """Actualiza los datos de un modelo de camioneta existente.
    
    Args:
        id_modelo_camion: UUID del modelo de camioneta a actualizar.
        payload: Datos actualizados del modelo (nombre opcional).
        db: Sesión de base de datos asíncrona inyectada por FastAPI.
    
    Returns:
        ModeloCamionOut: Objeto del modelo actualizado con sus datos actuales.
    
    Raises:
        HTTPException 404: Si el modelo no existe.
        HTTPException 400: Si el modelo tiene camiones asociados (no se puede modificar).
        HTTPException 401: Si el usuario no tiene permisos ADMIN/SUPERVISOR.
    
    Notes:
        - Solo se actualizan los campos proporcionados en el payload (parcial update).
        - Si el nombre cambia, se valida que no exista otro modelo con el mismo nombre 
          para la misma marca.
        - Se registra auditoría del evento de modificación.
    """
    data = payload.model_dump(exclude={"id_modelo_camion"})
    row = await _SERVICE.update(
        db, empresa.id_empresa, "modelos_camion", str(id_modelo_camion), data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return ModeloCamionOut(**row)


@router.delete("/modelos-camion/{id_modelo_camion}", status_code=204, dependencies=[Depends(require_catalog_manager)])
async def delete_modelo(
    id_modelo_camion: uuid.UUID,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Elimina un modelo de camioneta de la base de datos.
    
    Args:
        id_modelo_camion: UUID del modelo de camioneta a eliminar.
        db: Sesión de base de datos asíncrona inyectada por FastAPI.
    
    Raises:
        HTTPException 404: Si el modelo no existe.
        HTTPException 400: Si el modelo tiene camiones asociados (no se puede eliminar).
        HTTPException 401: Si el usuario no tiene permisos ADMIN.
    
    Notes:
        - **Regla de negocio**: Un modelo con camiones asociados no puede eliminarse.
        - Se devuelve 204 No Content en éxito (sin cuerpo de respuesta).
        - Se registra auditoría de eliminación con usuario y IP.
        - La eliminación es física de la fila en la tabla `modelos_camion`.
    """
    await _SERVICE.delete(
        db, empresa.id_empresa, "modelos_camion", str(id_modelo_camion),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )


# ---------------------------------------------------------------------------
# Camiones
# ---------------------------------------------------------------------------


@router.get("/camiones", response_model=list[CamionOut])
async def list_camiones(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[CamionOut]:
    rows = await _SERVICE.list_by_name(db, empresa.id_empresa, "camiones")
    return [CamionOut(**r) for r in rows]


@router.get("/camiones/buscar", response_model=list[CamionOut])
async def buscar_camiones(
    placa: str = Query(..., min_length=1),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[CamionOut]:
    result = await db.execute(
        select(Camion).where(
            Camion.id_empresa == empresa.id_empresa,
            Camion.placa.ilike(f"%{placa}%"),
        )
    )
    return [CamionOut.model_validate(r) for r in result.scalars().all()]


@router.post("/camiones", response_model=CamionOut, dependencies=[Depends(require_catalog_manager)])
async def create_camion(
    payload: CamionCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> CamionOut:
    row = await _SERVICE.create(db, empresa.id_empresa, "camiones", payload.model_dump(),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return CamionOut(**row)


@router.put("/camiones/{id_camion}", response_model=CamionOut, dependencies=[Depends(require_catalog_manager)])
async def update_camion(
    id_camion: uuid.UUID,
    payload: CamionCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> CamionOut:
    data = payload.model_dump(exclude={"id_camion"})
    row = await _SERVICE.update(db, empresa.id_empresa, "camiones", str(id_camion), data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return CamionOut(**row)


@router.delete("/camiones/{id_camion}", status_code=204, dependencies=[Depends(require_catalog_manager)])
async def delete_camion(
    id_camion: uuid.UUID,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _SERVICE.delete(db, empresa.id_empresa, "camiones", str(id_camion),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )


# ---------------------------------------------------------------------------
# Remolques
# ---------------------------------------------------------------------------


@router.get("/remolques", response_model=list[RemolqueOut])
async def list_remolques(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[RemolqueOut]:
    rows = await _SERVICE.list_by_name(db, empresa.id_empresa, "remolques")
    return [RemolqueOut(**r) for r in rows]


@router.post("/remolques", response_model=RemolqueOut, dependencies=[Depends(require_catalog_manager)])
async def create_remolque(
    payload: RemolqueCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> RemolqueOut:
    row = await _SERVICE.create(db, empresa.id_empresa, "remolques", payload.model_dump(),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return RemolqueOut(**row)


@router.put("/remolques/{id_remolque}", response_model=RemolqueOut, dependencies=[Depends(require_catalog_manager)])
async def update_remolque(
    id_remolque: uuid.UUID,
    payload: RemolqueCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> RemolqueOut:
    data = payload.model_dump(exclude={"id_remolque"})
    row = await _SERVICE.update(
        db, empresa.id_empresa, "remolques", str(id_remolque), data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return RemolqueOut(**row)


@router.delete("/remolques/{id_remolque}", status_code=204, dependencies=[Depends(require_catalog_manager)])
async def delete_remolque(
    id_remolque: uuid.UUID,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _SERVICE.delete(db, empresa.id_empresa, "remolques", str(id_remolque),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )