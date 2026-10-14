"""Edición de boletos: justificación obligatoria, historial y tope por boleto.

Regla de negocio (cliente):
- Un boleto solo se edita colocando la **justificación de la edición**, y cada
  justificación queda **almacenada por edición** en `boletos_ediciones`.
- El ADMIN de la cuenta fija en «Diseño de ticket» un **máximo de ediciones por
  boleto** que aplica **solo a las otras sesiones**; el ADMIN no tiene tope.
- Un boleto editado señala **MODIFICADO** (documentado).
- Los pesos capturados por la báscula no se editan: el `peso_neto` no puede
  cambiar por esta vía (si cambiara con Kardex presente, se rechaza).
"""

from __future__ import annotations

from decimal import Decimal
from typing import Any

import pytest
from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import select

from app.models import BoletoEdicion, BoletoPesaje, Kardex, Producto
from app.schemas import WeighingClose, WeighingCreate, WeighingUpdate
from app.services.weighing_service import WeighingService

JUSTIFICACION = "Corrección del documento y observaciones del boleto"


def _payload(**overrides: Any) -> WeighingCreate:
    base: dict[str, Any] = dict(
        id_vehiculo="EDIT01",
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


def _update(**overrides: Any) -> WeighingUpdate:
    base: dict[str, Any] = {"justificacion": JUSTIFICACION}
    base.update(overrides)
    return WeighingUpdate(**base)


async def _boleto_pendiente(db, empresa, **overrides) -> BoletoPesaje:
    svc = WeighingService()
    return await svc.create(db, empresa, _payload(**overrides))


async def _boleto_cerrado(db, empresa, **overrides) -> BoletoPesaje:
    svc = WeighingService()
    boleto = await _boleto_pendiente(db, empresa, **overrides)
    return await svc.close(
        db,
        empresa,
        boleto.boleto,
        WeighingClose(peso_salida_vehiculo=Decimal("40000")),
    )


class TestJustificacionObligatoria:
    async def test_la_schema_exige_justificacion(self):
        with pytest.raises(ValidationError):
            WeighingUpdate(documento="GUI-1")  # type: ignore[call-arg]

    async def test_justificacion_corta_rechazada(self):
        with pytest.raises(ValidationError):
            WeighingUpdate(documento="GUI-1", justificacion="corta")

    async def test_servicio_rechaza_justificacion_corta(self, db, empresa):
        svc = WeighingService()
        boleto = await _boleto_pendiente(db, empresa)
        with pytest.raises(HTTPException) as exc:
            await svc.update(
                db,
                empresa,
                boleto.boleto,
                _update(documento="GUI-1234"),
                justificacion="  corta  ",
            )
        assert exc.value.status_code == 422

    async def test_servicio_rechaza_justificacion_ausente(self, db, empresa):
        svc = WeighingService()
        boleto = await _boleto_pendiente(db, empresa)
        with pytest.raises(HTTPException) as exc:
            await svc.update(
                db,
                empresa,
                boleto.boleto,
                _update(documento="GUI-1234"),
                justificacion="",
            )
        assert exc.value.status_code == 422


class TestHistorialYEstado:
    async def test_edicion_guarda_justificacion_y_campos(self, db, empresa):
        svc = WeighingService()
        boleto = await _boleto_cerrado(db, empresa)
        await svc.update(
            db,
            empresa,
            boleto.boleto,
            _update(documento="GUI-9999", observaciones="Revisado"),
        )

        ediciones = (
            await db.execute(
                select(BoletoEdicion).where(BoletoEdicion.boleto == boleto.boleto)
            )
        ).scalars().all()
        assert len(ediciones) == 1
        ed = ediciones[0]
        assert ed.justificacion == JUSTIFICACION
        assert ed.edicion_numero == 1
        assert ed.estado_anterior == BoletoPesaje.ESTADO_CERRADO
        assert ed.estado_nuevo == BoletoPesaje.ESTADO_MODIFICADO
        assert set(ed.campos_modificados or {}) == {"documento", "observaciones"}
        assert ed.campos_modificados["documento"]["despues"] == "GUI-9999"

    async def test_boleto_editado_queda_modificado(self, db, empresa):
        svc = WeighingService()
        boleto = await _boleto_cerrado(db, empresa)
        actualizado = await svc.update(
            db, empresa, boleto.boleto, _update(documento="GUI-1")
        )
        assert actualizado.estado_boleto == BoletoPesaje.ESTADO_MODIFICADO
        assert actualizado.motivo_modificacion_ultima == JUSTIFICACION
        assert actualizado.ediciones_count == 1

    async def test_contador_incrementa_por_edicion(self, db, empresa):
        svc = WeighingService()
        boleto = await _boleto_cerrado(db, empresa)
        await svc.update(db, empresa, boleto.boleto, _update(documento="A-1"))
        await svc.update(db, empresa, boleto.boleto, _update(documento="A-2"))
        segunda = await svc.update(db, empresa, boleto.boleto, _update(documento="A-3"))
        assert segunda.ediciones_count == 3
        ediciones = await svc.listar_ediciones(db, empresa, boleto.boleto)
        assert [e.edicion_numero for e in ediciones] == [3, 2, 1]

    async def test_edicion_sin_cambios_no_registra(self, db, empresa):
        svc = WeighingService()
        boleto = await _boleto_cerrado(db, empresa)
        resultado = await svc.update(db, empresa, boleto.boleto, _update())
        assert resultado.ediciones_count == 0
        ediciones = await svc.listar_ediciones(db, empresa, boleto.boleto)
        assert ediciones == []

    async def test_reenviar_los_mismos_valores_no_registra(self, db, empresa):
        """El formulario manda siempre los diez campos: reenviarlos sin tocarlos
        no debe crear historial ni sumar al contador (antes sí lo hacía)."""
        svc = WeighingService()
        boleto = await _boleto_cerrado(db, empresa)
        await svc.update(db, empresa, boleto.boleto, _update(documento="GUI-1"))
        # Se reenvían los mismos valores que ya tiene el boleto.
        resultado = await svc.update(
            db,
            empresa,
            boleto.boleto,
            _update(documento="GUI-1", observaciones=boleto.observaciones),
        )
        assert resultado.ediciones_count == 1  # solo la edición real
        ediciones = await svc.listar_ediciones(db, empresa, boleto.boleto)
        assert len(ediciones) == 1

    async def test_vaciar_un_campo_se_persiste_y_registra(self, db, empresa):
        """Un `null` explícito debe borrar el valor (antes se descartaba por
        `exclude_none` y el valor anterior permanecía en silencio)."""
        svc = WeighingService()
        boleto = await _boleto_cerrado(db, empresa)
        await svc.update(db, empresa, boleto.boleto, _update(documento="GUI-1"))

        borrado = await svc.update(db, empresa, boleto.boleto, _update(documento=None))

        assert borrado.documento is None
        ediciones = await svc.listar_ediciones(db, empresa, boleto.boleto)
        assert len(ediciones) == 2
        ultima = ediciones[0]  # más reciente primero
        campos = ultima.campos_modificados or {}
        assert campos["documento"] == {
            "antes": "GUI-1",
            "despues": None,
        }

    async def test_boleto_anulado_no_se_edita(self, db, empresa):
        from app.schemas import WeighingAnular

        svc = WeighingService()
        boleto = await _boleto_cerrado(db, empresa)
        await svc.anular(
            db,
            empresa,
            boleto.boleto,
            WeighingAnular(motivo="Error de pesaje en entrada"),
        )
        with pytest.raises(HTTPException) as exc:
            await svc.update(db, empresa, boleto.boleto, _update(documento="X"))
        assert exc.value.status_code == 400


class TestTopeDeEdiciones:
    async def test_otra_sesion_bloqueada_al_alcanzar_el_tope(self, db, empresa):
        empresa.max_ediciones_boleto = 1
        await db.commit()
        svc = WeighingService()
        boleto = await _boleto_cerrado(db, empresa)
        await svc.update(db, empresa, boleto.boleto, _update(documento="A-1"), es_admin=False)
        with pytest.raises(HTTPException) as exc:
            await svc.update(db, empresa, boleto.boleto, _update(documento="A-2"), es_admin=False)
        assert exc.value.status_code == 409
        assert "máximo de ediciones" in exc.value.detail

    async def test_admin_no_tiene_tope(self, db, empresa):
        empresa.max_ediciones_boleto = 1
        await db.commit()
        svc = WeighingService()
        boleto = await _boleto_cerrado(db, empresa)
        await svc.update(db, empresa, boleto.boleto, _update(documento="A-1"), es_admin=True)
        segunda = await svc.update(
            db, empresa, boleto.boleto, _update(documento="A-2"), es_admin=True
        )
        assert segunda.ediciones_count == 2
        # El ADMIN también justifica: el historial guarda las dos justificaciones.
        ediciones = await svc.listar_ediciones(db, empresa, boleto.boleto)
        assert len(ediciones) == 2
        assert all(e.justificacion == JUSTIFICACION for e in ediciones)

    async def test_sin_tope_configurado_no_bloquea(self, db, empresa):
        empresa.max_ediciones_boleto = None
        await db.commit()
        svc = WeighingService()
        boleto = await _boleto_cerrado(db, empresa)
        for i in range(3):
            await svc.update(
                db, empresa, boleto.boleto, _update(documento=f"B-{i}"), es_admin=False
            )
        ediciones = await svc.listar_ediciones(db, empresa, boleto.boleto)
        assert len(ediciones) == 3

    async def test_tope_cero_significa_sin_tope(self, db, empresa):
        empresa.max_ediciones_boleto = 0
        await db.commit()
        svc = WeighingService()
        boleto = await _boleto_cerrado(db, empresa)
        resultado = await svc.update(
            db, empresa, boleto.boleto, _update(documento="C-1"), es_admin=False
        )
        assert resultado.ediciones_count == 1


class TestKardexIntacto:
    async def test_edicion_no_cambia_el_peso_neto_ni_el_kardex(self, db, empresa):
        """Los pesos de báscula no son editables: el movimiento de Kardex no cambia."""
        svc = WeighingService()
        boleto = await _boleto_cerrado(db, empresa)
        producto = (
            await db.execute(select(Producto).where(Producto.id_producto == boleto.id_producto))
        ).scalar_one()
        producto.es_kardex = True
        await db.commit()

        peso_neto_antes = boleto.peso_neto
        await svc.update(
            db,
            empresa,
            boleto.boleto,
            _update(peso_neto_declarado=Decimal("10000"), documento="GUI-77"),
        )
        actualizado = (
            await db.execute(select(BoletoPesaje).where(BoletoPesaje.boleto == boleto.boleto))
        ).scalar_one()
        assert actualizado.peso_neto == peso_neto_antes

    async def test_guarda_defensiva_si_el_neto_cambiara_con_kardex(self, db, empresa):
        """Si el neto cambiara y existiera Kardex, la edición se rechaza (no desincroniza)."""
        svc = WeighingService()
        boleto = await _boleto_cerrado(db, empresa)
        db.add(
            Kardex(
                id_empresa=empresa.id_empresa,
                id_movimiento=Kardex.KARDEX_INGRESO,
                fecha_kardex=boleto.fecha_hora_salida,
                id_producto=boleto.id_producto,
                id_almacen=boleto.id_almacen,
                valor=Decimal("10000"),
                boleto=boleto.boleto,
            )
        )
        await db.commit()

        # Simula un cambio de neto que la vía normal no permite (defensa a futuro).
        original = WeighingService._calcular

        def _calcular_falso(self, *args, **kwargs):
            resultado = original(self, *args, **kwargs)
            resultado["peso_neto"] = Decimal("123.45")
            return resultado

        WeighingService._calcular = _calcular_falso  # type: ignore[method-assign]
        try:
            with pytest.raises(HTTPException) as exc:
                await svc.update(
                    db, empresa, boleto.boleto,
                    _update(peso_neto_declarado=Decimal("11000")),
                )
            assert exc.value.status_code == 409
        finally:
            WeighingService._calcular = original  # type: ignore[method-assign]
