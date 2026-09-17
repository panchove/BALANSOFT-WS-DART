"""Rutas de sincronización de pesajes offline y usuarios→credenciales."""

from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa
from app.core.config import settings
from app.core.database import get_db
from app.models import BoletoPesaje, Empresa, SyncLog, SyncQueue
from app.schemas import (
    SyncBatchRequest,
    SyncBatchResponse,
    SyncStatusResponse,
)
from app.services.sync_service import SyncService

router = APIRouter(prefix="/api/v1/sync", tags=["Sync"])

_SERVICE = SyncService()


@router.post("/push", response_model=SyncBatchResponse)
async def push_sync_data(
    payload: SyncBatchRequest,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> SyncBatchResponse:
    if not payload.pesajes:
        return SyncBatchResponse(sincronizados=0, errores=0, detalle=[])
    sincronizados, errores, detalle = await _SERVICE.process_batch(
        db, empresa, payload.pesajes
    )
    return SyncBatchResponse(
        sincronizados=sincronizados, errores=errores, detalle=detalle
    )


@router.get("/status", response_model=SyncStatusResponse)
async def get_sync_status(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> SyncStatusResponse:
    pendientes = (
        await db.execute(
            select(func.count())
            .select_from(BoletoPesaje)
            .where(BoletoPesaje.id_empresa == empresa.id_empresa, BoletoPesaje.sincronizado.is_(False))
        )
    ).scalar() or 0

    ultima = (
        await db.execute(
            select(func.max(SyncLog.created_at)).where(
                SyncLog.id_empresa == empresa.id_empresa
            )
        )
    ).scalar()

    return SyncStatusResponse(
        pendientes=pendientes,
        ultima_sync=ultima,
        max_offline_dias=settings.max_offline_days,
        usando_licencia_demo=(empresa.licencia_tier == "DEMO"),
    )


@router.get("/pull")
async def pull_sync_data(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    # Los catálogos se bajan vía /catalogs/sync; aquí se devuelven pesajes
    # ya sincronizados de la empresa (para reconstruir cache local).
    result = await db.execute(
        select(BoletoPesaje)
        .where(
            BoletoPesaje.id_empresa == empresa.id_empresa,
            BoletoPesaje.sincronizado.is_(True),
        )
        .order_by(BoletoPesaje.created_at.desc())
        .limit(500)
    )
    rows = result.scalars().all()
    from app.schemas import WeighingOut

    return {"pesajes": [WeighingOut.model_validate(r).model_dump(mode="json") for r in rows]}


# ---------------------------------------------------------------------------
# Sincronización de usuarios locales → credenciales globales
# El App Flutter es el orquestador: lee lo pendiente, lo entrega al servidor
# (POST {server}/api/v1/sync/users) y marca la entrega aquí.
# ---------------------------------------------------------------------------


@router.get("/usuarios/pendientes")
async def list_usuarios_pendientes(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    result = await db.execute(
        select(SyncQueue)
        .where(
            SyncQueue.id_empresa == empresa.id_empresa,
            SyncQueue.entidad == "usuario",
            SyncQueue.pendiente.is_(True),
        )
        .order_by(SyncQueue.created_at)
    )
    items = []
    for fila in result.scalars():
        items.append(
            {
                "id_sync": str(fila.id_sync),
                "entidad_id": fila.entidad_id,
                "operacion": fila.operacion,
                "payload": fila.payload,
                "intentos": fila.intentos,
                "error": fila.error,
                "created_at": fila.created_at,
            }
        )
    return {"pendientes": items}


@router.post("/usuarios/entregados")
async def marcar_usuarios_entregados(
    payload: dict,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Marca como entregados los items de usuario que el servidor confirmó."""
    ids = payload.get("ids", [])
    if not isinstance(ids, list) or not ids:
        raise HTTPException(status_code=400, detail="Se requiere la lista 'ids'.")
    result = await db.execute(
        select(SyncQueue).where(
            SyncQueue.id_empresa == empresa.id_empresa,
            SyncQueue.entidad == "usuario",
            SyncQueue.id_sync.in_(ids),
        )
    )
    marcados = 0
    for fila in result.scalars():
        fila.pendiente = False
        fila.error = None
        marcados += 1
    db.add(
        SyncLog(
            id_empresa=empresa.id_empresa,
            tipo="usuarios",
            entidad="usuario",
            registros=marcados,
            errores=0,
            detalle="Usuarios entregados al servidor",
            created_at=datetime.now(UTC).replace(tzinfo=None),
        )
    )
    await db.commit()
    return {"entregados": marcados}
