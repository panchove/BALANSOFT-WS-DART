"""Pruebas funcionales HTTP de los endpoints de pesaje y autenticación.

Usa una app FastAPI fresca (sin middleware de auditoría para aislar de la BD
real), override de dependencias (usuario/empresa/DB) y un License Manager falso
via monkeypatch de get_license_client.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator

import httpx
import pytest_asyncio
from fastapi import FastAPI

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.api.v1.endpoints import auth as auth_module
from app.api.v1.endpoints import inventario as inventario_module
from app.api.v1.endpoints import pesajes as pesajes_module
from app.core import scale_session as scale_session_module
from app.core.database import get_db
from app.core.license_client import LicenseInfo
from app.models import Usuario


class FakeLM:
    """Cliente LM falso que siempre valida de forma positiva."""

    def check(self, license_key: str):
        return {"tier": "ENTERPRISE", "status": "ACTIVE"}

    def validate(self, license_key: str, hardware_id: str, **kwargs):
        return LicenseInfo(valid=True, tier="ENTERPRISE", status="ACTIVE", message="ok")

    def activate(self, license_key: str, hardware_id: str, **kwargs):
        return {"ok": True, "status": "ACTIVE"}

    def validate_or_activate(self, license_key: str, hardware_id: str, **kwargs):
        return self.validate(license_key, hardware_id, **kwargs)

    def validate_cached(self, license_key: str, hardware_id: str, **kwargs):
        return self.validate_or_activate(license_key, hardware_id, **kwargs)


class FakeHAL:
    """HAL de balanza falso para probar el endpoint de conexión."""

    def __init__(self, peso: float | None = 100.0, estable: bool = True):
        self._peso = peso
        self._estable = estable

    async def read_weight(self) -> float | None:
        return self._peso

    async def is_stable(self, duration_seconds: int = 3, tolerance_kg: float = 0.5):
        return self._estable


@pytest_asyncio.fixture
async def app(db, empresa, monkeypatch) -> FastAPI:
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin Test",
        email="admin@test.demo",
        password_hash="x",
        rol="ADMIN",
        activo=True,
    )
    db.add(user)
    await db.commit()

    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    application.dependency_overrides[get_current_user] = lambda: user
    application.dependency_overrides[get_current_empresa] = lambda: empresa

    monkeypatch.setattr(pesajes_module, "get_license_client", FakeLM)
    monkeypatch.setattr(auth_module, "get_license_client", FakeLM)
    return application


@pytest_asyncio.fixture
async def client(app) -> AsyncGenerator[httpx.AsyncClient, None]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


class TestPesajeEndpoints:
    async def test_create_pendiente(self, client, db):
        r = await client.post(
            "/api/v1/weighing/create",
            json={
                "id_vehiculo": "XYZ-123",
                "transporte_nombre": "Trans Test",
                "conductor_nombre": "Pepe",
                "producto_nombre": "Cemento",
                "almacen_nombre": "Planta A",
                "balanza_nombre": "B1",
                "tercero_nombre": "Cliente X",
                "peso_entrada_vehiculo": "50000",
            },
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["id_vehiculo"] == "XYZ-123"
        assert body["estado_boleto"] == "PENDIENTE"
        assert body["numero_boleto"].startswith("TA-")

    async def test_duplicado_pendiente_400(self, client):
        payload = {
            "id_vehiculo": "DUP-01",
            "transporte_nombre": "T",
            "conductor_nombre": "C",
            "producto_nombre": "P",
            "almacen_nombre": "A",
            "balanza_nombre": "B",
            "tercero_nombre": "X",
            "peso_entrada_vehiculo": "50000",
        }
        assert (await client.post("/api/v1/weighing/create", json=payload)).status_code == 200
        r2 = await client.post("/api/v1/weighing/create", json=payload)
        assert r2.status_code == 400
        assert "pendiente" in r2.json()["detail"]

    async def test_pendientes_lista(self, client):
        await client.post(
            "/api/v1/weighing/create",
            json={
                "id_vehiculo": "PEN-01",
                "transporte_nombre": "T",
                "conductor_nombre": "C",
                "producto_nombre": "P",
                "almacen_nombre": "A",
                "balanza_nombre": "B",
                "tercero_nombre": "X",
                "peso_entrada_vehiculo": "50000",
            },
        )
        r = await client.get("/api/v1/weighing/pendientes")
        assert r.status_code == 200
        assert any(p["id_vehiculo"] == "PEN-01" for p in r.json())

    async def test_cerrar_calcula_neto(self, client):
        created = (
            await client.post(
                "/api/v1/weighing/create",
                json={
                    "id_vehiculo": "CIE-01",
                    "transporte_nombre": "T",
                    "conductor_nombre": "C",
                    "producto_nombre": "P",
                    "almacen_nombre": "A",
                    "balanza_nombre": "B",
                    "tercero_nombre": "X",
                    "peso_entrada_vehiculo": "50000",
                },
            )
        ).json()
        boleto = created["boleto"]
        r = await client.post(
            f"/api/v1/weighing/close/{boleto}",
            json={"peso_salida_vehiculo": "45000", "densidad": "1.6"},
        )
        assert r.status_code == 200, r.text
        # El peso se serializa como Decimal -> string "5000.00"
        assert r.json()["peso_neto"] == "5000.00"

    async def test_pdf_genera(self, client):
        created = (
            await client.post(
                "/api/v1/weighing/create",
                json={
                    "id_vehiculo": "PDF-01",
                    "transporte_nombre": "T",
                    "conductor_nombre": "C",
                    "producto_nombre": "P",
                    "almacen_nombre": "A",
                    "balanza_nombre": "B",
                    "tercero_nombre": "X",
                    "peso_entrada_vehiculo": "50000",
                },
            )
        ).json()
        boleto = created["boleto"]
        r = await client.get(f"/api/v1/weighing/{boleto}/pdf")
        assert r.status_code == 200
        assert r.headers["content-type"].startswith("application/pdf")

    async def test_404_boleto_inexistente(self, client):
        r = await client.get(f"/api/v1/weighing/boleto/{uuid.uuid4()}")
        assert r.status_code == 404

    async def test_list_con_filtro_estado(self, client):
        await client.post(
            "/api/v1/weighing/create",
            json={
                "id_vehiculo": "FIL-01",
                "transporte_nombre": "T",
                "conductor_nombre": "C",
                "producto_nombre": "P",
                "almacen_nombre": "A",
                "balanza_nombre": "B",
                "tercero_nombre": "X",
                "peso_entrada_vehiculo": "50000",
            },
        )
        r = await client.get("/api/v1/weighing/list", params={"estado": "PENDIENTE"})
        assert r.status_code == 200
        assert all(p["estado_boleto"] == "PENDIENTE" for p in r.json())


class TestAuthEndpoints:
    async def test_register_crea_admin(self, app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://t") as ac:
            resp = await ac.post(
                "/api/v1/auth/register",
                json={
                    "empresa_nombre": "Empresa Nueva",
                    "empresa_rif": f"J-{uuid.uuid4().hex[:8]}",
                    "licencia_key": "LIC-DEMO-001",
                    "usuario_nombre": "Dueño",
                    "email": f"user{uuid.uuid4().hex[:6]}@test.demo",
                    "password": "secret123",
                },
            )
        assert resp.status_code == 201, resp.text
        body = resp.json()
        assert body["access_token"]
        assert body["user"]["rol"] == "ADMIN"

    async def test_licencia_empresa_snapshot(self, app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://t") as ac:
            resp = await ac.get("/api/v1/auth/license")
        assert resp.status_code == 200
        payload = resp.json()
        assert payload["valid"] is True
        assert payload["tier"] == "CENTRAL"
        assert payload["status"] == "ACTIVE"
        assert "registros_actuales" in payload

    async def test_login_credenciales_invalidas(self, app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://t") as ac:
            r = await ac.post(
                "/api/v1/auth/login",
                json={"email": "nobody@test.demo", "password": "wrong"},
            )
        assert r.status_code == 401


class TestDispositivosEndpoints:
    """Módulo de dispositivos: configuración y prueba de conexión de balanzas."""

    async def _crear_balanza(self, client, descripcion="B1", **extra):
        r = await client.post("/api/v1/balanzas", json={"descripcion": descripcion, **extra})
        assert r.status_code == 200, r.text
        return r.json()

    async def test_crear_balanza_con_hardware(self, client):
        body = await self._crear_balanza(
            client, ip_address="127.0.0.1", puerto_tcp=5555, protocolo="tcp"
        )
        assert body["ip_address"] == "127.0.0.1"
        assert body["puerto_tcp"] == 5555
        assert body["protocolo"] == "tcp"
        assert body["activo"] is True

    async def test_probar_sin_hardware_400(self, client):
        body = await self._crear_balanza(client)
        r = await client.post(f"/api/v1/balanzas/{body['id_balanza']}/probar")
        assert r.status_code == 400
        assert "hardware" in r.json()["detail"]

    async def test_probar_no_encontrada_404(self, client):
        r = await client.post(f"/api/v1/balanzas/{uuid.uuid4()}/probar")
        assert r.status_code == 404

    async def test_probar_conectado(self, client, monkeypatch):
        body = await self._crear_balanza(
            client, ip_address="192.168.0.50", puerto_tcp=5555, protocolo="tcp"
        )
        monkeypatch.setattr(
            scale_session_module,
            "get_scale_hal",
            lambda balanza: FakeHAL(12345.5, True),
        )
        r = await client.post(f"/api/v1/balanzas/{body['id_balanza']}/probar")
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["conectado"] is True
        assert data["peso_kg"] == 12345.5
        assert data["estable"] is True
        assert data["hardware"] == "tcp"
        assert data["protocolo"] == "tcp"

    async def test_probar_desconectado(self, client, monkeypatch):
        body = await self._crear_balanza(
            client, ip_address="192.168.0.99", puerto_tcp=5555, protocolo="tcp"
        )
        monkeypatch.setattr(
            scale_session_module,
            "get_scale_hal",
            lambda balanza: FakeHAL(None, False),
        )
        r = await client.post(f"/api/v1/balanzas/{body['id_balanza']}/probar")
        assert r.status_code == 200
        data = r.json()
        assert data["conectado"] is False
        assert data["detalle"]

    async def test_crear_balanza_simulada(self, client):
        sim = await self._crear_balanza(
            client,
            descripcion="Simulada",
            is_simulada=True,
            ip_address="127.0.0.1",
            puerto_tcp=5555,
            protocolo="tcp",
        )
        assert sim["is_simulada"] is True
        fisica = await self._crear_balanza(client, descripcion="Física")
        assert fisica["is_simulada"] is False

    async def test_descubrir_omite_registradas(self, client, monkeypatch):
        class FakeTcp:  # noqa: D106
            def __init__(self, host: str, port: int):
                self.host = host
                self.port = port

            async def read_weight(self) -> float:
                return 100.0

        monkeypatch.setattr(inventario_module, "TcpScaleHAL", FakeTcp)
        await self._crear_balanza(client, ip_address="127.0.0.1", puerto_tcp=5555, protocolo="tcp")
        r = await client.get("/api/v1/balanzas/descubrir")
        assert r.status_code == 200, r.text
        assert isinstance(r.json(), list)
        assert not any(d["protocolo"] == "tcp" and d["ip_address"] == "127.0.0.1" for d in r.json())

    async def test_descubrir_tcp_disponible(self, client, monkeypatch):
        class FakeTcp:  # noqa: D106
            def __init__(self, host: str, port: int):
                self.host = host
                self.port = port

            async def read_weight(self) -> float:
                return 321.5

        monkeypatch.setattr(inventario_module, "TcpScaleHAL", FakeTcp)
        r = await client.get("/api/v1/balanzas/descubrir")
        assert r.status_code == 200, r.text
        assert any(
            d["ip_address"] == "127.0.0.1" and d["puerto_tcp"] == 5555 and d["peso_kg"] == 321.5
            for d in r.json()
        )

    async def test_catalogo_sync_incluye_hardware(self, client):
        await self._crear_balanza(client, ip_address="10.0.0.7", puerto_tcp=5556, protocolo="tcp")
        r = await client.get("/api/v1/catalogo/sync")
        assert r.status_code == 200
        balanzas = r.json()["balanzas"]
        assert any(b["ip_address"] == "10.0.0.7" and b["puerto_tcp"] == 5556 for b in balanzas)
