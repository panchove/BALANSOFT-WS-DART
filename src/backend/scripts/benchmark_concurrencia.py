#!/usr/bin/env python3
"""Benchmark concurrente P2c — JWT + red TCP reales contra el servidor de una estación.

`benchmark_volumen.py` mide la ruta de datos por transporte ASGI en proceso, sin
red y sin validar JWT. Eso es una **cota inferior**: una estación real siempre
paga además la firma del token, el stack HTTP, el socket y la serialización en
JSON. Este script mide esa diferencia completa.

Por qué importa el diseño del test:

- **Un solo worker.** `wserver.py` lanza `uvicorn.run(app, ...)` con el valor por
  defecto (`workers=1`): toda la estación comparte **un** event loop. Por eso la
  concurrencia se mide contra un único worker — es el despliegue real — y por eso
  el N+1 que se corrigió en P2 no era un detalle: bloqueaba el loop entero.
- **JWT de verdad.** Cada operador virtual hace `POST /auth/login` y usa el token
  que le devuelve el servidor. No se falsea la autenticación.
- **Cierre por operador.** Cada operador virtual espera su respuesta antes de
  pedir la siguiente (como una persona frente a una pantalla), con un tiempo de
  pensar configurable. Abrir el lazo sin pausa satura la estación de forma
  artificial y no representa el uso real.

Uso:

    uv run python scripts/benchmark_concurrencia.py
    uv run python scripts/benchmark_concurrencia.py --operadores 1,5,10 --duracion 20
    uv run python scripts/benchmark_concurrencia.py --sin-think   # satuación pura
"""

from __future__ import annotations

import argparse
import asyncio
import os
import subprocess
import sys
import time
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
NOMBRE_BD = "balansoft_ws_volumen"
PUERTO = 8099
EMAIL = "admin@volumen.demo"
PASSWORD = "volumen1234"


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
    if not valores:
        return 0.0
    o = sorted(valores)
    return o[min(len(o) - 1, max(0, round((p / 100) * (len(o) - 1))))]


async def esperar_salud(url: str, segundos: int = 40) -> None:
    import httpx

    limite = time.monotonic() + segundos
    async with httpx.AsyncClient(timeout=5.0) as c:
        while time.monotonic() < limite:
            try:
                if (await c.get(f"{url}/api/v1/health")).status_code == 200:
                    return
            except Exception:  # noqa: BLE001
                pass
            await asyncio.sleep(0.4)
    raise SystemExit(f"El servidor no respondió /health en {segundos}s")


async def main() -> None:
    ap = argparse.ArgumentParser(description="Benchmark concurrente P2c (JWT + TCP)")
    ap.add_argument("--operadores", default="1,5,10",
                    help="Niveles de concurrencia, separados por coma")
    ap.add_argument("--duracion", type=int, default=15, help="Segundos por nivel")
    ap.add_argument("--sin-think", action="store_true",
                    help="Sin tiempo de pensar: satura la estación (peor caso)")
    ap.add_argument("--think", type=float, default=0.2,
                    help="Pausa por operador entre peticiones, en segundos")
    ap.add_argument("--puerto", type=int, default=PUERTO)
    ap.add_argument("--salida", type=Path, default=None)
    args = ap.parse_args()

    cargar_env()
    if "DATABASE_URL" not in os.environ:
        raise SystemExit("Falta DATABASE_URL en backend/.env")
    base = os.environ["DATABASE_URL"].replace("balansoft_ws_local", NOMBRE_BD)
    os.environ["DATABASE_URL"] = base
    sys.path.insert(0, str(BACKEND_DIR))

    import httpx  # noqa: PLC0415

    niveles = [int(x) for x in args.operadores.split(",") if x.strip()]
    url = f"http://127.0.0.1:{args.puerto}"
    think = 0.0 if args.sin_think else args.think

    # ------------------------------------------------------------------
    # Un worker, como la estación real
    # ------------------------------------------------------------------
    entorno = dict(os.environ)
    q(f"→ Levantando uvicorn (workers=1) en {url} contra {NOMBRE_BD}")
    servidor = subprocess.Popen(  # noqa: S603
        [sys.executable, "-m", "uvicorn", "app.main:app",
         "--host", "127.0.0.1", "--port", str(args.puerto), "--workers", "1",
         "--log-level", "warning"],
        cwd=BACKEND_DIR, env=entorno,
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )
    try:
        await esperar_salud(url)
        q("→ Servidor listo\n")

        # Operadores virtuales con token real
        async with httpx.AsyncClient(base_url=url, timeout=30.0) as cliente:
            tokens: list[str] = []
            for _ in range(max(niveles)):
                r = await cliente.post(
                    "/api/v1/auth/login",
                    json={"email": EMAIL, "password": PASSWORD},
                )
                r.raise_for_status()
                tokens.append(r.json()["access_token"])
            q(f"→ {len(tokens)} operadores virtuales autenticados (JWT real)\n")

            # Escenarios: uno representative del spectrum de la P2 + la base
            # sin auth para aislar el stack HTTP del costo de la API.
            base_sin_auth = "/api/v1/health"
            base_con_auth = "/api/v1/catalogo/sync?catalogo=almacenes"
            pesados = [
                "/api/v1/weighing/list?skip=0&limit=100",
                "/api/v1/weighing/pendientes?limit=100",
                "/api/v1/reports/daily",
                "/api/v1/reports/kardex/saldo",
            ]

            async def operador(token: str | None, ruta: str, parar: asyncio.Event):
                """Un operador virtual: pide, espera, piensa, repite."""
                cab = {} if token is None else {"Authorization": f"Bearer {token}"}
                muestras: list[float] = []
                errores = 0
                async with httpx.AsyncClient(
                    base_url=url, timeout=30.0, headers=cab
                ) as c:
                    while not parar.is_set():
                        t0 = time.perf_counter()
                        try:
                            r = await c.get(ruta)
                            if r.status_code >= 500:
                                errores += 1
                        except Exception:  # noqa: BLE001
                            errores += 1
                        muestras.append((time.perf_counter() - t0) * 1000)
                        if think:
                            await asyncio.sleep(think)
                return muestras, errores

            resultados: list[dict] = []
            for n in niveles:
                for nombre, ruta, con_token in (
                    ("base sin auth (/health)", base_sin_auth, False),
                    ("base con auth (catálogo)", base_con_auth, True),
                    *[("pesado " + r.split("?")[0].split("/")[-1], r, True) for r in pesados],
                ):
                    parar = asyncio.Event()
                    tareas = [
                        asyncio.create_task(
                            operador(tokens[i % len(tokens)] if con_token else None,
                                     ruta, parar)
                        )
                        for i in range(n)
                    ]
                    await asyncio.sleep(args.duracion)
                    parar.set()
                    todas = await asyncio.gather(*tareas)
                    muestras = [m for sublote, _ in todas for m in sublote]
                    errores = sum(e for _, e in todas)
                    if not muestras:
                        continue
                    p50 = pct(muestras, 50)
                    resultados.append({
                        "operadores": n, "escenario": nombre, "p50": p50,
                        "p95": pct(muestras, 95), "p99": pct(muestras, 99),
                        "max": max(muestras), "rps": len(muestras) / args.duracion,
                        "errores": errores, "n": len(muestras),
                    })
                    res = resultados[-1]
                    marca = "  ⚠ ERRORES" if errores else ""
                    q(f"  n={n:>2} {res['p50']:>7.1f} p50 | {res['p95']:>7.1f} p95 | "
                      f"{res['p99']:>7.1f} p99 | {res['rps']:>6.1f} req/s  {nombre}{marca}")
                q("")
    finally:
        servidor.terminate()
        try:
            servidor.wait(timeout=10)
        except subprocess.TimeoutExpired:
            servidor.kill()

    # ------------------------------------------------------------------
    # Informe
    # ------------------------------------------------------------------
    titulo = ("P2c concurrente — saturación pura (sin think)" if args.sin_think
              else f"P2c concurrente — think={think}s, {args.duracion}s por nivel")
    lineas = [titulo, "=" * 96,
              f"{'operadores':>11}{'escenario':>26}{'p50':>9}{'p95':>9}{'p99':>9}"
              f"{'max':>9}{'req/s':>9}{'err':>5}", "-" * 96]
    for r in resultados:
        lineas.append(
            f"{r['operadores']:>11}{r['escenario']:>26}{r['p50']:>9.1f}{r['p95']:>9.1f}"
            f"{r['p99']:>9.1f}{r['max']:>9.1f}{r['rps']:>9.1f}{r['errores']:>5}")
    lineas.append("-" * 96)
    total_err = sum(r["errores"] for r in resultados)
    lineas.append(f"Errores 5xx totales: {total_err}")
    tabla = "\n".join(lineas)

    q("\n" + tabla)
    if args.salida:
        args.salida.parent.mkdir(parents=True, exist_ok=True)
        args.salida.write_text(tabla + "\n", encoding="utf-8")
        q(f"\n→ Tabla escrita en {args.salida}")


if __name__ == "__main__":
    asyncio.run(main())