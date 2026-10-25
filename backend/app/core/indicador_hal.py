from __future__ import annotations

import asyncio
import logging
import os
import threading
from abc import ABC, abstractmethod
from typing import Any

import httpx

log = logging.getLogger("balansoft_ws.indicador")


class IndicadorHAL(ABC):
    @abstractmethod
    async def enviar_peso(self, peso_kg: float | None, trama: str | None = None, status: str | None = None) -> bool:
        raise NotImplementedError


class IndicadorSerialHAL(IndicadorHAL):
    _locks: dict[str, threading.Lock] = {}
    _guard = threading.Lock()

    def __init__(self, puerto: str, baudrate: int = 9600, timeout: float = 1.0, trama_formato: str = "st_gs"):
        self.puerto = puerto or ""
        self.baudrate = int(baudrate or 9600)
        self.timeout = float(timeout or 1.0)
        self.trama_formato = trama_formato

    @classmethod
    def _lock_for(cls, puerto: str) -> threading.Lock:
        with cls._guard:
            lock = cls._locks.get(puerto)
            if lock is None:
                lock = threading.Lock()
                cls._locks[puerto] = lock
            return lock

    def _formatear_trama(self, peso_kg: float | None, trama: str | None) -> str:
        if trama and trama.strip():
            if trama.endswith("\n") or trama.endswith("\r"):
                return trama
            return trama.strip() + "\n"
        if peso_kg is None:
            return "ST,GS,------\n"
        try:
            s = f"{peso_kg:+07.2f}"
        except Exception:
            s = "+00000.00"
        return f"ST,GS,{s} kg\n"

    async def enviar_peso(self, peso_kg: float | None, trama: str | None = None, status: str | None = None) -> bool:
        try:
            import serial  # noqa: F401
        except Exception as exc:
            log.warning("pyserial no instalado para indicador serial: %s", exc)
            return False
        return await asyncio.to_thread(self._write_locked, peso_kg, trama)

    def _write_locked(self, peso_kg: float | None, trama: str | None) -> bool:
        import serial

        if not self.puerto:
            return False
        if self.puerto.startswith("/") and not os.path.exists(self.puerto):
            return False
        lock = self._lock_for(self.puerto)
        with lock:
            try:
                with serial.Serial(self.puerto, self.baudrate, timeout=self.timeout) as ser:
                    data = self._formatear_trama(peso_kg, trama).encode("ascii", errors="ignore")
                    ser.write(data)
                    try:
                        ser.flush()
                    except Exception:
                        pass
                return True
            except Exception as exc:
                log.debug("indicador serial write fallo %s: %s", self.puerto, exc)
                return False


class IndicadorHttpHAL(IndicadorHAL):
    def __init__(self, ip: str, puerto: int = 80, ruta: str = "/api/peso", usar_https: bool = False, timeout: float = 2.0):
        self.ip = ip or "127.0.0.1"
        self.puerto = int(puerto or 80)
        self.ruta = ruta or "/api/peso"
        scheme = "https" if usar_https else "http"
        if (scheme == "http" and self.puerto == 80) or (scheme == "https" and self.puerto == 443):
            self.base = f"{scheme}://{self.ip}{self.ruta}"
        else:
            self.base = f"{scheme}://{self.ip}:{self.puerto}{self.ruta}"
        self.timeout = float(timeout or 2.0)

    async def enviar_peso(self, peso_kg: float | None, trama: str | None = None, status: str | None = None) -> bool:
        payload: dict[str, Any] = {"peso_kg": peso_kg, "status": status}
        if trama:
            payload["trama"] = trama
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                resp = await client.post(self.base, json=payload)
                return resp.status_code < 400
        except Exception as exc:
            log.debug("indicador http post fallo %s: %s", self.base, exc)
            return False


def get_indicador_hal(indicador) -> IndicadorHAL:  # noqa: ANN001
    proto = (getattr(indicador, "protocolo", None) or "").lower()
    if proto == "serial":
        return IndicadorSerialHAL(
            puerto=getattr(indicador, "puerto_com") or "",
            baudrate=int(getattr(indicador, "baudrate") or 9600),
        )
    if proto == "http":
        return IndicadorHttpHAL(
            ip=getattr(indicador, "ip_address") or "127.0.0.1",
            puerto=int(getattr(indicador, "puerto_tcp") or 80),
        )
    if getattr(indicador, "puerto_com"):
        return IndicadorSerialHAL(puerto=indicador.puerto_com, baudrate=getattr(indicador, "baudrate") or 9600)
    return IndicadorHttpHAL(ip=getattr(indicador, "ip_address") or "127.0.0.1", puerto=getattr(indicador, "puerto_tcp") or 80)
