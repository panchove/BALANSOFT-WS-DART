# BALANZAS SOPORTADAS — Matriz de compatibilidad de indicadores reales

| Versión | Fecha      | Estado  | Autor                  | Norma           | Fuente                                                                              |
|---------|------------|---------|------------------------|-----------------|-------------------------------------------------------------------------------------|
| 1.0     | 2026-10-12 | Vigente | ENCARGADO BALANSOFT-WS | AGENTS.md v3.21 | `app/core/scale_parser.py`, `app/core/scale_hal.py`, manuales de protocolo públicos |

Identificador trazable: `REQ-NF-BAL-001` (hardenización del HAL para básculas reales multi-marca).

---

## 1. Objetivo

Documentar qué marcas y protocolos serie puede leer BALANSOFT-WS directamente
desde un indicador de pesaje, qué configuración conviene usar en la ficha de
la balanza y qué limitaciones existen en terreno. La matriz se construyó con
las marcas reales que usarán las estaciones (Syneria, Ichiban, Yaohua, Keli,
Torrey, Rice Lake, Excel, Roccia) y se contrastó contra los manuales de
protocolo públicos y el parser multi-marca.

## 2. Cómo lee el sistema el peso

- **El parser** (`backend/app/core/scale_parser.py` + gemelo Dart
  `frontend/lib/data/services/scale_frame_parser.dart`) extrae el número de la
  línea ASCII y clasifica la estabilidad. Es **puro** y comparte el mismo
  contrato en backend (serial/TCP) y en el cliente TCP directo de Flutter.
- **El HAL** (`backend/app/core/scale_hal.py`) abre serial o TCP y entrega
  lecturas continuas; `formato_trama`, `baudrate` y `delimitador` se
  configuran por balanza en la ficha (migración `022`, columnas
  `balanzas.formato_trama|baudrate|delimitador`).
- **La sesión** (`app/core/scale_session.py`) mantiene una conexión viva por
  balanza, deduce estabilidad por repetición cuando la trama no trae token de
  estado y reconecta con backoff.

## 3. Matriz de marcas y protocolos

| Marca / equipo (según foto del cliente)                                                    | Protocolo serie típico                                                            | Ejemplo de trama                    | ¿Cubierto? | Configuración recomendada                                                                                                  |
|--------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|-------------------------------------|------------|----------------------------------------------------------------------------------------------------------------------------|
| **Syneria** / **Ichiban** — comercial torre y mostrador (rebranding de indicadores chinos) | Continuo estilo Toledo/GSI o Yaohua "="                                           | `ST,GS,+00042.5kg` / `=+000023.5kg` | ✅          | `formato_trama=auto`, `delimitador=lf\|crlf`, `baudrate=9600`; activar salida continua en el indicador                     |
| **Ichiban** — indicador ABS (LCD/LED) y de piso                                            | Toledo clon / Yaohua "="                                                          | `ST,GS,+00320.0kg` / `=+000023.5kg` | ✅          | igual que arriba                                                                                                           |
| **Yaohua** — XK3190-A9/A9+/C8/DS3 (indicadores en gabinete acero inox. y ABS)              | Modo PC continuo de 10 bytes: inicio `=`, 8 datos ASCII, stop; con o sin espacios | `=+000023.5kg`, `= 00023.5 kg`      | ✅          | `formato_trama=ascii` si el indicador lo soporta o `auto`; el estado se deduce por repetición (la trama "=" no lleva `ST`) |
| **Keli** — indicadores (y celdas)                                                          | Toledo clon `ST,GS,` o trama 22 bytes STX/ETX + checksum XOR                      | `ST,GS,+00320.0kg`                  | ✅          | `formato_trama=auto`; si el indicador usa checksum obligatorio, activar modo Toledo sin checksum (ver §6.4)                |
| **Torrey** — LQ (indicadores industriales)                                                 | Salida continua estilo Toledo/GSI                                                 | `ST,GS,+00042.5kg` CR LF            | ✅          | `formato_trama=auto` (`ascii` si se fija), `delimitador=lf\|crlf`                                                          |
| **Torrey** — LEQ-HS y básculas de mostrador retail                                         | Emiten **por comando** (envían peso tras recibir `P`/print)                       | —                                   | ⚠️ Ver §6.1 | Activar modo continuo en el indicador                                                                                      |
| **Rice Lake** — 120 / iQ / iQ+                                                             | Paralelo estilo Toledo `ST,GS,` o dirección adherida                              | `ST,GS,+000320.0` / `01+000320.0`   | ✅          | `formato_trama=auto`; `01+...` no lleva estado → deducción por repetición                                                  |
| **Excel** (indicadores)                                                                    | Continuo configurable estilo Toledo                                               | `ST,GS,+00042.5kg`                  | ✅          | `formato_trama=auto`                                                                                                       |
| **Roccia**                                                                                 | Comercialización de indicadores (rebranding)                                      | según indicador                     | ✅          | depende del indicador real                                                                                                 |
| **Celdas de carga Keli / Zemic / Mavin**                                                   | Señal analógica mV/V → van al **indicador**, no hablan protocolo                  | N/A                                 | N/A        | Se conectan al indicador; el sistema lee del indicador                                                                     |
| **Junction boxes Keli / Yaohua**                                                           | Suma analógica de celdas, sin protocolo                                           | N/A                                 | N/A        | N/A                                                                                                                        |
| **Repetidor / display LED gigante** (Yaohua/Ichiban)                                       | Es **receptor** (corriente 20 mA / comando) del indicador                         | N/A                                 | N/A        | Leer del indicador, no del repetidor                                                                                       |

## 4. Tramas ya fijadas por test (regresión)

| Formato                    | Ejemplo                       | Resultado                             |
|----------------------------|-------------------------------|---------------------------------------|
| Toledo/GSI                 | `ST,GS,+00320.00kg`           | `(320.0, stable)`                     |
| Toledo/GSI con espacios    | `ST,GS,+  320.00 kg`          | `(320.0, stable)`                     |
| Yaohua "=" (compacto)      | `=+000023.5kg`                | `(23.5, None)` — estado deducido      |
| Yaohua "=" (espaciado)     | `= 00023.5 kg`                | `(23.5, None)`                        |
| Yaohua "=" negativo        | `=-001234.0kg`                | `(-1234.0, None)`                     |
| Torrey LQ / Keli           | `ST,GS,+00042.5kg`            | `(42.5, stable)`                      |
| Rice Lake/iQ con dirección | `01+000320.0`                 | `(320.0, None)`                       |
| MT-SICS                    | `S S 320.00 kg`               | `(320.0, None)`                       |
| Signo suelto               | `-  12.50KG`                  | `(-12.5, None)`                       |
| STX/ETX + checksum XOR     | `\x02ST,GS,+00320.00kg\x032B` | `(320.0, stable)` (checksum validado) |
| ETX suelto en payload      | `ST,GS,320.00kg\x03`          | `(320.0, stable)`                     |

Rechazadas por diseño (anti-falso-positivo): `1234567890`, `01`, `=000001`
(número desnudo) y `123.4 567.8` (ambigüedad).

> Nota: las tramas sin token de estado (`=+…`, `01+…`, MT-SICS) devuelven
> `status=None`; la sesión entonces **asume estable** y, con ≥5 lecturas, exige
> que la varianza sea menor que la tolerancia (`_es_estable` en
> `scale_session.py`). Es la decisión correcta: esos protocolos no transmiten
> estabilidad, y ante una lectura dudosa el operador confirma la captura.

## 5. Puesta en marcha de un indicador real

1. Cablear RS232 (Tx→Rx, Gnd→Gnd, niveles 5 V) o TCP/IP; puerto COM y baudrate
   según el indicador (los chinos suelen 9600 8N1).
2. En el **indicador**: configurar **salida continua** (no "por comando").
   - Yaohua XK3190: parámetro de comunicación → modo continuo.
   - Torrey: `Cont` (continuo) en el menú RS-232, no `St 1`/`Pr 1`/`P`.
   - Toledo/GSI clones: modo stream.
3. En **BALANSOFT-WS**: Dispositivos → Balanzas → editar la balanza →
   `formato_trama` (dejar `auto` la primera vez), `baudrate`, `delimitador`
   (`lf` si llegan saltos de línea; `cr` si solo retornos; `crlf`; `stx_etx`
   si la trama va entre `0x02`/`0x03`).
4. Usar **Probar balanza** para ver el peso en vivo. Si no lee:
   - confirmar continuo y 8N1; bajar/ajustar baudrate;
   - si el indicador manda solo `\r`, poner `delimitador=cr`;
   - si la auto-detección no concluye (indicador lento en arrancar), fijar
     `formato_trama=ascii` explícito.

## 6. Limitaciones conocidas (aceptadas)

### 6.1 Básculas que solo emiten por comando (`P`/print)
Algunas básculas de mostrador (p. ej. Torrey LEQ-HS y varias retail) emiten el
peso **después de recibir un comando** (letra `P` o tecla de impresión) y no
tienen salida continua activable. El HAL no envía comandos de petición
configurables (decisión de la v3.21); la mitigación es activar el modo
continuo del indicador o usar un indicador industrial con salida stream.

### 6.2 Variante "dígitos separados" (`= 0 0 0 2 3 . 5 k g`)
Algún indicador muy antiguo rellena la trama ASCII dígito a dígito con
espacios. Se rechaza (`sin_numero`); alternativa: modo compacto o estilo
Toledo en el indicador. No se implementó por ser marginal y por el riesgo de
falsos positivos.

### 6.3 Delimitador solo-CR
Indicadores que terminan la trama solo con `\r` requieren
`delimitador=cr` en la ficha (ya disponible en la UI). El default es `lf`.

### 6.4 Checksum XOR obligatorio
Algunos modos de Keli/Yaohua (p. ej. scoreboard de 11 bytes o tramas de
22 bytes) exigen checksum. El parser tiene `validar_checksum` (XOR), pero **no
está expuesto en BD/UI** (decisión v3.21, `REQ-NF-BAL-001`). En terreno:
activar modo Toledo sin checksum en el indicador. Si un cliente lo requiere,
planificar la exposición (columna + UI + i18n + migración).

### 6.5 Celdas, junction boxes y repetidores
No son fuentes de protocolo: se conectan al indicador y el sistema lee del
indicador. Un repetidor LED recibe la señal, no la emite con formato utilizable.

## 7. Referencias

- `backend/app/core/scale_parser.py` — parser puro (fuente de verdad).
- `frontend/lib/data/services/scale_frame_parser.dart` — gemelo Dart.
- `backend/app/core/scale_hal.py` — `SerialScaleHAL`/`TcpScaleHAL`, auto-detección.
- `backend/app/core/scale_session.py` — sesión viva, estabilidad por repetición.
- `backend/tests/test_scale_parser.py` y `frontend/test/unit/scale_parser_test.dart` — regresión de tramas.
- `backend/migrations/022_balanza_formato_trama.sql` — columnas de configuración.
- Manuales públicos: Yaohua XK3190-A9/A9+ (modo PC continuo 10 bytes),
  Torrey LQ/LEQ-HS (RS-232), Rice Lake 120 (EDP).