"""Fixtures E2E (H2): stub del LM firmante con Ed25519 + app real por HTTP.

El stub (`scripts/lm_stub.py`) se levanta en un hilo de uvicorn con un par de
claves efímero; la **clave pública** se inyecta en ``LicenseClient`` para que la
verificación de firma sea real (no un bypass). La app se monta con los routers
reales y solo se sobreescriben la sesión de BD y el usuario/empresa.
"""

from __future__ import annotations

import importlib
import os
import socket
import threading
import time
from collections.abc import AsyncGenerator, Callable, Iterator
from pathlib import Path

import httpx
import pytest
import pytest_asyncio
import uvicorn
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from fastapi import FastAPI

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core import license_client as lc_module
from app.core.database import get_db
from app.core.license_client import LicenseClient
from app.core.security import hash_password
from app.models import Usuario

LICENCIA_TEST = "BWS-TEST-TEST-TEST-TEST"
LICENCIA_TEST_INVALIDA = "BWS-OTRA-OTRA-OTRA-OTRA"


def _puerto_libre() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def _esperar_salud(url: str, timeout: float = 15.0) -> None:
    limite = time.monotonic() + timeout
    ultimo: Exception | None = None
    while time.monotonic() < limite:
        try:
            r = httpx.get(f"{url}/health", timeout=1.0)
            if r.status_code == 200:
                return
        except Exception as exc:  # aún no escucha
            ultimo = exc
        time.sleep(0.1)
    raise RuntimeError(f"El stub del LM no respondió en {url}: {ultimo}")


@pytest.fixture(scope="session")
def lm_stub(tmp_path_factory) -> Iterator[str]:
    """Levanta el stub del LM en un hilo y devuelve su URL base.

    Reusa la clave privada que venga en `LICENSE_PRIVATE_KEY_PATH` (CI la
    genera con `scripts/generate_signing_keys.py` en el runner y nunca la
    commitea); si no existe, genera un par efímero en el directorio temporal
    del test. En ambos casos la clave pública se deriva y se inyecta en el
    `LicenseClient`: la verificación de firma ocurre de verdad.
    """
    ruta_privada = os.environ.get("LICENSE_PRIVATE_KEY_PATH")
    if not ruta_privada or not Path(ruta_privada).is_file():
        dir_claves = tmp_path_factory.mktemp("lm_keys")
        privada = Ed25519PrivateKey.generate()
        ruta = dir_claves / "key_privada.pem"
        ruta.write_bytes(
            privada.private_bytes(
                serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8,
                serialization.NoEncryption(),
            )
        )
        ruta_privada = str(ruta)

    os.environ["LM_STUB_PRIVATE_KEY_PATH"] = ruta_privada
    modulo = importlib.import_module("scripts.lm_stub")
    importlib.reload(modulo)  # relee la clave del entorno

    puerto = _puerto_libre()
    config = uvicorn.Config(
        modulo.app, host="127.0.0.1", port=puerto, log_level="warning"
    )
    servidor = uvicorn.Server(config)
    hilo = threading.Thread(target=servidor.run, daemon=True)
    hilo.start()
    url = f"http://127.0.0.1:{puerto}"
    try:
        _esperar_salud(url)
    except Exception:
        servidor.should_exit = True
        hilo.join(timeout=10)
        raise
    try:
        yield url
    finally:
        servidor.should_exit = True
        hilo.join(timeout=10)


@pytest.fixture
def lm_modo(lm_stub: str) -> Iterator[Callable[[str], None]]:
    """Cambia el modo del stub (`valid`/`invalid`/`expired`/`unreachable`/`tamper`)."""
    r = httpx.post(f"{lm_stub}/__mode/valid", timeout=5.0)
    r.raise_for_status()

    def _set(modo: str) -> None:
        resp = httpx.post(f"{lm_stub}/__mode/{modo}", timeout=5.0)
        resp.raise_for_status()

    yield _set
    httpx.post(f"{lm_stub}/__mode/valid", timeout=5.0)


@pytest.fixture
def lm_client(lm_stub: str) -> Iterator[LicenseClient]:
    """`LicenseClient` real apuntando al stub, con verificación de firma activa."""
    from scripts.lm_stub import estado  # noqa: PLC0415 (el módulo ya está cargado)

    cliente = LicenseClient()
    cliente.base_url = lm_stub
    cliente.public_key = estado.llave_publica_pem()
    assert cliente.public_key, "el stub debe exponer la clave pública de firma"
    yield cliente


@pytest.fixture(autouse=True)
def _inyectar_cliente_en_api(
    lm_client: LicenseClient, monkeypatch: pytest.MonkeyPatch
) -> Iterator[None]:
    """Que los endpoints usen el cliente real (stub) en lugar del singleton real."""
    monkeypatch.setattr(lc_module, "_license_client", lm_client)
    yield


@pytest_asyncio.fixture
async def api_app(db) -> FastAPI:
    """App con los routers reales; solo se sobreescribe la sesión de BD."""
    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    return application


@pytest_asyncio.fixture
async def admin_user(db, empresa) -> Usuario:
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin E2E",
        email="admin@e2e.demo",
        password_hash=hash_password("demo1234"),
        rol="ADMIN",
        activo=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@pytest_asyncio.fixture
async def api_client(api_app: FastAPI, db, empresa, admin_user) -> AsyncGenerator[
    httpx.AsyncClient, None
]:
    """Cliente HTTP con usuario/empresa inyectados (operación normal)."""

    async def _get_db():
        yield db

    api_app.dependency_overrides[get_current_user] = lambda: admin_user
    api_app.dependency_overrides[get_current_empresa] = lambda: empresa
    transport = httpx.ASGITransport(app=api_app)
    async with httpx.AsyncClient(transport=transport, base_url="http://e2e") as ac:
        yield ac


@pytest_asyncio.fixture
async def api_client_anon(api_app: FastAPI, db) -> AsyncGenerator[httpx.AsyncClient, None]:
    """Cliente HTTP sin sesión (login, register, validate-license)."""
    transport = httpx.ASGITransport(app=api_app)
    async with httpx.AsyncClient(transport=transport, base_url="http://e2e") as ac:
        yield ac