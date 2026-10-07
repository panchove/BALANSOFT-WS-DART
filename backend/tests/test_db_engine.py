"""Tests unitarios de app/core/db_engine.py y del validador _coherencia_motores.

Sin base de datos: ``Settings`` se instancia con ``_env_file=None`` y URLs
explícitas (OJO: nunca se usa el ``settings`` global con lru_cache de
``get_settings``; cada test construye su propia instancia).
"""

from __future__ import annotations

import time
from typing import Any
from urllib.parse import quote

import pytest
from pydantic import ValidationError

from app.core.config import Settings
from app.core.db_engine import (
    MENSAJE_FASE_2,
    PREFIJO_SYNC,
    EsquemaPendienteError,
    _estado_fresco,
    asegurar_esquema_listo,
    derivar_url_sync,
    detectar_motor,
    dsn_pyodbc,
    error_drivers_faltantes,
    marcar_estado_esquema,
    puerto_default,
    reiniciar_estado_esquema,
    sanear_password_en_mensaje,
    sql_conteo_tablas,
)

PREFIXES_PG = ["postgresql+asyncpg://", "postgresql://", "postgresql+psycopg2://"]
PREFIXES_MSSQL = ["mssql+aioodbc://", "mssql+pyodbc://", "mssql://"]


@pytest.fixture(autouse=True)
def _cache_esquema_limpio():
    reiniciar_estado_esquema()
    yield
    reiniciar_estado_esquema()


def _settings(**kw: Any) -> Settings:
    """Settings de prueba sin leer ningún .env (``_env_file`` no lo declara mypy)."""
    return Settings(**{"_env_file": None, **kw})


# ---------------------------------------------------------------------------
# detectar_motor
# ---------------------------------------------------------------------------
def test_detectar_motor_postgres_todos_los_prefijos():
    for prefijo in PREFIXES_PG:
        assert detectar_motor(f"{prefijo}user:pass@localhost:5432/bd") == "postgresql"


def test_detectar_motor_sqlserver_todos_los_prefijos():
    for prefijo in PREFIXES_MSSQL:
        assert detectar_motor(f"{prefijo}user:pass@localhost:1433/bd") == "sqlserver"


def test_detectar_motor_prefijo_desconocido_lanza_value_error():
    with pytest.raises(ValueError) as excinfo:
        detectar_motor("oracle+cx_Oracle://user:pass@host:1521/bd")
    texto = str(excinfo.value)
    assert "no soportado" in texto
    # El mensaje lista los prefijos aceptados (ayuda a quien instala).
    for prefijo in PREFIJO_SYNC:
        assert prefijo in texto


def test_puerto_default_por_motor():
    assert puerto_default("postgresql") == 5432
    assert puerto_default("sqlserver") == 1433


# ---------------------------------------------------------------------------
# derivar_url_sync
# ---------------------------------------------------------------------------
def test_derivar_sync_postgres_cambia_solo_prefijo():
    url = "postgresql+asyncpg://sqlman:7767@localhost:5432/balansoft_ws"
    assert (
        derivar_url_sync(url) == "postgresql+psycopg2://sqlman:7767@localhost:5432/balansoft_ws"
    )


def test_derivar_sync_postgres_con_query_se_conserva():
    url = "postgresql+asyncpg://u:p@h:5432/bd?sslmode=require&application_name=wserver"
    esperado = "postgresql+psycopg2://u:p@h:5432/bd?sslmode=require&application_name=wserver"
    assert derivar_url_sync(url) == esperado


def test_derivar_sync_sqlserver_preserva_query_params():
    url = (
        "mssql+aioodbc://u:p@servidor:1433/bd?"
        "driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes"
    )
    esperado = (
        "mssql+pyodbc://u:p@servidor:1433/bd?"
        "driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes"
    )
    assert derivar_url_sync(url) == esperado
    # byte a byte: solo cambia el prefijo
    assert derivar_url_sync(url)[len("mssql+pyodbc://") :] == url[len("mssql+aioodbc://") :]


def test_derivar_sync_lanza_value_error_si_prefijo_no_vale():
    with pytest.raises(ValueError):
        derivar_url_sync("mysql://u:p@h/bd")


# ---------------------------------------------------------------------------
# Settings: _coherencia_motores + property db_engine
# ---------------------------------------------------------------------------
def test_settings_sync_vacio_se_deriva():
    s = _settings(
        database_url="mssql+aioodbc://u:p@servidor:1433/bd",
        database_url_sync="",
    )
    assert s.database_url_sync == "mssql+pyodbc://u:p@servidor:1433/bd"


def test_settings_sync_incoherente_se_deriva_de_database_url():
    s = _settings(
        database_url="mssql+aioodbc://u:p@servidor:1433/bd?TrustServerCertificate=yes",
        database_url_sync="postgresql+psycopg2://u:p@localhost:5432/otra_bd",
    )
    # Precedencia de DATABASE_URL: se deriva en memoria, el .env no se toca.
    assert s.database_url_sync == (
        "mssql+pyodbc://u:p@servidor:1433/bd?TrustServerCertificate=yes"
    )


def test_settings_sync_coherente_se_conserva():
    sync = "mssql+pyodbc://u:p@servidor:1433/bd?TrustServerCertificate=yes&Encrypt=yes"
    s = _settings(
        database_url="mssql+aioodbc://u:p@servidor:1433/bd?TrustServerCertificate=yes",
        database_url_sync=sync,
    )
    assert s.database_url_sync == sync


def test_settings_postgres_regresion_intacta():
    """El camino PG sigue produciendo exactamente la misma pareja de URLs."""
    s = _settings(
        database_url="postgresql+asyncpg://sqlman:7767@localhost:5432/balansoft_ws",
        database_url_sync="postgresql+psycopg2://sqlman:7767@localhost:5432/balansoft_ws",
    )
    assert s.database_url_sync == "postgresql+psycopg2://sqlman:7767@localhost:5432/balansoft_ws"
    assert s.db_engine == "postgresql"


def test_settings_db_engine_property():
    pg = _settings(
        database_url="postgresql+asyncpg://u:p@h:5432/bd",
        database_url_sync="postgresql+psycopg2://u:p@h:5432/bd",
    )
    mssql = _settings(
        database_url="mssql+aioodbc://u:p@h:1433/bd",
        database_url_sync="mssql+pyodbc://u:p@h:1433/bd",
    )
    assert pg.db_engine == "postgresql"
    assert mssql.db_engine == "sqlserver"


def test_settings_url_desconocida_fall_fast():
    with pytest.raises(ValidationError) as excinfo:
        _settings(
            database_url="oracle://u:p@h:1521/bd",
            database_url_sync="",
        )
    assert "no soportado" in str(excinfo.value)


def test_settings_server_database_url_no_se_toca():
    """SERVER_DATABASE_URL (BD del central) queda fuera del validador."""
    s = _settings(
        database_url="mssql+aioodbc://u:p@h:1433/bd",
        database_url_sync="",
        server_database_url="postgresql+asyncpg://otro:otro@central:5432/server",
    )
    assert s.server_database_url == "postgresql+asyncpg://otro:otro@central:5432/server"
    assert s.active_server_database_url == "postgresql+asyncpg://otro:otro@central:5432/server"


# ---------------------------------------------------------------------------
# SQL por motor
# ---------------------------------------------------------------------------
def test_sql_conteo_tablas_postgres_contiene_pg_tables():
    sql = sql_conteo_tablas("postgresql")
    assert "pg_tables" in sql
    assert "schemaname" in sql
    assert "sys.tables" not in sql


def test_sql_conteo_tablas_sqlserver_contiene_sys_tables_y_dbo():
    sql = sql_conteo_tablas("sqlserver")
    assert "sys.tables" in sql
    assert "SCHEMA_NAME(schema_id)" in sql
    assert "N'dbo'" in sql
    assert "pg_tables" not in sql


def test_dsn_pyodbc_desescapa_los_espacios_del_driver():
    dsn = dsn_pyodbc(
        {
            "host": "servidor",
            "port": 1433,
            "db": "balansoft",
            "user": "sa",
            "password": "secreta",
            "driver": "ODBC+Driver+18+for+SQL+Server",
            "params": {"TrustServerCertificate": "yes"},
        }
    )
    assert dsn.startswith("DRIVER={ODBC Driver 18 for SQL Server};")
    assert "SERVER=servidor,1433;" in dsn
    assert "DATABASE=balansoft;" in dsn
    assert "UID=sa;" in dsn
    assert "PWD=secreta;" in dsn
    assert "TrustServerCertificate=yes;" in dsn
    assert "driver=" not in dsn.lower().replace("driver={", "")


def test_dsn_pyodbc_sin_driver_usa_el_por_defecto():
    dsn = dsn_pyodbc({"host": "h", "port": 1433, "db": "bd", "user": "u", "password": "p"})
    assert "DRIVER={ODBC Driver 18 for SQL Server};" in dsn


# ---------------------------------------------------------------------------
# Drivers ODBC faltantes
# ---------------------------------------------------------------------------
def test_error_drivers_faltantes_menciona_extra():
    err = error_drivers_faltantes("sqlserver", ModuleNotFoundError("No module named 'pyodbc'"))
    assert isinstance(err, RuntimeError)
    assert "uv sync --extra sqlserver" in str(err)
    assert "aioodbc" in str(err)
    assert "pyodbc" in str(err)
    assert "ODBC Driver 18" in str(err)
    assert "No module named 'pyodbc'" in str(err)


# ---------------------------------------------------------------------------
# Caché de estado del esquema
# ---------------------------------------------------------------------------
def test_cache_estado_esquema_flujo_basico():
    from app.core.db_engine import estado_esquema

    assert estado_esquema() is None
    marcar_estado_esquema("pendiente")
    assert estado_esquema() == "pendiente"
    assert _estado_fresco() is True
    marcar_estado_esquema("aplicado")
    assert estado_esquema() == "aplicado"
    reiniciar_estado_esquema()
    assert estado_esquema() is None


def test_cache_pendiente_vence_tras_el_ttl():
    from app.core import db_engine

    marcar_estado_esquema("pendiente")
    # Backdate: se marca como si hubiera pasado el TTL de 60 s.
    db_engine._estado_marcado_en = time.monotonic() - (db_engine._TTL_PENDIENTE_SEG + 1)
    assert _estado_fresco() is False
    # «aplicado» no caduca (pegajoso): nada que comprobar con TTL.


def test_cache_estado_invalido_es_rechazado():
    with pytest.raises(ValueError):
        marcar_estado_esquema("cualquier_cosa")


async def test_asegurar_esquema_listo_postgres_es_no_op(monkeypatch):
    """Con PostgreSQL el gate no toca nada (camino intacto)."""
    from app.core import config as config_module
    from app.core.db_engine import estado_esquema

    monkeypatch.setattr(
        config_module.settings, "database_url", "postgresql+asyncpg://u:p@localhost:5432/bd"
    )
    await asegurar_esquema_listo()  # no lanza y no consulta
    assert estado_esquema() is None


def test_mensaje_fase_2_es_explicito():
    assert "Fase 2" in MENSAJE_FASE_2
    assert "degradado" in MENSAJE_FASE_2
    assert issubclass(EsquemaPendienteError, Exception)


# ---------------------------------------------------------------------------
# MED-001: sanear_password_en_mensaje
# ---------------------------------------------------------------------------
@pytest.mark.parametrize(
    ("entrada", "esperado"),
    [
        # Conn-string ODBC: PWD con ; de cierre (el valor se corta en el ;).
        (
            "[08S01] Communication link failure. PWD=supersecreto; SERVER=h,",
            "[08S01] Communication link failure. password=***; SERVER=h,",
        ),
        # Conn-string ODBC: Password con espacios alrededor del =.
        ("Login falló: Password = abc;UID=svc", "Login falló: password=***;UID=svc"),
        # Conn-string ODBC: uid/pwd en minúsculas.
        ("uid=user;pwd=pass;", "uid=user;password=***;"),
        # URL con ; dentro de la password (se corta en @).
        ("fallo en ://user:mi;clave@host/bd", "fallo en ://user:***@host/bd"),
        # Password con = (tanto en DSN como en URL).
        ("PWD=ab=cd;SERVER=h", "password=***;SERVER=h"),
        ("fallo en ://user:ab=cd@host/bd", "fallo en ://user:***@host/bd"),
        # Mayúsculas/minúsculas indistintas.
        ("PASSWORD=otra;X=1", "password=***;X=1"),
    ],
)
def test_sanear_password_en_mensaje_cubre_dsn_y_url(entrada, esperado):
    assert sanear_password_en_mensaje(entrada) == esperado


def test_sanear_password_en_mensaje_no_altera_el_resto():
    """Solo cambia la password: el resto del mensaje queda byte a byte."""
    entrada = "ERROR 28000: Login failed for user 'sa'. PWD=secreta; DATABASE=bd;"
    salida = sanear_password_en_mensaje(entrada)
    assert "secreta" not in salida
    assert "password=***" in salida
    assert salida.startswith("ERROR 28000: Login failed for user 'sa'. ")
    assert salida.endswith("; DATABASE=bd;")


def test_sanear_password_en_mensaje_es_idempotente():
    una_vez = sanear_password_en_mensaje("PWD=valor;://u:p@h")
    assert sanear_password_en_mensaje(una_vez) == una_vez


def test_sanear_password_en_mensaje_no_toca_texto_sin_password():
    assert sanear_password_en_mensaje("relation \"usuarios\" does not exist") == (
        'relation "usuarios" does not exist'
    )


def test_texto_orig_enmascara_password_cruda_y_codificada(monkeypatch):
    """Caso preexistente (MED-001): crudo + percent-encoded + DSN PWD=."""
    from app.core import config as config_module
    from app.core.db_engine import _texto_orig

    pwd = "SECRETA@123"
    monkeypatch.setattr(
        config_module.settings,
        "database_url",
        f"mssql+aioodbc://sa:{quote(pwd, safe='')}@servidor:1433/bd",
    )
    err = RuntimeError(
        f"link failure. PWD={pwd} y tambien url ://sa:{pwd}@servidor"
    )
    texto = _texto_orig(err)
    assert "SECRETA" not in texto
    assert pwd not in texto
    assert quote(pwd, safe="") not in texto
    assert "password=***" in texto
    assert "link failure." in texto


def test_texto_orig_sanea_password_ajena_a_database_url(monkeypatch):
    """Una password que NO es la de DATABASE_URL también se enmascara (MED-001)."""
    from app.core import config as config_module
    from app.core.db_engine import _texto_orig

    monkeypatch.setattr(
        config_module.settings,
        "database_url", "mssql+aioodbc://sa:otraclave@servidor:1433/bd"
    )
    texto = _texto_orig(RuntimeError("login failed. UID=svc;PWD=distinta;"))
    assert "distinta" not in texto
    assert "UID=svc;" in texto
    assert "password=***" in texto


# ---------------------------------------------------------------------------
# LOW-001: un fallo de conexión al contar tablas restablece la caché
# ---------------------------------------------------------------------------
async def test_asegurar_esquema_listo_fallo_de_conexion_resetea_cache(monkeypatch):
    from app.core import config as config_module
    from app.core import db_engine
    from app.core.db_engine import estado_esquema

    monkeypatch.setattr(
        config_module.settings, "database_url", "mssql+aioodbc://u:p@h:1433/bd"
    )
    # "pendiente" caduco (TTL vencido): sin el reset seguiría enmascarando.
    marcar_estado_esquema("pendiente")
    db_engine._estado_marcado_en = time.monotonic() - (
        db_engine._TTL_PENDIENTE_SEG + 1
    )

    async def _consulta_falla():
        raise OSError("Communication link failure")

    monkeypatch.setattr(db_engine, "_consultar_esquema_sqlserver", _consulta_falla)

    with pytest.raises(OSError):
        await asegurar_esquema_listo()

    # La caché vuelve al valor inicial {valor: None, ts: 0.0}: el reintento
    # no ve un "pendiente" caduco.
    assert estado_esquema() is None
    assert db_engine._estado_marcado_en == 0.0


async def test_asegurar_esquema_listo_postgres_no_toca_cache_si_falla(monkeypatch):
    """Con PostgreSQL el gate sigue intacto: ni consulta ni toca la caché."""
    from app.core import config as config_module
    from app.core import db_engine
    from app.core.db_engine import estado_esquema

    monkeypatch.setattr(
        config_module.settings,
        "database_url",
        "postgresql+asyncpg://u:p@localhost:5432/bd",
    )
    marcar_estado_esquema("pendiente")

    async def _no_debe_llamarse():
        raise AssertionError("con PostgreSQL no se consulta el esquema")

    monkeypatch.setattr(db_engine, "_consultar_esquema_sqlserver", _no_debe_llamarse)
    await asegurar_esquema_listo()
    assert estado_esquema() == "pendiente", "la caché PG no cambia"
