---
name: scale-specialist
description: Protocolos de comunicación y decodificación de indicadores de báscula de BALANSOFT-WS (Toledo, Yaohua, Rice Lake, Torrey, Keli, MT-SICS, Cardinal) sobre Serial RS-232, TCP sockets y Bluetooth.
---

# Scale Specialist Skill — BALANSOFT-WS

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 42001 / ISO/IEC 17025 / OIML R 76-1
**Fuente:** Sistema BALANSOFT-WS
**Autor:** Lead Architect


## Arquitectura de Conexión de Básculas

1. **Parser Puro (`src/backend/app/core/scale_parser.py` y `src/frontend/lib/data/services/scale_frame_parser.dart`):**
   - Decodificación agnóstica de tramas ASCII/Hexadecimal sin efectos secundarios ni dependencias de I/O.
   - Satisface paridad estricta entre Python y Dart verificado por tests unitarios.
2. **Capa HAL (`src/backend/app/core/scale_hal.py`):**
   - Abstracción de canales físicos: Serial (`pyserial`), TCP (`asyncio.open_connection`) y Bluetooth RFCOMM/BLE.
   - Manejo de cerrojos (`threading.Lock`) por puerto para evitar concurrencia y buffer corruption.
3. **Gestor de Sesiones Persistentes (`src/backend/app/core/scale_session.py`):**
   - Mantiene conexiones abiertas con indicadores por red TCP para evitar sobrecarga por ciclos continuos SYN/RST.

## Comandos de Verificación con el Servidor MCP

El proyecto cuenta con un servidor MCP nativo en `src/backend/scripts/mcp_hardware_server.py`.

- **Probar parsing de trama:**
  Utilizar la herramienta MCP `parse_scale_frame` con la trama cruda del indicador.
- **Simular indicador:**
  Utilizar la herramienta MCP `simulate_scale_frame` especificando protocolo (`yaohua`, `toledo`, `ricelake`, `torrey`, `keli`, `mt-sics`) y peso objetivo.
- **Ejecutar tests del HAL y parser:**
  ```bash
  cd src/backend && uv run pytest tests/test_scale_parser.py tests/test_scale_hal.py -v
  ```