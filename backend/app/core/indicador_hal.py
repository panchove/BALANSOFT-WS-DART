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
        # CORRECCIÓN PYREFLY: Quitamos el int() innecesario en la línea 27
        self.baudrate = baudrate or 9600 
        self.timeout = float(timeout or 1.0)
        self.trama_formato = trama_formato
        self._ser = None

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
        
        print(f"[HAL] Intentando escribir en {self.puerto} el peso {peso_kg}")
        
        lock = self._lock_for(self.puerto)
        with lock:
            try:
                if self._ser is None or not self._ser.is_open:
                    self._ser = serial.Serial()
                    self._ser.port = self.puerto
                    self._ser.baudrate = self.baudrate
                    self._ser.timeout = self.timeout
                    self._ser.dsrdtr = False
                    self._ser.rtscts = False
                    self._ser.open()
                    self._ser.dtr = False
                    self._ser.rts = False
                    print(f"[HAL] Puerto {self.puerto} abierto")

                data = self._formatear_trama(peso_kg, trama).encode("ascii", errors="ignore")
                self._ser.write(data)
                self._ser.flush()
                print(f"[HAL] Enviado con éxito: {data}")
                return True
            except Exception as exc:
                print(f"[HAL] ERROR al escribir: {exc}")
                log.debug("indicador serial write fallo %s: %s", self.puerto, exc)
                try:
                    if self._ser and self._ser.is_open:
                        self._ser.close()
                except Exception:
                    pass
                self._ser = None
                return False

    async def probar_conexion(self) -> dict:
        """
        Envía un peso de prueba (0.00) y espera unos milisegundos a ver si
        el dispositivo responde (ej. la ESP32 devuelve "OK").
        """
        try:
            import serial
        except ImportError:
            return {"conectado": False, "detalle": "pyserial no instalado"}

        if not self.puerto:
            return {"conectado": False, "detalle": "Puerto no configurado"}

        # Ejecutamos en un hilo para no bloquear el event loop de FastAPI
        return await asyncio.to_thread(self._probar_locked)

    def _probar_locked(self) -> dict:
        import serial

        lock = self._lock_for(self.puerto)
        with lock:
            try:
                # Usamos un bloque with para que se cierre automáticamente al terminar
                with serial.Serial() as ser:
                    ser.port = self.puerto
                    ser.baudrate = self.baudrate
                    ser.timeout = 1.5 # Damos 1.5s de margen para que la ESP32 responda
                    ser.dsrdtr = False
                    ser.rtscts = False
                    ser.open()
                    ser.dtr = False
                    ser.rts = False
                    
                    # Enviamos un peso de prueba
                    ser.write(b"000.00\n")
                    ser.flush()
                    
                    # Leemos lo que responda el dispositivo
                    respuesta = ser.readline().decode('ascii', errors='ignore').strip()
                    
                    if respuesta:
                        return {
                            "conectado": True, 
                            "recibido": respuesta,
                            "detalle": "Dispositivo respondió correctamente"
                        }
                    else:
                        return {
                            "conectado": True, 
                            "recibido": "(sin respuesta)",
                            "detalle": "Puerto abierto, pero no hubo eco"
                        }
            except Exception as exc:
                return {"conectado": False, "detalle": str(exc)}


class IndicadorHttpHAL(IndicadorHAL):
    def __init__(self, ip: str, puerto: int = 80, ruta: str = "/api/peso", usar_https: bool = False, timeout: float = 2.0):
        self.ip = ip or "127.0.0.1"
        # CORRECCIÓN PYREFLY: Quitamos el int() innecesario en la línea 107
        self.puerto = puerto or 80
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