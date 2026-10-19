"""Rutas de catálogo: sincronización combinada para clientes offline."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, require_admin
from app.core.database import get_db
from app.models import Empresa, Usuario
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
    SeedCatalogosResponse,
    TerceroOut,
    TransporteOut,
)
from app.services.catalog_service import CatalogService
from app.services.seed_service import SeedService

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


@router.post("/seed", response_model=SeedCatalogosResponse)
async def seed_catalogos(
    empresa: Empresa = Depends(get_current_empresa),
    _admin: Usuario = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> SeedCatalogosResponse:
    """Aplica (o re-aplica) la siembra base de catálogos (REQ-FN-023).

    Solo ADMIN. Si la empresa ya tiene catálogos responde 409: la siembra
    manual nunca sobrescribe la operación existente.
    """
    try:
        resultado = await SeedService.aplicar(db, empresa)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=str(e)
        ) from e
    await db.commit()
    return SeedCatalogosResponse(
        aplicado=True,
        categorias=resultado.categorias,
        productos=resultado.productos,
        almacenes=resultado.almacenes,
    )
