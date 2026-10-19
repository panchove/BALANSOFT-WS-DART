# MATRIZ TÉCNICA DETALLADA DE INDICADORES DE PESAJE

Esta guía documenta los detalles de bajo nivel, pines, baudrates y configuración de menú de los principales indicadores industriales utilizados en estaciones camioneras y de tolva.

---

## 1. Yaohua (XK3190-A9 / A9+ / C8 / DS3)
Muy común en básculas camioneras de 60t, 80t y 100t (acero inox o ABS).

- **Salida RS-232:** DB9 hembra.
  - Pin 2: TxD (salida del indicador → RxD de la PC)
  - Pin 3: RxD (entrada al indicador)
  - Pin 5: GND (tierra de señal)
- **Modo PC Continuo (10 bytes):**
  - Trama: `= <signo> <dígitos> <unidad> <CR/LF>`
  - Ejemplo: `=+0002450.0kg\r\n` o espaciado `= 00023.5 kg\r`
  - Longitud fija de 10 a 14 bytes según el firmware.
- **Configuración en el menú del indicador:**
  - Parámetro `[bAud]` → Fijar en `9600` (o `4800` / `2400` / `1200`).
  - Parámetro `[Adr]` → Dirección de comunicación (ej: `01`).
  - Parámetro `[tF]` (Transmission Format) → Fijar en modo continuo para PC.
- **Particularidad en BALANSOFT-WS:**
  - No emite token explícito de estabilidad (`ST`/`US`). El sistema clasifica el frame con `estado=None` y `scale_session.py` evalúa la varianza entre lecturas consecutivas para determinar si el camión ya se detuvo por completo.

---

## 2. Mettler Toledo / GSI (8142, JagXtreme, IND560)
Estándar internacional de alta precisión.

- **Modo Continuous Stream (Toledo Standard):**
  - Cada frame contiene 16 a 18 bytes:
    `ST,GS,+000320.00kg\r\n`
    `US,NT,+000150.00kg\r\n`
  - Campos:
    1. Status 1: `ST` (Stable), `US` (Unstable), `OL` (Overload).
    2. Status 2: `GS` (Gross), `NT` (Net).
    3. Signo y Peso: `+` o `-` seguido de dígitos con punto decimal.
    4. Unidad: `kg`, `lb`, `t`.
- **Configuración en BALANSOFT-WS:**
  - `formato_trama`: `auto` o `ascii`.
  - `delimitador`: `crlf` o `lf`.
  - `baudrate`: 9600 (8N1).

---

## 3. Rice Lake Weighing Systems (120, 720i, 920i, iQ)
Utilizado ampliamente en plantas de asfalto, tolvas y básculas de camiones de alto tráfico.

- **Modo EDP / Continuo:**
  - Puede configurarse para emitir con dirección de báscula adherida:
    `01+000320.0\r`
  - O en modo estándar Toledo: `ST,GS,+000320.0\r\n`
- **Rechazo de ambigüedad:**
  - El parser de BALANSOFT-WS descarta el prefijo de dirección `01` y extrae el peso `+000320.0` con total precisión.

---

## 4. Torrey (LQ industrial vs LEQ-HS retail)
- **Torrey LQ (Plataforma industrial):**
  - Menú `RS-232`: Activar `Cont` (continuo).
  - Trama: `ST,GS,+00042.5kg\r\n`.
  - Delimitador: `crlf` o `lf`.
- **Torrey LEQ-HS (Mostrador / Retail):**
  - Muchas unidades de fábrica solo responden tras presionar la tecla `Print` o recibir el byte `'P'` (0x50) por el puerto serie.
  - Para BALANSOFT-WS, se recomienda configurar el indicador en modo continuo si el firmware lo permite, o activar el sondeo en la estación.

---

## 5. Keli (KX3101 y clones chinos con Checksum)
- Emite paquete enmarcado entre caracteres de control ASCII:
  - Byte 0: `STX` (`\x02`)
  - Bytes 1..N: Payload ASCII (ej: `ST,GS,+00320.00kg`)
  - Byte N+1: `ETX` (`\x03`)
  - Bytes N+2..N+3: Checksum XOR en 2 caracteres hexadecimales.
- **Configuración en BALANSOFT-WS:**
  - `delimitador`: `stx_etx`.
  - El parser valida automáticamente que `XOR(payload) == checksum_hex`.

---

## 6. Mettler Toledo MT-SICS (Protocolo por Comandos y Stream)
- Trama continua o de respuesta a comando:
  `S S 320.00 kg\r\n` (Estable)
  `S D 320.00 kg\r\n` (Dinámico / Inestable)
- El parser detecta el espacio y los tokens `S S` o `S D` para extraer el peso de forma confiable.
