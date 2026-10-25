"""Pruebas HTTP del módulo INDICADORES (terminal de peso) — migración 028.

Estrategia de ``test_camaras_api.py``: app FastAPI fresca con overrides de
dependencias sobre la BD real de tests.

Cubre las reglas del negocio:

- El indicador (terminal) es una entidad separada de la báscula física.
- El enlace báscula ↔ indicador vive en ``balanzas.id_indicador`` (nullable).
- Un indicador con básculas enlazadas **no se puede borrar** (409).
- Aislamiento multi-tenant: un indicador de otra empresa da 404.
"""

from __future__ import annotations

import uuid

import httpx
import pytest_asyncio
from fastapi import FastAPI

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core.database import get_db
from app.models import Balanza, Empresa, Indicador, Usuario


def _app_para(db, user: Usuario, empresa: Empresa) -> FastAPI:
    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    application.dependency_overrides[get_current_user] = lambda: user
    application.dependency_overrides[get_current_empresa] = lambda: empresa
    return application


@pytest_asyncio.fixture
async def admin(db, empresa):
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin Indicador",
        email=f"admin-{uuid.uuid4().hex[:6]}@indic.demo",
        password_hash="x",
        rol="ADMIN",
        activo=True,
    )
    db.add(user)
    await db.commit()
    return user


@pytest_asyncio.fixture
async def operador(db, empresa):
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Operador Indicador",
        email=f"op-{uuid.uuid4().hex[:6]}@indic.demo",
        password_hash="x",
        rol="OPERADOR",
        activo=True,
    )
    db.add(user)
    await db.commit()
    return user


@pytest_asyncio.fixture
async def app(db, admin, empresa):
    return _app_para(db, admin, empresa)


@pytest_asyncio.fixture
async def client(app):
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


async def _crear_indicador(db, empresa, descripcion="Indicador entrada", **extra) -> Indicador:
    ind = Indicador(
        id_empresa=empresa.id_empresa,
        descripcion=descripcion,
        **extra,
    )
    db.add(ind)
    await db.commit()
    await db.refresh(ind)
    return ind


async def _crear_balanza(db, empresa, descripcion="Báscula 1", **extra) -> Balanza:
    b = Balanza(
        id_empresa=empresa.id_empresa,
        descripcion=descripcion,
        capacidad_max=extra.pop("capacidad_max", 60000),
        **extra,
    )
    db.add(b)
    await db.commit()
    await db.refresh(b)
    return b


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------
class TestCrudIndicadores:
    async def test_lista_vacia(self, client):
        r = await client.get("/api/v1/indicadores")
        assert r.status_code == 200
        assert r.json() == []

    async def test_crear_aplica_defaults(self, client):
        r = await client.post(
            "/api/v1/indicadores",
            json={"descripcion": "Indicador BKG"},
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["descripcion"] == "Indicador BKG"
        assert data["formato_trama"] == "auto"
        assert data["baudrate"] == 9600
        assert data["activo"] is True
        assert data["balanzas_enlazadas"] == 0

    async def test_crear_con_configuracion_completa(self, client):
        r = await client.post(
            "/api/v1/indicadores",
            json={
                "descripcion": "CAS C12001A",
                "marca": "CAS",
                "modelo": "C12001A",
                "protocolo": "serial",
                "puerto_com": "/dev/ttyUSB0",
                "formato_trama": "ascii",
                "baudrate": 19200,
                "delimitador": "crlf",
            },
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["marca"] == "CAS"
        assert data["modelo"] == "C12001A"
        assert data["protocolo"] == "serial"
        assert data["puerto_com"] == "/dev/ttyUSB0"
        assert data["formato_trama"] == "ascii"
        assert data["baudrate"] == 19200
        assert data["delimitador"] == "crlf"

    async def test_baudrate_invalido_devuelve_422(self, client):
        r = await client.post(
            "/api/v1/indicadores",
            json={"descripcion": "Indicador raro", "baudrate": 12345},
        )
        assert r.status_code == 422

    async def test_operador_no_puede_crear(self, db, operador, empresa):
        app = _app_para(db, operador, empresa)
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            r = await ac.post(
                "/api/v1/indicadores",
                json={"descripcion": "Indicador operador"},
            )
        assert r.status_code == 403

    async def test_actualizar(self, client, db, empresa):
        ind = await _crear_indicador(db, empresa)
        r = await client.put(
            f"/api/v1/indicadores/{ind.id_indicador}",
            json={"descripcion": "Indicador renombrado", "ip_address": "10.0.0.9"},
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["descripcion"] == "Indicador renombrado"
        assert data["ip_address"] == "10.0.0.9"

    async def test_eliminar(self, client, db, empresa):
        ind = await _crear_indicador(db, empresa)
        r = await client.delete(f"/api/v1/indicadores/{ind.id_indicador}")
        assert r.status_code == 204
        assert (await client.get("/api/v1/indicadores")).json() == []


# ---------------------------------------------------------------------------
# Aislamiento multi-tenant
# ---------------------------------------------------------------------------
class TestAislamiento:
    async def test_indicador_de_otra_empresa_da_404(self, client, db):
        otra = Empresa(
            nombre_fiscal=f"Otra {uuid.uuid4().hex[:6]}",
            rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        )
        db.add(otra)
        await db.commit()
        await db.refresh(otra)
        ajeno = await _crear_indicador(db, otra, descripcion="Ajeno")

        r = await client.put(
            f"/api/v1/indicadores/{ajeno.id_indicador}",
            json={"descripcion": "Intruso"},
        )
        assert r.status_code == 404

    async def test_lista_solo_de_la_empresa(self, client, db, empresa):
        await _crear_indicador(db, empresa, descripcion="Propio")
        otra = Empresa(
            nombre_fiscal=f"Otra {uuid.uuid4().hex[:6]}",
            rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        )
        db.add(otra)
        await db.commit()
        await db.refresh(otra)
        await _crear_indicador(db, otra, descripcion="Ajeno")

        r = await client.get("/api/v1/indicadores")
        assert r.status_code == 200
        descripciones = [x["descripcion"] for x in r.json()]
        assert descripciones == ["Propio"]


# ---------------------------------------------------------------------------
# Enlace báscula ↔ indicador
# ---------------------------------------------------------------------------
class TestEnlace:
    async def test_enlazar_y_contar(self, client, db, empresa):
        ind = await _crear_indicador(db, empresa)
        bal = await _crear_balanza(db, empresa)

        r = await client.post(
            f"/api/v1/indicadores/{ind.id_indicador}/balanzas/{bal.id_balanza}/enlazar"
        )
        assert r.status_code == 200, r.text
        assert r.json()["balanzas_enlazadas"] == 1

        await db.refresh(bal)
        assert bal.id_indicador == ind.id_indicador

    async def test_desenlazar(self, client, db, empresa):
        ind = await _crear_indicador(db, empresa)
        bal = await _crear_balanza(db, empresa)

        await client.post(
            f"/api/v1/indicadores/{ind.id_indicador}/balanzas/{bal.id_balanza}/enlazar"
        )
        r = await client.delete(
            f"/api/v1/indicadores/{ind.id_indicador}/balanzas/{bal.id_balanza}/enlazar"
        )
        assert r.status_code == 200, r.text
        assert r.json()["balanzas_enlazadas"] == 0

        await db.refresh(bal)
        assert bal.id_indicador is None

    async def test_reasignar_a_otro_indicador(self, client, db, empresa):
        ind1 = await _crear_indicador(db, empresa, descripcion="Indicador 1")
        ind2 = await _crear_indicador(db, empresa, descripcion="Indicador 2")
        bal = await _crear_balanza(db, empresa)

        await client.post(
            f"/api/v1/indicadores/{ind1.id_indicador}/balanzas/{bal.id_balanza}/enlazar"
        )
        await client.post(
            f"/api/v1/indicadores/{ind2.id_indicador}/balanzas/{bal.id_balanza}/enlazar"
        )
        await db.refresh(bal)
        assert bal.id_indicador == ind2.id_indicador

    async def test_enlazar_balanza_ajena_da_404(self, client, db, empresa):
        ind = await _crear_indicador(db, empresa)
        otra = Empresa(
            nombre_fiscal=f"Otra {uuid.uuid4().hex[:6]}",
            rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        )
        db.add(otra)
        await db.commit()
        await db.refresh(otra)
        bal_ajena = await _crear_balanza(db, otra, descripcion="Báscula ajena")

        r = await client.post(
            f"/api/v1/indicadores/{ind.id_indicador}"
            f"/balanzas/{bal_ajena.id_balanza}/enlazar"
        )
        assert r.status_code == 404

    async def test_eliminar_enlazado_devuelve_409(self, client, db, empresa):
        ind = await _crear_indicador(db, empresa)
        bal = await _crear_balanza(db, empresa)
        await client.post(
            f"/api/v1/indicadores/{ind.id_indicador}/balanzas/{bal.id_balanza}/enlazar"
        )

        r = await client.delete(f"/api/v1/indicadores/{ind.id_indicador}")
        assert r.status_code == 409
        # Sigue existiendo.
        assert len((await client.get("/api/v1/indicadores")).json()) == 1

    async def test_eliminar_tras_desenlazar(self, client, db, empresa):
        ind = await _crear_indicador(db, empresa)
        bal = await _crear_balanza(db, empresa)
        await client.post(
            f"/api/v1/indicadores/{ind.id_indicador}/balanzas/{bal.id_balanza}/enlazar"
        )
        await client.delete(
            f"/api/v1/indicadores/{ind.id_indicador}/balanzas/{bal.id_balanza}/enlazar"
        )

        r = await client.delete(f"/api/v1/indicadores/{ind.id_indicador}")
        assert r.status_code == 204
