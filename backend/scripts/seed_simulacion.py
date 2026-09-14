#!/usr/bin/env python3
"""Seed de simulación realista para Balansoft-WS (Empresa Demo Balansoft).

Pobla la empresa demo (ca567509-3376-476b-afcc-a7e96612a37b) con:
  - Catálogos maestros realistas (camiones, remolques, transportes,
    conductores, productos, almacenes, balanzas, terceros, marcas/modelos).
  - Boletos de pesaje con ENTRADA y SALIDA completas en varios estados
    (CERRADO, PENDIENTE, ANULADO, MODIFICADO), con pesos netos/litros
    calculados según las reglas de negocio.
  - Tablas de configuración: `configuraciones` y `parametros_sistema`
    (incluida la configuración del modo de pesaje y de la báscula/puerto COM).

Uso:  uv run python scripts/seed_simulacion.py
"""

from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

from sqlalchemy import text

from app.core.database import AsyncSessionLocal
from app.models import (
    Almacen,
    Balanza,
    BoletoPesaje,
    Camion,
    Conductor,
    Empresa,
    Marca,
    ModeloCamion,
    Producto,
    Remolque,
    Tercero,
    Transporte,
    Usuario,
)

EMPRESA_DEMO_ID = "ca567509-3376-476b-afcc-a7e96612a37b"
Q2 = Decimal("0.01")


def _fmt(v: Decimal, dec: int = 2) -> Decimal:
    return v.quantize(Decimal(f"1.{'0' * dec}" if dec else "1"))


def _d(x) -> Decimal:
    return Decimal(str(x))


def _time(days_back: int, hour: int = 8, minute: int = 0) -> datetime:
    now = datetime.now(UTC).replace(tzinfo=None)
    return (now - timedelta(days=days_back)).replace(
        hour=hour, minute=minute, second=0, microsecond=0
    )


# ---------------------------------------------------------------------------
# Datos simulados
# ---------------------------------------------------------------------------

CAMIONES = [
    ("V-0012AB", "Blanco", "2500.00"),
    ("V-0034CD", "Rojo", "3200.00"),
    ("V-0056EF", "Azul", "2800.00"),
    ("V-0078GH", "Gris", "3100.00"),
]

REMOLQUES = [
    ("R-1001", "PLATAFORMA", "7500.00"),
    ("R-1002", "CISERNA", "6500.00"),
    ("R-1003", "VOLQUETE", "8000.00"),
]

TRANSPORTES = [
    ("T001", "Transportes El Sol", "J-20011122-3", "0414-1002001", "Luis Rojas"),
    ("T002", "Cargas del Centro", "J-30022334-5", "0416-3004506", "Pedro Gómez"),
    ("T003", "Logística Andina C.A.", "J-40033445-7", "0424-5006708", "Ana Torres"),
]

CONDUCTORES = [
    ("V-11223344", "Carlos Hernández"),
    ("V-99887766", "José Martínez"),
    ("V-55667788", "Luis Fernández"),
    ("V-22334455", "Miguel Salazar"),
]

PRODUCTOS = [
    ("CEM", "Cemento Tipo I", "Cemento gris tipo I", "3.1500", "TON", True, "2.0000"),
    ("ARN", "Arena Lavada", "Arena de río lavada", "1.6000", "TON", True, "3.0000"),
    ("CLL", "Clinker", "Clinker de cemento", "1.3000", "TON", True, "1.5000"),
    ("DIE", "Diesel", "Combustible diésel", "0.8500", "LTS", False, None),
    ("GAS", "Gasolina", "Combustible gasolina", "0.7200", "LTS", False, None),
]

ALMACENES = [
    ("A1", "Planta Principal", "Nave central", "15000.00", "8200.50"),
    ("A2", "Patio de Clinker", "Patio norte", "25000.00", "13450.75"),
    ("A3", "Tanque de Combustible", "Área de despacho", "50000.00", "22800.00"),
]

BALANZAS = [
    ("BALANZA1", "Balanza 1 - Entrada", "Digi", "SM300", "80000.00", "20.00"),
    ("BALANZA2", "Balanza 2 - Salida", "Toledo", "CM6000", "80000.00", "20.00"),
]

TERCEROS = [
    ("C001", "CLIENTE", "Constructora El Ávila", "J-10011123-1", "Av. Libertador"),
    ("C002", "CLIENTE", "Hormigones Nacionales", "J-20022334-2", "Zona Industrial Sur"),
    ("P001", "PROVEEDOR", "Arena y Piedra C.A.", "J-30033556-3", "Cantera Norte"),
    ("P002", "PROVEEDOR", "Ferretería Central", "J-40044778-9", "Centro Comercial"),
]

MARCAS = [
    ("MACK", "Mack Trucks"),
    ("MERCEDES", "Mercedes-Benz"),
    ("KENWORTH", "Kenworth"),
]

MODELOS = [
    ("MACK", "Granite", "40.00", 3),
    ("MERCEDES", "Actros 2645", "40.00", 3),
    ("KENWORTH", "T800", "38.00", 3),
]


def _boletos(parametros: dict) -> list[dict]:
    """Genera la lista de boletos de simulación."""
    camiones = parametros["camiones"]
    remolques = parametros["remolques"]
    transportes = parametros["transportes"]
    conductores = parametros["conductores"]
    productos = parametros["productos"]
    almacenes = parametros["almacenes"]
    balanzas = parametros["balanzas"]
    terceros = parametros["terceros"]

    # Cada boleto: (dias_atras, hora_entrada, hora_salida, camion_idx,
    #   remolque_idx|null, transporte_idx, conductor_idx, producto_idx,
    #   almacen_idx, balanza_ent_idx, balanza_sal_idx, tercero_idx,
    #   peso_entrada, peso_salida, documento, flete, costo_flete, observaciones,
    #   estado, motivo_anulacion|null)
    rows = [
        # CERRADOS completos (entrada y salida, neto calculado)
        (3, 7, 9, 0, None, 0, 0, 0, 0, 0, 1, 0,
         "45000.00", "39000.00", "G-001", "Flete centro", "1200.00",
         None, "CERRADO", None),
        (3, 10, 13, 1, 0, 1, 1, 1, 1, 0, 1, 1,
         "52000.00", "41500.00", "G-002", "Flete sur", "1500.00",
         "Cliente solicitó pesaje completo", "CERRADO", None),
        (2, 8, 11, 2, None, 2, 2, 2, 2, 0, 1, 2,
         "48000.00", "35600.00", "G-003", "Flete este", "1300.00",
         None, "CERRADO", None),
        (2, 14, 17, 3, 1, 0, 3, 3, 2, 0, 1, 3,
         "61000.00", "50500.00", "G-004", "Combustible", "2000.00",
         None, "CERRADO", None),
        (1, 9, 12, 0, 2, 1, 0, 4, 2, 0, 1, 0,
         "55000.00", "46200.00", "G-005", "Gasolina 95", "1800.00",
         "Guía despacho", "CERRADO", None),
        (1, 15, 18, 1, None, 2, 1, 1, 0, 0, 1, 1,
         "46000.00", "39800.00", "G-006", "Flete arena", "1100.00",
         None, "CERRADO", None),
        # MODIFICADO (cerrado y luego corregido)
        (0, 8, 10, 2, 0, 0, 2, 2, 1, 0, 1, 2,
         "50000.00", "42000.00", "G-007", "Flete ceniza", "1400.00",
         "Corrección de peso declarado", "MODIFICADO", None),
        # PENDIENTE (solo entrada, sin salida; vehículo en planta)
        (0, 16, None, 3, None, 1, 3, 1, 1, 1, None, 3,
         "53000.00", None, "G-008", None, None,
         None, "PENDIENTE", None),
        # ANULADO (con motivo)
        (4, 10, 12, 0, None, 2, 0, 3, 2, 0, 1, 0,
         "58000.00", "51500.00", "G-009", "Flete anulado", "1600.00",
         None, "ANULADO", "Vehículo presentó documentación incorrecta."),
    ]

    boletos = []
    for r in rows:
        (
            dias, h_e, h_si, ci, ri, ti, di, pi, ai, bei, bsi, tei,
            p_e, p_s, doc, fle, costo, obs, estado, motivo,
        ) = r
        vehiculo = camiones[ci]
        entrada = _time(dias, h_e)
        salida = _time(dias, h_si) if h_si is not None else None
        peso_ent_veh = _fmt(_d(p_e))
        peso_sal_veh = _fmt(_d(p_s)) if p_s else None
        peso_ent_rem = _fmt(_d(remolques[ri][2])) if ri is not None else None
        peso_sal_rem = _fmt(_d(remolques[ri][2])) if ri is not None and p_s else None
        pte = _fmt(peso_ent_veh + (peso_ent_rem or Decimal("0.00")))
        pts = _fmt(peso_sal_veh + (peso_sal_rem or Decimal("0.00"))) if peso_sal_veh is not None else None
        p_neto = _fmt(pte - pts) if pts is not None else None

        boleto = {
            "id_empresa": parametros["empresa_id"],
            "id_vehiculo": vehiculo[0],
            "remolque": ri is not None,
            "id_remolque": remolques[ri][3] if ri is not None else None,
            "id_transporte": transportes[ti][4],
            "id_conductor": conductores[di][2],
            "id_producto": productos[pi][6],
            "id_almacen": almacenes[ai][3],
            "id_balanza": balanzas[bei][4] if bei is not None else None,
            "tipo_tercero": "CLIENTE" if terceros[tei][1] == "CLIENTE" else "PROVEEDOR",
            "id_tercero": terceros[tei][4],
            "fecha_hora_entrada": entrada,
            "peso_entrada_vehiculo": peso_ent_veh,
            "peso_entrada_remolque": peso_ent_rem,
            "fecha_hora_salida": salida,
            "peso_salida_vehiculo": peso_sal_veh,
            "peso_salida_remolque": peso_sal_rem,
            "documento": doc,
            "flete": fle,
            "costo_flete": _fmt(_d(costo)) if costo else None,
            "observaciones": obs,
            "peso_total_entrada": pte,
            "peso_total_salida": pts,
            "peso_neto": p_neto,
            "peso_bruto": max(pte, pts) if pts else pte,
            "peso_tara": min(pte, pts) if pts else None,
            "densidad": productos[pi][7],
            "litros": _fmt(p_neto / productos[pi][7]) if p_neto is not None and productos[pi][7] else None,
            "estado_boleto": estado,
            "motivo_anulacion": motivo,
            "creado_por": "Administrador Demo",
            "salida_por": "Administrador Demo" if salida else None,
        }
        boletos.append(boleto)
    return boletos


async def main() -> None:
    async with AsyncSessionLocal() as db:
        empresa = await db.get(Empresa, uuid.UUID(EMPRESA_DEMO_ID))
        if empresa is None:
            print("❌ Empresa demo no encontrada. Ejecuta primero seed_data.py")
            return
        empresa_id = empresa.id_empresa

        # ---- Marcas y modelos ------------------------------------------
        marcas: list[str] = []
        for cod, nombre in MARCAS:
            marcas.append(await _get_or_create_marca(db, empresa_id, cod, nombre))
        await db.flush()

        # ---- Camiones ---------------------------------------------------
        camion_rows: list[list] = []
        for placa, color, tara in CAMIONES:
            camion_rows.append(
                await _get_or_create_camion(db, empresa_id, placa, color, _d(tara))
            )
        await db.flush()

        # ---- Remolques --------------------------------------------------
        remolque_rows: list[list] = []
        for placa, tipo, tara in REMOLQUES:
            remolque_rows.append(
                await _get_or_create_remolque(db, empresa_id, placa, tipo, _d(tara))
            )
        await db.flush()

        # ---- Transportes ------------------------------------------------
        transporte_rows: list[list] = []
        for cod, rs, rif, tel, contacto in TRANSPORTES:
            transporte_rows.append(
                await _get_or_create_transporte(db, empresa_id, cod, rs, rif, tel, contacto)
            )
        await db.flush()

        # ---- Conductores ------------------------------------------------
        conductor_rows: list[list] = []
        for ced, nombre in CONDUCTORES:
            conductor_rows.append(await _get_or_create_conductor(db, empresa_id, ced, nombre))
        await db.flush()

        # ---- Productos --------------------------------------------------
        producto_rows: list[list] = []
        for cod, nombre, desc, dens, um, kardex, tol in PRODUCTOS:
            producto_rows.append(
                await _get_or_create_producto(
                    db, empresa_id, cod, nombre, desc, _d(dens), um, kardex, _d(tol) if tol else None
                )
            )
        await db.flush()

        # ---- Almacenes ---------------------------------------------------
        almacen_rows: list[list] = []
        for cod, nombre, ubic, cap, stock in ALMACENES:
            almacen_rows.append(
                await _get_or_create_almacen(db, empresa_id, cod, nombre, ubic, _d(cap), _d(stock))
            )
        await db.flush()

        # ---- Balanzas ----------------------------------------------------
        balanza_rows: list[list] = []
        for cod, desc, marca, modelo, cap, div in BALANZAS:
            balanza_rows.append(
                await _get_or_create_balanza(db, empresa_id, cod, desc, marca, modelo, _d(cap), _d(div))
            )
        await db.flush()

        # ---- Terceros ----------------------------------------------------
        tercero_rows: list[list] = []
        for cod, tipo, rs, rif, dir_ in TERCEROS:
            tercero_rows.append(await _get_or_create_tercero(db, empresa_id, cod, tipo, rs, rif, dir_))
        await db.flush()

        # ---- Preparar parámetros y boletos --------------------------------
        parametros = {
            "empresa_id": empresa_id,
            "camiones": camion_rows,
            "remolques": remolque_rows,
            "transportes": transporte_rows,
            "conductores": conductor_rows,
            "productos": producto_rows,
            "almacenes": almacen_rows,
            "balanzas": balanza_rows,
            "terceros": tercero_rows,
        }

        # Numeración secuencial de boletos (no reutiliza dados existentes)
        boletos = _boletos(parametros)
        numero = await _siguiente_numero_boleto(db, empresa_id)

        for i, b in enumerate(boletos):
            existente = (
                await db.execute(
                    text(
                        "SELECT 1 FROM boletos_pesaje "
                        "WHERE id_empresa = :e AND id_vehiculo = :v "
                        "AND fecha_hora_entrada = :fh LIMIT 1"
                    ),
                    {
                        "e": str(empresa_id),
                        "v": b["id_vehiculo"],
                        "fh": b["fecha_hora_entrada"],
                    },
                )
            ).scalar_one_or_none()
            if existente:
                continue
            numero += 1
            await db.execute(
                text(
                    """
                    INSERT INTO boletos_pesaje (
                        boleto, numero_boleto, id_empresa, id_vehiculo, remolque,
                        id_remolque, id_transporte, id_conductor, id_producto,
                        id_almacen, id_balanza, tipo_tercero, id_tercero,
                        fecha_hora_entrada, peso_entrada_vehiculo, peso_entrada_remolque,
                        fecha_hora_salida, peso_salida_vehiculo, peso_salida_remolque,
                        documento, flete, costo_flete, observaciones,
                        peso_total_entrada, peso_total_salida, peso_neto,
                        peso_bruto, peso_tara, densidad, litros,
                        estado_boleto, motivo_anulacion, creado_por, salida_por,
                        sincronizado, sync_intentos, created_at, updated_at
                    ) VALUES (
                        :boleto, :numero_boleto, :id_empresa, :id_vehiculo, :remolque,
                        :id_remolque, :id_transporte, :id_conductor, :id_producto,
                        :id_almacen, :id_balanza, :tipo_tercero, :id_tercero,
                        :fh_e, :pe_veh, :pe_rem,
                        :fh_s, :ps_veh, :ps_rem,
                        :documento, :flete, :costo_flete, :observaciones,
                        :pte, :pts, :p_neto,
                        :peso_bruto, :peso_tara, :densidad, :litros,
                        :estado, :motivo, :creado_por, :salida_por,
                        :sinc, :sync_int, :created_at, :updated_at
                    )
                    """
                ),
                {
                    "boleto": str(uuid.uuid4()),
                    "numero_boleto": f"TA-{numero:08d}",
                    "id_empresa": str(empresa_id),
                    "id_vehiculo": b["id_vehiculo"],
                    "remolque": b["remolque"],
                    "id_remolque": str(b["id_remolque"]) if b["id_remolque"] else None,
                    "id_transporte": str(b["id_transporte"]),
                    "id_conductor": b["id_conductor"],
                    "id_producto": str(b["id_producto"]),
                    "id_almacen": str(b["id_almacen"]),
                    "id_balanza": str(b["id_balanza"]) if b["id_balanza"] else None,
                    "tipo_tercero": b["tipo_tercero"],
                    "id_tercero": str(b["id_tercero"]),
                    "fh_e": b["fecha_hora_entrada"],
                    "pe_veh": str(b["peso_entrada_vehiculo"]),
                    "pe_rem": str(b["peso_entrada_remolque"]) if b["peso_entrada_remolque"] else None,
                    "fh_s": b["fecha_hora_salida"],
                    "ps_veh": str(b["peso_salida_vehiculo"]) if b["peso_salida_vehiculo"] else None,
                    "ps_rem": str(b["peso_salida_remolque"]) if b["peso_salida_remolque"] else None,
                    "documento": b["documento"],
                    "flete": b["flete"],
                    "costo_flete": str(b["costo_flete"]) if b["costo_flete"] else None,
                    "observaciones": b["observaciones"],
                    "pte": str(b["peso_total_entrada"]),
                    "pts": str(b["peso_total_salida"]) if b["peso_total_salida"] else None,
                    "p_neto": str(b["peso_neto"]) if b["peso_neto"] else None,
                    "peso_bruto": str(b["peso_bruto"]) if b["peso_bruto"] else None,
                    "peso_tara": str(b["peso_tara"]) if b["peso_tara"] else None,
                    "densidad": str(b["densidad"]) if b["densidad"] else None,
                    "litros": str(b["litros"]) if b["litros"] else None,
                    "estado": b["estado_boleto"],
                    "motivo": b["motivo_anulacion"],
                    "creado_por": b["creado_por"],
                    "salida_por": b["salida_por"],
                    "sinc": True,
                    "sync_int": 0,
                    "created_at": b["fecha_hora_entrada"],
                    "updated_at": b["fecha_hora_salida"] or b["fecha_hora_entrada"],
                },
            )
        await db.commit()

        # ---- Configuración (tablas configuraciones/parametros_sistema) ----
        await _seed_parametros_sistema(db, empresa_id)
        await db.commit()

        print("✅ Simulación cargada en Empresa Demo Balansoft.")
        print(f"   Camiones      : {len(CAMIONES)}")
        print(f"   Remolques     : {len(REMOLQUES)}")
        print(f"   Transportes   : {len(TRANSPORTES)}")
        print(f"   Conductores   : {len(CONDUCTORES)}")
        print(f"   Productos     : {len(PRODUCTOS)}")
        print(f"   Almacenes     : {len(ALMACENES)}")
        print(f"   Balanzas      : {len(BALANZAS)}")
        print(f"   Terceros      : {len(TERCEROS)}")
        print(f"   Boletos       : {len(boletos)}")


async def _seed_parametros_sistema(db, empresa_id) -> None:
    """Llena `configuraciones` y `parametros_sistema` con la configuración del sistema."""
    cfg = [
        # Pesaje: modo separado entrada/salida + control de PENDIENTE único
        ("MODO_OPERACION_PESAJE", "ENTRADA_SALIDA_SEPARADOS",
         "Cada operación de pesaje (entrada y salida) se registra como boleto con su tipo de operación."),
        ("PREFIJO_BOLETO", "TA-", "Prefijo del número de boleto secuencial."),
        ("DIGITOS_BOLETO", "8", "Cantidad de dígitos del número de boleto."),
        ("BOLETO_UNICO_PENDIENTE", "true",
         "Un vehículo no puede tener dos boletos PENDIENTE a la vez."),
        ("PESO_MANUAL_PERMITIDO", "true",
         "Pesaje manual solo para SUPERVISOR y ADMIN."),
        # Báscula / puerto COM / balanza
        ("BAS_1_DESCRIPCION", "Balanza 1 - Entrada", "Balanzas disponibles"),
        ("BAS_1_PUERTO_COM", "COM3", "Puerto serie de la báscula 1."),
        ("BAS_1_BAUD_RATE", "9600", "Baud rate del puerto serie."),
        ("BAS_1_DATA_BITS", "8", "Bits de datos del protocolo."),
        ("BAS_1_PARITY", "NONE", "Paridad del protocolo serie."),
        ("BAS_1_STOP_BITS", "1", "Bits de parada."),
        ("BAS_1_IP_ADDRESS", "192.168.1.50", "IP de la báscula (modo red)."),
        ("BAS_1_PROTOCOLO", "SERIAL",
         "Protocolo de lectura: SERIAL (COM) o IP."),
        ("BAS_2_DESCRIPCION", "Balanza 2 - Salida", "Balanzas disponibles"),
        ("BAS_2_PUERTO_COM", "COM4", "Puerto serie de la báscula 2."),
        ("BAS_2_BAUD_RATE", "9600", "Baud rate del puerto serie."),
        ("BAS_2_PROTOCOLO", "SERIAL", "Protocolo de lectura: SERIAL (COM) o IP."),
    ]
    for clave, valor, desc in cfg:
        await db.execute(
            text(
                """
                INSERT INTO configuraciones (clave, valor, descripcion, id_empresa, updated_at)
                VALUES (:c, :v, :d, :e, now())
                ON CONFLICT (clave) DO UPDATE
                  SET valor = EXCLUDED.valor, descripcion = EXCLUDED.descripcion, updated_at = now()
                """
            ),
            {"c": clave, "v": valor, "d": desc, "e": str(empresa_id)},
        )

    parametros = [
        ("prefijo_boleto", "TA-", "pesaje", "Prefijo del número de boleto."),
        ("digitos_boleto", "8", "pesaje", "Dígitos del número de boleto."),
        ("modo_pesaje", "ENTRADA_SALIDA_SEPARADOS", "pesaje",
         "Modo de operación: separar entrada y salida en boletos distintos."),
        ("peso_manual_supervisor", "true", "pesaje",
         "Habilita pesaje manual para SUPERVISOR/ADMIN."),
        ("puerto_com_bascula", "COM3", "bascula", "Puerto serie de la báscula."),
        ("baud_rate_bascula", "9600", "bascula", "Baud rate."),
        ("ip_bascula", "192.168.1.50", "bascula", "Dirección IP de la báscula."),
        ("protocolo_bascula", "SERIAL", "bascula", "Protocolo serial o IP."),
        ("intervalo_sync_min", "2", "sync", "Intervalo de sincronización (min)."),
        ("max_offline_dias", "30", "sync", "Máximo de días offline permitidos."),
    ]
    for parametro, valor, grupo, desc in parametros:
        await db.execute(
            text(
                """
                INSERT INTO parametros_sistema (parametro, valor, grupo, descripcion, updated_at)
                VALUES (:p, :v, :g, :d, now())
                ON CONFLICT (parametro) DO UPDATE
                  SET valor = EXCLUDED.valor, grupo = EXCLUDED.grupo,
                      descripcion = EXCLUDED.descripcion, updated_at = now()
                """
            ),
            {"p": parametro, "v": valor, "g": grupo, "d": desc},
        )


async def _siguiente_numero_boleto(db, empresa_id) -> int:
    maximo = (
        await db.execute(
            text(
                "SELECT COALESCE(MAX(CAST(SUBSTRING(numero_boleto FROM '-(\\d+)$') AS INTEGER)), 0) "
                "FROM boletos_pesaje WHERE id_empresa = :e"
            ),
            {"e": str(empresa_id)},
        )
    ).scalar() or 0
    return int(maximo)


async def _get_or_create_marca(db, empresa_id, codigo, nombre) -> str:
    res = await db.execute(
        text("SELECT id_marca FROM marcas WHERE id_empresa = :e AND UPPER(nombre) = UPPER(:n) LIMIT 1"),
        {"e": str(empresa_id), "n": nombre},
    )
    row = res.scalar_one_or_none()
    if row:
        return row
    id_marca = uuid.uuid4()
    await db.execute(
        text("INSERT INTO marcas (id_marca, id_empresa, nombre) VALUES (:id, :e, :n)"),
        {"id": str(id_marca), "e": str(empresa_id), "n": nombre},
    )
    return str(id_marca)


async def _get_or_create_camion(db, empresa_id, placa, color, tara) -> list:
    res = await db.execute(
        text("SELECT id FROM camiones WHERE id_empresa = :e AND UPPER(placa) = UPPER(:p) LIMIT 1"),
        {"e": str(empresa_id), "p": placa},
    )
    row = res.scalar_one_or_none()
    if row:
        return [placa, row]
    id = uuid.uuid4()
    await db.execute(
        text(
            "INSERT INTO camiones (id, id_empresa, placa, color, tara_habitual, activo) "
            "VALUES (:id, :e, :p, :c, :t, true)"
        ),
        {"id": str(id), "e": str(empresa_id), "p": placa, "c": color, "t": str(tara)},
    )
    return [placa, str(id)]


async def _get_or_create_remolque(db, empresa_id, placa, tipo, tara) -> list:
    res = await db.execute(
        text("SELECT id_remolque FROM remolques WHERE id_empresa = :e AND UPPER(placa) = UPPER(:p) LIMIT 1"),
        {"e": str(empresa_id), "p": placa},
    )
    row = res.scalar_one_or_none()
    if row:
        return [placa, tipo, tara, row]
    id = uuid.uuid4()
    await db.execute(
        text(
            "INSERT INTO remolques (id_remolque, id_empresa, placa, tipo_remolque, tara_habitual, activo) "
            "VALUES (:id, :e, :p, :t, :ta, true)"
        ),
        {"id": str(id), "e": str(empresa_id), "p": placa, "t": tipo, "ta": str(tara)},
    )
    return [placa, tipo, tara, str(id)]


async def _get_or_create_transporte(db, empresa_id, codigo, rs, rif, tel, contacto) -> list:
    res = await db.execute(
        text(
            "SELECT id_transporte FROM transportes "
            "WHERE id_empresa = :e AND UPPER(razon_social) = UPPER(:rs) LIMIT 1"
        ),
        {"e": str(empresa_id), "rs": rs},
    )
    row = res.scalar_one_or_none()
    if row:
        return [codigo, rs, rif, tel, row]
    id = uuid.uuid4()
    await db.execute(
        text(
            "INSERT INTO transportes (id_transporte, id_empresa, codigo, razon_social, "
            "identificacion_fiscal, telefono, contacto, activo) "
            "VALUES (:id, :e, :c, :rs, :rif, :tel, :ct, true)"
        ),
        {"id": str(id), "e": str(empresa_id), "c": codigo, "rs": rs,
         "rif": rif, "tel": tel, "ct": contacto},
    )
    return [codigo, rs, rif, tel, str(id)]


async def _get_or_create_conductor(db, empresa_id, cedula, nombre) -> list:
    res = await db.execute(
        text("SELECT cedula_dni FROM conductores WHERE cedula_dni = :c LIMIT 1"),
        {"c": cedula},
    )
    row = res.scalar_one_or_none()
    if row:
        return [cedula, nombre, row]
    await db.execute(
        text(
            "INSERT INTO conductores (cedula_dni, id_empresa, nombre_completo, activo) "
            "VALUES (:c, :e, :n, true)"
        ),
        {"c": cedula, "e": str(empresa_id), "n": nombre},
    )
    return [cedula, nombre, cedula]


async def _get_or_create_producto(db, empresa_id, codigo, nombre, desc, dens, um, kardex, tol) -> list:
    res = await db.execute(
        text("SELECT id_producto FROM productos WHERE id_empresa = :e AND UPPER(nombre) = UPPER(:n) LIMIT 1"),
        {"e": str(empresa_id), "n": nombre},
    )
    row = res.scalar_one_or_none()
    if row:
        return [codigo, nombre, desc, dens, um, kardex, row, dens]
    id = uuid.uuid4()
    await db.execute(
        text(
            "INSERT INTO productos (id_producto, id_empresa, codigo, nombre, descripcion, "
            "densidad_estandar, unidad_medida, es_kardex, tolerancia, activo) "
            "VALUES (:id, :e, :c, :n, :d, :de, :um, :k, :t, true)"
        ),
        {"id": str(id), "e": str(empresa_id), "c": codigo, "n": nombre, "d": desc,
         "de": str(dens), "um": um, "k": kardex, "t": str(tol) if tol else None},
    )
    return [codigo, nombre, desc, dens, um, kardex, str(id), dens]


async def _get_or_create_almacen(db, empresa_id, codigo, nombre, ubic, cap, stock) -> list:
    res = await db.execute(
        text("SELECT id_almacen FROM almacenes WHERE id_empresa = :e AND UPPER(nombre) = UPPER(:n) LIMIT 1"),
        {"e": str(empresa_id), "n": nombre},
    )
    row = res.scalar_one_or_none()
    if row:
        return [codigo, nombre, ubic, row]
    id = uuid.uuid4()
    await db.execute(
        text(
            "INSERT INTO almacenes (id_almacen, id_empresa, codigo, nombre, ubicacion, "
            "capacidad_max_ton, stock_actual_ton, activo) "
            "VALUES (:id, :e, :c, :n, :u, :cap, :stock, true)"
        ),
        {"id": str(id), "e": str(empresa_id), "c": codigo, "n": nombre, "u": ubic,
         "cap": str(cap), "stock": str(stock)},
    )
    return [codigo, nombre, ubic, str(id)]


async def _get_or_create_balanza(db, empresa_id, codigo, desc, marca, modelo, cap, div) -> list:
    res = await db.execute(
        text("SELECT id_balanza FROM balanzas WHERE id_empresa = :e AND UPPER(descripcion) = UPPER(:d) LIMIT 1"),
        {"e": str(empresa_id), "d": desc},
    )
    row = res.scalar_one_or_none()
    if row:
        return [codigo, desc, marca, modelo, row]
    id = uuid.uuid4()
    await db.execute(
        text(
            "INSERT INTO balanzas (id_balanza, id_empresa, codigo, descripcion, marca, modelo, "
            "capacidad_max, division, activo) "
            "VALUES (:id, :e, :c, :d, :m, :mo, :cap, :div, true)"
        ),
        {"id": str(id), "e": str(empresa_id), "c": codigo, "d": desc, "m": marca,
         "mo": modelo, "cap": str(cap), "div": str(div)},
    )
    return [codigo, desc, marca, modelo, str(id)]


async def _get_or_create_tercero(db, empresa_id, codigo, tipo, rs, rif, direccion) -> list:
    res = await db.execute(
        text(
            "SELECT id_tercero FROM terceros "
            "WHERE id_empresa = :e AND UPPER(razon_social) = UPPER(:rs) LIMIT 1"
        ),
        {"e": str(empresa_id), "rs": rs},
    )
    row = res.scalar_one_or_none()
    if row:
        return [codigo, tipo, rs, rif, row]
    id = uuid.uuid4()
    await db.execute(
        text(
            "INSERT INTO terceros (id_tercero, id_empresa, codigo, tipo, razon_social, "
            "identificacion_fiscal, direccion, activo) "
            "VALUES (:id, :e, :c, :t, :rs, :rif, :dir, true)"
        ),
        {"id": str(id), "e": str(empresa_id), "c": codigo, "t": tipo, "rs": rs,
         "rif": rif, "dir": direccion},
    )
    return [codigo, tipo, rs, rif, str(id)]


if __name__ == "__main__":
    asyncio.run(main())
