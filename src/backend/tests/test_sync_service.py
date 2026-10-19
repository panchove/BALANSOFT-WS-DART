"""Regresión del push offline: datetimes con offset → columnas naive (H2).

`boletos_pesaje.fecha_hora_*` son `TIMESTAMP WITHOUT TIME ZONE` (UTC naive). La
app y otros clientes envían ISO-8601 con offset; sin normalizar, asyncpg lanza
`DataError` y todo el lote de sincronización se cae.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta, timezone
from decimal import Decimal

import pytest

from app.core.datetime_utils import naive_utc


class TestNaiveUtc:
    def test_aware_se_convierte_a_utc_naive(self):
        v = datetime(2026, 10, 1, 9, 0, tzinfo=timezone(timedelta(hours=-4)))
        convertido = naive_utc(v)
        assert convertido == datetime(2026, 10, 1, 13, 0)
        assert convertido.tzinfo is None

    def test_aware_utc_se_normaliza(self):
        v = datetime(2026, 10, 1, 13, 0, 30, tzinfo=UTC)
        assert naive_utc(v) == datetime(2026, 10, 1, 13, 0, 30)
        assert naive_utc(v) is not None

    def test_naive_se_deja_intacto(self):
        v = datetime(2026, 10, 1, 13, 0, 30)
        assert naive_utc(v) == v

    def test_none_es_none(self):
        assert naive_utc(None) is None


@pytest.mark.asyncio
async def test_push_guarda_fechas_en_utc_naive(db, empresa):
    """End-to-end del servicio: el boleto del push queda con la hora UTC correcta."""
    from sqlalchemy import select

    from app.models import BoletoPesaje
    from app.schemas import WeighingSyncItem
    from app.services.sync_service import SyncService

    entrada = datetime(2026, 10, 1, 9, 0, tzinfo=timezone(timedelta(hours=-4)))
    item = WeighingSyncItem(
        boleto=str(uuid.uuid4()),
        id_vehiculo="TZ-001",
        fecha_hora_entrada=entrada,
        peso_entrada_vehiculo=Decimal("10000"),
        created_at=entrada,
        updated_at=entrada,
    )
    sincronizados, errores, _ = await SyncService().process_batch(db, empresa, [item])
    assert (sincronizados, errores) == (1, 0)

    fila = (
        await db.execute(
            select(BoletoPesaje).where(
                BoletoPesaje.id_empresa == empresa.id_empresa,
                BoletoPesaje.id_vehiculo == "TZ-001",
            )
        )
    ).scalar_one()
    assert fila.fecha_hora_entrada == datetime(2026, 10, 1, 13, 0)
    assert fila.fecha_hora_entrada.tzinfo is None
