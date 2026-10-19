"""E2E del ciclo offline de pesajes: push → status → pull por la API real (H2)."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app.models import BoletoPesaje, SyncLog

pytestmark = pytest.mark.e2e


def _item(veh: str, *, cerrado: bool = True) -> dict:
    """`WeighingSyncItem` mínimo válido para el push de sincronización.

    Ojo al contrato: `estado_boleto` sigue aceptando los valores legacy
    ("Abierto"/"Cerrado") y `created_at`/`updated_at` son obligatorios; el
    servicio los normaliza a PENDIENTE/CERRADO.
    """
    ahora = datetime.now(UTC) - timedelta(hours=6)
    return {
        "boleto": str(uuid.uuid4()),
        "id_vehiculo": veh,
        "fecha_hora_entrada": ahora.isoformat(),
        "peso_entrada_vehiculo": "10000",
        "peso_salida_vehiculo": "5000" if cerrado else None,
        "estado_boleto": "Cerrado" if cerrado else "Abierto",
        "created_at": ahora.isoformat(),
        "updated_at": ahora.isoformat(),
    }


class TestPushSync:
    async def test_push_crea_boletos(self, api_client, db, empresa):
        r = await api_client.post(
            "/api/v1/sync/push",
            json={"equipos": [], "pesajes": [_item("SYNC-001"), _item("SYNC-002")]},
        )
        assert r.status_code == 200, r.text
        cuerpo = r.json()
        assert cuerpo["sincronizados"] == 2
        assert cuerpo["errores"] == 0
        assert all(d["ok"] for d in cuerpo["detalle"])

        rows = (
            await db.execute(
                select(BoletoPesaje).where(BoletoPesaje.id_empresa == empresa.id_empresa)
            )
        ).scalars().all()
        assert len(rows) == 2
        assert {row.id_vehiculo for row in rows} == {"SYNC-001", "SYNC-002"}

    async def test_push_es_idempotente_por_boleto(self, api_client, db, empresa):
        """Reenviar el mismo lote no duplica: upsert determinístico por `boleto`."""
        item = _item("SYNC-IDEM")
        primero = await api_client.post(
            "/api/v1/sync/push", json={"equipos": [], "pesajes": [item]}
        )
        segundo = await api_client.post(
            "/api/v1/sync/push", json={"equipos": [], "pesajes": [item]}
        )
        assert primero.json()["sincronizados"] == 1
        assert segundo.json()["sincronizados"] == 1

        total = (
            await db.execute(
                select(BoletoPesaje).where(
                    BoletoPesaje.id_empresa == empresa.id_empresa,
                    BoletoPesaje.id_vehiculo == "SYNC-IDEM",
                )
            )
        ).scalars().all()
        assert len(total) == 1

    async def test_push_reporta_boleto_invalido(self, api_client):
        r = await api_client.post(
            "/api/v1/sync/push",
            json={
                "equipos": [],
                "pesajes": [
                    {
                        "boleto": "no-es-uuid",
                        "id_vehiculo": "SYNC-BAD",
                        "fecha_hora_entrada": datetime.now(UTC).isoformat(),
                        "peso_entrada_vehiculo": "1",
                        "created_at": datetime.now(UTC).isoformat(),
                        "updated_at": datetime.now(UTC).isoformat(),
                    }
                ],
            },
        )
        assert r.status_code == 200, r.text
        cuerpo = r.json()
        assert cuerpo["sincronizados"] == 0
        assert cuerpo["errores"] == 1
        assert cuerpo["detalle"][0]["mensaje"] == "boleto inválido"

    async def test_push_vacio_no_opera(self, api_client):
        r = await api_client.post("/api/v1/sync/push", json={"equipos": [], "pesajes": []})
        assert r.status_code == 200, r.text
        assert r.json() == {"sincronizados": 0, "errores": 0, "detalle": []}


class TestStatusYPull:
    async def test_status_reporta_pendientes(self, api_client, db, empresa):
        """Los boletos creados en la estación y aún no empujados cuentan como pendientes."""
        for veh in ("ST-001", "ST-002"):
            await api_client.post(
                "/api/v1/weighing/create",
                json={"id_vehiculo": veh, "peso_entrada_vehiculo": "8000"},
            )

        r = await api_client.get("/api/v1/sync/status")
        assert r.status_code == 200, r.text
        cuerpo = r.json()
        assert cuerpo["pendientes"] == 2
        assert cuerpo["usando_licencia_demo"] is False
        assert cuerpo["max_offline_dias"] >= 1

    async def test_status_sin_pendientes(self, api_client):
        r = await api_client.get("/api/v1/sync/status")
        assert r.status_code == 200, r.text
        assert r.json()["pendientes"] == 0

    async def test_pull_solo_devuelve_sincronizados(self, api_client, db, empresa):
        """`/sync/pull` reconstruye el caché local: solo lo ya sincronizado."""
        await api_client.post(
            "/api/v1/weighing/create",
            json={"id_vehiculo": "PULL-NO", "peso_entrada_vehiculo": "8000"},
        )
        await api_client.post(
            "/api/v1/sync/push",
            json={"equipos": [], "pesajes": [_item("PULL-OK")]},
        )

        r = await api_client.get("/api/v1/sync/pull")
        assert r.status_code == 200, r.text
        pesajes = r.json()["pesajes"]
        assert len(pesajes) == 1
        assert pesajes[0]["id_vehiculo"] == "PULL-OK"

    async def test_sync_log_registra_el_push(self, api_client, db, empresa):
        await api_client.post(
            "/api/v1/sync/push", json={"equipos": [], "pesajes": [_item("LOG-001")]}
        )
        logs = (
            await db.execute(
                select(SyncLog).where(SyncLog.id_empresa == empresa.id_empresa)
            )
        ).scalars().all()
        assert logs, "el push debe dejar rastro en sync_log"
        assert any(log.registros >= 1 for log in logs)
        assert all(log.tipo == "push" for log in logs)