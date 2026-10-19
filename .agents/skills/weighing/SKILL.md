---
name: weighing
description: >-
  Pesaje industrial integral de BALANSOFT-WS. Coordinador maestro para básculas (RS-232, TCP, Bluetooth),
  cálculos metrológicos de camiones (tara, bruto, neto), impresión de tickets y reglas de negocio.
---

# BALANSOFT-WS — Master Weighing Architecture & Runbook

Habilidad orquestadora del sistema de pesaje industrial de BALANSOFT-WS. Coordina el hardware de lectura, el cálculo de camiones, el ciclo de vida de los boletos y la impresión física.

## 1. Módulos Especializados del Dominio

Para tareas específicas, consultar y activar las habilidades especializadas:

- **[scale-specialist](../scale-specialist/SKILL.md):**
  Protocolos de indicadores (Toledo, Yaohua, Rice Lake, Torrey, Keli, MT-SICS), decodificación de tramas ASCII/hex, algoritmos de checksum XOR, delimitadores (`lf`, `cr`, `crlf`, `stx_etx`), auto-descubrimiento y detección de estabilidad.
- **[truck-weighing-system](../truck-weighing-system/SKILL.md):**
  Tipologías de camiones (C2, C3, C4, T3S2, T3S3, Bitrén), pesaje por ejes, doble pesada (recepción vs despacho), desgloses de camión + remolque, integración con Kardex (10 Ingreso / 60 Despacho) y bloqueo transaccional de series de numeración.
- **[printer-specialist](../printer-specialist/SKILL.md):**
  Impresoras térmicas ESC/POS (80mm/58mm), matriciales de impacto ESC/P (Epson LX-350 / FX-890) con formulario continuo y copias carbón, generación PDF adaptativa (ReportLab) y paridad visual con Flutter.
- **[tcp-bluetooth-io](../tcp-bluetooth-io/SKILL.md):**
  Sockets TCP asíncronos (`asyncio`), enlaces Bluetooth clásico RFCOMM/SPP (`/dev/rfcomm*`), BLE GATT y puertos serie virtuales (`socat` / PTYs).
- **[opencode-mcp-devkit](../opencode-mcp-devkit/SKILL.md):**
  Servidor MCP local (`backend/scripts/mcp_hardware_server.py`) y configuración de desarrollo con OpenCode.

---

## 2. Invariables de Negocio del Pesaje

1. **Inmutabilidad de la Báscula:** El peso capturado por hardware nunca se edita directamente en la base de datos.
2. **Estados del Boleto:** `PENDIENTE -> CERRADO/MODIFICADO -> ANULADO`. No existen estados intermedios no autorizados.
3. **Restricción de Vehículo en Tránsito:** Ningún camión puede tener dos boletos en estado `PENDIENTE` al mismo tiempo.
4. **Kardex y Reversión:**
   - Recepción = Movimiento 10 (+).
   - Despacho = Movimiento 60 (-).
   - Anulación = Contra-asiento inverso automático con valor opuesto.
5. **Paridad de Boleto:** La tabla de 5 columnas `[ (etiqueta) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL ]` es idéntica en térmica, hoja y matricial.

---

## 3. Pruebas y Validación Rápida

- **Ejecutar tests de básculas y parser:**
  ```bash
  backend/.venv/bin/python -m pytest backend/tests/test_scale_parser.py backend/tests/test_scale_hal.py -v
  ```
- **Probar una trama arbitraria:**
  ```bash
  backend/.venv/bin/python .agents/skills/scale-specialist/scripts/test_frame.py "ST,GS,+00320.00kg"
  ```
- **Calcular distribución de peso de camión:**
  ```bash
  backend/.venv/bin/python .agents/skills/truck-weighing-system/scripts/truck_weight_calculator.py --pe-camion 15000 --ps-camion 5000 --operacion RECEPCION
  ```