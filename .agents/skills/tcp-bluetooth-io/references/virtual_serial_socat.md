# EMULACIÓN DE PUERTOS SERIE VIRTUALES CON SOCAT Y PTYS

Guía para simular puertos RS-232 y USB-Serial en Linux para pruebas locales y CI automatizado sin hardware real.

---

## 1. Funcionamiento del Par PTY con `socat`

`socat` permite crear un canal bidireccional entre dos pseudo-terminales (PTYs):
```bash
socat -d -d pty,raw,echo=0,link=/tmp/ttyV0 pty,raw,echo=0,link=/tmp/ttyV1
```

- `/tmp/ttyV0`: El simulador o generador de tramas escribe aquí.
- `/tmp/ttyV1`: La aplicación (FastAPI / WServer) lee de aquí como si fuera `/dev/ttyUSB0`.

---

## 2. Detección Automática en BALANSOFT-WS

El endpoint de auto-descubrimiento (`GET /api/v1/balanzas/descubrir` en `app/api/v1/endpoints/inventario.py`) busca rutas coincidentes con la variable de entorno:
```bash
BSSD_SERIAL_GLOBS="/tmp/bsdd_*,/tmp/ttyV*,/tmp/tnt*"
```

Cualquier enlace en `/tmp/ttyV*` que sea un PTY activo es clasificado automáticamente como:
- `protocolo: serial`
- `is_simulada: true`
- `puerto_com: /tmp/ttyV1`

Esto permite que la pantalla de `Dispositivos` en Flutter detecte la balanza virtual con un solo clic en **"Detectar básculas"**.
