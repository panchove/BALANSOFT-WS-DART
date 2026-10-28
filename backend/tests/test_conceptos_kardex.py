"""Pruebas del CRUD de ``conceptos_kardex`` (catálogo de IDs 0-99).

Cubren las reglas de negocio del módulo:

- coherencia ID ↔ signo (0=inicial, 01-49=positivo, 50-99=negativo);
- los conceptos del sistema (0/10/60) no se crean, ni se les cambia el signo,
  ni se borran;
- no se borra un concepto con movimientos (soft delete = desactivar);
- filtros por estado y signo;
- aislamiento multi-tenant por ``id_empresa``.
"""

from __future__ import annotations

import pytest
import pytest_asyncio

from tests.helpers_kardex import cliente, nueva_empresa, sembrar_conceptos_sistema

URL = "/api/v1/conceptos-kardex"


@pytest_asyncio.fixture
async def empresa(db):
    """Empresa con los conceptos del sistema sembrados (como la migración 031)."""
    emp = await nueva_empresa(db, "Empresa Test")
    await sembrar_conceptos_sistema(db, emp)
    return emp


@pytest_asyncio.fixture
async def empresa_b(db):
    emp = await nueva_empresa(db, "Empresa B")
    await sembrar_conceptos_sistema(db, emp)
    return emp


async def test_crear_concepto_positivo_valido(db, empresa):
    async with cliente(db, empresa) as c:
        r = await c.post(
            URL,
            json={
                "id_concepto": 5,
                "nombre": "Compra",
                "signo": "positivo",
                "aplica_a": "INGRESO",
                "activo": True,
            },
        )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["id_concepto"] == 5
    assert body["signo"] == "positivo"
    assert body["es_sistema"] is False


async def test_crear_concepto_negativo_valido(db, empresa):
    async with cliente(db, empresa) as c:
        r = await c.post(
            URL,
            json={
                "id_concepto": 55,
                "nombre": "Merma",
                "signo": "negativo",
                "aplica_a": "AJUSTE",
            },
        )
    assert r.status_code == 201, r.text
    assert r.json()["signo"] == "negativo"


async def test_crear_concepto_signo_incoherente(db, empresa):
    """El ID 5 es del rango positivo: no admite signo negativo."""
    async with cliente(db, empresa) as c:
        r = await c.post(
            URL,
            json={"id_concepto": 5, "nombre": "X", "signo": "negativo", "aplica_a": "AMBOS"},
        )
    assert r.status_code == 422, r.text


async def test_crear_concepto_signo_incoherente_rango_negativo(db, empresa):
    """El ID 55 es del rango negativo: no admite signo positivo."""
    async with cliente(db, empresa) as c:
        r = await c.post(
            URL,
            json={"id_concepto": 55, "nombre": "X", "signo": "positivo", "aplica_a": "AMBOS"},
        )
    assert r.status_code == 422, r.text


@pytest.mark.parametrize("id_concepto,signo", [(0, "inicial"), (10, "positivo"), (60, "negativo")])
async def test_crear_concepto_del_sistema_rechazado(db, empresa, id_concepto, signo):
    """0/10/60 existen por seed y no se pueden crear de nuevo."""
    async with cliente(db, empresa) as c:
        r = await c.post(
            URL,
            json={"id_concepto": id_concepto, "nombre": "Intento", "signo": signo},
        )
    assert r.status_code == 409, r.text


async def test_crear_concepto_duplicado(db, empresa):
    payload = {
        "id_concepto": 7,
        "nombre": "Devolución",
        "signo": "positivo",
        "aplica_a": "INGRESO",
    }
    async with cliente(db, empresa) as c:
        r1 = await c.post(URL, json=payload)
        assert r1.status_code == 201, r1.text
        r2 = await c.post(URL, json=payload)
    assert r2.status_code == 409, r2.text


async def test_crear_concepto_fuera_de_rango(db, empresa):
    async with cliente(db, empresa) as c:
        r = await c.post(
            URL, json={"id_concepto": 150, "nombre": "X", "signo": "positivo"}
        )
    assert r.status_code == 422, r.text


async def test_editar_concepto_sistema_cambiar_signo(db, empresa):
    """El signo lo determina el rango del ID: cambiarlo se rechaza de forma
    explícita (422) en lugar de ignorarse en silencio."""
    async with cliente(db, empresa) as c:
        r = await c.put(f"{URL}/10", json={"signo": "negativo"})
    assert r.status_code == 422, r.text


async def test_editar_concepto_sistema_cambiar_nombre(db, empresa):
    async with cliente(db, empresa) as c:
        r = await c.put(f"{URL}/10", json={"nombre": "Ingreso (renombrado)"})
    assert r.status_code == 200, r.text
    assert r.json()["nombre"] == "Ingreso (renombrado)"
    # El signo del sistema no cambia al renombrar.
    assert r.json()["signo"] == "positivo"


async def test_borrar_concepto_sistema(db, empresa):
    async with cliente(db, empresa) as c:
        r = await c.delete(f"{URL}/10")
    assert r.status_code == 409, r.text


async def test_listar_solo_activos(db, empresa):
    async with cliente(db, empresa) as c:
        await c.post(
            URL,
            json={"id_concepto": 12, "nombre": "Alta", "signo": "positivo"},
        )
        await c.post(
            URL,
            json={"id_concepto": 13, "nombre": "Baja", "signo": "positivo", "activo": False},
        )
        r_activos = await c.get(URL, params={"activo": "true"})
        r_todos = await c.get(URL)
    nombres_activos = [x["nombre"] for x in r_activos.json()]
    nombres_todos = [x["nombre"] for x in r_todos.json()]
    assert "Alta" in nombres_activos
    assert "Baja" not in nombres_activos
    assert "Baja" in nombres_todos


async def test_listar_por_signo(db, empresa):
    async with cliente(db, empresa) as c:
        await c.post(URL, json={"id_concepto": 14, "nombre": "Pos", "signo": "positivo"})
        await c.post(URL, json={"id_concepto": 64, "nombre": "Neg", "signo": "negativo"})
        r = await c.get(URL, params={"signo": "negativo"})
    ids = [x["id_concepto"] for x in r.json()]
    assert 64 in ids
    assert 14 not in ids


async def test_concepto_del_sistema_sembrado(db, empresa):
    """La migración 031 deja 0/10/60 por empresa, marcados como sistema."""
    async with cliente(db, empresa) as c:
        r = await c.get(URL)
    sistema = {x["id_concepto"] for x in r.json() if x["es_sistema"]}
    assert {0, 10, 60} <= sistema


async def test_aislamiento_empresa(db, empresa, empresa_b):
    """La empresa B no ve ni puede tocar los conceptos de la empresa A."""
    async with cliente(db, empresa) as c:
        await c.post(
            URL, json={"id_concepto": 15, "nombre": "Solo A", "signo": "positivo"}
        )
    async with cliente(db, empresa_b) as c_b:
        r = await c_b.get(URL)
        ids = [x["id_concepto"] for x in r.json()]
        assert 15 not in ids
        # El intento de escritura sobre el ID ajeno no lo modifica.
        r_put = await c_b.put(f"{URL}/15", json={"nombre": "Intento B"})
        assert r_put.status_code in (403, 404, 422)
    async with cliente(db, empresa) as c:
        r_a = await c.get(URL)
    assert any(x["nombre"] == "Solo A" for x in r_a.json())


async def test_crear_concepto_sin_nombre(db, empresa):
    async with cliente(db, empresa) as c:
        r = await c.post(URL, json={"id_concepto": 16, "signo": "positivo"})
    assert r.status_code == 422, r.text
