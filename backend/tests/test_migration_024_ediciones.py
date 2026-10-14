"""Migración 024: ediciones de boletos con justificación, tope e impresión.

Comprueba que la migración y los esquemas canónicos (PG y SQL Server) declaran
las mismas columnas/tablas que el mapeo ORM, y que la migración es idempotente.

No toca la BD: el esquema de los tests lo crea SQLAlchemy desde los modelos.
"""

from __future__ import annotations

import re
from pathlib import Path

from app.models import BoletoEdicion, BoletoPesaje, Empresa

BACKEND = Path(__file__).resolve().parents[1]
MIGRACION = BACKEND / "migrations" / "024_ediciones_justificacion_tope_impresion.sql"
ESQUEMA_PG = BACKEND / "balansoft-ws-local.sql"
ESQUEMA_MSSQL = BACKEND / "sqlserver" / "balansoft-ws-local.sql"

COLUMNAS_BOLETO = (
    "ediciones_count",
    "motivo_modificacion_ultima",
    "ultimo_editor_nombre",
)
COLUMNAS_EMPRESA = (
    "max_ediciones_boleto",
    "impresion_automatica",
    "protocolo_impresion",
    "impresora_nombre",
    "impresora_host",
    "impresora_puerto",
)


def _leer(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_migracion_declara_el_historial():
    texto = _leer(MIGRACION)
    assert "CREATE TABLE IF NOT EXISTS boletos_ediciones" in texto


def test_migracion_es_idempotente():
    texto = _leer(MIGRACION)
    assert texto.count("CREATE TABLE IF NOT EXISTS boletos_ediciones") == 1
    assert "ADD COLUMN IF NOT EXISTS" in texto
    assert "CREATE INDEX IF NOT EXISTS" in texto
    assert "CREATE UNIQUE INDEX IF NOT EXISTS" in texto
    # Nada destructivo: la migración solo añade.
    assert "DROP TABLE" not in texto.upper()
    assert "DROP COLUMN" not in texto.upper()
    # La justificación es obligatoria también en la BD.
    assert "char_length(trim(justificacion)) >= 10" in texto


def test_columnas_del_modelo_historial_estan_en_la_migracion():
    """El mapeo ORM y el DDL no deben divergir (columna faltante => 500)."""
    texto = _leer(MIGRACION)
    bloque = texto.split("CREATE TABLE IF NOT EXISTS boletos_ediciones")[1].split(");")[0]
    declaradas = set(re.findall(r"^\s{4}(\w+)\s", bloque, re.M))
    faltan = {c.name for c in BoletoEdicion.__table__.columns} - declaradas
    assert not faltan, f"boletos_ediciones: faltan columnas {sorted(faltan)}"


def test_columnas_nuevas_de_boletos_pesaje_en_pg():
    texto = _leer(ESQUEMA_PG)
    for col in COLUMNAS_BOLETO:
        assert col in texto, f"falta {col} en el esquema PG"


def test_columnas_nuevas_de_empresas_en_pg():
    texto = _leer(ESQUEMA_PG)
    for col in COLUMNAS_EMPRESA:
        assert col in texto, f"falta {col} en el esquema PG"


def test_esquema_pg_canonico_refleja_la_tabla():
    texto = _leer(ESQUEMA_PG)
    assert "CREATE TABLE IF NOT EXISTS boletos_ediciones" in texto


def test_esquema_mssql_refleja_la_migracion():
    texto = _leer(ESQUEMA_MSSQL)
    assert "IF OBJECT_ID(N'dbo.boletos_ediciones', N'U') IS NULL BEGIN" in texto
    for col in COLUMNAS_BOLETO + COLUMNAS_EMPRESA:
        assert f"[{col}]" in texto, f"falta {col} en el esquema SQL Server"
    # Unicidad filtrada de sync_operation_id (varios NULL permitidos).
    assert "WHERE [sync_operation_id] IS NOT NULL" in texto


def test_modelos_exponen_los_campos_nuevos():
    assert "ediciones_count" in {c.name for c in BoletoPesaje.__table__.columns}
    assert "max_ediciones_boleto" in {c.name for c in Empresa.__table__.columns}
