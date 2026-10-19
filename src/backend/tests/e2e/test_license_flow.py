"""E2E del flujo de licencia a través de la API real: login → validate-license → pesajes (H2)."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app.models import BoletoPesaje, Empresa, IdentidadLocal
from tests.e2e.conftest import LICENCIA_TEST

pytestmark = pytest.mark.e2e


async def _set_licencia(db, empresa: Empresa, key: str, status: str = "ACTIVE") -> None:
    empresa.licencia_key = key
    empresa.licencia_status = status
    await db.commit()


async def _identidad(db) -> IdentidadLocal | None:
    return (
        await db.execute(select(IdentidadLocal).where(IdentidadLocal.id.is_(True)))
    ).scalar_one_or_none()


class TestFlujoLicencia:
    async def test_login_con_licencia_valida(self, api_client_anon, admin_user):
        r = await api_client_anon.post(
            "/api/v1/auth/login",
            json={"email": admin_user.email, "password": "demo1234"},
        )
        assert r.status_code == 200, r.text
        cuerpo = r.json()
        assert cuerpo["access_token"]
        assert cuerpo["user"]["email"] == admin_user.email

    async def test_login_persiste_expiracion_naive(
        self, api_client_anon, db, empresa, admin_user
    ):
        """Regresión: el LM responde ISO con offset y `empresas.licencia_expira`
        es `TIMESTAMP WITHOUT TIME ZONE`; sin normalizar, el login moría con 500.
        """
        await _set_licencia(db, empresa, LICENCIA_TEST)
        r = await api_client_anon.post(
            "/api/v1/auth/login",
            json={"email": admin_user.email, "password": "demo1234"},
        )
        assert r.status_code == 200, r.text
        await db.refresh(empresa)
        assert empresa.licencia_expira is not None, "el login debe cachear la expiración"
        assert empresa.licencia_expira.tzinfo is None
        assert empresa.licencia_status == "ACTIVE"

    async def test_login_credenciales_invalidas(self, api_client_anon, admin_user):
        r = await api_client_anon.post(
            "/api/v1/auth/login",
            json={"email": admin_user.email, "password": "incorrecta"},
        )
        assert r.status_code in (400, 401), r.text

    async def test_validate_license_con_stub_firmado(
        self, api_client, db, empresa, lm_modo
    ):
        """El endpoint persiste licencia/tier/identidad desde la respuesta firmada."""
        await _set_licencia(db, empresa, LICENCIA_TEST)
        r = await api_client.post(
            "/api/v1/auth/validate-license",
            json={"licencia_key": LICENCIA_TEST, "hardware_id": "HW-E2E-API-01"},
        )
        assert r.status_code == 200, r.text
        cuerpo = r.json()
        assert cuerpo["valid"] is True
        assert cuerpo["status"] == "ACTIVE"
        assert cuerpo["tier"]

        await db.refresh(empresa)
        assert empresa.licencia_key == LICENCIA_TEST
        assert (empresa.licencia_status or "").upper() == "ACTIVE"

    async def test_validate_license_vencida_no_es_valida(
        self, api_client, db, empresa, lm_modo
    ):
        lm_modo("expired")
        await _set_licencia(db, empresa, LICENCIA_TEST)
        r = await api_client.post(
            "/api/v1/auth/validate-license",
            json={"licencia_key": LICENCIA_TEST, "hardware_id": "HW-E2E-API-02"},
        )
        assert r.status_code == 200, r.text
        assert r.json()["valid"] is False
        assert r.json()["status"] == "EXPIRED"

    async def test_validate_license_suspendida_no_es_valida(
        self, api_client, db, empresa, lm_modo
    ):
        lm_modo("invalid")
        await _set_licencia(db, empresa, LICENCIA_TEST)
        r = await api_client.post(
            "/api/v1/auth/validate-license",
            json={"licencia_key": LICENCIA_TEST, "hardware_id": "HW-E2E-API-03"},
        )
        assert r.status_code == 200, r.text
        assert r.json()["valid"] is False
        assert r.json()["status"] == "SUSPENDIDA"

    async def test_license_endpoint_revalida_en_vivo(self, api_client, db, empresa):
        """`GET /auth/license` re-valida contra el stub y devuelve el snapshot."""
        await _set_licencia(db, empresa, LICENCIA_TEST)
        r = await api_client.get("/api/v1/auth/license")
        assert r.status_code == 200, r.text
        cuerpo = r.json()
        assert cuerpo["valid"] is True
        assert cuerpo["status"] == "ACTIVE"
        # La clave nunca se expone en claro: va enmascarada.
        assert cuerpo["licencia_key_masked"] == "BWS-...TEST"

    async def test_license_endpoint_cachea_si_lm_cae(
        self, api_client, db, empresa, lm_modo
    ):
        """Offline-first: si el LM no responde, devuelve el estado cacheado."""
        await _set_licencia(db, empresa, LICENCIA_TEST)
        lm_modo("unreachable")
        r = await api_client.get("/api/v1/auth/license")
        assert r.status_code == 200, r.text
        assert r.json()["status"] == "ACTIVE"


class TestPesajesConLicencia:
    """El gate de licencia de pesajes opera con la licencia firmada por el stub."""

    async def test_crear_boleto_con_licencia_activa(self, api_client, db, empresa):
        await _set_licencia(db, empresa, LICENCIA_TEST, status="ACTIVE")
        r = await api_client.post(
            "/api/v1/weighing/create",
            json={
                "id_vehiculo": "ABC-123",
                "fecha_hora_entrada": datetime.now(UTC).isoformat(),
                "peso_entrada_vehiculo": 12000,
            },
        )
        assert r.status_code == 200, r.text
        cuerpo = r.json()
        assert cuerpo["estado_boleto"] == "PENDIENTE"

        boleto = (
            await db.execute(
                select(BoletoPesaje).where(
                    BoletoPesaje.id_empresa == empresa.id_empresa,
                    BoletoPesaje.id_vehiculo == "ABC-123",
                )
            )
        ).scalar_one()
        assert boleto.estado_boleto == "PENDIENTE"
        assert boleto.boleto == uuid.UUID(cuerpo["boleto"])

    async def test_cerrar_boleto_con_licencia_activa(self, api_client, db, empresa):
        await _set_licencia(db, empresa, LICENCIA_TEST, status="ACTIVE")
        creado = await api_client.post(
            "/api/v1/weighing/create",
            json={
                "id_vehiculo": "XYZ-987",
                "peso_entrada_vehiculo": 30000,
            },
        )
        assert creado.status_code == 200, creado.text
        boleto_id = creado.json()["boleto"]

        cerrado = await api_client.post(
            f"/api/v1/weighing/close/{boleto_id}",
            json={
                "peso_salida_vehiculo": 48000,
                "fecha_hora_salida": datetime.now(UTC).isoformat(),
            },
        )
        assert cerrado.status_code == 200, cerrado.text
        cuerpo = cerrado.json()
        assert cuerpo["estado_boleto"] == "CERRADO"
        # Convención del dominio: peso_neto = entrada - salida. Negativo = DESPACHO.
        assert float(cuerpo["peso_neto"]) == pytest.approx(-18000.0)
        assert float(cuerpo["peso_bruto"]) == pytest.approx(48000.0)
        assert float(cuerpo["peso_tara"]) == pytest.approx(30000.0)

    async def test_pesaje_creado_queda_pendiente_de_sync(self, api_client, db, empresa):
        """Un boleto creado offline queda `sincronizado=false` (base del push)."""
        await _set_licencia(db, empresa, LICENCIA_TEST, status="ACTIVE")
        await api_client.post(
            "/api/v1/weighing/create",
            json={
                "id_vehiculo": "OFF-001",
                "fecha_hora_entrada": (datetime.now(UTC) - timedelta(days=2)).isoformat(),
                "peso_entrada_vehiculo": 9000,
            },
        )
        boleto = (
            await db.execute(
                select(BoletoPesaje).where(
                    BoletoPesaje.id_empresa == empresa.id_empresa,
                    BoletoPesaje.id_vehiculo == "OFF-001",
                )
            )
        ).scalar_one()
        assert boleto.sincronizado is False