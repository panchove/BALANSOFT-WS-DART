"""Nivel 1 de la suite SQL Server (T8): esquema real, idempotencia y paridad.

Requiere un SQL Server real accesible vía ``MSSQL_TEST_URL_SYNC`` (URL
síncrona ``mssql+pyodbc://...``). Sin la variable (o sin conexión) los tests
se saltan; nunca fallan en CI que no tiene SQL Server.

Cubre:
- ``wserver.crear_bd_si_falta`` + ``_asegurar_db_sqlserver`` (Fase 2):
  aplica el T-SQL, siembra ``schema_migrations`` (21).
- Idempotencia: una segunda pasada no vuelve a aplicar nada ni revienta.
- Paridad: 27 tablas / 27 PK / 37 FK contra el T-SQL canónico (N0).
"""

from __future__ import annotations

import os
import uuid
from pathlib import Path

import pytest

import wserver
from app.core import db_engine
from app.core.db_engine import desactivar_pooling_pyodbc, dsn_pyodbc

desactivar_pooling_pyodbc()  # pyodbc 5: pooling interno → HY000 con lotes DDL
pytestmark = pytest.mark.mssql

ESQUEMA_MSSQL = Path(__file__).resolve().parents[1] / "sqlserver" / "balansoft-ws-local.sql"
BD_TEST = "balansoft_ws_mssql_test"


def _url_sync_test() -> str:
    """URL sync de test desde env; si no está, el módulo se salta."""
    url = os.environ.get("MSSQL_TEST_URL_SYNC")
    if not url:
        pytest.skip("MSSQL_TEST_URL_SYNC no definida (SQL Server de prueba requerido)")
    return url


def _url_bd(url_sync: str, bd: str) -> str:
    """Reescribe la BD de la URL SIN enmascarar el password."""
    from sqlalchemy.engine import make_url

    return make_url(url_sync).set(database=bd).render_as_string(hide_password=False)


def _conexion_sqlserver(url_sync: str, bd: str):
    """Conexión pyodbc directa a una BD concreta (autocommit activo)."""
    import pyodbc

    c = wserver._descomponer_url(url_sync)
    conn = pyodbc.connect(dsn_pyodbc({**c, "db": bd}), autocommit=True, timeout=10)
    return conn


def _drop_bd(url_sync: str, bd: str) -> None:
    """Borra una BD de test dedicada desde master (nunca en producción)."""
    import pyodbc

    c = wserver._descomponer_url(url_sync)
    conn = pyodbc.connect(dsn_pyodbc({**c, "db": "master"}), autocommit=True, timeout=10)
    try:
        cur = conn.cursor()
        cur.execute(
            f"IF DB_ID(N'{bd}') IS NOT NULL BEGIN "
            f"ALTER DATABASE [{bd}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; "
            f"DROP DATABASE [{bd}]; END"
        )
    finally:
        conn.close()


@pytest.fixture(scope="module")
def disponibilidad():
    """Conecta a master; sin SQL Server el módulo se salta entero."""
    url_sync = _url_sync_test()
    try:
        import pyodbc  # noqa: F401

        c = wserver._descomponer_url(url_sync)
        conn = pyodbc.connect(dsn_pyodbc({**c, "db": "master"}), autocommit=True, timeout=5)
        conn.close()
    except Exception as exc:  # noqa: BLE001 (sin SQL Server → skip, no fail)
        pytest.skip(f"SQL Server no disponible: {exc}")
    return url_sync


def test_esquema_aplicado_idempotente_y_siembra(disponibilidad):
    """Aplicar T-SQL manual, contar paridad, re-aplicar y sembrar migraciones."""
    url_sync = disponibilidad
    import pyodbc

    bd = f"{BD_TEST}_n1a_{uuid.uuid4().hex[:8]}"
    url_test = _url_bd(url_sync, bd)
    try:
        wserver.crear_bd_si_falta(url_test)
    except Exception as exc:  # noqa: BLE001
        pytest.skip(f"no se pudo crear BD de test: {exc}")

# La BD ya existe: cualquier fallo posterior debe dropearla (LOW-02:
    # huérfanas balansoft_ws_mssql_test* acumuladas en el contenedor).
    conn = None
    try:
        c = wserver._descomponer_url(url_sync)
        conn = pyodbc.connect(dsn_pyodbc({**c, "db": bd}), autocommit=False, timeout=10)
        cur = conn.cursor()
        sql_texto = ESQUEMA_MSSQL.read_text(encoding="utf-8")
        # 1ª aplicación: el T-SQL es idempotente pero la BD debe partir vacía.
        cur.execute("SELECT COUNT(*) FROM sys.tables WHERE SCHEMA_NAME(schema_id) = N'dbo'")
        ya_aplicado = cur.fetchone()[0] > 0
        cur.execute(sql_texto)
        conn.commit()

        _verificar_paridad(cur)
        assert not ya_aplicado, "la BD de test debería haber partido vacía"

        # 2ª aplicación: guards IF OBJECT_ID / IF NOT EXISTS → no falla ni duplica.
        cur.execute(sql_texto)
        conn.commit()
        _verificar_paridad(cur)

        # schema_migrations vacía → siembra las 001-021 reales, sin duplicar al repetir.
        cur.execute("SELECT COUNT(*) FROM dbo.schema_migrations")
        assert cur.fetchone()[0] == 0, "schema_migrations debe partir vacía"
        mig_dir = Path(__file__).resolve().parents[1] / "migrations"
        versiones = sorted(p.name for p in mig_dir.glob("*.sql")) if mig_dir.exists() else []
        assert len(versiones) == 21, f"se esperaban 21 migraciones plegadas, hay {len(versiones)}"
        wserver._sembrar_migraciones_sqlserver(conn, versiones)
        cur.execute("SELECT COUNT(*) FROM dbo.schema_migrations")
        assert cur.fetchone()[0] == 21
        wserver._sembrar_migraciones_sqlserver(conn, versiones)
        cur.execute("SELECT COUNT(*) FROM dbo.schema_migrations")
        assert cur.fetchone()[0] == 21
    finally:
        if conn is not None:
            conn.close()
        try:
            _drop_bd(url_sync, bd)
        except Exception:  # noqa: BLE001 — la limpieza no debe enmascarar un assert
            pass


def test_asegurar_db_fase2(disponibilidad):
    """El orquestador ``asegurar_db`` aplica el esquema en una BD nueva."""
    url_sync = disponibilidad
    bd_tmp = f"{BD_TEST}_n1b_{uuid.uuid4().hex[:8]}"
    url_tmp = _url_bd(url_sync, bd_tmp)

    # ``asegurar_db`` crea la BD: si falla (o el assert posterior), igual se
    # dropea (LOW-02: huérfanas balansoft_ws_mssql_test* en el contenedor).
    conn = None
    try:
        db_engine.marcar_estado_esquema(None)  # reset caché para forzar la consulta
        wserver.asegurar_db(url_tmp)
        assert db_engine.estado_esquema() == "aplicado"

        conn = _conexion_sqlserver(url_sync, bd_tmp)
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM sys.tables WHERE SCHEMA_NAME(schema_id) = N'dbo'")
        assert cur.fetchone()[0] == 27
        cur.execute("SELECT COUNT(*) FROM dbo.schema_migrations")
        assert cur.fetchone()[0] == 21
    finally:
        if conn is not None:
            conn.close()
        try:
            _drop_bd(url_sync, bd_tmp)
        except Exception:  # noqa: BLE001 — la limpieza no debe enmascarar un assert
            pass


def _verificar_paridad(cur) -> None:
    """Paridad canónica del esquema: 27 tablas / 27 PK / 37 FK."""
    cur.execute("SELECT COUNT(*) FROM sys.tables WHERE SCHEMA_NAME(schema_id) = N'dbo'")
    assert cur.fetchone()[0] == 27, "se esperaban 27 tablas"
    cur.execute(
        "SELECT COUNT(*) FROM sys.key_constraints "
        "WHERE type = 'PK' AND SCHEMA_NAME(schema_id) = N'dbo'"
    )
    assert cur.fetchone()[0] == 27, "se esperaban 27 PK"
    cur.execute(
        "SELECT COUNT(*) FROM sys.foreign_keys "
        "WHERE SCHEMA_NAME(schema_id) = N'dbo'"
    )
    assert cur.fetchone()[0] == 37, "se esperaban 37 FK"