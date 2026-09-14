"""Pruebas del servicio de reportes (agregación SQL).

Regla clave: los boletos ANULADOS no cuentan en ningún reporte de
ingresos/despachos.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal

from app.models import BoletoPesaje, Kardex, Producto, Tercero, Transporte
from app.services.report_service import ReportService

DAY = date(2026, 9, 8)


async def _crear_kardex_mov(db, empresa, *, movimiento, valor, producto=None,
                            almacen=None, fecha=None) -> None:
    db.add(
        Kardex(
            id_empresa=empresa.id_empresa,
            id_movimiento=movimiento,
            fecha_kardex=fecha or datetime(2026, 9, 8, 12, 0),
            id_producto=producto,
            id_almacen=almacen,
            valor=Decimal(valor),
            documento="DOC",
        )
    )
    await db.commit()


async def _crear_producto(db, empresa, nombre="Cemento") -> str:
    prod = Producto(
        id_empresa=empresa.id_empresa,
        nombre=nombre,
        unidad_medida="TON",
    )
    db.add(prod)
    await db.commit()
    await db.refresh(prod)
    return str(prod.id_producto)


async def _crear_transporte(db, empresa, *, nombre="Transportista Test") -> str:
    t = Transporte(
        id_empresa=empresa.id_empresa,
        razon_social=nombre,
    )
    db.add(t)
    await db.commit()
    await db.refresh(t)
    return str(t.id_transporte)


async def _crear_tercero(db, empresa, *, tipo="CLIENTE", nombre="Tercero Test") -> str:
    t = Tercero(
        id_empresa=empresa.id_empresa,
        tipo=tipo,
        razon_social=nombre,
    )
    db.add(t)
    await db.commit()
    await db.refresh(t)
    return str(t.id_tercero)


async def _crear_boleto(db, empresa, *, placa="XYZ999", peso_neto="5000",
                        estado=BoletoPesaje.ESTADO_CERRADO,
                        fecha=datetime(2026, 9, 8, 10, 0)) -> BoletoPesaje:
    p = BoletoPesaje(
        boleto=uuid.uuid4(),
        numero_boleto=None,
        id_empresa=empresa.id_empresa,
        id_vehiculo=placa,
        fecha_hora_entrada=fecha,
        peso_entrada_vehiculo=Decimal("48000"),
        peso_entrada_remolque=None,
        peso_total_entrada=Decimal("48000"),
        peso_total_salida=Decimal("43000"),
        peso_salida_vehiculo=Decimal("43000"),
        peso_neto=Decimal(peso_neto),
        estado_boleto=estado,
        id_producto=None,
    )
    db.add(p)
    await db.commit()
    await db.refresh(p)
    return p


async def _crear_boleto_avanzado(
    db,
    empresa,
    *,
    placa="ADV999",
    peso_neto="5000",
    estado=BoletoPesaje.ESTADO_CERRADO,
    fecha=datetime(2026, 9, 8, 10, 0),
    id_transporte=None,
    id_tercero=None,
    tipo_tercero=None,
) -> BoletoPesaje:
    p = BoletoPesaje(
        boleto=uuid.uuid4(),
        numero_boleto=None,
        id_empresa=empresa.id_empresa,
        id_vehiculo=placa,
        fecha_hora_entrada=fecha,
        peso_entrada_vehiculo=Decimal("48000"),
        peso_entrada_remolque=None,
        peso_total_entrada=Decimal("48000"),
        peso_total_salida=Decimal("43000"),
        peso_salida_vehiculo=Decimal("43000"),
        peso_neto=Decimal(peso_neto),
        estado_boleto=estado,
        id_transporte=uuid.UUID(id_transporte) if id_transporte else None,
        id_tercero=uuid.UUID(id_tercero) if id_tercero else None,
        tipo_tercero=tipo_tercero,
    )
    db.add(p)
    await db.commit()
    await db.refresh(p)
    return p


class TestDaily:
    async def test_vacia(self, db, empresa):
        r = await ReportService().daily(db, empresa, DAY)
        assert r["total_pesajes"] == 0
        assert r["peso_neto_total"] == 0
        assert r["por_producto"] == []

    async def test_suma_y_contabiliza(self, db, empresa):
        await _crear_boleto(db, empresa, peso_neto="1000")
        await _crear_boleto(db, empresa, placa="AAA", peso_neto="2000")
        r = await ReportService().daily(db, empresa, DAY)
        assert r["total_pesajes"] == 2
        assert r["cerrados"] == 2
        assert r["peso_neto_total"] == 3000.0

    async def test_anulado_no_cuenta(self, db, empresa):
        await _crear_boleto(db, empresa, peso_neto="1000")
        await _crear_boleto(db, empresa, placa="ANU", peso_neto="999999",
                            estado=BoletoPesaje.ESTADO_ANULADO)
        r = await ReportService().daily(db, empresa, DAY)
        assert r["total_pesajes"] == 1
        assert r["peso_neto_total"] == 1000.0


class TestMonthly:
    async def test_acumula_mes_y_por_dia(self, db, empresa):
        await _crear_boleto(db, empresa, peso_neto="500",
                            fecha=datetime(2026, 9, 1, 9, 0))
        await _crear_boleto(db, empresa, placa="B", peso_neto="1500",
                            fecha=datetime(2026, 9, 8, 9, 0))
        r = await ReportService().monthly(db, empresa, 2026, 9)
        assert r["total_pesajes"] == 2
        assert r["peso_neto_total"] == 2000.0
        assert len(r["por_dia"]) == 2


class TestVehicle:
    async def test_filtra_por_placa_y_rango(self, db, empresa):
        await _crear_boleto(db, empresa, placa="VM-100", peso_neto="300")
        await _crear_boleto(db, empresa, placa="VM-200", peso_neto="700")
        r = await ReportService().vehicle(
            db, empresa, "VM-100",
            datetime(2026, 9, 1), datetime(2026, 9, 30),
        )
        assert r["total_pesajes"] == 1
        assert r["peso_neto_total"] == 300.0
        assert r["peso_promedio"] == 300.0

    async def test_vehiculo_sin_pesajes(self, db, empresa):
        r = await ReportService().vehicle(
            db, empresa, "NO-EXISTE",
            datetime(2026, 9, 1), datetime(2026, 9, 30),
        )
        assert r["total_pesajes"] == 0
        assert r["peso_promedio"] is None


class TestKardexSaldo:
    async def test_saldo_vacio(self, db, empresa):
        r = await ReportService().kardex_saldo(
            db, empresa, datetime(2026, 9, 8, 12, 0)
        )
        assert r["saldo_total"] == 0
        assert r["por_producto"] == []

    async def test_ingreso_y_despacho_sumados_con_signo(self, db, empresa):
        # INGRESO POR BASCULA (10, positivo) y DESPACHO POR BASCULA (60, negativo)
        await _crear_kardex_mov(db, empresa, movimiento=10, valor="5000")
        await _crear_kardex_mov(db, empresa, movimiento=60, valor="1500")
        r = await ReportService().kardex_saldo(
            db, empresa, datetime(2026, 9, 8, 12, 0)
        )
        assert r["saldo_total"] == 3500.0

    async def test_inverso_cancela_movimiento_original(self, db, empresa):
        # Anulado CERRADO: se conserva el 10 original y se añade el inverso 60
        await _crear_kardex_mov(db, empresa, movimiento=10, valor="5000")
        await _crear_kardex_mov(db, empresa, movimiento=60, valor="5000")
        r = await ReportService().kardex_saldo(
            db, empresa, datetime(2026, 9, 8, 12, 0)
        )
        assert r["saldo_total"] == 0.0

    async def test_filtro_a_fecha_de_corte(self, db, empresa):
        await _crear_kardex_mov(
            db, empresa, movimiento=10, valor="5000",
            fecha=datetime(2026, 9, 8, 12, 0),
        )
        await _crear_kardex_mov(
            db, empresa, movimiento=10, valor="999",
            fecha=datetime(2026, 9, 9, 12, 0),
        )
        # Corte antes del segundo movimiento: solo cuenta el primero
        r = await ReportService().kardex_saldo(
            db, empresa, datetime(2026, 9, 8, 23, 0)
        )
        assert r["saldo_total"] == 5000.0


class TestKardexDetalle:
    async def test_detalle_vacio(self, db, empresa):
        r = await ReportService().kardex_detalle(
            db, empresa,
            datetime(2026, 9, 1), datetime(2026, 9, 30),
        )
        assert r["saldo_inicial"] == 0.0
        assert r["saldo_actual"] == 0.0
        assert r["movimientos"] == []

    async def test_saldo_acumulado_por_movimiento(self, db, empresa):
        # Movimiento previo al rango => saldo inicial
        await _crear_kardex_mov(
            db, empresa, movimiento=10, valor="1000",
            fecha=datetime(2026, 9, 1, 12, 0),
        )
        await _crear_kardex_mov(
            db, empresa, movimiento=10, valor="500",
            fecha=datetime(2026, 9, 2, 12, 0),
        )
        await _crear_kardex_mov(
            db, empresa, movimiento=60, valor="200",
            fecha=datetime(2026, 9, 3, 12, 0),
        )
        r = await ReportService().kardex_detalle(
            db, empresa,
            datetime(2026, 9, 2), datetime(2026, 9, 3, 23, 59, 59),
        )
        assert r["saldo_inicial"] == 1000.0
        assert len(r["movimientos"]) == 2
        assert r["movimientos"][0]["id_movimiento"] == 10
        assert r["movimientos"][0]["stock"] == 1500.0
        assert r["movimientos"][1]["id_movimiento"] == 60
        assert r["movimientos"][1]["stock"] == 1300.0
        assert r["saldo_actual"] == 1300.0

    async def test_detalle_filtra_por_producto(self, db, empresa):
        prod_1 = await _crear_producto(db, empresa, nombre="Cemento P-1")
        prod_2 = await _crear_producto(db, empresa, nombre="Clinker P-2")
        await _crear_kardex_mov(db, empresa, movimiento=10, valor="500",
                                producto=prod_1)
        await _crear_kardex_mov(db, empresa, movimiento=10, valor="900",
                                producto=prod_2)
        r = await ReportService().kardex_detalle(
            db, empresa,
            datetime(2026, 9, 1), datetime(2026, 9, 30),
            id_producto=prod_1,
        )
        assert len(r["movimientos"]) == 1
        assert r["movimientos"][0]["id_producto"] == prod_1
        assert r["saldo_actual"] == 500.0


class TestTransportista:
    async def test_ranking_por_volumen(self, db, empresa):
        tid = await _crear_transporte(db, empresa, nombre="Transporte A")
        await _crear_boleto_avanzado(
            db, empresa, peso_neto="2000", id_transporte=tid,
        )
        await _crear_boleto_avanzado(
            db, empresa, peso_neto="8000", id_transporte=tid,
        )
        r = await ReportService().transportista(
            db, empresa,
            datetime(2026, 9, 1), datetime(2026, 9, 30),
        )
        assert r["total_transportistas"] == 1
        t = r["transportistas"][0]
        assert t["razon_social"] == "Transporte A"
        assert t["total_pesajes"] == 2
        assert t["peso_neto_total"] == 10000.0
        assert t["peso_promedio"] == 5000.0

    async def test_excluye_anulados(self, db, empresa):
        tid = await _crear_transporte(db, empresa)
        await _crear_boleto_avanzado(
            db, empresa, peso_neto="99999", id_transporte=tid,
            estado=BoletoPesaje.ESTADO_ANULADO,
        )
        r = await ReportService().transportista(
            db, empresa,
            datetime(2026, 9, 1), datetime(2026, 9, 30),
        )
        assert r["total_transportistas"] == 0

    async def test_sin_transportista_omitiendo(self, db, empresa):
        await _crear_boleto_avanzado(db, empresa, peso_neto="1000")
        r = await ReportService().transportista(
            db, empresa,
            datetime(2026, 9, 1), datetime(2026, 9, 30),
        )
        assert r["total_transportistas"] == 0


class TestTercero:
    async def test_volumen_por_tercero(self, db, empresa):
        tercero_id = await _crear_tercero(
            db, empresa, tipo="CLIENTE", nombre="Cliente Alpha",
        )
        await _crear_boleto_avanzado(
            db, empresa, peso_neto="3000",
            id_tercero=tercero_id, tipo_tercero="CLIENTE",
        )
        r = await ReportService().tercero(
            db, empresa,
            datetime(2026, 9, 1), datetime(2026, 9, 30),
        )
        assert r["total_terceros"] == 1
        assert r["terceros"][0]["razon_social"] == "Cliente Alpha"
        assert r["terceros"][0]["peso_neto_total"] == 3000.0

    async def test_filtro_por_tipo_tercero(self, db, empresa):
        cli = await _crear_tercero(db, empresa, tipo="CLIENTE", nombre="C")
        prov = await _crear_tercero(db, empresa, tipo="PROVEEDOR", nombre="P")
        await _crear_boleto_avanzado(
            db, empresa, peso_neto="100",
            id_tercero=cli, tipo_tercero="CLIENTE",
        )
        await _crear_boleto_avanzado(
            db, empresa, peso_neto="200",
            id_tercero=prov, tipo_tercero="PROVEEDOR",
        )
        r = await ReportService().tercero(
            db, empresa,
            datetime(2026, 9, 1), datetime(2026, 9, 30),
            tipo_tercero="CLIENTE",
        )
        assert r["total_terceros"] == 1
        assert r["terceros"][0]["tipo_tercero"] == "CLIENTE"


class TestPesoRango:
    async def test_buckets_ordenados(self, db, empresa):
        await _crear_boleto_avanzado(db, empresa, peso_neto="500")
        await _crear_boleto_avanzado(db, empresa, placa="R1", peso_neto="6000")
        await _crear_boleto_avanzado(db, empresa, placa="R2", peso_neto="25000")
        await _crear_boleto_avanzado(
            db, empresa, placa="R3", peso_neto="0",
        )
        r = await ReportService().peso_rango(
            db, empresa,
            datetime(2026, 9, 1), datetime(2026, 9, 30),
        )
        assert r["total_pesajes"] == 4
        by = {x["rango"]: x for x in r["rangos"]}
        assert by["0-1t"]["cantidad"] == 1
        assert by["5-10t"]["cantidad"] == 1
        assert by["20-40t"]["cantidad"] == 1
        assert by["SIN_PESO"]["cantidad"] == 1


class TestComparativoMensual:
    async def test_variacion_porcentual(self, db, empresa):
        for i in range(5):
            await _crear_boleto_avanzado(
                db, empresa, peso_neto="1000",
                fecha=datetime(2026, 9, 1 + i),
                placa=f"C{i:02d}",
            )
        r = await ReportService().comparativo_mensual(db, empresa, 2026, 9)
        assert r["mes_actual"] == "2026-09"
        assert r["actual"]["total_pesajes"] == 5
        assert r["actual"]["peso_neto_total"] == 5000.0
        assert r["anterior"]["total_pesajes"] == 0
        assert r["variacion_peso"] == 100.0
