"""Rutas de sincronización de pesajes offline."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa
from app.core.config import settings
from app.core.database import get_db
from app.models import BoletoPesaje, Empresa, SyncLog
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
