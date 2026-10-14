"""Pruebas HTTP de la edición de boletos (contrato y aislamiento multi-tenant).

Misma estrategia que ``test_categorias_seguridad.py``/``test_endpoints.py``: app
FastAPI fresca con overrides de dependencias sobre la BD real de tests.

Lo que se fija aquí (y que los tests de servicio no cubrían):
- contrato HTTP de ``PUT /api/v1/weighing/{boleto}`` y
  ``GET /api/v1/weighing/{boleto}/ediciones``;
- **aislamiento multi-tenant**: un boleto de otra empresa da **404**, no 200;
- códigos de negocio: **422** (justificación inválida) y **409** (tope);
- el mensaje de error viaja traducido según ``?idioma=``.

El nombre de la ruta es el real montado por ``API_ROUTERS``; si el prefijo
cambia, el test lo detecta en vez de pasar en vacío (se comprueba que las rutas
duran en el openapi de la app).
"""

from __future__ import annotations

from collections.abc import AsyncGenerator
from decimal import Decimal
from typing import Any

import httpx
import pytest_asyncio
from fastapi import FastAPI
from sqlalchemy import select

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core.database import get_db
from app.models import BoletoEdicion, BoletoPesaje, Empresa, Usuario
from app.schemas import WeighingClose, WeighingCreate
from app.services.weighing_service import WeighingService

JUSTIFICACION = "Corrección del documento y observaciones del boleto"


def _payload(**overrides: Any) -> WeighingCreate:
    base: dict[str, Any] = dict(
        id_vehiculo="API01",
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


async def _boleto_cerrado(db, empresa, **overrides) -> BoletoPesaje:
    svc = WeighingService()
    boleto = await svc.create(db, empresa, _payload(**overrides))
    return await svc.close(
        db,
        empresa,
        boleto.boleto,
        WeighingClose(peso_salida_vehiculo=Decimal("40000")),
    )


async def _otra_empresa(db) -> Empresa:
    otra = Empresa(
        nombre_fiscal="Empresa Ajena",
        nombre_comercial="Ajena S.A.",
        rif_nit="J-AJENA0001",
        licencia_tier="CENTRAL",
        licencia_status="ACTIVE",
        activa=True,
    )
    db.add(otra)
    await db.commit()
    await db.refresh(otra)
    return otra


@pytest_asyncio.fixture
async def usuario(db, empresa) -> Usuario:
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Operador Test",
        email="operador@edicion.demo",
        password_hash="x",
        rol="OPERADOR",
        activo=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@pytest_asyncio.fixture
async def app(db, empresa, usuario) -> FastAPI:
    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    application.dependency_overrides[get_current_user] = lambda: usuario
    application.dependency_overrides[get_current_empresa] = lambda: empresa
    return application


@pytest_asyncio.fixture
async def client(app) -> AsyncGenerator[httpx.AsyncClient, None]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


RUTA = "/api/v1/weighing"


class TestContratoHTTP:
    async def test_las_rutas_de_edicion_existen(self, app):
        """Si el prefijo o la ruta cambian, el test avisa en vez de pasar en vacío."""
        paths = app.openapi()["paths"]
        assert f"{RUTA}/{{boleto}}" in paths
        assert "put" in paths[f"{RUTA}/{{boleto}}"]
        assert f"{RUTA}/{{boleto}}/ediciones" in paths
        assert "get" in paths[f"{RUTA}/{{boleto}}/ediciones"]

    async def test_put_edita_y_registra_historial(self, db, empresa, client):
        boleto = await _boleto_cerrado(db, empresa)

        r = await client.put(
            f"{RUTA}/{boleto.boleto}",
            json={"documento": "GUI-7777", "justificacion": JUSTIFICACION},
        )
        assert r.status_code == 200, r.text
        assert r.json()["estado_boleto"] == BoletoPesaje.ESTADO_MODIFICADO

        r = await client.get(f"{RUTA}/{boleto.boleto}/ediciones")
        assert r.status_code == 200, r.text
        ediciones = r.json()
        assert len(ediciones) == 1
        assert ediciones[0]["justificacion"] == JUSTIFICACION
        assert ediciones[0]["edicion_numero"] == 1
        assert "documento" in ediciones[0]["campos_modificados"]

    async def test_put_justificacion_invalida_responde_422(self, db, empresa, client):
        boleto = await _boleto_cerrado(db, empresa)
        r = await client.put(
            f"{RUTA}/{boleto.boleto}",
            json={"documento": "GUI-1", "justificacion": "corta"},
        )
        assert r.status_code == 422
        # Nada se escribió.
        assert (
            await db.execute(
                select(BoletoEdicion).where(BoletoEdicion.boleto == boleto.boleto)
            )
        ).scalars().all() == []

    async def test_put_sin_justificacion_responde_422(self, db, empresa, client):
        boleto = await _boleto_cerrado(db, empresa)
        r = await client.put(f"{RUTA}/{boleto.boleto}", json={"documento": "GUI-1"})
        assert r.status_code == 422

    async def test_tope_alcanzado_responde_409_con_mensaje(self, db, empresa, client):
        empresa.max_ediciones_boleto = 1
        await db.commit()
        boleto = await _boleto_cerrado(db, empresa)

        primera = await client.put(
            f"{RUTA}/{boleto.boleto}",
            json={"documento": "A-1", "justificacion": JUSTIFICACION},
        )
        assert primera.status_code == 200, primera.text

        segunda = await client.put(
            f"{RUTA}/{boleto.boleto}",
            json={"documento": "A-2", "justificacion": JUSTIFICACION},
        )
        assert segunda.status_code == 409, segunda.text
        assert "máximo de ediciones" in segunda.json()["detail"]
        # El rechazo no dejó rastro.
        ediciones = (
            await db.execute(
                select(BoletoEdicion).where(BoletoEdicion.boleto == boleto.boleto)
            )
        ).scalars().all()
        assert len(ediciones) == 1

    async def test_el_mensaje_de_error_respeta_el_idioma(self, db, empresa, client):
        empresa.max_ediciones_boleto = 1
        await db.commit()
        boleto = await _boleto_cerrado(db, empresa)
        await client.put(
            f"{RUTA}/{boleto.boleto}",
            json={"documento": "A-1", "justificacion": JUSTIFICACION},
        )
        r = await client.put(
            f"{RUTA}/{boleto.boleto}?idioma=en",
            json={"documento": "A-2", "justificacion": JUSTIFICACION},
        )
        assert r.status_code == 409
        assert "maximum number of edits" in r.json()["detail"]


class TestAislamientoMultiTenant:
    async def test_no_se_puede_editar_un_boleto_de_otra_empresa(self, db, empresa, client):
        ajena = await _otra_empresa(db)
        boleto_ajeno = await _boleto_cerrado(db, ajena)

        r = await client.put(
            f"{RUTA}/{boleto_ajeno.boleto}",
            json={"documento": "HACK", "justificacion": JUSTIFICACION},
        )
        assert r.status_code == 404, r.text
        # El boleto ajeno quedó intacto y sin historial.
        await db.refresh(boleto_ajeno)
        assert boleto_ajeno.documento != "HACK"
        ediciones = (
            await db.execute(
                select(BoletoEdicion).where(BoletoEdicion.boleto == boleto_ajeno.boleto)
            )
        ).scalars().all()
        assert ediciones == []

    async def test_no_se_ven_las_ediciones_de_un_boleto_ajeno(self, db, empresa, client):
        ajena = await _otra_empresa(db)
        boleto_ajeno = await _boleto_cerrado(db, ajena)
        r = await client.get(f"{RUTA}/{boleto_ajeno.boleto}/ediciones")
        assert r.status_code == 404, r.text
