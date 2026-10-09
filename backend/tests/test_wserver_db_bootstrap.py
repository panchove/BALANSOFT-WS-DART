"""Tests del bootstrap de BD de wserver.py (PostgreSQL + SQL Server Fase 1).

Los drivers se sustituyen por fakes (``monkeypatch.setitem(sys.modules, …)``),
así que aquí NO se abre ninguna conexión real: se verifica el SQL exacto que
ejecuta cada rama y que la rama SQL Server jamás aplica DDL de PostgreSQL.
"""

from __future__ import annotations

import argparse
import importlib.machinery
import sys
import types
from typing import Any

import pytest

import wserver
from app.core import db_engine

URL_PG = "postgresql+psycopg2://miusuario:mipass@servidorpg:5432/balansoft_ws_local"
URL_MSSQL = "mssql+pyodbc://sa:P%40ss@10.0.0.5:1433/balansoft"


@pytest.fixture(autouse=True)
def _estado_esquema_limpio():
    db_engine.reiniciar_estado_esquema()
    yield
    db_engine.reiniciar_estado_esquema()


# ---------------------------------------------------------------------------
# Fakes de drivers
# ---------------------------------------------------------------------------
class _Ident:
    def __init__(self, nombre: str):
        self.nombre = nombre

    def __str__(self) -> str:
        return '"' + self.nombre.replace('"', '""') + '"'


class _SqlInstr:
    def __init__(self, plantilla: str):
        self.plantilla = plantilla

    def format(self, ident: _Ident) -> str:
        return self.plantilla.replace("{}", str(ident))


class _CursorPG:
    def __init__(self, conn: _ConexionPG):
        self._conn = conn

    def execute(self, sql, params=None):  # noqa: ANN001 (str o Composable)
        self._conn.sql.append(str(sql))
        self._conn.params.append(params)

    def fetchone(self):
        return self._conn.resultados.pop(0) if self._conn.resultados else None

    def fetchall(self):
        return list(self._conn.resultados)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def close(self):
        pass


class _ConexionPG:
    def __init__(self, resultados=None):
        self.resultados = list(resultados or [])
        self.sql: list[str] = []
        self.params: list = []
        self.kwargs: dict = {}
        self.autocommit = False
        self.cerrada = False

    def cursor(self) -> _CursorPG:
        return _CursorPG(self)

    def close(self):
        self.cerrada = True

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.cerrada = True
        return False


def _psycopg2_falso(resultados=None, falla: bool = False):
    """Módulo psycopg2 falso; ``resultados`` es la cola de ``fetchone``."""
    return _ModPsycopg2(resultados, falla)


class _ModPsycopg2(types.ModuleType):
    """Subclase de ModuleType para que mypy conozca los atributos falsos."""

    conexiones: list
    connect: Any
    sql: Any

    def __init__(self, resultados=None, falla: bool = False):
        super().__init__("psycopg2")
        self.conexiones = []
        self._resultados = resultados
        self._falla = falla
        self.connect = self._conectar
        self.sql = types.SimpleNamespace(SQL=_SqlInstr, Identifier=_Ident)

    def _conectar(self, **kwargs):
        if self._falla:
            raise OSError("could not connect to server: Connection refused")
        conn = _ConexionPG(self._resultados)
        conn.kwargs = kwargs
        self.conexiones.append(conn)
        return conn


class _CursorMSSQL:
    def __init__(self, conn: _ConexionMSSQL):
        self._conn = conn

    def execute(self, sql, params=None):  # noqa: ANN001
        self._conn.sql.append(str(sql))

    def fetchone(self):
        sql = self._conn.sql[-1] if self._conn.sql else ""
        return self._conn.respuestas(sql)

    def close(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *_exc):  # noqa: ANN002
        self.close()


class _ConexionMSSQL:
    def __init__(self, dsn: str, respuestas):
        self.dsn = dsn
        self.respuestas = respuestas
        self.sql: list[str] = []
        self.autocommit = False
        self.timeout = 0
        self.cerrada = False

    def cursor(self) -> _CursorMSSQL:
        return _CursorMSSQL(self)

    def commit(self):
        pass

    def close(self):
        self.cerrada = True


def _respuestas_vacias(sql: str) -> tuple:
    """BD sin tablas y sin crear todavía (por defecto en casi todos los tests)."""
    if "DB_ID" in sql:
        return (None,)
    if "sys.tables" in sql:
        return (0,)
    return (None,)


class _ModPyodbc(types.ModuleType):
    """pyodbc fake con __spec__ (para find_spec) y atributos declarados."""

    conexiones: list
    connect: Any

    def __init__(self, respuestas=None, falla: bool = False):
        super().__init__("pyodbc")
        self.__spec__ = importlib.machinery.ModuleSpec("pyodbc", loader=None)
        self.conexiones = []
        self._respuestas = respuestas or _respuestas_vacias
        self._falla = falla
        self.connect = self._conectar

    def _conectar(self, dsn, autocommit=False, timeout=0):  # noqa: ANN001
        if self._falla:
            raise OSError("Communication link failure")
        conn = _ConexionMSSQL(dsn, self._respuestas)
        conn.autocommit = autocommit
        conn.timeout = timeout
        self.conexiones.append(conn)
        return conn


def _pyodbc_falso(respuestas=None, falla: bool = False):
    """Módulo pyodbc fake (con __spec__ para que find_spec lo acepte)."""
    return _ModPyodbc(respuestas, falla)


def _args(**kwargs) -> argparse.Namespace:
    base = dict(
        db_host=None, db_port=None, db_user=None, db_pass=None, db_name=None,
        api_port=None, api_host=None,
    )
    base.update(kwargs)
    return argparse.Namespace(**base)


def _leer_linea(texto: str, clave: str) -> str:
    for linea in texto.splitlines():
        if linea.startswith(f"{clave}="):
            return linea
    raise AssertionError(f"no se encontró {clave}= en:\n{texto}")


# ---------------------------------------------------------------------------
# _existe_esquema
# ---------------------------------------------------------------------------
def test_existe_esquema_postgres_consulta_pg_tables(monkeypatch):
    fake = _psycopg2_falso(resultados=[(True,)])
    monkeypatch.setitem(sys.modules, "psycopg2", fake)

    assert wserver._existe_esquema(URL_PG) is True

    assert len(fake.conexiones) == 1
    conn = fake.conexiones[0]
    assert conn.kwargs["dbname"] == "balansoft_ws_local"
    assert conn.kwargs["host"] == "servidorpg"
    assert conn.kwargs["port"] == 5432
    assert any("pg_tables" in sql and "public" in sql for sql in conn.sql)


def test_existe_esquema_postgres_falso_si_no_conecta(monkeypatch):
    fake = _psycopg2_falso(falla=True)
    monkeypatch.setitem(sys.modules, "psycopg2", fake)
    assert wserver._existe_esquema(URL_PG) is False
    assert fake.conexiones == []


def test_existe_esquema_sqlserver_consulta_sys_tables(monkeypatch):
    fake = _pyodbc_falso(respuestas=lambda sql: (7,) if "sys.tables" in sql else (None,))
    monkeypatch.setitem(sys.modules, "pyodbc", fake)

    assert wserver._existe_esquema(URL_MSSQL) is True

    assert len(fake.conexiones) == 1
    conn = fake.conexiones[0]
    assert "DATABASE=balansoft" in conn.dsn
    assert "SERVER=10.0.0.5,1433" in conn.dsn
    assert any(
        "sys.tables" in sql and "SCHEMA_NAME(schema_id)" in sql and "N'dbo'" in sql
        for sql in conn.sql
    )


def test_existe_esquema_sqlserver_sin_tablas_false(monkeypatch):
    fake = _pyodbc_falso()  # respuestas_vacias → 0 tablas
    monkeypatch.setitem(sys.modules, "pyodbc", fake)
    assert wserver._existe_esquema(URL_MSSQL) is False


# ---------------------------------------------------------------------------
# crear_bd_si_falta
# ---------------------------------------------------------------------------
def test_crear_bd_postgres_conecta_a_postgres_usa_pg_database(monkeypatch):
    # fetchone → None (la BD no existe) → debe crearla
    fake = _psycopg2_falso(resultados=[None])
    monkeypatch.setitem(sys.modules, "psycopg2", fake)

    wserver.crear_bd_si_falta(URL_PG)

    conn = fake.conexiones[0]
    assert conn.kwargs["dbname"] == "postgres", "PG debe conectar a la BD 'postgres'"
    assert conn.autocommit is True
    assert any("pg_database" in sql for sql in conn.sql)
    assert any('CREATE DATABASE "balansoft_ws_local"' in sql for sql in conn.sql)


def test_crear_bd_postgres_no_crea_si_ya_existe(monkeypatch):
    fake = _psycopg2_falso(resultados=[("balansoft_ws_local",)])
    monkeypatch.setitem(sys.modules, "psycopg2", fake)

    wserver.crear_bd_si_falta(URL_PG)

    assert not any("CREATE DATABASE" in sql for sql in fake.conexiones[0].sql)


def test_crear_bd_sqlserver_conecta_a_master_usa_db_id(monkeypatch):
    fake = _pyodbc_falso()
    monkeypatch.setitem(sys.modules, "pyodbc", fake)

    wserver.crear_bd_si_falta(URL_MSSQL)

    assert len(fake.conexiones) == 1
    conn = fake.conexiones[0]
    assert "DATABASE=master;" in conn.dsn, "SQL Server debe conectar a master"
    assert "SERVER=10.0.0.5,1433;" in conn.dsn
    assert conn.autocommit is True
    assert any("DB_ID(N'balansoft')" in sql for sql in conn.sql)
    assert any("CREATE DATABASE [balansoft]" in sql for sql in conn.sql)


def test_crear_bd_sqlserver_es_idempotente(monkeypatch):
    estado = {"creada": False}

    def respuestas(sql: str) -> tuple:
        if "DB_ID" in sql:
            return (None,) if not estado["creada"] else (7,)
        return (None,)

    fake = _pyodbc_falso(respuestas=respuestas)
    monkeypatch.setitem(sys.modules, "pyodbc", fake)

    wserver.crear_bd_si_falta(URL_MSSQL)
    assert any("CREATE DATABASE [balansoft]" in sql for sql in fake.conexiones[0].sql)
    estado["creada"] = True

    wserver.crear_bd_si_falta(URL_MSSQL)
    assert not any(
        "CREATE DATABASE" in sql for sql in fake.conexiones[1].sql
    ), "la segunda pasada no debe volver a crear la BD"


def test_crear_bd_sqlserver_escapa_comillas_y_corchetes(monkeypatch):
    url = "mssql+pyodbc://sa:p@h:1433/bd]con'comilla"
    fake = _pyodbc_falso()
    monkeypatch.setitem(sys.modules, "pyodbc", fake)

    wserver.crear_bd_si_falta(url)

    sqls = fake.conexiones[0].sql
    assert any("DB_ID(N'bd]con''comilla')" in sql for sql in sqls)
    assert any("CREATE DATABASE [bd]]con'comilla]" in sql for sql in sqls)


def test_crear_bd_sqlserver_sin_permisos_no_lanza(monkeypatch, capsys):
    def falla(*args, **kwargs):
        raise OSError("Cannot create database. User does not have permission.")

    mod = _pyodbc_falso()
    mod.connect = falla
    monkeypatch.setitem(sys.modules, "pyodbc", mod)

    wserver.crear_bd_si_falta(URL_MSSQL)  # no debe lanzar

    err = capsys.readouterr().err
    assert "CREATE DATABASE" in err  # pista sobre permisos


# ---------------------------------------------------------------------------
# asegurar_db en modo SQL Server
# ---------------------------------------------------------------------------
class _Mock:
    def __init__(self):
        self.llamadas = 0

    def __call__(self, *args, **kwargs):
        self.llamadas += 1
        return []


def test_asegurar_db_sqlserver_aplica_esquema_y_siembra_migraciones(
    monkeypatch, capsys, tmp_path
):
    # Fase 2: sobre una BD SQL Server recién creada (sin tablas), el WServer
    # aplica el T-SQL autocontenido y siembra schema_migrations con las
    # migraciones plegadas 001-021; el estado final queda "aplicado".
    estado = {"aplicado": False}

    def respuestas(sql: str) -> tuple:
        if "DB_ID" in sql:
            return (None,)  # la BD no existe → se crea
        if "sys.tables" in sql:
            return (7,) if estado["aplicado"] else (0,)
        if "schema_migrations" in sql:
            return (0,)  # tabla vacía → se siembra
        return (None,)

    fake = _pyodbc_falso(respuestas=respuestas)
    monkeypatch.setitem(sys.modules, "pyodbc", fake)
    aplicar_sql = _Mock()
    migraciones = _Mock()
    registrar = _Mock()
    monkeypatch.setattr(wserver, "_aplicar_sql", aplicar_sql)
    monkeypatch.setattr(wserver, "_migraciones_pendientes", migraciones)
    monkeypatch.setattr(wserver, "_registrar_migracion", registrar)

    _aplicar_tsql_original = wserver._aplicar_tsql_sqlserver

    def _aplicar_tsql_con_estado(conn, ruta_absoluta, etiqueta):
        _aplicar_tsql_original(conn, ruta_absoluta, etiqueta)
        estado["aplicado"] = True  # simula que el DDL creó las tablas

    monkeypatch.setattr(wserver, "_aplicar_tsql_sqlserver", _aplicar_tsql_con_estado)

    wserver.asegurar_db("mssql+pyodbc://sa:p@localhost:1433/bd_que_no_existe")

    # No toca la rama PostgreSQL (balansoft-ws-local.sql ni migrations/*.sql).
    assert aplicar_sql.llamadas == 0, "no se aplica balansoft-ws-local.sql (PG)"
    assert migraciones.llamadas == 0, "no se aplican migrations/*.sql (PG)"
    assert registrar.llamadas == 0
    # La conexión de bootstrap ejecutó el T-SQL del esquema embebido.
    conn_bootstrap = fake.conexiones[2]
    assert any(
        "balansoft-ws-local.sql" in sql for sql in conn_bootstrap.sql
    ) or any("CREATE TABLE" in sql for sql in conn_bootstrap.sql)
    assert db_engine.estado_esquema() == "aplicado"
    salida = capsys.readouterr().out
    assert "Esquema SQL Server aplicado" in salida
    assert "Migraciones plegadas registradas: 21" in salida


def test_asegurar_db_sqlserver_con_tablas_no_reaplica(monkeypatch, capsys):
    fake = _pyodbc_falso(respuestas=lambda sql: (3,) if "sys.tables" in sql else (None,))
    monkeypatch.setitem(sys.modules, "pyodbc", fake)
    monkeypatch.setattr(wserver, "_aplicar_sql", _Mock())
    monkeypatch.setattr(wserver, "_migraciones_pendientes", _Mock())

    wserver.asegurar_db(URL_MSSQL)

    # Tablas creadas manualmente → el bootstrap no re-aplica el T-SQL.
    assert db_engine.estado_esquema() == "aplicado"
    salida = capsys.readouterr().out
    assert "ya aplicado (no se re-aplica)" in salida


def test_asegurar_db_sqlserver_templa_fallo_de_conexion(monkeypatch, capsys):
    fake = _pyodbc_falso(falla=True)
    monkeypatch.setitem(sys.modules, "pyodbc", fake)

    wserver.asegurar_db(URL_MSSQL)  # no debe lanzar

    err = capsys.readouterr().err
    assert "No se pudo" in err
    assert db_engine.estado_esquema() == "pendiente"


def test_asegurar_db_sqlserver_sin_drivers_mensaje_claro(monkeypatch, capsys):
    fake = _pyodbc_falso()
    monkeypatch.setitem(sys.modules, "pyodbc", fake)
    monkeypatch.setattr("importlib.util.find_spec", lambda nombre: None)

    wserver.asegurar_db(URL_MSSQL)

    err = capsys.readouterr().err
    assert "uv sync --extra sqlserver" in err
    assert "aioodbc" in err and "pyodbc" in err
    assert fake.conexiones == [], "sin drivers no se intenta conectar"
    assert db_engine.estado_esquema() is None, "no se siembra estado sin drivers"


# ---------------------------------------------------------------------------
# _descomponer_url
# ---------------------------------------------------------------------------
def test_descomponer_url_sqlserver_puerto_default_1433_y_query():
    url = (
        "mssql+aioodbc://sa:P%40ss@servidor:1433/bd?"
        "driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes"
    )
    c = wserver._descomponer_url(url)
    assert c["motor"] == "sqlserver"
    assert c["prefijo"] == "mssql+aioodbc://"
    assert c["host"] == "servidor"
    assert c["port"] == 1433
    assert c["user"] == "sa"
    assert c["password"] == "P@ss"
    assert c["db"] == "bd"
    assert c["query"] == "driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes"
    assert c["params"]["TrustServerCertificate"] == "yes"


def test_descomponer_url_sqlserver_sin_puerto_default_1433():
    c = wserver._descomponer_url("mssql://sa:p@mihost/bd")
    assert c["motor"] == "sqlserver"
    assert c["port"] == 1433  # puerto default del motor
    assert c["host"] == "mihost"
    assert c["db"] == "bd"
    assert c["query"] == ""


def test_descomponer_url_postgres_default_5432():
    """Regresión: el parseo PG conserva credenciales y usa 5432."""
    c = wserver._descomponer_url("postgresql+asyncpg://miusuario:mipass@servidorpg/bd")
    assert c["motor"] == "postgresql"
    assert c["prefijo"] == "postgresql+asyncpg://"
    assert c["port"] == 5432
    assert c["user"] == "miusuario"
    assert c["password"] == "mipass"
    assert c["db"] == "bd"


def test_descomponer_url_lanza_value_error_si_motor_no_soportado():
    with pytest.raises(ValueError):
        wserver._descomponer_url("oracle://u:p@h:1521/bd")


# ---------------------------------------------------------------------------
# _actualizar_env_si_aplica
# ---------------------------------------------------------------------------
def _env_mssql(path):
    path.write_text(
        "# comentario previo\n"
        "DATABASE_URL=mssql+aioodbc://sa:P%40ss@10.0.0.5:1433/balansoft"
        "?driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes\n"
        "DATABASE_URL_SYNC=mssql+pyodbc://sa:P%40ss@10.0.0.5:1433/balansoft"
        "?driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes\n"
        "API_PORT=8000\n",
        encoding="utf-8",
    )


def test_actualizar_env_preserva_prefijo_mssql_y_query(tmp_path):
    _env_mssql(tmp_path / ".env")

    wserver._actualizar_env_si_aplica(tmp_path, _args(db_host="192.168.1.50"))

    texto = (tmp_path / ".env").read_text(encoding="utf-8")
    url_async = _leer_linea(texto, "DATABASE_URL")
    url_sync = _leer_linea(texto, "DATABASE_URL_SYNC")

    assert url_async.startswith("DATABASE_URL=mssql+aioodbc://")
    assert url_sync.startswith("DATABASE_URL_SYNC=mssql+pyodbc://")
    assert "192.168.1.50:1433/balansoft" in url_async
    # Query original intacta byte a byte y credenciales recodificadas.
    assert (
        "?driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes" in url_async
    )
    assert (
        "?driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes" in url_sync
    )
    assert "P%40ss@" in url_async and "P%40ss@" in url_sync
    # El resto del .env no se toca.
    assert _leer_linea(texto, "API_PORT") == "API_PORT=8000"
    assert texto.startswith("# comentario previo\n")


def test_actualizar_env_postgres_comportamiento_regresion(tmp_path):
    (tmp_path / ".env").write_text(
        "DATABASE_URL=postgresql+asyncpg://balansoft:CHANGE_ME@localhost:5432/balansoft_ws_local\n"
        "DATABASE_URL_SYNC=postgresql+psycopg2://balansoft:CHANGE_ME@localhost:5432/balansoft_ws_local\n"
        "API_PORT=8000\n",
        encoding="utf-8",
    )

    wserver._actualizar_env_si_aplica(
        tmp_path,
        _args(
            db_host="10.1.1.9",
            db_port="5544",
            db_user="operador",
            db_pass="clave",
            db_name="otra_bd",
            api_port="8010",
        ),
    )

    texto = (tmp_path / ".env").read_text(encoding="utf-8")
    assert _leer_linea(texto, "DATABASE_URL") == (
        "DATABASE_URL=postgresql+asyncpg://operador:clave@10.1.1.9:5544/otra_bd"
    )
    assert _leer_linea(texto, "DATABASE_URL_SYNC") == (
        "DATABASE_URL_SYNC=postgresql+psycopg2://operador:clave@10.1.1.9:5544/otra_bd"
    )
    assert _leer_linea(texto, "API_PORT") == "API_PORT=8010"


def test_actualizar_env_url_sin_puerto_no_destruye_credenciales(tmp_path):
    (tmp_path / ".env").write_text(
        "DATABASE_URL=postgresql+asyncpg://miusuario:mipass@servidor/balansoft_ws_local\n"
        "DATABASE_URL_SYNC=postgresql+psycopg2://miusuario:mipass@servidor/balansoft_ws_local\n",
        encoding="utf-8",
    )

    wserver._actualizar_env_si_aplica(tmp_path, _args(db_name="nueva_bd"))

    texto = (tmp_path / ".env").read_text(encoding="utf-8")
    # Antes de Fase 1 un URL sin puerto no casaba con el regex y se perdían
    # credenciales reales por los defaults.
    assert _leer_linea(texto, "DATABASE_URL") == (
        "DATABASE_URL=postgresql+asyncpg://miusuario:mipass@servidor:5432/nueva_bd"
    )
    assert _leer_linea(texto, "DATABASE_URL_SYNC") == (
        "DATABASE_URL_SYNC=postgresql+psycopg2://miusuario:mipass@servidor:5432/nueva_bd"
    )


def test_actualizar_env_sin_argumentos_no_toca_el_env(tmp_path):
    env = tmp_path / ".env"
    env.write_text("DATABASE_URL=postgresql+asyncpg://u:p@h/bd\n", encoding="utf-8")
    wserver._actualizar_env_si_aplica(env.parent, _args())
    assert env.read_text(encoding="utf-8") == "DATABASE_URL=postgresql+asyncpg://u:p@h/bd\n"


def test_actualizar_env_url_ilegible_usa_defaults_pg(tmp_path):
    (tmp_path / ".env").write_text(
        "DATABASE_URL=esto no es una url\n",
        encoding="utf-8",
    )
    wserver._actualizar_env_si_aplica(tmp_path, _args(db_host="1.2.3.4"))
    texto = (tmp_path / ".env").read_text(encoding="utf-8")
    assert "DATABASE_URL=postgresql+asyncpg://balansoft:CHANGE_ME@1.2.3.4:5432/" in texto


# asegurar_estructura: BACKUP_DIR absoluto del runtime
def test_asegurar_estructura_genera_env_con_backup_dir_absoluto(tmp_path, monkeypatch):
    """La plantilla trae ``BACKUP_DIR=backups`` (relativo al CWD) y puede
    quedar ilegible en instalaciones (p. ej. Program Files); al generar el
    ``.env`` el WServer lo reemplaza por el directorio de respaldos del
    runtime, que ya fue creado por asegurar_estructura()."""
    raiz = tmp_path / "raiz"
    raiz.mkdir()
    (raiz / ".env.plantilla").write_text(
        "SECRET_KEY=__SECRET_KEY__\nBACKUP_DIR=backups\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(wserver, "ROOT", raiz)

    home = tmp_path / "runtime"
    wserver.asegurar_estructura(home)

    assert (home / "backups").is_dir()
    lineas = (home / ".env").read_text(encoding="utf-8").splitlines()
    assert f"BACKUP_DIR={home / 'backups'}" in lineas
    assert "BACKUP_DIR=backups" not in lineas
    assert not any("__SECRET_KEY__" in linea for linea in lineas)
