"""Rutas del catálogo CONCEPTOS DE INVENTARIO (motivos de kardex).

Hasta la migración 029 el motivo de un movimiento de kardex se escribía a mano
en ``kardex.documento`` (texto libre). Este catálogo permite elegir el concepto
en el ajuste de inventario; el movimiento queda enlazado por
``kardex.id_concepto`` y el nombre del concepto se copia a ``documento`` para
conservar el histórico.

Config **local de la estación** (no se sincroniza), igual que
``balanzas``/``semaforos``/``camaras``/``indicadores``.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import (
    get_current_empresa,
    get_current_user,
    require_admin,
    require_catalog_manager,
)
from app.core.database import get_db
from app.models import ConceptoInventario, Empresa, Kardex, Usuario
from app.schemas import ConceptoInventarioCreate, ConceptoInventarioOut
from app.services.catalog_service import CatalogService

router = APIRouter(prefix="/api/v1", tags=["Conceptos de Inventario"])
_SERVICE = CatalogService()


async def _obtener_concepto(
    db: AsyncSession, empresa: Empresa, id_concepto: uuid.UUID
) -> ConceptoInventario:
    """Carga un concepto de la empresa (404 si no existe) — aislamiento tenant."""
    concepto = await db.get(ConceptoInventario, id_concepto)
    if concepto is None or concepto.id_empresa != empresa.id_empresa:
        raise HTTPException(status_code=404, detail="Concepto de inventario no encontrado")
    return concepto


async def _contar_movimientos(
    db: AsyncSession, id_empresa: uuid.UUID, id_concepto: uuid.UUID
) -> int:
    """Movimientos de kardex enlazados a este concepto."""
    result = await db.execute(
        select(func.count())
        .select_from(Kardex)
        .where(
            Kardex.id_empresa == id_empresa,
            Kardex.id_concepto == id_concepto,
        )
    )
    return int(result.scalar() or 0)


def _normalizar(data: dict) -> dict:
    """Normaliza campos antes de persistir (código vacío → NULL)."""
    if data.get("codigo") is not None:
        data["codigo"] = str(data["codigo"]).strip() or None
    return data


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------


@router.get("/conceptos_inventario", response_model=list[ConceptoInventarioOut])
async def list_conceptos(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[ConceptoInventarioOut]:
    rows = await _SERVICE.list_by_name(
        db, empresa.id_empresa, "conceptos_inventario"
    )
    return [ConceptoInventarioOut(**r) for r in rows]


@router.post(
    "/conceptos_inventario",
    response_model=ConceptoInventarioOut,
    dependencies=[Depends(require_catalog_manager)],
)
async def create_concepto(
    payload: ConceptoInventarioCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ConceptoInventarioOut:
    row = await _SERVICE.create(
        db,
        empresa.id_empresa,
        "conceptos_inventario",
        _normalizar(payload.model_dump()),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return ConceptoInventarioOut(**row)


@router.put(
    "/conceptos_inventario/{id_concepto}",
    response_model=ConceptoInventarioOut,
    dependencies=[Depends(require_catalog_manager)],
)
async def update_concepto(
    id_concepto: uuid.UUID,
    payload: ConceptoInventarioCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ConceptoInventarioOut:
    await _obtener_concepto(db, empresa, id_concepto)
    row = await _SERVICE.update(
        db,
        empresa.id_empresa,
        "conceptos_inventario",
        str(id_concepto),
        _normalizar(payload.model_dump()),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return ConceptoInventarioOut(**row)


@router.delete(
    "/conceptos_inventario/{id_concepto}",
    status_code=204,
    dependencies=[Depends(require_admin)],
)
async def delete_concepto(
    id_concepto: uuid.UUID,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _obtener_concepto(db, empresa, id_concepto)
    usados = await _contar_movimientos(db, empresa.id_empresa, id_concepto)
    if usados:
        raise HTTPException(
            status_code=409,
            detail=(
                f"No se puede eliminar: {usados} movimiento(s) de kardex usan "
                "este concepto. Desactívelo en su lugar."
            ),
        )
    await _SERVICE.delete(
        db,
        empresa.id_empresa,
        "conceptos_inventario",
        str(id_concepto),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
