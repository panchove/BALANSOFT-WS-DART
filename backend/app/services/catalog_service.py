"""Servicio de catálogos: operaciones CRUD genéricas por entidad."""

from __future__ import annotations

import logging
import uuid
from collections.abc import Sequence
from typing import Any

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    Almacen,
    Balanza,
    Camion,
    Categoria,
    Conductor,
    Marca,
    ModeloCamion,
    Producto,
    Remolque,
    Tercero,
    Transporte,
)
from app.services.audit_service import registrar

log = logging.getLogger(__name__)

# Mapeo: nombre de entidad -> (modelo, columna de filtro por empresa)
CATALOGS: dict[str, dict[str, Any]] = {
    "camiones": {"model": Camion, "empresa_col": "id_empresa", "id_col": "id"},
    "remolques": {"model": Remolque, "empresa_col": "id_empresa", "id_col": "id_remolque"},
    "marcas": {"model": Marca, "empresa_col": "id_empresa", "id_col": "id_marca"},
    "modelos_camion": {
        "model": ModeloCamion,
        "empresa_col": "id_empresa",
        "id_col": "id_modelo_camion",
    },
    "transportes": {"model": Transporte, "empresa_col": "id_empresa", "id_col": "id_transporte"},
    "conductores": {"model": Conductor, "empresa_col": "id_empresa", "id_col": "cedula_dni"},
    "productos": {"model": Producto, "empresa_col": "id_empresa", "id_col": "id_producto"},
    "almacenes": {"model": Almacen, "empresa_col": "id_empresa", "id_col": "id_almacen"},
    "categorias": {"model": Categoria, "empresa_col": "id_empresa", "id_col": "id_categoria"},
    "balanzas": {"model": Balanza, "empresa_col": "id_empresa", "id_col": "id_balanza"},
    "terceros": {"model": Tercero, "empresa_col": "id_empresa", "id_col": "id_tercero"},
}


# Etiqueta singular legible por entidad (para mensajes de conflicto).
_ETIQUETAS_ENTIDAD: dict[str, str] = {
    "camiones": "vehículo",
    "remolques": "remolque",
    "marcas": "marca",
    "modelos_camion": "modelo de camión",
    "transportes": "transportista",
    "conductores": "conductor",
    "productos": "producto",
    "almacenes": "almacén",
    "categorias": "categoría",
    "balanzas": "báscula",
    "terceros": "tercero",
}


def _mensaje_conflicto_codigo(name: str, data: dict) -> str:
    """Mensaje claro cuando se viola la unicidad de `codigo` por empresa.

    Los índices `<tabla>_empresa_codigo_uk` (migración 018) solo exigen
    unicidad cuando `codigo IS NOT NULL`; si el choque viene de otra
    restricción única se devuelve un mensaje genérico.
    """
    etiqueta = _ETIQUETAS_ENTIDAD.get(name, name)
    codigo = (data.get("codigo") or "").strip()
    if codigo:
        return f"Ya existe un {etiqueta} con el código '{codigo}'"
    return f"Registro duplicado de {etiqueta}"


class CatalogService:
    async def list_all(
        self,
        db: AsyncSession,
        empresa_id: uuid.UUID,
        *,
        limite: int | None = None,
        skip: int = 0,
        solo: Sequence[str] | None = None,
    ) -> dict[str, Any]:
        """Devuelve todos los catálogos de la empresa.

        ``limite``/``skip`` paginan cada catálogo (H11). Sin ``limite`` el
        comportamiento es el histórico: se devuelve el catálogo completo. La
        clave ``__totales__`` lleva el número real de filas por catálogo y
        ``__truncado__`` indica si alguna respuesta quedó recortada.
        """
        pedidos = [n for n in CATALOGS if solo is None or n in solo]
        desconocidos = [n for n in (solo or []) if n not in CATALOGS]
        if desconocidos:
            raise HTTPException(
                status_code=404,
                detail=f"Catálogo desconocido: {', '.join(sorted(desconocidos))}",
            )

        result: dict[str, Any] = {}
        totales: dict[str, int] = {}
        truncado = False
        for name in pedidos:
            filas, total = await self._listar_paginado(
                db, empresa_id, name, limite=limite, skip=skip
            )
            result[name] = filas
            totales[name] = total
            if limite is not None and total > skip + len(filas):
                truncado = True
        result["__totales__"] = totales
        result["__truncado__"] = truncado
        return result

    async def _listar_paginado(
        self,
        db: AsyncSession,
        empresa_id: uuid.UUID,
        name: str,
        *,
        limite: int | None,
        skip: int,
    ) -> tuple[list[dict], int]:
        cfg = CATALOGS[name]
        model = cfg["model"]
        filtro = getattr(model, cfg["empresa_col"]) == empresa_id
        total = await db.scalar(select(func.count()).select_from(model).where(filtro))
        stmt = select(model).where(filtro)
        if skip:
            stmt = stmt.offset(skip)
        if limite is not None:
            stmt = stmt.limit(limite)
        rows = (await db.execute(stmt)).scalars().all()
        return [self._dump(r) for r in rows], int(total or 0)

    async def list_by_name(self, db: AsyncSession, empresa_id: uuid.UUID, name: str) -> list:
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
        except IntegrityError as e:
            await db.rollback()
            log.warning("Código duplicado al crear en catálogo '%s': %s", name, e.orig)
            raise HTTPException(status_code=409, detail=_mensaje_conflicto_codigo(name, values)) from e
        except Exception as e:
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
        try:
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
        except IntegrityError as e:
            await db.rollback()
            log.warning("Código duplicado al actualizar en catálogo '%s': %s", name, e.orig)
            raise HTTPException(status_code=409, detail=_mensaje_conflicto_codigo(name, data)) from e
        except Exception as e:
            await db.rollback()
            log.exception("Error actualizando registro en catálogo '%s'", name)
            raise HTTPException(status_code=400, detail=f"No se pudo actualizar: {e}") from e
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
        from sqlalchemy.exc import IntegrityError
        try:
            await db.delete(obj)
            await db.commit()
        except IntegrityError as err:
            await db.rollback()
            raise HTTPException(
                status_code=400,
                detail="No se puede eliminar el registro porque está en uso en el sistema (ej. en un pesaje)."
            ) from err

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
