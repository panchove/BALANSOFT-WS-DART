"""Pruebas de auditoría hacia la tabla `auditoria` (REQ-NF-SEG-001).

Cubre operaciones críticas de pesaje (CREATE/CLOSE/UPDATE/ANULAR) y el CRUD
de catálogos (CREATE/UPDATE/DELETE), más el aislamiento por empresa.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator
from decimal import Decimal
from typing import Any

import pytest_asyncio
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Auditoria, BoletoPesaje, Empresa, Marca, Usuario
from app.schemas import WeighingAnular, WeighingClose, WeighingCreate, WeighingUpdate
from app.services.catalog_service import CatalogService
from app.services.weighing_service import WeighingService


@pytest_asyncio.fixture
async def usuario(db: AsyncSession, empresa: Empresa) -> Usuario:
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Auditor Prueba",
        email=f"auditor-{uuid.uuid4().hex[:8]}@test.local",
        password_hash="no-usado",
        rol="ADMIN",
        activo=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@pytest_asyncio.fixture
async def otra_empresa(db: AsyncSession) -> AsyncGenerator[Empresa, None]:
    emp = Empresa(
        nombre_fiscal="Otra Empresa",
        nombre_comercial="Otra S.A.",
        rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        licencia_tier="CENTRAL",
        licencia_status="ACTIVE",
        activa=True,
    )
    db.add(emp)
    await db.commit()
    await db.refresh(emp)
    yield emp


def _payload(**overrides: Any) -> WeighingCreate:
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


async def _registros(
    db: AsyncSession,
    *,
    accion: str,
    entidad: str = "boletos_pesaje",
) -> list[Auditoria]:
    stmt = select(Auditoria).where(
        Auditoria.entidad == entidad,
        Auditoria.accion == accion,
    )
    return list((await db.execute(stmt)).scalars().all())


class TestAuditoriaPesaje:
    async def test_crear_boleto_inserta_fila_create(self, db, empresa, usuario):
        svc = WeighingService()
        boleto = await svc.create(
            db,
            empresa,
            _payload(),
            id_usuario=usuario.id_usuario,
            ip="127.0.0.1",
        )

        regs = await _registros(db, accion="CREATE")
        assert len(regs) == 1
        assert regs[0].entidad_id == str(boleto.boleto)
        assert regs[0].id_empresa == empresa.id_empresa
        assert regs[0].id_usuario == usuario.id_usuario
        assert regs[0].ip == "127.0.0.1"
        assert regs[0].detalle is not None
        assert regs[0].detalle["numero_boleto"] == boleto.numero_boleto

    async def test_cerrar_boleto_inserta_fila_close(self, db, empresa, usuario):
        svc = WeighingService()
        boleto = await svc.create(
            db,
            empresa,
            _payload(),
            id_usuario=usuario.id_usuario,
        )
        await svc.close(
            db,
            empresa,
            boleto.boleto,
            WeighingClose(peso_salida_vehiculo=Decimal("30000")),
            id_usuario=usuario.id_usuario,
            ip="127.0.0.1",
        )

        regs = await _registros(db, accion="CLOSE")
        assert len(regs) == 1
        assert regs[0].entidad_id == str(boleto.boleto)
        assert regs[0].ip == "127.0.0.1"
        assert regs[0].detalle is not None
        assert regs[0].detalle["numero_boleto"]

    async def test_modificar_boleto_registra_campos_modificados(self, db, empresa, usuario):
        svc = WeighingService()
        boleto = await svc.create(
            db,
            empresa,
            _payload(),
            id_usuario=usuario.id_usuario,
        )
        await svc.update(
            db,
            empresa,
            boleto.boleto,
            WeighingUpdate(documento="GUI-0001", observaciones="Revisado"),
            id_usuario=usuario.id_usuario,
            ip="10.0.0.2",
        )

        regs = await _registros(db, accion="UPDATE")
        assert len(regs) == 1
        assert regs[0].id_usuario == usuario.id_usuario
        assert regs[0].detalle is not None
        assert set(regs[0].detalle["campos_modificados"]) == {"documento", "observaciones"}

    async def test_anular_boleto_inserta_fila_andular_con_motivo(self, db, empresa, usuario):
        svc = WeighingService()
        boleto = await svc.create(
            db,
            empresa,
            _payload(),
            id_usuario=usuario.id_usuario,
        )
        await svc.anular(
            db,
            empresa,
            boleto.boleto,
            WeighingAnular(motivo="Error de pesaje en entrada"),
            id_usuario=usuario.id_usuario,
            ip="10.0.0.3",
        )

        regs = await _registros(db, accion="ANULAR")
        assert len(regs) == 1
        assert regs[0].entidad_id == str(boleto.boleto)
        assert regs[0].detalle is not None
        assert regs[0].detalle["motivo"] == "Error de pesaje en entrada"
        assert regs[0].ip == "10.0.0.3"
        assert (
            await db.execute(
                select(BoletoPesaje).where(BoletoPesaje.boleto == boleto.boleto)
            )
        ).scalar_one().estado_boleto == BoletoPesaje.ESTADO_ANULADO

    async def test_auditoria_boletos_aislada_por_empresa(self, db, empresa, usuario, otra_empresa):
        svc = WeighingService()
        await svc.create(
            db,
            empresa,
            _payload(),
            id_usuario=usuario.id_usuario,
        )
        await svc.create(
            db,
            otra_empresa,
            _payload(id_vehiculo="ZZZ999", conductor_nombre="María García"),
        )

        aislamiento = (
            await db.execute(
                select(Auditoria).where(Auditoria.id_empresa == empresa.id_empresa)
            )
        ).scalars().all()
        assert len(aislamiento) == 1
        assert aislamiento[0].id_usuario == usuario.id_usuario


class TestAuditoriaCatalogo:
    async def test_create_registra_auditoria(self, db, empresa, usuario):
        svc = CatalogService()
        row = await svc.create(
            db,
            empresa.id_empresa,
            "marcas",
            {"nombre": "Chevrolet", "logo_url": None},
            id_usuario=usuario.id_usuario,
            ip="127.0.0.1",
        )

        marca = (
            await db.execute(select(Marca).where(Marca.nombre == "Chevrolet"))
        ).scalar_one()
        assert str(marca.id_marca) == str(row["id_marca"])

        regs = await _registros(db, accion="CREATE", entidad="marcas")
        assert len(regs) == 1
        assert regs[0].entidad_id == str(marca.id_marca)
        assert regs[0].id_empresa == empresa.id_empresa
        assert regs[0].id_usuario == usuario.id_usuario
        assert regs[0].ip == "127.0.0.1"

    async def test_update_registra_auditoria(self, db, empresa, usuario):
        svc = CatalogService()
        await svc.create(
            db,
            empresa.id_empresa,
            "marcas",
            {"nombre": "Ford", "logo_url": None},
            id_usuario=usuario.id_usuario,
        )
        marca = (
            await db.execute(select(Marca).where(Marca.nombre == "Ford"))
        ).scalar_one()

        row = await svc.update(
            db,
            empresa.id_empresa,
            "marcas",
            str(marca.id_marca),
            {"nombre": "Ford Motor", "logo_url": None},
            id_usuario=usuario.id_usuario,
            ip="10.0.0.2",
        )
        assert row["nombre"] == "Ford Motor"

        regs = await _registros(db, accion="UPDATE", entidad="marcas")
        assert len(regs) == 1
        assert regs[0].entidad_id == str(marca.id_marca)
        assert regs[0].ip == "10.0.0.2"
        assert regs[0].detalle == {"campos_modificados": ["logo_url", "nombre"]}

    async def test_delete_registra_auditoria_y_elimina(self, db, empresa, usuario):
        svc = CatalogService()
        await svc.create(
            db,
            empresa.id_empresa,
            "marcas",
            {"nombre": "Scania", "logo_url": None},
            id_usuario=usuario.id_usuario,
        )
        marca = (
            await db.execute(select(Marca).where(Marca.nombre == "Scania"))
        ).scalar_one()

        await svc.delete(
            db,
            empresa.id_empresa,
            "marcas",
            str(marca.id_marca),
            id_usuario=usuario.id_usuario,
            ip="10.0.0.9",
        )

        assert (
            await db.execute(select(Marca).where(Marca.nombre == "Scania"))
        ).scalar_one_or_none() is None

        regs = await _registros(db, accion="DELETE", entidad="marcas")
        assert len(regs) == 1
        assert regs[0].entidad_id == str(marca.id_marca)
        assert regs[0].id_usuario == usuario.id_usuario