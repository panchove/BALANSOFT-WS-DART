#!/usr/bin/env python3
"""Semilla de volumen para P2 (prueba de ~50k boletos).

Genera un conjunto **coherente con las reglas de negocio** en una base
**diferente** a la de trabajo (`balansoft_ws_local`) y a la de pruebas
(`balansoft_ws_test`): por defecto `balansoft_ws_volumen`, que se crea desde
el esquema canónico `backend/balansoft-ws-local.sql`.

Qué garantiza el generador (para que el benchmark mida algo real):

- Numeración por series (migración 015) con contadores altos, coherentes con
  los números de boleto emitidos.
- Estados ``PENDIENTE / CERRADO / MODIFICADO / ANULADO`` con la distribución
  acordada; los ANULADOS se anulan **solo** desde CERRADO y conservan
  ``motivo_anulacion``.
- Pesos: ``tara < bruto``, ``neto = bruto - tara``, ``bruto + tara`` no se
  inventa, y los campos derivados (densidad, litros, diferencia, desviación)
  se rellenan igual que lo hace la capa de pesajes.
- Kardex: solo para productos con ``es_kardex``; CERRADO con neto >= 0 genera
  INGRESO (10, positivo) y con neto < 0 DESPACHO (60, negativo); cada ANULADO
  de un boleto con kardex genera el movimiento **inverso** (60 <-> 10), sin
  borrar el original (regla invariable: no se elimina historia).
- Timestamps en UTC naive (columnas ``timestamp without time zone``), igual
  que el runtime.

Uso:

    # crear la BD desde el esquema canónico y llenarla
    uv run python scripts/seed_volumen.py --crear-bd

    # reutilizar una BD ya creada y rellenarla
    VOLUMEN_DATABASE_URL=postgresql+asyncpg://... uv run python scripts/seed_volumen.py

    # borrar la BD de volumen al terminar
    uv run python scripts/seed_volumen.py --drop-bd
"""

from __future__ import annotations

import argparse
import asyncio
import os
import random
import sys
import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
ESQUEMA = BACKEND_DIR / "balansoft-ws-local.sql"
MIGRACIONES = BACKEND_DIR / "migrations"
NOMBRE_BD = "balansoft_ws_volumen"


def cargar_env() -> None:
    """Carga `backend/.env` al entorno (pydantic solo lo lee para `settings`)."""
    env = BACKEND_DIR / ".env"
    if not env.is_file():
        return
    for linea in env.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea or linea.startswith("#") or "=" not in linea:
            continue
        clave, valor = linea.split("=", 1)
        os.environ.setdefault(clave.strip(), valor.strip().strip("\"'"))

# --------------------------------------------------------------------------
# Parámetros del volumen
# --------------------------------------------------------------------------
BOLETOS = 50_000
CAMIONES = 500
CONDUCTORES = 200
TRANSPORTES = 50
PRODUCTOS = 100
PRODUCTOS_KARDEX = 20
ALMACENES = 20
BALANZAS = 10
SERIES = 5
MESES = 12
LOTE = 2_000  # boletos por transaction para no inflar la WAL

DISTRIBUCION = {"CERRADO": 0.70, "PENDIENTE": 0.20, "MODIFICADO": 0.05, "ANULADO": 0.05}

# Estados que generan asiento de kardex (los PENDIENTE todavía no se cerraron).
CON_KARDEX = ("CERRADO", "MODIFICADO", "ANULADO")

EMPRESA_NOMBRE = "Volumetrica Demo S.A."
EMPRESA_RIF = "J-40999888-7"
USUARIO_EMAIL = "admin@volumen.demo"
USUARIO_PASS = "volumen1234"

PRODUCTOS_BASE = [
    ("Maíz blanco", "Granel", True, 750.0),
    ("Arroz paddy", "Granel", True, 780.0),
    ("Azúcar refinada", "Granel", True, 850.0),
    ("Café en grano", "Granel", True, 650.0),
    ("Trigo suave", "Granel", True, 780.0),
    ("Soya", "Granel", True, 760.0),
    ("Caña de azúcar", "Granel", True, 900.0),
    ("Cacao en grano", "Granel", True, 500.0),
    ("Papa", "Granel", True, 650.0),
    ("Caraota", "Granel", True, 800.0),
]
PRODUCTOS_SIN_KARDEX = [
    ("Concreto listo", "Construcción", False, 2400.0),
    ("Grava", "Construcción", False, 1600.0),
    ("Arena", "Construcción", False, 1500.0),
    ("Cemento a granel", "Construcción", False, 1300.0),
    ("Cal viva", "Construcción", False, 900.0),
    ("Clinker", "Construcción", False, 1450.0),
    ("Añaguanos plegable", "Agroinsumos", False, 0.0),
    ("Fertilizante granulado", "Agroinsumos", False, 1100.0),
    ("Semilla certificada", "Agroinsumos", False, 700.0),
    ("Plástico agrícola", "Agroinsumos", False, 950.0),
]
ALMACENES_BASE = ["Plataforma 1", "Plataforma 2", "Silo A", "Silo B", "Silo C"]
TRANSPORTES_BASE = ["Transporte Rapidez", "Cargas del Oriente", "Fletes Miranda"]
APELLIDOS = ["Pérez", "González", "Rodríguez", "Martínez", "López", "Hernández",
             "García", "Sánchez", "Ramírez", "Torres", "Flores", "Rivas"]
NOMBRES = ["José", "Luis", "Carlos", "Miguel", "Jesús", "Rafael", "Pedro",
           "Antonio", "Héctor", "Óscar", "Daniel", "Iván"]


def q(msg: str = "") -> None:
    print(msg, flush=True)


def url_admin() -> str:
    """URL asyncpg de la BD de trabajo, deducida de `DATABASE_URL`."""
    base = os.getenv("VOLUMEN_DATABASE_URL") or os.getenv("DATABASE_URL") or ""
    if not base:
        raise SystemExit("Falta DATABASE_URL (o VOLUMEN_DATABASE_URL) en el entorno.")
    # asyncpg no entiende el dialecto SQLAlchemy (`postgresql+asyncpg://`).
    return base.replace("postgresql+asyncpg://", "postgresql://").replace(
        "postgresql+psycopg2://", "postgresql://")


def url_volumen() -> str:
    """Sustituye el nombre de la BD por `balansoft_ws_volumen`."""
    base = url_admin()
    return base.rsplit("/", 1)[0] + "/" + NOMBRE_BD


async def crear_o_borrar_bd() -> None:
    """Crea la BD desde el esquema canónico (o la borra)."""
    import asyncpg

    dsn_admin = url_admin()
    dsn_volumen = url_volumen()
    # `postgres` es la BD de mantenimiento donde se crea/destruye.
    dsn_mantenimiento = dsn_admin.rsplit("/", 1)[0] + "/postgres"

    conexion = await asyncpg.connect(dsn_mantenimiento)
    try:
        await conexion.execute(f'DROP DATABASE IF EXISTS "{NOMBRE_BD}" WITH (FORCE)')
        q(f"→ BD eliminada: {NOMBRE_BD}")
        await conexion.execute(f'CREATE DATABASE "{NOMBRE_BD}"')
    finally:
        await conexion.close()
    q(f"→ BD creada: {NOMBRE_BD}")

    conexion = await asyncpg.connect(dsn_volumen)
    try:
        await conexion.execute(ESQUEMA.read_text(encoding="utf-8"))
        # El esquema canónico no trae `series_numeracion` (migración 015) ni
        # otras tablas añadidas después; sin ellas el volumen no es representativo.
        for archivo in sorted(MIGRACIONES.glob("*.sql")):
            await conexion.execute(archivo.read_text(encoding="utf-8"))
        q(f"→ Esquema aplicado: {ESQUEMA.name} + {len(list(MIGRACIONES.glob('*.sql')))} migraciones")
    finally:
        await conexion.close()


def proximo_utc() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None, microsecond=0)


async def main() -> None:
    parser = argparse.ArgumentParser(description="Semilla de volumen P2 (~50k boletos)")
    parser.add_argument("--crear-bd", action="store_true",
                        help="Recrea balansoft_ws_volumen desde el esquema canónico")
    parser.add_argument("--drop-bd", action="store_true",
                        help="Solo borra la BD de volumen y sale")
    parser.add_argument("--boletos", type=int, default=BOLETOS)
    args = parser.parse_args()
    cargar_env()

    if args.drop_bd:
        await crear_o_borrar_bd()
        return
    if args.crear_bd:
        await crear_o_borrar_bd()

    # La URL debe apuntar a la BD de volumen para todo lo demás.
    os.environ["DATABASE_URL"] = url_volumen().replace("postgresql://", "postgresql+asyncpg://")
    sys.path.insert(0, str(BACKEND_DIR))

    from sqlalchemy import func, select, text  # noqa: PLC0415
    from sqlalchemy.ext.asyncio import create_async_engine  # noqa: PLC0415

    from app.core.security import hash_password  # noqa: PLC0415
    from app.models import (  # noqa: PLC0415
        Almacen,
        Balanza,
        BoletoPesaje,
        Camion,
        Categoria,
        Conductor,
        Empresa,
        Kardex,
        Producto,
        SerieNumeracion,
        Transporte,
        Usuario,
    )

    rnd = random.Random(20261002)  # semilla fija: el volumen es reproducible
    motor = create_async_engine(os.environ["DATABASE_URL"], pool_size=5, max_overflow=5)
    inicio = proximo_utc()
    fecha_inicio = inicio - timedelta(days=MESES * 30)
    ventana_s = (inicio - fecha_inicio).total_seconds()

    async with motor.begin() as conn:
        await conn.execute(text("SET synchronous_commit = off"))

    q(f"→ Empresa, usuario y catálogos ({PRODUCTOS} productos, "
      f"{PRODUCTOS_KARDEX} con kardex, {ALMACENES} almacenes)")

    async with AsyncSessionLocal_from(motor) as db:
        empresa = (await db.execute(select(Empresa))).scalars().first()
        if empresa is None:
            empresa = Empresa(
                nombre_fiscal=EMPRESA_NOMBRE, nombre_comercial=EMPRESA_NOMBRE,
                rif_nit=EMPRESA_RIF, activa=True, licencia_status="ACTIVE",
                licencia_tier="CENTRAL", idioma="es",
            )
            db.add(empresa)
            await db.flush()
        empresa_id = empresa.id_empresa

        db.add(Usuario(
            id_empresa=empresa_id, nombre="Administrador Volumen",
            email=USUARIO_EMAIL, password_hash=hash_password(USUARIO_PASS),
            rol="ADMIN", activo=True,
        ))

        categoria = Categoria(id_empresa=empresa_id, codigo="GRANEL",
                              nombre="Granel", activo=True)
        db.add(categoria)
        await db.flush()

        # ---- Productos: 20 con kardex, 80 sin kardex ----------------------
        productos: list[Producto] = []
        for i in range(PRODUCTOS):
            with_kardex = i < PRODUCTOS_KARDEX
            base = PRODUCTOS_BASE[i % len(PRODUCTOS_BASE)] if with_kardex \
                else PRODUCTOS_SIN_KARDEX[i % len(PRODUCTOS_SIN_KARDEX)]
            nombre, _cat, kardex, densidad = base
            sufijo = "" if i < len(PRODUCTOS_BASE) else f" {i // len(PRODUCTOS_BASE) + 1}"
            p = Producto(
                id_empresa=empresa_id, id_categoria=categoria.id_categoria,
                codigo=f"P{i + 1:04d}", nombre=f"{nombre}{sufijo}",
                unidad_medida="TON", es_kardex=with_kardex,
                densidad_estandar=Decimal(str(densidad)) if densidad else None,
                peso_unidad=Decimal("1000") if densidad else None,
                activo=True,
            )
            db.add(p)
            productos.append(p)
        await db.flush()

        # ---- Almacenes, camiones, conductores, transportes, balanzas ------
        almacenes = []
        for i in range(ALMACENES):
            nombre = ALMACENES_BASE[i % len(ALMACENES_BASE)] + \
                ("" if i < len(ALMACENES_BASE) else f" {i // len(ALMACENES_BASE) + 1}")
            a = Almacen(id_empresa=empresa_id, codigo=f"A{i + 1:03d}", nombre=nombre,
                        capacidad_max_ton=Decimal("50000"),
                        stock_actual_ton=Decimal("0"), activo=True)
            db.add(a)
            almacenes.append(a)
        await db.flush()

        transportes = []
        for i in range(TRANSPORTES):
            base = TRANSPORTES_BASE[i % len(TRANSPORTES_BASE)]
            t = Transporte(id_empresa=empresa_id, codigo=f"T{i + 1:03d}",
                           razon_social=f"{base} {i + 1}", activo=True)
            db.add(t)
            transportes.append(t)
        await db.flush()

        camiones = []
        for i in range(CAMIONES):
            c = Camion(id_empresa=empresa_id, placa=f"AB{i + 1:03d}CD",
                       transporte_id=transportes[i % TRANSPORTES].id_transporte,
                       color="Blanco", tara_habitual=Decimal(str(rnd.randint(6, 14))),
                       activo=True)
            db.add(c)
            camiones.append(c)

        conductores = []
        for i in range(CONDUCTORES):
            d = Conductor(id_empresa=empresa_id, cedula_dni=f"V{i + 1:08d}",
                          nombre_completo=f"{rnd.choice(NOMBRES)} {rnd.choice(APELLIDOS)} "
                                          f"{rnd.choice(APELLIDOS)}",
                          licencia_conducir="A", activo=True)
            db.add(d)
            conductores.append(d)

        for i in range(BALANZAS):
            db.add(Balanza(id_empresa=empresa_id, codigo=f"BAL{i + 1:02d}",
                           descripcion=f"Báscula {i + 1}", marca="Toledo",
                           modelo="IND570", capacidad_max=Decimal("60000"),
                           division=Decimal("10"), activo=True, is_simulada=True,
                           protocolo="TCP", puerto_tcp=8000 + i))
        await db.commit()

        catalogo = {
            "productos": productos, "almacenes": almacenes, "camiones": camiones,
            "conductores": conductores, "transportes": transportes,
        }
        q(f"   productos={len(productos)} (kardex={PRODUCTOS_KARDEX}) "
          f"almacenes={len(almacenes)} camiones={len(camiones)} "
          f"conductores={len(conductores)} transportes={len(transportes)} balanzas={BALANZAS}")

        # ---- Series de numeración (contadores altos, coherentes) ---------
        q(f"→ {SERIES} series de numeración")
        series = []
        for i in range(SERIES):
            s = SerieNumeracion(
                id_empresa=empresa_id, nombre=f"Serie {i + 1}",
                prefijo=f"V{i + 1}-", inicio=1, siguiente=1, digitos=8,
                activa=(i == 0),
            )
            db.add(s)
            series.append(s)
        await db.commit()

    # ------------------------------------------------------------------
    # Boletos
    # ------------------------------------------------------------------
    q(f"→ Generando {args.boletos} boletos en lotes de {LOTE} "
      f"({MESES} meses, distribución {DISTRIBUCION})")
    counters = {s.nombre: s.siguiente for s in series}
    estados = list(DISTRIBUCION)
    pesos = [0.70, 0.20, 0.05, 0.05]
    emitidos = 0
    kardex_total = 0

    async with AsyncSessionLocal_from(motor) as db:
        lote: list[dict] = []
        for n in range(args.boletos):
            estado = rnd.choices(estados, pesos)[0]
            serie = series[n % SERIES]
            numero = f"{serie.prefijo}{counters[serie.nombre]:08d}"
            counters[serie.nombre] += 1

            f_entrada = fecha_inicio + timedelta(
                seconds=rnd.uniform(0, ventana_s))
            tara = Decimal(str(rnd.randint(6000, 14000)))          # kg
            bruto_entrada = tara + Decimal(str(rnd.randint(8000, 42000)))
            producto = rnd.choice(catalogo["productos"])
            camion = rnd.choice(catalogo["camiones"])

            fila: dict = {
                "boleto": uuid.uuid4(),
                "numero_boleto": numero,
                "id_empresa": empresa_id,
                "id_vehiculo": camion.placa,
                "id_transporte": camion.transporte_id,
                "id_conductor": rnd.choice(catalogo["conductores"]).cedula_dni,
                "id_producto": producto.id_producto,
                "id_almacen": rnd.choice(catalogo["almacenes"]).id_almacen,
                "id_balanza": None,
                "tipo_tercero": "CLIENTE",
                "id_tercero": None,
                "documento": f"DOC-{n + 1:07d}",
                "medida": "TON",
                "peso_entrada_vehiculo": bruto_entrada,
                "peso_entrada_remolque": Decimal("0"),
                "fecha_hora_entrada": f_entrada,
                "estado_boleto": estado,
                "es_peso_manual": False,
                "sincronizado": True,
                "created_at": f_entrada,
                "updated_at": f_entrada,
                "peso_bruto": bruto_entrada,
                "peso_tara": tara,
                "_producto_kardex": producto.es_kardex,
            }

            if estado == "PENDIENTE":
                # Sin salida: el peso neto aún no existe.
                fila["peso_total_entrada"] = bruto_entrada
            else:
                # Cierre: salida horas después, salida <= entrada total.
                f_salida = f_entrada + timedelta(minutes=rnd.randint(20, 600))
                bruto_salida = bruto_entrada - Decimal(str(rnd.randint(200, 4000)))
                if bruto_salida < tara:
                    bruto_salida = tara + Decimal("500")
                neto = bruto_salida - tara
                fila.update({
                    "fecha_hora_salida": f_salida,
                    "peso_salida_vehiculo": bruto_salida,
                    "peso_salida_remolque": Decimal("0"),
                    "peso_total_salida": bruto_salida,
                    "peso_neto": neto,
                    "peso_bruto": bruto_salida,
                    "salida_por": USUARIO_EMAIL,
                    "updated_at": f_salida,
                })
                if producto.densidad_estandar:
                    densidad = Decimal("1")
                    fila.update({
                        "densidad": densidad,
                        "litros": round(neto / densidad, 2),
                        "unidades": round(neto / Decimal("1000"), 3),
                    })
                if estado == "MODIFICADO":
                    fila["modificado_por"] = USUARIO_EMAIL
                elif estado == "ANULADO":
                    fila["anulado_por"] = USUARIO_EMAIL
                    fila["motivo_anulacion"] = rnd.choice(
                        ["Error de producto", "Documento anulado por el cliente",
                         "Pesaje duplicado", "Retorno por calidad"])
            lote.append(fila)

            if len(lote) >= LOTE:
                emitidos += await insertar_lote(db, lote, kardex_total)
                kardex_total = await db.scalar(select(func.count()).select_from(Kardex))
                q(f"   … {emitidos} boletos, kardex={kardex_total}")
                lote = []

        if lote:
            emitidos += await insertar_lote(db, lote, kardex_total)
            kardex_total = await db.scalar(select(func.count()).select_from(Kardex))
        await db.commit()

    # ------------------------------------------------------------------
    # Reporte
    # ------------------------------------------------------------------
    q("\n=== Resumen del volumen ===")
    async with AsyncSessionLocal_from(motor) as db:
        total = await db.scalar(select(func.count()).select_from(BoletoPesaje))
        q(f"Boletos          : {total}")
        for est, _ in DISTRIBUCION.items():
            c = await db.scalar(
                select(func.count()).select_from(BoletoPesaje)
                .where(BoletoPesaje.estado_boleto == est))
            q(f"  {est:<14}: {c}")
        km = await db.scalar(select(func.count()).select_from(Kardex))
        q(f"Kardex           : {km}")
        filas_por_mov = await db.execute(
            select(Kardex.id_movimiento, func.count())
            .group_by(Kardex.id_movimiento).order_by(Kardex.id_movimiento))
        q("  " + "  ".join(f"ID{m}={c}" for m, c in filas_por_mov))
        ant = await db.scalar(
            select(func.count()).select_from(BoletoPesaje)
            .where(BoletoPesaje.estado_boleto == "ANULADO"))
        q(f"ANULADOS         : {ant}")
    q(f"\n✔ Volumen listo. BD: {url_volumen().rsplit('/', 1)[-1]}")


async def insertar_lote(db, lote: list[dict], _kardex_antes) -> int:
    """Inserta un lote de boletos y su kardex coherente (dos `executemany`)."""
    from sqlalchemy import insert  # noqa: PLC0415

    from app.models import BoletoPesaje, Kardex  # noqa: PLC0415

    boletos: list[dict] = []
    movimientos: list[dict] = []
    for fila in lote:
        kardex_flag = fila.pop("_producto_kardex")
        boletos.append(fila)

        if not kardex_flag or fila["estado_boleto"] == "PENDIENTE":
            continue
        neto = fila.get("peso_neto")
        if neto is None:
            continue
        # Regla del servicio: neto >= 0 → INGRESO (10); neto < 0 → DESPACHO (60).
        es_ingreso = neto >= 0
        base = {
            "id_kardex": uuid.uuid4(),
            "id_empresa": fila["id_empresa"],
            "id_movimiento": 10 if es_ingreso else 60,
            "fecha_kardex": fila.get("fecha_hora_salida") or fila["fecha_hora_entrada"],
            "id_producto": fila["id_producto"],
            "id_almacen": fila["id_almacen"],
            "fecha_documento": fila.get("fecha_hora_salida"),
            "documento": fila["documento"],
            "valor": abs(neto),
            "boleto": fila["boleto"],
            "created_at": fila["updated_at"],
        }
        movimientos.append(base)
        if fila["estado_boleto"] == "ANULADO":
            # Anulación de un CERRADO → movimiento inverso; la historia se conserva.
            inverso = dict(base)
            inverso["id_kardex"] = uuid.uuid4()
            inverso["id_movimiento"] = 60 if es_ingreso else 10
            movimientos.append(inverso)

    # Boletos primero: `kardex.boleto` es FK a `boletos_pesaje(boleto)`.
    await db.execute(insert(BoletoPesaje), boletos)
    if movimientos:
        await db.execute(insert(Kardex), movimientos)
    await db.commit()
    return len(lote)


def AsyncSessionLocal_from(motor):  # noqa: N802
    """Sessionmaker async sobre un motor concreto."""
    from sqlalchemy.ext.asyncio import AsyncSession  # noqa: PLC0415

    return AsyncSession(motor, expire_on_commit=False)


if __name__ == "__main__":
    asyncio.run(main())