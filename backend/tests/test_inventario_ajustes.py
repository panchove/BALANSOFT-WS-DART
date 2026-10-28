"""Pruebas del ajuste manual de inventario con ``id_concepto`` (migración 031).

Reglas verificadas:

- el movimiento se inserta en ``kardex`` con ``id_movimiento = id_concepto``
  (ya no con 10/60 fijos);
- el concepto debe existir, estar activo y no ser del sistema;
- coherencia estricta signo ↔ cantidad (un concepto positivo exige cantidad > 0
  y uno negativo < 0);
- el ajuste queda auditado con el motivo.
"""

from __future__ import annotations

import pytest_asyncio
from sqlalchemy import select

from app.models import Kardex
from tests.helpers_kardex import (
    cliente,
    crear_concepto,
    nueva_empresa,
    sembrar_catalogo,
    sembrar_conceptos_sistema,
)

URL = "/api/v1/inventario/ajustes"
KARDEX = "/api/v1/reports/kardex/detalle"
AUDITORIA = "/api/v1/auditoria"


@pytest_asyncio.fixture
async def empresa(db):
    emp = await nueva_empresa(db, "Empresa Ajustes")
    await sembrar_conceptos_sistema(db, emp)
    return emp


def _rango_kardex() -> dict:
    """Rango amplio: el endpoint de detalle exige fecha_desde/fecha_hasta."""
    return {
        "fecha_desde": "2020-01-01T00:00:00",
        "fecha_hasta": "2100-01-01T00:00:00",
    }


@pytest_asyncio.fixture
async def producto_kardex(db, empresa):
    _, prod, alm = await sembrar_catalogo(db, empresa)
    return prod, alm


@pytest_asyncio.fixture
async def concepto_positivo_5(db, empresa):
    return await crear_concepto(db, empresa, 5, "Compra", signo="positivo")


@pytest_asyncio.fixture
async def concepto_negativo_55(db, empresa):
    return await crear_concepto(db, empresa, 55, "Merma", signo="negativo")


def _payload_ajuste(**kwargs) -> dict:
    base = {
        "id_concepto": 5,
        "cantidad": 200,
        "motivo": "Compra inicial de prueba",
    }
    base.update(kwargs)
    return base


async def test_ajuste_con_concepto_positivo_valido(
    db, empresa, producto_kardex, concepto_positivo_5
):
    prod, alm = producto_kardex
    async with cliente(db, empresa) as c:
        r = await c.post(
            URL,
            json=_payload_ajuste(
                id_producto=str(prod.id_producto), id_almacen=str(alm.id_almacen)
            ),
        )
        assert r.status_code == 200, r.text
        assert r.json()["id_movimiento"] == 5
        parametros = _rango_kardex()
        parametros["producto"] = str(prod.id_producto)
        d = await c.get(KARDEX, params=parametros)
    assert d.status_code == 200, d.text
    movs = d.json()["movimientos"]
    fila = next(m for m in movs if m["id_movimiento"] == 5)
    assert fila["valor"] == 200
    assert fila["documento"].startswith("AJUSTE-")
    assert fila["concepto_nombre"] == "Compra"
    assert fila["origen"] == "Manual"


async def test_ajuste_con_concepto_negativo_valido(
    db, empresa, producto_kardex, concepto_negativo_55
):
    prod, alm = producto_kardex
    async with cliente(db, empresa) as c:
        r = await c.post(
            URL,
            json=_payload_ajuste(
                id_concepto=55,
                cantidad=-15,
                motivo="Merma por humedad",
                id_producto=str(prod.id_producto),
                id_almacen=str(alm.id_almacen),
            ),
        )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["id_movimiento"] == 55
    assert float(body["valor"]) == 15.0  # se almacena en valor absoluto


async def test_ajuste_con_concepto_positivo_y_cantidad_negativa(
    db, empresa, producto_kardex, concepto_positivo_5
):
    prod, alm = producto_kardex
    async with cliente(db, empresa) as c:
        r = await c.post(
            URL,
            json=_payload_ajuste(
                cantidad=-50,
                motivo="Motivo válido pero signo mal",
                id_producto=str(prod.id_producto),
                id_almacen=str(alm.id_almacen),
            ),
        )
    assert r.status_code == 422, r.text
    assert "positivo" in r.json()["detail"].lower()


async def test_ajuste_con_concepto_negativo_y_cantidad_positiva(
    db, empresa, producto_kardex, concepto_negativo_55
):
    prod, alm = producto_kardex
    async with cliente(db, empresa) as c:
        r = await c.post(
            URL,
            json=_payload_ajuste(
                id_concepto=55,
                cantidad=50,
                motivo="Motivo válido pero signo mal",
                id_producto=str(prod.id_producto),
                id_almacen=str(alm.id_almacen),
            ),
        )
    assert r.status_code == 422, r.text
    assert "negativo" in r.json()["detail"].lower()


async def test_ajuste_con_concepto_sistema_10(db, empresa, producto_kardex):
    """0/10/60 son del sistema: no se usan en ajustes manuales."""
    prod, alm = producto_kardex
    async with cliente(db, empresa) as c:
        r = await c.post(
            URL,
            json=_payload_ajuste(
                id_concepto=10,
                cantidad=100,
                motivo="Intento con concepto del sistema",
                id_producto=str(prod.id_producto),
                id_almacen=str(alm.id_almacen),
            ),
        )
    assert r.status_code == 422, r.text
    assert "sistema" in r.json()["detail"].lower()


async def test_ajuste_con_concepto_inicial_0(db, empresa, producto_kardex):
    prod, alm = producto_kardex
    async with cliente(db, empresa) as c:
        r = await c.post(
            URL,
            json=_payload_ajuste(
                id_concepto=0,
                cantidad=100,
                motivo="Intento con saldo inicial",
                id_producto=str(prod.id_producto),
                id_almacen=str(alm.id_almacen),
            ),
        )
    assert r.status_code == 422, r.text


async def test_ajuste_con_concepto_inexistente(db, empresa, producto_kardex):
    prod, alm = producto_kardex
    async with cliente(db, empresa) as c:
        r = await c.post(
            URL,
            json=_payload_ajuste(
                id_concepto=99,
                cantidad=100,
                motivo="Concepto inexistente en el catálogo",
                id_producto=str(prod.id_producto),
                id_almacen=str(alm.id_almacen),
            ),
        )
    assert r.status_code == 404, r.text
    # No debe haber dejado movimiento en kardex.
    res = await db.execute(select(Kardex))
    assert res.scalars().all() == []


async def test_ajuste_rechaza_producto_no_kardex(db, empresa, producto_kardex, concepto_positivo_5):
    """Solo productos con es_kardex=true aceptan ajustes."""
    from tests.helpers_kardex import sembrar_catalogo as _s

    _, prod, _alm = await _s(db, empresa)
    prod.es_kardex = False
    await db.commit()
    _, _p, alm = await _s(db, empresa)
    async with cliente(db, empresa) as c:
        r = await c.post(
            URL,
            json=_payload_ajuste(
                id_producto=str(prod.id_producto), id_almacen=str(alm.id_almacen)
            ),
        )
    assert r.status_code == 422, r.text
    assert "es_kardex" in r.json()["detail"].lower()


async def test_ajuste_audita_motivo_en_detalle(
    db, empresa, producto_kardex, concepto_positivo_5
):
    prod, alm = producto_kardex
    async with cliente(db, empresa) as c:
        await c.post(
            URL,
            json=_payload_ajuste(
                cantidad=200,
                motivo="Motivo rastreable 12345",
                id_producto=str(prod.id_producto),
                id_almacen=str(alm.id_almacen),
            ),
        )
        r = await c.get(AUDITORIA, params={"entidad": "kardex", "limit": 5})
    assert r.status_code == 200, r.text
    # El endpoint de auditoría devuelve la lista directamente (sin envoltorio).
    detalle = str(r.json()[0]["detalle"])
    assert "Motivo rastreable 12345" in detalle
    assert "Compra" in detalle


async def test_ajuste_no_deja_movimiento_si_falla_la_validacion(
    db, empresa, producto_kardex, concepto_positivo_5
):
    """Un ajuste rechazado no inserta nada en kardex (transacción deshecha)."""
    prod, alm = producto_kardex
    async with cliente(db, empresa) as c:
        await c.post(
            URL,
            json=_payload_ajuste(
                cantidad=-5,
                motivo="Debe fallar por signo",
                id_producto=str(prod.id_producto),
                id_almacen=str(alm.id_almacen),
            ),
        )
    res = await db.execute(select(Kardex))
    assert res.scalars().all() == []
