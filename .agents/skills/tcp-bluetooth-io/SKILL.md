---
name: tcp-bluetooth-io
description: >-
  Especialista en I/O de bajo nivel, sockets TCP asíncronos y conectividad Bluetooth (SPP / BLE) para BALANSOFT-WS.
  Usar para comunicación con básculas e impresoras por red local o inalámbrica, reconexión resiliente con backoff,
  buffers de tramas, emparejamiento persistente y pruebas con PTYs virtuales.
---

# TCP & Bluetooth I/O Specialist — BALANSOFT-WS

Guía para la ingeniería y mantenimiento de comunicaciones de red asíncronas y conectividad inalámbrica Bluetooth con básculas, repetidores e impresoras.

## 1. Arquitectura TCP en BALANSOFT-WS

### Backend (Python Asyncio)
- En `backend/app/core/scale_hal.py`:
  - `TcpScaleHAL` utiliza `asyncio.open_connection(host, port)`.
  - Lectura delimitada mediante `reader.readuntil(delimiter)`.
  - **Cierre seguro**: todo `StreamWriter` debe cerrarse dentro de un bloque protegido por timeout (`asyncio.wait_for(writer.wait_closed(), timeout=2.0)`) para no dejar sockets colgados en estado `CLOSE_WAIT` cuando el indicador se apaga o reinicia.
- En `backend/app/core/scale_session.py`:
  - Mantiene viva la conexión entre solicitudes sucesivas del operador (`ScaleSession`).
  - Implementa backoff exponencial ante caídas del enlace de red (`1s, 2s, 4s... hasta 30s`).

### Frontend (Dart / Flutter)
- En `frontend/lib/data/services/scale_frame_parser.dart` y servicios de socket directo:
  - Usa `Socket.connect(host, port, timeout: Duration(seconds: 3))`.
  - Convierte el stream `Uint8List` en líneas de texto mediante `utf8.decoder` y `LineSplitter`.
  - Parsea el peso en tiempo real sin saturar el hilo principal de Flutter.

## 2. Conectividad Bluetooth (Básculas e Impresoras)

### Bluetooth Classic (SPP / RFCOMM)
- Utilizado por indicadores y módulos industriales RS-232 a Bluetooth (ej: HC-05, HC-06, adaptadores industriales Sena/Baudcom):
  - UUID estándar Serial Port Profile: `00001101-0000-1000-8000-00805F9B34FB`.
  - En Linux (WServer / Estación): el kernel expone el enlace como un puerto serie tty: `/dev/rfcomm0`.
  - BALANSOFT-WS trata `/dev/rfcomm0` con la misma robustez que un puerto RS-232 físico (`SerialScaleHAL`), beneficiándose del bloqueo por hilo y del parseo de tramas.

### Bluetooth Low Energy (BLE)
- Utilizado en básculas modernas y dispositivos móviles:
  - Servicio GATT estándar Weight Scale: `0x181D`.
  - Característica Weight Measurement: `0x2A98` / `0x2A9D`.
  - Módulos transparentes UART BLE (Nordic SPP):
    - Service UUID: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
    - RX Characteristic (Write): `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`
    - TX Characteristic (Notify): `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`

*Ver guía completa en [bluetooth_spp_and_ble.md](./references/bluetooth_spp_and_ble.md).*

## 3. Entorno de Pruebas Virtuales con `socat`

Para desarrollo y CI sin hardware físico:
- El script [setup_virtual_serial.sh](./scripts/setup_virtual_serial.sh) crea un par de pseudo-terminales bidireccionales (`/tmp/ttyV0` <-> `/tmp/ttyV1`).
- El simulador escribe en `/tmp/ttyV0` y BALANSOFT-WS lee de `/tmp/ttyV1` como si fuera `/dev/ttyUSB0`.
- El script [tcp_echo_indicator.py](./scripts/tcp_echo_indicator.py) levanta un servidor TCP de prueba inmediato.
