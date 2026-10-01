"""Rutas de catálogo: sincronización combinada para clientes offline."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
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
    catalogo: list[str] | None = Query(
        None,
        description=(
            "Catálogos a sincronizar (repetible: ?catalogo=productos&catalogo=marcas). "
            "Omitido = todos."
        ),
    ),
    limit: int | None = Query(
        None,
        ge=1,
        le=5000,
        description="Máximo de registros por catálogo. Omitido = sin recorte.",
    ),
    skip: int = Query(0, ge=0, description="Registros a saltar por catálogo (paginación)."),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> CatalogSyncResponse:
    data = await _SERVICE.list_all(
        db,
        empresa.id_empresa,
        limite=limit,
        skip=skip,
        solo=catalogo or None,
    )
    return CatalogSyncResponse(
        camiones=[CamionOut(**v) for v in data.get("camiones", [])],
        remolques=[RemolqueOut(**r) for r in data.get("remolques", [])],
        marcas=[MarcaOut(**r) for r in data.get("marcas", [])],
        modelos_camion=[ModeloCamionOut(**r) for r in data.get("modelos_camion", [])],
        transportes=[TransporteOut(**t) for t in data.get("transportes", [])],
        conductores=[ConductorOut(**c) for c in data.get("conductores", [])],
        productos=[ProductoOut(**p) for p in data.get("productos", [])],
        almacenes=[AlmacenOut(**a) for a in data.get("almacenes", [])],
        categorias=[CategoriaOut(**c) for c in data.get("categorias", [])],
        balanzas=[BalanzaOut(**b) for b in data.get("balanzas", [])],
        terceros=[TerceroOut(**t) for t in data.get("terceros", [])],
        totales=data["__totales__"],
        truncado=data["__truncado__"],
    )
