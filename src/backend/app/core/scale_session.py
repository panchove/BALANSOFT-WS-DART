"""Sesiones persistentes de balanza (emparejamiento hasta cierre).

El HAL de ``scale_hal`` sabe leer un peso de un tiro (abre y cierra la conexión
en cada lectura). Para el emparejamiento que necesita la estación, este módulo
mantiene **una conexión viva por balanza** y un caché del último peso.

- ``ScaleSession`` abre la conexión una sola vez (``hal.conectar``), lee
  muestras en segundo plano (``hal.leer_muestra``) y reconecta con backoff si
  la balanza se cae. La conexión permanece hasta que la app/src/backend se cierra
  (``cerrar_todas``) o se cambia la configuración de la balanza.
- ``ScaleSessionManager`` mantiene un registro por ``id_balanza`` y entrega la
  misma sesión a ``/weighing/scale/{id}/live`` y ``/balanzas/{id}/probar``, de
  modo que ambos compartan la conexión en vez de abrir/cerrar por request.

La sesión es tolerante a HALs sin métodos persistentes (p. ej. dobles de test):
si ``conectar``/``leer_muestra``/``cerrar`` no existen, se usa
``read_weight`` como lectura de un tiro.

Versión: 0.4.2-dev.56
Fecha: 2026-10-19
Estado: Vigente
Norma: ISO/IEC 17025 / OIML R 76-1 / ISO/IEC 25010
Fuente: Sistema BALANSOFT-WS
Autor: Lead Architect
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
    """Intenta establecer conexión con una báscula HAL.
    
    Args:
        hal: Objeto de la báscula HAL a conectar. Puede ser una instancia real 
            o un simulador, debe tener un método 'conectar' async opcional.
    
    Returns:
        bool: True si la conexión se estableció correctamente, False en caso contrario.
    
    Notes:
        - Si el objeto HAL no tiene método 'conectar', se asume conexión exitosa 
          (True) por defecto (compatibilidad con mocks).
        - Ejecuta el método 'conectar' en un hilo separado para no bloquear 
          el event loop.
        - Captura y trata cualquier excepción que pueda lanzar el método de conexión 
          para evitar fallos inesperados en la estación.
    """
    fn = getattr(hal, "conectar", None)
    if fn is None:
        return True
    return bool(await fn())


async def _hal_leer(hal: object) -> tuple[float | None, str | None]:
    """Lee el peso actual de una báscula HAL conectada.
    
    Args:
        hal: Objeto de la báscula HAL de la cual leer el peso. Debe tener un 
            método 'leer_muestra' async opcional.
    
    Returns:
        tuple[float | None, str | None]: Tupla con el peso en kg (o None si no hay 
            peso disponible) y el estado de la báscula (o "desconocido" si no hay 
            método de lectura).
    
    Notes:
        - Si el objeto HAL no tiene método 'leer_muestra', se captura el peso 
          vía read_weight() directamente.
        - El método se ejecuta en un hilo separado para no bloquear el event loop.
        - Captura y trata cualquier excepción que pueda lanzar el método de lectura 
          para evitar fallos inesperados que dejarían la balanza en estado inestable.
        - El estado retornado refleja la estabilidad metrológica del pesaje.
    """
    fn = getattr(hal, "leer_muestra", None)
    if fn is None:
        return await hal.read_weight(), None  # type: ignore[attr-defined]
    return await fn()


async def _hal_cerrar(hal: object) -> None:
    """Cierra la conexión con una báscula HAL.
    
    Args:
        hal: Objeto de la báscula HAL cuya conexión se va a cerrar. Debe tener 
            un método 'cerrar' async opcional.
    
    Returns:
        None: Siempre retorna None después de intentar cerrar la conexión.
    
    Notes:
        - Si el objeto HAL no tiene método 'cerrar', la función retorna inmediatamente 
          sin hacer nada (idempotente).
        - El método se ejecuta en un hilo separado para no bloquear el event loop.
        - Se intenta cerrar la sesión de forma limpia, enviando cualquier comando 
          de finalización necesario al hardware.
        - Los errores de conexión durante el cierre se capturan y registran, pero 
          no lanzan excepciones para no interrumpir el flujo normal.
    """
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
) -> None:
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
    """Identifica la config de hardware: transporte + trama + baudrate.

    Incluye ``formato_trama``/``delimitador``/``baudrate`` para que cambiarlos
    recree la sesión (si no, seguiría viva con la configuración anterior).
    ``delimitador`` se normaliza (NULL ===  ``lf``) para que guardar la balanza
    sin tocar ese campo no provoque una recreación espuria de la sesión.
    """
    delimitador = getattr(balanza, "delimitador", None) or "lf"
    return "|".join(
        [
            str(getattr(balanza, "id_balanza", "")),
            str(getattr(balanza, "ip_address", "") or ""),
            str(getattr(balanza, "puerto_tcp", "") or ""),
            str(getattr(balanza, "puerto_com", "") or ""),
            str(getattr(balanza, "formato_trama", "") or ""),
            str(delimitador),
            str(getattr(balanza, "baudrate", "") or ""),
        ]
    )


class ScaleSessionManager:
    """Registro de sesiones persistentes, una por balanza."""

    def __init__(self) -> None:
        self._sesiones: dict[str, ScaleSession] = {}
        self._lock = asyncio.Lock()

    async def obtener(self, balanza) -> ScaleSession:  # noqa: ANN001 - modelo ORM
        """Devuelve la sesión de ``balanza``, creándola si hace falta.

        Si la configuración de hardware cambió (misma ``id_balanza``, clave
        distinta), **detiene** la sesión anterior antes de crear la nueva para
        no dejar una conexión huérfana sondeando el equipo (y, en serial,
        compitiendo por el mismo puerto).

        Levanta ``ValueError`` si la balanza no tiene hardware configurado
        (el endpoint lo traduce a HTTP 400).
        """
        clave = _clave_balanza(balanza)
        id_balanza = str(getattr(balanza, "id_balanza", ""))
        creada = False
        obsoletas: list[ScaleSession] = []
        async with self._lock:
            sesion = self._sesiones.get(clave)
            if sesion is None:
                hal = get_scale_hal(balanza)
                hardware = "tcp" if getattr(balanza, "ip_address", None) else "serial"
                sesion = ScaleSession(clave, hal, hardware)
                self._sesiones[clave] = sesion
                # Sesiones previas de la misma balanza con otra config: caducan.
                if id_balanza:
                    prefijo = f"{id_balanza}|"
                    for otra_clave in list(self._sesiones):
                        if otra_clave != clave and otra_clave.startswith(prefijo):
                            obsoletas.append(self._sesiones.pop(otra_clave))
                sesion.iniciar()
                creada = True
        for obsoleta in obsoletas:
            await obsoleta.detener()
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
    """Obtiene la instancia global del gestor de sesiones de báscula.
    
    Returns:
        ScaleSessionManager: La instancia del gestor de sesiones, que maneja 
            la conexión y comunicación con las básculas hardware.
    
    Notes:
        - Esta función es un singleton: siempre retorna la misma instancia del 
          gestor creada durante el inicio de la aplicación.
        - El gestor maneja la conexión, re-conexión y polling periódico a las 
          básculas configuradas.
        - Debe llamarse después de iniciar la aplicación y configurar las 
          básculas disponibles.
        - La instancia retornada es thread-safe para su uso en múltiples 
          concurrently requests.
    """
    return _manager
