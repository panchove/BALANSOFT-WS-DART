"""HAL (Hardware Abstraction Layer) de balanza (B7 / REQ-NF-ARQ-004).

Permite leer el peso en vivo desde hardware real (serial/RS-232) o desde un
servidor TCP (p. ej. el simulador BSDD que emite líneas JSON
``{"weight_kg":..., "status":"stable"}``).

El backend no están conectado a hardware de forma persistente: cada lectura
abre/cierra la conexión. ``get_scale_hal`` decide la implementación según la
configuración de la balanza (``puerto_com`` vs ``ip_address``/``puerto_tcp``).
"""

from __future__ import annotations

import asyncio
import json
import logging
from abc import ABC, abstractmethod

log = logging.getLogger("balansoft_ws.scale")


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


class SerialScaleHAL(ScaleHAL):
    """Balanza serial (RS-232/USB). Requiere el paquete ``pyserial``."""

    def __init__(self, port: str, baudrate: int = 9600, timeout: float = 1):
        self.port = port
        self.baudrate = baudrate
        self.timeout = timeout

    def _parse_line(self, line: str) -> float | None:
        t = line.strip()
        if not t:
            return None
        try:
            return float(t.split()[-1].replace(",", "."))
        except (TypeError, ValueError):
            return None

    async def read_weight(self) -> float | None:
        try:
            import serial  # dependencia opcional (pyserial)

            return await asyncio.to_thread(self._read_once, serial)
        except ImportError:
            log.error("pyserial no instalado; imposible leer balanza serial %s", self.port)
        except Exception as exc:  # noqa: BLE001 - el HAL nunca debe romper la API
            log.warning("Lectura serial fallida en %s: %s", self.port, exc)
        return None

    def _read_once(self, serial) -> float | None:  # type: ignore[no-untyped-def]
        with serial.Serial(self.port, self.baudrate, timeout=self.timeout) as ser:
            line = ser.readline().decode("ascii", errors="ignore")
        return self._parse_line(line)

    async def is_stable(
        self, duration_seconds: int = 3, tolerance_kg: float = 0.5
    ) -> bool:
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
    ):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.tolerance_kg = tolerance_kg

    async def read_weight(self) -> float | None:
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(self.host, self.port), timeout=self.timeout
            )
            try:
                writer.write(b'{"action":"get_state"}\n')
                await writer.drain()
                data = await asyncio.wait_for(reader.readline(), timeout=self.timeout)
            finally:
                writer.close()
                await writer.wait_closed()
            if not data:
                return None
            payload = json.loads(data.decode(errors="ignore"))
            peso = payload.get("weight_kg")
            return float(peso) if peso is not None else None
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