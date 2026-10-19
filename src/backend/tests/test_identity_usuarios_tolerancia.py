"""Tests de las nuevas funcionalidades backend:
- Identidad local (singleton).
- Validación de tolerancia comercial al cerrar boleto.
- CRUD de usuarios locales + cola de sync.

Usa la misma BD de test que conftest.py (PostgreSQL real, `balansoft_ws_test`).
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator
from decimal import Decimal

import httpx
import pytest_asyncio
from fastapi import FastAPI
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.api.v1.endpoints import auth as auth_module
from app.core.database import get_db
from app.core.license_client import LicenseInfo
from app.core.security import hash_password
from app.models import (
    Categoria,
    Empresa,
    IdentidadLocal,
    LogSistema,
    Producto,
    SyncQueue,
    Usuario,
)


class FakeLM:
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


@pytest_asyncio.fixture
async def admin_user(db: AsyncSession, empresa: Empresa) -> Usuario:
    u = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin",
        email=f"admin-id-{uuid.uuid4().hex[:6]}@test.com",
        password_hash="x",
        rol="ADMIN",
        activo=True,
    )
    db.add(u)
    await db.commit()
    await db.refresh(u)
    return u


@pytest_asyncio.fixture
async def app(db, empresa, admin_user, monkeypatch) -> FastAPI:
    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    application.dependency_overrides[get_current_user] = lambda: admin_user
    application.dependency_overrides[get_current_empresa] = lambda: empresa
    monkeypatch.setattr(auth_module, "get_license_client", FakeLM)
    return application


@pytest_asyncio.fixture
async def client(app) -> AsyncGenerator[httpx.AsyncClient, None]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


# -----------------------------------------------------------------------
# Identidad local
# -----------------------------------------------------------------------


class TestIdentidadLocal:
    async def test_put_y_get_identidad(self, client, db):
        payload = {
            "id_cuenta": str(uuid.uuid4()),
            "rif_nit": "J-123456789",
            "nombre_fiscal": "Empresa Identidad",
            "nombre_comercial": "Identidad SA",
            "licencia_key": "KEY123",
            "licencia_tier": "CENTRAL",
            "licencia_status": "ACTIVA",
            "licencia_expira": "2030-01-01T00:00:00Z",
            "hardware_id": "HW-ID-001",
        }
        r = await client.put("/api/v1/identity", json=payload)
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["rif_nit"] == "J-123456789"
        assert data["nombre_fiscal"] == "Empresa Identidad"
        assert data["modo_offline"] is False

        r2 = await client.get("/api/v1/identity")
        assert r2.status_code == 200
        assert r2.json()["id_cuenta"] == payload["id_cuenta"]

    async def test_identidad_no_configurada_404(self, client):
        r = await client.get("/api/v1/identity")
        assert r.status_code == 404

    async def test_validate_license_persiste_hardware_id(self, client, db):
        r = await client.post(
            "/api/v1/auth/validate-license",
            json={"licencia_key": "KEY-123", "hardware_id": "HW-REAL-001"},
        )
        assert r.status_code == 200, r.text
        identidad = (
            await db.execute(
                select(IdentidadLocal).where(IdentidadLocal.id.is_(True))
            )
        ).scalar_one_or_none()
        assert identidad is not None
        assert identidad.hardware_id == "HW-REAL-001"

    async def test_login_admin_hardware_mismatch_rechazado(self, app, db, empresa, admin_user):
        admin_user.password_hash = hash_password("password123")
        identidad = IdentidadLocal(
            id=True,
            id_cuenta=empresa.id_empresa,
            rif_nit=empresa.rif_nit,
            nombre_fiscal=empresa.nombre_fiscal,
            hardware_id="HW-TITULAR-001",
        )
        db.add(identidad)
        await db.commit()

        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.post(
                "/api/v1/auth/login",
                json={
                    "email": admin_user.email,
                    "password": "password123",
                    "hardware_id": "HW-OTRO-DISPOSITIVO",
                },
            )
            assert resp.status_code == 403
            assert "activada en otro equipo titular" in resp.json()["detail"]

    async def test_put_identidad_requiere_admin(self, app, db, empresa, monkeypatch):
        non_admin = Usuario(
            id_empresa=empresa.id_empresa,
            nombre="Operador",
            email=f"op-{uuid.uuid4().hex[:6]}@test.com",
            password_hash="x",
            rol="OPERADOR",
            activo=True,
        )
        db.add(non_admin)
        await db.commit()

        app.dependency_overrides[get_current_user] = lambda: non_admin
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            r = await ac.put(
                "/api/v1/identity",
                json={
                    "id_cuenta": str(uuid.uuid4()),
                    "rif_nit": "J-000",
                    "nombre_fiscal": "Fallo",
                },
            )
            assert r.status_code == 403


# -----------------------------------------------------------------------
# Perfil de la empresa
# -----------------------------------------------------------------------


class TestEmpresaPerfil:
    async def test_get_perfil(self, client):
        r = await client.get("/api/v1/empresa")
        assert r.status_code == 200, r.text
        assert r.json()["nombre_fiscal"] == "Empresa Test"
        assert r.json()["logo_url"] is None

    async def test_put_perfil_admin(self, client, db, empresa):
        r = await client.put(
            "/api/v1/empresa",
            json={
                "nombre_comercial": "Comercial Nueva",
                "direccion": "Av. Siempre Viva 123",
                "telefono": "+58 412-0000000",
                "email": "contacto@test.com",
                "logo_url": "/media/logos/logo.png",
            },
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["nombre_comercial"] == "Comercial Nueva"
        assert data["logo_url"] == "/media/logos/logo.png"

        await db.refresh(empresa)
        assert empresa.telefono == "+58 412-0000000"
        assert empresa.email == "contacto@test.com"

    async def test_put_perfil_requiere_admin(self, app, db, empresa):
        operador = Usuario(
            id_empresa=empresa.id_empresa,
            nombre="Operador Perfil",
            email=f"op-perfil-{uuid.uuid4().hex[:6]}@test.com",
            password_hash="x",
            rol="OPERADOR",
            activo=True,
        )
        db.add(operador)
        await db.commit()

        app.dependency_overrides[get_current_user] = lambda: operador
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            r = await ac.put(
                "/api/v1/empresa", json={"nombre_comercial": "No permitido"}
            )
            assert r.status_code == 403


# -----------------------------------------------------------------------
# Tolerancia comercial
# -----------------------------------------------------------------------


class TestToleranciaComercial:
    async def test_advertencia_tolerancia_en_cierre(self, client, db, empresa):
        categoria = Categoria(
            id_empresa=empresa.id_empresa, nombre="Categoría Cemento"
        )
        db.add(categoria)
        await db.flush()
        producto = Producto(
            id_empresa=empresa.id_empresa,
            id_categoria=categoria.id_categoria,
            nombre="Cemento Tolerancia",
            tolerancia=Decimal("1.00"),  # 1% de tolerancia
            es_kardex=False,
        )
        db.add(producto)
        await db.flush()

        create_payload = {
            "id_vehiculo": "TOL-001",
            "producto_nombre": "Cemento Tolerancia",
            "almacen_nombre": "Planta T",
            "balanza_nombre": "B1",
            "peso_entrada_vehiculo": "50000",
        }
        r = await client.post("/api/v1/weighing/create", json=create_payload)
        assert r.status_code == 200, r.text
        boleto = r.json()["boleto"]

        # Salida 40000; PND 8000 → PNT=10000 → PDF=2000 → PDV=0.25 → 25% > 1%
        close_payload = {
            "peso_salida_vehiculo": "40000",
            "peso_neto_declarado": "8000",
        }
        r = await client.post(f"/api/v1/weighing/close/{boleto}", json=close_payload)
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["estado_boleto"] == "CERRADO"
        assert body["advertencia_tolerancia"] is not None
        assert "25.00%" in body["advertencia_tolerancia"]

        log = (
            await db.execute(
                select(LogSistema).where(LogSistema.modulo == "weighing")
            )
        ).scalar_one_or_none()
        assert log is not None
        assert log.nivel == "WARN"

    async def test_sin_advertencia_dentro_tolerancia(self, client, db, empresa):
        categoria = Categoria(
            id_empresa=empresa.id_empresa, nombre="Categoría Arena"
        )
        db.add(categoria)
        await db.flush()
        producto = Producto(
            id_empresa=empresa.id_empresa,
            id_categoria=categoria.id_categoria,
            nombre="Arena Tolerancia",
            tolerancia=Decimal("5.00"),
            es_kardex=False,
        )
        db.add(producto)
        await db.flush()

        create = await client.post(
            "/api/v1/weighing/create",
            json={
                "id_vehiculo": "TOL-002",
                "producto_nombre": "Arena Tolerancia",
                "almacen_nombre": "Planta T",
                "balanza_nombre": "B2",
                "peso_entrada_vehiculo": "50000",
            },
        )
        boleto = create.json()["boleto"]
        # Salida 2000 → PNT=48000 → PDF=0 → PDV=0%, dentro del 5%.
        close = await client.post(
            f"/api/v1/weighing/close/{boleto}",
            json={"peso_salida_vehiculo": "2000", "peso_neto_declarado": "48000"},
        )
        assert close.status_code == 200
        assert close.json()["advertencia_tolerancia"] is None


# -----------------------------------------------------------------------
# CRUD Usuarios + cola sync
# -----------------------------------------------------------------------


class TestUsuariosCRUD:
    async def test_create_y_list_usuarios(self, client, db, empresa):
        # La empresa ya tiene el usuario ADMIN (fixture admin_user).
        r = await client.get("/api/v1/usuarios")
        assert r.status_code == 200
        assert len(r.json()) == 1

        email = f"usr-{uuid.uuid4().hex[:6]}@test.com"
        r = await client.post(
            "/api/v1/usuarios",
            json={
                "nombre": "Juan Operador",
                "email": email,
                "password": "pass123456",
                "rol": "OPERADOR",
            },
        )
        assert r.status_code == 201, r.text
        uid = r.json()["id_usuario"]
        assert r.json()["email"] == email

        cola = (
            await db.execute(
                select(SyncQueue).where(
                    SyncQueue.entidad == "usuario",
                    SyncQueue.entidad_id == uid,
                    SyncQueue.pendiente.is_(True),
                )
            )
        ).scalar_one_or_none()
        assert cola is not None
        assert cola.operacion == "upsert"
        assert cola.payload["email"] == email

        r = await client.get("/api/v1/usuarios")
        assert len(r.json()) == 2

    async def test_update_y_delete_usuario(self, client, db, empresa):
        create = await client.post(
            "/api/v1/usuarios",
            json={
                "nombre": "Actualizable",
                "email": f"a-{uuid.uuid4().hex[:6]}@test.com",
                "password": "pass123456",
                "rol": "OPERADOR",
            },
        )
        uid = create.json()["id_usuario"]

        r = await client.put(f"/api/v1/usuarios/{uid}", json={"rol": "AUDITOR"})
        assert r.status_code == 200
        assert r.json()["rol"] == "AUDITOR"

        r = await client.delete(f"/api/v1/usuarios/{uid}")
        assert r.status_code == 204

        u = (
            await db.execute(select(Usuario).where(Usuario.id_usuario == uid))
        ).scalar_one()
        assert u.activo is False

    async def test_email_duplicado_400(self, client, empresa, db):
        email = f"dup-{uuid.uuid4().hex[:6]}@test.com"
        await client.post(
            "/api/v1/usuarios",
            json={"nombre": "Usuario A", "email": email, "password": "pass123456"},
        )
        r = await client.post(
            "/api/v1/usuarios",
            json={"nombre": "Usuario B", "email": email, "password": "pass123456"},
        )
        assert r.status_code == 400

    async def test_no_admin_cannot_create(self, app, db, empresa):
        operador = Usuario(
            id_empresa=empresa.id_empresa,
            nombre="OP",
            email=f"noadmin-{uuid.uuid4().hex[:6]}@test.com",
            password_hash="x",
            rol="OPERADOR",
            activo=True,
        )
        db.add(operador)
        await db.flush()
        app.dependency_overrides[get_current_user] = lambda: operador
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            r = await ac.post(
                "/api/v1/usuarios",
                json={
                    "nombre": "Usuario X",
                    "email": f"x-{uuid.uuid4().hex[:6]}@test.com",
                    "password": "pass123456",
                },
            )
            assert r.status_code == 403


# -----------------------------------------------------------------------
# Sync pendientes/entregados
# -----------------------------------------------------------------------


class TestSyncUsuariosEndpoints:
    async def test_pendientes_y_entregados(self, client, db, empresa):
        from datetime import UTC, datetime
        now = datetime.now(UTC).replace(tzinfo=None)
        sq = SyncQueue(
            id_empresa=empresa.id_empresa,
            entidad="usuario",
            operacion="upsert",
            entidad_id=str(uuid.uuid4()),
            payload={"email": "sync@test.com", "nombre": "Sync"},
            pendiente=True,
            created_at=now,
            updated_at=now,
        )
        db.add(sq)
        await db.flush()

        r = await client.get("/api/v1/sync/usuarios/pendientes")
        assert r.status_code == 200
        pendientes = r.json()["pendientes"]
        assert len(pendientes) == 1
        assert pendientes[0]["id_sync"] == str(sq.id_sync)

        r = await client.post(
            "/api/v1/sync/usuarios/entregados",
            json={"ids": [str(sq.id_sync)]},
        )
        assert r.status_code == 200
        assert r.json()["entregados"] == 1

        await db.refresh(sq)
        assert sq.pendiente is False
