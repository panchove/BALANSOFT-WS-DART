"""Utilidades de fechas del dominio.

Regla del proyecto: los `TIMESTAMP` de PostgreSQL son **naive y en UTC**
(`AGENTS.md`: timestamps en UTC, conversión a local solo en Flutter). Todo dato
que entra de afuera —respuesta del LM (`expires_at` en ISO-8601 con offset),
ISO del cliente Flutter en `POST /sync/push`,Body del servidor central— llega
*aware* y debe normalizarse, o asyncpg responde `DataError`
("can't subtract offset-naive and offset-aware datetimes") y la operación
—incluido el login— se cae con 500.
"""

from __future__ import annotations

from datetime import UTC, datetime


def naive_utc(valor: datetime | None) -> datetime | None:
    """Convierte a UTC y quita el `tzinfo` (None si la entrada es None).

    >>> naive_utc(datetime(2026, 10, 1, 9, tzinfo=timezone(timedelta(hours=-4))))
    datetime.datetime(2026, 10, 1, 13, 0)
    """
    if valor is None:
        return None
    if valor.tzinfo is None:
        return valor
    return valor.astimezone(UTC).replace(tzinfo=None)