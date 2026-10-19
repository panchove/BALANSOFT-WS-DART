"""Paridad entre el esquema canónico del SERVIDOR y los modelos SQLAlchemy.

Motivación (incidente 2026-10-14): la BD desplegada del central respondía
``500 asyncpg.exceptions.UndefinedColumnError: column dispositivos.estado does
not exist`` porque el esquema **desplegado** era anterior a RB-12, mientras el
modelo ``app/models_server.py`` ya esperaba ``estado``/``rol_sesion``. El
canónico ``balansoft-ws-server.sql`` sí las tenía, pero ``instalar`` usa
``CREATE TABLE IF NOT EXISTS`` y nunca re-aplica sobre una BD existente.

Estos tests (puros, sin BD) fijan dos garantías:

1. El canónico ``balansoft-ws-server.sql`` y ``ServerBase.metadata`` declaran
   exactamente las mismas tablas y columnas (evita que el modelo se adelante al
   SQL, que es la causa raíz del incidente).
2. El canónico incluye los bloques ``DO $$`` idempotentes que **sanan** una BD
   desplegada con deriva (re-aplicarlo añade las columnas que falten).
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from app.models_server import ServerBase

SQL_PATH = Path(__file__).resolve().parent.parent / "balansoft-ws-server.sql"


def _sql() -> str:
    return SQL_PATH.read_text(encoding="utf-8")


_INICIO_CONSTRAINT = ("CONSTRAINT", "PRIMARY KEY", "UNIQUE", "FOREIGN KEY", "CHECK")


def _columnas_de_cuerpo(cuerpo: str) -> list[str]:
    """Nombres de columna de un CREATE TABLE, ignorando las constraint.

    Las constraint multilínea (``CHECK ( ... )``) se saltan siguiendo la
    profundidad de paréntesis: sin esto, una línea de continuación como
    ``rol_sesion IS NULL OR ...`` se confundiría con una columna y enmascararía
    una columna realmente ausente (falso positivo verificado por mutación).
    """
    columnas: list[str] = []
    profundidad = 0
    for linea in cuerpo.splitlines():
        texto = linea.strip()
        if not texto or texto.startswith("--"):
            continue
        if profundidad == 0:
            if not texto.upper().startswith(_INICIO_CONSTRAINT):
                token = texto.split()[0].strip(",").strip()
                if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", token):
                    columnas.append(token)
        profundidad += texto.count("(") - texto.count(")")
    return columnas


def _tablas_sql(texto: str) -> dict[str, list[str]]:
    """Extrae {tabla: [columnas]} de los CREATE TABLE del canónico."""
    tablas: dict[str, list[str]] = {}
    patron = re.compile(
        r"CREATE TABLE IF NOT EXISTS\s+(\w+)\s*\((.*?)\n\);", re.S
    )
    for m in patron.finditer(texto):
        tablas[m.group(1)] = _columnas_de_cuerpo(m.group(2))
    return tablas


def _tablas_modelo() -> dict[str, list[str]]:
    return {
        t.name: [c.name for c in t.columns]
        for t in ServerBase.metadata.tables.values()
    }


def test_todas_las_tablas_del_modelo_estan_en_el_sql() -> None:
    sql = _tablas_sql(_sql())
    faltantes = sorted(set(_tablas_modelo()) - set(sql))
    assert not faltantes, (
        f"El canónico balansoft-ws-server.sql no define: {faltantes}"
    )


def test_el_sql_no_declara_tablas_huerfanas() -> None:
    modelo = set(_tablas_modelo())
    huerfanas = sorted(set(_tablas_sql(_sql())) - modelo)
    assert not huerfanas, (
        f"balansoft-ws-server.sql declara tablas sin modelo: {huerfanas}"
    )


@pytest.mark.parametrize("tabla", sorted(_tablas_modelo()))
def test_columnas_del_modelo_existen_en_el_sql(tabla: str) -> None:
    """Si el modelo añade una columna, el canónico DEBE declararla.

    Este es el test que habría detenido el incidente de ``dispositivos.estado``.
    """
    sql = _tablas_sql(_sql())[tabla]
    faltan = sorted(set(_tablas_modelo()[tabla]) - set(sql))
    assert not faltan, (
        f"columnas del modelo ausentes en el SQL de '{tabla}': {faltan}"
    )


@pytest.mark.parametrize("tabla", sorted(_tablas_modelo()))
def test_el_sql_no_tiene_columnas_de_mas(tabla: str) -> None:
    extra = sorted(set(_tablas_sql(_sql())[tabla]) - set(_tablas_modelo()[tabla]))
    assert not extra, (
        f"columnas del SQL ausentes en el modelo de '{tabla}': {extra}"
    )


def test_dispositivos_declara_estado_y_rol_sesion_rb12() -> None:
    columnas = _tablas_sql(_sql())["dispositivos"]
    assert "estado" in columnas
    assert "rol_sesion" in columnas
    texto = _sql()
    assert "chk_dispositivos_estado" in texto
    assert "chk_dispositivos_rol_sesion" in texto


def test_el_canonico_sana_una_bd_con_deriva() -> None:
    """El canónico debe poder re-aplicarse sobre una BD antigua sin romper.

    Exige los ALTER idempotentes para las columnas que causaron el incidente.
    """
    texto = _sql()
    assert re.search(
        r"ALTER TABLE dispositivos ADD COLUMN estado\b", texto
    ), "falta el ALTER idempotente de dispositivos.estado"
    assert re.search(
        r"ALTER TABLE dispositivos ADD COLUMN rol_sesion\b", texto
    ), "falta el ALTER idempotente de dispositivos.rol_sesion"
    assert re.search(
        r"ALTER TABLE licencias ADD COLUMN max_sesiones\b", texto
    ), "falta el ALTER idempotente de licencias.max_sesiones"
    # Los ALTER viven dentro de bloques DO $$ guardados por information_schema.
    assert texto.count("DO $$") >= 2
    assert "information_schema.columns" in texto
