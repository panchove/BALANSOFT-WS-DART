"""HAL (Hardware Abstraction Layer) de balanza (B7 / REQ-NF-ARQ-004).

Permite leer el peso en vivo desde hardware real (serial/RS-232) o desde un
servidor TCP (p. ej. el simulador BSDD que emite líneas JSON
``{"weight_kg":..., "status":"stable"}``).

Por defecto la lectura es de un tiro (abre/cierra la conexión). El TCP además
soporta **emparejamiento persistente** (``conectar``/``leer_muestra``/``cerrar``)
que ``ScaleSession`` usa para mantener una misma conexión viva. ``get_scale_hal``
decide la implementación según la configuración de la balanza (``puerto_com`` vs
``ip_address``/``puerto_tcp``).

**Concurrencia serial:** ``SerialScaleHAL`` usa un ``threading.Lock`` por ruta
de puerto (compartido a nivel de clase). El bloqueo se aplica **dentro del
hilo** que ejecuta pyserial (``asyncio.to_thread``), porque un ``asyncio.Lock``
no serializa correctamente el IO bloqueante que corre en otro hilo. Sin esto,
dos lecturas simultáneas (p. ej. ``/probar`` y ``/live``) provocan el error
clásico de pyserial
``"device reports readiness to read but returned no data"``.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import threading
import time
from abc import ABC, abstractmethod

log = logging.getLogger("balansoft_ws.scale")


async def _cerrar_writer(writer: asyncio.StreamWriter | None) -> None:
    """Cierra un ``StreamWriter`` sin colgarse si el par ya no responde.

    ``wait_closed()`` puede quedar esperando indefinidamente cuando la balanza
    desapareció; se acota con timeout y se ignoran errores de cierre.
    """
    if writer is None:
        return
    try:
        writer.close()
        await asyncio.wait_for(writer.wait_closed(), timeout=2.0)
    except (TimeoutError, OSError, ValueError):
        pass


class ScaleHAL(ABC):
    """Interfaz abstracta para hardware de balanza."""

    @abstractmethod
    async def read_weight(self) -> float | None:
        """Lee el peso actual en kg. Devuelve ``None`` si no se puede leer."""
        raise NotImplementedError

    @abstractmethod
    async def is_stable(
        self, duration_seconds: int = 3, tolerance_kg: float = 0.5
    ) -> bool:
        """Verifica que el peso esté estable durante N segundos."""
        raise NotImplementedError

    # ------------------------------------------------------------------
    # Emparejamiento persistente (opcional)
    #
    # Por defecto la lectura es de un solo tiro (abre/cierra por lectura).
    # Los transportes que pueden mantener la conexión viva (TCP) sobreescriben
    # estos métodos para que ``ScaleSession`` reutilice una misma conexión
    # hasta que la app o la balanza se cierren.
    # ------------------------------------------------------------------

    async def conectar(self) -> bool:
        """Abre la conexión persistente. ``True`` si quedó emparejada."""
        return True

    async def leer_muestra(self) -> tuple[float | None, str | None]:
        """Lee la siguiente muestra de la conexión abierta.

        Devuelve ``(peso_kg, estado)``; ``(None, None)`` si aún no hay dato.
        """
        return await self.read_weight(), None

    async def cerrar(self) -> None:
        """Cierra la conexión persistente (idempotente)."""
        return None


class SerialScaleHAL(ScaleHAL):
    """Balanza serial (RS-232/USB). Requiere el paquete ``pyserial``.

    Serializa el acceso con un ``threading.Lock`` a nivel de proceso por ruta
    de puerto. El lock se aplica **dentro del hilo** que abre pyserial, así
    que dos requests concurrentes (``/probar`` y ``/live``, por ejemplo) no
    pueden abrir el mismo pty a la vez. Además reintenta hasta 3 veces si el
    pty está transitoriamente ocupado.
    """

    # Lock a nivel de proceso (threading, no asyncio) por ruta de puerto.
    _thread_locks: dict[str, threading.Lock] = {}
    _thread_locks_guard = threading.Lock()

    def __init__(self, port: str, baudrate: int = 9600, timeout: float = 1):
        self.port = port
        self.baudrate = baudrate
        self.timeout = timeout

    @classmethod
    def _lock_for(cls, port: str) -> threading.Lock:
        """Devuelve (creando si hace falta) el lock asociado a `port`."""
        with cls._thread_locks_guard:
            lock = cls._thread_locks.get(port)
            if lock is None:
                lock = threading.Lock()
                cls._thread_locks[port] = lock
            return lock

    def _parse_line(self, line: str) -> float | None:
        """Convierte una línea de la báscula en un número.

        Acepta formatos como:
        - ``+320.00``
        - ``ST,GS,+00320.00kg``
        - ``320.0``
        """
        t = line.strip()
        if not t:
            return None
        # Quita unidades alfabéticas finales (kg, g, lb, etc.).
        t = t.rstrip("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        # Toma el último token y normaliza coma decimal → punto.
        token = t.split()[-1].replace(",", ".")
        try:
            return float(token)
        except (TypeError, ValueError):
            return None

    async def read_weight(self) -> float | None:
        try:
            import serial  # noqa: F401  (dependencia opcional; validada aquí)
        except ImportError:
            log.error(
                "pyserial no instalado; imposible leer balanza serial %s", self.port
            )
            return None
        return await asyncio.to_thread(self._read_locked)

    def _read_locked(self) -> float | None:
        """Abre, lee una línea y cierra. Se ejecuta en un hilo bloqueante.

        Protegido por ``threading.Lock`` por ruta: solo un hilo a la vez por
        cada puerto. Reintenta hasta 3 veces si el pty está ocupado.
        """
        import serial  # import local, ya validado en read_weight

        # Si el puerto es una ruta Unix (/dev/...) y no existe físicamente en el sistema,
        # evitar lecturas y retries innecesarios.
        if self.port.startswith("/") and not os.path.exists(self.port):
            return None

        lock = self._lock_for(self.port)
        with lock:
            last_exc: Exception | None = None
            for _ in range(3):
                try:
                    with serial.Serial(
                        self.port, self.baudrate, timeout=self.timeout
                    ) as ser:
                        # Descartar restos del buffer para no leer línea vieja.
                        try:
                            ser.reset_input_buffer()
                        except Exception:  # noqa: BLE001
                            pass
                        line = ser.readline().decode("ascii", errors="ignore")
                    return self._parse_line(line)
                except serial.SerialException as exc:
                    last_exc = exc
                    msg = str(exc).lower()
                    if "no such file" in msg or "file not found" in msg or "errno 2" in msg:
                        return None
                    if "readiness" in msg or "could not open" in msg:
                        # El pty quedó ocupado un instante; reintenta.
                        time.sleep(0.15)
                        continue
                    log.warning("Lectura serial fallida en %s: %s", self.port, exc)
                    return None
                except Exception as exc:  # noqa: BLE001
                    log.warning("Lectura serial fallida en %s: %s", self.port, exc)
                    return None
            log.warning(
                "Lectura serial agotó reintentos en %s: %s", self.port, last_exc
            )
            return None

    async def is_stable(
        self, duration_seconds: int = 3, tolerance_kg: float = 0.5
    ) -> bool:
        """Lee N muestras seguidas y comprueba que la dispersión sea pequeña.

        Cada lectura pasa por el lock, así que no se solapa con otras
        lecturas del mismo puerto. Se recomienda ``duration_seconds=1``
        cuando se llama desde ``/probar`` para no bloquear el pty tanto tiempo.
        """
        samples: list[float] = []
        for _ in range(duration_seconds * 10):
            peso = await self.read_weight()
            if peso is not None:
                samples.append(peso)
            await asyncio.sleep(0.1)
        if len(samples) < 10:
            return False
        return max(samples) - min(samples) < tolerance_kg


class TcpScaleHAL(ScaleHAL):
    """Balanza TCP (simulador BSDD): envía ``get_state`` y parsea el JSON."""

    def __init__(
        self,
        host: str,
        port: int = 5555,
        timeout: float = 5.0,
        tolerance_kg: float = 0.5,
        intervalo: float = 0.5,
    ):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.tolerance_kg = tolerance_kg
        # Cada cuánto pedir el estado si la balanza no empuja datos sola.
        self.intervalo = intervalo
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None

    async def conectar(self) -> bool:
        """Abre y **mantiene** la conexión TCP con la balanza.

        A diferencia de ``read_weight`` (un tiro), aquí la conexión queda viva
        hasta llamar a ``cerrar``: es la base del emparejamiento persistente.
        """
        await self.cerrar()
        try:
            self._reader, self._writer = await asyncio.wait_for(
                asyncio.open_connection(self.host, self.port), timeout=self.timeout
            )
        except (TimeoutError, OSError) as exc:
            log.debug(
                "No se pudo emparejar con balanza %s:%s: %s",
                self.host,
                self.port,
                exc,
            )
            await self.cerrar()
            return False
        await self._pedir_estado()
        return True

    async def leer_muestra(self) -> tuple[float | None, str | None]:
        """Lee la siguiente muestra JSON de la conexión abierta.

        - ``TimeoutError`` (sin datos en ``intervalo``): pide el estado y
          devuelve ``(None, None)``.
        - EOF/caída: levanta ``ConnectionError`` para que la sesión reconecte.
        """
        if self._reader is None:
            raise ConnectionError("conexión TCP no abierta")
        reader = self._reader
        try:
            data = await asyncio.wait_for(reader.readline(), timeout=self.intervalo)
        except TimeoutError:
            await self._pedir_estado()
            return None, None
        if not data:
            raise ConnectionError("la balanza cerró la conexión")
        # El simulador emite una línea por cada cambio de peso; al manipular la
        # báscula se acumulan. Drenar (acotado) las líneas ya disponibles evita
        # quedarse mostrando estados viejos y entrega la muestra más reciente.
        loop = asyncio.get_running_loop()
        deadline = loop.time() + 0.15
        for _ in range(50):
            restante = deadline - loop.time()
            if restante <= 0:
                break
            try:
                extra = await asyncio.wait_for(
                    reader.readline(), timeout=min(0.02, restante)
                )
            except TimeoutError:
                break
            if not extra:
                break
            data = extra
        linea = data.decode(errors="ignore").strip()
        if not linea:
            return None, None
        try:
            payload = json.loads(linea)
        except ValueError:
            return None, None
        if not isinstance(payload, dict):
            return None, None
        peso = payload.get("weight_kg")
        if peso is None:
            return None, None
        try:
            return float(peso), payload.get("status")
        except (TypeError, ValueError):
            return None, None

    async def _pedir_estado(self) -> None:
        if self._writer is None:
            return
        try:
            self._writer.write(b'{"action":"get_state"}\n')
            await self._writer.drain()
        except OSError as exc:
            raise ConnectionError(str(exc)) from exc

    async def cerrar(self) -> None:
        writer, self._writer = self._writer, None
        self._reader = None
        await _cerrar_writer(writer)

    async def read_weight(self) -> float | None:
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(self.host, self.port), timeout=self.timeout
            )
            try:
                writer.write(b'{"action":"get_state"}\n')
                await writer.drain()
                deadline = asyncio.get_running_loop().time() + self.timeout
                # Lee líneas JSON descartando vacías/malformadas hasta obtener un
                # `weight_kg` válido o agotar el timeout. Robusto ante el simulador
                # BSDD, que emite una línea al conectarse el cliente y otra más al
                # responder `get_state`.
                while True:
                    restante = deadline - asyncio.get_running_loop().time()
                    if restante <= 0:
                        return None
                    data = await asyncio.wait_for(
                        reader.readline(), timeout=restante
                    )
                    if not data:
                        return None
                    linea = data.decode(errors="ignore").strip()
                    if not linea:
                        continue
                    try:
                        payload = json.loads(linea)
                    except ValueError:
                        continue
                    if not isinstance(payload, dict):
                        continue
                    peso = payload.get("weight_kg")
                    if peso is None:
                        continue
                    try:
                        return float(peso)
                    except (TypeError, ValueError):
                        continue
            finally:
                await _cerrar_writer(writer)
        except (TimeoutError, OSError, ValueError, TypeError, json.JSONDecodeError):
            return None

    async def is_stable(
        self, duration_seconds: int = 3, tolerance_kg: float = 0.5
    ) -> bool:
        muestras: list[float] = []
        for _ in range(duration_seconds * 10):
            peso = await self.read_weight()
            if peso is not None:
                muestras.append(peso)
            await asyncio.sleep(0.1)
        if len(muestras) < 10:
            return False
        return max(muestras) - min(muestras) < tolerance_kg


def get_scale_hal(balanza) -> ScaleHAL:
    """Construye el HAL según la configuración de hardware de la balanza.

    Prioridad: TCP (``ip_address``/``puerto_tcp``) → serial (``puerto_com``).
    Si no hay configuración, levanta ``ValueError`` (el endpoint responde 400).
    """
    ip = getattr(balanza, "ip_address", None)
    puerto_tcp = getattr(balanza, "puerto_tcp", None)
    puerto_com = getattr(balanza, "puerto_com", None)

    if ip:
        return TcpScaleHAL(str(ip), int(puerto_tcp or 5555))
    if puerto_com:
        return SerialScaleHAL(str(puerto_com))
    raise ValueError(
        "La balanza no tiene configuración de hardware "
        "(ip_address/puerto_tcp o puerto_com)"
    )