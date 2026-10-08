"""Nivel 0 de la suite SQL Server (T8): validación estática del T-SQL.

No requiere SQL Server real: verifica la integridad del esquema canónico
``backend/sqlserver/balansoft-ws-local.sql`` (anti-GO, conteos de tablas/PK/FK,
guards idempotentes, límite NVARCHAR(255) en columnas indexadas y paridad con
el esquema PostgreSQL ``balansoft-ws-local.sql``).

La paridad esperada es 27 tablas = 24 canónicas SQLite/PG + 3 auxiliares que
solo existen en SQL Server: ``password_reset_tokens``, ``series_numeracion``
y ``schema_migrations``.
"""

from __future__ import annotations

import re
from pathlib import Path

ESQUEMA_PG = Path(__file__).resolve().parents[1] / "balansoft-ws-local.sql"
ESQUEMA_MSSQL = Path(__file__).resolve().parents[1] / "sqlserver" / "balansoft-ws-local.sql"
MIGRACIONES_DIR = Path(__file__).resolve().parents[1] / "migrations"

TABLAS_PG_Y_MSSQL = {
    "almacenes", "auditoria", "balanzas", "boletos_pesaje", "camiones",
    "categorias", "conductores", "configuraciones", "empresas",
    "identidad_local", "imagenes_pesaje", "kardex", "logs_sistema", "marcas",
    "modelos_camion", "parametros_sistema", "permisos_acceso", "productos",
    "remolques", "sync_logs", "sync_queue", "terceros", "transportes",
    "usuarios",
}
TABLAS_SOLO_MSSQL = {"password_reset_tokens", "series_numeracion", "schema_migrations"}
TABLAS_ESPERADAS_MSSQL = TABLAS_PG_Y_MSSQL | TABLAS_SOLO_MSSQL

ESPERADAS_PK = 27
ESPERADAS_FK = 37
ESPERADAS_MIGRACIONES_PLEGADAS = 21
MAX_NVARCHAR_INDEXADA = 255


def _leer_mssql() -> str:
    return ESQUEMA_MSSQL.read_text(encoding="utf-8")


def _leer_pg() -> str:
    return ESQUEMA_PG.read_text(encoding="utf-8")


def _tablas_mssql(texto: str) -> set[str]:
    return {
        m[1]
        for m in re.findall(r"CREATE TABLE\s+\[?(\w+)\]?\.\[?(\w+)\]?", texto, re.I)
    }


def _tablas_pg(texto: str) -> set[str]:
    return set(re.findall(r"CREATE TABLE IF NOT EXISTS (?:public\.)?(\w+)", texto, re.I))


# ---------------------------------------------------------------------------
# anti-GO y estructura de lote
# ---------------------------------------------------------------------------
def test_no_contiene_go():
    """El T-SQL no usa separadores GO (pyodbc ejecuta un solo lote)."""
    texto = _leer_mssql()
    assert not [linea for linea in texto.splitlines() if linea.strip().upper() == "GO"]


def test_cabecera_transaccional():
    """El esquema lleva SET QUOTED_IDENTIFIER/ANSI_NULLS e inicia transacción.

    MS SQL Server exige QUOTED_IDENTIFIER ON incluso para INSERT/UPDATE sobre
    tablas con índices filtrados; el archivo lo fija al principio del lote.
    """
    texto = _leer_mssql()
    assert "SET QUOTED_IDENTIFIER ON" in texto
    assert "SET ANSI_NULLS ON" in texto
    assert "BEGIN TRANSACTION" in texto
    assert "COMMIT" in texto


# ---------------------------------------------------------------------------
# conteos
# ---------------------------------------------------------------------------
def test_conteo_tablas_27():
    assert _tablas_mssql(_leer_mssql()) == TABLAS_ESPERADAS_MSSQL
    assert len(_tablas_mssql(_leer_mssql())) == 27


def test_conteo_pk_27():
    texto = _leer_mssql()
    assert len(re.findall(r"PRIMARY KEY", texto, re.I)) == ESPERADAS_PK


def test_conteo_fk_37():
    texto = _leer_mssql()
    assert len(re.findall(r"FOREIGN KEY", texto, re.I)) == ESPERADAS_FK


def test_tablas_solo_mssql_presentes():
    texto = _leer_mssql()
    for tabla in TABLAS_SOLO_MSSQL:
        assert f"{tabla}]" in texto, f"falta la tabla auxiliar {tabla}"


# ---------------------------------------------------------------------------
# guards idempotentes
# ---------------------------------------------------------------------------
def test_guards_idempotentes_tablas():
    """Cada CREATE TABLE está protegido por IF OBJECT_ID (no usa DROP)."""
    texto = _leer_mssql()
    crea = len(re.findall(r"CREATE TABLE", texto, re.I))
    guards = len(re.findall(r"IF OBJECT_ID", texto, re.I))
    assert crea == guards == 27, f"CREATE TABLE={crea} guards={guards}"


def test_guards_idempotentes_indices_y_fk():
    """Índices y FKs se crean con IF NOT EXISTS sobre sys.indexes/foreign_keys."""
    texto = _leer_mssql()
    assert texto.count("IF NOT EXISTS (SELECT 1 FROM sys.indexes") >= 30
    assert texto.count("IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys") == ESPERADAS_FK


# ---------------------------------------------------------------------------
# NVARCHAR(255) en columnas indexadas (regla de 900 bytes)
# ---------------------------------------------------------------------------
def test_columnas_indexadas_no_exceden_nvarchar_255():
    """Ninguna columna citada en un índice usa NVARCHAR/VARCHAR(> 255).

    El índice clustered de una PK con NVARCHAR(500)+2 bytes excedería los 900
    bytes máximos de una clave de índice en SQL Server (6120); por eso todo
    texto indexado es <= 255 caracteres.
    """
    texto = _leer_mssql()
    # Columnas citadas dentro de CREATE INDEX (...)
    columnas_indexadas: set[str] = set()
    for m in re.finditer(r"CREATE (?:UNIQUE )?INDEX\s+\S+\s+ON\s+\S+\s*\(([^)]+)\)", texto, re.I):
        for col in re.findall(r"\[(\w+)\]", m.group(1)):
            columnas_indexadas.add(col)
    # También las columnas de la PK compuesta (ej. sync_queue)
    for m in re.finditer(r"PRIMARY KEY\s*\(([^)]+)\)", texto, re.I):
        for col in re.findall(r"\[(\w+)\]", m.group(1)):
            columnas_indexadas.add(col)

    problema: list[str] = []
    for m in re.finditer(r"\[(\w+)\]\s+(?:NVARCHAR|VARCHAR)\((\d+)\)", texto, re.I):
        col, ancho = m.group(1), int(m.group(2))
        if col in columnas_indexadas and ancho > MAX_NVARCHAR_INDEXADA:
            problema.append(f"{col} {ancho}")
    assert not problema, f"columnas indexadas demasiado anchas: {problema}"


# ---------------------------------------------------------------------------
# paridad con PostgreSQL
# ---------------------------------------------------------------------------
def test_paridad_tablas_pg_vs_mssql():
    """Todas las tablas del esquema PG están en el T-SQL y viceversa."""
    pg = _tablas_pg(_leer_pg())
    mssql = _tablas_mssql(_leer_mssql())
    assert pg == TABLAS_PG_Y_MSSQL
    assert mssql == TABLAS_ESPERADAS_MSSQL
    assert pg <= mssql, f"faltan en mssql: {pg - mssql}"
    assert mssql - pg == TABLAS_SOLO_MSSQL


def test_migraciones_plegadas_documentadas():
    """Las 21 migraciones 001-021 existen como archivo (las pliega el WServer).

    ``wserver._sembrar_migraciones_sqlserver`` itera ``migrations/*.sql`` del
    disco; si el directorio real no tuviera esos 21 archivos, la siembra en
    SQL Server (N1) registraría menos versiones y el esquema quedaría
    desincronizado respecto a PostgreSQL. Verificar contra el directorio real
    (no contra una constante) evita un test tautológico.
    """
    archivos = sorted(p.name for p in MIGRACIONES_DIR.glob("*.sql")) if MIGRACIONES_DIR.exists() else []
    assert len(archivos) == ESPERADAS_MIGRACIONES_PLEGADAS, (
        f"se esperaban {ESPERADAS_MIGRACIONES_PLEGADAS} migraciones plegadas, "
        f"hay {len(archivos)} en {MIGRACIONES_DIR}"
    )
    # Numeración contigua 001..021 (sin huecos) para que la siembra sea determinista.
    for i in range(1, ESPERADAS_MIGRACIONES_PLEGADAS + 1):
        assert any(p.startswith(f"{i:03d}_") for p in archivos), f"falta la migración {i:03d}_*.sql"