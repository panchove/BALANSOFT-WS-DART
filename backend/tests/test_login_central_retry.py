"""Tests del timeout y reintento de `POST /api/v1/auth/login-central`.

Contrato (docs/MANEJO_DB.md §11):

- Timeout del cliente HTTP al central configurable con ``CENTRAL_TIMEOUT``
  (default 30 s); antes estaba hardcodeado en 10 s y el arranque en frío
  (DNS + TLS + cold start de Cloudflare) producía ConnectTimeout intermitente.
- UN reintento único, SOLO ante ``ConnectTimeout``/``ReadTimeout``. Ante
  ``ConnectError``/DNS u otros ``TransportError`` no se reintenta (1 llamada
  y 502). Las respuestas HTTP del central (401/400/403) tampoco reintentan.
- El timeout efectivo se expone en ``/api/v1/health`` y
  ``/api/v1/environment`` (clave ``central``) para diagnóstico desde el
  instalador sin leer el .env.

El central se simula parcheando ``httpx.AsyncClient.post`` a nivel de clase
(mismo patrón que ``test_activacion_instalacion.py``).
"""

from __future__ import annotations

import uuid

import httpx
import pytest
import pytest_asyncio
from fastapi import FastAPI
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.testclient import TestClient

from app.api.v1.endpoints import API_ROUTERS
from app.api.v1.endpoints import auth as auth_module
from app.core.config import Settings, settings
from app.core.database import get_db
from app.main import app as app_real

URL_CENTRAL = "http://central.test"


def _central_ok() -> dict:
    """Respuesta 200 del central (mismo esqueleto que test_activacion_instalacion)."""
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
            "hardware_id": "HW-LOCAL-1",
        },
        "dispositivo": {
            "id_dispositivo": str(uuid.uuid4()),
            "hardware_id": "HW-LOCAL-1",
            "rol": "SERVIDOR_LOCAL",
            "activo": True,
            "puede_ser_servidor": True,
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
    # La espera real (2 s) haría lenta la suite: se parchea en los tests de
    # retry; el contrato 1-2 s lo fija test_espera_reintento_en_rango_1_2s.
    monkeypatch.setattr(auth_module, "_ESPERA_REINTENTO_CENTRAL", 0.0)
    return application


def _parchear_central(monkeypatch, comportamientos: list) -> dict:
    """Intercepta las llamadas al central con una secuencia preprogramada.

    ``comportamientos``: lista de ``Exception`` (se lanza) o ``(status, cuerpo)``
    (se devuelve). El último elemento se repite si hay más llamadas. Devuelve
    el contador de llamadas y los timeouts efectivos observados.
    """
    original = httpx.AsyncClient.post
    contador = {"n": 0}
    tiempos: list[float] = []

    class _RespuestaDummy:
        headers: dict[str, str] = {}

        def __init__(self, status: int = 200, cuerpo: dict | None = None):
            self.status_code = status
            self._cuerpo = cuerpo or {}

        def json(self):
            return self._cuerpo

    async def _post(self, url, **kwargs):
        if "central.test" not in str(url):
            return await original(self, url, **kwargs)
        # Timeout efectivo del cliente con el que se hace la llamada al central.
        t = getattr(self, "timeout", None)
        tiempos.append(float(getattr(t, "read", t) or 0.0))
        comportamiento = comportamientos[min(contador["n"], len(comportamientos) - 1)]
        contador["n"] += 1
        if isinstance(comportamiento, Exception):
            raise comportamiento
        status, cuerpo = comportamiento
        return _RespuestaDummy(status, cuerpo)

    monkeypatch.setattr(httpx.AsyncClient, "post", _post)
    return {"contador": contador, "tiempos": tiempos}


async def _llamar_login_central(app) -> httpx.Response:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        return await ac.post(
            "/api/v1/auth/login-central",
            json={
                "email": "admin@cliente.com",
                "password": "pass123456",
                "server_url": URL_CENTRAL,
            },
        )


# ---------------------------------------------------------------------------
# Reintento ante timeout (la condición NO puede ser «cualquier TransportError»)
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_reintenta_una_vez_tras_connect_timeout(app, db, monkeypatch) -> None:
    """1ª llamada con ConnectTimeout → reintento → 200, con 2 llamadas."""
    spy = _parchear_central(
        monkeypatch,
        [httpx.ConnectTimeout("timeout"), (200, _central_ok())],
    )

    r = await _llamar_login_central(app)
    assert r.status_code == 200, r.text
    assert spy["contador"]["n"] == 2


@pytest.mark.asyncio
async def test_reintenta_una_vez_tras_read_timeout(app, db, monkeypatch) -> None:
    """Igual que connect pero con ReadTimeout (también reintentable)."""
    spy = _parchear_central(
        monkeypatch,
        [httpx.ReadTimeout("timeout"), (200, _central_ok())],
    )

    r = await _llamar_login_central(app)
    assert r.status_code == 200, r.text
    assert spy["contador"]["n"] == 2


@pytest.mark.asyncio
async def test_timeout_agotado_devuelve_502_y_solo_dos_intentos(
    app, db, monkeypatch
) -> None:
    """Timeout siempre → 502 tras EXACTAMENTE 2 intentos (ni 1 ni 3)."""
    spy = _parchear_central(monkeypatch, [httpx.ConnectTimeout("timeout")])

    r = await _llamar_login_central(app)
    assert r.status_code == 502, r.text
    assert spy["contador"]["n"] == 2


@pytest.mark.asyncio
async def test_connect_error_no_se_reintenta(app, db, monkeypatch) -> None:
    """ConnectError (central caído/DNS/proxy) NO reintentable: 1 llamada."""
    spy = _parchear_central(monkeypatch, [httpx.ConnectError("rechazado")])

    r = await _llamar_login_central(app)
    assert r.status_code == 502, r.text
    assert spy["contador"]["n"] == 1


@pytest.mark.asyncio
async def test_respuesta_401_del_central_no_se_reintenta(app, db, monkeypatch) -> None:
    """401 del central se devuelve tal cual y con UNA sola llamada upstream."""
    spy = _parchear_central(monkeypatch, [(401, {"detail": "Credenciales inválidas"})])

    r = await _llamar_login_central(app)
    assert r.status_code == 401, r.text
    assert spy["contador"]["n"] == 1


# ---------------------------------------------------------------------------
# Timeout efectivo configurable (CENTRAL_TIMEOUT)
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_timeout_efectivo_usa_settings_central_timeout(
    app, db, monkeypatch
) -> None:
    """El cliente se construye con settings.central_timeout (rojo si hardcodea 10)."""
    monkeypatch.setattr(settings, "central_timeout", 7)
    spy = _parchear_central(monkeypatch, [(200, _central_ok())])

    r = await _llamar_login_central(app)
    assert r.status_code == 200, r.text
    assert spy["tiempos"], "la llamada al central debe registrar su timeout"
    assert spy["tiempos"][0] == 7.0


def test_settings_central_timeout_por_defecto_y_env(monkeypatch) -> None:
    """Default 30 y la env var CENTRAL_TIMEOUT (nombre exacto) lo pisa.

    El default se lee del modelo (inmune a un .env local que lo defina) y la
    env var tiene prioridad sobre el archivo .env en pydantic-settings.
    """
    assert Settings.model_fields["central_timeout"].default == 30
    monkeypatch.setenv("CENTRAL_TIMEOUT", "45")
    assert Settings().central_timeout == 45


def test_espera_reintento_en_rango_1_2s() -> None:
    """Contrato: la espera entre intentos está en 1-2 s (los tests de retry la
    parchean a 0 para no lentificar la suite, aquí se fija el valor real)."""
    assert 1.0 <= auth_module._ESPERA_REINTENTO_CENTRAL <= 2.0
    assert auth_module._MAX_INTENTOS_CENTRAL == 2


# ---------------------------------------------------------------------------
# Diagnóstico: timeout efectivo expuesto sin leer el .env
# ---------------------------------------------------------------------------
@pytest.fixture
def app_diag():
    """App global de app.main con overrides limpios (patrón test_sqlserver_degradado)."""
    original = dict(app_real.dependency_overrides)
    app_real.dependency_overrides.clear()
    yield app_real
    app_real.dependency_overrides.clear()
    app_real.dependency_overrides.update(original)


def test_health_expone_central_timeout(app_diag) -> None:
    r = TestClient(app_diag).get("/api/v1/health")
    assert r.status_code == 200
    assert r.json()["central"] == {
        "timeout_s": settings.central_timeout,
        "max_intentos": 2,
    }


def test_environment_expone_central_timeout(app_diag) -> None:
    r = TestClient(app_diag).get("/api/v1/environment")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["central"] == {
        "timeout_s": settings.central_timeout,
        "max_intentos": 2,
    }
    # Contrato existente intacto (app Flutter): ninguna clave renombrada.
    assert set(body) >= {"estado", "motor", "sistema", "api", "postgres", "hardware"}
