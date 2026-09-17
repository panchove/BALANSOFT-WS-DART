"""Sesiones persistentes de balanza (emparejamiento hasta cierre).

El HAL de ``scale_hal`` sabe leer un peso de un tiro (abre y cierra la conexión
en cada lectura). Para el emparejamiento que necesita la estación, este módulo
mantiene **una conexión viva por balanza** y un caché del último peso.

- ``ScaleSession`` abre la conexión una sola vez (``hal.conectar``), lee
  muestras en segundo plano (``hal.leer_muestra``) y reconecta con backoff si
  la balanza se cae. La conexión permanece hasta que la app/backend se cierra
  (``cerrar_todas``) o se cambia la configuración de la balanza.
- ``ScaleSessionManager`` mantiene un registro por ``id_balanza`` y entrega la
  misma sesión a ``/weighing/scale/{id}/live`` y ``/balanzas/{id}/probar``, de
  modo que ambos compartan la conexión en vez de abrir/cerrar por request.

La sesión es tolerante a HALs sin métodos persistentes (p. ej. dobles de test):
si ``conectar``/``leer_muestra``/``cerrar`` no existen, se usa
``read_weight`` como lectura de un tiro.
"""

from __future__ import annotations

import asyncio
import logging
from collections import deque
from dataclasses import dataclass
from datetime import UTC, datetime

from app.core.scale_hal import ScaleHAL, get_scale_hal

log = logging.getLogger("balansoft_ws.scale.session")


@dataclass
class MuestraPeso:
    """Última muestra válida leída de la balanza."""

    peso_kg: float
    estable: bool
    timestamp: datetime


async def _hal_conectar(hal: object) -> bool:
    fn = getattr(hal, "conectar", None)
    if fn is None:
        return True
    return bool(await fn())


async def _hal_leer(hal: object) -> tuple[float | None, str | None]:
    fn = getattr(hal, "leer_muestra", None)
    if fn is None:
        return await hal.read_weight(), None  # type: ignore[attr-defined]
    return await fn()


async def _hal_cerrar(hal: object) -> None:
    fn = getattr(hal, "cerrar", None)
    if fn is not None:
        await fn()


class ScaleSession:
    """Mantiene viva la conexión con una balanza y cachea su último peso."""

    def __init__(
        self,
        clave: str,
        hal: ScaleHAL,
        hardware: str,
        *,
        max_muestras: int = 30,
        tolerancia_kg: float = 0.5,
        pausa: float = 0.2,
    ):
        self.clave = clave
        self.hardware = hardware
        self._hal = hal
        self._muestras: deque[float] = deque(maxlen=max_muestras)
        self._ultimo: MuestraPeso | None = None
        self._conectado = False
        self._tolerancia_kg = tolerancia_kg
        self._pausa = pausa
        self._parar = asyncio.Event()
        self._primer_dato = asyncio.Event()
        self._tarea: asyncio.Task[None] | None = None

    # -- estado -----------------------------------------------------------

    @property
    def conectado(self) -> bool:
        """Hay conexión abierta y al menos una lectura válida reciente."""
        return self._conectado and self._ultimo is not None

    @property
    def peso_kg(self) -> float | None:
        return self._ultimo.peso_kg if self._ultimo else None

    @property
    def estable(self) -> bool:
        return self._ultimo.estable if self._ultimo else False

    @property
    def ultimo(self) -> MuestraPeso | None:
        return self._ultimo

    def coincide(self, balanza) -> bool:  # noqa: ANN001 - modelo ORM
        """True si la config de hardware de ``balanza`` es la de esta sesión."""
        return self.clave == _clave_balanza(balanza)

    # -- ciclo de vida ----------------------------------------------------

    def iniciar(self) -> None:
        if self._tarea is None:
            self._tarea = asyncio.create_task(self._run())

    async def esperar_primera(self, timeout: float = 2.0) -> None:
        """Espera a la primera lectura (o al timeout) tras crear la sesión."""
        try:
            await asyncio.wait_for(self._primer_dato.wait(), timeout=timeout)
        except TimeoutError:
            pass

    async def detener(self) -> None:
        self._parar.set()
        tarea = self._tarea
        self._tarea = None
        if tarea is not None:
            tarea.cancel()
            try:
                await asyncio.wait_for(tarea, timeout=3.0)
            except (asyncio.CancelledError, TimeoutError):
                pass
            except Exception as exc:  # noqa: BLE001 - la tarea no debe propagar
                log.debug("Error en tarea de sesión %s: %s", self.clave, exc)
        try:
            await _hal_cerrar(self._hal)
        except Exception as exc:  # noqa: BLE001 - cierre best-effort
            log.debug("Error cerrando sesión %s: %s", self.clave, exc)
        self._conectado = False

    # -- interno ----------------------------------------------------------

    def _registrar(self, peso: float, status: str | None) -> None:
        self._muestras.append(peso)
        self._ultimo = MuestraPeso(
            peso_kg=peso,
            estable=self._es_estable(status),
            timestamp=datetime.now(UTC),
        )
        if not self._primer_dato.is_set():
            self._primer_dato.set()

    def _es_estable(self, status: str | None) -> bool:
        if status is not None:
            return status == "stable"
        if len(self._muestras) >= 5:
            return max(self._muestras) - min(self._muestras) < self._tolerancia_kg
        # Sin datos suficientes ni campo `status`: asumir estable (como el HAL).
        return True

    async def _run(self) -> None:
        backoff = 0.5
        while not self._parar.is_set():
            try:
                ok = await _hal_conectar(self._hal)
                if not ok:
                    raise ConnectionError("no se pudo abrir la conexión")
                self._conectado = True
                backoff = 0.5
                while not self._parar.is_set():
                    peso, status = await _hal_leer(self._hal)
                    if peso is not None:
                        self._registrar(peso, status)
                    # Ceder siempre el turno: algunos HAL (o dobles de test)
                    # devuelven sin suspender y, sin esta pausa, el bucle
                    # bloquearía el event loop.
                    await asyncio.sleep(self._pausa)
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001 - reconectar ante cualquier fallo
                log.debug("Sesión %s: %s", self.clave, exc)
            finally:
                self._conectado = False
                try:
                    await _hal_cerrar(self._hal)
                except Exception:  # noqa: BLE001
                    pass
            if self._parar.is_set():
                break
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 5.0)


def _clave_balanza(balanza) -> str:  # noqa: ANN001 - modelo ORM
    """Identifica la config de hardware: (id, ip, puerto_tcp, puerto_com)."""
    return "|".join(
        [
            str(getattr(balanza, "id_balanza", "")),
            str(getattr(balanza, "ip_address", "") or ""),
            str(getattr(balanza, "puerto_tcp", "") or ""),
            str(getattr(balanza, "puerto_com", "") or ""),
        ]
    )


class ScaleSessionManager:
    """Registro de sesiones persistentes, una por balanza."""

    def __init__(self) -> None:
        self._sesiones: dict[str, ScaleSession] = {}
        self._lock = asyncio.Lock()

    async def obtener(self, balanza) -> ScaleSession:  # noqa: ANN001 - modelo ORM
        """Devuelve la sesión de ``balanza``, creándola si hace falta.

        Levanta ``ValueError`` si la balanza no tiene hardware configurado
        (el endpoint lo traduce a HTTP 400).
        """
        clave = _clave_balanza(balanza)
        creada = False
        async with self._lock:
            sesion = self._sesiones.get(clave)
            if sesion is None:
                hal = get_scale_hal(balanza)
                hardware = "tcp" if getattr(balanza, "ip_address", None) else "serial"
                sesion = ScaleSession(clave, hal, hardware)
                self._sesiones[clave] = sesion
                sesion.iniciar()
                creada = True
        if creada:
            await sesion.esperar_primera()
        return sesion

    async def cerrar(self, clave: str) -> None:
        async with self._lock:
            sesion = self._sesiones.pop(clave, None)
        if sesion is not None:
            await sesion.detener()

    async def cerrar_todas(self) -> None:
        async with self._lock:
            sesiones = list(self._sesiones.values())
            self._sesiones.clear()
        for sesion in sesiones:
            await sesion.detener()


_manager = ScaleSessionManager()


def get_scale_session_manager() -> ScaleSessionManager:
    return _manager
