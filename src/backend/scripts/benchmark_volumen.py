#!/usr/bin/env python3
"""Benchmark de volumen P2 sobre la BD `balansoft_ws_volumen` (~50k boletos).

Mide la ruta de datos real (endpoint → SQLAlchemy → PostgreSQL → serialización)
con el transporte **ASGI en proceso**: sin red, sin uvicorn y sin WebSocket, para
que el número atribuido sea al SQL y no al entorno.

Decisiones metodológicas (importan al leer el reporte):

- ``get_current_user`` / ``get_current_empresa`` se sustituyen por dependencias
  reales resueltas contra la BD sembrada. La firma JWT se omite a propósito: es
  una verificación de firma (~µs) y meterla en el ruido escondería lo que se
  quiere medir, que es el acceso a datos.
- El rate limiting está **desactivado** por defecto en `config.py`
  (``rate_limit_enabled = False``); si estuviera activo, varias mediciones
  darían 429 y falsearían los percentiles.
- Cada escenario se repite ``--repeticiones`` veces (5 por defecto) y se
  reportan p50/p95/p99/max, no solo la media: los percentiles son los que
  importan para una estación de pesaje.
- Los parámetros se derivan de los datos realmente sembrados (una placa con
  muchos boletos, un producto con kardex), no se inventan a ciegas.

Uso:

    uv run python scripts/benchmark_volumen.py
    uv run python scripts/benchmark_volumen.py --repeticiones 10 --salida docs/evidencia/…
"""

from __future__ import annotations

import argparse
import asyncio
import os
import statistics
import sys
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
NOMBRE_BD = "balansoft_ws_volumen"

# Umbrales acordados (ms) para decidir si un escenario necesita un índice.
UMBRALES = {
    "weighing/list sin filtro (página 1)": 200,
    "weighing/list placa + rango de fechas": 300,
    "weighing/list página profunda (skip 20000)": 300,
    "weighing/list filtrado por estado": 200,
    "weighing/pendientes": 100,
    "reports/daily": 500,
    "reports/monthly": 1000,
    "reports/vehicle (1 placa, 12 meses)": 500,
    "reports/kardex/saldo": 300,
    "reports/kardex/detalle": 500,
    "catalogo/sync (todo)": 1000,
}


def cargar_env() -> None:
    env = BACKEND_DIR / ".env"
    if not env.is_file():
        return
    for linea in env.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea or linea.startswith("#") or "=" not in linea:
            continue
        clave, valor = linea.split("=", 1)
        os.environ.setdefault(clave.strip(), valor.strip().strip("\"'"))


def q(msg: str = "") -> None:
    print(msg, flush=True)


def pct(valores: list[float], p: float) -> float:
    """Percentil por el método del índice más cercano."""
    ordenados = sorted(valores)
    if not ordenados:
        return 0.0
    k = min(len(ordenados) - 1, max(0, round((p / 100) * (len(ordenados) - 1))))
    return ordenados[k]


async def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark P2 sobre 50k boletos")
    parser.add_argument("--repeticiones", type=int, default=5)
    parser.add_argument("--salida", type=Path, default=None,
                        help="Escribir además la tabla en este archivo de texto")
    args = parser.parse_args()

    cargar_env()
    if "DATABASE_URL" not in os.environ:
        raise SystemExit("Falta DATABASE_URL en backend/.env")
    os.environ["DATABASE_URL"] = os.environ["DATABASE_URL"].replace(
        "balansoft_ws_local", NOMBRE_BD)
    os.environ.setdefault("METRICS_ENABLED", "false")
    sys.path.insert(0, str(BACKEND_DIR))

    import httpx  # noqa: PLC0415
    from sqlalchemy import func, select  # noqa: PLC0415
    from sqlalchemy.ext.asyncio import create_async_engine  # noqa: PLC0415

    from app.api.dependencies import get_current_empresa, get_current_user  # noqa: PLC0415
    from app.core.database import AsyncSessionLocal  # noqa: PLC0415
    from app.main import app as fastapi_app  # noqa: PLC0415
    from app.models import (  # noqa: PLC0415
        BoletoPesaje,
        Empresa,
        Kardex,
        Producto,
        Usuario,
    )

    # ------------------------------------------------------------------
    # Datos representativos tomados del volumen sembrado
    # ------------------------------------------------------------------
    motor = create_async_engine(os.environ["DATABASE_URL"])
    async with AsyncSessionLocal() as db:
        empresa = (await db.execute(select(Empresa))).scalars().first()
        usuario = (await db.execute(
            select(Usuario).where(Usuario.email == "admin@volumen.demo"))).scalars().first()
        if empresa is None or usuario is None:
            raise SystemExit(
                "La BD de volumen está vacía. Genere la semilla antes:\n"
                "  uv run python scripts/seed_volumen.py --crear-bd")
        total_boletos = await db.scalar(
            select(func.count()).select_from(BoletoPesaje))
        # La placa con más boletos: el peor caso realista de /vehicle.
        placa_top = (await db.execute(
            select(BoletoPesaje.id_vehiculo, func.count().label("n"))
            .group_by(BoletoPesaje.id_vehiculo)
            .order_by(__import__("sqlalchemy").desc("n")).limit(1))).first()
        producto_kardex = (await db.execute(
            select(Producto).where(Producto.es_kardex.is_(True)).limit(1))).scalar_one_or_none()
        total_kardex = await db.scalar(
            select(func.count()).select_from(Kardex))

    placa = placa_top[0]
    placa_n = placa_top[1]
    producto_id = str(producto_kardex.id_producto) if producto_kardex else None

    ahora = datetime.now(UTC).replace(tzinfo=None, microsecond=0)
    hace_12m = ahora - timedelta(days=365)
    dia_reciente = (ahora - timedelta(days=7)).date()
    mes = ahora.month
    anio = ahora.year

    q(f"→ BD {NOMBRE_BD}: {total_boletos} boletos, {total_kardex} kardex")
    q(f"→ Peor caso de /vehicle: placa {placa} con {placa_n} boletos")
    q(f"→ Producto con kardex: {producto_id}")
    q(f"→ {args.repeticiones} repeticiones por escenario\n")

    # ------------------------------------------------------------------
    # La API con la empresa real resuelta desde la BD (no se falsea el tenant)
    # ------------------------------------------------------------------
    async def _usuario():
        return usuario

    async def _empresa():
        return empresa

    fastapi_app.dependency_overrides[get_current_user] = _usuario
    fastapi_app.dependency_overrides[get_current_empresa] = _empresa

    escenarios: list[tuple[str, str]] = [
        ("weighing/list sin filtro (página 1)",
         "/api/v1/weighing/list?skip=0&limit=100"),
        ("weighing/list placa + rango de fechas",
         f"/api/v1/weighing/list?skip=0&limit=100&vehicle_id={placa}"
         f"&date_from={hace_12m.isoformat()}&date_to={ahora.isoformat()}"),
        ("weighing/list página profunda (skip 20000)",
         "/api/v1/weighing/list?skip=20000&limit=100"),
        ("weighing/list filtrado por estado",
         "/api/v1/weighing/list?skip=0&limit=100&estado=PENDIENTE"),
        ("weighing/pendientes", "/api/v1/weighing/pendientes?skip=0&limit=100"),
        ("reports/daily", f"/api/v1/reports/daily?fecha={dia_reciente.isoformat()}"),
        ("reports/monthly", f"/api/v1/reports/monthly?year={anio}&month={mes}"),
        ("reports/vehicle (1 placa, 12 meses)",
         f"/api/v1/reports/vehicle/{placa}"
         f"?date_from={hace_12m.isoformat()}&date_to={ahora.isoformat()}"),
        ("reports/kardex/saldo",
         f"/api/v1/reports/kardex/saldo?fecha_corte={ahora.isoformat()}"
         + (f"&id_producto={producto_id}" if producto_id else "")),
        ("reports/kardex/detalle",
         f"/api/v1/reports/kardex/detalle"
         f"?fecha_desde={hace_12m.isoformat()}"
         f"&fecha_hasta={ahora.isoformat()}"
         + (f"&id_producto={producto_id}" if producto_id else "")),
        ("catalogo/sync (todo)", "/api/v1/catalogo/sync"),
    ]

    resultados: list[dict] = []
    transport = httpx.ASGITransport(app=fastapi_app)
    async with httpx.AsyncClient(transport=transport, base_url="http://bench",
                                 timeout=300.0) as cliente:
        for nombre, ruta in escenarios:
            # Calentamiento: descarta el plan de ejecución en caché y el
            # primer acceso a cada relación (por eso luego el p50 baja).
            await cliente.get(ruta)
            muestras: list[float] = []
            codigo = None
            filas = None
            for _ in range(args.repeticiones):
                t0 = time.perf_counter()
                r = await cliente.get(ruta)
                muestras.append((time.perf_counter() - t0) * 1000)
                codigo = r.status_code
                if filas is None and r.status_code == 200:
                    try:
                        cuerpo = r.json()
                        filas = len(cuerpo) if isinstance(cuerpo, list) else "obj"
                    except Exception:  # noqa: BLE001
                        filas = "?"
            resultados.append({
                "escenario": nombre, "ruta": ruta, "codigo": codigo, "filas": filas,
                "p50": pct(muestras, 50), "p95": pct(muestras, 95),
                "p99": pct(muestras, 99), "max": max(muestras),
                "media": statistics.fmean(muestras), "umbral": UMBRALES.get(nombre),
            })
            res = resultados[-1]
            marca = ""
            if res["umbral"] is not None:
                marca = "  ⚠ SUPERA UMBRAL" if res["p95"] > res["umbral"] else "  ok"
            q(f"  {res['p50']:8.1f} p50 | {res['p95']:8.1f} p95 | {res['p99']:8.1f} p99"
              f"  [{codigo}] filas={filas}  {nombre}{marca}")

    await motor.dispose()
    fastapi_app.dependency_overrides.clear()

    # ------------------------------------------------------------------
    # Tabla final
    # ------------------------------------------------------------------
    fuera_de_umbral = [r for r in resultados
                         if r["umbral"] is not None and r["p95"] > r["umbral"]]
    fallos = [r for r in resultados if r["codigo"] != 200]
    lineas = [
        "Benchmark de volumen P2 — balansoft_ws_volumen",
        "=" * 108,
        f"{'escenario':<44}{'p50':>9}{'p95':>9}{'p99':>9}{'max':>9}{'umbral':>9}  estado",
        "-" * 108,
    ]
    for r in resultados:
        if r["umbral"] is not None and r["p95"] > r["umbral"]:
            estado = "SUPERA"
        elif r["codigo"] != 200:
            estado = f"HTTP {r['codigo']}"
        else:
            estado = "ok"
        lineas.append(
            f"{r['escenario']:<44}{r['p50']:>9.1f}{r['p95']:>9.1f}{r['p99']:>9.1f}"
            f"{r['max']:>9.1f}{(r['umbral'] if r['umbral'] is not None else 0):>9.0f}  {estado}")
    lineas.append("-" * 108)
    lineas.append(f"{len(resultados) - len(fuera_de_umbral)}/{len(resultados)} escenarios dentro de umbral"
                  f" · {len(fallos)} con error HTTP")
    tabla = "\n".join(lineas)

    q("\n" + tabla)
    if args.salida:
        args.salida.parent.mkdir(parents=True, exist_ok=True)
        args.salida.write_text(tabla + "\n", encoding="utf-8")
        q(f"\n→ Tabla escrita en {args.salida}")
    if fuera_de_umbral:
        q(f"\n⚠ {len(fuera_de_umbral)} escenario(s) superan el umbral; requieren análisis.")
    if fallos:
        q(f"\n✗ {len(fallos)} escenario(s) devolvieron error; corregir antes de comparar.")


if __name__ == "__main__":
    asyncio.run(main())