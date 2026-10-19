"""Tests de la migración 021: tipografía del ticket por `id_empresa`.

Cubre REQ-FN-009 (persistencia por empresa), REQ-FN-012 (las estaciones
existentes siguen igual) y REQ-FN-014 (solo DejaVu Sans).

La migración 021 añade a `empresas`:
  - `tamano_ticket_pdf` VARCHAR(20) → AUTOMATICO|GRANDE|MEDIANO|PEQUENO (def. AUTOMATICO)
  - `fuente_ticket_pdf`  VARCHAR(20) → DejaVu (def. DejaVu)

Por qué `psycopg2` y no `asyncpg`: el protocolo de consulta simple acepta el
archivo multi-sentencia tal cual (igual que `scripts/setup_db.sh`), mientras que
asyncpg exige una sentencia por `execute`. El DDL/DML va por psycopg2 y las
aserciones por la sesión `db` (que además garantiza que el esquema existe, ya
que `_engine` hace `create_all` a partir del modelo).

Antes de cada verificación de creación se **eliminan** las columnas: si no, la
prueba sería un verde falso, porque `create_all` ya las crea desde el modelo y
nunca llegaría a probar que la migración funciona.
"""

from __future__ import annotations

import os
from pathlib import Path

import psycopg2
import psycopg2.errors
import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models import Empresa

BACKEND = Path(__file__).resolve().parent.parent
MIGRACION = BACKEND / "migrations" / "021_tamano_ticket_empresa.sql"
ESQUEMA_LOCAL = BACKEND / "balansoft-ws-local.sql"

TAMANO_VALIDOS = ("AUTOMATICO", "GRANDE", "MEDIANO", "PEQUENO")
FUENTE_VALIDA = "DejaVu"


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
    # Sin esto, un DDL que espera un lock cuelga el suite entero en vez de fallar.
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("SET lock_timeout = '10s'")
    return conn


def _sql(script: str) -> None:
    """Ejecuta un script multi-sentencia vía psycopg2 (DDL/DML)."""
    with _conectar() as conn, conn.cursor() as cur:
        cur.execute(script)


def _aplicar_migracion() -> None:
    _sql(MIGRACION.read_text(encoding="utf-8"))


def _restablecer_pre_021() -> None:
    """Deja `empresas` como estaba antes de la 021: sin esas columnas."""
    _sql(
        "ALTER TABLE empresas DROP COLUMN IF EXISTS tamano_ticket_pdf;"
        "ALTER TABLE empresas DROP COLUMN IF EXISTS fuente_ticket_pdf;"
    )


def _insertar(rif: str, tamano: str, fuente: str) -> None:
    with _conectar() as conn, conn.cursor() as cur:
        # `id_empresa` y `activa` se escriben explícitos: en el modelo sus
        # defaults son Python (`default=_uuid` / `default=True`), no de servidor,
        # así que la tabla que crea `create_all` no los tiene.
        cur.execute(
            "INSERT INTO empresas (id_empresa, nombre_fiscal, rif_nit, activa, "
            "tamano_ticket_pdf, fuente_ticket_pdf) "
            "VALUES (gen_random_uuid(), %s, %s, TRUE, %s, %s)",
            ("Empresa Test", rif, tamano, fuente),
        )


async def _columna(db: AsyncSession, nombre: str) -> tuple | None:
    res = await db.execute(
        text(
            "SELECT data_type, character_maximum_length, is_nullable, column_default "
            "FROM information_schema.columns "
            "WHERE table_schema = 'public' AND table_name = 'empresas' "
            "AND column_name = :nombre"
        ),
        {"nombre": nombre},
    )
    fila = res.fetchone()
    return tuple(fila) if fila else None


@pytest.fixture(autouse=True)
async def _deja_esquema_021_aplicado(db: AsyncSession):
    """El resto de tests hereda el esquema con la 021 aplicada.

    `db` se solicita solo por su efecto secundario: `_engine` ejecuta
    `create_all`, que es lo que hace existir la tabla `empresas`.
    """
    yield
    # La sesión puede haber dejado una transacción abierta con un lock sobre
    # `empresas`; sin cerrarla, el DDL de este teardown se espera a sí mismo.
    await db.rollback()
    _aplicar_migracion()


# --------------------------------------------------------------------------- #
# Migración
# --------------------------------------------------------------------------- #
class TestMigracion021:
    def test_archivo_021_existe(self):
        assert MIGRACION.is_file(), f"No existe {MIGRACION}"

    def test_no_crea_tablas_ni_columnas_de_tenant(self):
        """Constitución regla 1: la 021 no introduce tablas ni tenants nuevos."""
        # Se ignoran los comentarios: el encabezado documenta el reflejo en
        # `balansoft-ws-local.sql` y menciona `CREATE TABLE` sin crearlo.
        sql = "\n".join(
            linea
            for linea in MIGRACION.read_text(encoding="utf-8").splitlines()
            if not linea.strip().startswith("--")
        ).upper()
        assert "CREATE TABLE" not in sql
        assert "CREATE SCHEMA" not in sql
        assert "ADD COLUMN IF NOT EXISTS ID_EMPRESA" not in sql

    async def test_crea_las_dos_columnas_con_tipo_y_default(self, db: AsyncSession):
        _restablecer_pre_021()
        _aplicar_migracion()

        tamano = await _columna(db, "tamano_ticket_pdf")
        assert tamano is not None, "tamano_ticket_pdf no creada por la migración"
        assert tamano[0] == "character varying"
        assert tamano[1] == 20
        assert tamano[2] == "YES"
        assert tamano[3] == "'AUTOMATICO'::character varying"

        fuente = await _columna(db, "fuente_ticket_pdf")
        assert fuente is not None, "fuente_ticket_pdf no creada por la migración"
        assert fuente[0] == "character varying"
        assert fuente[1] == 20
        assert fuente[2] == "YES"
        assert fuente[3] == "'DejaVu'::character varying"

    async def test_es_idempotente_aplicada_dos_veces(self, db: AsyncSession):
        _restablecer_pre_021()
        _aplicar_migracion()
        _aplicar_migracion()  # no debe lanzar

        assert await _columna(db, "tamano_ticket_pdf") is not None
        assert await _columna(db, "fuente_ticket_pdf") is not None

        res = await db.execute(
            text(
                "SELECT conname FROM pg_constraint "
                "WHERE conrelid = 'empresas'::regclass AND contype = 'c' "
                "AND conname LIKE 'ck_empresas%ticket_pdf%' ORDER BY conname"
            )
        )
        nombres = [r[0] for r in res.fetchall()]
        assert nombres == ["ck_empresas_fuente_ticket_pdf", "ck_empresas_tamano_ticket_pdf"], (
            f"CHECKs inesperados tras dos aplicaciones: {nombres}"
        )

    async def test_backfill_de_nulls_respeta_las_estaciones_existentes(
        self, db: AsyncSession
    ):
        """REQ-FN-012: una fila previa sin valor queda en los defaults de hoy."""
        _restablecer_pre_021()
        _sql(
            "ALTER TABLE empresas ADD COLUMN tamano_ticket_pdf VARCHAR(20);"
            "ALTER TABLE empresas ADD COLUMN fuente_ticket_pdf VARCHAR(20);"
            "INSERT INTO empresas (id_empresa, nombre_fiscal, rif_nit, activa) "
            "VALUES (gen_random_uuid(), 'Empresa Legada', 'J-LEGACY-021', TRUE);"
        )
        _aplicar_migracion()

        res = await db.execute(
            text(
                "SELECT tamano_ticket_pdf, fuente_ticket_pdf FROM empresas WHERE rif_nit = :r"
            ),
            {"r": "J-LEGACY-021"},
        )
        assert res.fetchall() == [("AUTOMATICO", FUENTE_VALIDA)]


# --------------------------------------------------------------------------- #
# Literales de la spec
# --------------------------------------------------------------------------- #
class TestLiteralesAdmitidos:
    def test_tamano_admite_los_cuatro_valores(self):
        _aplicar_migracion()
        for i, valor in enumerate(TAMANO_VALIDOS):
            _insertar(f"J-OK-{i}", valor, FUENTE_VALIDA)

    def test_tamano_rechaza_valor_fuera_del_literal(self):
        _aplicar_migracion()
        with pytest.raises(psycopg2.errors.CheckViolation):
            _insertar("J-MAL-TAM", "GIGANTE", FUENTE_VALIDA)

    def test_fuente_admite_dejavu(self):
        _aplicar_migracion()
        _insertar("J-OK-FUE", "AUTOMATICO", FUENTE_VALIDA)

    def test_fuente_rechaza_otra_familia(self):
        """REQ-FN-014: la única familia admitida es DejaVu Sans."""
        _aplicar_migracion()
        with pytest.raises(psycopg2.errors.CheckViolation):
            _insertar("J-MAL-FUE", "AUTOMATICO", "Roboto")

    def test_los_check_aceptan_null(self):
        """El CHECK no estrangula la compatibilidad: NULL sigue siendo admisible."""
        _aplicar_migracion()
        _sql(
            "INSERT INTO empresas (id_empresa, nombre_fiscal, rif_nit, activa) "
            "VALUES (gen_random_uuid(), 'Empresa Nulls', 'J-NULL-021', TRUE)"
        )


# --------------------------------------------------------------------------- #
# Modelo SQLAlchemy
# --------------------------------------------------------------------------- #
class TestModeloEmpresa:
    def test_expone_las_dos_columnas(self):
        columnas = set(Empresa.__table__.columns.keys())
        assert "tamano_ticket_pdf" in columnas
        assert "fuente_ticket_pdf" in columnas

    @pytest.mark.parametrize(
        "nombre,default",
        [("tamano_ticket_pdf", "AUTOMATICO"), ("fuente_ticket_pdf", "DejaVu")],
    )
    def test_tipo_nullable_y_default(self, nombre, default):
        col = Empresa.__table__.columns[nombre]
        assert col.type.length == 20
        assert col.nullable is True
        assert col.default is not None and col.default.arg == default
        assert col.server_default is not None and default in str(col.server_default.arg)

    def test_conserva_id_empresa_como_pk(self):
        assert [c.name for c in Empresa.__table__.primary_key] == ["id_empresa"]


# --------------------------------------------------------------------------- #
# Reflejo en el esquema canónico local
# --------------------------------------------------------------------------- #
def _bloque_create_table_empresas(texto: str) -> str:
    inicio = texto.index("CREATE TABLE IF NOT EXISTS empresas (")
    return texto[inicio : texto.index(");", inicio)]


def _bloque_alineacion(texto: str) -> str:
    inicio = texto.index("-- Alineación idempotente")
    return texto[inicio : texto.index("ALTER TABLE empresas ALTER COLUMN id_cuenta")]


class TestEsquemaLocalReflejado:
    def test_create_table_de_empresas_las_declara(self):
        bloque = _bloque_create_table_empresas(ESQUEMA_LOCAL.read_text(encoding="utf-8"))
        assert "tamano_ticket_pdf" in bloque
        assert "fuente_ticket_pdf" in bloque

    def test_bloque_de_alineacion_las_agrega(self):
        bloque = _bloque_alineacion(ESQUEMA_LOCAL.read_text(encoding="utf-8"))
        assert "ADD COLUMN IF NOT EXISTS tamano_ticket_pdf" in bloque
        assert "ADD COLUMN IF NOT EXISTS fuente_ticket_pdf" in bloque

    def test_declara_los_dos_checks(self):
        texto = ESQUEMA_LOCAL.read_text(encoding="utf-8")
        assert "ck_empresas_tamano_ticket_pdf" in texto
        assert "ck_empresas_fuente_ticket_pdf" in texto


# --------------------------------------------------------------------------- #
# F1: el esquema local sigue sin `series_numeracion` (fuera de alcance de la 021)
# --------------------------------------------------------------------------- #
def test_f1_series_numeracion_sigue_ausente_y_no_afecta_a_la_021():
    assert "series_numeracion" not in ESQUEMA_LOCAL.read_text(encoding="utf-8")
    assert "series_numeracion" not in MIGRACION.read_text(encoding="utf-8")