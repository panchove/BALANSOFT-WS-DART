"""Tests de la siembra inicial de catálogos (REQ-FN-023).

Cubre:
- El registro de una empresa nueva siembra categorías/productos/almacén.
- La siembra es idempotente (no duplica en logins posteriores).
- El endpoint manual ``POST /api/v1/catalogo/seed`` es solo ADMIN y responde
  409 cuando la empresa ya tiene catálogos.
- Los productos sembrados llevan ``es_kardex=True`` y existe el almacén
  ``PRINCIPAL`` (``ALM01``).
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator

import httpx
import pytest_asyncio
from fastapi import FastAPI
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core.database import get_db
from app.core.license_client import LicenseInfo
from app.models import Almacen, Categoria, Empresa, Producto, Usuario
from app.services.seed_service import (
    ALMACEN_PRINCIPAL_CODIGO,
    SeedService,
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
        email=f"admin-seed-{uuid.uuid4().hex[:6]}@test.com",
        password_hash="x",
        rol="ADMIN",
        activo=True,
    )
    db.add(u)
    await db.commit()
    await db.refresh(u)
    return u


def _build_app(db, usuario: Usuario, empresa: Empresa) -> FastAPI:
    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    application.dependency_overrides[get_current_user] = lambda: usuario
    application.dependency_overrides[get_current_empresa] = lambda: empresa
    return application


@pytest_asyncio.fixture
async def app(db, empresa, admin_user) -> FastAPI:
    return _build_app(db, admin_user, empresa)


@pytest_asyncio.fixture
async def client(app) -> AsyncGenerator[httpx.AsyncClient, None]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


async def _conteos(db: AsyncSession, id_empresa) -> dict:
    categorias = await db.scalar(
        select(func.count()).select_from(Categoria).where(Categoria.id_empresa == id_empresa)
    )
    productos = await db.scalar(
        select(func.count()).select_from(Producto).where(Producto.id_empresa == id_empresa)
    )
    almacenes = await db.scalar(
        select(func.count()).select_from(Almacen).where(Almacen.id_empresa == id_empresa)
    )
    return {"categorias": categorias, "productos": productos, "almacenes": almacenes}


class TestSeedAlRegistrar:
    """El registro de una empresa nueva dispara la siembra (REQ-FN-023)."""

    async def test_register_siembra_catalogos(self, db: AsyncSession, monkeypatch):
        from app.api.v1.endpoints import auth as _auth

        monkeypatch.setattr(_auth, "get_license_client", FakeLM)

        app_anon = FastAPI()
        for router in API_ROUTERS:
            app_anon.include_router(router)

        async def _get_db():
            yield db

        app_anon.dependency_overrides[get_db] = _get_db

        transport = httpx.ASGITransport(app=app_anon)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            r = await ac.post(
                "/api/v1/auth/register",
                json={
                    "empresa_nombre": "Empresa Semilla",
                    "empresa_rif": f"J-{uuid.uuid4().hex[:10]}",
                    "usuario_nombre": "Admin Semilla",
                    "email": f"seed-{uuid.uuid4().hex[:8]}@test.com",
                    "password": "clave123456",
                    "licencia_key": "SEMILLA-LICENCIA-1",
                },
            )
        assert r.status_code == 201, r.text

        empresa = (
            await db.execute(select(Empresa).where(Empresa.nombre_fiscal == "Empresa Semilla"))
        ).scalar_one()
        conteos = await _conteos(db, empresa.id_empresa)
        assert conteos == {"categorias": 6, "productos": 12, "almacenes": 1}

        # Todos los productos sembrados llevan es_kardex=True.
        productos = (
            await db.execute(select(Producto).where(Producto.id_empresa == empresa.id_empresa))
        ).scalars().all()
        assert productos and all(p.es_kardex for p in productos)

        # Existe el almacén principal ALM01.
        almacen = (
            await db.execute(
                select(Almacen).where(
                    Almacen.id_empresa == empresa.id_empresa,
                    Almacen.codigo == ALMACEN_PRINCIPAL_CODIGO,
                )
            )
        ).scalar_one()
        assert almacen.nombre == "PRINCIPAL"


class TestSeedIdempotente:
    """La siembra no se duplica y no sobrescribe datos existentes."""

    async def test_aplicar_si_aplicable_no_duplica(self, db: AsyncSession, empresa: Empresa):
        primer = await SeedService.aplicar(db, empresa)
        await db.commit()
        assert primer.categorias == 6 and primer.productos == 12 and primer.almacenes == 1

        segundo = await SeedService.aplicar_si_aplicable(db, empresa)
        await db.commit()
        assert segundo is None
        assert await _conteos(db, empresa.id_empresa) == {
            "categorias": 6,
            "productos": 12,
            "almacenes": 1,
        }

    async def test_aplicar_con_catalogo_existente_lanza(self, db: AsyncSession, empresa: Empresa):
        db.add(
            Categoria(
                id_categoria=uuid.uuid4(),
                id_empresa=empresa.id_empresa,
                codigo="EXISTE",
                nombre="Ya existe",
            )
        )
        await db.commit()

        import pytest

        with pytest.raises(ValueError):
            await SeedService.aplicar(db, empresa)

    async def test_sembrar_si_aplicable_aplica_y_confirma(
        self, db: AsyncSession, empresa: Empresa
    ):
        """La variante protegida aplica Y confirma en una sola llamada."""
        aplicado = await SeedService.sembrar_si_aplicable(db, empresa)
        assert aplicado is True
        # Persistido (commit interno): visible en una consulta nueva.
        assert await _conteos(db, empresa.id_empresa) == {
            "categorias": 6,
            "productos": 12,
            "almacenes": 1,
        }
        # Idempotente: una segunda llamada no duplica.
        segundo = await SeedService.sembrar_si_aplicable(db, empresa)
        assert segundo is False
        assert await _conteos(db, empresa.id_empresa) == {
            "categorias": 6,
            "productos": 12,
            "almacenes": 1,
        }

    async def test_sembrar_si_aplicable_fallo_never_rompe(
        self, db: AsyncSession, empresa: Empresa, monkeypatch
    ):
        """Un fallo de infraestructura en la siembra no rompe login/registro."""

        async def _bd_caida(*args, **kwargs):
            raise RuntimeError("base de datos caída")

        monkeypatch.setattr(
            SeedService, "empresa_sin_catalogo", staticmethod(_bd_caida)
        )
        aplicado = await SeedService.sembrar_si_aplicable(db, empresa)
        assert aplicado is False

        # El servicio se recupera: deshecho el fallo, la siguiente llamada
        # aplica y confirma sin necesidad de reiniciar (rollback limpio).
        monkeypatch.undo()
        recuperado = await SeedService.sembrar_si_aplicable(db, empresa)
        assert recuperado is True
        assert await _conteos(db, empresa.id_empresa) == {
            "categorias": 6,
            "productos": 12,
            "almacenes": 1,
        }


class TestSeedEndpoint:
    """Endpoint manual ``POST /api/v1/catalogo/seed`` (solo ADMIN)."""

    async def test_seed_manual_admin(self, client, db: AsyncSession, empresa: Empresa):
        r = await client.post("/api/v1/catalogo/seed")
        assert r.status_code == 200, r.text
        body = r.json()
        assert body == {
            "aplicado": True,
            "categorias": 6,
            "productos": 12,
            "almacenes": 1,
        }

        # Segunda llamada: la empresa ya tiene catálogos → 409.
        r2 = await client.post("/api/v1/catalogo/seed")
        assert r2.status_code == 409

    async def test_seed_manual_requiere_admin(
        self, db: AsyncSession, empresa: Empresa, admin_user: Usuario
    ):
        auditor = Usuario(
            id_empresa=empresa.id_empresa,
            nombre="Auditor",
            email=f"auditor-seed-{uuid.uuid4().hex[:6]}@test.com",
            password_hash="x",
            rol="AUDITOR",
            activo=True,
        )
        db.add(auditor)
        await db.commit()
        await db.refresh(auditor)

        app_auditor = _build_app(db, auditor, empresa)
        transport = httpx.ASGITransport(app=app_auditor)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            r = await ac.post("/api/v1/catalogo/seed")
        assert r.status_code == 403