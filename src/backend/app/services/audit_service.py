"""Servicio de auditoría de negocio hacia la tabla `auditoria`.

Complementa a `AuditMiddleware` (que registra en `logs_sistema`) con la
trazabilidad funcional (accion/entidad/entidad_id/detalle/ip) que exige
REQ-NF-SEG-001. Nunca rompe la operación principal: si falla, solo se
registra un warning.
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime
from decimal import Decimal
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Auditoria

log = logging.getLogger("balansoft_ws.audit")


def _serializar(value: Any) -> Any:
    """Convierte valores no-JSON (Decimal/UUID/datetime) a tipos JSON."""
    if isinstance(value, dict):
        return {k: _serializar(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_serializar(v) for v in value]
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, uuid.UUID):
        return str(value)
    if isinstance(value, datetime):
        return value.isoformat()
    return value


async def registrar(
    db: AsyncSession,
    *,
    id_usuario: uuid.UUID | None,
    id_empresa: uuid.UUID | None,
    accion: str,
    entidad: str,
    entidad_id: str | None = None,
    detalle: dict[str, Any] | None = None,
    ip: str | None = None,
) -> None:
    """Agrega una fila a `auditoria` en la sesión actual (sin commit propio).

    El commit lo realiza la operación principal para conservar la atomicidad.
    """
    try:
        db.add(
            Auditoria(
                id_usuario=id_usuario,
                id_empresa=id_empresa,
                accion=accion,
                entidad=entidad,
                entidad_id=entidad_id,
                detalle=_serializar(detalle) if detalle else None,
                ip=ip,
            )
        )
    except Exception:
        log.warning("No se pudo registrar auditoría (non-critical)", exc_info=True)