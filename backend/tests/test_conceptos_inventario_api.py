"""Pruebas HTTP del módulo CONCEPTOS DE INVENTARIO — migración 029.

Estrategia de ``test_indicadores_api.py``: app FastAPI fresca con overrides de
dependencias sobre la BD real de tests.

Cubre las reglas del negocio:

- El catálogo es por empresa (`conceptos_inventario`).
- El ajuste de inventario elige un concepto (`id_concepto`); su nombre se copia
  a `documento` para el histórico y el movimiento queda enlazado.
- Un concepto con movimientos de kardex **no se puede borrar** (409).
- Aislamiento multi-tenant: un concepto de otra empresa da 404 y el ajuste no
  puede usar un concepto ajeno.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from decimal import Decimal

import httpx
import pytest_asyncio
from fastapi import FastAPI

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core.database import get_db
from app.models import (
    Almacen,
    Categoria,
    ConceptoInventario,
    Empresa,
    Kardex,
    Producto,
    Usuario,
)


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
        nombre="Admin Concepto",
        email=f"admin-{uuid.uuid4().hex[:6]}@conc.demo",
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
        nombre="Operador Concepto",
        email=f"op-{uuid.uuid4().hex[:6]}@conc.demo",
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


async def _crear_concepto(
    db, empresa, nombre="Merma por derrame", **extra
) -> ConceptoInventario:
    c = ConceptoInventario(id_empresa=empresa.id_empresa, nombre=nombre, **extra)
    db.add(c)
    await db.commit()
    await db.refresh(c)
    return c


async def _crear_categoria(db, empresa) -> Categoria:
    c = Categoria(
        id_empresa=empresa.id_empresa,
        nombre=f"Categoría {uuid.uuid4().hex[:6]}",
    )
    db.add(c)
    await db.commit()
    await db.refresh(c)
    return c


async def _crear_producto(db, empresa, **extra) -> Producto:
    id_categoria = extra.pop("id_categoria", None)
    if id_categoria is None:
        id_categoria = (await _crear_categoria(db, empresa)).id_categoria
    p = Producto(
        id_empresa=empresa.id_empresa,
        nombre=extra.pop("nombre", "Producto kardex"),
        id_categoria=id_categoria,
        es_kardex=extra.pop("es_kardex", True),
        **extra,
    )
    db.add(p)
    await db.commit()
    await db.refresh(p)
    return p


async def _crear_almacen(db, empresa, **extra) -> Almacen:
    a = Almacen(
        id_empresa=empresa.id_empresa,
        nombre=extra.pop("nombre", "Almacén 1"),
        **extra,
    )
    db.add(a)
    await db.commit()
    await db.refresh(a)
    return a


async def _crear_movimiento(db, empresa, concepto, **extra) -> Kardex:
    k = Kardex(
        id_empresa=empresa.id_empresa,
        id_movimiento=extra.pop("id_movimiento", 10),
        valor=extra.pop("valor", Decimal("5.00")),
        fecha_kardex=extra.pop("fecha_kardex", datetime.now(UTC).replace(tzinfo=None)),
        id_concepto=concepto.id_concepto,
        documento=extra.pop("documento", "Merma"),
        **extra,
    )
    db.add(k)
    await db.commit()
    await db.refresh(k)
    return k


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------
class TestCrudConceptos:
    async def test_lista_vacia(self, client):
        r = await client.get("/api/v1/conceptos_inventario")
        assert r.status_code == 200
        assert r.json() == []

    async def test_crear(self, client):
        r = await client.post(
            "/api/v1/conceptos_inventario",
            json={"nombre": "Merma por derrame", "tipo_movimiento": "despacho"},
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["nombre"] == "Merma por derrame"
        assert data["tipo_movimiento"] == "despacho"
        assert data["activo"] is True

    async def test_crear_tipo_invalido_devuelve_422(self, client):
        r = await client.post(
            "/api/v1/conceptos_inventario",
            json={"nombre": "Concepto raro", "tipo_movimiento": "otro"},
        )
        assert r.status_code == 422

    async def test_operador_no_puede_crear(self, db, operador, empresa):
        app = _app_para(db, operador, empresa)
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            r = await ac.post(
                "/api/v1/conceptos_inventario",
                json={"nombre": "Concepto operador"},
            )
        assert r.status_code == 403

    async def test_actualizar(self, client, db, empresa):
        c = await _crear_concepto(db, empresa)
        r = await client.put(
            f"/api/v1/conceptos_inventario/{c.id_concepto}",
            json={"nombre": "Merma corregida", "activo": False},
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["nombre"] == "Merma corregida"
        assert data["activo"] is False

    async def test_eliminar(self, client, db, empresa):
        c = await _crear_concepto(db, empresa)
        r = await client.delete(f"/api/v1/conceptos_inventario/{c.id_concepto}")
        assert r.status_code == 204
        assert (await client.get("/api/v1/conceptos_inventario")).json() == []


# ---------------------------------------------------------------------------
# Aislamiento multi-tenant
# ---------------------------------------------------------------------------
class TestAislamiento:
    async def test_concepto_de_otra_empresa_da_404(self, client, db):
        otra = Empresa(
            nombre_fiscal=f"Otra {uuid.uuid4().hex[:6]}",
            rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        )
        db.add(otra)
        await db.commit()
        await db.refresh(otra)
        ajeno = await _crear_concepto(db, otra, nombre="Ajeno")

        r = await client.put(
            f"/api/v1/conceptos_inventario/{ajeno.id_concepto}",
            json={"nombre": "Intruso"},
        )
        assert r.status_code == 404

    async def test_lista_solo_de_la_empresa(self, client, db, empresa):
        await _crear_concepto(db, empresa, nombre="Propio")
        otra = Empresa(
            nombre_fiscal=f"Otra {uuid.uuid4().hex[:6]}",
            rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        )
        db.add(otra)
        await db.commit()
        await db.refresh(otra)
        await _crear_concepto(db, otra, nombre="Ajeno")

        r = await client.get("/api/v1/conceptos_inventario")
        assert r.status_code == 200
        nombres = [x["nombre"] for x in r.json()]
        assert nombres == ["Propio"]


# ---------------------------------------------------------------------------
# Uso desde el ajuste de inventario
# ---------------------------------------------------------------------------
class TestAjusteConConcepto:
    """Ajuste manual contra el catálogo `conceptos_kardex` (migración 031).

    El contrato cambió respecto al diseño anterior: el movimiento se identifica
    por ``id_concepto`` (int, no del sistema) y ``cantidad`` con signo; el nombre
    del concepto queda en la auditoría y el documento pasa a ``AJUSTE-*``.
    La cobertura completa vive en ``tests/test_inventario_ajustes.py``.
    """

    async def _kardex(self, db, empresa, id_concepto=5, nombre="Merma por derrame"):
        from app.models import ConceptoKardex

        concepto = ConceptoKardex(
            id_empresa=empresa.id_empresa,
            id_concepto=id_concepto,
            nombre=nombre,
            signo="negativo" if id_concepto >= 50 else "positivo",
            es_sistema=False,
            activo=True,
            aplica_a="AMBOS",
        )
        db.add(concepto)
        await db.commit()
        await db.refresh(concepto)
        return concepto

    async def test_ajuste_con_concepto_kardex_registra_movimiento(
        self, client, db, empresa
    ):
        concepto = await self._kardex(db, empresa, id_concepto=55)
        producto = await _crear_producto(db, empresa)
        almacen = await _crear_almacen(db, empresa)

        r = await client.post(
            "/api/v1/inventario/ajustes",
            json={
                "id_concepto": concepto.id_concepto,
                "id_producto": str(producto.id_producto),
                "id_almacen": str(almacen.id_almacen),
                "cantidad": "-12.50",
                "motivo": "Merma por derrame en patio",
            },
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["id_movimiento"] == 55
        assert data["valor"] == "12.50"
        assert data["documento"].startswith("AJUSTE-")

        # El nombre del concepto queda trazado en la auditoría.
        aud = await client.get("/api/v1/auditoria", params={"entidad": "kardex"})
        assert aud.status_code == 200, aud.text
        assert concepto.nombre in str(aud.json()[0]["detalle"])

    async def test_ajuste_sin_concepto_devuelve_422(self, client, db, empresa):
        producto = await _crear_producto(db, empresa)
        almacen = await _crear_almacen(db, empresa)

        r = await client.post(
            "/api/v1/inventario/ajustes",
            json={
                "id_producto": str(producto.id_producto),
                "id_almacen": str(almacen.id_almacen),
                "valor_kg": "10",
            },
        )
        assert r.status_code == 422

    async def test_ajuste_con_concepto_ajeno_da_404(self, client, db, empresa):
        otra = Empresa(
            nombre_fiscal=f"Otra {uuid.uuid4().hex[:6]}",
            rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        )
        db.add(otra)
        await db.commit()
        await db.refresh(otra)
        # El concepto existe, pero en otra empresa (no debe filtrarse).
        await self._kardex(db, otra, id_concepto=44, nombre="Ajeno")
        producto = await _crear_producto(db, empresa)
        almacen = await _crear_almacen(db, empresa)

        r = await client.post(
            "/api/v1/inventario/ajustes",
            json={
                "id_concepto": 44,
                "id_producto": str(producto.id_producto),
                "id_almacen": str(almacen.id_almacen),
                "cantidad": "10",
                "motivo": "Concepto que no es de esta empresa",
            },
        )
        assert r.status_code == 404


# ---------------------------------------------------------------------------
# Borrado protegido
# ---------------------------------------------------------------------------
class TestBorradoProtegido:
    async def test_concepto_usado_no_se_puede_borrar(self, client, db, empresa):
        concepto = await _crear_concepto(db, empresa)
        await _crear_movimiento(db, empresa, concepto)

        r = await client.delete(f"/api/v1/conceptos_inventario/{concepto.id_concepto}")
        assert r.status_code == 409
        # Sigue existiendo.
        assert len((await client.get("/api/v1/conceptos_inventario")).json()) == 1
