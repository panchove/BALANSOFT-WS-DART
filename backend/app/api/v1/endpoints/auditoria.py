"""Consulta de la tabla ``auditoria`` (REQ-NF-SEG-001).

Expone el registro funcional completo (acción, entidad, entidad_id, detalle,
IP, usuario y timestamp UTC) que complementa al estado transaccional del
boleto. Solo ADMIN y AUDITOR pueden consultarlo.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.core.database import get_db
from app.models import Auditoria, Usuario

router = APIRouter(prefix="/api/v1/auditoria", tags=["Auditoria"])

_PERMISOS_CONSULTA = {"ADMIN", "AUDITOR"}
_MAX_LIMIT = 500


class AuditoriaOut(BaseModel):
    id_auditoria: str
    id_usuario: str | None = None
    usuario_email: str | None = None
    accion: str
    entidad: str | None = None
    entidad_id: str | None = None
    detalle: dict[str, Any] | None = None
    ip: str | None = None
    created_at: datetime


@router.get("", response_model=list[AuditoriaOut])
async def listar_auditoria(
    entidad: str | None = None,
    accion: str | None = None,
    fecha_desde: datetime | None = None,
    fecha_hasta: datetime | None = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=_MAX_LIMIT),
    usuario: Usuario = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[AuditoriaOut]:
    if usuario.rol not in _PERMISOS_CONSULTA:
        raise HTTPException(
            status_code=403, detail="No autorizado para consultar la auditoría"
        )

    stmt = (
        select(Auditoria, Usuario.email)
        .outerjoin(Usuario, Usuario.id_usuario == Auditoria.id_usuario)
        .where(Auditoria.id_empresa == usuario.id_empresa)
    )
    if entidad:
        stmt = stmt.where(Auditoria.entidad == entidad)
    if accion:
        stmt = stmt.where(Auditoria.accion == accion)
    if fecha_desde:
        stmt = stmt.where(Auditoria.created_at >= fecha_desde)
    if fecha_hasta:
        stmt = stmt.where(Auditoria.created_at <= fecha_hasta)

    stmt = stmt.order_by(Auditoria.created_at.desc()).offset(skip).limit(limit)
    filas = (await db.execute(stmt)).all()
    return [
        AuditoriaOut(
            id_auditoria=str(a.id_auditoria),
            id_usuario=str(a.id_usuario) if a.id_usuario else None,
            usuario_email=email,
            accion=a.accion,
            entidad=a.entidad,
            entidad_id=a.entidad_id,
            detalle=a.detalle,
            ip=a.ip,
            created_at=a.created_at,
        )
        for a, email in filas
    ]
