"""Nivel 2 de la suite SQL Server (T8): flujo funcional real sobre SQL Server.

Requiere ``MSSQL_TEST_URL_SYNC`` (URL ``mssql+pyodbc://...``); la variante
asíncrona ``mssql+aioodbc`` se deriva en memoria cambiando el prefijo. Sin
SQL Server real los tests se saltan.

Cubre (contra el esquema canónico T-SQL aplicado por ``asegurar_db``):
- ``WeighingService.generar_numero_boleto``: serie activa ``TA-`` emite
  ``TA-00000001`` … ``TA-00000003`` e incrementa ``siguiente`` (FOR UPDATE).
- ``ReportService.monthly``: cuenta los boletos CERRADO del mes.
- ``ReportService.peso_rango``: distribución por buckets (CASO especial:
  bindparams literal_execute repetidos en SELECT y GROUP BY, error 8120).
"""

from __future__ import annotations

import os
import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest

import wserver
from app.core import db_engine
from app.core.db_engine import desactivar_pooling_pyodbc
from app.models import BoletoPesaje, Empresa, SerieNumeracion
from app.services.report_service import ReportService
from app.services.weighing_service import WeighingService

desactivar_pooling_pyodbc()  # pyodbc 5: pooling interno → HY000 con lotes DDL
pytestmark = pytest.mark.mssql

PREFIJO_ASYNC = "mssql+aioodbc://"


def _url_sync_test() -> str:
    url = os.environ.get("MSSQL_TEST_URL_SYNC")
    if not url:
        pytest.skip("MSSQL_TEST_URL_SYNC no definida (SQL Server de prueba requerido)")
    return url


def _url_async(url_sync: str, bd: str) -> str:
    """Variante async con BD propia: mssql+aioodbc://.../<bd>?<query>"""
    from sqlalchemy.engine import make_url

    u = make_url(url_sync).set(database=bd)
    return u.render_as_string(hide_password=False).replace(
        "mssql+pyodbc://", PREFIJO_ASYNC, 1
    )


def _drop_bd(url_sync: str, bd: str) -> None:
    """Borra la BD de test dedicada (solo en el contenedor de pruebas)."""
    import pyodbc

    from app.core.db_engine import dsn_pyodbc

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
def entorno_mssql():
    """Fixture de módulo: BD dedicada con esquema aplicado + engine async."""
    from sqlalchemy.ext.asyncio import create_async_engine
    from sqlalchemy.pool import NullPool

    url_sync = _url_sync_test()
    bd = f"balansoft_ws_mssql_test_n2_{uuid.uuid4().hex[:8]}"

    # Comprobar disponibilidad conectando a master.
    try:
        import pyodbc  # noqa: F401

        c = wserver._descomponer_url(url_sync)
        from app.core.db_engine import dsn_pyodbc

        conn = pyodbc.connect(dsn_pyodbc({**c, "db": "master"}), autocommit=True, timeout=5)
        conn.close()
    except Exception as exc:  # noqa: BLE001 (sin SQL Server → skip, no fail)
        pytest.skip(f"SQL Server no disponible: {exc}")

    url_async = _url_async(url_sync, bd)

    # Aplicar esquema + siembra de migraciones vía WServer (Fase 2). Si
    # cualquiera de estos pasos falla, la BD temporal debe dropearse igual:
    # LOW-02 (huérfanas balansoft_ws_mssql_test* acumuladas en el contenedor).
    engine = None
    try:
        db_engine.marcar_estado_esquema(None)
        wserver.asegurar_db(_url_bd(url_sync, bd))
        assert db_engine.estado_esquema() == "aplicado"

        engine = create_async_engine(url_async, poolclass=NullPool)
        yield {
            "url_sync": url_sync,
            "bd": bd,
            "engine": engine,
        }
    finally:
        import asyncio

        if engine is not None:
            asyncio.run(engine.dispose())
        try:
            _drop_bd(url_sync, bd)
        except Exception:  # noqa: BLE001 — la limpieza no debe enmascarar un assert
            pass


def _url_bd(url_sync: str, bd: str) -> str:
    from sqlalchemy.engine import make_url

    return make_url(url_sync).set(database=bd).render_as_string(hide_password=False)


async def _sesion(engine):
    from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

    factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
    return factory()


@pytest.mark.asyncio
async def test_flujo_numero_serie_reporte(entorno_mssql):
    """Serie numeración, boleto CERRADO, monthly y peso_rango en mssql."""
    from sqlalchemy import select

    engine = entorno_mssql["engine"]

    async with await _sesion(engine) as db:
        # Empresa + serie activa TA- (1..N, 8 dígitos).
        empresa = Empresa(
            nombre_fiscal="Empresa Mssql N2",
            nombre_comercial="N2 S.A.",
            rif_nit=f"J-{uuid.uuid4().hex[:10]}",
            licencia_tier="CENTRAL",
            licencia_status="ACTIVE",
            activa=True,
        )
        db.add(empresa)
        await db.flush()
        serie = SerieNumeracion(
            id_empresa=empresa.id_empresa,
            nombre="Serie Principal",
            prefijo="TA-",
            inicio=1,
            siguiente=1,
            digitos=8,
            activa=True,
        )
        db.add(serie)
        await db.commit()

        # Emisión secuencial con FOR UPDATE: 3 números consecutivos.
        svc = WeighingService()
        n1 = await svc.generar_numero_boleto(db, empresa.id_empresa, serie.id_serie)
        n2 = await svc.generar_numero_boleto(db, empresa.id_empresa, serie.id_serie)
        n3 = await svc.generar_numero_boleto(db, empresa.id_empresa, serie.id_serie)
        assert [n1[0], n2[0], n3[0]] == ["TA-00000001", "TA-00000002", "TA-00000003"]
        assert n1[1] == serie.id_serie

        serie_actualizada = (
            await db.execute(
                select(SerieNumeracion).where(SerieNumeracion.id_serie == serie.id_serie)
            )
        ).scalar_one()
        assert serie_actualizada.siguiente == 4

        # Boletos CERRADO: dos en este mes (buckets 5-10t y 10-20t) y uno
        # anulado el mes pasado (debe quedar fuera de monthly y peso_rango).
        ahora = datetime.now(UTC)
        def _boleto(numero: str, peso: int, fecha: datetime, estado: str) -> BoletoPesaje:
            return BoletoPesaje(
                numero_boleto=numero,
                id_empresa=empresa.id_empresa,
                id_serie=serie.id_serie,
                fecha_hora_entrada=fecha,
                peso_entrada_vehiculo=Decimal(peso),
                peso_total_entrada=Decimal(peso),
                peso_salida_vehiculo=Decimal(0),
                peso_total_salida=Decimal(0),
                peso_neto=Decimal(peso),
                estado_boleto=estado,
                sincronizado=False,
                sync_intentos=0,
            )

        db.add(_boleto("TA-00000001", 6000, ahora, BoletoPesaje.ESTADO_CERRADO))
        db.add(_boleto("TA-00000002", 12000, ahora, BoletoPesaje.ESTADO_CERRADO))
        db.add(
            _boleto(
                "TA-00000003",
                99999,
                ahora - timedelta(days=40),
                BoletoPesaje.ESTADO_ANULADO,
            )
        )
        await db.commit()

        # monthly: solo 2 CERRADO del mes.
        rep = ReportService()
        informe = await rep.monthly(db, empresa, ahora.year, ahora.month)
        assert informe["total_pesajes"] == 2

        # peso_rango: 6000 → 5-10t, 12000 → 10-20t, 99999 anulado → fuera.
        distribucion = await rep.peso_rango(
            db, empresa, ahora - timedelta(days=1), ahora + timedelta(days=1)
        )
        assert distribucion["total_pesajes"] == 2
        por_rango = {r["rango"]: r["cantidad"] for r in distribucion["rangos"]}
        assert por_rango["5-10t"] == 1 and por_rango["10-20t"] == 1
        assert por_rango["40t+"] == 0

        # daily: el statement reescrito (cast/Date().with_variant(mssql.DATE))
        # debe compilar y devolver los 2 CERRADO de hoy (regresión 8120).
        diario = await rep.daily(db, empresa, ahora.date())
        assert diario["total_pesajes"] == 2