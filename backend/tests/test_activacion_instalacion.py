"""Tests de la activación/instalación en el servidor local.

`POST /api/v1/auth/login-central` es el paso 3 del modo SERVIDOR: valida las
credenciales contra el servidor central y hace el espejo local (empresa +
usuario admin + identidad). Aquí se cubren:

- El bloqueo cuando la máquina NO es titular de la licencia y pide SERVIDOR.
- El espejo de los datos de la cuenta central (prefill del formulario de
  empresa del paso 4).
- El reflejo del rol del dispositivo en `identidad_local`.

El central se simula parcheando `httpx.AsyncClient.post` (mismo patrón que el
resto de tests del login central).
"""

from __future__ import annotations

import uuid

import httpx
import pytest
import pytest_asyncio
from fastapi import FastAPI
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.endpoints import API_ROUTERS
from app.api.v1.endpoints import auth as auth_module
from app.core.database import get_db
from app.models import Empresa, IdentidadLocal


def _central(
    *,
    rol_dispositivo: str = "SERVIDOR_LOCAL",
    hardware_titular: str = "HW-OTRA-PC",
    cuenta_extra: dict | None = None,
) -> dict:
    """Respuesta del servidor central para `POST /api/v1/auth/login`."""
    cuenta = {
        "id_cuenta": str(uuid.uuid4()),
        "rif_nit": "J-99999999-9",
        "nombre_fiscal": "Cliente del Central SA",
        "nombre_comercial": "Cliente del Central",
        "email_admin": "admin@cliente.com",
        "telefono": "0212-1234567",
        "direccion": "Av. Principal, Caracas",
        "activa": True,
    }
    cuenta.update(cuenta_extra or {})
    return {
        "access_token": "tok-central",
        "refresh_token": "ref-central",
        "user": {
            "id_credencial": str(uuid.uuid4()),
            "id_cuenta": cuenta["id_cuenta"],
            "email": cuenta["email_admin"],
            "rol_global": "ADMIN",
        },
        "cuenta": cuenta,
        "licencia": {
            "licencia_key": "BWS-CENTRAL-TEST",
            "licencia_tier": "CENTRAL",
            "licencia_status": "ACTIVA",
            "fecha_expira": "2027-12-31T00:00:00Z",
            "max_usuarios": None,
            "max_equipos": None,
            "max_sesiones": None,
            "hardware_id": hardware_titular,
        },
        "dispositivo": {
            "id_dispositivo": str(uuid.uuid4()),
            "hardware_id": "HW-LOCAL-1",
            "rol": rol_dispositivo,
            "activo": True,
            "puede_ser_servidor": rol_dispositivo == "SERVIDOR_LOCAL",
        },
    }


@pytest_asyncio.fixture
async def app(db: AsyncSession, monkeypatch) -> FastAPI:
    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    monkeypatch.setattr(auth_module, "obtener_hardware_id", lambda: "HW-LOCAL-1")
    return application


def _parchear_central(monkeypatch, cuerpo: dict, status: int = 200) -> None:
    """Sustituye la llamada HTTP **al central** por una respuesta fija.

    Solo intercepta URLs del servidor central; cualquier otra petición (el
    propio cliente de test) sigue su curso normal.
    """
    original = httpx.AsyncClient.post

    class _RespuestaDummy:
        status_code = status
        headers: dict[str, str] = {}

        def json(self):
            return cuerpo

    async def _post(self, url, **kwargs):
        if "central.test" in str(url):
            return _RespuestaDummy()
        return await original(self, url, **kwargs)

    monkeypatch.setattr(httpx.AsyncClient, "post", _post)


@pytest.mark.asyncio
async def test_precarga_datos_de_empresa_del_central(app, db, monkeypatch) -> None:
    """Paso 3+4: al validar la cuenta, la empresa queda con los datos que ya
    tenía en el central (nombre, RIF, dirección, teléfono y email)."""
    central = _central()
    _parchear_central(monkeypatch, central)

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/auth/login-central",
            json={
                "email": "admin@cliente.com",
                "password": "pass123456",
                "server_url": "http://central.test",
            },
        )
    assert r.status_code == 200, r.text
    body = r.json()

    empresa = (await db.execute(select(Empresa))).scalar_one()
    assert empresa.rif_nit == "J-99999999-9"
    assert empresa.nombre_fiscal == "Cliente del Central SA"
    assert empresa.nombre_comercial == "Cliente del Central"
    assert empresa.direccion == "Av. Principal, Caracas"
    assert empresa.telefono == "0212-1234567"
    assert empresa.email == "admin@cliente.com"
    assert empresa.licencia_tier == "CENTRAL"

    # El cliente recibe todo lo necesario para pintar el formulario precargado.
    assert body["empresa"]["rif_nit"] == "J-99999999-9"
    assert body["empresa"]["direccion"] == "Av. Principal, Caracas"
    assert body["license"]["puede_ser_servidor"] is True
    assert body["license"]["dispositivo_rol"] == "SERVIDOR_LOCAL"
    assert body["license"]["id_cuenta"] == central["cuenta"]["id_cuenta"]


@pytest.mark.asyncio
async def test_maquina_no_titular_no_puede_instalarse_como_servidor(
    app, db, monkeypatch
) -> None:
    """Un equipo LOCAL que pide SERVIDOR recibe 403 y NO se crea empresa local:
    la instalación debe continuar por la ruta de trabajador."""
    _parchear_central(monkeypatch, _central(rol_dispositivo="LOCAL"))

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/auth/login-central",
            json={
                "email": "admin@cliente.com",
                "password": "pass123456",
                "server_url": "http://central.test",
                "modo_solicitado": "SERVIDOR",
            },
        )
    assert r.status_code == 403, r.text
    # El mensaje dice cuál equipo ES el titular, para que soporte pueda corregirlo
    # desde el panel sin adivinar.
    assert "titular" in r.json()["detail"].lower()
    assert "HW-OTRA-PC" in r.json()["detail"]
    assert (await db.execute(select(Empresa))).scalars().all() == []
    assert (await db.execute(select(IdentidadLocal))).scalars().all() == []


@pytest.mark.asyncio
async def test_maquina_titular_puede_instalarse_como_servidor(
    app, db, monkeypatch
) -> None:
    _parchear_central(monkeypatch, _central(rol_dispositivo="SERVIDOR_LOCAL"))

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/auth/login-central",
            json={
                "email": "admin@cliente.com",
                "password": "pass123456",
                "server_url": "http://central.test",
                "modo_solicitado": "SERVIDOR",
            },
        )
    assert r.status_code == 200, r.text

    identidad = (await db.execute(select(IdentidadLocal))).scalar_one()
    assert identidad.rol_dispositivo == "SERVIDOR_LOCAL"


@pytest.mark.asyncio
async def test_trabajador_no_es_bloqueado(app, db, monkeypatch) -> None:
    """Un equipo LOCAL que se instala como TRABAJADOR pasa la validación (el
    login normal del trabajador no va por el central de la licencia titular)."""
    _parchear_central(monkeypatch, _central(rol_dispositivo="LOCAL"))

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/auth/login-central",
            json={
                "email": "admin@cliente.com",
                "password": "pass123456",
                "server_url": "http://central.test",
                "modo_solicitado": "TRABAJADOR",
            },
        )
    assert r.status_code == 200, r.text

    identidad = (await db.execute(select(IdentidadLocal))).scalar_one()
    assert identidad.rol_dispositivo == "LOCAL"


@pytest.mark.asyncio
async def test_login_normal_sin_modo_solicitado_no_se_bloquea(
    app, db, monkeypatch
) -> None:
    """Regresión: el login de la app (sin modo) nunca debe quedar bloqueado
    aunque el equipo no sea el titular."""
    _parchear_central(monkeypatch, _central(rol_dispositivo="LOCAL"))

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/auth/login-central",
            json={
                "email": "admin@cliente.com",
                "password": "pass123456",
                "server_url": "http://central.test",
            },
        )
    assert r.status_code == 200, r.text
