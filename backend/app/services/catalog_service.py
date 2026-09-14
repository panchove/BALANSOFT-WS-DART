"""Servicio de catálogos: operaciones CRUD genéricas por entidad."""

from __future__ import annotations

import logging
import uuid
from typing import Any

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

log = logging.getLogger(__name__)

# Mapeo: nombre de entidad -> (modelo, columna de filtro por empresa)
from app.models import (
    Almacen,
    Balanza,
    Camion,
    Conductor,
    Marca,
    ModeloCamion,
    Producto,
    Remolque,
    Tercero,
    Transporte,
)
from app.services.audit_service import registrar

CATALOGS: dict[str, dict[str, Any]] = {
    "camiones": {"model": Camion, "empresa_col": "id_empresa", "id_col": "id"},
    "remolques": {"model": Remolque, "empresa_col": "id_empresa", "id_col": "id_remolque"},
    "marcas": {"model": Marca, "empresa_col": "id_empresa", "id_col": "id_marca"},
    "modelos_camion": {"model": ModeloCamion, "empresa_col": "id_empresa", "id_col": "id_modelo_camion"},
    "transportes": {"model": Transporte, "empresa_col": "id_empresa", "id_col": "id_transporte"},
    "conductores": {"model": Conductor, "empresa_col": "id_empresa", "id_col": "cedula_dni"},
    "productos": {"model": Producto, "empresa_col": "id_empresa", "id_col": "id_producto"},
    "almacenes": {"model": Almacen, "empresa_col": "id_empresa", "id_col": "id_almacen"},
    "balanzas": {"model": Balanza, "empresa_col": "id_empresa", "id_col": "id_balanza"},
    "terceros": {"model": Tercero, "empresa_col": "id_empresa", "id_col": "id_tercero"},
}


class CatalogService:
    async def list_all(self, db: AsyncSession, empresa_id: uuid.UUID) -> dict[str, list]:
        result: dict[str, list] = {}
        for name, cfg in CATALOGS.items():
            model = cfg["model"]
            stmt = select(model).where(getattr(model, cfg["empresa_col"]) == empresa_id)
            rows = (await db.execute(stmt)).scalars().all()
            result[name] = [self._dump(r) for r in rows]
        return result

    async def list_by_name(
        self, db: AsyncSession, empresa_id: uuid.UUID, name: str
    ) -> list:
        cfg = CATALOGS.get(name)
        if cfg is None:
            raise HTTPException(status_code=404, detail=f"Catálogo desconocido: {name}")
        model = cfg["model"]
        stmt = select(model).where(getattr(model, cfg["empresa_col"]) == empresa_id)
        rows = (await db.execute(stmt)).scalars().all()
        return [self._dump(r) for r in rows]

    async def create(
        self,
        db: AsyncSession,
        empresa_id: uuid.UUID,
        name: str,
        data: dict,
        *,
        id_usuario: uuid.UUID | None = None,
        ip: str | None = None,
    ) -> Any:
        cfg = CATALOGS.get(name)
        if cfg is None:
            raise HTTPException(status_code=404, detail=f"Catálogo desconocido: {name}")
        model = cfg["model"]
        values = dict(data)
        values[cfg["empresa_col"]] = empresa_id
        obj = model(**values)
        db.add(obj)
        try:
            await db.flush()
            await registrar(
                db,
                id_usuario=id_usuario,
                id_empresa=empresa_id,
                accion="CREATE",
                entidad=name,
                entidad_id=str(getattr(obj, cfg["id_col"])),
                ip=ip,
            )
            await db.commit()
        except Exception as e:  # unique violation etc.
            await db.rollback()
            log.exception("Error creando registro en catálogo '%s'", name)
            raise HTTPException(status_code=400, detail=f"No se pudo crear: {e}") from e
        await db.refresh(obj)
        return self._dump(obj)

    async def update(
        self,
        db: AsyncSession,
        empresa_id: uuid.UUID,
        name: str,
        id_value: str,
        data: dict,
        *,
        id_usuario: uuid.UUID | None = None,
        ip: str | None = None,
    ) -> Any:
        cfg = CATALOGS.get(name)
        if cfg is None:
            raise HTTPException(status_code=404, detail=f"Catálogo desconocido: {name}")
        model = cfg["model"]
        stmt = select(model).where(
            getattr(model, cfg["empresa_col"]) == empresa_id,
            getattr(model, cfg["id_col"]) == id_value,
        )
        obj = (await db.execute(stmt)).scalar_one_or_none()
        if obj is None:
            raise HTTPException(status_code=404, detail="Registro no encontrado")
        for k, v in data.items():
            if k != cfg["empresa_col"] and hasattr(obj, k):
                setattr(obj, k, v)
        await registrar(
            db,
            id_usuario=id_usuario,
            id_empresa=empresa_id,
            accion="UPDATE",
            entidad=name,
            entidad_id=str(id_value),
            detalle={"campos_modificados": sorted(data.keys())},
            ip=ip,
        )
        await db.commit()
        await db.refresh(obj)
        return self._dump(obj)

    async def delete(
        self,
        db: AsyncSession,
        empresa_id: uuid.UUID,
        name: str,
        id_value: str,
        *,
        id_usuario: uuid.UUID | None = None,
        ip: str | None = None,
    ) -> None:
        cfg = CATALOGS.get(name)
        if cfg is None:
            raise HTTPException(status_code=404, detail=f"Catálogo desconocido: {name}")
        model = cfg["model"]
        stmt = select(model).where(
            getattr(model, cfg["empresa_col"]) == empresa_id,
            getattr(model, cfg["id_col"]) == id_value,
        )
        obj = (await db.execute(stmt)).scalar_one_or_none()
        if obj is None:
            raise HTTPException(status_code=404, detail="Registro no encontrado")
        await registrar(
            db,
            id_usuario=id_usuario,
            id_empresa=empresa_id,
            accion="DELETE",
            entidad=name,
            entidad_id=str(id_value),
            ip=ip,
        )
        await db.delete(obj)
        await db.commit()

    def _dump(self, obj: Any) -> dict:
        from sqlalchemy.inspection import inspect as sa_inspect

        out: dict[str, Any] = {}
        for col in sa_inspect(obj).mapper.column_attrs:
            val = getattr(obj, col.key)
            if val is None:
                out[col.key] = None
            elif hasattr(val, "isoformat"):
                out[col.key] = val.isoformat()
            else:
                out[col.key] = val
        return out
