"""HAL (Hardware Abstraction Layer) de balanza (B7 / REQ-NF-ARQ-004).

Permite leer el peso en vivo desde hardware real:

- **Serial/RS-232/USB** (``pyserial``): lee una línea por lectura.
- **TCP**: soporta tanto el simulador BSDD (líneas JSON
  ``{"weight_kg":..., "status":"stable"}``) como **indicadores reales** que
  emiten un flujo ASCII continuo (Toledo/GSI ``ST,GS,+00320.00kg``, etc.).

El parseo numérico vive en ``app/core/scale_parser.py`` (función pura
``parse_weight_frame``), de modo que serial y TCP comparten la misma robustez
(signo, prefijos de estado, STX/ETX, unidades, dirección adherida) y no hay
falsos positivos con números desnudos.

Por defecto la lectura es de un tiro (abre/cierra la conexión). El TCP además
soporta **emparejamiento persistente** (``conectar``/``leer_muestra``/``cerrar``)
que ``ScaleSession`` usa para mantener una misma conexión viva. ``get_scale_hal``
decide la implementación según la configuración de la balanza (``puerto_com`` vs
``ip_address``/``puerto_tcp``) y propaga ``formato_trama``, ``baudrate`` y
``delimitador``.

**Formatos de trama** (``formato_trama``): ``auto`` (default; detecta JSON vs
ASCII), ``json`` (simulador BSDD) y ``ascii`` (indicador de flujo continuo).
**Delimitador** (``delimitador``): ``lf`` (default), ``cr``, ``crlf`` o
``stx_etx``.

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

from app.core.scale_parser import clasificar_trama, parse_weight_frame

log = logging.getLogger("balansoft_ws.scale")

#: Separadores de frame por nombre de delimitador.
_DELIMITADORES: dict[str, bytes] = {
    "lf": b"\n",
    "cr": b"\r",
    "crlf": b"\r\n",
    "stx_etx": b"\x03",
}


def _normalizar_delimitador(delimitador: str | None) -> str:
    valor = (delimitador or "lf").strip().lower()
    return valor if valor in _DELIMITADORES else "lf"


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


def _parse_json_line(linea: str) -> tuple[float | None, str | None]:
    """Extrae ``(peso_kg, status)`` de una línea JSON (simulador BSDD)."""
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

    def __init__(
        self,
        port: str,
        baudrate: int = 9600,
        timeout: float = 1,
        formato_trama: str = "auto",
        delimitador: str | None = None,
        capacidad_max: float | None = None,
    ):
        self.port = port
        self.baudrate = baudrate
        self.timeout = timeout
        self.formato_trama = formato_trama
        self.delimitador = _normalizar_delimitador(delimitador)
        self.capacidad_max = capacidad_max

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
        """Convierte una línea de la báscula en un número (multi-marca).

        Delegado en ``scale_parser.parse_weight_frame``; acepta formatos como
        ``+320.00``, ``ST,GS,+00320.00kg``, ``ST,GS,+  320.00 kg``,
        ``01+000320.0`` y ``-  12.50``, y rechaza números desnudos.
        """
        peso, _status, _motivo = parse_weight_frame(
            line, capacidad_max=self.capacidad_max
        )
        return peso

    def _leer_frame(self, ser) -> str:  # noqa: ANN001 - serial.Serial
        """Lee una trama del puerto según el delimitador configurado."""
        delim = self.delimitador
        if delim == "cr":
            raw = ser.read_until(b"\r")
        elif delim == "crlf":
            raw = ser.read_until(b"\r\n")
        elif delim == "stx_etx":
            raw = ser.read_until(b"\x03")
        else:
            raw = ser.readline()
        return raw.decode("ascii", errors="ignore")

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
                        line = self._leer_frame(ser)
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
    """Balanza TCP.

    Soporta dos protocolos:

    - **JSON** (simulador BSDD): ``{"weight_kg":..., "status":...}``; se pide
      el estado escribiendo ``{"action":"get_state"}``.
    - **ASCII continuo** (indicadores reales): el equipo empuja líneas como
      ``ST,GS,+00320.00kg``; se parsean con ``scale_parser`` y **no** se le
      escribe nada.

    Con ``formato_trama="auto"`` (default) se abre la conexión, se esperan
    uno o varios frames no solicitados durante una ventana corta y se decide:
    si es ASCII, modo ASCII (sin escribir); si es JSON, modo JSON; si no llega
    nada concluyente, queda en modo mixto que intenta JSON y luego ASCII por
    línea y emite ``get_state`` (comportamiento del simulador BSDD).
    """

    def __init__(
        self,
        host: str,
        port: int = 5555,
        timeout: float = 5.0,
        tolerance_kg: float = 0.5,
        intervalo: float = 0.5,
        formato_trama: str = "auto",
        delimitador: str | None = None,
        capacidad_max: float | None = None,
    ):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.tolerance_kg = tolerance_kg
        # Cada cuánto pedir el estado si la balanza no empuja datos sola.
        self.intervalo = intervalo
        self.formato_trama = formato_trama
        self.delimitador = _normalizar_delimitador(delimitador)
        self.capacidad_max = capacidad_max
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._modo: str | None = None
        self._buffer: list[bytes] = []

    # -- lectura de frames ------------------------------------------------

    async def _leer_frame(self, reader: asyncio.StreamReader) -> bytes:
        """Lee un frame del stream según el delimitador configurado."""
        sep = _DELIMITADORES[self.delimitador]
        if sep == b"\n":
            return await reader.readline()
        try:
            return await reader.readuntil(sep)
        except asyncio.IncompleteReadError as exc:
            return exc.partial
        except asyncio.LimitOverrunError:
            return b""

    def _decodificar(self, data: bytes) -> str:
        return data.decode(errors="ignore").strip()

    def _peso_json(self, linea: str) -> tuple[float | None, str | None]:
        return _parse_json_line(linea)

    def _peso_ascii(self, linea: str) -> tuple[float | None, str | None]:
        peso, status, _motivo = parse_weight_frame(
            linea, capacidad_max=self.capacidad_max
        )
        return peso, status

    # -- emparejamiento persistente --------------------------------------

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
        await self._resolver_modo()
        return True

    async def _resolver_modo(self) -> None:
        """Decide el modo (``json``/``ascii``/``auto``) según ``formato_trama``.

        - ``ascii``/``json``: modo fijo.
        - ``auto``: se inspeccionan hasta unos pocos frames no solicitados
          (básculas que empujan) dentro de una ventana corta; si alguno es
          ASCII → ``ascii``, si es JSON → ``json``. Si no llega nada
          concluyente (indicador lento o un banner inicial sin peso) queda en
          ``auto``: por cada línea intenta JSON y luego ASCII, y se pide el
          estado como haría el simulador BSDD.
        """
        fmt = (self.formato_trama or "auto").strip().lower()
        if fmt == "ascii":
            self._modo = "ascii"
            return
        if fmt == "json":
            self._modo = "json"
            await self._pedir_estado()
            return

        # auto: esperar uno o varios frames no solicitados.
        self._modo = None
        if self._reader is not None:
            loop = asyncio.get_running_loop()
            deadline = loop.time() + min(self.timeout, 0.6)
            for _ in range(5):
                restante = deadline - loop.time()
                if restante <= 0:
                    break
                try:
                    data = await asyncio.wait_for(
                        self._leer_frame(self._reader), timeout=restante
                    )
                except (TimeoutError, OSError):
                    break
                if not data:
                    break
                self._buffer.append(data)
                tipo = clasificar_trama(self._decodificar(data))
                if tipo == "ascii":
                    self._modo = "ascii"
                    break
                if tipo == "json":
                    self._modo = "json"
                    break
        if self._modo is None:
            # Nada concluyente: modo mixto (JSON o ASCII por línea) + get_state.
            self._modo = "auto"
            await self._pedir_estado()

    async def leer_muestra(self) -> tuple[float | None, str | None]:
        """Lee la siguiente muestra de la conexión abierta.

        - ``TimeoutError`` (sin datos en ``intervalo``): en modo JSON pide el
          estado y devuelve ``(None, None)``.
        - EOF/caída: levanta ``ConnectionError`` para que la sesión reconecte.
        """
        if self._reader is None:
            raise ConnectionError("conexión TCP no abierta")
        reader = self._reader
        if self._buffer:
            data = self._buffer.pop(0)
        else:
            try:
                data = await asyncio.wait_for(
                    self._leer_frame(reader), timeout=self.intervalo
                )
            except TimeoutError:
                if self._modo in ("json", "auto"):
                    await self._pedir_estado()
                return None, None
        if not data:
            raise ConnectionError("la balanza cerró la conexión")
        # Si la balanza emite ráfagas (o el peso se está manipulando), drenar
        # (acotado) las tramas ya disponibles evita quedarse con estados viejos
        # y entrega la muestra más reciente.
        loop = asyncio.get_running_loop()
        deadline = loop.time() + 0.15
        for _ in range(50):
            restante = deadline - loop.time()
            if restante <= 0:
                break
            try:
                extra = await asyncio.wait_for(
                    self._leer_frame(reader), timeout=min(0.02, restante)
                )
            except TimeoutError:
                break
            if not extra:
                break
            data = extra
        linea = self._decodificar(data)
        if not linea:
            return None, None
        if self._modo == "ascii":
            return self._peso_ascii(linea)
        if self._modo == "auto":
            # Modo mixto: intenta JSON (BSDD) y, si no, ASCII (indicador real).
            peso, status = self._peso_json(linea)
            if peso is not None:
                return peso, status
            return self._peso_ascii(linea)
        return self._peso_json(linea)

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
        self._modo = None
        self._buffer.clear()
        await _cerrar_writer(writer)

    # -- lectura de un tiro ----------------------------------------------

    async def read_weight(self) -> float | None:
        fmt = (self.formato_trama or "auto").strip().lower()
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(self.host, self.port), timeout=self.timeout
            )
            try:
                loop = asyncio.get_running_loop()
                deadline = loop.time() + self.timeout
                if fmt == "ascii":
                    return await self._oneshot_ascii(reader, deadline)
                if fmt == "json":
                    return await self._oneshot_json(reader, writer, deadline)
                # auto: primero flujo continuo (sin escribir) y, si nada, JSON.
                peso = await self._oneshot_ascii(
                    reader, min(deadline, loop.time() + 0.4)
                )
                if peso is not None:
                    return peso
                return await self._oneshot_json(reader, writer, deadline)
            finally:
                await _cerrar_writer(writer)
        except (TimeoutError, OSError, ValueError, TypeError):
            return None

    async def _oneshot_json(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        deadline: float,
    ) -> float | None:
        try:
            writer.write(b'{"action":"get_state"}\n')
            await writer.drain()
        except OSError as exc:
            raise ConnectionError(str(exc)) from exc
        loop = asyncio.get_running_loop()
        while True:
            restante = deadline - loop.time()
            if restante <= 0:
                return None
            data = await asyncio.wait_for(reader.readline(), timeout=restante)
            if not data:
                return None
            linea = self._decodificar(data)
            if not linea:
                continue
            peso, _status = _parse_json_line(linea)
            if peso is not None:
                return peso

    async def _oneshot_ascii(
        self, reader: asyncio.StreamReader, deadline: float
    ) -> float | None:
        loop = asyncio.get_running_loop()
        while True:
            restante = deadline - loop.time()
            if restante <= 0:
                return None
            try:
                data = await asyncio.wait_for(
                    self._leer_frame(reader), timeout=restante
                )
            except TimeoutError:
                return None
            if not data:
                return None
            linea = self._decodificar(data)
            if not linea:
                continue
            peso, _status, _motivo = parse_weight_frame(
                linea, capacidad_max=self.capacidad_max
            )
            if peso is not None:
                return peso

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
    Propaga ``formato_trama``, ``baudrate``, ``delimitador`` y ``capacidad_max``
    cuando el modelo los expone. Si no hay configuración, levanta ``ValueError``
    (el endpoint responde 400).
    """
    ip = getattr(balanza, "ip_address", None)
    puerto_tcp = getattr(balanza, "puerto_tcp", None)
    puerto_com = getattr(balanza, "puerto_com", None)
    formato = getattr(balanza, "formato_trama", None) or "auto"
    delimitador = getattr(balanza, "delimitador", None) or None
    baudrate = getattr(balanza, "baudrate", None) or 9600
    capacidad = getattr(balanza, "capacidad_max", None)
    capacidad_max = float(capacidad) if capacidad is not None else None

    if ip:
        return TcpScaleHAL(
            str(ip),
            int(puerto_tcp or 5555),
            formato_trama=str(formato),
            delimitador=delimitador,
            capacidad_max=capacidad_max,
        )
    if puerto_com:
        return SerialScaleHAL(
            str(puerto_com),
            baudrate=int(baudrate),
            formato_trama=str(formato),
            delimitador=delimitador,
            capacidad_max=capacidad_max,
        )
    raise ValueError(
        "La balanza no tiene configuración de hardware "
        "(ip_address/puerto_tcp o puerto_com)"
    )
