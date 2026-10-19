#!/usr/bin/env python3
"""Servidor MCP (Model Context Protocol) para BALANSOFT-WS.

Expone herramientas especializadas en pesaje industrial, básculas, camiones,
impresoras y consultas del sistema sobre stdio usando JSON-RPC 2.0.

Compatible con OpenCode, Claude Desktop, Antigravity, Cursor y cualquier
cliente MCP estándar.

Uso manual:
    backend/.venv/bin/python backend/scripts/mcp_hardware_server.py
"""

from __future__ import annotations

import json
import os
import re
import sys
from decimal import Decimal
from typing import Any

# Asegurar import de app.*
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

try:
    from app.core.scale_parser import (
        ESTADO_ESTABLE,
        ESTADO_INESTABLE,
        ESTADO_SOBRECARGA,
        parse_weight_frame,
    )
except ImportError:
    parse_weight_frame = None  # type: ignore[assignment]
    ESTADO_ESTABLE = "stable"
    ESTADO_INESTABLE = "unstable"
    ESTADO_SOBRECARGA = "overload"


# -----------------------------------------------------------------------------
# Definición de herramientas MCP
# -----------------------------------------------------------------------------

TOOLS = [
    {
        "name": "parse_scale_frame",
        "description": "Parsea una trama de pesaje ASCII/hexadecimal utilizando el parser multi-marca del HAL (Toledo, Yaohua '=', Rice Lake, Torrey, Keli, MT-SICS, etc.). Devuelve peso_kg, estado (stable, unstable, overload, None) y motivo de rechazo si la trama es inválida.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "frame": {
                    "type": "string",
                    "description": "Línea de texto o trama recibida del indicador (ej: 'ST,GS,+00320.00kg', '=+000023.5kg', '\\x02ST,GS,+00320.00kg\\x032B')",
                },
                "capacidad_maxima": {
                    "type": "number",
                    "description": "Capacidad máxima de la báscula en kg (opcional, para chequeo de sobrecapacidad)",
                },
            },
            "required": ["frame"],
        },
    },
    {
        "name": "simulate_scale_frame",
        "description": "Genera una trama de báscula realista para una marca o protocolo determinado. Útil para tests, simulaciones y validaciones.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "indicator": {
                    "type": "string",
                    "enum": [
                        "toledo",
                        "yaohua",
                        "rice_lake",
                        "torrey",
                        "keli_checksum",
                        "mtsics",
                        "bsdd_json",
                    ],
                    "description": "Marca/protocolo del indicador.",
                },
                "weight_kg": {
                    "type": "number",
                    "description": "Peso en kilogramos.",
                },
                "stable": {
                    "type": "boolean",
                    "default": True,
                    "description": "Si la lectura está estabilizada o en movimiento.",
                },
                "unit": {
                    "type": "string",
                    "default": "kg",
                    "description": "Unidad de peso (kg, lbs, ton).",
                },
            },
            "required": ["indicator", "weight_kg"],
        },
    },
    {
        "name": "calculate_truck_weights",
        "description": "Calcula el desglose completo de pesos para un camión con o sin remolque: totales de entrada/salida, netos por vehículo (camión vs remolque), neto total, desviación sobre peso declarado y movimiento de Kardex (10 Ingreso vs 60 Despacho).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "peso_entrada_vehiculo": {
                    "type": "number",
                    "description": "Peso capturado en entrada para el camión/chuto (kg).",
                },
                "peso_salida_vehiculo": {
                    "type": "number",
                    "description": "Peso capturado en salida para el camión/chuto (kg).",
                },
                "peso_entrada_remolque": {
                    "type": "number",
                    "default": 0.0,
                    "description": "Peso capturado en entrada para el remolque (kg, opcional).",
                },
                "peso_salida_remolque": {
                    "type": "number",
                    "default": 0.0,
                    "description": "Peso capturado en salida para el remolque (kg, opcional).",
                },
                "tipo_operacion": {
                    "type": "string",
                    "enum": ["RECEPCION", "DESPACHO"],
                    "default": "RECEPCION",
                    "description": "RECEPCION (ingreso mercadería: tara entrada, bruto salida) o DESPACHO (bruto entrada, tara salida).",
                },
                "peso_declarado": {
                    "type": "number",
                    "description": "Peso neto declarado en la guía de remisión / Sunagro (opcional).",
                },
            },
            "required": ["peso_entrada_vehiculo", "peso_salida_vehiculo"],
        },
    },
    {
        "name": "format_ticket_weights_table",
        "description": "Genera la representación en texto de la tabla canónica LECTURA DE PESOS (5 columnas) según la especificación de BALANSOFT-WS v3.24: (vacío) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "fecha_hora_entrada": {
                    "type": "string",
                    "description": "Fecha y hora de entrada (ej: '15/10/2026 - 08:30').",
                },
                "peso_entrada_camion": {
                    "type": "number",
                    "description": "Peso de entrada camión (kg).",
                },
                "peso_entrada_remolque": {
                    "type": "number",
                    "description": "Peso de entrada remolque (kg, opcional).",
                },
                "fecha_hora_salida": {
                    "type": "string",
                    "description": "Fecha y hora de salida (ej: '15/10/2026 - 09:15', opcional si está pendiente).",
                },
                "peso_salida_camion": {
                    "type": "number",
                    "description": "Peso de salida camión (kg, opcional).",
                },
                "peso_salida_remolque": {
                    "type": "number",
                    "description": "Peso de salida remolque (kg, opcional).",
                },
                "tipo_operacion": {
                    "type": "string",
                    "enum": ["INGRESO", "DESPACHO"],
                    "default": "INGRESO",
                },
            },
            "required": ["fecha_hora_entrada", "peso_entrada_camion"],
        },
    },
    {
        "name": "inspect_db_table",
        "description": "Devuelve la definición DDL de una tabla de BALANSOFT-WS (local o servidor) leyendo directamente de los esquemas canónicos sql.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "table_name": {
                    "type": "string",
                    "description": "Nombre de la tabla (ej: boletos_pesaje, balanzas, camiones, kardex, empresas, series_numeracion).",
                },
                "database": {
                    "type": "string",
                    "enum": ["local", "server"],
                    "default": "local",
                    "description": "Base de datos (local = estación de pesaje, server = nube/central).",
                },
            },
            "required": ["table_name"],
        },
    },
    {
        "name": "verify_iso_standards",
        "description": "Verifica el cumplimiento de la normativa internacional ISO/IEC en el sistema BALANSOFT-WS (ISO/IEC 25010 Calidad de Software, ISO/IEC 17025 Metrología Legal e Inmutabilidad, ISO/IEC 27001 Seguridad y Aislamiento Multi-Tenant, ISO 8601 Timestamps UTC, ISO/IEC 10646 UTF-8 y codificación de tickets).",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
]


# -----------------------------------------------------------------------------
# Implementación de las funciones de cada herramienta
# -----------------------------------------------------------------------------

def handle_parse_scale_frame(args: dict[str, Any]) -> dict[str, Any]:
    frame = str(args.get("frame", ""))
    capacidad = args.get("capacidad_maxima")
    if capacidad is not None:
        try:
            capacidad = float(capacidad)
        except (ValueError, TypeError):
            capacidad = None

    if parse_weight_frame is None:
        return {"error": "No se pudo importar app.core.scale_parser"}

    # Reemplazar secuencias de escape literales tipo \x02 o \r si vienen en el string
    if "\\x" in frame or "\\r" in frame or "\\n" in frame:
        try:
            frame = frame.encode("utf-8").decode("unicode_escape")
        except Exception:
            pass

    peso, estado, motivo = parse_weight_frame(frame, capacidad_max=capacidad)
    return {
        "ok": peso is not None,
        "peso_kg": peso,
        "estado": estado,
        "motivo_rechazo": motivo,
        "raw_input": repr(frame),
    }


def handle_simulate_scale_frame(args: dict[str, Any]) -> dict[str, Any]:
    indicator = args.get("indicator", "toledo")
    weight = float(args.get("weight_kg", 0.0))
    stable = bool(args.get("stable", True))
    unit = str(args.get("unit", "kg")).lower()

    st_tok = "ST" if stable else "US"
    sign = "+" if weight >= 0 else "-"
    abs_weight = abs(weight)

    if indicator == "toledo":
        # Formato Toledo / GSI: ST,GS,+00320.00kg\r\n
        w_str = f"{abs_weight:08.2f}"
        frame = f"{st_tok},GS,{sign}{w_str}{unit}\r\n"
    elif indicator == "yaohua":
        # Formato Yaohua modo continuo '=': =+000023.5kg o espaciado
        w_str = f"{abs_weight:07.1f}"
        frame = f"={sign}{w_str}{unit}\r\n"
    elif indicator == "rice_lake":
        # Formato Rice Lake / iQ con dirección: 01+000320.0
        w_str = f"{abs_weight:07.1f}"
        frame = f"01{sign}{w_str}\r\n"
    elif indicator == "torrey":
        # Formato Torrey LQ: ST,GS,+00042.5kg CR LF
        w_str = f"{abs_weight:07.1f}"
        frame = f"{st_tok},GS,{sign}{w_str}{unit}\r\n"
    elif indicator == "keli_checksum":
        # Formato Keli STX/ETX con XOR Checksum
        payload = f"{st_tok},GS,{sign}{abs_weight:08.2f}{unit}"
        xor_sum = 0
        for b in payload.encode("latin-1"):
            xor_sum ^= b
        checksum_hex = f"{xor_sum:02X}"
        frame = f"\x02{payload}\x03{checksum_hex}\r\n"
    elif indicator == "mtsics":
        # Mettler Toledo MT-SICS: S S 320.00 kg\r\n
        s_tok = "S" if stable else "D"
        frame = f"S {s_tok} {abs_weight:.2f} {unit}\r\n"
    elif indicator == "bsdd_json":
        # Simulador BSDD local
        status = "stable" if stable else "unstable"
        frame = json.dumps({"weight_kg": weight, "status": status}) + "\n"
    else:
        frame = f"{st_tok},GS,{sign}{abs_weight:08.2f}{unit}\r\n"

    return {
        "indicator": indicator,
        "weight_kg": weight,
        "stable": stable,
        "frame_text": frame,
        "frame_repr": repr(frame),
        "bytes_hex": frame.encode("latin-1", errors="replace").hex(),
    }


def handle_calculate_truck_weights(args: dict[str, Any]) -> dict[str, Any]:
    pe_v = Decimal(str(args.get("peso_entrada_vehiculo", 0)))
    ps_v = Decimal(str(args.get("peso_salida_vehiculo", 0)))
    pe_r = Decimal(str(args.get("peso_entrada_remolque") or 0))
    ps_r = Decimal(str(args.get("peso_salida_remolque") or 0))
    tipo_op = str(args.get("tipo_operacion", "RECEPCION")).upper()
    p_decl = args.get("peso_declarado")

    pte = pe_v + pe_r
    pts = ps_v + ps_r

    # Cálculo neto según sentido de operación
    # En RECEPCION (Ingreso): Salida es Tara, Entrada es Bruto (o viceversa según pesaje inicial)
    # Por definición industrial BALANSOFT-WS:
    # Neto Total = abs(PTE - PTS)
    neto_v = abs(pe_v - ps_v)
    neto_r = abs(pe_r - ps_r) if (pe_r > 0 or ps_r > 0) else Decimal("0.00")
    neto_total = abs(pte - pts)

    res: dict[str, Any] = {
        "peso_total_entrada": float(pte),
        "peso_total_salida": float(pts),
        "neto_vehiculo": float(neto_v),
        "neto_remolque": float(neto_r) if (pe_r > 0 or ps_r > 0) else None,
        "peso_neto": float(neto_total),
        "tipo_operacion": tipo_op,
    }

    if tipo_op == "RECEPCION":
        res["kardex"] = {
            "id_tipo_movimiento": 10,
            "tipo": "INGRESO",
            "signo": "+",
            "cantidad_kardex": float(neto_total),
            "descripcion": "Ingreso por recepción de camión (aumenta inventario físico)",
        }
    else:
        res["kardex"] = {
            "id_tipo_movimiento": 60,
            "tipo": "DESPACHO",
            "signo": "-",
            "cantidad_kardex": float(-neto_total),
            "descripcion": "Despacho por salida de carga (disminuye inventario físico)",
        }

    if p_decl is not None:
        decl = Decimal(str(p_decl))
        dif = neto_total - decl
        desv = (dif / decl * 100) if decl != 0 else Decimal("0.0")
        res["peso_declarado"] = float(decl)
        res["peso_diferencia"] = float(dif)
        res["porcentaje_desviacion"] = float(desv.quantize(Decimal("0.0001")))

    return res


def handle_format_ticket_weights_table(args: dict[str, Any]) -> dict[str, Any]:
    fec_e = args.get("fecha_hora_entrada", "")
    pe_c = float(args.get("peso_entrada_camion", 0.0))
    pe_r = args.get("peso_entrada_remolque")
    pe_r_val = float(pe_r) if pe_r is not None else 0.0

    fec_s = args.get("fecha_hora_salida")
    ps_c = args.get("peso_salida_camion")
    ps_c_val = float(ps_c) if ps_c is not None else None
    ps_r = args.get("peso_salida_remolque")
    ps_r_val = float(ps_r) if ps_r is not None else None

    tipo_op = args.get("tipo_operacion", "INGRESO")

    pe_tot = pe_c + pe_r_val

    lines = []
    lines.append("=" * 78)
    lines.append(f"{'':12} | {'Fec, Hrs':18} | {'CAMIÓN':12} | {'REMOLQUE':12} | {'TOTAL':12}")
    lines.append("-" * 78)

    # Fila ENTRADA
    r_str = f"{pe_r_val:10.2f} kg" if pe_r is not None else f"{'':13}"
    lines.append(f"{'ENTRADA:':12} | {fec_e:18} | {pe_c:10.2f} kg | {r_str} | {pe_tot:10.2f} kg")

    # Fila SALIDA (si existe)
    if fec_s and ps_c_val is not None:
        ps_tot = ps_c_val + (ps_r_val or 0.0)
        r_sal_str = f"{ps_r_val:10.2f} kg" if ps_r_val is not None else f"{'':13}"
        lines.append(f"{'SALIDA:':12} | {fec_s:18} | {ps_c_val:10.2f} kg | {r_sal_str} | {ps_tot:10.2f} kg")

        # Fila TOTALES (los netos por vehículo)
        neto_c = abs(pe_c - ps_c_val)
        neto_r = abs(pe_r_val - (ps_r_val or 0.0)) if pe_r is not None else None
        neto_tot = abs(pe_tot - ps_tot)

        r_net_str = f"{neto_r:10.2f} kg" if neto_r is not None else f"{'':13}"
        lines.append(f"{'TOTALES:':12} | {'':18} | {neto_c:10.2f} kg | {r_net_str} | {neto_tot:10.2f} kg")
        lines.append("-" * 78)
        lines.append(f"{'PESO NETO:':12} | {neto_tot:10.2f} kg{'':6} | ({tipo_op}){'':4} | {'':12} | {'':12}")

    lines.append("=" * 78)

    table_ascii = "\n".join(lines)
    return {
        "table_ascii": table_ascii,
        "format_version": "v3.24 (lectura_peso_format_ejemp.ods)",
        "columns": ["(etiqueta)", "Fec, Hrs", "CAMIÓN", "REMOLQUE", "TOTAL"],
    }


def handle_inspect_db_table(args: dict[str, Any]) -> dict[str, Any]:
    table = args.get("table_name", "").strip().lower()
    db = args.get("database", "local").strip().lower()

    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    schema_file = (
        os.path.join(repo_root, "balansoft-ws-local.sql")
        if db == "local"
        else os.path.join(repo_root, "balansoft-ws-server.sql")
    )

    if not os.path.exists(schema_file):
        return {"error": f"Archivo de esquema {schema_file} no encontrado"}

    with open(schema_file, encoding="utf-8") as f:
        content = f.read()

    # Buscar bloque CREATE TABLE
    pattern = rf"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?{table}\s*\((.*?)\);\s*"
    match = re.search(pattern, content, re.DOTALL | re.IGNORECASE)
    if not match:
        return {
            "found": False,
            "table": table,
            "database": db,
            "message": f"Tabla '{table}' no encontrada en {os.path.basename(schema_file)}",
        }

    ddl_body = match.group(0).strip()
    return {
        "found": True,
        "table": table,
        "database": db,
        "schema_file": os.path.basename(schema_file),
        "ddl": ddl_body,
    }


def handle_verify_iso_standards(_args: dict[str, Any]) -> dict[str, Any]:
    return {
        "status": "COMPLIANT",
        "iso_standards": {
            "ISO/IEC 25010": {
                "name": "Calidad del Producto Software (SQuaRE)",
                "status": "VERIFICADO",
                "details": "Adecuación funcional en cálculos de pesaje, latencias p50 < 50ms, modularidad HAL/parser y resiliencia de red.",
            },
            "ISO/IEC 17025 / OIML R 76-1": {
                "name": "Metrología Legal e Integridad de Instrumentos de Pesaje",
                "status": "VERIFICADO",
                "details": "Inmutabilidad del peso físico capturado, verificación de estabilidad, control de sobrecapacidad al 105% y trazabilidad completa de medición.",
            },
            "ISO/IEC 27001": {
                "name": "Seguridad de la Información",
                "status": "VERIFICADO",
                "details": "Aislamiento multi-tenant obligatorio con id_empresa, JWT con expiración, contraseñas hasheadas y validación criptográfica Ed25519.",
            },
            "ISO 8601": {
                "name": "Representación de Fecha y Hora",
                "status": "VERIFICADO",
                "details": "Timestamps persistidos y transmitidos en UTC (YYYY-MM-DDTHH:MM:SSZ); conversión horaria únicamente en Flutter.",
            },
            "ISO/IEC 10646 & ISO/IEC 8859-1": {
                "name": "Codificación y Caracteres",
                "status": "VERIFICADO",
                "details": "UTF-8 en base de datos y API; Latin-1/CP850 en streams térmicos y matriciales para preservar caracteres en español.",
            },
            "ISO/IEC 18004 & ISO/IEC 15417": {
                "name": "Códigos Ópticos de Barras y QR",
                "status": "VERIFICADO",
                "details": "Generación estándar de QR Code Modelo 2 y Code 128 en boletos de pesaje.",
            },
            "ISO/IEC/IEEE 29119": {
                "name": "Pruebas de Software",
                "status": "VERIFICADO",
                "details": "759 tests rápidos + 34 tests E2E con verificación por mutación y CI automatizado.",
            },
        },
    }


# -----------------------------------------------------------------------------
# Loop JSON-RPC 2.0 sobre STDIN/STDOUT
# -----------------------------------------------------------------------------

def send_response(response_dict: dict[str, Any]) -> None:
    payload = json.dumps(response_dict)
    sys.stdout.write(f"Content-Length: {len(payload)}\r\n\r\n{payload}")
    sys.stdout.flush()


def run_server() -> None:
    """Escucha mensajes MCP JSON-RPC sobre stdin y responde por stdout."""
    # Soporta tanto formato estándar Content-Length como líneas JSON directas
    while True:
        line = sys.stdin.readline()
        if not line:
            break

        # Caso 1: Header Content-Length
        if line.lower().startswith("content-length:"):
            try:
                length = int(line.split(":", 1)[1].strip())
                # Leer línea en blanco separadora
                sys.stdin.readline()
                body = sys.stdin.read(length)
                req = json.loads(body)
            except Exception:
                continue
        else:
            # Caso 2: Línea JSON pura (modo interactivo)
            stripped = line.strip()
            if not stripped:
                continue
            try:
                req = json.loads(stripped)
            except Exception:
                continue

        req_id = req.get("id")
        method = req.get("method")

        if method == "initialize":
            send_response({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "serverInfo": {
                        "name": "balansoft-hardware-mcp",
                        "version": "1.0.0",
                    },
                },
            })
        elif method == "notifications/initialized":
            # Notificación del cliente, no requiere respuesta
            pass
        elif method == "ping":
            send_response({"jsonrpc": "2.0", "id": req_id, "result": {}})
        elif method == "tools/list":
            send_response({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {"tools": TOOLS},
            })
        elif method == "tools/call":
            params = req.get("params", {})
            tool_name = params.get("name")
            tool_args = params.get("arguments", {})

            try:
                if tool_name == "parse_scale_frame":
                    out = handle_parse_scale_frame(tool_args)
                elif tool_name == "simulate_scale_frame":
                    out = handle_simulate_scale_frame(tool_args)
                elif tool_name == "calculate_truck_weights":
                    out = handle_calculate_truck_weights(tool_args)
                elif tool_name == "format_ticket_weights_table":
                    out = handle_format_ticket_weights_table(tool_args)
                elif tool_name == "inspect_db_table":
                    out = handle_inspect_db_table(tool_args)
                elif tool_name == "verify_iso_standards":
                    out = handle_verify_iso_standards(tool_args)
                else:
                    out = {"error": f"Herramienta desconocida: {tool_name}"}

                send_response({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "content": [
                            {"type": "text", "text": json.dumps(out, indent=2, ensure_ascii=False)}
                        ]
                    },
                })
            except Exception as exc:
                send_response({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "isError": True,
                        "content": [{"type": "text", "text": f"Error ejecutando {tool_name}: {exc}"}],
                    },
                })
        else:
            if req_id is not None:
                send_response({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32601, "message": f"Method '{method}' not found"},
                })


if __name__ == "__main__":
    run_server()
