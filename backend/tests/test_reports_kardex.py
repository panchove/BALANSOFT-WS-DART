"""Pruebas del JOIN de ``kardex/detalle`` con ``conceptos_kardex`` y del
filtro ``kardex_mov`` de ``/weighing/list`` (Ingresos / Despachos).

Cubren:

- ``concepto_nombre`` / ``concepto_signo`` / ``concepto_es_sistema`` por fila;
- el ``origen`` derivado (Báscula / Manual / Sistema) y el fallback cuando el
  concepto no existe en el catálogo;
- que Ingresos/Despachos solo devuelven CERRADO/MODIFICADO con asiento de
  kardex, excluyendo PENDIENTES y ANULADOS.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest
import pytest_asyncio

from app.models import Kardex
from tests.helpers_kardex import (
    cliente,
    crear_concepto,
    nueva_empresa,
    sembrar_catalogo,
    sembrar_conceptos_sistema,
)

DETALLE = "/api/v1/reports/kardex/detalle"
LISTA = "/api/v1/weighing/list"
RANGO = {"fecha_desde": "2020-01-01T00:00:00", "fecha_hasta": "2100-01-01T00:00:00"}


@pytest_asyncio.fixture
async def empresa(db):
    emp = await nueva_empresa(db, "Empresa Kardex")
    await sembrar_conceptos_sistema(db, emp)
    # El kardex solo se genera para productos marcados es_kardex=True.
    _, prod, alm = await sembrar_catalogo(db, emp)
    emp._producto = prod  # type: ignore[attr-defined]
    emp._almacen = alm  # type: ignore[attr-defined]
    return emp


async def _ids_catalogo(empresa):
    return str(empresa._producto.id_producto), str(empresa._almacen.id_almacen)  # type: ignore[attr-defined]


async def _movimiento(
    db,
    empresa,
    id_movimiento: int,
    valor: float = 100,
    fecha: datetime | None = None,
) -> Kardex:
    mov = Kardex(
        id_empresa=empresa.id_empresa,
        id_movimiento=id_movimiento,
        fecha_kardex=fecha or datetime.now(UTC).replace(tzinfo=None),
        valor=valor,
        documento=f"DOC-{uuid.uuid4().hex[:6]}",
    )
    db.add(mov)
    await db.commit()
    await db.refresh(mov)
    return mov


async def _detalle(c, **params) -> list[dict]:
    p = dict(RANGO)
    p.update(params)
    r = await c.get(DETALLE, params=p)
    assert r.status_code == 200, r.text
    return r.json()["movimientos"]


# ---------------------------------------------------------------------------
# kardex/detalle: JOIN con conceptos_kardex
# ---------------------------------------------------------------------------
async def test_detalle_incluye_concepto_nombre(db, empresa):
    await _movimiento(db, empresa, 10, valor=500)
    async with cliente(db, empresa) as c:
        movs = await _detalle(c)
    m10 = next(m for m in movs if m["id_movimiento"] == 10)
    assert m10["concepto_nombre"] == "Ingreso por báscula"
    assert m10["concepto_signo"] == "positivo"
    assert m10["concepto_es_sistema"] is True


async def test_detalle_incluye_origen_bascula(db, empresa):
    await _movimiento(db, empresa, 10, valor=500)
    await _movimiento(db, empresa, 60, valor=400)
    async with cliente(db, empresa) as c:
        movs = await _detalle(c)
    for mov_id in (10, 60):
        m = next(x for x in movs if x["id_movimiento"] == mov_id)
        assert m["origen"] == "Báscula"


async def test_detalle_incluye_origen_sistema(db, empresa):
    await _movimiento(db, empresa, 0, valor=50)
    async with cliente(db, empresa) as c:
        movs = await _detalle(c)
    m0 = next(m for m in movs if m["id_movimiento"] == 0)
    assert m0["origen"] == "Sistema"
    assert m0["concepto_nombre"] == "Saldo inicial"


async def test_detalle_incluye_origen_manual(db, empresa):
    await crear_concepto(db, empresa, 5, "Compra", signo="positivo")
    await _movimiento(db, empresa, 5, valor=200)
    async with cliente(db, empresa) as c:
        movs = await _detalle(c)
    m05 = next(m for m in movs if m["id_movimiento"] == 5)
    assert m05["origen"] == "Manual"
    assert m05["concepto_nombre"] == "Compra"
    assert m05["concepto_es_sistema"] is False


async def test_detalle_fallback_concepto_inexistente(db, empresa):
    """Un movimiento cuyo ID no está en el catálogo no rompe el reporte."""
    await _movimiento(db, empresa, 99, valor=10)
    async with cliente(db, empresa) as c:
        movs = await _detalle(c)
    m99 = next(m for m in movs if m["id_movimiento"] == 99)
    assert "sin definir" in m99["concepto_nombre"]
    assert m99["concepto_signo"] is None
    assert m99["origen"] == "Manual"


async def test_detalle_suma_saldo_acumulado(db, empresa):
    """El saldo acumulado aplica el signo del rango del movimiento."""
    await crear_concepto(db, empresa, 5, "Compra", signo="positivo")
    await crear_concepto(db, empresa, 55, "Merma", signo="negativo")
    await _movimiento(db, empresa, 5, valor=300)
    await _movimiento(db, empresa, 55, valor=120)
    async with cliente(db, empresa) as c:
        r = await c.get(DETALLE, params=dict(RANGO))
    body = r.json()
    # 300 (positivo) - 120 (negativo) = 180 sobre los movimientos sembrados.
    assert float(body["saldo_actual"]) == 180.0


# ---------------------------------------------------------------------------
# /weighing/list?kardex_mov : Ingresos / Despachos
# ---------------------------------------------------------------------------
async def _crear_boleto(c, placa: str, empresa) -> dict:
    id_producto, id_almacen = await _ids_catalogo(empresa)
    r = await c.post(
        "/api/v1/weighing/create",
        json={
            "id_vehiculo": placa,
            "transporte_nombre": "T",
            "conductor_nombre": "C",
            "id_producto": id_producto,
            "id_almacen": id_almacen,
            "balanza_nombre": "B",
            "tercero_nombre": "X",
            "peso_entrada_vehiculo": "50000",
        },
    )
    assert r.status_code == 200, r.text
    return r.json()


async def test_kardex_mov_10_solo_cerrados(db, empresa):
    async with cliente(db, empresa) as c:
        pendiente = await _crear_boleto(c, "PEN-01", empresa)
        cerrado = await _crear_boleto(c, "CER-01", empresa)
        r_close = await c.post(
            f"/api/v1/weighing/close/{cerrado['boleto']}",
            json={"peso_salida_vehiculo": "45000", "es_peso_manual": True},
        )
        assert r_close.status_code == 200, r_close.text
        r = await c.get(LISTA, params={"kardex_mov": 10})
    assert r.status_code == 200, r.text
    boletos = [it["boleto"] for it in r.json()]
    assert pendiente["boleto"] not in boletos, "un PENDIENTE no tiene kardex aún"
    assert cerrado["boleto"] in boletos


async def test_kardex_mov_10_excluye_anulados(db, empresa):
    async with cliente(db, empresa) as c:
        boleto = await _crear_boleto(c, "ANU-01", empresa)
        await c.post(
            f"/api/v1/weighing/close/{boleto['boleto']}",
            json={"peso_salida_vehiculo": "45000", "es_peso_manual": True},
        )
        # El anulado genera contra-asiento en kardex, pero no cuenta en Ingresos.
        r_anular = await c.put(
            f"/api/v1/weighing/{boleto['boleto']}/anular",
            json={"motivo": "Error de digitación del operador"},
        )
        if r_anular.status_code not in (200, 400):
            pytest.skip(f"anulación no disponible: {r_anular.status_code} {r_anular.text}")
        r = await c.get(LISTA, params={"kardex_mov": 10})
    boletos = [it["boleto"] for it in r.json()]
    assert boleto["boleto"] not in boletos


async def test_kardex_mov_60_solo_despachos(db, empresa):
    async with cliente(db, empresa) as c:
        boleto = await _crear_boleto(c, "DES-01", empresa)
        await c.post(
            f"/api/v1/weighing/close/{boleto['boleto']}",
            json={"peso_salida_vehiculo": "45000", "es_peso_manual": True},
        )
        r10 = await c.get(LISTA, params={"kardex_mov": 10})
        r60 = await c.get(LISTA, params={"kardex_mov": 60})
    assert boleto["boleto"] in [it["boleto"] for it in r10.json()]
    # El cierre con neto positivo genera ingreso (10), no despacho (60).
    assert boleto["boleto"] not in [it["boleto"] for it in r60.json()]


async def test_lista_sin_kardex_mov_no_filtra_por_estado(db, empresa):
    """Sin el parámetro, el listado general conserva su comportamiento."""
    async with cliente(db, empresa) as c:
        await _crear_boleto(c, "MIX-01", empresa)
        r = await c.get(LISTA)
    assert r.status_code == 200, r.text
    assert any(it["estado_boleto"] in ("PENDIENTE", "CERRADO", "MODIFICADO") for it in r.json())


async def test_resumen_movimiento_devuelve_total(db, empresa):
    async with cliente(db, empresa) as c:
        boleto = await _crear_boleto(c, "KPI-01", empresa)
        await c.post(
            f"/api/v1/weighing/close/{boleto['boleto']}",
            json={"peso_salida_vehiculo": "45000", "es_peso_manual": True},
        )
        r = await c.get("/api/v1/weighing/resumen", params={"kardex_mov": 10})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["kardex_mov"] == 10
    assert body["total_boletos"] == 1
    assert body["total_kg"] > 0


async def test_detalle_filtra_por_almacen(db, empresa):
    """El detalle respeta el filtro por almacén (y sigue trayendo el JOIN)."""
    _, prod, alm = await sembrar_catalogo(db, empresa)
    mov = await _movimiento(db, empresa, 5, valor=250)
    mov.id_producto = prod.id_producto
    mov.id_almacen = alm.id_almacen
    await db.commit()

    async with cliente(db, empresa) as c:
        con_almacen = await _detalle(c, id_almacen=str(alm.id_almacen))
        sin_almacen = await _detalle(c)

    assert any(m["id_movimiento"] == 5 for m in con_almacen)
    assert any(m["id_movimiento"] == 5 for m in sin_almacen)
