"""Rutas de reportes."""

from __future__ import annotations

from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa
from app.core.database import get_db
from app.models import Empresa
from app.services.report_service import ReportService

router = APIRouter(prefix="/api/v1/reports", tags=["Reports"])

_SERVICE = ReportService()


@router.get("/daily")
async def daily_report(
    fecha: date = date.today(),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await _SERVICE.daily(db, empresa, fecha)


@router.get("/monthly")
async def monthly_report(
    year: int,
    month: int,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    if not (1 <= month <= 12):
        raise HTTPException(status_code=400, detail="Mes inválido")
    return await _SERVICE.monthly(db, empresa, year, month)


@router.get("/vehicle/{vehicle_id}")
async def vehicle_report(
    vehicle_id: str,
    date_from: datetime,
    date_to: datetime,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await _SERVICE.vehicle(db, empresa, vehicle_id, date_from, date_to)


@router.get("/kardex/saldo")
async def kardex_saldo(
    fecha_corte: datetime | None = None,
    id_producto: str | None = None,
    id_almacen: str | None = None,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Saldo de kardex a fecha de corte (MODEL.md): positivos 01-49 − negativos 50-99."""
    corte = fecha_corte or datetime.now()
    return await _SERVICE.kardex_saldo(db, empresa, corte, id_producto, id_almacen)


@router.get("/kardex/detalle")
async def kardex_detalle(
    fecha_desde: datetime,
    fecha_hasta: datetime,
    id_producto: str | None = None,
    id_almacen: str | None = None,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Movimientos de kardex en el rango con saldo acumulado (PRD §9.6)."""
    return await _SERVICE.kardex_detalle(
        db,
        empresa,
        fecha_desde,
        fecha_hasta,
        id_producto,
        id_almacen,
    )


@router.get("/transportista")
async def reporte_transportista(
    fecha_desde: datetime,
    fecha_hasta: datetime,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Ranking de transportistas por volumen movilizado (cerrado/sin anular)."""
    return await _SERVICE.transportista(db, empresa, fecha_desde, fecha_hasta)


@router.get("/tercero")
async def reporte_tercero(
    fecha_desde: datetime,
    fecha_hasta: datetime,
    tipo_tercero: str | None = None,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Volumen por cliente/proveedor (tercero) en el rango."""
    return await _SERVICE.tercero(db, empresa, fecha_desde, fecha_hasta, tipo_tercero)


@router.get("/peso-rango")
async def reporte_peso_rango(
    fecha_desde: datetime,
    fecha_hasta: datetime,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Distribución de pesos netos por rango (buckets de tonelaje)."""
    return await _SERVICE.peso_rango(db, empresa, fecha_desde, fecha_hasta)


@router.get("/comparativo-mensual")
async def reporte_comparativo_mensual(
    year: int,
    month: int,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Comparativo mes actual vs. mes anterior."""
    if not (1 <= month <= 12):
        raise HTTPException(status_code=400, detail="Mes inválido")
    return await _SERVICE.comparativo_mensual(db, empresa, year, month)
