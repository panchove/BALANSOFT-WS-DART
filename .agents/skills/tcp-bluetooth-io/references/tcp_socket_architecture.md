# ARQUITECTURA DE SOCKETS TCP INDUSTRIALES EN BALANSOFT-WS

Guía de diseño para la comunicación confiable por TCP/IP con indicadores de pesaje y pasarelas Ethernet/Serial (Moxa NPort, USR-TCP232, etc.).

---

## 1. Desafíos en Redes Industriales

1. **Desconexiones silenciosas (Half-Open Sockets):**
   - Un cable de red desconectado o un corte de energía en el indicador no siempre envía el paquete `FIN` o `RST`.
   - Sin keep-alive ni timeouts, el socket queda bloqueado indefinidamente.
2. **Fragmentación y Concatenación de Paquetes (Nagle / MTU):**
   - Un paquete TCP no garantiza la delimitación de una trama completa. En una sola lectura pueden recibirse dos tramas juntas (ej: `ST,GS,+00320.00kg\r\nST,GS,+00320.00kg\r\n`) o solo medio frame (ej: `ST,GS,+00`).
   - El código debe usar un buffer acumulador delimitado por `\n`, `\r` o `\x03`.

---

## 2. Patrón de Implementación Asíncrona en Python

```python
async def leer_trama_tcp(host: str, puerto: int, delimitador: bytes, timeout: float = 3.0) -> bytes:
    reader, writer = await asyncio.wait_for(
        asyncio.open_connection(host, puerto),
        timeout=timeout,
    )
    try:
        raw = await asyncio.wait_for(
            reader.readuntil(delimitador),
            timeout=timeout,
        )
        return raw
    finally:
        writer.close()
        try:
            await asyncio.wait_for(writer.wait_closed(), timeout=2.0)
        except (TimeoutError, OSError):
            pass
```

### Reglas Clave:
- Nunca omitir el timeout en `writer.wait_closed()`.
- Capturar `IncompleteReadError` de `asyncio.streams`: si el socket se cierra a mitad de trama, descartar el fragmento parcial.
- Utilizar `ScaleSession` para evitar reconexiones continuas cuando la pantalla está activa monitoreando el peso.

---

## 3. Patrón de Conexión en Flutter (Dart)

```dart
class ScaleTcpClient {
  Socket? _socket;
  final StreamController<String> _frames = StreamController.broadcast();

  Future<void> connect(String host, int port) async {
    _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
    _socket!
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => _frames.add(line),
          onError: (e) => _handleError(e),
          onDone: () => _handleDisconnect(),
          cancelOnError: false,
        );
  }
}
```
