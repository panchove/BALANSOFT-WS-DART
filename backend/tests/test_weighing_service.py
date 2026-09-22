"""Pruebas de las reglas de negocio críticas de WeighingService (MODEL.md).

Cubre creación inline, boleto PENDIENTE único por vehículo, numeración
secuencial no reutilizable, cálculo de neto/litros al cerrar, anulación con
motivo obligatorio y liberación del vehículo.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Any

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.models import BoletoPesaje, Camion, Categoria, Kardex, Producto
from app.schemas import WeighingAnular, WeighingClose, WeighingCreate
from app.services.weighing_service import WeighingService


def _create_payload(**overrides: Any) -> WeighingCreate:
    base: dict[str, Any] = dict(
        id_vehiculo="ABC123",
        remolque=False,
        transporte_nombre="Transportes RL",
        conductor_nombre="Juan Pérez",
        producto_nombre="Cemento",
        almacen_nombre="Planta Central",
        balanza_nombre="Balanza 1",
        tipo_tercero="CLIENTE",
        tercero_nombre="Cliente Prueba",
        peso_entrada_vehiculo=Decimal("50000"),
    )
    base.update(overrides)
    return WeighingCreate(**base)


class TestCreacionInline:
    async def test_crea_catalogo_si_no_existe(self, db, empresa):
        svc = WeighingService()
        pesaje = await svc.create(db, empresa, _create_payload(), creado_por="Admin")

        camion = (
            await db.execute(select(Camion).where(Camion.placa == "ABC123"))
        ).scalar_one()
        assert camion.id_empresa == empresa.id_empresa

        producto = (
            await db.execute(select(Producto).where(Producto.nombre == "Cemento"))
        ).scalar_one()
        assert producto.id_empresa == empresa.id_empresa

        assert pesaje.id_vehiculo == "ABC123"
        assert pesaje.id_producto is not None
        assert pesaje.estado_boleto == BoletoPesaje.ESTADO_PENDIENTE

    async def test_no_duplica_catalogo_en_segunda_entrada(self, db, empresa):
        svc = WeighingService()
        await svc.create(db, empresa, _create_payload(id_vehiculo="AAA111"))
        # cerramos el primer boleto para poder crear otro con otro vehículo
        b = (
            await db.execute(
                select(BoletoPesaje).where(BoletoPesaje.id_vehiculo == "AAA111")
            )
        ).scalar_one()
        await svc.close(db, empresa, b.boleto, WeighingClose(peso_salida_vehiculo=Decimal("40000")))

        await svc.create(
            db, empresa,
            _create_payload(id_vehiculo="BBB222", producto_nombre="Cemento"),
        )
        count = (
            await db.execute(
                select(Producto).where(Producto.nombre == "Cemento", Producto.id_empresa == empresa.id_empresa)
            )
        ).scalars().all()
        assert len(count) == 1


class TestPendienteUnico:
    async def test_rechaza_segunda_entrada_mismo_vehiculo(self, db, empresa):
        svc = WeighingService()
        await svc.create(db, empresa, _create_payload())
        with pytest.raises(HTTPException) as exc:
            await svc.create(db, empresa, _create_payload(id_vehiculo="abc123"))  # mismo (mayúsculas)
        assert exc.value.status_code == 400
        assert "tiene un boleto pendiente" in str(exc.value.detail)

    async def test_permite_nueva_entrada_despues_de_cerrar(self, db, empresa):
        svc = WeighingService()
        b1 = await svc.create(db, empresa, _create_payload())
        await svc.close(db, empresa, b1.boleto, WeighingClose(peso_salida_vehiculo=Decimal("45000")))
        # Ya está cerrado: se puede registrar otra entrada con la misma placa
        b2 = await svc.create(db, empresa, _create_payload())
        assert b2.boleto != b1.boleto


class TestNumeracion:
    async def test_secuencial_y_no_reutilizable(self, db, empresa):
        svc = WeighingService()
        b1 = await svc.create(db, empresa, _create_payload(id_vehiculo="V001"))
        b2 = await svc.create(db, empresa, _create_payload(id_vehiculo="V002"))
        await svc.close(db, empresa, b1.boleto, WeighingClose(peso_salida_vehiculo=Decimal("1")))
        b3 = await svc.create(db, empresa, _create_payload(id_vehiculo="V003"))

        assert b1.numero_boleto == "TA-00000001"
        assert b2.numero_boleto == "TA-00000002"
        assert b3.numero_boleto == "TA-00000003"

        numeros = {b1.numero_boleto, b2.numero_boleto, b3.numero_boleto}
        assert len(numeros) == 3  # nunca se reutilizan


class TestCierre:
    async def test_calcula_neto_y_litros(self, db, empresa):
        svc = WeighingService()
        b = await svc.create(
            db, empresa,
            _create_payload(peso_entrada_vehiculo=Decimal("50000"), remolque=False),
        )
        cerrado = await svc.close(
            db, empresa, b.boleto,
            WeighingClose(peso_salida_vehiculo=Decimal("45000"), densidad=Decimal("1.6")),
            salida_por="Admin",
        )
        assert cerrado.estado_boleto == BoletoPesaje.ESTADO_CERRADO
        assert cerrado.peso_neto == Decimal("5000.00")
        assert cerrado.litros == Decimal("3125.00")

    async def test_no_cierra_boleto_ya_cerrado(self, db, empresa):
        svc = WeighingService()
        b = await svc.create(db, empresa, _create_payload())
        await svc.close(db, empresa, b.boleto, WeighingClose(peso_salida_vehiculo=Decimal("1")))
        with pytest.raises(HTTPException) as exc:
            await svc.close(db, empresa, b.boleto, WeighingClose(peso_salida_vehiculo=Decimal("1")))
        assert exc.value.status_code == 400

    async def test_404_boleto_inexistente(self, db, empresa):
        import uuid
        svc = WeighingService()
        with pytest.raises(HTTPException) as exc:
            await svc.close(db, empresa, uuid.uuid4(), WeighingClose(peso_salida_vehiculo=Decimal("1")))
        assert exc.value.status_code == 404


class TestAnulacion:
    async def test_anula_y_libera_vehiculo(self, db, empresa):
        svc = WeighingService()
        b = await svc.create(db, empresa, _create_payload())
        anulado = await svc.anular(
            db, empresa, b.boleto, WeighingAnular(motivo="error de captura de datos de prueba de anulacion")
        )
        assert anulado.estado_boleto == BoletoPesaje.ESTADO_ANULADO
        assert "ANULADO" in (anulado.observaciones or "")

        # El vehículo quedó liberado: nueva entrada con la misma placa ya es válida
        b2 = await svc.create(db, empresa, _create_payload())
        assert b2.numero_boleto != b.numero_boleto

    async def test_no_anula_dos_veces(self, db, empresa):
        svc = WeighingService()
        b = await svc.create(db, empresa, _create_payload())
        await svc.anular(db, empresa, b.boleto, WeighingAnular(motivo="motivo de anulacion correcto de prueba"))
        with pytest.raises(HTTPException) as exc:
            await svc.anular(db, empresa, b.boleto, WeighingAnular(motivo="otro motivo de anulacion prueba"))
        assert exc.value.status_code == 400
        assert "ya está anulado" in str(exc.value.detail)

    async def test_anula_cerrado(self, db, empresa):
        svc = WeighingService()
        b = await svc.create(db, empresa, _create_payload())
        await svc.close(db, empresa, b.boleto, WeighingClose(peso_salida_vehiculo=Decimal("1")))
        anulado = await svc.anular(db, empresa, b.boleto, WeighingAnular(motivo="se anula un cerrado para prueba de flujo"))
        assert anulado.estado_boleto == BoletoPesaje.ESTADO_ANULADO

    async def test_anula_cerrado_registra_inverso_kardex(self, db, empresa):
        svc = WeighingService()
        # Producto con ES_KARDEX: al cerrar genera INGRESO (10) por PNT > 0
        categoria = Categoria(
            id_empresa=empresa.id_empresa, nombre="Categoría Cemento"
        )
        db.add(categoria)
        await db.flush()
        producto = Producto(
            id_empresa=empresa.id_empresa,
            id_categoria=categoria.id_categoria,
            nombre="Cemento Kardex",
            es_kardex=True,
        )
        db.add(producto)
        await db.flush()

        b = await svc.create(
            db, empresa,
            _create_payload(id_vehiculo="INV001", producto_nombre="Cemento Kardex"),
        )
        await svc.close(
            db, empresa, b.boleto, WeighingClose(peso_salida_vehiculo=Decimal("1"))
        )

        movimientos = (
            (await db.execute(
                select(Kardex).where(Kardex.boleto == b.boleto)
            )).scalars().all()
        )
        assert [m.id_movimiento for m in movimientos] == [Kardex.KARDEX_INGRESO]

        # Anular un CERRADO NO borra la historia: registra el inverso (60)
        await svc.anular(
            db, empresa, b.boleto,
            WeighingAnular(motivo="anulacion de cerrado con kardex para prueba"),
        )
        movimientos = (
            (await db.execute(
                select(Kardex)
                .where(Kardex.boleto == b.boleto)
                .order_by(Kardex.created_at)
            )).scalars().all()
        )
        assert [m.id_movimiento for m in movimientos] == [
            Kardex.KARDEX_INGRESO,
            Kardex.KARDEX_DESPACHO,
        ]
        assert movimientos[0].valor == movimientos[1].valor == Decimal("49999.00")

    async def test_anula_pendiente_no_genera_kardex(self, db, empresa):
        svc = WeighingService()
        categoria = Categoria(
            id_empresa=empresa.id_empresa, nombre="Categoría Cemento 2"
        )
        db.add(categoria)
        await db.flush()
        producto = Producto(
            id_empresa=empresa.id_empresa,
            id_categoria=categoria.id_categoria,
            nombre="Cemento Kardex 2",
            es_kardex=True,
        )
        db.add(producto)
        await db.flush()

        b = await svc.create(
            db, empresa,
            _create_payload(id_vehiculo="INV002", producto_nombre="Cemento Kardex 2"),
        )
        await svc.anular(
            db, empresa, b.boleto,
            WeighingAnular(motivo="anulacion de pendiente sin movimiento de kardex prueba"),
        )
        movimientos = (
            (await db.execute(select(Kardex).where(Kardex.boleto == b.boleto)))
            .scalars().all()
        )
        assert movimientos == []
