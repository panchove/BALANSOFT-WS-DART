# SPOOLING Y ENVÍO DE TICKETS A IMPRESORAS DE RED, USB Y CUPS

Guía de transporte para la entrega física de trabajos de impresión en estaciones BALANSOFT-WS.

---

## 1. Impresión Directa por Red (Raw TCP / Puerto 9100 JetDirect)

Las impresoras térmicas con placa Ethernet/WiFi (Epson TM-T20/T88, Xprinter, Bixolon) escuchan en el puerto TCP 9100:

```python
import socket

def imprimir_raw_tcp(host: str, datos_binarios: bytes, puerto: int = 9100, timeout: float = 5.0):
    with socket.create_connection((host, puerto), timeout=timeout) as s:
        s.sendall(datos_binarios)
```

- Es el método más rápido (sin colas de impresión del sistema operativo).
- No requiere controladores de fabricante instalados.

---

## 2. Impresión Directa por USB (`/dev/usb/lp*`)

En estaciones Linux (WServer / Ubuntu / Debian):
- Las impresoras USB suelen registrarse en `/dev/usb/lp0` o `/dev/usb/lp1`.
- El proceso del WServer necesita permisos del grupo `lp` (`sudo usermod -a -G lp $USER`).
- Escritura directa atómica:
  ```python
  with open("/dev/usb/lp0", "wb") as f:
      f.write(datos_binarios)
  ```

---

## 3. Spooling mediante CUPS (`lp` / `lpr`)

Para impresoras instaladas a nivel de sistema operativo:
- **Listar impresoras:** `lpstat -p`
- **Enviar archivo a cola:**
  ```bash
  lp -d NombreImpresora -o raw /tmp/ticket.txt
  ```
- La opción `-o raw` es fundamental para impresoras matriciales y térmicas, ya que evita que CUPS intente convertir el archivo de texto en PostScript o raster gráfico.
