"""Servicio de auditoría de negocio hacia la tabla `auditoria`.

Complementa a `AuditMiddleware` (que registra en `logs_sistema`) con la
trazabilidad funcional (accion/entidad/entidad_id/detalle/ip) que exige
REQ-NF-SEG-001. Nunca rompe la operación principal: si falla, solo se
registra un warning.

Versión: 0.4.2-dev.56
Fecha: 2026-10-19
Estado: Vigente
Norma: ISO/IEC 27001 / ISO/IEC 25010
Fuente: Sistema BALANSOFT-WS
Autor: Lead Architect
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
    """Convierte de forma recursiva valores no-JSON a tipos serializables estándar.

    Precondiciones:
        - `value`: Cualquier objeto o estructura anidada de Python.

    Poscondiciones:
        - Retorna tipos nativos JSON (dict, list, float, str) listos para almacenamiento.
    """
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
    """Agrega una entrada inmutable de auditoría funcional a la sesión de base de datos activa.

    Precondiciones:
        - `db`: Sesión asíncrona abierta y transaccional activa.
        - `accion`: Identificador en mayúsculas de la operación (ej. 'CREAR', 'EDITAR', 'ANULAR').
        - `entidad`: Nombre de la tabla o entidad de negocio afectada (ej. 'boletos_pesaje').

    Poscondiciones:
        - Instancia `Auditoria` añadida al contexto de SQLAlchemy (`db.add`).
        - Atomicidad garantizada: El commit lo realiza la operación principal.
        - No-bloqueante ante fallos: Si ocurre un error de serialización, emite advertencia en logs
          sin abortar la transacción de negocio principal.
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