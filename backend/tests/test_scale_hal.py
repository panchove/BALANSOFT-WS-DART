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
from app.core.scale_session import get_scale_session_manager
from app.models import Balanza, Empresa, Usuario


@dataclass
class FakeBalanza:
    """Config de hardware mínima para la fábrica (sin tocar la BD)."""

    ip_address: str | None = None
    puerto_tcp: int | None = None
    puerto_com: str | None = None


@dataclass
class _ServidorTCP:
    """Servidor TCP persistente que emula al simulador BSDD.

    Empuja el estado al conectar y responde a cada ``get_state``, **sin cerrar**
    la conexión (como un equipo emparejado real). Cuenta las conexiones
    aceptadas para verificar que la sesión las reutiliza.
    """

    peso: float
    status: str = "stable"
    conexiones: int = field(default=0, init=False)
    _server: asyncio.Server | None = field(default=None, init=False, repr=False)
    _writers: list[asyncio.StreamWriter] = field(default_factory=list, init=False)
    port: int = field(default=0, init=False)

    async def _handler(self, reader, writer):  # noqa: D102
        self.conexiones += 1
        self._writers.append(writer)
        estado = (
            json.dumps({"weight_kg": self.peso, "status": self.status}).encode() + b"\n"
        )
        try:
            writer.write(estado)
            await writer.drain()
            while True:
                linea = await reader.readline()
                if not linea:
                    break
                writer.write(estado)
                await writer.drain()
        finally:
            writer.close()

    async def start(self) -> None:  # noqa: D102
        self._server = await asyncio.start_server(self._handler, "127.0.0.1", 0)
        self.port = self._server.sockets[0].getsockname()[1]

    async def stop(self) -> None:  # noqa: D102
        server, self._server = self._server, None
        if server is not None:
            server.close()
        # Cerrar primero las conexiones de los clientes: desde Python 3.12
        # ``wait_closed`` espera a que terminen todas las conexiones activas.
        for writer in self._writers:
            writer.close()
        self._writers.clear()
        if server is not None:
            try:
                await asyncio.wait_for(server.wait_closed(), timeout=2.0)
            except (TimeoutError, OSError):
                pass


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


@dataclass
class _ServidorTCPConRuido:
    """Servidor que emite línea vacía y basura antes del JSON válido.

    Reproduce el caso real del simulador BSDD (que llegó a emitir ``json\\n\\n``)
    y de líneas no-JSON en el buffer. El HAL debe descartarlas y quedarse con
    el primer ``weight_kg`` válido.
    """

    peso: float
    solo_basura: bool = False
    _server: asyncio.Server | None = field(default=None, init=False, repr=False)
    port: int = field(default=0, init=False)

    async def _handler(self, reader, writer):  # noqa: D102
        try:
            await reader.readline()
            writer.write(b"\n")
            writer.write(b"no-es-json\n")
            if not self.solo_basura:
                writer.write(
                    json.dumps({"weight_kg": self.peso, "status": "stable"}).encode()
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
async def test_tcp_read_weight_ignora_lineas_vacias_y_basura():
    server = _ServidorTCPConRuido(peso=987.6)
    await server.start()
    try:
        hal = TcpScaleHAL("127.0.0.1", server.port, timeout=2)
        assert await hal.read_weight() == 987.6
    finally:
        await server.stop()


@pytest.mark.asyncio
async def test_tcp_read_weight_solo_basura_devuelve_none():
    server = _ServidorTCPConRuido(peso=0.0, solo_basura=True)
    await server.start()
    try:
        hal = TcpScaleHAL("127.0.0.1", server.port, timeout=0.5)
        assert await hal.read_weight() is None
    finally:
        await server.stop()


@dataclass
class _ServidorTCPRafaga:
    """Emite una ráfaga de líneas por petición (peso manipulándose).

    La última línea es el peso asentado; el HAL debe drenar y quedarse con ella
    en vez de devolver la primera (estado viejo).
    """

    pesos: list[float]
    _server: asyncio.Server | None = field(default=None, init=False, repr=False)
    _writers: list[asyncio.StreamWriter] = field(default_factory=list, init=False)
    port: int = field(default=0, init=False)

    async def _handler(self, reader, writer):  # noqa: D102
        self._writers.append(writer)
        try:
            while True:
                linea = await reader.readline()
                if not linea:
                    break
                for i, peso in enumerate(self.pesos):
                    estado = "stable" if i == len(self.pesos) - 1 else "reading"
                    writer.write(
                        json.dumps({"weight_kg": peso, "status": estado}).encode()
                        + b"\n"
                    )
                await writer.drain()
        finally:
            writer.close()

    async def start(self) -> None:  # noqa: D102
        self._server = await asyncio.start_server(self._handler, "127.0.0.1", 0)
        self.port = self._server.sockets[0].getsockname()[1]

    async def stop(self) -> None:  # noqa: D102
        server, self._server = self._server, None
        if server is not None:
            server.close()
        for writer in self._writers:
            writer.close()
        self._writers.clear()
        if server is not None:
            try:
                await asyncio.wait_for(server.wait_closed(), timeout=2.0)
            except (TimeoutError, OSError):
                pass


@pytest.mark.asyncio
async def test_tcp_leer_muestra_drena_y_devuelve_la_mas_reciente():
    server = _ServidorTCPRafaga(pesos=[100.0, 200.0, 300.0, 350.0])
    await server.start()
    hal = TcpScaleHAL("127.0.0.1", server.port, timeout=2, intervalo=0.5)
    try:
        assert await hal.conectar() is True
        peso, status = await hal.leer_muestra()
        assert peso == 350.0
        assert status == "stable"
    finally:
        await hal.cerrar()
        await server.stop()


@pytest.mark.asyncio
async def test_sesion_no_estable_mientras_el_peso_cambia():
    server = _ServidorTCP(peso=500, status="reading")
    await server.start()
    balanza = SimpleNamespace(
        id_balanza="00000000-0000-0000-0000-0000000000aa",
        ip_address="127.0.0.1",
        puerto_tcp=server.port,
        puerto_com=None,
    )
    manager = get_scale_session_manager()
    try:
        sesion = await manager.obtener(balanza)
        assert sesion.peso_kg == 500
        assert sesion.estable is False
    finally:
        await manager.cerrar_todas()
        await server.stop()


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
    assert payload["conectado"] is True
    assert payload["estable"] is True


@pytest.mark.asyncio
async def test_endpoint_peso_en_vivo_reutiliza_conexion(
    db, app, client, empresa, server_tcp
):
    """El emparejamiento persiste: varios polls comparten una sola conexión."""
    balanza = await _balanza_empresa(db, empresa)
    for _ in range(3):
        resp = await client.get(f"/api/v1/weighing/scale/{balanza.id_balanza}/live")
        assert resp.status_code == 200
        assert resp.json()["peso_kg"] == 25000
    assert server_tcp.conexiones == 1


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
