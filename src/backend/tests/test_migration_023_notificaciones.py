"""Migración 023 (notificaciones y recordatorios): validación e idempotencia.

Comprueba que la migración y los **tres** esquemas canónicos declaran las mismas
tablas, y que la parte de SQL Server conserva los *guards* idempotentes y el
índice único filtrado que la BD local necesita (SQL Server no admite varios
NULL en un UNIQUE normal, así que la unicidad de ``dedup_key`` es filtrada).

No toca la BD: el esquema de los tests lo crea SQLAlchemy desde los modelos, y
mutar tablas aquí rompería a los demás tests de la sesión.
"""

from __future__ import annotations

import re
from pathlib import Path

from app.models import Notificacion, Recordatorio

BACKEND = Path(__file__).resolve().parents[1]
MIGRACION = BACKEND / "migrations" / "023_notificaciones_recordatorios.sql"
ESQUEMA_PG = BACKEND / "balansoft-ws-local.sql"
ESQUEMA_MSSQL = BACKEND / "sqlserver" / "balansoft-ws-local.sql"

TABLAS = ("recordatorios", "notificaciones")


def _leer(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_migracion_declara_las_dos_tablas():
    texto = _leer(MIGRACION)
    for tabla in TABLAS:
        assert f"CREATE TABLE IF NOT EXISTS {tabla}" in texto, f"falta {tabla}"


def test_migracion_es_idempotente():
    texto = _leer(MIGRACION)
    assert texto.count("CREATE TABLE IF NOT EXISTS") == len(TABLAS)
    # Los índices también se crean con IF NOT EXISTS.
    assert "CREATE INDEX IF NOT EXISTS" in texto
    assert "DROP " not in texto.upper()


def test_columnas_del_modelo_estan_en_la_migracion():
    """El mapeo ORM y el DDL no deben divergir (columnas faltantes => 500)."""
    migracion = _leer(MIGRACION)
    for modelo in (Recordatorio, Notificacion):
        por_tabla = migracion.split(f"CREATE TABLE IF NOT EXISTS {modelo.__tablename__}")[1]
        bloque = por_tabla.split(");")[0]
        declaradas = set(re.findall(r"^\s{4}(\w+)\s", bloque, re.M))
        faltan = {c.name for c in modelo.__table__.columns} - declaradas
        assert not faltan, f"{modelo.__tablename__}: faltan columnas {sorted(faltan)}"


def test_esquema_pg_canonico_refleja_la_migracion():
    texto = _leer(ESQUEMA_PG)
    for tabla in TABLAS:
        assert f"CREATE TABLE IF NOT EXISTS {tabla}" in texto


def test_esquema_mssql_refleja_la_migracion():
    texto = _leer(ESQUEMA_MSSQL)
    for tabla in TABLAS:
        assert f"IF OBJECT_ID(N'dbo.{tabla}', N'U') IS NULL BEGIN" in texto
    # Unicidad filtrada de dedup_key (SQL Server no admite varios NULL en UNIQUE).
    assert (
        "CREATE UNIQUE INDEX [uq_notificaciones_empresa_dedup] "
        "ON [dbo].[notificaciones] (id_empresa, dedup_key) "
        "WHERE (dedup_key IS NOT NULL)" in texto
    )
    for fk in (
        "notificaciones_id_empresa_fkey",
        "notificaciones_id_recordatorio_fkey",
        "recordatorios_id_empresa_fkey",
        "recordatorios_id_usuario_fkey",
    ):
        assert f"ADD CONSTRAINT [{fk}] FOREIGN KEY" in texto, f"falta la FK {fk}"
