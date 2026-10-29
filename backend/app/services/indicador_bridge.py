"""Puente de datos: báscula → indicador serie (ESP32).

Este servicio se ejecuta en segundo plano por cada vínculo activo
(VinculoBalanzaIndicador.activo = True) y se encarga de:
1. Abrir y mantener el puerto serie del indicador.
2. Leer el peso de la báscula vía ScaleSession.
3. Formatear la trama como: ST,GS,+ {peso_float:.1f} kg\r\n
4. Escribir en el puerto serie del indicador.
5. Reconectar automáticamente si se pierde el puerto.
6. Logs de depuración en consola.

Usa los mismos patrones de concurrencia que VinculoManager y
IndicadorSerialHAL (locks threading por puerto, asyncio.to_thread).
"""

from __future__ import annotations

import asyncio
import logging
import threading
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.indicador_hal import IndicadorHAL, get_indicador_hal
from app.core.scale_session import get_scale_session_manager
from app.models import Balanza, Indicador, VinculoBalanzaIndicador

log = logging.getLogger("balansoft_ws.indicador_bridge")

# pyserial is optional; import here to avoid hard dependency at module level
# The actual import inside methods handles the optional dependency
try:
    import serial  # noqa: F401
except ImportError:  # pragma: no cover
    serial = None  # type: ignore

# Formato de trama exacto solicitado: ST,GS,+ {peso_float:.1f} kg\r\n
TRAMA_FORMATO = "ST,GS,+ {:.1f} kg\r\n"


class IndicadorBridge:
    """Puente de datos para un solo vínculo balanza-indicador.

    Responsabilidades:
    - Gestionar el ciclo de vida del puerto serie del indicador.
    - Leer pesos de la báscula sesionada.
    - Formatear y enviar trámite al indicador.
    - Reconectar automáticamente ante desconexiones.
    """

    def __init__(self, id_vinculo: UUID, id_empresa: UUID):
        self.id_vinculo = str(id_vinculo)
        self.id_empresa = id_empresa
        self._task: asyncio.Task | None = None
        self._stop_event = asyncio.Event()
        self._puerto_serial: str | None = None
        self._ser: serial.Serial | None = None  # type: ignore
        self._lock = threading.Lock()
        self._ultimo_peso: float | None = None
        self._hal_ind: IndicadorHAL | None = None
        self._balanza = None  # type: ignore
        self._indicador = None  # type: ignore
        self._mgr = None  # type: ignore

    # ------------------------------------------------------------------
    # Ciclo de vida
    # ------------------------------------------------------------------

    async def iniciar(self, db: AsyncSession) -> None:
        """Iniciar el puente para este vínculo. Llamar al arranque o al activar enlace."""
        if self._task is not None and not self._task.done():
            return
        self._stop_event = asyncio.Event()
        # Cargar configuración del vínculo desde la BD
        await self._cargar_desde_db(db)
        if self._balanza is None or self._indicador is None:
            log.warning("No se pudo cargar hardware para vínculo %s", self.id_vinculo)
            return
        self._task = asyncio.create_task(self._loop())
        log.info("Puente indicador iniciado para vínculo %s", self.id_vinculo)

    async def detener(self) -> None:
        """Detener el puente y cerrar el puerto serie."""
        self._stop_event.set()
        tarea = self._task
        self._task = None
        if tarea is not None:
            try:
                await asyncio.wait_for(tarea, timeout=3.0)
            except (asyncio.CancelledError, TimeoutError):
                try:
                    tarea.cancel()
                except Exception:
                    pass
        # Cerrar puerto serie
        await self._cerrar_puerto()
        log.info("Puente indicador detenido para vínculo %s", self.id_vinculo)

    async def _cerrar_puerto(self) -> None:
        """Cerrar el puerto serie de forma segura."""
        with self._lock:
            if self._ser is not None:
                try:
                    if self._ser.is_open:
                        self._ser.flush()
                        self._ser.close()
                except Exception:
                    pass
                self._ser = None
                self._puerto_serial = None

    async def _cargar_desde_db(self, db: AsyncSession) -> None:
        """Cargar balanza, indicador y manager desde la base de datos."""
        try:
            # Cargar vínculo
            res_v = await db.execute(
                select(VinculoBalanzaIndicador).where(VinculoBalanzaIndicador.id_vinculo == UUID(self.id_vinculo))
            )
            vinculo = res_v.scalar_one_or_none()
            if vinculo is None or not vinculo.activo:
                log.warning("Vínculo %s no encontrado o inactivo", self.id_vinculo)
                return

            # Cargar báscula
            res_b = await db.execute(
                select(Balanza).where(
                    Balanza.id_balanza == vinculo.id_bascula,
                    Balanza.id_empresa == self.id_empresa
                )
            )
            self._balanza = res_b.scalar_one_or_none()
            if self._balanza is None:
                log.warning("Vínculo %s: báscula no encontrada", self.id_vinculo)
                return

            # Cargar indicador
            res_i = await db.execute(
                select(Indicador).where(
                    Indicador.id_indicador == vinculo.id_indicador,
                    Indicador.id_empresa == self.id_empresa
                )
            )
            self._indicador = res_i.scalar_one_or_none()
            if self._indicador is None:
                log.warning("Vínculo %s: indicador no encontrado", self.id_vinculo)
                return

            # Obtener manager de sesiones
            self._mgr = get_scale_session_manager()

            # Obtener HAL del indicador
            self._hal_ind = get_indicador_hal(self._indicador)
            self._puerto_serial = self._indicador.puerto_com or self._indicador.ip_address or ""

            log.info(
                "Vínculo %s: báscula='%s' (puerto=%s) -> indicador='%s' (proto=%s, puerto=%s)",
                self.id_vinculo,
                self._balanza.descripcion,
                self._balanza.puerto_com,
                self._indicador.descripcion,
                self._indicador.protocolo,
                self._puerto_serial,
            )
        except Exception as exc:
            log.error("Error cargando configuración para vínculo %s: %s", self.id_vinculo, exc)

    # ------------------------------------------------------------------
    # Loop principal
    # ------------------------------------------------------------------

    async def _loop(self) -> None:
        """Bucle principal: leer peso y enviar al indicador."""
        log.info("Bucle puente indicador comenzado para vínculo %s", self.id_vinculo)

        try:
            ses = None

            while not self._stop_event.is_set():
                try:
                    # Si no hay sesión o no está conectada, intentar obtenerla
                    if ses is None or not ses.conectado:
                        try:
                            ses = await self._mgr.obtener(self._balanza)
                            if ses is not None:
                                ses.iniciar()
                                # No esperamos el primer dato aquí, se obtendrá en la primera iteración
                        except Exception as exc:
                            log.debug("Error obteniendo sesión de báscula: %s", exc)
                            await asyncio.sleep(1.0)
                            continue

                    # Leer peso actual
                    peso_actual = ses.peso_kg if ses is not None else None

                    # Solo enviar si el peso cambió
                    if peso_actual is not None and peso_actual != self._ultimo_peso:
                        self._ultimo_peso = peso_actual

                        # Formatear trama exacta solicitada
                        trama = TRAMA_FORMATO.format(peso_actual)

                        # Log de depuración (matching the requested format)
                        puerto_mostrar = self._puerto_serial or "/dev/ttyUSB0"
                        print(f"Indicador: Enviando {trama.strip()} a {puerto_mostrar}")

                        # Enviar al indicador
                        await self._enviar_a_indicador(trama)

                    # Pausa breve entre lecturas
                    await asyncio.sleep(0.5)

                except asyncio.CancelledError:
                    raise
                except Exception as exc:
                    log.debug("Error en bucle puente: %s", exc)
                    await asyncio.sleep(1.0)

        except asyncio.CancelledError:
            log.info("Bucle puente indicador cancelado para vínculo %s", self.id_vinculo)
        except Exception as exc:
            log.error("Error fatal en bucle puente %s: %s", self.id_vinculo, exc)
        finally:
            await self._cerrar_puerto()
            log.info("Bucle puente indicador finalizado para vínculo %s", self.id_vinculo)

    # ------------------------------------------------------------------
    # Envío al indicador
    # ------------------------------------------------------------------

    async def _enviar_a_indicador(self, trama: str) -> None:
        """Enviar trama formateada al indicador mediante pyserial directo."""
        import serial

        with self._lock:
            puerto = self._puerto_serial or "/dev/ttyUSB0"

            # Asegurar que el puerto esté abierto
            if self._ser is None or not self._ser.is_open:
                try:
                    self._ser = serial.Serial(puerto, 9600, timeout=1)
                    log.info("Puerto serie abierto: %s a 9600", puerto)
                except serial.SerialException as exc:
                    log.error("No se pudo abrir puerto serie %s: %s", puerto, exc)
                    return

            try:
                self._ser.write(trama.encode("utf-8"))
                self._ser.flush()

                # Log de depuración (matching the requested format)
                print(f"Indicador: Enviando {trama.strip()} a {puerto}")

            except serial.SerialException as exc:
                log.error("Excepción serial enviando al indicador: %s", exc)
                # Marcar puerto como inválido para reconexión en el próximo ciclo
                self._ser = None
            except Exception as exc:
                log.debug("Error inesperado enviando al indicador: %s", exc)


class VinculoManager:
    """Manager para vinculos balanza-indicador.

    Uses IndicadorBridge per active link to send weight data to the indicator serial port.
    """

    def __init__(self):
        self._bridges: dict[str, IndicadorBridge] = {}
        self._tasks: dict[str, asyncio.Task] = {}
        self._stop: dict[str, asyncio.Event] = {}
        self._estado: dict[str, str] = {}

    async def iniciar(self, db: AsyncSession, id_empresa: UUID, vinculo: VinculoBalanzaIndicador):
        key = str(vinculo.id_vinculo)
        if key in self._tasks and not self._tasks[key].done():
            return
        # Crear y almacenar el puente para este vínculo
        bridge = IndicadorBridge(UUID(key), id_empresa)
        self._bridges[key] = bridge
        self._tasks[key] = asyncio.create_task(bridge.iniciar(db))
        log.info("Vinculo %s: puente iniciado", key)

    async def detener(self, id_vinculo: UUID):
        key = str(id_vinculo)
        # Detener el puente associated
        bridge = self._bridges.get(key)
        if bridge is not None:
            await bridge.detener()
            self._bridges.pop(key, None)
        ev = self._stop.get(key)
        if ev:
            ev.set()
        t = self._tasks.get(key)
        if t:
            try:
                await asyncio.wait_for(t, timeout=2.0)
            except Exception:
                try:
                    t.cancel()
                except Exception:
                    pass
        self._tasks.pop(key, None)
        self._stop.pop(key, None)
        self._estado.pop(key, None)

    async def detener_todos(self):
        for key in list(self._tasks.keys()):
            try:
                ev = self._stop.get(key)
                if ev:
                    ev.set()
                t = self._tasks.get(key)
                if t and not t.done():
                    t.cancel()
            except Exception:
                pass
        self._tasks.clear()
        self._stop.clear()
        self._estado.clear()
        # Detener todos los puentes
        for key in list(self._bridges.keys()):
            try:
                bridge = self._bridges.get(key)
                if bridge is not None:
                    await bridge.detener()
            except Exception:
                pass
        self._bridges.clear()

    async def estado(self, id_vinculo: UUID) -> str:
        key = str(id_vinculo)
        return self._estado.get(key, "inactivo")

    async def iniciar_vinculo(self, db: AsyncSession, id_empresa: UUID, vinculo: VinculoBalanzaIndicador):
        """Alias para compatibilidad: iniciar el puente para un vínculo existente."""
        await self.iniciar(db, id_empresa, vinculo)


VINCULO_MGR = VinculoManager()