---
name: opencode-mcp-devkit
description: >-
  Herramientas de desarrollo, configuración de OpenCode y Servidores MCP para BALANSOFT-WS.
  Usar para integración con el protocolo MCP (Model Context Protocol), herramientas de simulación de hardware,
  diagnóstico rápido del backend y workflows de programación asistida por IA.
---

# OpenCode & MCP DevKit — BALANSOFT-WS

Guía operacional para el uso de servidores MCP (Model Context Protocol) y configuración del entorno OpenCode para programar en BALANSOFT-WS de forma ágil y confiable.

## 1. El Servidor MCP Local de BALANSOFT-WS

Ubicación del script del servidor:
`backend/scripts/mcp_hardware_server.py`

Configurado en:
`.agents/mcp_config.json` y `opencode.json`.

### Herramientas Expuestas por el Servidor MCP:
1. `parse_scale_frame`: Parsea una trama ASCII/hexadecimal en tiempo real con el parser multi-marca del HAL (`app.core.scale_parser`).
2. `simulate_scale_frame`: Genera tramas sintéticas válidas para Toledo, Yaohua, Rice Lake, Torrey, Keli (con checksum XOR), MT-SICS o BSDD JSON.
3. `calculate_truck_weights`: Calcula totales de entrada/salida, desgloses independientes para camión y remolque, peso neto, desviación sobre guía y movimiento contable de Kardex (10 Ingreso vs 60 Despacho).
4. `format_ticket_weights_table`: Genera la tabla textual canónica de 5 columnas para la lectura de pesos según el formato v3.24.
5. `inspect_db_table`: Inspecciona el DDL y esquema de cualquier tabla de la base de datos local o central (`balansoft-ws-local.sql` y `balansoft-ws-server.sql`).

*Ver guía completa del protocolo en [mcp_protocol_guide.md](./references/mcp_protocol_guide.md).*

## 2. Configuración de OpenCode (`opencode.json`)

El archivo `opencode.json` en la raíz del repositorio define:
- Enlace a las reglas de negocio críticas (`.agents/rules/*.md`).
- Scripts canónicos de ejecución rápida (`backend:test`, `backend:lint`, `frontend:analyze`, `frontend:test`).
- Parámetros del dominio industrial (marcas de básculas, impresoras, estados de boleto y kardex).

*Ver guía de flujos de trabajo en [opencode_workflow.md](./references/opencode_workflow.md).*
