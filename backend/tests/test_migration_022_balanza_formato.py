"""Tests de la migración 022: formato de trama y baudrate por balanza.

La migración 022 añade a `balanzas` la configuración fina del HAL para leer
básculas **reales** (no solo el simulador BSDD):

  - `formato_trama` VARCHAR(10) NOT NULL DEFAULT 'auto' → auto|json|ascii
  - `baudrate`      INTEGER    NOT NULL DEFAULT 9600
  - `delimitador`   VARCHAR(10) NULL                    → lf|cr|crlf|stx_etx

Los defaults dejan toda estación existente **exactamente como hoy**
(auto/9600/NULL): el simulador BSDD (JSON) sigue funcionando igual.

Mismo patrón que `test_migration_021_tamano_ticket.py`: el DDL va por `psycopg2`
(el protocolo simple acepta el archivo multi-sentencia) y las aserciones por la
sesión `db`, que garantiza que el esquema existe (`_engine` hace `create_all`).

Antes de cada verificación de creación se **eliminan** las columnas: si no, la
prueba sería un verde falso, porque `create_all` ya las crea desde el modelo y
nunca llegaría a probar que la migración funciona.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import psycopg2
import psycopg2.errors
import pytest
from pydantic import ValidationError
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models import Balanza
from app.schemas import BalanzaCreate

BACKEND = Path(__file__).resolve().parent.parent
MIGRACION = BACKEND / "migrations" / "022_balanza_formato_trama.sql"
ESQUEMA_LOCAL = BACKEND / "balansoft-ws-local.sql"
ESQUEMA_MSSQL = BACKEND / "sqlserver" / "balansoft-ws-local.sql"

FORMATOS_VALIDOS = ("auto", "json", "ascii")
# Debe coincidir con el CHECK `ck_balanzas_baudrate` de la BD y con el
# validador de `BalanzaCreate` (si divergen, un valor intermedio pasaría
# Pydantic y la BD respondería IntegrityError → 409 engañoso).
BAUDRATES_VALIDOS = (1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200)
DELIMITADORES_VALIDOS = ("lf", "cr", "crlf", "stx_etx")


# --------------------------------------------------------------------------- #
# Utilidades
# --------------------------------------------------------------------------- #
def _dsn_test() -> str:
    """DSN libpq de la BD de tests, respetando TEST_DATABASE_URL como en conftest."""
    url = os.environ.get("TEST_DATABASE_URL")
    if not url:
        head, _, _ = settings.database_url.rpartition("/")
        url = f"{head}/balansoft_ws_test"
    esquema, _, resto = url.partition("://")
    return f"{esquema.split('+', 1)[0]}://{resto}"


def _conectar():
    conn = psycopg2.connect(_dsn_test())
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("SET lock_timeout = '10s'")
    return conn


def _sql(script: str) -> None:
    with _conectar() as conn, conn.cursor() as cur:
        cur.execute(script)


def _aplicar_migracion() -> None:
    _sql(MIGRACION.read_text(encoding="utf-8"))


def _restablecer_pre_022() -> None:
    """Deja `balanzas` como estaba antes de la 022: sin esas columnas."""
    _sql(
        "ALTER TABLE balanzas DROP COLUMN IF EXISTS formato_trama;"
        "ALTER TABLE balanzas DROP COLUMN IF EXISTS baudrate;"
        "ALTER TABLE balanzas DROP COLUMN IF EXISTS delimitador;"
    )


def _empresa_id(rif: str) -> str:
    with _conectar() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO empresas (id_empresa, nombre_fiscal, rif_nit, activa) "
            "VALUES (gen_random_uuid(), 'Empresa Bal', %s, TRUE) RETURNING id_empresa",
            (rif,),
        )
        return cur.fetchone()[0]


def _insertar_balanza(
    formato: str | None = "auto",
    baudrate: int | None = 9600,
    delimitador: str | None = None,
    rif: str = "J-BAL-022",
) -> None:
    empresa = _empresa_id(rif)
    with _conectar() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO balanzas (id_balanza, id_empresa, descripcion, activo, "
            "is_simulada, formato_trama, baudrate, delimitador) "
            "VALUES (gen_random_uuid(), %s, 'Balanza Test', TRUE, FALSE, %s, %s, %s)",
            (empresa, formato, baudrate, delimitador),
        )


async def _columna(db: AsyncSession, nombre: str) -> tuple | None:
    res = await db.execute(
        text(
            "SELECT data_type, character_maximum_length, is_nullable, column_default "
            "FROM information_schema.columns "
            "WHERE table_schema = 'public' AND table_name = 'balanzas' "
            "AND column_name = :nombre"
        ),
        {"nombre": nombre},
    )
    fila = res.fetchone()
    return tuple(fila) if fila else None


@pytest.fixture(autouse=True)
async def _deja_esquema_022_aplicado(db: AsyncSession):
    """El resto de tests hereda el esquema con la 022 aplicada."""
    yield
    await db.rollback()
    _aplicar_migracion()


# --------------------------------------------------------------------------- #
# Migración
# --------------------------------------------------------------------------- #
class TestMigracion022:
    def test_archivo_022_existe(self):
        assert MIGRACION.is_file(), f"No existe {MIGRACION}"

    def test_no_crea_tablas_ni_columnas_de_tenant(self):
        """Constitución regla 1: la 022 no introduce tablas ni tenants nuevos."""
        sql = "\n".join(
            linea
            for linea in MIGRACION.read_text(encoding="utf-8").splitlines()
            if not linea.strip().startswith("--")
        ).upper()
        assert "CREATE TABLE" not in sql
        assert "CREATE SCHEMA" not in sql
        assert "ADD COLUMN IF NOT EXISTS ID_EMPRESA" not in sql

    async def test_crea_las_tres_columnas_con_tipo_y_default(self, db: AsyncSession):
        _restablecer_pre_022()
        _aplicar_migracion()

        formato = await _columna(db, "formato_trama")
        assert formato is not None, "formato_trama no creada por la migración"
        assert formato[0] == "character varying"
        assert formato[1] == 10
        assert formato[2] == "NO"
        assert formato[3] == "'auto'::character varying"

        baud = await _columna(db, "baudrate")
        assert baud is not None, "baudrate no creada por la migración"
        assert baud[0] == "integer"
        assert baud[1] is None
        assert baud[2] == "NO"
        assert baud[3] == "9600"

        delim = await _columna(db, "delimitador")
        assert delim is not None, "delimitador no creada por la migración"
        assert delim[0] == "character varying"
        assert delim[1] == 10
        assert delim[2] == "YES"
        assert delim[3] is None

    async def test_es_idempotente_aplicada_dos_veces(self, db: AsyncSession):
        _restablecer_pre_022()
        _aplicar_migracion()
        _aplicar_migracion()  # no debe lanzar

        assert await _columna(db, "formato_trama") is not None
        assert await _columna(db, "baudrate") is not None
        assert await _columna(db, "delimitador") is not None

        res = await db.execute(
            text(
                "SELECT conname FROM pg_constraint "
                "WHERE conrelid = 'balanzas'::regclass AND contype = 'c' "
                "AND conname LIKE 'ck_balanzas_%' ORDER BY conname"
            )
        )
        nombres = [r[0] for r in res.fetchall()]
        assert nombres == [
            "ck_balanzas_baudrate",
            "ck_balanzas_delimitador",
            "ck_balanzas_formato_trama",
        ], f"CHECKs inesperados tras dos aplicaciones: {nombres}"

    async def test_backfill_de_nulls_respeta_las_estaciones_existentes(
        self, db: AsyncSession
    ):
        """Una fila previa sin valor queda en los defaults de hoy (auto/9600/NULL)."""
        _restablecer_pre_022()
        _sql(
            "ALTER TABLE balanzas ADD COLUMN formato_trama VARCHAR(10);"
            "ALTER TABLE balanzas ADD COLUMN baudrate INTEGER;"
            "ALTER TABLE balanzas ADD COLUMN delimitador VARCHAR(10);"
        )
        empresa = _empresa_id("J-LEGACY-022")
        _sql(
            "INSERT INTO balanzas (id_balanza, id_empresa, descripcion, activo, "
            "is_simulada, formato_trama, baudrate, delimitador) "
            f"VALUES (gen_random_uuid(), '{empresa}', 'Balanza Legada', TRUE, FALSE, "
            "NULL, NULL, NULL);"
        )
        _aplicar_migracion()

        res = await db.execute(
            text(
                "SELECT formato_trama, baudrate, delimitador FROM balanzas "
                "WHERE descripcion = 'Balanza Legada'"
            )
        )
        assert res.fetchall() == [("auto", 9600, None)]


# --------------------------------------------------------------------------- #
# Literales admitidos
# --------------------------------------------------------------------------- #
class TestLiteralesAdmitidos:
    def test_formato_admite_los_tres_valores(self):
        _aplicar_migracion()
        for i, valor in enumerate(FORMATOS_VALIDOS):
            _insertar_balanza(formato=valor, rif=f"J-FMT-{i}")

    def test_formato_rechaza_valor_fuera_del_literal(self):
        _aplicar_migracion()
        with pytest.raises(psycopg2.errors.CheckViolation):
            _insertar_balanza(formato="binario", rif="J-MAL-FMT")

    @pytest.mark.parametrize("baudrate", BAUDRATES_VALIDOS)
    def test_baudrate_admite_valores_estandar(self, baudrate):
        _aplicar_migracion()
        _insertar_balanza(baudrate=baudrate, rif=f"J-BAUD-{baudrate}")

    def test_baudrate_rechaza_valor_no_estandar(self):
        _aplicar_migracion()
        with pytest.raises(psycopg2.errors.CheckViolation):
            _insertar_balanza(baudrate=12345, rif="J-MAL-BAUD")

    @pytest.mark.parametrize("delim", DELIMITADORES_VALIDOS)
    def test_delimitador_admite_los_validos(self, delim):
        _aplicar_migracion()
        _insertar_balanza(delimitador=delim, rif=f"J-DELIM-{delim}")

    def test_delimitador_rechaza_valor_desconocido(self):
        _aplicar_migracion()
        with pytest.raises(psycopg2.errors.CheckViolation):
            _insertar_balanza(delimitador="pipe", rif="J-MAL-DELIM")

    def test_delimitador_acepta_null(self):
        """NULL = lf: el CHECK no estrangula la compatibilidad."""
        _aplicar_migracion()
        _insertar_balanza(delimitador=None, rif="J-NULL-DELIM")


# --------------------------------------------------------------------------- #
# Modelo SQLAlchemy
# --------------------------------------------------------------------------- #
class TestModeloBalanza:
    def test_expone_las_tres_columnas(self):
        columnas = set(Balanza.__table__.columns.keys())
        assert "formato_trama" in columnas
        assert "baudrate" in columnas
        assert "delimitador" in columnas

    def test_formato_tipo_nullable_y_default(self):
        col: Any = Balanza.__table__.columns["formato_trama"]
        assert col.type.length == 10
        assert col.nullable is False
        assert col.default is not None and col.default.arg == "auto"
        assert col.server_default is not None and "auto" in str(col.server_default.arg)

    def test_baudrate_tipo_nullable_y_default(self):
        col = Balanza.__table__.columns["baudrate"]
        assert col.nullable is False
        assert col.default is not None and col.default.arg == 9600
        assert col.server_default is not None and "9600" in str(col.server_default.arg)

    def test_delimitador_es_nullable_sin_default(self):
        col: Any = Balanza.__table__.columns["delimitador"]
        assert col.type.length == 10
        assert col.nullable is True
        assert col.default is None
        assert col.server_default is None

    def test_conserva_id_balanza_y_fk_a_empresa(self):
        assert [c.name for c in Balanza.__table__.primary_key] == ["id_balanza"]
        fks = {fk.target_fullname for fk in Balanza.__table__.foreign_keys}
        assert "empresas.id_empresa" in fks


# --------------------------------------------------------------------------- #
# Schema Pydantic (validación alineada con el CHECK de la BD)
# --------------------------------------------------------------------------- #
class TestSchemaBalanzaCreate:
    def _crear(self, **over) -> BalanzaCreate:
        base: dict[str, Any] = {
            "descripcion": "Balanza X",
            "codigo": None,
            "marca": None,
            "modelo": None,
            "capacidad_max": None,
            "division": None,
            "activo": True,
            "is_simulada": False,
            "puerto_com": None,
            "ip_address": None,
            "puerto_tcp": None,
            "protocolo": None,
            "formato_trama": "auto",
            "baudrate": 9600,
            "delimitador": None,
        }
        base.update(over)
        return BalanzaCreate(**base)

    def test_defaults_no_opcionales(self):
        """Los defaults deben permitir create/update sin NULL en columnas NOT NULL."""
        s = self._crear()
        assert s.formato_trama == "auto"
        assert s.baudrate == 9600
        assert s.delimitador is None

    @pytest.mark.parametrize("baudrate", BAUDRATES_VALIDOS)
    def test_baudrate_admite_estandar(self, baudrate):
        assert self._crear(baudrate=baudrate).baudrate == baudrate

    @pytest.mark.parametrize("baudrate", (12345, 14400, 14401))
    def test_baudrate_rechaza_intermedios(self, baudrate):
        """Un valor fuera del CHECK no debe pasar Pydantic (evita el 409 engañoso)."""
        with pytest.raises(ValidationError, match="baudrate"):
            self._crear(baudrate=baudrate)

    def test_paridad_con_el_check_de_la_bd(self):
        """El conjunto validado por Pydantic == conjunto del CHECK de la BD."""
        sql = MIGRACION.read_text(encoding="utf-8")
        linea = next(s for s in sql.splitlines() if "CHECK (baudrate IN" in s)
        for valor in BAUDRATES_VALIDOS:
            assert str(valor) in linea
        # Y ningún valor "intermedio" cuela en el CHECK.
        assert "14400" not in linea


# --------------------------------------------------------------------------- #
# Reflejo en los esquemas canónicos
# --------------------------------------------------------------------------- #
def _bloque_create_table_balanzas(texto: str) -> str:
    inicio = texto.index("CREATE TABLE IF NOT EXISTS balanzas (")
    return texto[inicio : texto.index(");", inicio)]


class TestEsquemasReflejados:
    def test_pg_create_table_las_declara(self):
        bloque = _bloque_create_table_balanzas(ESQUEMA_LOCAL.read_text(encoding="utf-8"))
        assert "formato_trama" in bloque
        assert "baudrate" in bloque
        assert "delimitador" in bloque

    def test_pg_bloque_de_alineacion_las_agrega(self):
        texto = ESQUEMA_LOCAL.read_text(encoding="utf-8")
        assert "ADD COLUMN IF NOT EXISTS formato_trama" in texto
        assert "ADD COLUMN IF NOT EXISTS baudrate" in texto
        assert "ADD COLUMN IF NOT EXISTS delimitador" in texto

    def test_pg_declara_los_tres_checks(self):
        texto = ESQUEMA_LOCAL.read_text(encoding="utf-8")
        assert "ck_balanzas_formato_trama" in texto
        assert "ck_balanzas_baudrate" in texto
        assert "ck_balanzas_delimitador" in texto

    def test_mssql_create_table_las_declara(self):
        texto = ESQUEMA_MSSQL.read_text(encoding="utf-8")
        assert "[formato_trama] NVARCHAR(10)" in texto
        assert "[baudrate] INT" in texto
        assert "[delimitador] NVARCHAR(10)" in texto
        assert "ck_balanzas_formato_trama" in texto
        assert "ck_balanzas_baudrate" in texto
        assert "ck_balanzas_delimitador" in texto
