"""Rutas de catálogo: sincronización combinada para clientes offline."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa
from app.core.database import get_db
from app.models import Empresa
from app.schemas import (
    AlmacenOut,
    BalanzaOut,
    CamionOut,
    CatalogSyncResponse,
    CategoriaOut,
    ConductorOut,
    MarcaOut,
    ModeloCamionOut,
    ProductoOut,
    RemolqueOut,
    TerceroOut,
    TransporteOut,
)
from app.services.catalog_service import CatalogService

router = APIRouter(prefix="/api/v1/catalogo", tags=["Catalogo"])

_SERVICE = CatalogService()


@router.get("/sync", response_model=CatalogSyncResponse)
async def sync_catalogos(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> CatalogSyncResponse:
    data = await _SERVICE.list_all(db, empresa.id_empresa)
    return CatalogSyncResponse(
        camiones=[CamionOut(**v) for v in data["camiones"]],
        remolques=[RemolqueOut(**r) for r in data["remolques"]],
        marcas=[MarcaOut(**r) for r in data["marcas"]],
        modelos_camion=[ModeloCamionOut(**r) for r in data["modelos_camion"]],
        transportes=[TransporteOut(**t) for t in data["transportes"]],
        conductores=[ConductorOut(**c) for c in data["conductores"]],
        productos=[ProductoOut(**p) for p in data["productos"]],
        almacenes=[AlmacenOut(**a) for a in data["almacenes"]],
        categorias=[CategoriaOut(**c) for c in data.get("categorias", [])],
        balanzas=[BalanzaOut(**b) for b in data["balanzas"]],
        terceros=[TerceroOut(**t) for t in data["terceros"]],
    )
