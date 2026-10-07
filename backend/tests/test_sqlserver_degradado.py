"""Tests del modo degradado SQL Server (Fase 1).

Cubre el gate de ``get_db``, los exception handlers globales registrados en
``app.main`` y la respuesta de ``/api/v1/environment`` con motor SQL Server.
No toca la BD real: los engines siguen apuntando al PostgreSQL del ``.env``
y los errores se inyectan con ``dependency_overrides``.
"""

from __future__ import annotations

import pytest
from sqlalchemy.exc import ProgrammingError
from starlette.testclient import TestClient

from app.api.dependencies import get_current_empresa, get_current_user
from app.core import db_engine
from app.core.config import settings
from app.core.database import get_db
from app.core.db_engine import (
    CODIGO_ESQUEMA_PENDIENTE,
    CODIGO_SIN_CONEXION,
    MENSAJE_FASE_2,
    MENSAJE_SIN_CONEXION,
    EsquemaPendienteError,
)
from app.main import app as app_real

URL_MSSQL = "mssql+aioodbc://sa:SECRETA@servidor:1433/balansoft"
PASSWORD_PRUEBA = "SECRETA"


@pytest.fixture(autouse=True)
def _estado_esquema_limpio():
    db_engine.reiniciar_estado_esquema()
    yield
    db_engine.reiniciar_estado_esquema()


@pytest.fixture
def app():
    """App global con los overrides de auth/DB limpios y restaurados al final."""
    original = dict(app_real.dependency_overrides)
    app_real.dependency_overrides.clear()
    yield app_real
    app_real.dependency_overrides.clear()
    app_real.dependency_overrides.update(original)


def _forzar_auth(app) -> None:
    """Auth/empresa falsos para llegar al ``Depends(get_db)`` sin JWT."""

    class _Falso:
        id_empresa = "00000000-0000-0000-0000-000000000001"
        rol = "ADMIN"

    app.dependency_overrides[get_current_user] = lambda: _Falso()
    app.dependency_overrides[get_current_empresa] = lambda: _Falso()


class _ResultadoFake:
    def __init__(self, n: int):
        self._n = n

    def scalar_one(self):
        return self._n


class _SesionFake:
    """Sesión asíncrona falsa que registra el SQL ejecutado (sin BD)."""

    def __init__(self, n_tablas: int, capturado: list[str]):
        self._n = n_tablas
        self._capturado = capturado

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        return False

    async def execute(self, stmt):
        self._capturado.append(str(stmt))
        return _ResultadoFake(self._n)


def _db_roto(sqlstate: str, mensaje: str):
    """Dependencia get_db falsa que lanza un DBAPIError con el origen dado."""

    async def _roto():
        raise ProgrammingError(None, None, Exception(sqlstate, mensaje))
        yield  # pragma: no cover (solo para que sea un generador)

    return _roto


# ---------------------------------------------------------------------------
# /api/v1/health — nunca depende de la BD
# ---------------------------------------------------------------------------
def test_health_200_en_modo_degradado(monkeypatch, app):
    monkeypatch.setattr(settings, "database_url", URL_MSSQL)
    r = TestClient(app).get("/api/v1/health")
    assert r.status_code == 200
    assert r.json()["status"] == "healthy"


# ---------------------------------------------------------------------------
# Gate de get_db
# ---------------------------------------------------------------------------
async def test_get_db_lanza_esquema_pendiente_sin_tocar_bd(monkeypatch):
    monkeypatch.setattr(settings, "database_url", URL_MSSQL)
    capturado: list[str] = []
    monkeypatch.setattr(
        "app.core.database.AsyncSessionLocal", lambda: _SesionFake(0, capturado)
    )
    gen = get_db()
    with pytest.raises(EsquemaPendienteError) as excinfo:
        await gen.__anext__()
    await gen.aclose()
    assert MENSAJE_FASE_2 in str(excinfo.value)
    # La consulta barata sí se hizo y es la de SQL Server (sys.tables/dbo).
    assert capturado, "el gate debe consultar el conteo de tablas"
    assert "sys.tables" in capturado[0]


async def test_get_db_sqlserver_con_esquema_listo_entrega_sesion(monkeypatch):
    monkeypatch.setattr(settings, "database_url", URL_MSSQL)
    capturado: list[str] = []
    fake = _SesionFake(12, capturado)
    monkeypatch.setattr("app.core.database.AsyncSessionLocal", lambda: fake)
    gen = get_db()
    session = await gen.__anext__()
    assert session is fake
    await gen.aclose()
    # Sembrado como «aplicado»: no vuelve a consultar en las siguientes.
    assert db_engine.estado_esquema() == "aplicado"
    assert len(capturado) == 1


async def test_gate_postgres_no_consulta(monkeypatch):
    monkeypatch.setattr(
        settings, "database_url", "postgresql+asyncpg://u:p@localhost:5432/bd"
    )
    capturado: list[str] = []
    monkeypatch.setattr(
        "app.core.database.AsyncSessionLocal", lambda: _SesionFake(9, capturado)
    )
    gen = get_db()
    await gen.__anext__()
    await gen.aclose()
    assert not capturado, "con PostgreSQL el gate no debe consultar nada"
    assert db_engine.estado_esquema() is None


# ---------------------------------------------------------------------------
# 503 de esquema pendiente en un endpoint real
# ---------------------------------------------------------------------------
def test_endpoint_devuelve_503_fase2(monkeypatch, app):
    monkeypatch.setattr(settings, "database_url", URL_MSSQL)
    db_engine.marcar_estado_esquema("pendiente")
    _forzar_auth(app)
    r = TestClient(app).get("/api/v1/empresa/series")
    assert r.status_code == 503, r.text
    body = r.json()
    assert body["codigo"] == CODIGO_ESQUEMA_PENDIENTE
    assert "Fase 2" in body["detail"]


# ---------------------------------------------------------------------------
# Traducción de errores crudos de BD (handler manejador_error_bd)
# ---------------------------------------------------------------------------
def test_error_crudo_sql_se_traduce_a_503_en_sqlserver(monkeypatch, app):
    monkeypatch.setattr(settings, "database_url", URL_MSSQL)
    db_engine.marcar_estado_esquema("aplicado")  # el gate pasa; falla la query
    _forzar_auth(app)
    app.dependency_overrides[get_db] = _db_roto(
        "42S02", "Invalid object name 'dbo.usuarios'."
    )
    r = TestClient(app).get("/api/v1/empresa/series")
    assert r.status_code == 503, r.text
    body = r.json()
    assert body["codigo"] == CODIGO_ESQUEMA_PENDIENTE
    assert "Fase 2" in body["detail"]


def test_error_sql_localizado_espanol_tambien_503(monkeypatch, app):
    monkeypatch.setattr(settings, "database_url", URL_MSSQL)
    db_engine.marcar_estado_esquema("aplicado")
    _forzar_auth(app)
    app.dependency_overrides[get_db] = _db_roto(
        "", "No es válida la columna 'peso' en la tabla 'dbo.boletos'."
    )
    r = TestClient(app).get("/api/v1/empresa/series")
    assert r.status_code == 503, r.text
    assert r.json()["codigo"] == CODIGO_ESQUEMA_PENDIENTE


def test_error_no_clasificado_sqlserver_sigue_siendo_500(monkeypatch, app):
    monkeypatch.setattr(settings, "database_url", URL_MSSQL)
    db_engine.marcar_estado_esquema("aplicado")
    _forzar_auth(app)
    app.dependency_overrides[get_db] = _db_roto("42001", "Statement too complex.")
    r = TestClient(app, raise_server_exceptions=False).get("/api/v1/empresa/series")
    assert r.status_code == 500


def test_error_pg_no_se_intercepta_500(monkeypatch, app):
    """Con PostgreSQL el handler re-lanza: 500 de siempre, sin 503."""
    assert settings.db_engine == "postgresql", "este test asume el .env de desarrollo"
    _forzar_auth(app)
    app.dependency_overrides[get_db] = _db_roto(
        "42P01", "relation \"usuarios\" does not exist"
    )
    r = TestClient(app, raise_server_exceptions=False).get("/api/v1/empresa/series")
    assert r.status_code == 500
    assert "Fase 2" not in r.text


def test_error_conexion_sqlserver_503_sin_conexion(monkeypatch, app):
    monkeypatch.setattr(settings, "database_url", URL_MSSQL)
    db_engine.marcar_estado_esquema("aplicado")
    _forzar_auth(app)
    app.dependency_overrides[get_db] = _db_roto(
        "08S01",
        f"[08S01] Communication link failure. UID=sa;PWD={PASSWORD_PRUEBA}",
    )
    r = TestClient(app).get("/api/v1/empresa/series")
    assert r.status_code == 503, r.text
    body = r.json()
    assert body["codigo"] == CODIGO_SIN_CONEXION
    assert body["detail"] == MENSAJE_SIN_CONEXION
    # La password real de DATABASE_URL jamás aparece en la respuesta.
    assert PASSWORD_PRUEBA not in r.text


def test_login_failed_se_traduce_a_503_sin_conexion(monkeypatch, app):
    monkeypatch.setattr(settings, "database_url", URL_MSSQL)
    db_engine.marcar_estado_esquema("aplicado")
    _forzar_auth(app)
    app.dependency_overrides[get_db] = _db_roto(
        "28000", "Login failed for user 'sa'."
    )
    r = TestClient(app).get("/api/v1/empresa/series")
    assert r.status_code == 503, r.text
    assert r.json()["codigo"] == CODIGO_SIN_CONEXION


def test_password_no_se_filtra_en_logs_del_handler(monkeypatch):
    """_texto_orig enmascara la password en crudo y percent-encoded."""
    from app.core.db_engine import _texto_orig

    # Password con carácter especial: aparece %40 en la URL y @ en claro en el
    # error del driver; ambas formas deben quedar como ***.
    monkeypatch.setattr(
        settings, "database_url", "mssql+aioodbc://sa:SECRETA%40123@servidor:1433/bd"
    )
    err = ProgrammingError(
        None,
        None,
        Exception(
            "08S01",
            "Communication link failure. PWD=SECRETA@123; again PWD=SECRETA%40123",
        ),
    )
    texto = _texto_orig(err)
    assert "SECRETA" not in texto
    assert "***" in texto


# ---------------------------------------------------------------------------
# Handlers registrados + /api/v1/environment
# ---------------------------------------------------------------------------
def test_handlers_registrados_en_app(app):
    import sqlalchemy.exc

    assert EsquemaPendienteError in app.exception_handlers
    assert sqlalchemy.exc.DBAPIError in app.exception_handlers


def test_environment_reporta_motor_sqlserver_y_mantiene_clave_postgres(monkeypatch, app):
    capturado: list[str] = []
    monkeypatch.setattr(
        "app.api.v1.endpoints.entorno.AsyncSessionLocal",
        lambda: _SesionFake(0, capturado),
    )
    monkeypatch.setattr(settings, "database_url", URL_MSSQL)
    r = TestClient(app).get("/api/v1/environment")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["motor"] == "sqlserver"
    assert body["estado"] == "incompleto"
    # Clave "postgres" intacta: es el contrato con la app Flutter.
    assert "postgres" in body
    assert body["postgres"]["conectado"] is True
    assert body["postgres"]["esquema_listo"] is False
    assert body["postgres"]["n_tablas"] == 0
    assert capturado and "sys.tables" in capturado[0]


def test_environment_postgres_payload_regresion(monkeypatch, app):
    capturado: list[str] = []
    monkeypatch.setattr(
        "app.api.v1.endpoints.entorno.AsyncSessionLocal",
        lambda: _SesionFake(5, capturado),
    )
    monkeypatch.setattr(
        settings, "database_url", "postgresql+asyncpg://u:p@localhost:5432/balansoft_ws"
    )
    r = TestClient(app).get("/api/v1/environment")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["motor"] == "postgresql"
    assert body["estado"] == "ok"
    assert body["postgres"] == {
        "conectado": True,
        "esquema_listo": True,
        "n_tablas": 5,
        "bd": "balansoft_ws",
    }
    assert set(body) >= {"estado", "motor", "sistema", "api", "postgres", "hardware"}
    assert capturado and "pg_tables" in capturado[0]
