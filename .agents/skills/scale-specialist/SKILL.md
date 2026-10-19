---
name: scale-specialist
description: >-
  Especialista en básculas industriales, indicadores de pesaje y protocolos de hardware para BALANSOFT-WS.
  Usar para indicadores (Toledo, Yaohua, Rice Lake, Torrey, Cardinal, Keli, MT-SICS), decodificación de tramas continuas y por comando,
  checksums XOR/CRC, delimitadores (LF, CR, CRLF, STX/ETX), detección de estabilidad, auto-descubrimiento y pruebas de conexión.
---

# Scale Specialist Skill — BALANSOFT-WS

Guía operacional y de ingeniería para la integración, diagnóstico y programación de básculas industriales e indicadores de pesaje camioneros y de plataforma.

## 1. Arquitectura del HAL en BALANSOFT-WS

El sistema maneja las lecturas de peso a través de tres capas desacopladas:
1. **Parser Puro (`backend/app/core/scale_parser.py` y `frontend/lib/data/services/scale_frame_parser.dart`):**
   - No realiza I/O de red ni serial.
   - Extrae el peso numérico, detecta unidades (`kg`, `lb`, `ton`), prefijos de signo (`+`, `-`), direcciones adheridas (`01+000320.0`) y tokens de estado (`ST`, `US`, `OL`).
   - Aplica el **principio anti-falso-positivo**: rechaza números desnudos sin semántica (como `1234567890`).
2. **Capa HAL (`backend/app/core/scale_hal.py`):**
   - Implementaciones: `SerialScaleHAL` (pyserial / RS-232 / USB) y `TcpScaleHAL` (sockets TCP).
   - Maneja buffers delimitados (`lf`, `cr`, `crlf`, `stx_etx`).
   - Bloqueo por puerto serial mediante `threading.Lock` para prevenir colisiones entre peticiones simultáneas.
3. **Gestor de Sesiones Persistentes (`backend/app/core/scale_session.py`):**
   - Mantiene viva la conexión TCP o serial con cada báscula activa.
   - Para indicadores que no emiten token de estabilidad (ej: Yaohua `=`, Rice Lake `01+`, MT-SICS), deduce la estabilidad calculando la varianza de las últimas 5 lecturas consecutivas.

## 2. Matriz Rápida de Indicadores Industriales

| Indicador | Modo de Salida | Trama Ejemplo | Delimitador | Configuración Recomendada |
|---|---|---|---|---|
| **Yaohua** (XK3190-A9/A9+/C8/DS3) | Continuo 10 bytes | `=+000023.5kg` o `= 00023.5 kg` | `lf` o `crlf` | `formato_trama=auto`, `baudrate=9600`, 8N1 |
| **Mettler Toledo / GSI** (8142, JagXtreme) | Continuo stream | `ST,GS,+00320.00kg` | `crlf` o `lf` | `formato_trama=ascii`, `delimitador=crlf` |
| **Rice Lake** (120, 720i, 920i, iQ) | EDP / Continuo | `01+000320.0` o `ST,GS,+...` | `cr` o `crlf` | `formato_trama=auto`, `baudrate=9600` |
| **Torrey** (LQ / LEQ-HS) | Continuo o Comando `P` | `ST,GS,+00042.5kg\r\n` | `crlf` | En indicador activar modo `Cont` |
| **Keli** (KX3101) | STX/ETX + XOR Checksum | `\x02ST,GS,+00320.00kg\x032B` | `stx_etx` | Validar checksum XOR de 2 dígitos hex |
| **Cardinal** (205, 210) | Continuo SMA | `<LF>00320.0<CR>` | `cr` o `lf` | `delimitador=cr` |

*Para más detalles, consultar [indicators_matrix.md](./references/indicators_matrix.md).*

## 3. Delimitación y Checksums

- **Toledo / Keli Checksum XOR**:
  $$\text{Checksum} = \bigoplus_{i=1}^{n} \text{byte}_i$$
  Se calcula sobre el payload entre `STX` (0x02) y `ETX` (0x03) y se compara con los 2 caracteres hex que siguen al `ETX`.
- Ver especificación en [frame_grammar_and_checksums.md](./references/frame_grammar_and_checksums.md).

## 4. Detección de Estabilidad y Capacidad

- Si el frame contiene `ST`: Estable (`stable`).
- Si el frame contiene `US`: En movimiento / inestable (`unstable`).
- Si el frame contiene `OL`: Sobrecarga (`overload`).
- Si no hay token (`status=None`): Se infiere estable si la desviación en las últimas 5 muestras no excede la tolerancia del sistema (`TOLERANCIA_VARIACION`).
- Capacidad máxima: Se rechaza si supera `1.05 * capacidad_maxima` (`TOLERANCIA_CAPACIDAD`).
- Ver [stability_and_zero_tracking.md](./references/stability_and_zero_tracking.md).

## 5. Scripts y Herramientas

- **Simular báscula en vivo (TCP o Serial PTY):**
  [simulate_scale.py](./scripts/simulate_scale.py)
  ```bash
  backend/.venv/bin/python .agents/skills/scale-specialist/scripts/simulate_scale.py --tcp 5555 --indicator yaohua --peso 24500
  ```
- **Probar parser con una trama arbitraria:**
  [test_frame.py](./scripts/test_frame.py)
  ```bash
  backend/.venv/bin/python .agents/skills/scale-specialist/scripts/test_frame.py "= 00023.5 kg"
  ```
- **Catálogo de tramas de prueba:**
  [frames_catalog.json](./examples/frames_catalog.json)
