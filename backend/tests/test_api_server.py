"""Tests de la API del SERVIDOR (APP_ROLE=server).

Verifican el flujo central de cuenta/licencia contra una DB PostgreSQL
dedicada (balansoft_ws_server_test): registro de cuenta, login global con
dispositivo, listado/alta de licencias, refresh, panel del proveedor y
recepción de sync de una estación local.
"""

from __future__ import annotations

import os
import uuid
from collections.abc import AsyncGenerator
from datetime import datetime

import httpx
import pytest
import pytest_asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import NullPool

from app.api.v1.endpoints.servidor import router as server_router
from app.core.database import get_server_db
from app.core.security import hash_password
from app.models_server import ProveedorUsuario, ServerBase


def _url_para_bbdd(url: str, nombre: str) -> str:
    head, _, _ = url.rpartition("/")
    return f"{head}/{nombre}"


# DB de prueba del servidor (independiente de la DB local).
TEST_SERVER_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL_SERVER",
    _url_para_bbdd(os.environ.get("DATABASE_URL", "postgresql+asyncpg://sqlman:7767@localhost:5432/balansoft_ws"), "balansoft_ws_server_test"),
)


@pytest_asyncio.fixture(scope="module")
async def _server_engine():
    engine = create_async_engine(TEST_SERVER_DATABASE_URL, poolclass=NullPool)
    async with engine.begin() as conn:
        await conn.run_sync(ServerBase.metadata.drop_all)
        await conn.run_sync(ServerBase.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(ServerBase.metadata.drop_all)
    await engine.dispose()


@pytest_asyncio.fixture
async def server_db(_server_engine) -> AsyncGenerator[AsyncSession, None]:
    session_factory = async_sessionmaker(
        bind=_server_engine, class_=AsyncSession, expire_on_commit=False
    )
    async with session_factory() as session:
        yield session
    tabla = ", ".join(t.name for t in reversed(ServerBase.metadata.sorted_tables))
    async with _server_engine.begin() as conn:
        await conn.execute(text(f"TRUNCATE TABLE {tabla} RESTART IDENTITY CASCADE"))


@pytest.mark.asyncio
async def test_registro_login_licencias_y_sync(
    _server_engine,
) -> None:
    """Flujo completo: registro → login (dispositivo) → licencias → sync."""
    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        rif = f"J-{uuid.uuid4().hex[:10]}".upper()
        email = f"server-{uuid.uuid4().hex[:8]}@test.com"
        key = f"BWS-{uuid.uuid4().hex[:12].upper()}"

        r = await ac.post(
            "/api/v1/auth/register",
            json={
                "empresa_nombre": "Servidor Test SA",
                "empresa_rif": rif,
                "email_admin": email,
                "usuario_nombre": "Admin",
                "password": "pass123456",
                "licencia_key": key,
                "licencia_tier": "CENTRAL",
                "fecha_expira": "2027-12-31T00:00:00Z",
                "max_equipos": 2,
            },
        )
        assert r.status_code == 201, r.text
        data = r.json()
        assert data["cuenta"]["rif_nit"] == rif
        assert data["licencia"]["licencia_tier"] == "CENTRAL"

        r = await ac.post(
            "/api/v1/auth/login",
            json={
                "email": email,
                "password": "pass123456",
                "hardware_id": "HW-TEST-001",
                "nombre_equipo": "Estacion-A",
            },
        )
        assert r.status_code == 200, r.text
        login = r.json()
        assert login["dispositivo"]["hardware_id"] == "HW-TEST-001"

        r = await ac.get(
            "/api/v1/licencias", headers={"Authorization": f"Bearer {login['access_token']}"}
        )
        assert r.status_code == 200
        assert len(r.json()) == 1

        r = await ac.post(
            "/api/v1/sync/server",
            headers={"Authorization": f"Bearer {login['access_token']}"},
            json={
                "tipo": "push",
                "items": [
                    {
                        "entidad": "pesaje",
                        "operacion": "create",
                        "entidad_id": "BOL-1",
                        "payload": {"neto": 100.5},
                    }
                ],
            },
        )
        assert r.status_code == 200, r.text
        assert r.json()["recibidos"] == 1


@pytest.mark.asyncio
async def test_rif_duplicado_rechazado(_server_engine) -> None:
    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    payload = {
        "empresa_nombre": "Duplicada SA",
        "empresa_rif": "J-999999999",
        "email_admin": f"dup-{uuid.uuid4().hex[:8]}@test.com",
        "usuario_nombre": "Admin",
        "password": "pass123456",
        "licencia_key": f"BWS-{uuid.uuid4().hex[:12].upper()}",
        "licencia_tier": "DEMO",
        "fecha_expira": "2027-12-31T00:00:00Z",
    }
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r1 = await ac.post("/api/v1/auth/register", json=payload)
        assert r1.status_code == 201
        r2 = await ac.post("/api/v1/auth/register", json=payload)
        assert r2.status_code == 400
        assert "RIF" in r2.json()["detail"]


@pytest.mark.asyncio
async def test_login_credencial_invalida(_server_engine) -> None:
    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": "noexiste@test.com", "password": "x", "hardware_id": "HW-1"},
        )
        assert r.status_code == 401


@pytest.mark.asyncio
async def test_licencia_suspendida_bloquea_login(_server_engine, server_db) -> None:
    from sqlalchemy import select

    from app.models_server import Licencia

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"sus-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/auth/register",
            json={
                "empresa_nombre": "Susp SA",
                "empresa_rif": rif,
                "email_admin": email,
                "usuario_nombre": "Admin",
                "password": "pass123456",
                "licencia_key": f"BWS-{uuid.uuid4().hex[:12].upper()}",
                "licencia_tier": "CENTRAL",
                "fecha_expira": "2027-12-31T00:00:00Z",
            },
        )
        assert r.status_code == 201
        key = r.json()["licencia"]["licencia_key"]

        # El fixture server_db comparte la misma BD: consultar y suspender.
        lic = (
            await server_db.execute(
                select(Licencia).where(Licencia.licencia_key == key)
            )
        ).scalar_one()
        lic.licencia_status = "SUSPENDIDA"
        await server_db.commit()

        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "pass123456", "hardware_id": "HW-SUSP"},
        )
        assert r.status_code == 403


@pytest.mark.asyncio
async def test_panel_proveedor_login_y_cuentas(_server_engine, server_db) -> None:

    from app.models_server import Cuenta

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    # Cuenta existente visible para el panel.
    cuenta = Cuenta(
        rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        nombre_fiscal="Panel Test SA",
        email_admin=f"panel-{uuid.uuid4().hex[:8]}@test.com",
        activa=True,
    )
    server_db.add(cuenta)
    prov = ProveedorUsuario(
        email=f"prov-{uuid.uuid4().hex[:8]}@test.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SOPORTE",
    )
    server_db.add(prov)
    await server_db.commit()
    await server_db.refresh(prov)

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        assert r.status_code == 200, r.text
        token = r.json()["access_token"]

        r = await ac.get(
            "/api/v1/panel/cuentas", headers={"Authorization": f"Bearer {token}"}
        )
        assert r.status_code == 200
        rifs = [c["rif_nit"] for c in r.json()]
        assert cuenta.rif_nit in rifs


@pytest.mark.asyncio
async def test_sync_sin_auth_rechazado(_server_engine) -> None:
    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/sync/server",
            json={"tipo": "push", "items": []},
        )
        assert r.status_code == 401


@pytest.mark.asyncio
async def test_sync_usuarios_crea_credenciales(_server_engine, server_db) -> None:
    """Una estación sincroniza usuarios → se crean credenciales globales."""
    from sqlalchemy import select

    from app.models_server import Credencial

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"sy-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/auth/register",
            json={
                "empresa_nombre": "Sync Users SA",
                "empresa_rif": rif,
                "email_admin": email,
                "usuario_nombre": "Admin",
                "password": "pass123456",
                "licencia_key": f"BWS-{uuid.uuid4().hex[:12].upper()}",
                "licencia_tier": "CENTRAL",
                "fecha_expira": "2027-12-31T00:00:00Z",
            },
        )
        assert r.status_code == 201
        token = r.json()["access_token"]

        nuevo = f"op-{uuid.uuid4().hex[:8]}@test.com"
        r = await ac.post(
            "/api/v1/sync/users",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "items": [
                    {
                        "email": nuevo,
                        "nombre": "Operador Sinc",
                        "rol_global": "OPERADOR",
                        "activo": True,
                        "operacion": "upsert",
                    }
                ]
            },
        )
        assert r.status_code == 200, r.text
        assert r.json()["procesados"] == 1
        assert r.json()["errores"] == 0

        cred = (
            await server_db.execute(
                select(Credencial).where(Credencial.email == nuevo)
            )
        ).scalar_one_or_none()
        assert cred is not None
        assert cred.rol_global == "OPERADOR"

        # Upsert nuevamente: no debe duplicar, debe actualizar el rol.
        server_db.expire_all()
        r = await ac.post(
            "/api/v1/sync/users",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "items": [
                    {
                        "email": nuevo,
                        "nombre": "Operador Sinc",
                        "rol_global": "AUDITOR",
                        "activo": True,
                        "operacion": "upsert",
                    }
                ]
            },
        )
        assert r.status_code == 200
        credetado = (
            await server_db.execute(
                select(Credencial).where(Credencial.email == nuevo)
            )
        ).scalar_one()
        assert credetado.rol_global == "AUDITOR"


@pytest.mark.asyncio
async def test_panel_verificar_licencia_contra_lm(
    _server_engine, server_db, monkeypatch
) -> None:
    """El panel verifica la licencia en el LM local (mockeado).

    Aptitud según la política del LM: producto WS + cliente asociado +
    distribuidor asignado. AVAILABLE con esos datos => válida (se activará
    en el primer uso de la estación).
    """
    from app.api.v1.endpoints import servidor as servidor_mod
    from app.core.config import settings
    from app.core.license_client import LicenseError

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    prov = ProveedorUsuario(
        email=f"prov-{uuid.uuid4().hex[:8]}@lm.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SOPORTE",
    )
    server_db.add(prov)
    await server_db.commit()
    await server_db.refresh(prov)

    apta: dict = {
        "exists": True,
        "status": "AVAILABLE",
        "tier": "CENTRAL",
        "plan_type": "basic",
        "product_code": settings.license_product_code,
        "has_client": True,
        "client_name": "Cliente Ejemplo C.A.",
        "distributor_id": "d1a2b3c4-0000-0000-0000-000000000001",
        "distributor_name": "Distribuidora Ejemplo",
        "requires_activation": True,
    }

    class _FakeLm:
        def check(self, license_key: str) -> dict:
            if license_key == "BWS-NOEXISTE":
                raise LicenseError("Check LM fallido (404)")
            return apta

    monkeypatch.setattr(servidor_mod, "get_license_client", lambda: _FakeLm())

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        assert r.status_code == 200
        token = r.json()["access_token"]

        r = await ac.post(
            "/api/v1/panel/verificar-licencia",
            headers={"Authorization": f"Bearer {token}"},
            json={"licencia_key": "BWS-VALIDA-0000"},
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["valida"] is True
        assert body["status"] == "AVAILABLE"
        assert body["tier"] == "CENTRAL"
        assert "activará" in body["message"]

        r = await ac.post(
            "/api/v1/panel/verificar-licencia",
            headers={"Authorization": f"Bearer {token}"},
            json={"licencia_key": "BWS-NOEXISTE"},
        )
        assert r.status_code == 200, r.text
        assert r.json()["valida"] is False


@pytest.mark.asyncio
async def test_panel_verificar_licencia_requisitos_lm(
    _server_engine, server_db, monkeypatch
) -> None:
    """Solo son válidas las licencias WS con cliente y distribuidor (política LM)."""
    from app.api.v1.endpoints import servidor as servidor_mod

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    prov = ProveedorUsuario(
        email=f"prov-{uuid.uuid4().hex[:8]}@requisitos.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SUPERADMIN",
    )
    server_db.add(prov)
    await server_db.commit()

    casos = {
        "BWS-OTRO-PROD": {
            "exists": True,
            "status": "AVAILABLE",
            "product_code": "OTRO",
            "has_client": True,
            "distributor_id": "d-otro",
        },
        "BWS-SIN-CLIENTE": {
            "exists": True,
            "status": "AVAILABLE",
            "product_code": "BWS",
            "has_client": False,
        },
        "BWS-SIN-DISTRIB": {
            "exists": True,
            "status": "AVAILABLE",
            "product_code": "BWS",
            "has_client": True,
            "client_name": "Cliente X",
        },
        "BWS-YA-ACTIVA": {
            "exists": True,
            "status": "ACTIVE",
            "product_code": "BWS",
            "has_client": True,
            "client_name": "Otro Cliente",
            "distributor_id": "d-abc",
            "requires_activation": False,
        },
    }

    class _FakeLm:
        def check(self, license_key: str) -> dict:
            return casos[license_key]

    monkeypatch.setattr(servidor_mod, "get_license_client", lambda: _FakeLm())

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        token = r.json()["access_token"]

        for clave, _datos in casos.items():
            r = await ac.post(
                "/api/v1/panel/verificar-licencia",
                headers={"Authorization": f"Bearer {token}"},
                json={"licencia_key": clave},
            )
            assert r.status_code == 200, r.text
            assert r.json()["valida"] is False, f"{clave} no debía ser válida"
            assert r.json()["message"]


@pytest.mark.asyncio
async def test_panel_verificar_licencia_sin_auth(_server_engine) -> None:
    """Sin token de proveedor no se puede verificar licencias."""
    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/verificar-licencia",
            json={"licencia_key": "BWS-LM-0001"},
        )
        assert r.status_code == 401


@pytest.mark.asyncio
async def test_panel_verificar_licencia_estado_invalido(
    _server_engine, server_db, monkeypatch
) -> None:
    """Licencia SUSPENDIDA en el LM -> valida=False."""
    from app.api.v1.endpoints import servidor as servidor_mod

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    prov = ProveedorUsuario(
        email=f"prov-{uuid.uuid4().hex[:8]}@susp.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SUPERADMIN",
    )
    server_db.add(prov)
    await server_db.commit()

    class _LmSusp:
        def check(self, license_key: str) -> dict:
            return {
                "exists": True,
                "status": "SUSPENDIDA",
                "product_code": "BWS",
                "has_client": True,
                "client_name": "Cliente X",
                "distributor_id": "d-abc",
                "requires_activation": False,
            }

    monkeypatch.setattr(servidor_mod, "get_license_client", lambda: _LmSusp())

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        token = r.json()["access_token"]
        r = await ac.post(
            "/api/v1/panel/verificar-licencia",
            headers={"Authorization": f"Bearer {token}"},
            json={"licencia_key": "BWS-SUSP-0000"},
        )
        assert r.status_code == 200, r.text
        assert r.json()["valida"] is False


@pytest.mark.asyncio
async def test_panel_cuenta_detalle(_server_engine, server_db) -> None:
    """Detalle de cuenta: licencias, credenciales y dispositivos."""
    from app.models_server import Credencial, Cuenta, Dispositivo, Licencia

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    cuenta = Cuenta(
        rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        nombre_fiscal="Panmal Test SA",
        email_admin=f"det-{uuid.uuid4().hex[:8]}@test.com",
        activa=True,
    )
    server_db.add(cuenta)
    await server_db.flush()
    server_db.add(
        Licencia(
            id_cuenta=cuenta.id_cuenta,
            licencia_key=f"BWS-DET-{uuid.uuid4().hex[:12].upper()}",
            licencia_tier="CENTRAL",
            licencia_status="ACTIVA",
            fecha_expira=datetime(2030, 1, 1),
        )
    )
    server_db.add(
        Credencial(
            id_cuenta=cuenta.id_cuenta,
            email=f"op-{uuid.uuid4().hex[:8]}@test.com",
            password_hash=hash_password("op123456"),
            rol_global="OPERADOR",
        )
    )
    server_db.add(
        Dispositivo(
            id_cuenta=cuenta.id_cuenta,
            hardware_id="HW-DET-1",
            rol_dispositivo="LOCAL",
        )
    )
    prov = ProveedorUsuario(
        email=f"prov-{uuid.uuid4().hex[:8]}@det.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SOPORTE",
    )
    server_db.add(prov)
    await server_db.commit()

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        token = r.json()["access_token"]
        r = await ac.get(
            f"/api/v1/panel/cuentas/{cuenta.id_cuenta}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["cuenta"]["rif_nit"] == cuenta.rif_nit
        assert len(body["licencias"]) == 1
        assert len(body["credenciales"]) == 1
        assert body["credenciales"][0]["rol_global"] == "OPERADOR"
        assert body["total_dispositivos"] == 1


@pytest.mark.asyncio
async def test_panel_cuenta_actualizar(_server_engine, server_db) -> None:
    """El panel puede editar la ficha del cliente y su estatus (cuenta/licencia)."""
    from app.models_server import Credencial, Cuenta, Licencia

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    cuenta = Cuenta(
        rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        nombre_fiscal="Cliente Editable SA",
        email_admin=f"edit-{uuid.uuid4().hex[:8]}@test.com",
        activa=True,
    )
    server_db.add(cuenta)
    await server_db.flush()
    server_db.add(
        Licencia(
            id_cuenta=cuenta.id_cuenta,
            licencia_key=f"BWS-EDIT-{uuid.uuid4().hex[:12].upper()}",
            licencia_tier="CENTRAL",
            licencia_status="ACTIVA",
            fecha_expira=datetime(2030, 1, 1),
        )
    )
    # Como en el alta real: la credencial ADMIN comparte email con la cuenta
    server_db.add(
        Credencial(
            id_cuenta=cuenta.id_cuenta,
            email=cuenta.email_admin,
            password_hash=hash_password("admin123456"),
            rol_global="ADMIN",
        )
    )
    prov = ProveedorUsuario(
        email=f"prov-{uuid.uuid4().hex[:8]}@edit.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SUPERADMIN",
    )
    server_db.add(prov)
    await server_db.commit()

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        token = r.json()["access_token"]

        r = await ac.put(
            f"/api/v1/panel/cuentas/{cuenta.id_cuenta}",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "nombre_comercial": "Editable Comercial C.A.",
                "telefono": "+58 412 555 1234",
                "direccion": "Av. Principal, Edif. Central, Piso 2",
                "activa": False,
                "licencia_status": "SUSPENDIDA",
            },
        )
        assert r.status_code == 200, r.text
        body = r.json()
        cuenta_out = body["cuenta"]
        assert cuenta_out["nombre_comercial"] == "Editable Comercial C.A."
        assert cuenta_out["telefono"] == "+58 412 555 1234"
        assert cuenta_out["direccion"] == "Av. Principal, Edif. Central, Piso 2"
        assert cuenta_out["activa"] is False
        assert body["licencias"][0]["licencia_status"] == "SUSPENDIDA"

        # La edición persiste en la DB
        await server_db.refresh(cuenta)
        assert cuenta.activa is False
        assert cuenta.direccion == "Av. Principal, Edif. Central, Piso 2"

        # Estatus de licencia revertido a ACTIVA
        r = await ac.put(
            f"/api/v1/panel/cuentas/{cuenta.id_cuenta}",
            headers={"Authorization": f"Bearer {token}"},
            json={"licencia_status": "ACTIVA", "activa": True},
        )
        assert r.status_code == 200, r.text
        assert r.json()["licencias"][0]["licencia_status"] == "ACTIVA"
        assert r.json()["cuenta"]["activa"] is True

        # Guardar manteniendo el email/admin y el RIF actuales no debe fallar
        r = await ac.put(
            f"/api/v1/panel/cuentas/{cuenta.id_cuenta}",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "email_admin": cuenta.email_admin,
                "rif_nit": cuenta.rif_nit,
            },
        )
        assert r.status_code == 200, r.text


@pytest.mark.asyncio
async def test_panel_cuenta_actualizar_unicidad(_server_engine, server_db) -> None:
    """No se puede duplicar RIF/email de otra cuenta al editar."""
    from app.models_server import Cuenta

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    base = f"dup-{uuid.uuid4().hex[:8]}"
    c1 = Cuenta(rif_nit=f"J-1{uuid.uuid4().hex[:10]}".upper(),
                nombre_fiscal="Duplicada 1",
                email_admin=f"{base}1@test.com", activa=True)
    c2 = Cuenta(rif_nit=f"J-2{uuid.uuid4().hex[:10]}".upper(),
                nombre_fiscal="Duplicada 2",
                email_admin=f"{base}2@test.com", activa=True)
    server_db.add_all([c1, c2])
    await server_db.commit()

    prov = ProveedorUsuario(
        email=f"{base}p@test.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SUPERADMIN",
    )
    server_db.add(prov)
    await server_db.commit()

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        token = r.json()["access_token"]

        r = await ac.put(
            f"/api/v1/panel/cuentas/{c1.id_cuenta}",
            headers={"Authorization": f"Bearer {token}"},
            json={"rif_nit": c2.rif_nit},
        )
        assert r.status_code == 400, r.text
        assert "EIR/NIT" in r.text or "RIF/NIT" in r.text

        r = await ac.put(
            f"/api/v1/panel/cuentas/{c1.id_cuenta}",
            headers={"Authorization": f"Bearer {token}"},
            json={"email_admin": c2.email_admin},
        )
        assert r.status_code == 400, r.text


def _server_app(engine):
    """Aplicación FastAPI con solo los routers del servidor y DB sobreescrita."""
    from fastapi import FastAPI

    application = FastAPI()

    async def _get_server_db() -> AsyncGenerator[AsyncSession, None]:
        session_factory = async_sessionmaker(
            bind=engine, class_=AsyncSession, expire_on_commit=False
        )
        async with session_factory() as session:
            yield session

    application.dependency_overrides[get_server_db] = _get_server_db
    application.include_router(server_router)
    return application