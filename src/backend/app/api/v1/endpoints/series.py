"""Series de numeración de documentos por empresa.

- GET   /api/v1/empresa/series            → series de la empresa (cualquier rol)
- POST  /api/v1/empresa/series            → crear serie (ADMIN de la empresa)
- PUT   /api/v1/empresa/series/{id}       → actualizar datos técnicos (ADMIN)
- PUT   /api/v1/empresa/series/{id}/activa→ marcar ACTIVA (ADMIN, única por empresa)
- DELETE/api/v1/empresa/series/{id}       → quitar serie (ADMIN, no la in-use)

El "campo de trabajo" elige cuál serie usa cada boleto; los reportes y la
gestión muestran qué modelo de serie se aplicó. SOLO escrita por ADMIN; el
resto de roles la leen (REGLA_REQ-NF-SERIE-01).
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user, require_admin
from app.core.database import get_db
from app.models import BoletoPesaje, Empresa, SerieNumeracion, Usuario
from app.schemas import (
    SerieNumeracionCreate,
    SerieNumeracionOut,
    SerieNumeracionUpdate,
)

router = APIRouter(prefix="/api/v1/empresa/series", tags=["SeriesNumeracion"])


@router.get("", response_model=list[SerieNumeracionOut])
async def listar_series(
    _user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[SerieNumeracion]:
    """Lista las series de la empresa (orden: activa primero, luego nombre)."""
    return list(
        (
            await db.execute(
                select(SerieNumeracion)
                .where(SerieNumeracion.id_empresa == empresa.id_empresa)
                .order_by(SerieNumeracion.activa.desc(), SerieNumeracion.nombre.asc())
            )
        ).scalars()
    )


@router.post("", response_model=SerieNumeracionOut, status_code=status.HTTP_201_CREATED)
async def crear_serie(
    data: SerieNumeracionCreate,
    _admin: Usuario = Depends(require_admin),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> SerieNumeracion:
    """Crea un modelo de serie para la empresa. Si es la primera o trae
    ``activa=True`` se activa (única por empresa)."""
    n_existentes = (
        await db.scalar(
            select(SerieNumeracion.id_serie).where(
                SerieNumeracion.id_empresa == empresa.id_empresa
            )
        )
    )
    activa = bool(data.activa) or n_existentes is None
    if activa:
        await db.execute(
            update(SerieNumeracion)
            .where(SerieNumeracion.id_empresa == empresa.id_empresa)
            .values(activa=False)
        )
    serie = SerieNumeracion(
        id_empresa=empresa.id_empresa,
        nombre=data.nombre,
        prefijo=data.prefijo,
        inicio=data.inicio,
        siguiente=data.inicio,
        digitos=data.digitos,
        activa=activa,
    )
    db.add(serie)
    await db.commit()
    await db.refresh(serie)
    return serie


@router.put("/{serie_id}", response_model=SerieNumeracionOut)
async def actualizar_serie(
    serie_id: uuid.UUID,
    data: SerieNumeracionUpdate,
    _admin: Usuario = Depends(require_admin),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> SerieNumeracion:
    serie = (
        await db.scalar(
            select(SerieNumeracion).where(
                SerieNumeracion.id_serie == serie_id,
                SerieNumeracion.id_empresa == empresa.id_empresa,
            )
        )
    )
    if serie is None:
        raise HTTPException(status_code=404, detail="Serie no encontrada")
    for campo, valor in data.model_dump(exclude_unset=True).items():
        if valor is not None:
            setattr(serie, campo, valor)
    await db.commit()
    await db.refresh(serie)
    return serie


@router.put("/{serie_id}/activa", response_model=SerieNumeracionOut)
async def marcar_serie_activa(
    serie_id: uuid.UUID,
    _admin: Usuario = Depends(require_admin),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> SerieNumeracion:
    """Marca una serie como activa (única por empresa: desactiva las demás)."""
    serie = (
        await db.scalar(
            select(SerieNumeracion).where(
                SerieNumeracion.id_serie == serie_id,
                SerieNumeracion.id_empresa == empresa.id_empresa,
            )
        )
    )
    if serie is None:
        raise HTTPException(status_code=404, detail="Serie no encontrada")
    await db.execute(
        update(SerieNumeracion)
        .where(SerieNumeracion.id_empresa == empresa.id_empresa)
        .values(activa=False)
    )
    serie.activa = True
    await db.commit()
    await db.refresh(serie)
    return serie


@router.delete("/{serie_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar_serie(
    serie_id: uuid.UUID,
    _admin: Usuario = Depends(require_admin),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Quita una serie. Si hay boletos que la usan, 409 (no huérfanos)."""
    serie = (
        await db.scalar(
            select(SerieNumeracion).where(
                SerieNumeracion.id_serie == serie_id,
                SerieNumeracion.id_empresa == empresa.id_empresa,
            )
        )
    )
    if serie is None:
        raise HTTPException(status_code=404, detail="Serie no encontrada")
    en_uso = (
        await db.scalar(
            select(BoletoPesaje.boleto).where(BoletoPesaje.id_serie == serie_id)
        )
    )
    if en_uso is not None:
        raise HTTPException(
            status_code=409,
            detail="La serie tiene boletos asociados; no se puede eliminar",
        )
    await db.delete(serie)
    await db.commit()
