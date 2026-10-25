"""HAL (Hardware Abstraction Layer) de las barreras de tránsito (control de acceso).

Dispositivo actuador de salida: la app orquesta la decisión de paso (abrir/cerrar)
y el hardware ejecuta la acción mecánica por HTTP o puerto serie/USB
(docs/DISPOSITIVOS.md §5).

Canales soportados:
- HTTP/REST: `POST http://host:puerto/api/barrera` (comando `{"action": "open"|"close"}`)
  y `GET http://host:puerto/api/barrera` (estado publicado).
- USB / serie (RS-232, CDC-ACM): escritura de comando y lectura de estado con
  `threading.Lock` por puerto para evitar colisiones.
"""

from __future__ import annotations

import asyncio
import json
import logging
import threading
from abc import ABC, abstractmethod
from typing import Any

import httpx

log = logging.getLogger("balansoft_ws.barrera")

ACCIONES_VALIDAS: tuple[str, ...] = ("open", "close")
TIEMPO_ESPERA_DEFECTO = 2.0


class BarreraHAL(ABC):
    """Interfaz abstracta del transporte de comandos/estado de la barrera."""

    @abstractmethod
    async def enviar_comando(self, action: str) -> bool:
        """Envía el comando de abrir o cerrar ('open' o 'close')."""

    @abstractmethod
    async def leer_estado(self) -> dict[str, Any] | None:
        """Lee el estado del dispositivo. None si no hay respuesta."""


class HttpBarreraHAL(BarreraHAL):
    """Barrera controlada por HTTP/REST."""

    def __init__(
        self,
        host: str,
        puerto: int = 8082,
        timeout: float = TIEMPO_ESPERA_DEFECTO,
        transport: httpx.AsyncBaseTransport | None = None,
        comando_abrir: str | None = None,
        comando_cerrar: str | None = None,
    ) -> None:
        self.host = host
        self.puerto = int(puerto or 8082)
        self.timeout = timeout
        self.transport = transport
        self.comando_abrir = comando_abrir
        self.comando_cerrar = comando_cerrar

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.puerto}"

    async def enviar_comando(self, action: str) -> bool:
        if action not in ACCIONES_VALIDAS:
            raise ValueError(f"Acción inválida para barrera: {action!r}")
        try:
            custom = self.comando_abrir if action == "open" else self.comando_cerrar
            payload: Any
            if custom and custom.strip().startswith("{"):
                try:
                    payload = json.loads(custom)
                except Exception:
                    payload = {"action": action, "custom": custom}
            elif custom:
                payload = {"action": action, "cmd": custom}
            else:
                payload = {"action": action}

            async with httpx.AsyncClient(
                timeout=self.timeout, transport=self.transport
            ) as client:
                resp = await client.post(
                    f"{self.base_url}/api/barrera", json=payload
                )
            return 200 <= resp.status_code < 300
        except (httpx.HTTPError, ValueError, OSError) as exc:
            log.debug("Barrera HTTP %s: comando fallido: %s", self.base_url, exc)
            return False

    async def leer_estado(self) -> dict[str, Any] | None:
        try:
            async with httpx.AsyncClient(
                timeout=self.timeout, transport=self.transport
            ) as client:
                resp = await client.get(f"{self.base_url}/api/barrera")
            if resp.status_code != 200:
                return None
            data = resp.json()
        except (httpx.HTTPError, ValueError, OSError) as exc:
            log.debug("Barrera HTTP %s: estado ilegible: %s", self.base_url, exc)
            return None
        return data if isinstance(data, dict) else None


class SerialBarreraHAL(BarreraHAL):
    """Barrera controlada por USB serie / RS-232."""

    _thread_locks: dict[str, threading.Lock] = {}
    _thread_locks_guard = threading.Lock()

    def __init__(
        self,
        port: str,
        baudrate: int = 9600,
        timeout: float = 1.0,
        comando_abrir: str | None = None,
        comando_cerrar: str | None = None,
    ) -> None:
        self.port = port
        self.baudrate = int(baudrate or 9600)
        self.timeout = timeout
        self.comando_abrir = comando_abrir
        self.comando_cerrar = comando_cerrar

    @classmethod
    def _lock_for(cls, port: str) -> threading.Lock:
        with cls._thread_locks_guard:
            lock = cls._thread_locks.get(port)
            if lock is None:
                lock = threading.Lock()
                cls._thread_locks[port] = lock
            return lock

    def _escribir_comando(self, action: str) -> bool:
        try:
            import serial
        except ImportError:
            log.warning("pyserial no está disponible para barrera serial %s", self.port)
            return False

        custom = self.comando_abrir if action == "open" else self.comando_cerrar
        if custom:
            raw = custom.encode("utf-8") + b"\n"
        else:
            raw = json.dumps({"action": action}).encode("utf-8") + b"\n"

        lock = self._lock_for(self.port)
        with lock:
            try:
                with serial.Serial(
                    self.port,
                    baudrate=self.baudrate,
                    timeout=self.timeout,
                    write_timeout=self.timeout,
                ) as ser:
                    ser.write(raw)
                    ser.flush()
                return True
            except (OSError, serial.SerialException) as exc:
                log.debug("Barrera serial %s: fallo al escribir: %s", self.port, exc)
                return False

    def _leer_estado(self) -> dict[str, Any] | None:
        try:
            import serial
        except ImportError:
            return None

        lock = self._lock_for(self.port)
        with lock:
            try:
                with serial.Serial(
                    self.port,
                    baudrate=self.baudrate,
                    timeout=self.timeout,
                    write_timeout=self.timeout,
                ) as ser:
                    raw = ser.readline()
            except (OSError, serial.SerialException) as exc:
                log.debug("Barrera serial %s: fallo al leer estado: %s", self.port, exc)
                return None

        if not raw:
            return None
        try:
            data = json.loads(raw.decode("utf-8", errors="ignore").strip())
        except ValueError:
            return {"raw": raw.decode("utf-8", errors="ignore").strip()}
        return data if isinstance(data, dict) else None

    async def enviar_comando(self, action: str) -> bool:
        if action not in ACCIONES_VALIDAS:
            raise ValueError(f"Acción inválida para barrera: {action!r}")
        return await asyncio.to_thread(self._escribir_comando, action)

    async def leer_estado(self) -> dict[str, Any] | None:
        return await asyncio.to_thread(self._leer_estado)


def get_barrera_hal(barrera: Any) -> BarreraHAL:
    """Construye el HAL de la barrera según su configuración de hardware."""
    protocolo = (getattr(barrera, "protocolo", None) or "http").lower()
    puerto_com = getattr(barrera, "puerto_com", None)
    ip = getattr(barrera, "ip_address", None)
    puerto_tcp = getattr(barrera, "puerto_tcp", None)
    baudrate = getattr(barrera, "baudrate", None) or 9600
    cmd_abrir = getattr(barrera, "comando_abrir", None)
    cmd_cerrar = getattr(barrera, "comando_cerrar", None)

    if protocolo == "serial" or (puerto_com and not ip):
        if not puerto_com:
            raise ValueError("La barrera serial no tiene puerto_com configurado")
        return SerialBarreraHAL(
            str(puerto_com),
            baudrate=int(baudrate),
            comando_abrir=cmd_abrir,
            comando_cerrar=cmd_cerrar,
        )

    if ip or protocolo == "http":
        return HttpBarreraHAL(
            str(ip or "127.0.0.1"),
            int(puerto_tcp or 8082),
            comando_abrir=cmd_abrir,
            comando_cerrar=cmd_cerrar,
        )

    raise ValueError(
        "La barrera no tiene configuración de hardware (ip_address/puerto_tcp o puerto_com)"
    )
