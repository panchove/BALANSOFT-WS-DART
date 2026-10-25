"""HAL (Hardware Abstraction Layer) del semáforo de pesaje (torre N50-3).

El semáforo **no** es un perfil de báscula: es un actuador de salida. Esta app es
la dueña de la decisión (peso/estabilidad/boleto → LED) y el dispositivo solo
obedece comandos; el HAL es el transporte de esos comandos al equipo.

Contrato implementado (SPEC del simulador BSDD, §3 estado y §4 comandos), el
mismo JSON en todos los canales:

- **HTTP/REST** (Fase 2): ``POST http://host:8080/api/semaforo`` (comando) y
  ``GET http://host:8080/api/semaforo`` (estado publicado).
- **USB serie CDC-ACM** (Fase 3): ``/dev/bsdd_semaforo_acm`` — se escriben
  líneas JSON terminadas en ``\\n`` y se lee una línea de estado.

Comandos aceptados (forma canónica): ``{"color":"rojo","action":"on"|"off"|
"flash"}``, ``{"zumbador":"on"|"off"}``, ``{"all":"off"}``, ``{"reset":true}`` y
``{"automatico":true|false}``.

Se aceptan además los **atajos planos** por color del SPEC §5.6
(``{"rojo":true}``, ``{"verde":"flash"}``, ``{"rojo":false}``) y el alias ``luz``
de ``color``, de modo que el parser acepta las mismas formas que el propio
simulador BSDD (``comando_semaforo.dart``). Todos se normalizan a la forma
canónica antes de salir por el canal.

**Concurrencia serial:** igual que la báscula (``scale_hal``), el puerto serie
se protege con un ``threading.Lock`` por ruta aplicado **dentro del hilo** que
ejecuta pyserial, porque dos accesos concurrentes (comando + lectura de estado)
sobre el mismo pty dan el clásico *"device reports readiness to read but
returned no data"*.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import threading
import time
from abc import ABC, abstractmethod
from typing import Any

import httpx

log = logging.getLogger("balansoft_ws.semaforo")

#: Colores y acciones válidos del SPEC §4.
COLORES: tuple[str, ...] = ("rojo", "amarillo", "verde")
ACCIONES: tuple[str, ...] = ("on", "off", "flash")

#: Claves reconocidas del protocolo de comandos (incluye el alias ``luz`` y los
#: atajos planos por color del SPEC §5.6).
_CLAVES_COMANDO = {
    "color",
    "luz",
    "action",
    "zumbador",
    "all",
    "reset",
    "automatico",
    *COLORES,
}

TIEMPO_ESPERA_DEFECTO = 2.0


def _accion_atajo(valor: Any) -> str | None:
    """Traduce el valor de un atajo plano a ``"on"``/``"off"``/``"flash"``.

    Acepta el booleano (``{"rojo":true}`` → ``"on"``) y las acciones del SPEC
    (``{"verde":"flash"}``). Devuelve ``None`` si el valor no es válido.
    """
    if isinstance(valor, bool):
        return "on" if valor else "off"
    if isinstance(valor, str) and valor in ACCIONES:
        return valor
    return None


def normalizar_comando(payload: dict[str, Any]) -> dict[str, Any]:
    """Valida y limpia un comando del SPEC §4/§5.6.

    Devuelve solo las claves reconocidas, normalizando ``zumbador`` booleano a
    ``"on"``/``"off"``. Acepta el alias ``luz`` de ``color`` y los atajos planos
    por color (``{"rojo":true}``, ``{"verde":"flash"}``), que se traducen a
    ``color``+``action``. Levanta ``ValueError`` si no hay ninguna clave
    reconocida o si ``color``/``action``/``all`` traen un valor inválido.
    """
    if not isinstance(payload, dict):
        raise ValueError("el comando debe ser un objeto JSON")

    limpio: dict[str, Any] = {}

    color = payload.get("color")
    if color is None:
        color = payload.get("luz")
    if color is not None:
        if color not in COLORES:
            raise ValueError(f"color inválido: {color!r} (use {', '.join(COLORES)})")
        limpio["color"] = color

    if "color" not in limpio:
        # Atajos planos por color (SPEC §5.6): {"rojo":true}, {"verde":"flash"}.
        # El orden de precedencia replica el del parser de BSDD (enum de luces).
        for nombre in COLORES:
            valor = payload.get(nombre)
            if valor is None:
                continue
            accion = _accion_atajo(valor)
            if accion is None:
                raise ValueError(
                    f"{nombre} debe ser booleano o {'/'.join(ACCIONES)}"
                )
            limpio["color"] = nombre
            limpio["action"] = accion
            break

    action = payload.get("action")
    if action is not None:
        if action not in ACCIONES:
            raise ValueError(f"action inválida: {action!r} (use {', '.join(ACCIONES)})")
        limpio["action"] = action

    if "color" in limpio and "action" not in limpio:
        # Atajo: color sin action equivale a encenderlo fijo.
        limpio["action"] = "on"

    if "zumbador" in payload and payload["zumbador"] is not None:
        zumbador = payload["zumbador"]
        if isinstance(zumbador, bool):
            limpio["zumbador"] = "on" if zumbador else "off"
        elif zumbador in ("on", "off"):
            limpio["zumbador"] = zumbador
        else:
            raise ValueError("zumbador debe ser booleano o 'on'/'off'")

    if "all" in payload and payload["all"] is not None:
        if payload["all"] != "off":
            raise ValueError("all solo admite el valor 'off'")
        limpio["all"] = "off"

    if "reset" in payload and payload["reset"] is not None:
        limpio["reset"] = bool(payload["reset"])

    if "automatico" in payload and payload["automatico"] is not None:
        limpio["automatico"] = bool(payload["automatico"])

    if not limpio:
        raise ValueError(
            "comando vacío o sin claves reconocidas "
            f"({', '.join(sorted(_CLAVES_COMANDO))})"
        )
    return limpio


class SemaforoHAL(ABC):
    """Interfaz abstracta del transporte de comandos/estado del semáforo."""

    @abstractmethod
    async def enviar_comando(self, payload: dict[str, Any]) -> bool:
        """Envía un comando §4. Devuelve ``True`` si el equipo lo aceptó."""

    @abstractmethod
    async def leer_estado(self) -> dict[str, Any] | None:
        """Lee el estado publicado (SPEC §3). ``None`` si no hay respuesta."""


class HttpSemaforoHAL(SemaforoHAL):
    """Semáforo por HTTP/REST (simulador BSDD Fase 2 o equipo con API)."""

    def __init__(
        self,
        host: str,
        puerto: int = 8080,
        timeout: float = TIEMPO_ESPERA_DEFECTO,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self.host = host
        self.puerto = int(puerto or 8080)
        self.timeout = timeout
        #: Transporte alternativo (solo pruebas: ``httpx.MockTransport``).
        self.transport = transport

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.puerto}"

    async def enviar_comando(self, payload: dict[str, Any]) -> bool:
        try:
            comando = normalizar_comando(payload)
            async with httpx.AsyncClient(
                timeout=self.timeout, transport=self.transport
            ) as client:
                resp = await client.post(
                    f"{self.base_url}/api/semaforo", json=comando
                )
            return 200 <= resp.status_code < 300
        except (httpx.HTTPError, ValueError, OSError) as exc:
            log.debug("Semáforo HTTP %s: comando fallido: %s", self.base_url, exc)
            return False

    async def leer_estado(self) -> dict[str, Any] | None:
        try:
            async with httpx.AsyncClient(
                timeout=self.timeout, transport=self.transport
            ) as client:
                resp = await client.get(f"{self.base_url}/api/semaforo")
            if resp.status_code != 200:
                return None
            data = resp.json()
        except (httpx.HTTPError, ValueError, OSError) as exc:
            log.debug("Semáforo HTTP %s: estado ilegible: %s", self.base_url, exc)
            return None
        return data if isinstance(data, dict) else None


class SerialSemaforoHAL(SemaforoHAL):
    """Semáforo por USB serie CDC-ACM (``/dev/bsdd_semaforo_acm``).

    Escribe líneas JSON + ``\\n`` y lee una línea de estado con timeout. El
    acceso al puerto se serializa con un ``threading.Lock`` por ruta.
    """

    _thread_locks: dict[str, threading.Lock] = {}
    _thread_locks_guard = threading.Lock()

    def __init__(
        self,
        port: str,
        baudrate: int = 9600,
        timeout: float = 1.0,
    ) -> None:
        self.port = port
        self.baudrate = int(baudrate or 9600)
        self.timeout = timeout

    @classmethod
    def _lock_for(cls, port: str) -> threading.Lock:
        with cls._thread_locks_guard:
            lock = cls._thread_locks.get(port)
            if lock is None:
                lock = threading.Lock()
                cls._thread_locks[port] = lock
            return lock

    def _escribir_comando(self, comando: dict[str, Any]) -> bool:
        """Abre, escribe una línea JSON y cierra (en hilo bloqueante)."""
        try:
            import serial  # dependencia opcional; validada aquí
        except ImportError:
            log.error("pyserial no instalado; imposible comandar %s", self.port)
            return False
        if self.port.startswith("/") and not os.path.exists(self.port):
            return False

        linea = (json.dumps(comando, ensure_ascii=False) + "\n").encode("utf-8")
        lock = self._lock_for(self.port)
        with lock:
            for _ in range(3):
                try:
                    with serial.Serial(
                        self.port, self.baudrate, timeout=self.timeout
                    ) as ser:
                        ser.write(linea)
                        ser.flush()
                    return True
                except serial.SerialException as exc:
                    msg = str(exc).lower()
                    if "no such file" in msg or "file not found" in msg or "errno 2" in msg:
                        return False
                    if "readiness" in msg or "could not open" in msg or "busy" in msg:
                        time.sleep(0.15)
                        continue
                    log.warning("Comando serial fallido en %s: %s", self.port, exc)
                    return False
                except Exception as exc:  # noqa: BLE001
                    log.warning("Comando serial fallido en %s: %s", self.port, exc)
                    return False
        return False

    def _leer_estado(self) -> dict[str, Any] | None:
        try:
            import serial
        except ImportError:
            return None
        if self.port.startswith("/") and not os.path.exists(self.port):
            return None

        lock = self._lock_for(self.port)
        with lock:
            try:
                with serial.Serial(
                    self.port, self.baudrate, timeout=self.timeout
                ) as ser:
                    raw = ser.readline()
            except Exception as exc:  # noqa: BLE001
                log.debug("Lectura de estado fallida en %s: %s", self.port, exc)
                return None
        if not raw:
            return None
        try:
            data = json.loads(raw.decode("utf-8", errors="ignore").strip())
        except ValueError:
            return None
        return data if isinstance(data, dict) else None

    async def enviar_comando(self, payload: dict[str, Any]) -> bool:
        try:
            comando = normalizar_comando(payload)
        except ValueError as exc:
            log.debug("Comando inválido para %s: %s", self.port, exc)
            return False
        return await asyncio.to_thread(self._escribir_comando, comando)

    async def leer_estado(self) -> dict[str, Any] | None:
        return await asyncio.to_thread(self._leer_estado)


def get_semaforo_hal(semaforo: Any) -> SemaforoHAL:
    """Construye el HAL del semáforo según su configuración de hardware.

    Prioridad: protocolo ``serial``/``puerto_com`` → HTTP (``ip_address``/
    ``puerto_tcp``, por defecto ``127.0.0.1:8080``). Sin configuración levanta
    ``ValueError`` (el endpoint responde 400).
    """
    protocolo = (getattr(semaforo, "protocolo", None) or "http").lower()
    puerto_com = getattr(semaforo, "puerto_com", None)
    ip = getattr(semaforo, "ip_address", None)
    puerto_tcp = getattr(semaforo, "puerto_tcp", None)
    baudrate = getattr(semaforo, "baudrate", None) or 9600

    if protocolo == "serial" or (puerto_com and not ip):
        if not puerto_com:
            raise ValueError(
                "El semáforo serial no tiene puerto_com configurado"
            )
        return SerialSemaforoHAL(str(puerto_com), baudrate=int(baudrate))

    if ip or protocolo == "http":
        return HttpSemaforoHAL(str(ip or "127.0.0.1"), int(puerto_tcp or 8080))

    raise ValueError(
        "El semáforo no tiene configuración de hardware (ip_address/puerto_tcp "
        "o puerto_com)"
    )
