# REGLAS DE CONCURRENCIA E I/O PARA HARDWARE (SERIAL, TCP, BLUETOOTH, IMPRESORAS)

La comunicación con dispositivos físicos industriales en BALANSOFT-WS exige aislamiento y manejo de concurrencia riguroso:

## 1. Concurrencia en Puertos Seriales (RS-232 / USB / Bluetooth RFCOMM)
- **Un puerto serie físico solo puede tener un lector activo a la vez.**
- Dos llamadas concurrentes al mismo puerto (ej: `/balanzas/{id}/probar` y el worker en segundo plano de `/live`) provocan la falla de pyserial:
  `device reports readiness to read but returned no data` o buffer corruption.
- `SerialScaleHAL` debe utilizar siempre un cerrojo por dispositivo (`threading.Lock` indexado por la ruta `/dev/...`), y dicho cerrojo debe adquirirse **dentro del hilo de ejecución** (`asyncio.to_thread`) antes de tocar el objeto `serial.Serial`.
- Los timeouts de lectura serie deben estar acotados (ej: 1.0s a 2.0s). Nunca usar lecturas bloqueantes infinitas sin timeout.

## 2. Conexiones de Red y Sockets TCP
- Los indicadores en red emiten flujos continuos o por comandos.
- Al cerrar un `asyncio.StreamWriter`, usar siempre envoltorio seguro con `asyncio.wait_for(writer.wait_closed(), timeout=2.0)` capturando `TimeoutError`, `OSError` y `ValueError`. Dejar `wait_closed()` sin timeout cuelga el proceso si la balanza fue desconectada físicamente.
- Las conexiones TCP con balanzas deben persistirse vía `ScaleSessionManager` entre llamadas sucesivas para evitar sobrecargar la interfaz de red del indicador con ciclos continuos de SYN/RST.
- En caso de desconexión, implementar reintento con backoff exponencial y marcar el estado de conexión como `inestable` o `desconectado`.

## 3. Delimitación y Framing
- Una línea o trama no se considera completa hasta recibir el delimitador configurado para el equipo:
  - `lf`: `\n` (estándar común)
  - `cr`: `\r` (común en indicadores antiguos)
  - `crlf`: `\r\n`
  - `stx_etx`: `\x02` inicio, `\x03` fin (con o sin checksum)
- Descartar bytes `NUL` (`\x00`) y caracteres basura antes del delimitador de inicio.

## 4. Impresoras Industriales (Térmicas y Matriciales)
- El envío de datos a impresoras (USB `/dev/usb/lp*`, Raw TCP puerto 9100 o spooler del SO) debe ser atómico para no intercalar fragmentos de tickets de diferentes terminales.
- Al imprimir en matriciales de formulario continuo, nunca forzar un `Form Feed` (`FF` / `\x0c`) completo si el boleto usa formato de media carta o salto por líneas configurado (`ESC C`), para no desperdiciar papel preimpreso.
- Al imprimir en térmicas (ESC/POS), enviar siempre comando de inicialización `ESC @` al inicio y corte `GS V` tras avanzar 3 a 5 líneas vacías (`\n\n\n`).
