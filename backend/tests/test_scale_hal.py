"""Pruebas del HAL de balanza (B7 / REQ-NF-ARQ-004).

Cubre la fábrica ``get_scale_hal``, la lectura TCP (simulador BSDD: líneas
JSON) y el endpoint HTTP ``GET /api/v1/weighing/scale/{balanza_id}/live``.
"""

from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncGenerator
from dataclasses import dataclass, field
from types import SimpleNamespace

import httpx
import pytest
import pytest_asyncio
from fastapi import FastAPI
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core.database import get_db
from app.core.scale_hal import SerialScaleHAL, TcpScaleHAL, get_scale_hal
from app.models import Balanza, Empresa, Usuario


@dataclass
class FakeBalanza:
    """Config de hardware mínima para la fábrica (sin tocar la BD)."""

    ip_address: str | None = None
    puerto_tcp: int | None = None
    puerto_com: str | None = None


@dataclass
class _ServidorTCP:
    """Servidor TCP mínimo que responde a ``get_state`` como el simulador."""

    peso: float
    _server: asyncio.Server | None = field(default=None, init=False, repr=False)
    port: int = field(default=0, init=False)

    async def _handler(self, reader, writer):  # noqa: D102
        try:
            await reader.readline()
            writer.write(
                json.dumps({"weight_kg": self.peso, "status": "stable"})
                .encode()
                + b"\n"
            )
            await writer.drain()
        finally:
            writer.close()

    async def start(self) -> None:  # noqa: D102
        self._server = await asyncio.start_server(self._handler, "127.0.0.1", 0)
        self.port = self._server.sockets[0].getsockname()[1]

    async def stop(self) -> None:  # noqa: D102
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()


@pytest.mark.asyncio
async def test_tcp_read_weight_parsea_json_del_simulador():
    server = _ServidorTCP(peso=1234.5)
    await server.start()
    try:
        hal = TcpScaleHAL("127.0.0.1", server.port, timeout=2)
        peso = await hal.read_weight()
        assert peso == 1234.5
    finally:
        await server.stop()


@pytest.mark.asyncio
async def test_tcp_read_weight_sin_servidor_devuelve_none():
    hal = TcpScaleHAL("127.0.0.1", 1, timeout=0.5)
    assert await hal.read_weight() is None


def test_factory_prioriza_tcp():
    hal = get_scale_hal(
        SimpleNamespace(
            ip_address="10.0.0.7", puerto_tcp=5556, puerto_com="/dev/ttyUSB0"
        )
    )
    assert isinstance(hal, TcpScaleHAL)
    assert hal.host == "10.0.0.7"
    assert hal.port == 5556


def test_factory_serial_sin_ip():
    hal = get_scale_hal(FakeBalanza(puerto_com="COM3"))
    assert isinstance(hal, SerialScaleHAL)
    assert hal.port == "COM3"


def test_factory_sin_hardware_lanza_error():
    with pytest.raises(ValueError):
        get_scale_hal(FakeBalanza())


@pytest_asyncio.fixture
async def server_tcp() -> AsyncGenerator[_ServidorTCP, None]:
    server = _ServidorTCP(peso=25000)
    await server.start()
    yield server
    await server.stop()


@pytest_asyncio.fixture
async def app(db, empresa, server_tcp: _ServidorTCP) -> FastAPI:
    balanza = Balanza(
        id_empresa=empresa.id_empresa,
        descripcion="Balanza Test",
        ip_address="127.0.0.1",
        puerto_tcp=server_tcp.port,
        protocolo="tcp",
    )
    db.add(balanza)
    await db.commit()
    await db.refresh(balanza)

    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin",
        email="admin@scale.test",
        password_hash="x",
        rol="ADMIN",
        activo=True,
    )
    db.add(user)
    await db.commit()

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
async def client(app) -> AsyncGenerator[httpx.AsyncClient, None]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


def _crear_empresa_ajena(db: AsyncSession) -> Empresa:
    return Empresa(
        nombre_fiscal="Otra Empresa",
        nombre_comercial="Otra S.A.",
        rif_nit="J-9999999999",
        licencia_tier="CENTRAL",
        licencia_status="ACTIVE",
        activa=True,
    )


@pytest.mark.asyncio
async def _balanza_empresa(db, empresa: Empresa) -> Balanza:
    return (
        await db.execute(
            select(Balanza).where(Balanza.id_empresa == empresa.id_empresa)
        )
    ).scalar_one()


@pytest.mark.asyncio
async def test_endpoint_peso_en_vivo(db, app, client, empresa):
    balanza = await _balanza_empresa(db, empresa)
    resp = await client.get(f"/api/v1/weighing/scale/{balanza.id_balanza}/live")
    assert resp.status_code == 200
    payload = resp.json()
    assert payload["peso_kg"] == 25000
    assert payload["hardware"] == "tcp"
    assert payload["balanza"] == "Balanza Test"


@pytest.mark.asyncio
async def test_endpoint_balanza_sin_hardware_400(db, empresa, app, client):
    balanza = Balanza(
        id_empresa=empresa.id_empresa,
        descripcion="Balanza Sin Hardware",
    )
    db.add(balanza)
    await db.commit()
    resp = await client.get(f"/api/v1/weighing/scale/{balanza.id_balanza}/live")
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_endpoint_balanza_de_otra_empresa_404(db, empresa, app, client):
    ajena = _crear_empresa_ajena(db)
    db.add(ajena)
    await db.commit()
    balanza = Balanza(
        id_empresa=ajena.id_empresa,
        descripcion="Balanza Ajena",
        ip_address="127.0.0.1",
        puerto_tcp=1,
    )
    db.add(balanza)
    await db.commit()
    resp = await client.get(f"/api/v1/weighing/scale/{balanza.id_balanza}/live")
    assert resp.status_code == 404