"""Tests de la API del SERVIDOR (APP_ROLE=server).

Verifican el flujo central de cuenta/licencia contra una DB PostgreSQL
dedicada (balansoft_ws_server_test): registro de cuenta, login global con
dispositivo, listado/alta de licencias, refresh, panel del proveedor y
recepción de sync de una estación local.
"""

from __future__ import annotations

import os
import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, datetime

import httpx
import pytest
import pytest_asyncio
from sqlalchemy import text, update
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import NullPool

from app.api.v1.endpoints.servidor import router as server_router
from app.core.database import get_server_db
from app.core.security import hash_password
from app.models_server import ProveedorUsuario, ServerBase


def _url_para_bbdd(url: str, nombre: str) -> str:
    head, _, _ = url.rpartition("/")
    return f"{head}/{nombre}"


# DB de prueba del servidor (independiente de la DB local).
TEST_SERVER_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL_SERVER",
    _url_para_bbdd(os.environ.get("DATABASE_URL", "postgresql+asyncpg://sqlman:7767@localhost:5432/balansoft_ws"), "balansoft_ws_server_test"),
)


@pytest_asyncio.fixture(scope="module")
async def _server_engine():
    engine = create_async_engine(TEST_SERVER_DATABASE_URL, poolclass=NullPool)
    async with engine.begin() as conn:
        await conn.run_sync(ServerBase.metadata.drop_all)
        await conn.run_sync(ServerBase.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(ServerBase.metadata.drop_all)
    await engine.dispose()


@pytest_asyncio.fixture
async def server_db(_server_engine) -> AsyncGenerator[AsyncSession, None]:
    session_factory = async_sessionmaker(
        bind=_server_engine, class_=AsyncSession, expire_on_commit=False
    )
    async with session_factory() as session:
        yield session
    await _truncar_server_db(_server_engine)


async def _truncar_server_db(engine) -> None:
    tabla = ", ".join(t.name for t in reversed(ServerBase.metadata.sorted_tables))
    async with engine.begin() as conn:
        await conn.execute(text(f"TRUNCATE TABLE {tabla} RESTART IDENTITY CASCADE"))


@pytest_asyncio.fixture(autouse=True)
async def _aislar_server_db(_server_engine) -> AsyncGenerator[None, None]:
    """Vacía la BD del servidor tras **cada** test del módulo.

    ``server_db`` solo trunca cuando el test lo recibe, pero varias pruebas
    crean filas llamando a la API sin pedirlo; esas filas quedaban visibles
    para el siguiente test y, como ``dispositivos.hardware_id`` es **único
    global**, dos cuentas distintas que reutilizaban ``HW-TITULAR`` chocaban
    con ``403 Dispositivo registrado en otra cuenta``. Con el truncado
    automático el aislamiento deja de depender de que el test pida la sesión.
    """
    yield
    await _truncar_server_db(_server_engine)


@pytest.mark.asyncio
async def test_registro_login_licencias_y_sync(
    _server_engine,
) -> None:
    """Flujo completo: registro → login (dispositivo) → licencias → sync."""
    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        rif = f"J-{uuid.uuid4().hex[:10]}".upper()
        email = f"server-{uuid.uuid4().hex[:8]}@test.com"
        key = f"BWS-{uuid.uuid4().hex[:12].upper()}"

        r = await ac.post(
            "/api/v1/auth/register",
            json={
                "empresa_nombre": "Servidor Test SA",
                "empresa_rif": rif,
                "email_admin": email,
                "usuario_nombre": "Admin",
                "password": "pass123456",
                "licencia_key": key,
                "licencia_tier": "CENTRAL",
                "fecha_expira": "2027-12-31T00:00:00Z",
                "max_equipos": 2,
            },
        )
        assert r.status_code == 201, r.text
        data = r.json()
        assert data["cuenta"]["rif_nit"] == rif
        assert data["licencia"]["licencia_tier"] == "CENTRAL"

        r = await ac.post(
            "/api/v1/auth/login",
            json={
                "email": email,
                "password": "pass123456",
                "hardware_id": "HW-TEST-001",
                "nombre_equipo": "Estacion-A",
            },
        )
        assert r.status_code == 200, r.text
        login = r.json()
        assert login["dispositivo"]["hardware_id"] == "HW-TEST-001"

        r = await ac.get(
            "/api/v1/licencias", headers={"Authorization": f"Bearer {login['access_token']}"}
        )
        assert r.status_code == 200
        assert len(r.json()) == 1

        r = await ac.post(
            "/api/v1/sync/server",
            headers={"Authorization": f"Bearer {login['access_token']}"},
            json={
                "tipo": "push",
                "items": [
                    {
                        "entidad": "pesaje",
                        "operacion": "create",
                        "entidad_id": "BOL-1",
                        "payload": {"neto": 100.5},
                    }
                ],
            },
        )
        assert r.status_code == 200, r.text
        assert r.json()["recibidos"] == 1


@pytest.mark.asyncio
async def test_rif_duplicado_rechazado(_server_engine) -> None:
    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    payload = {
        "empresa_nombre": "Duplicada SA",
        "empresa_rif": "J-999999999",
        "email_admin": f"dup-{uuid.uuid4().hex[:8]}@test.com",
        "usuario_nombre": "Admin",
        "password": "pass123456",
        "licencia_key": f"BWS-{uuid.uuid4().hex[:12].upper()}",
        "licencia_tier": "DEMO",
        "fecha_expira": "2027-12-31T00:00:00Z",
    }
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r1 = await ac.post("/api/v1/auth/register", json=payload)
        assert r1.status_code == 201
        r2 = await ac.post("/api/v1/auth/register", json=payload)
        assert r2.status_code == 400
        assert "RIF" in r2.json()["detail"]


@pytest.mark.asyncio
async def test_login_credencial_invalida(_server_engine) -> None:
    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": "noexiste@test.com", "password": "x", "hardware_id": "HW-1"},
        )
        assert r.status_code == 401


async def _registrar_cuenta(
    ac: httpx.AsyncClient, rif: str, email: str, **extra
) -> dict:
    cuerpo = {
        "empresa_nombre": f"Cliente {rif}",
        "empresa_rif": rif,
        "email_admin": email,
        "usuario_nombre": "Admin",
        "password": "pass123456",
        "licencia_key": f"BWS-{uuid.uuid4().hex[:12].upper()}",
        "licencia_tier": "CENTRAL",
        "fecha_expira": "2027-12-31T00:00:00Z",
    }
    cuerpo.update(extra)
    r = await ac.post("/api/v1/auth/register", json=cuerpo)
    assert r.status_code == 201, r.text
    return r.json()


async def _admin_titular(
    ac: httpx.AsyncClient, rif: str, email: str, *, hardware: str = "HW-TITULAR"
) -> tuple[dict, dict]:
    """Da de alta una cuenta CENTRAL y la activa desde el equipo titular.

    Devuelve ``(alta, login)``. El equipo dueño queda ``SERVIDOR_LOCAL`` y su
    token es el que usa la tutora para aprobar equipos (RB-12).
    """
    alta = await _registrar_cuenta(ac, rif, email)
    r = await ac.post(
        "/api/v1/auth/login",
        json={"email": email, "password": "pass123456", "hardware_id": hardware},
    )
    assert r.status_code == 200, r.text
    return alta, r.json()


async def _operador(server_db, id_cuenta: uuid.UUID, email: str) -> None:
    """Añade una credencial no-ADMIN (equipo nuevo de la misma cuenta)."""
    from app.models_server import Credencial

    server_db.add(
        Credencial(
            id_cuenta=id_cuenta,
            email=email,
            password_hash=hash_password("oper123456"),
            rol_global="OPERADOR",
        )
    )
    await server_db.commit()


@pytest.mark.asyncio
async def test_primer_dispositivo_queda_como_titular_servidor(_server_engine) -> None:
    """Regla del titular: el PRIMER equipo que valida la cuenta es el dueño de
    la licencia (SERVIDOR_LOCAL) y por tanto puede instalarse como servidor."""
    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"titular-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        await _registrar_cuenta(ac, rif, email)

        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "pass123456", "hardware_id": "HW-TITULAR"},
        )
        assert r.status_code == 200, r.text
        disp = r.json()["dispositivo"]
        assert disp["rol"] == "SERVIDOR_LOCAL"
        assert disp["puede_ser_servidor"] is True


@pytest.mark.asyncio
async def test_segundo_dispositivo_queda_como_trabajador(
    _server_engine, server_db
) -> None:
    """Regla del titular: el 2.º equipo es LOCAL y solo opera si se aprueba.

    RB-12 cambió esta expectativa **a propósito**: en una licencia CENTRAL el
    equipo que no es el dueño ya no entra directo —nace ``PENDIENTE``— y la
    tutora debe aprobarlo. Antes de RB-12 esta prueba veía un 200 en el primer
    intento; ahora el 200 llega solo tras aprobar (la regla del titular
    —LOCAL, nunca servidor— se comprueba igual).
    """
    from sqlalchemy import select

    from app.models_server import Credencial, Dispositivo

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"dos-{uuid.uuid4().hex[:8]}@test.com"
    email_operador = f"oper-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        alta, login_admin = await _admin_titular(ac, rif, email)
        assert login_admin["dispositivo"]["rol"] == "SERVIDOR_LOCAL"

        server_db.add(
            Credencial(
                id_cuenta=uuid.UUID(alta["cuenta"]["id_cuenta"]),
                email=email_operador,
                password_hash=hash_password("oper123456"),
                rol_global="OPERADOR",
            )
        )
        await server_db.commit()

        cuerpo = {
            "email": email_operador,
            "password": "oper123456",
            "hardware_id": "HW-SEGUNDO",
        }
        # RB-12: bloqueado en el primer intento (equipo nuevo sin aprobar).
        r = await ac.post("/api/v1/auth/login", json=cuerpo)
        assert r.status_code == 403, r.text
        assert "pendiente de aprobación" in r.json()["detail"]

        pendiente = (
            await server_db.execute(
                select(Dispositivo).where(Dispositivo.hardware_id == "HW-SEGUNDO")
            )
        ).scalar_one()
        assert pendiente.estado == "PENDIENTE"

        # La tutora lo aprueba con un rol de sesión.
        r = await ac.patch(
            f"/api/v1/auth/sesiones/{pendiente.id_dispositivo}",
            headers={"Authorization": f"Bearer {login_admin['access_token']}"},
            json={"estado": "APROBADO", "rol_sesion": "OPERADOR"},
        )
        assert r.status_code == 200, r.text
        assert r.json()["es_dueno"] is False

        r = await ac.post("/api/v1/auth/login", json=cuerpo)
        assert r.status_code == 200, r.text
        disp = r.json()["dispositivo"]
        assert disp["rol"] == "LOCAL"
        assert disp["puede_ser_servidor"] is False
        assert disp["rol_sesion"] == "OPERADOR"


# ---------------------------------------------------------------------------
# RB-12 · aprobación de equipos (docs/SESIONES.md)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_rb12_listado_de_sesiones_y_permisos(_server_engine, server_db) -> None:
    """``GET /auth/sesiones``: solo ADMIN, con el dueño marcado y el pendiente visible."""
    from sqlalchemy import select

    from app.models_server import Dispositivo

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"rb12l-{uuid.uuid4().hex[:8]}@test.com"
    email_oper = f"rb12lo-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        alta, login_admin = await _admin_titular(ac, rif, email)
        await _operador(server_db, uuid.UUID(alta["cuenta"]["id_cuenta"]), email_oper)

        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email_oper, "password": "oper123456", "hardware_id": "HW-PEND"},
        )
        assert r.status_code == 403, r.text

        r = await ac.get(
            "/api/v1/auth/sesiones",
            headers={"Authorization": f"Bearer {login_admin['access_token']}"},
        )
        assert r.status_code == 200, r.text
        datos = r.json()
        por_hw = {i["hardware_id"]: i for i in datos["items"]}
        assert datos["hardware_titular"] == "HW-TITULAR"
        assert por_hw["HW-TITULAR"]["es_dueno"] is True
        assert por_hw["HW-TITULAR"]["estado"] == "APROBADO"
        assert por_hw["HW-TITULAR"]["rol_sesion"] == "ADMIN"
        assert por_hw["HW-PEND"]["estado"] == "PENDIENTE"
        assert por_hw["HW-PEND"]["es_dueno"] is False
        assert por_hw["HW-PEND"]["activo"] is False

        # Aprobar y comprobar que el listado se reflexiona y que un OPERADOR
        # (no ADMIN) no puede listar ni aprobar equipos.
        pend = (
            await server_db.execute(
                select(Dispositivo).where(Dispositivo.hardware_id == "HW-PEND")
            )
        ).scalar_one()
        r = await ac.patch(
            f"/api/v1/auth/sesiones/{pend.id_dispositivo}",
            headers={"Authorization": f"Bearer {login_admin['access_token']}"},
            json={"estado": "APROBADO", "rol_sesion": "OPERADOR"},
        )
        assert r.status_code == 200, r.text
        assert r.json()["estado"] == "APROBADO"

        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email_oper, "password": "oper123456", "hardware_id": "HW-PEND"},
        )
        assert r.status_code == 200, r.text
        disp_oper = r.json()["dispositivo"]
        assert disp_oper["estado"] == "APROBADO"
        assert disp_oper["rol_sesion"] == "OPERADOR"
        cabecera_oper = {"Authorization": f"Bearer {r.json()['access_token']}"}

        # Solo ADMIN: un OPERADOR no lista ni aprueba equipos.
        r = await ac.get("/api/v1/auth/sesiones", headers=cabecera_oper)
        assert r.status_code == 403, r.text
        r = await ac.patch(
            f"/api/v1/auth/sesiones/{pend.id_dispositivo}",
            headers=cabecera_oper,
            json={"estado": "RECHAZADO"},
        )
        assert r.status_code == 403, r.text


@pytest.mark.asyncio
async def test_rb12_aprobar_exige_rol_de_sesion(_server_engine, server_db) -> None:
    """Aprobar sin ``rol_sesion`` es 422; el equipo sigue bloqueado."""
    from sqlalchemy import select

    from app.models_server import Dispositivo

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"rb12r-{uuid.uuid4().hex[:8]}@test.com"
    email_oper = f"rb12ro-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        alta, login_admin = await _admin_titular(ac, rif, email)
        await _operador(server_db, uuid.UUID(alta["cuenta"]["id_cuenta"]), email_oper)
        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email_oper, "password": "oper123456", "hardware_id": "HW-R1"},
        )
        assert r.status_code == 403, r.text
        pend = (
            await server_db.execute(
                select(Dispositivo).where(Dispositivo.hardware_id == "HW-R1")
            )
        ).scalar_one()

        cabecera = {"Authorization": f"Bearer {login_admin['access_token']}"}
        r = await ac.patch(
            f"/api/v1/auth/sesiones/{pend.id_dispositivo}",
            headers=cabecera,
            json={"estado": "APROBADO"},
        )
        assert r.status_code == 422, r.text
        # Sigue bloqueado: aprobar no ocurrió a medias.
        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email_oper, "password": "oper123456", "hardware_id": "HW-R1"},
        )
        assert r.status_code == 403, r.text

        # Un cuerpo vacío también es 422 (no hay nada que cambiar).
        r = await ac.patch(
            f"/api/v1/auth/sesiones/{pend.id_dispositivo}",
            headers=cabecera,
            json={},
        )
        assert r.status_code == 422, r.text


@pytest.mark.asyncio
async def test_rb12_titular_no_es_modificable(_server_engine, server_db) -> None:
    """El equipo dueño de la licencia no se aprueba, rechaza ni cambia de rol."""
    from sqlalchemy import select

    from app.models_server import Dispositivo

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"rb12t-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        _alta, login_admin = await _admin_titular(ac, rif, email)
        dueno = (
            await server_db.execute(
                select(Dispositivo).where(Dispositivo.hardware_id == "HW-TITULAR")
            )
        ).scalar_one()
        cabecera = {"Authorization": f"Bearer {login_admin['access_token']}"}
        for cuerpo in (
            {"estado": "RECHAZADO"},
            {"rol_sesion": "TRABAJADOR"},
            {"estado": "APROBADO", "rol_sesion": "OPERADOR"},
        ):
            r = await ac.patch(
                f"/api/v1/auth/sesiones/{dueno.id_dispositivo}",
                headers=cabecera,
                json=cuerpo,
            )
            assert r.status_code == 422, r.text
        # Y sigue siendo el titular operativo.
        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "pass123456", "hardware_id": "HW-TITULAR"},
        )
        assert r.status_code == 200, r.text
        assert r.json()["dispositivo"]["rol"] == "SERVIDOR_LOCAL"


@pytest.mark.asyncio
async def test_rb12_aislamiento_entre_cuentas(_server_engine, server_db) -> None:
    """La cuenta B no ve ni modifica los equipos de la cuenta A (404)."""
    from sqlalchemy import select

    from app.models_server import Dispositivo

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        rif_a = f"J-{uuid.uuid4().hex[:10]}".upper()
        email_a = f"rb12a-{uuid.uuid4().hex[:8]}@test.com"
        email_oper_a = f"rb12ao-{uuid.uuid4().hex[:8]}@test.com"
        alta_a, _login_a = await _admin_titular(ac, rif_a, email_a, hardware="HW-A-TITULAR")
        await _operador(server_db, uuid.UUID(alta_a["cuenta"]["id_cuenta"]), email_oper_a)
        r = await ac.post(
            "/api/v1/auth/login",
            json={
                "email": email_oper_a,
                "password": "oper123456",
                "hardware_id": "HW-A-PEND",
            },
        )
        assert r.status_code == 403, r.text
        equipo_a = (
            await server_db.execute(
                select(Dispositivo).where(Dispositivo.hardware_id == "HW-A-PEND")
            )
        ).scalar_one()

        # Cuenta B, con su propio titular.
        rif_b = f"J-{uuid.uuid4().hex[:10]}".upper()
        email_b = f"rb12b-{uuid.uuid4().hex[:8]}@test.com"
        _alta_b, login_b = await _admin_titular(ac, rif_b, email_b, hardware="HW-B-TITULAR")
        cabecera_b = {"Authorization": f"Bearer {login_b['access_token']}"}

        r = await ac.patch(
            f"/api/v1/auth/sesiones/{equipo_a.id_dispositivo}",
            headers=cabecera_b,
            json={"estado": "APROBADO", "rol_sesion": "OPERADOR"},
        )
        assert r.status_code == 404, r.text  # no 403: no se filtra su existencia

        r = await ac.get("/api/v1/auth/sesiones", headers=cabecera_b)
        assert r.status_code == 200, r.text
        assert {i["hardware_id"] for i in r.json()["items"]} == {"HW-B-TITULAR"}

        # El equipo de A sigue pendiente (B no lo aprobó).
        r = await ac.post(
            "/api/v1/auth/login",
            json={
                "email": email_oper_a,
                "password": "oper123456",
                "hardware_id": "HW-A-PEND",
            },
        )
        assert r.status_code == 403, r.text


@pytest.mark.asyncio
async def test_rb12_rechazar_bloquea_login_y_token_vigente(
    _server_engine, server_db
) -> None:
    """Rechazar un equipo mata su sesión vigente y su próximo login (403)."""
    from sqlalchemy import select

    from app.models_server import Dispositivo

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"rb12x-{uuid.uuid4().hex[:8]}@test.com"
    email_oper = f"rb12xo-{uuid.uuid4().hex[:8]}@test.com"
    cuerpo_login = {"email": email_oper, "password": "oper123456", "hardware_id": "HW-X"}
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        alta, login_admin = await _admin_titular(ac, rif, email)
        await _operador(server_db, uuid.UUID(alta["cuenta"]["id_cuenta"]), email_oper)
        cabecera_admin = {"Authorization": f"Bearer {login_admin['access_token']}"}

        r = await ac.post("/api/v1/auth/login", json=cuerpo_login)
        assert r.status_code == 403, r.text
        equipo = (
            await server_db.execute(
                select(Dispositivo).where(Dispositivo.hardware_id == "HW-X")
            )
        ).scalar_one()
        r = await ac.patch(
            f"/api/v1/auth/sesiones/{equipo.id_dispositivo}",
            headers=cabecera_admin,
            json={"estado": "APROBADO", "rol_sesion": "OPERADOR"},
        )
        assert r.status_code == 200, r.text

        r = await ac.post("/api/v1/auth/login", json=cuerpo_login)
        assert r.status_code == 200, r.text
        token_oper = r.json()["access_token"]
        cabecera_oper = {"Authorization": f"Bearer {token_oper}"}
        r = await ac.get("/api/v1/licencias", headers=cabecera_oper)
        assert r.status_code == 200, r.text  # el equipo aprobado sí opera

        r = await ac.patch(
            f"/api/v1/auth/sesiones/{equipo.id_dispositivo}",
            headers=cabecera_admin,
            json={"estado": "RECHAZADO"},
        )
        assert r.status_code == 200, r.text
        assert r.json()["estado"] == "RECHAZADO"
        assert r.json()["activo"] is False

        # El token que ya tenía deja de servir (defensa en profundidad: el
        # estado del equipo se re-verifica en cada petición del servidor).
        r = await ac.get("/api/v1/licencias", headers=cabecera_oper)
        assert r.status_code == 403, r.text
        # La tutora sigue operando con normalidad.
        r = await ac.get("/api/v1/licencias", headers=cabecera_admin)
        assert r.status_code == 200, r.text
        # ...y el equipo rechazado no vuelve a entrar.
        r = await ac.post("/api/v1/auth/login", json=cuerpo_login)
        assert r.status_code == 403, r.text
        assert "rechazado" in r.json()["detail"]


@pytest.mark.asyncio
async def test_rb12_equipo_pendiente_no_es_el_dispositivo_del_sync(
    _server_engine, server_db
) -> None:
    """Un equipo pendiente no compite como dispositivo activo del sync.

    El lote se atribuye al equipo activo (la tutora); si el pendiente contara
    como activo podría robar la atribución por tener una ``ultima_conexion``
    más reciente.
    """
    from sqlalchemy import select

    from app.models_server import Dispositivo, SyncSesion

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"rb12s-{uuid.uuid4().hex[:8]}@test.com"
    email_oper = f"rb12so-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        alta, login_admin = await _admin_titular(ac, rif, email)
        await _operador(server_db, uuid.UUID(alta["cuenta"]["id_cuenta"]), email_oper)
        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email_oper, "password": "oper123456", "hardware_id": "HW-SYNC"},
        )
        assert r.status_code == 403, r.text
        pendiente = (
            await server_db.execute(
                select(Dispositivo).where(Dispositivo.hardware_id == "HW-SYNC")
            )
        ).scalar_one()
        dueno = (
            await server_db.execute(
                select(Dispositivo).where(Dispositivo.hardware_id == "HW-TITULAR")
            )
        ).scalar_one()

        r = await ac.post(
            "/api/v1/sync/server",
            headers={"Authorization": f"Bearer {login_admin['access_token']}"},
            json={
                "tipo": "push",
                "items": [
                    {
                        "entidad": "pesaje",
                        "operacion": "create",
                        "entidad_id": "1",
                        "payload": {"peso": 10},
                    }
                ],
            },
        )
        assert r.status_code == 200, r.text
        # El sync no falla por el equipo pendiente y se atribuye al de la tutora.
        r = await ac.get(
            "/api/v1/auth/sesiones",
            headers={"Authorization": f"Bearer {login_admin['access_token']}"},
        )
        assert r.status_code == 200
        sync_sesion = (await server_db.execute(select(SyncSesion))).scalars().one()
        assert sync_sesion.id_dispositivo == dueno.id_dispositivo
        assert sync_sesion.id_dispositivo != pendiente.id_dispositivo


@pytest.mark.asyncio
async def test_rb12_demo_conserva_el_bloqueo_previo(_server_engine, server_db) -> None:
    """DEMO no estrena el gate de RB-12: ya bloqueaba el 2.º equipo.

    En DEMO el rechazo del segundo equipo lo hace la comprobación de titular
    (previa a RB-12) y **no** crea una fila de dispositivo: RB-12 no cambia
    este camino ni deja un equipo pendiente en una licencia de un solo equipo.
    """
    from sqlalchemy import select

    from app.models_server import Credencial, Dispositivo

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"rb12d-{uuid.uuid4().hex[:8]}@test.com"
    email_oper = f"rb12do-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        alta = await _registrar_cuenta(ac, rif, email, licencia_tier="DEMO")
        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "pass123456", "hardware_id": "HW-D1"},
        )
        assert r.status_code == 200, r.text
        server_db.add(
            Credencial(
                id_cuenta=uuid.UUID(alta["cuenta"]["id_cuenta"]),
                email=email_oper,
                password_hash=hash_password("oper123456"),
                rol_global="OPERADOR",
            )
        )
        await server_db.commit()

        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email_oper, "password": "oper123456", "hardware_id": "HW-D2"},
        )
        assert r.status_code == 403, r.text
        # Es el gate de titular previo a RB-12 (DEMO = un solo equipo), no el
        # de aprobación: el mensaje identifica al equipo titular.
        assert "equipo titular" in r.json()["detail"]
        assert r.json()["hardware_titular"] == "HW-D1"
        # Diagnóstico: el 403 dice qué huella ENVIÓ este equipo, para poder
        # reconciliar el titular sin adivinar (incidente 2026-10-14).
        assert r.json()["hardware_recibido"] == "HW-D2"
        # Y no se dejó una fila PENDIENTE colgando en la cuenta.
        equipos = (
            await server_db.execute(
                select(Dispositivo).where(Dispositivo.hardware_id == "HW-D2")
            )
        ).scalar_one_or_none()
        assert equipos is None


@pytest.mark.asyncio
async def test_rb12_fila_preexistente_sin_estado_sigue_operando(
    _server_engine, server_db
) -> None:
    """Compatibilidad: un equipo creado antes de RB-12 (sin ``estado``) no se
    auto-bloquea; el DEFAULT de la columna lo deja aprobado."""
    from sqlalchemy import select

    from app.models_server import Credencial, Dispositivo

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"rb12c-{uuid.uuid4().hex[:8]}@test.com"
    email_oper = f"rb12co-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        alta, _login_admin = await _admin_titular(ac, rif, email)
        id_cuenta = uuid.UUID(alta["cuenta"]["id_cuenta"])
        # INSERT crudo omitiendo `estado`: así se prueba el DEFAULT del DDL
        # (lo que hace la migración con las filas que ya existían), no el
        # default de Python del modelo.
        await server_db.execute(
            text(
                "INSERT INTO dispositivos "
                "(id_dispositivo, id_cuenta, hardware_id, rol_dispositivo, activo, "
                " created_at, updated_at) "
                "VALUES (:id, :cuenta, 'HW-ANTIGUO', 'LOCAL', TRUE, :now, :now)"
            ),
            {"id": uuid.uuid4(), "cuenta": id_cuenta, "now": datetime.now(UTC).replace(tzinfo=None)},
        )
        server_db.add(
            Credencial(
                id_cuenta=id_cuenta,
                email=email_oper,
                password_hash=hash_password("oper123456"),
                rol_global="OPERADOR",
            )
        )
        await server_db.commit()
        server_db.expire_all()

        antiguo = (
            await server_db.execute(
                select(Dispositivo).where(Dispositivo.hardware_id == "HW-ANTIGUO")
            )
        ).scalar_one()
        assert antiguo.estado == "APROBADO"
        assert antiguo.activo is True

        r = await ac.post(
            "/api/v1/auth/login",
            json={
                "email": email_oper,
                "password": "oper123456",
                "hardware_id": "HW-ANTIGUO",
            },
        )
        assert r.status_code == 200, r.text
        assert r.json()["dispositivo"]["estado"] == "APROBADO"


@pytest.mark.asyncio
async def test_planes_ws_no_admite_monopuesto(_server_engine) -> None:
    """WS solo ofrece **DEMO** y **CENTRAL**: MONOPUESTO se rechaza al registrar.

    Decisión de producto (docs/PLANES-PAGOS.md §2): una estación de pesaje
    necesita como mínimo 3 sesiones simultáneas, así que el tier MONOPUESTO del
    producto ganadero (BALANSOFT SG) **no** aplica a WS y el esquema lo rechaza
    antes de crear la cuenta. El LM debe emitir solo DEMO|CENTRAL para WS.
    """
    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/auth/register",
            json={
                "empresa_nombre": "Monopuesto SA",
                "empresa_rif": f"J-{uuid.uuid4().hex[:10]}".upper(),
                "email_admin": f"mono-{uuid.uuid4().hex[:8]}@test.com",
                "usuario_nombre": "Admin",
                "password": "pass123456",
                "licencia_key": f"BWS-{uuid.uuid4().hex[:12].upper()}",
                "licencia_tier": "MONOPUESTO",
                "fecha_expira": "2027-12-31T00:00:00Z",
            },
        )
        assert r.status_code == 422, r.text


@pytest.mark.asyncio
async def test_titular_no_pierde_el_rol_al_reingresar(_server_engine) -> None:
    """El titular conserva SERVIDOR_LOCAL aunque su sesión se cierre y vuelva
    a validar la licencia (no debe degradarse a LOCAL)."""
    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"reing-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        await _registrar_cuenta(ac, rif, email)
        for _ in range(2):
            r = await ac.post(
                "/api/v1/auth/login",
                json={"email": email, "password": "pass123456", "hardware_id": "HW-REEN"},
            )
            assert r.status_code == 200, r.text
            assert r.json()["dispositivo"]["rol"] == "SERVIDOR_LOCAL"


@pytest.mark.asyncio
async def test_rol_titular_se_autocorrige_segun_la_licencia(
    _server_engine, server_db
) -> None:
    """El rol del titular lo manda la LICENCIA, no el orden de las filas.

    Caso real de campo: la fila del equipo quedó como ``LOCAL`` (se había
    registrado antes de existir la regla, o por un equipo de pruebas) pero la
    licencia sí está atada a ese mismo hardware. Al volver a validar la cuenta
    el rol se corrige solo, sin editar la base a mano.
    """
    from sqlalchemy import select

    from app.models_server import Dispositivo, Licencia

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"corr-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        alta = await _registrar_cuenta(ac, rif, email)
        id_cuenta = uuid.UUID(alta["cuenta"]["id_cuenta"])

        # La licencia queda atada a HW-BUTACA, pero la fila nace degradada.
        await server_db.execute(
            update(Licencia)
            .where(Licencia.id_cuenta == id_cuenta)
            .values(hardware_id="HW-BUTACA")
        )
        server_db.add(
            Dispositivo(
                id_cuenta=id_cuenta,
                hardware_id="HW-BUTACA",
                rol_dispositivo="LOCAL",
            )
        )
        server_db.add(
            Dispositivo(
                id_cuenta=id_cuenta,
                hardware_id="HW-OTRO",
                rol_dispositivo="SERVIDOR_LOCAL",  # rol obsoleto
            )
        )
        await server_db.commit()

        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "pass123456", "hardware_id": "HW-BUTACA"},
        )
        assert r.status_code == 200, r.text
        assert r.json()["dispositivo"]["rol"] == "SERVIDOR_LOCAL"
        assert r.json()["dispositivo"]["puede_ser_servidor"] is True

        # Y el equipo que tenía el rol viejo lo pierde: solo hay un titular.
        roles = dict(
            (
                await server_db.execute(
                    select(Dispositivo.hardware_id, Dispositivo.rol_dispositivo).where(
                        Dispositivo.id_cuenta == id_cuenta
                    )
                )
            ).all()
        )
        assert roles == {"HW-BUTACA": "SERVIDOR_LOCAL", "HW-OTRO": "LOCAL"}


@pytest.mark.asyncio
async def test_panel_designar_titular(_server_engine, server_db) -> None:
    """El panel puede reatar la licencia a otro equipo registrado y recalcula roles."""
    from app.models_server import Cuenta, Dispositivo, Licencia

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    cuenta = Cuenta(
        rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        nombre_fiscal="Titular SA",
        email_admin=f"tit-{uuid.uuid4().hex[:8]}@test.com",
        activa=True,
    )
    server_db.add(cuenta)
    await server_db.flush()
    server_db.add(
        Licencia(
            id_cuenta=cuenta.id_cuenta,
            licencia_key=f"BWS-TIT-{uuid.uuid4().hex[:12].upper()}",
            licencia_tier="CENTRAL",
            licencia_status="ACTIVA",
            fecha_expira=datetime(2030, 1, 1),
            hardware_id="HW-VIEJO",
        )
    )
    server_db.add(
        Dispositivo(id_cuenta=cuenta.id_cuenta, hardware_id="HW-VIEJO", rol_dispositivo="LOCAL")
    )
    server_db.add(
        Dispositivo(id_cuenta=cuenta.id_cuenta, hardware_id="HW-NUEVO", rol_dispositivo="LOCAL")
    )
    prov = ProveedorUsuario(
        email=f"prov-{uuid.uuid4().hex[:8]}@tit.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SOPORTE",
    )
    server_db.add(prov)
    await server_db.commit()

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        token = r.json()["access_token"]
        auth = {"Authorization": f"Bearer {token}"}

        # Un equipo de otra cuenta no sirve.
        r = await ac.post(
            f"/api/v1/panel/cuentas/{cuenta.id_cuenta}/titular",
            json={"hardware_id": "HW-AJENO"},
            headers=auth,
        )
        assert r.status_code == 404, r.text

        r = await ac.post(
            f"/api/v1/panel/cuentas/{cuenta.id_cuenta}/titular",
            json={"hardware_id": "HW-NUEVO"},
            headers=auth,
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["hardware_titular"] == "HW-NUEVO"
        roles = {d["hardware_id"]: d["rol_dispositivo"] for d in body["dispositivos"]}
        assert roles == {"HW-VIEJO": "LOCAL", "HW-NUEVO": "SERVIDOR_LOCAL"}


@pytest.mark.asyncio
async def test_licencia_virgen_available_se_amarra_al_primer_equipo(
    _server_engine, server_db
) -> None:
    """AVAILABLE = licencia VIRGEN: no está rechazada.

    El primer equipo que valida la cuenta se amarra a la licencia como titular
    único (SERVIDOR_LOCAL) y la licencia queda ACTIVA. Antes, el estado AVAILABLE
    del LM se guardaba en `licencias.licencia_status` y el central la takeoff
    como inválida (`_licencia_activa` exigía ACTIVA), dejando al equipo sin
    poder instalarse como servidor (docs/MANEJO_DB.md §13).
    """
    from sqlalchemy import select

    from app.api.v1.endpoints.servidor import _normalizar_estado_lm
    from app.models_server import Dispositivo, Licencia

    # El AVAILABLE del LM nunca debe escribirse como estado de la cuenta.
    assert _normalizar_estado_lm("AVAILABLE") == "ACTIVA"
    assert _normalizar_estado_lm("DEVICE_NOT_REGISTERED") == "ACTIVA"
    assert _normalizar_estado_lm("ACTIVE") == "ACTIVA"
    assert _normalizar_estado_lm("SUSPENDED") == "SUSPENDIDA"

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"virgen-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        alta = await _registrar_cuenta(ac, rif, email)
        id_cuenta = uuid.UUID(alta["cuenta"]["id_cuenta"])

        # Licencia virgen: estado heredado AVAILABLE (fila vieja del sync) y sin
        # hardware atado.
        await server_db.execute(
            update(Licencia)
            .where(Licencia.id_cuenta == id_cuenta)
            .values(licencia_status="AVAILABLE", hardware_id=None)
        )
        server_db.add(
            Dispositivo(
                id_cuenta=id_cuenta, hardware_id="HW-PRUEBA", rol_dispositivo="LOCAL"
            )
        )
        await server_db.commit()

        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "pass123456", "hardware_id": "HW-NUEVO"},
        )
        assert r.status_code == 200, r.text
        # Este equipo es el titular y el otro queda como trabajador.
        assert r.json()["dispositivo"]["rol"] == "SERVIDOR_LOCAL"
        assert r.json()["licencia"]["licencia_status"] == "ACTIVA"
        assert r.json()["licencia"]["hardware_id"] == "HW-NUEVO"

        roles = dict(
            (
                await server_db.execute(
                    select(Dispositivo.hardware_id, Dispositivo.rol_dispositivo).where(
                        Dispositivo.id_cuenta == id_cuenta
                    )
                )
            ).all()
        )
        assert roles == {"HW-PRUEBA": "LOCAL", "HW-NUEVO": "SERVIDOR_LOCAL"}


@pytest.mark.asyncio
async def test_licencia_suspendida_bloquea_login(_server_engine, server_db) -> None:
    from sqlalchemy import select

    from app.models_server import Licencia

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"sus-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/auth/register",
            json={
                "empresa_nombre": "Susp SA",
                "empresa_rif": rif,
                "email_admin": email,
                "usuario_nombre": "Admin",
                "password": "pass123456",
                "licencia_key": f"BWS-{uuid.uuid4().hex[:12].upper()}",
                "licencia_tier": "CENTRAL",
                "fecha_expira": "2027-12-31T00:00:00Z",
            },
        )
        assert r.status_code == 201
        key = r.json()["licencia"]["licencia_key"]

        # El fixture server_db comparte la misma BD: consultar y suspender.
        lic = (
            await server_db.execute(
                select(Licencia).where(Licencia.licencia_key == key)
            )
        ).scalar_one()
        lic.licencia_status = "SUSPENDIDA"
        await server_db.commit()

        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "pass123456", "hardware_id": "HW-SUSP"},
        )
        assert r.status_code == 403


@pytest.mark.asyncio
async def test_panel_proveedor_login_y_cuentas(_server_engine, server_db) -> None:

    from app.models_server import Cuenta

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    # Cuenta existente visible para el panel.
    cuenta = Cuenta(
        rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        nombre_fiscal="Panel Test SA",
        email_admin=f"panel-{uuid.uuid4().hex[:8]}@test.com",
        activa=True,
    )
    server_db.add(cuenta)
    prov = ProveedorUsuario(
        email=f"prov-{uuid.uuid4().hex[:8]}@test.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SOPORTE",
    )
    server_db.add(prov)
    await server_db.commit()
    await server_db.refresh(prov)

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        assert r.status_code == 200, r.text
        token = r.json()["access_token"]

        r = await ac.get(
            "/api/v1/panel/cuentas", headers={"Authorization": f"Bearer {token}"}
        )
        assert r.status_code == 200
        rifs = [c["rif_nit"] for c in r.json()]
        assert cuenta.rif_nit in rifs


@pytest.mark.asyncio
async def test_sync_sin_auth_rechazado(_server_engine) -> None:
    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/sync/server",
            json={"tipo": "push", "items": []},
        )
        assert r.status_code == 401


@pytest.mark.asyncio
async def test_sync_usuarios_crea_credenciales(_server_engine, server_db) -> None:
    """Una estación sincroniza usuarios → se crean credenciales globales."""
    from sqlalchemy import select

    from app.models_server import Credencial

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"sy-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/auth/register",
            json={
                "empresa_nombre": "Sync Users SA",
                "empresa_rif": rif,
                "email_admin": email,
                "usuario_nombre": "Admin",
                "password": "pass123456",
                "licencia_key": f"BWS-{uuid.uuid4().hex[:12].upper()}",
                "licencia_tier": "CENTRAL",
                "fecha_expira": "2027-12-31T00:00:00Z",
            },
        )
        assert r.status_code == 201
        token = r.json()["access_token"]

        nuevo = f"op-{uuid.uuid4().hex[:8]}@test.com"
        r = await ac.post(
            "/api/v1/sync/users",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "items": [
                    {
                        "email": nuevo,
                        "nombre": "Operador Sinc",
                        "rol_global": "OPERADOR",
                        "activo": True,
                        "operacion": "upsert",
                    }
                ]
            },
        )
        assert r.status_code == 200, r.text
        assert r.json()["procesados"] == 1
        assert r.json()["errores"] == 0

        cred = (
            await server_db.execute(
                select(Credencial).where(Credencial.email == nuevo)
            )
        ).scalar_one_or_none()
        assert cred is not None
        assert cred.rol_global == "OPERADOR"

        # Upsert nuevamente: no debe duplicar, debe actualizar el rol.
        server_db.expire_all()
        r = await ac.post(
            "/api/v1/sync/users",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "items": [
                    {
                        "email": nuevo,
                        "nombre": "Operador Sinc",
                        "rol_global": "AUDITOR",
                        "activo": True,
                        "operacion": "upsert",
                    }
                ]
            },
        )
        assert r.status_code == 200
        credetado = (
            await server_db.execute(
                select(Credencial).where(Credencial.email == nuevo)
            )
        ).scalar_one()
        assert credetado.rol_global == "AUDITOR"


@pytest.mark.asyncio
async def test_panel_verificar_licencia_contra_lm(
    _server_engine, server_db, monkeypatch
) -> None:
    """El panel verifica la licencia en el LM local (mockeado).

    Aptitud según la política del LM: producto WS + cliente asociado +
    distribuidor asignado. AVAILABLE con esos datos => válida (se activará
    en el primer uso de la estación).
    """
    from app.api.v1.endpoints import servidor as servidor_mod
    from app.core.config import settings
    from app.core.license_client import LicenseError

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    prov = ProveedorUsuario(
        email=f"prov-{uuid.uuid4().hex[:8]}@lm.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SOPORTE",
    )
    server_db.add(prov)
    await server_db.commit()
    await server_db.refresh(prov)

    apta: dict = {
        "exists": True,
        "status": "AVAILABLE",
        "tier": "CENTRAL",
        "plan_type": "basic",
        "product_code": settings.license_product_code,
        "has_client": True,
        "client_name": "Cliente Ejemplo C.A.",
        "distributor_id": "d1a2b3c4-0000-0000-0000-000000000001",
        "distributor_name": "Distribuidora Ejemplo",
        "requires_activation": True,
    }

    class _FakeLm:
        def check(self, license_key: str) -> dict:
            if license_key == "BWS-NOEXISTE":
                raise LicenseError("Check LM fallido (404)")
            return apta

    monkeypatch.setattr(servidor_mod, "get_license_client", lambda: _FakeLm())

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        assert r.status_code == 200
        token = r.json()["access_token"]

        r = await ac.post(
            "/api/v1/panel/verificar-licencia",
            headers={"Authorization": f"Bearer {token}"},
            json={"licencia_key": "BWS-VALIDA-0000"},
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["valida"] is True
        assert body["status"] == "AVAILABLE"
        assert body["tier"] == "CENTRAL"
        assert "activará" in body["message"]

        r = await ac.post(
            "/api/v1/panel/verificar-licencia",
            headers={"Authorization": f"Bearer {token}"},
            json={"licencia_key": "BWS-NOEXISTE"},
        )
        assert r.status_code == 200, r.text
        assert r.json()["valida"] is False


@pytest.mark.asyncio
async def test_panel_verificar_licencia_requisitos_lm(
    _server_engine, server_db, monkeypatch
) -> None:
    """Solo son válidas las licencias WS con cliente y distribuidor (política LM)."""
    from app.api.v1.endpoints import servidor as servidor_mod

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    prov = ProveedorUsuario(
        email=f"prov-{uuid.uuid4().hex[:8]}@requisitos.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SUPERADMIN",
    )
    server_db.add(prov)
    await server_db.commit()

    casos = {
        "BWS-OTRO-PROD": {
            "exists": True,
            "status": "AVAILABLE",
            "product_code": "OTRO",
            "has_client": True,
            "distributor_id": "d-otro",
        },
        "BWS-SIN-CLIENTE": {
            "exists": True,
            "status": "AVAILABLE",
            "product_code": "BWS",
            "has_client": False,
        },
        "BWS-SIN-DISTRIB": {
            "exists": True,
            "status": "AVAILABLE",
            "product_code": "BWS",
            "has_client": True,
            "client_name": "Cliente X",
        },
        "BWS-YA-ACTIVA": {
            "exists": True,
            "status": "ACTIVE",
            "product_code": "BWS",
            "has_client": True,
            "client_name": "Otro Cliente",
            "distributor_id": "d-abc",
            "requires_activation": False,
        },
    }

    class _FakeLm:
        def check(self, license_key: str) -> dict:
            return casos[license_key]

    monkeypatch.setattr(servidor_mod, "get_license_client", lambda: _FakeLm())

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        token = r.json()["access_token"]

        for clave, _datos in casos.items():
            r = await ac.post(
                "/api/v1/panel/verificar-licencia",
                headers={"Authorization": f"Bearer {token}"},
                json={"licencia_key": clave},
            )
            assert r.status_code == 200, r.text
            assert r.json()["valida"] is False, f"{clave} no debía ser válida"
            assert r.json()["message"]


@pytest.mark.asyncio
async def test_panel_verificar_licencia_sin_auth(_server_engine) -> None:
    """Sin token de proveedor no se puede verificar licencias."""
    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/verificar-licencia",
            json={"licencia_key": "BWS-LM-0001"},
        )
        assert r.status_code == 401


@pytest.mark.asyncio
async def test_panel_verificar_licencia_estado_invalido(
    _server_engine, server_db, monkeypatch
) -> None:
    """Licencia SUSPENDIDA en el LM -> valida=False."""
    from app.api.v1.endpoints import servidor as servidor_mod

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    prov = ProveedorUsuario(
        email=f"prov-{uuid.uuid4().hex[:8]}@susp.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SUPERADMIN",
    )
    server_db.add(prov)
    await server_db.commit()

    class _LmSusp:
        def check(self, license_key: str) -> dict:
            return {
                "exists": True,
                "status": "SUSPENDIDA",
                "product_code": "BWS",
                "has_client": True,
                "client_name": "Cliente X",
                "distributor_id": "d-abc",
                "requires_activation": False,
            }

    monkeypatch.setattr(servidor_mod, "get_license_client", lambda: _LmSusp())

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        token = r.json()["access_token"]
        r = await ac.post(
            "/api/v1/panel/verificar-licencia",
            headers={"Authorization": f"Bearer {token}"},
            json={"licencia_key": "BWS-SUSP-0000"},
        )
        assert r.status_code == 200, r.text
        assert r.json()["valida"] is False


@pytest.mark.asyncio
async def test_panel_cuenta_detalle(_server_engine, server_db) -> None:
    """Detalle de cuenta: licencias, credenciales y dispositivos."""
    from app.models_server import Credencial, Cuenta, Dispositivo, Licencia

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    cuenta = Cuenta(
        rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        nombre_fiscal="Panmal Test SA",
        email_admin=f"det-{uuid.uuid4().hex[:8]}@test.com",
        activa=True,
    )
    server_db.add(cuenta)
    await server_db.flush()
    server_db.add(
        Licencia(
            id_cuenta=cuenta.id_cuenta,
            licencia_key=f"BWS-DET-{uuid.uuid4().hex[:12].upper()}",
            licencia_tier="CENTRAL",
            licencia_status="ACTIVA",
            fecha_expira=datetime(2030, 1, 1),
        )
    )
    server_db.add(
        Credencial(
            id_cuenta=cuenta.id_cuenta,
            email=f"op-{uuid.uuid4().hex[:8]}@test.com",
            password_hash=hash_password("op123456"),
            rol_global="OPERADOR",
        )
    )
    server_db.add(
        Dispositivo(
            id_cuenta=cuenta.id_cuenta,
            hardware_id="HW-DET-1",
            rol_dispositivo="LOCAL",
        )
    )
    prov = ProveedorUsuario(
        email=f"prov-{uuid.uuid4().hex[:8]}@det.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SOPORTE",
    )
    server_db.add(prov)
    await server_db.commit()

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        token = r.json()["access_token"]
        r = await ac.get(
            f"/api/v1/panel/cuentas/{cuenta.id_cuenta}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["cuenta"]["rif_nit"] == cuenta.rif_nit
        assert len(body["licencias"]) == 1
        assert len(body["credenciales"]) == 1
        assert body["credenciales"][0]["rol_global"] == "OPERADOR"
        assert body["total_dispositivos"] == 1
        assert [d["hardware_id"] for d in body["dispositivos"]] == ["HW-DET-1"]
        assert body["hardware_titular"] is None


@pytest.mark.asyncio
async def test_panel_cuenta_actualizar(_server_engine, server_db) -> None:
    """El panel puede editar la ficha del cliente y su estatus (cuenta/licencia)."""
    from app.models_server import Credencial, Cuenta, Licencia

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    cuenta = Cuenta(
        rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        nombre_fiscal="Cliente Editable SA",
        email_admin=f"edit-{uuid.uuid4().hex[:8]}@test.com",
        activa=True,
    )
    server_db.add(cuenta)
    await server_db.flush()
    server_db.add(
        Licencia(
            id_cuenta=cuenta.id_cuenta,
            licencia_key=f"BWS-EDIT-{uuid.uuid4().hex[:12].upper()}",
            licencia_tier="CENTRAL",
            licencia_status="ACTIVA",
            fecha_expira=datetime(2030, 1, 1),
        )
    )
    # Como en el alta real: la credencial ADMIN comparte email con la cuenta
    server_db.add(
        Credencial(
            id_cuenta=cuenta.id_cuenta,
            email=cuenta.email_admin,
            password_hash=hash_password("admin123456"),
            rol_global="ADMIN",
        )
    )
    prov = ProveedorUsuario(
        email=f"prov-{uuid.uuid4().hex[:8]}@edit.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SUPERADMIN",
    )
    server_db.add(prov)
    await server_db.commit()

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        token = r.json()["access_token"]

        r = await ac.put(
            f"/api/v1/panel/cuentas/{cuenta.id_cuenta}",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "nombre_comercial": "Editable Comercial C.A.",
                "telefono": "+58 412 555 1234",
                "direccion": "Av. Principal, Edif. Central, Piso 2",
                "activa": False,
                "licencia_status": "SUSPENDIDA",
            },
        )
        assert r.status_code == 200, r.text
        body = r.json()
        cuenta_out = body["cuenta"]
        assert cuenta_out["nombre_comercial"] == "Editable Comercial C.A."
        assert cuenta_out["telefono"] == "+58 412 555 1234"
        assert cuenta_out["direccion"] == "Av. Principal, Edif. Central, Piso 2"
        assert cuenta_out["activa"] is False
        assert body["licencias"][0]["licencia_status"] == "SUSPENDIDA"

        # La edición persiste en la DB
        await server_db.refresh(cuenta)
        assert cuenta.activa is False
        assert cuenta.direccion == "Av. Principal, Edif. Central, Piso 2"

        # Estatus de licencia revertido a ACTIVA
        r = await ac.put(
            f"/api/v1/panel/cuentas/{cuenta.id_cuenta}",
            headers={"Authorization": f"Bearer {token}"},
            json={"licencia_status": "ACTIVA", "activa": True},
        )
        assert r.status_code == 200, r.text
        assert r.json()["licencias"][0]["licencia_status"] == "ACTIVA"
        assert r.json()["cuenta"]["activa"] is True

        # Guardar manteniendo el email/admin y el RIF actuales no debe fallar
        r = await ac.put(
            f"/api/v1/panel/cuentas/{cuenta.id_cuenta}",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "email_admin": cuenta.email_admin,
                "rif_nit": cuenta.rif_nit,
            },
        )
        assert r.status_code == 200, r.text


@pytest.mark.asyncio
async def test_panel_cuenta_actualizar_unicidad(_server_engine, server_db) -> None:
    """No se puede duplicar RIF/email de otra cuenta al editar."""
    from app.models_server import Cuenta

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)

    base = f"dup-{uuid.uuid4().hex[:8]}"
    c1 = Cuenta(rif_nit=f"J-1{uuid.uuid4().hex[:10]}".upper(),
                nombre_fiscal="Duplicada 1",
                email_admin=f"{base}1@test.com", activa=True)
    c2 = Cuenta(rif_nit=f"J-2{uuid.uuid4().hex[:10]}".upper(),
                nombre_fiscal="Duplicada 2",
                email_admin=f"{base}2@test.com", activa=True)
    server_db.add_all([c1, c2])
    await server_db.commit()

    prov = ProveedorUsuario(
        email=f"{base}p@test.com",
        password_hash=hash_password("prov123456"),
        nombre="Soporte",
        rol="SUPERADMIN",
    )
    server_db.add(prov)
    await server_db.commit()

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/panel/login",
            json={"email": prov.email, "password": "prov123456"},
        )
        token = r.json()["access_token"]

        r = await ac.put(
            f"/api/v1/panel/cuentas/{c1.id_cuenta}",
            headers={"Authorization": f"Bearer {token}"},
            json={"rif_nit": c2.rif_nit},
        )
        assert r.status_code == 400, r.text
        assert "EIR/NIT" in r.text or "RIF/NIT" in r.text

        r = await ac.put(
            f"/api/v1/panel/cuentas/{c1.id_cuenta}",
            headers={"Authorization": f"Bearer {token}"},
            json={"email_admin": c2.email_admin},
        )
        assert r.status_code == 400, r.text


def _server_app(engine):
    """Aplicación FastAPI con solo los routers del servidor y DB sobreescrita."""
    from fastapi import FastAPI

    application = FastAPI()

    async def _get_server_db() -> AsyncGenerator[AsyncSession, None]:
        session_factory = async_sessionmaker(
            bind=engine, class_=AsyncSession, expire_on_commit=False
        )
        async with session_factory() as session:
            yield session

    application.dependency_overrides[get_server_db] = _get_server_db
    application.include_router(server_router)
    return application

@pytest.mark.asyncio
async def test_refresh_token_sin_sesion_o_caducado_no_renueva(
    _server_engine, server_db
) -> None:
    """M1 (auditoría): un refresh no renueva si su sesión no existe o caducó.

    Antes se rotaba a ciegas: bastaba con presentar un refresh firmado para
    acuñar una sesión nueva con 7 días más, aunque su fila no existiera (token
    fabricado) o estuviera caducada.
    """
    from sqlalchemy import select, update

    from app.core.security import create_refresh_token
    from app.models_server import Credencial, Sesion

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"m1a-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        _alta, login = await _admin_titular(ac, rif, email)

        # Refresh firmado y válido pero SIN fila de sesión (fabricado o purgado).
        cred = (
            await server_db.execute(
                select(Credencial).where(Credencial.email == email)
            )
        ).scalar_one()
        huerfano = create_refresh_token(str(cred.id_credencial))
        r = await ac.post(
            "/api/v1/auth/refresh-token", json={"refresh_token": huerfano}
        )
        assert r.status_code == 401, r.text

        # Sesión caducada: tampoco renueva.
        await server_db.execute(
            update(Sesion)
            .where(Sesion.id_credencial == cred.id_credencial)
            .values(expira=datetime(2020, 1, 1))
        )
        await server_db.commit()
        r = await ac.post(
            "/api/v1/auth/refresh-token",
            json={"refresh_token": login["refresh_token"]},
        )
        assert r.status_code == 401, r.text

        # Y un refresh con firma inválida sigue siendo 401.
        r = await ac.post(
            "/api/v1/auth/refresh-token", json={"refresh_token": "no-es-un-jwt"}
        )
        assert r.status_code == 401, r.text


@pytest.mark.asyncio
async def test_refresh_token_reutilizado_revoca_la_cadena(
    _server_engine, server_db
) -> None:
    """M1 (auditoría): reusar un refresh ya rotado mata la cadena entera.

    La rotación normal revoca la sesión usada y emite otra. Si alguien vuelve a
    presentar la usada (robo), se revocan TODAS las sesiones de la credencial,
    incluida la recién emitida, para que el atacante no pueda mantener viva la
    cadena renovando indefinidamente.
    """
    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"m1b-{uuid.uuid4().hex[:8]}@test.com"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        _alta, login = await _admin_titular(ac, rif, email)
        viejo = login["refresh_token"]

        r = await ac.post("/api/v1/auth/refresh-token", json={"refresh_token": viejo})
        assert r.status_code == 200, r.text
        nuevo = r.json()["refresh_token"]
        assert nuevo != viejo

        # Reuso del viejo → 401 y la cadena cae (el nuevo deja de servir).
        r = await ac.post("/api/v1/auth/refresh-token", json={"refresh_token": viejo})
        assert r.status_code == 401, r.text
        r = await ac.post("/api/v1/auth/refresh-token", json={"refresh_token": nuevo})
        assert r.status_code == 401, r.text

        # El usuario vuelve a iniciar sesión y recupera el acceso con normalidad.
        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "pass123456", "hardware_id": "HW-TITULAR"},
        )
        assert r.status_code == 200, r.text
        r = await ac.post(
            "/api/v1/auth/refresh-token",
            json={"refresh_token": r.json()["refresh_token"]},
        )
        assert r.status_code == 200, r.text


@pytest.mark.asyncio
async def test_rb12_licencia_virgen_no_aprueba_al_primer_equipo_no_admin(
    _server_engine, server_db
) -> None:
    """M2 (auditoría): sin titular, el primer equipo no-ADMIN nace PENDIENTE.

    Con `hardware_id` NULL nadie exigía aprobación, así que si el primer login
    de una licencia CENTRAL virgen no era el del ADMIN (el único que amarra la
    licencia) ese equipo nacía APROBADO y saltaba RB-12 para siempre.
    """
    from sqlalchemy import select, update

    from app.models_server import Dispositivo, Licencia

    app = _server_app(_server_engine)
    transport = httpx.ASGITransport(app=app)
    rif = f"J-{uuid.uuid4().hex[:10]}".upper()
    email = f"m2-{uuid.uuid4().hex[:8]}@test.com"
    email_oper = f"m2o-{uuid.uuid4().hex[:8]}@test.com"
    cuerpo_oper = {"email": email_oper, "password": "oper123456", "hardware_id": "HW-M2"}
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        alta = await _registrar_cuenta(ac, rif, email)
        id_cuenta = uuid.UUID(alta["cuenta"]["id_cuenta"])
        await server_db.execute(
            update(Licencia)
            .where(Licencia.id_cuenta == id_cuenta)
            .values(licencia_status="AVAILABLE", hardware_id=None)
        )
        await server_db.commit()
        await _operador(server_db, id_cuenta, email_oper)

        # Primer login de la licencia virgen y NO es el del ADMIN → pendiente.
        r = await ac.post("/api/v1/auth/login", json=cuerpo_oper)
        assert r.status_code == 403, r.text
        assert "pendiente" in r.json()["detail"].lower()
        equipo = (
            await server_db.execute(
                select(Dispositivo).where(Dispositivo.hardware_id == "HW-M2")
            )
        ).scalar_one()
        assert equipo.estado == "PENDIENTE"

        # El ADMIN amarra la licencia (es el dueño) y entra.
        r = await ac.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "pass123456", "hardware_id": "HW-TITULAR"},
        )
        assert r.status_code == 200, r.text
        cabecera = {"Authorization": f"Bearer {r.json()['access_token']}"}

        # El equipo no-ADMIN sigue pendiente; tras aprobarlo, entra.
        r = await ac.patch(
            f"/api/v1/auth/sesiones/{equipo.id_dispositivo}",
            headers=cabecera,
            json={"estado": "APROBADO", "rol_sesion": "OPERADOR"},
        )
        assert r.status_code == 200, r.text
        r = await ac.post("/api/v1/auth/login", json=cuerpo_oper)
        assert r.status_code == 200, r.text
