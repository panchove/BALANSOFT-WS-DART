"""Pruebas HTTP del módulo BARRERAS (CRUD, filtros, prueba y comando)."""

from __future__ import annotations

import uuid
from typing import Any

import httpx
import pytest
import pytest_asyncio
from fastapi import FastAPI
from sqlalchemy import select

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.api.v1.endpoints import barreras as barreras_mod
from app.core.barrera_hal import BarreraHAL
from app.core.database import get_db
from app.models import Barrera, Empresa, Usuario


class DummyBarreraHAL(BarreraHAL):
    def __init__(self, conectado: bool = True):
        self.conectado = conectado
        self.ultimo_comando: str | None = None

    async def enviar_comando(self, action: str) -> bool:
        self.ultimo_comando = action
        return self.conectado

    async def leer_estado(self) -> dict[str, Any] | None:
        if not self.conectado:
            return None
        return {"estado": "closed", "raw": "OK"}


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
        nombre="Admin Barrera",
        email=f"admin-{uuid.uuid4().hex[:6]}@barrera.demo",
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
        nombre="Operador Barrera",
        email=f"op-{uuid.uuid4().hex[:6]}@barrera.demo",
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


@pytest.mark.asyncio
async def test_crear_y_listar_barrera_http(client, db, empresa):
    resp = await client.post(
        "/api/v1/barreras",
        json={
            "codigo": "BAR-01",
            "descripcion": "Barrera Principal Acceso",
            "protocolo": "http",
            "ip_address": "192.168.1.150",
            "puerto_tcp": 8082,
            "ubicacion": "entrada",
            "control_automatico": True,
            "tiempo_espera_segundos": 10,
        },
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["codigo"] == "BAR-01"
    assert data["descripcion"] == "Barrera Principal Acceso"
    assert data["protocolo"] == "http"
    assert data["ip_address"] == "192.168.1.150"
    assert data["ubicacion"] == "entrada"
    assert data["control_automatico"] is True
    assert data["tiempo_espera_segundos"] == 10

    id_barrera = data["id_barrera"]

    # Listar
    resp_list = await client.get("/api/v1/barreras")
    assert resp_list.status_code == 200
    items = resp_list.json()
    assert any(b["id_barrera"] == id_barrera for b in items)

    # Detalle
    resp_get = await client.get(f"/api/v1/barreras/{id_barrera}")
    assert resp_get.status_code == 200
    assert resp_get.json()["id_barrera"] == id_barrera


@pytest.mark.asyncio
async def test_crear_barrera_serial_validaciones(client):
    # Sin puerto_com debe fallar con 400
    resp_fail = await client.post(
        "/api/v1/barreras",
        json={
            "descripcion": "Barrera Serial Sin Puerto",
            "protocolo": "serial",
            "puerto_com": "",
        },
    )
    assert resp_fail.status_code == 400

    # Con puerto_com válido
    resp_ok = await client.post(
        "/api/v1/barreras",
        json={
            "descripcion": "Barrera Serial USB",
            "protocolo": "serial",
            "puerto_com": "/dev/ttyUSB0",
            "baudrate": 19200,
            "ubicacion": "salida",
        },
    )
    assert resp_ok.status_code == 200
    data = resp_ok.json()
    assert data["protocolo"] == "serial"
    assert data["puerto_com"] == "/dev/ttyUSB0"
    assert data["baudrate"] == 19200
    assert data["ip_address"] is None


@pytest.mark.asyncio
async def test_actualizar_y_eliminar_barrera(client):
    resp = await client.post(
        "/api/v1/barreras",
        json={
            "descripcion": "Barrera Para Editar",
            "protocolo": "http",
        },
    )
    assert resp.status_code == 200
    id_barrera = resp.json()["id_barrera"]

    # PUT
    resp_put = await client.put(
        f"/api/v1/barreras/{id_barrera}",
        json={
            "descripcion": "Barrera Editada",
            "control_automatico": True,
            "tiempo_espera_segundos": 15,
        },
    )
    assert resp_put.status_code == 200
    assert resp_put.json()["descripcion"] == "Barrera Editada"
    assert resp_put.json()["control_automatico"] is True
    assert resp_put.json()["tiempo_espera_segundos"] == 15

    # DELETE
    resp_del = await client.delete(f"/api/v1/barreras/{id_barrera}")
    assert resp_del.status_code == 200

    # 404 tras eliminar
    resp_404 = await client.get(f"/api/v1/barreras/{id_barrera}")
    assert resp_404.status_code == 404


@pytest.mark.asyncio
async def test_aislamiento_multitenant(db, admin, empresa):
    # Crear otra empresa y una barrera perteneciente a ella
    otra_empresa = Empresa(
        nombre="Otra Empresa SA",
        rif=f"J-{uuid.uuid4().hex[:8]}",
        pais="Venezuela",
        moneda="USD",
    )
    db.add(otra_empresa)
    await db.flush()

    barrera_ajena = Barrera(
        id_empresa=otra_empresa.id_empresa,
        descripcion="Barrera de otra empresa",
        protocolo="http",
    )
    db.add(barrera_ajena)
    await db.commit()

    # Cliente autenticado como admin de la empresa original
    app = _app_para(db, admin, empresa)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        # GET ajena da 404
        r = await ac.get(f"/api/v1/barreras/{barrera_ajena.id_barrera}")
        assert r.status_code == 404

        # En el listado no aparece
        r_list = await ac.get("/api/v1/barreras")
        assert r_list.status_code == 200
        ids = [b["id_barrera"] for b in r_list.json()]
        assert str(barrera_ajena.id_barrera) not in ids


@pytest.mark.asyncio
async def test_filtros_barreras(client):
    r1 = await client.post(
        "/api/v1/barreras",
        json={
            "codigo": "B-FILTRO-1",
            "descripcion": "Acceso Norte Entrada",
            "protocolo": "http",
            "ubicacion": "entrada",
            "control_automatico": True,
            "activo": True,
        },
    )
    r2 = await client.post(
        "/api/v1/barreras",
        json={
            "codigo": "B-FILTRO-2",
            "descripcion": "Acceso Sur Salida",
            "protocolo": "serial",
            "puerto_com": "/dev/ttyUSB1",
            "ubicacion": "salida",
            "control_automatico": False,
            "activo": False,
        },
    )
    assert r1.status_code == 200 and r2.status_code == 200

    # Filtro q
    res_q = await client.get("/api/v1/barreras?q=Norte")
    assert res_q.status_code == 200
    assert any(b["codigo"] == "B-FILTRO-1" for b in res_q.json())
    assert not any(b["codigo"] == "B-FILTRO-2" for b in res_q.json())

    # Filtro ubicacion
    res_ub = await client.get("/api/v1/barreras?ubicacion=salida")
    assert res_ub.status_code == 200
    assert any(b["codigo"] == "B-FILTRO-2" for b in res_ub.json())
    assert not any(b["codigo"] == "B-FILTRO-1" for b in res_ub.json())

    # Filtro activo
    res_act = await client.get("/api/v1/barreras?activo=true")
    assert res_act.status_code == 200
    assert any(b["codigo"] == "B-FILTRO-1" for b in res_act.json())
    assert not any(b["codigo"] == "B-FILTRO-2" for b in res_act.json())


@pytest.mark.asyncio
async def test_probar_y_comando_barrera(client, monkeypatch):
    r = await client.post(
        "/api/v1/barreras",
        json={"descripcion": "Barrera Test HAL", "protocolo": "http"},
    )
    id_barrera = r.json()["id_barrera"]

    dummy = DummyBarreraHAL(conectado=True)
    monkeypatch.setattr(barreras_mod, "get_barrera_hal", lambda _: dummy)

    # Probar conexión (conectado)
    r_probar = await client.post(f"/api/v1/barreras/{id_barrera}/probar")
    assert r_probar.status_code == 200
    assert r_probar.json()["conectado"] is True

    # Estado
    r_estado = await client.get(f"/api/v1/barreras/{id_barrera}/estado")
    assert r_estado.status_code == 200
    assert r_estado.json()["conectado"] is True

    # Comando abrir
    r_cmd_open = await client.post(
        f"/api/v1/barreras/{id_barrera}/comando",
        json={"action": "open"},
    )
    assert r_cmd_open.status_code == 200
    assert r_cmd_open.json()["aplicado"] is True
    assert dummy.ultimo_comando == "open"

    # Comando cerrar
    r_cmd_close = await client.post(
        f"/api/v1/barreras/{id_barrera}/comando",
        json={"action": "close"},
    )
    assert r_cmd_close.status_code == 200
    assert r_cmd_close.json()["aplicado"] is True
    assert dummy.ultimo_comando == "close"

    # Probar con HAL desconectado
    dummy_fail = DummyBarreraHAL(conectado=False)
    monkeypatch.setattr(barreras_mod, "get_barrera_hal", lambda _: dummy_fail)
    r_fail = await client.post(f"/api/v1/barreras/{id_barrera}/probar")
    assert r_fail.status_code == 200
    assert r_fail.json()["conectado"] is False
