"""Pruebas HTTP de Categorías (CRUD + sync) y Seguridad y Accesos (matriz).

Usa la misma estrategia que test_endpoints.py: app FastAPI fresca con overrides
de dependencias. Categorías y permisos operan sobre la BD real de tests.
"""

from __future__ import annotations

import pytest_asyncio
from fastapi import FastAPI

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core.database import get_db
from app.models import Usuario


@pytest_asyncio.fixture
async def app(db, empresa, monkeypatch) -> FastAPI:
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin Test",
        email="admin@seguridad.demo",
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
    return application


@pytest_asyncio.fixture
async def client(app):

    import httpx

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


class TestCategoriasEndpoints:
    async def test_crud_categoria(self, client):
        r = await client.post(
            "/api/v1/categorias",
            json={
                "codigo": "CAT-01",
                "nombre": "Agregados",
                "descripcion": "Materiales granulares",
            },
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["nombre"] == "Agregados"
        id_cat = body["id_categoria"]

        r = await client.get("/api/v1/categorias")
        assert r.status_code == 200
        assert any(c["id_categoria"] == id_cat for c in r.json())

        r = await client.put(
            f"/api/v1/categorias/{id_cat}",
            json={
                "codigo": "CAT-01",
                "nombre": "Agregados y Derivados",
                "descripcion": "Actualizado",
            },
        )
        assert r.status_code == 200
        assert r.json()["nombre"] == "Agregados y Derivados"

        r = await client.delete(f"/api/v1/categorias/{id_cat}")
        assert r.status_code == 204

        r = await client.get("/api/v1/categorias")
        assert r.status_code == 200
        assert all(c["id_categoria"] != id_cat for c in r.json())

    async def test_categoria_requiere_nombre(self, client):
        r = await client.post("/api/v1/categorias", json={"nombre": ""})
        assert r.status_code == 422

    async def test_categorias_en_sync(self, client):
        await client.post(
            "/api/v1/categorias",
            json={"codigo": "CAT-SYNC", "nombre": "Lubricantes"},
        )
        r = await client.get("/api/v1/catalogo/sync")
        assert r.status_code == 200
        data = r.json()
        assert "categorias" in data
        assert any(c["nombre"] == "Lubricantes" for c in data["categorias"])


class TestProductoCategoriaEndpoints:
    async def test_producto_sin_categoria_rechazado(self, client):
        r = await client.post(
            "/api/v1/productos",
            json={"nombre": "Clinker", "codigo": "CLK"},
        )
        assert r.status_code == 422

    async def test_producto_categoria_inexistente_rechazado(self, client):
        r = await client.post(
            "/api/v1/productos",
            json={"nombre": "Clinker", "id_categoria": "00000000-0000-0000-0000-000000000000"},
        )
        assert r.status_code == 409

    async def test_producto_categoria_de_otra_empresa_rechazado(self, client, db):
        from app.models import Categoria, Empresa

        otra = Empresa(
            nombre_fiscal="Otra Empresa",
            nombre_comercial="Otra S.A.",
            rif_nit="J-99999999-0",
            licencia_tier="MONOPUESTA",
            licencia_status="ACTIVE",
            activa=True,
        )
        db.add(otra)
        await db.flush()
        otra_cat = Categoria(
            id_empresa=otra.id_empresa, nombre="Cat ajena"
        )
        db.add(otra_cat)
        await db.commit()

        r = await client.post(
            "/api/v1/productos",
            json={"nombre": "Clinker", "id_categoria": str(otra_cat.id_categoria)},
        )
        assert r.status_code == 409

    async def test_producto_con_categoria_ok(self, client):
        cat = (await client.post(
            "/api/v1/categorias", json={"nombre": "Cementos"}
        )).json()

        r = await client.post(
            "/api/v1/productos",
            json={
                "nombre": "Cemento Tipo I",
                "codigo": "CEM-I",
                "id_categoria": cat["id_categoria"],
            },
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["id_categoria"] == cat["id_categoria"]

        id_prod = body["id_producto"]
        r = await client.get("/api/v1/productos")
        assert r.status_code == 200
        assert any(p["id_producto"] == id_prod for p in r.json())

    async def test_producto_update_con_categoria_valida(self, client):
        cat = (await client.post(
            "/api/v1/categorias", json={"nombre": "Derivados"}
        )).json()
        prod = (await client.post(
            "/api/v1/productos",
            json={"nombre": "Agregado", "id_categoria": cat["id_categoria"]},
        )).json()

        r = await client.put(
            f"/api/v1/productos/{prod['id_producto']}",
            json={
                "nombre": "Agregado fino",
                "id_categoria": cat["id_categoria"],
            },
        )
        assert r.status_code == 200, r.text
        assert r.json()["nombre"] == "Agregado fino"


class TestSeguridadEndpoints:
    async def test_matriz_valores_default(self, client):
        r = await client.get("/api/v1/seguridad/matriz")
        assert r.status_code == 200
        modulos = r.json()["modulos"]
        mapa = {m["clave"]: m for m in modulos}

        assert "inicio" in mapa
        assert mapa["inicio"]["accesos"]["ADMIN"] == "editar"
        assert mapa["inicio"]["accesos"]["TRABAJADOR"] == "ver"

        # OPERADOR no ve usuarios; AUDITOR ve kardex solo lectura.
        assert mapa["usuarios"]["accesos"]["OPERADOR"] == "ninguno"
        assert mapa["kardex"]["accesos"]["OPERADOR"] == "ver"
        assert mapa["kardex"]["accesos"]["AUDITOR"] == "ver"

    async def test_actualizar_acceso_persiste(self, client):
        r = await client.get("/api/v1/seguridad/matriz")
        assert r.status_code == 200
        usuarios = next(m for m in r.json()["modulos"] if m["clave"] == "usuarios")
        assert usuarios["accesos"]["OPERADOR"] == "ninguno"

        r = await client.put(
            "/api/v1/seguridad/matriz",
            json={"rol": "OPERADOR", "modulo": "usuarios", "acceso": "ver"},
        )
        assert r.status_code == 200
        assert r.json()["clave"] == "usuarios"
        assert r.json()["accesos"]["OPERADOR"] == "ver"

        r = await client.get("/api/v1/seguridad/matriz")
        usuarios = next(m for m in r.json()["modulos"] if m["clave"] == "usuarios")
        assert usuarios["accesos"]["OPERADOR"] == "ver"

    async def test_acceso_invalido_rechazado(self, client):
        r = await client.put(
            "/api/v1/seguridad/matriz",
            json={"rol": "OPERADOR", "modulo": "usuarios", "acceso": "borrar-todo"},
        )
        assert r.status_code == 422

        r = await client.put(
            "/api/v1/seguridad/matriz",
            json={"rol": "NOEXISTE", "modulo": "usuarios", "acceso": "ver"},
        )
        assert r.status_code == 400

        r = await client.put(
            "/api/v1/seguridad/matriz",
            json={"rol": "OPERADOR", "modulo": "modulo_fantasma", "acceso": "ver"},
        )
        assert r.status_code == 400
