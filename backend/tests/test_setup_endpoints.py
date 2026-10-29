"""Pruebas de los endpoints de setup inicial (FASE 2 del plan de despliegue local).

Cubre:
- POST /api/v1/setup/validar-licencia (licencia válida, sin cliente, formato inválido, LM caído)
- POST /api/v1/setup/crear-admin (DB vacía, DB ya poblada, licencia inválida, LM caído)

Usa la misma estrategia que test_categorias_seguridad.py: app FastAPI fresca con
overrides de dependencias (get_db) y cliente httpx ASGI.
"""

from __future__ import annotations

import re
from datetime import UTC, datetime
from uuid import uuid4

import pytest_asyncio
from fastapi import FastAPI, status
from httpx import ASGITransport, AsyncClient

from app.api.dependencies import get_db
from app.api.v1.endpoints import API_ROUTERS
from app.core.database import get_db as get_db_core
from app.core.license_client import LicenseError, LicenseInfo, get_license_client
from app.models import Empresa, Usuario
from app.main import app as _app_main


# ---------------------------------------------------------------------------
# Helpers de mock del LM
# ---------------------------------------------------------------------------

class _FakeLicenseClient:
    """Cliente de licencia falso para pruebas de setup."""

    def __init__(
        self,
        *,
        check_result: dict | None = None,
        validate_result: LicenseInfo | None = None,
        raise_on_check: Exception | None = None,
    ):
        self._check_result = check_result or {}
        self._validate_result = validate_result or LicenseInfo(
            valid=True, status="ACTIVE", tier="CENTRAL", expires_at=None,
            features={}, message="OK",
        )
        self._raise_on_check = raise_on_check

    def check(self, license_key: str) -> dict:
        if self._raise_on_check:
            raise self._raise_on_check
        return dict(self._check_result)

    def validate_or_activate(
        self,
        license_key: str,
        hardware_id: str,
        *,
        mac_address: str | None = None,
        device_brand: str | None = None,
        device_model: str | None = None,
        os_version: str | None = None,
        product_code: str | None = None,
    ) -> LicenseInfo:
        return self._validate_result


def _override_license_client(fake: _FakeLicenseClient) -> None:
    """Reemplaza el cliente de licencia del módulo setup por un falso."""
    import app.api.v1.endpoints.setup as setup_mod

    setup_mod.get_license_client = lambda: fake  # type: ignore[assignment]


# ---------------------------------------------------------------------------
# Fixtures de app y cliente HTTP
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture
async def app(db):  # noqa: F811 - fixture inyectada por conftest
    """App FastAPI con los routers de API y get_db sobrefrito a la sesión de prueba."""
    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db_core] = _get_db
    application.dependency_overrides[get_db] = _get_db
    return application


@pytest_asyncio.fixture
async def client(app):  # noqa: F811
    import httpx

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


# ---------------------------------------------------------------------------
# Pruebas de validación de formato de licencia (puras, sin HTTP)
# ---------------------------------------------------------------------------

def test_license_key_formato_valido():
    patron = r"^[A-Z0-9]{2,11}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"
    assert re.match(patron, "BWS-A1B2-C3D4-E5F6-G7H8")
    assert re.match(patron, "SG-XYZ9-8765-4321-ABCD")
    assert not re.match(patron, "invalido")
    assert not re.match(patron, "BWS-A1B2")


def test_mask_license_key():
    from app.api.v1.endpoints.setup import _mask_license_key

    assert _mask_license_key("BWS-A1B2-C3D4-E5F6-G7H8") == "BWS...G7H8"
    assert _mask_license_key("ABCD") == "••••"
    assert _mask_license_key(None) is None
    assert _mask_license_key("") is None


# ---------------------------------------------------------------------------
# Pruebas de /validar-licencia
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture
async def fake_valido():
    return _FakeLicenseClient(
        check_result={
            "exists": True,
            "status": "AVAILABLE",
            "tier": "CENTRAL",
            "has_client": True,
            "client_id": str(uuid4()),
            "client_name": "Cliente Ejemplo S.A.",
            "client_email": "cliente@ejemplo.com",
            "message": "Licencia disponible",
        },
        validate_result=LicenseInfo(
            valid=True, status="ACTIVE", tier="CENTRAL",
            expires_at=datetime(2027, 12, 31, tzinfo=UTC),
            features={}, message="OK",
        ),
    )


@pytest.mark.asyncio
async def test_validar_licencia_valida_con_cliente(client, app, fake_valido):  # noqa: F811
    _override_license_client(fake_valido)

    resp = await client.post(
        "/api/v1/setup/validar-licencia",
        json={
            "license_key": "BWS-A1B2-C3D4-E5F6-G7H8",
            "hardware_id": "hw-12345",
        },
    )
    assert resp.status_code == status.HTTP_200_OK
    data = resp.json()
    assert data["valid"] is True
    assert data["tier"] == "CENTRAL"
    assert data["client_email"] == "cliente@ejemplo.com"
    assert data["client_name"] == "Cliente Ejemplo S.A."
    assert data["client_id"] is not None
    assert data["licencia_key_masked"] == "BWS...G7H8"


@pytest.mark.asyncio
async def test_validar_licencia_sin_cliente(client, app):  # noqa: F811
    fake = _FakeLicenseClient(
        check_result={
            "exists": True,
            "status": "AVAILABLE",
            "tier": "DEMO",
            "has_client": False,
            "message": "Licencia sin cliente asignado",
        }
    )
    _override_license_client(fake)

    resp = await client.post(
        "/api/v1/setup/validar-licencia",
        json={"license_key": "BWS-A1B2-C3D4-E5F6-G7H8"},
    )
    assert resp.status_code == status.HTTP_400_BAD_REQUEST
    assert "cliente asignado" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_validar_licencia_no_existe(client, app):  # noqa: F811
    fake = _FakeLicenseClient(check_result={"exists": False})
    _override_license_client(fake)

    resp = await client.post(
        "/api/v1/setup/validar-licencia",
        json={"license_key": "BWS-A1B2-C3D4-E5F6-G7H8"},
    )
    assert resp.status_code == status.HTTP_404_NOT_FOUND


@pytest.mark.asyncio
async def test_validar_licencia_formato_invalido(client, app):  # noqa: F811
    resp = await client.post(
        "/api/v1/setup/validar-licencia",
        json={"license_key": "clave-invalida"},
    )
    assert resp.status_code == status.HTTP_400_BAD_REQUEST


@pytest.mark.asyncio
async def test_validar_licencia_lm_caido(client, app):  # noqa: F811
    fake = _FakeLicenseClient(raise_on_check=LicenseError("LM no disponible"))
    _override_license_client(fake)

    resp = await client.post(
        "/api/v1/setup/validar-licencia",
        json={"license_key": "BWS-A1B2-C3D4-E5F6-G7H8"},
    )
    assert resp.status_code == status.HTTP_503_SERVICE_UNAVAILABLE


# ---------------------------------------------------------------------------
# Pruebas de /crear-admin
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture
async def fake_crear_valido():
    return _FakeLicenseClient(
        check_result={
            "exists": True,
            "status": "ACTIVE",
            "tier": "CENTRAL",
            "has_client": True,
            "client_id": str(uuid4()),
            "client_name": "Cliente Ejemplo S.A.",
            "client_email": "cliente@ejemplo.com",
        },
        validate_result=LicenseInfo(
            valid=True, status="ACTIVE", tier="CENTRAL",
            expires_at=datetime(2027, 12, 31, tzinfo=UTC),
            features={}, message="OK",
        ),
    )


@pytest.mark.asyncio
async def test_crear_admin_db_vacia_exito(client, app, db, fake_crear_valido):  # noqa: F811
    _override_license_client(fake_crear_valido)

    resp = await client.post(
        "/api/v1/setup/crear-admin",
        json={
            "license_key": "BWS-A1B2-C3D4-E5F6-G7H8",
            "password": "Password123!",
            "nombre_comercial": "Mi Empresa",
            "rif_nit": "J-12345678-0",
            "direccion": "Calle Falsa 123",
            "telefono": "0212-1234567",
        },
    )
    assert resp.status_code == status.HTTP_201_CREATED
    data = resp.json()
    assert data["access_token"] is not None
    assert data["refresh_token"] is not None
    assert data["token_type"] == "bearer"
    assert data["user"]["rol"] == "ADMIN"
    assert data["user"]["email"] == "cliente@ejemplo.com"
    assert data["empresa"]["rif_nit"] == "J-12345678-0"
    assert data["empresa"]["nombre_comercial"] == "Mi Empresa"
    assert data["empresa"]["lm_client_email"] == "cliente@ejemplo.com"
    assert data["license"]["valid"] is True
    assert data["license"]["tier"] == "CENTRAL"

    # Verificar en BD que la contraseña está hasheada
    from sqlalchemy import select
    result = await db.execute(select(Usuario).where(Usuario.email == "cliente@ejemplo.com"))
    usuario = result.scalar_one()
    assert usuario.password_hash != "Password123!"
    assert usuario.password_hash.startswith("$2b$") or usuario.password_hash.startswith("$2a$")
    assert usuario.rol == "ADMIN"


@pytest.mark.asyncio
async def test_crear_admin_db_ya_tiene_empresa(client, app, db):  # noqa: F811
    # Crear una empresa previa para simular DB ya poblada
    empresa = Empresa(
        id_empresa=uuid4(),
        nombre_fiscal="Empresa Previa",
        rif_nit="J-00000000-0",
        email="previa@ejemplo.com",
        activa=True,
    )
    db.add(empresa)
    await db.commit()

    fake = _FakeLicenseClient(
        check_result={"exists": True, "has_client": True, "client_email": "x@y.com"}
    )
    _override_license_client(fake)

    resp = await client.post(
        "/api/v1/setup/crear-admin",
        json={
            "license_key": "BWS-A1B2-C3D4-E5F6-G7H8",
            "password": "Password123!",
            "nombre_comercial": "Otra Empresa",
            "rif_nit": "J-99999999-9",
        },
    )
    assert resp.status_code == status.HTTP_409_CONFLICT
    assert "ya tiene una empresa" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_crear_admin_licencia_invalida(client, app, db):  # noqa: F811
    fake = _FakeLicenseClient(
        check_result={
            "exists": True, "has_client": True,
            "client_email": "cliente@ejemplo.com",
            "client_name": "Cliente Ejemplo",
        },
        validate_result=LicenseInfo(
            valid=False, status="EXPIRED", tier="DEMO",
            expires_at=None, features={}, message="Licencia expirada",
        ),
    )
    _override_license_client(fake)

    resp = await client.post(
        "/api/v1/setup/crear-admin",
        json={
            "license_key": "BWS-A1B2-C3D4-E5F6-G7H8",
            "password": "Password123!",
            "nombre_comercial": "Mi Empresa",
            "rif_nit": "J-12345678-0",
        },
    )
    assert resp.status_code == status.HTTP_403_FORBIDDEN


@pytest.mark.asyncio
async def test_crear_admin_lm_caido(client, app, db):  # noqa: F811
    fake = _FakeLicenseClient(raise_on_check=LicenseError("LM no disponible"))
    _override_license_client(fake)

    resp = await client.post(
        "/api/v1/setup/crear-admin",
        json={
            "license_key": "BWS-A1B2-C3D4-E5F6-G7H8",
            "password": "Password123!",
            "nombre_comercial": "Mi Empresa",
            "rif_nit": "J-12345678-0",
        },
    )
    assert resp.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
