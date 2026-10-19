# GUÍA DE INTEGRACIÓN BLUETOOTH (SPP / RFCOMM Y BLE) EN PESAJE

Esta referencia detalla cómo conectar básculas, repetidores de pesaje e impresoras móviles vía Bluetooth en BALANSOFT-WS tanto en estaciones Linux de escritorio como en terminales móviles Android.

---

## 1. Bluetooth Clásico (SPP / RFCOMM)

El perfil SPP (Serial Port Profile) emula un cable RS-232 sobre el protocolo RFCOMM:
- **UUID SPP Estándar:** `00001101-0000-1000-8000-00805F9B34FB`
- **Canal RFCOMM Típico:** Canal 1.

### Vinculación en Linux (Estaciones de Pesaje / WServer)
Para que el backend FastAPI o WServer lea un indicador Bluetooth como un puerto serie normal:

1. **Escanear y emparejar:**
   ```bash
   bluetoothctl
   [bluetooth]# scan on
   [bluetooth]# pair 00:14:03:05:5B:2A
   [bluetooth]# trust 00:14:03:05:5B:2A
   ```
2. **Crear el enlace serie `/dev/rfcomm0`:**
   ```bash
   sudo rfcomm bind 0 00:14:03:05:5B:2A 1
   ```
3. **Configuración en BALANSOFT-WS:**
   - En la ficha de la báscula: `protocolo = serial`, `puerto_com = /dev/rfcomm0`.
   - `SerialScaleHAL` abre `/dev/rfcomm0` exactamente igual que `/dev/ttyUSB0`, con cerrojo `threading.Lock` y auto-detección de delimitador.

---

## 2. Bluetooth Low Energy (BLE GATT)

En indicadores modernos con chip BLE (Nordic nRF52, ESP32, TI CC2640):

### Perfil Estándar Weight Scale (SIG GATT)
- **GATT Service:** `0x181D` (Weight Scale)
- **GATT Characteristic:** `0x2A9D` (Weight Measurement)
  - Byte 0: Flags (Bit 0: 0=kg / 1=lbs; Bit 1: Timestamp present; Bit 2: User ID; Bit 3: BMI).
  - Bytes 1–2: Peso en formato IEEE-11073 16-bit float (SFLOAT) o entero con resolución.

### Módulos Transparentes BLE UART (Nordic SPP)
La inmensa mayoría de indicadores industriales con BLE utilizan un servicio UART transparente que emite las mismas tramas ASCII que el puerto RS-232:
- **Service UUID:** `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- **TX Characteristic (Notify):** `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` (el indicador envía el peso).
- **RX Characteristic (Write):** `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` (para enviar comando `'P'`, `'T'` tara o `'Z'` cero).

En Flutter se suscribe a las notificaciones de la característica TX y se alimenta directamente a `ScaleFrameParser`.
