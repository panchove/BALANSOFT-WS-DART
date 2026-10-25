"""Servicio del semáforo de pesaje: decisión del LED y vigilante automático.

**Esta app es la dueña de la decisión** (SPEC del semáforo: el dispositivo solo
obedece). El ciclo a implementar es el de ``docs/SEMAFORO.md`` — báscula en cero
y despejada → VERDE para subir; vehículo sobre la plataforma → ROJO; peso sin
estabilizar → ROJO + AMARILLO intermitente; pesaje cerrado → VERDE (vía libre
para salir).

La decisión vive en ``decidir_semaforo`` (función **pura**, fácil de probar) y el
``SemaforoController`` solo la cablea: lee el peso en vivo de la báscula
vinculada (sesión persistente del HAL), el estado del boleto y manda al
semáforo **solo los cambios** de luz, para no inundar el equipo.

Fuente de fases (espejo del autómata del SPEC, en modo `app`):

===========================  ==============================================
Fase                         Luces
===========================  ==============================================
``SIN_BALANZA``              ROJO fijo (sin lectura no se autoriza nada)
``AUTORIZADO``               VERDE fijo (plataforma libre)
``ESPERANDO``                ROJO fijo (boleto abierto sin peso / sin ciclo)
``PESANDO``                  ROJO fijo (vehículo sobre la plataforma)
``INESTABLE``                ROJO fijo + AMARILLO intermitente
``SALIDA``                   VERDE fijo (boleto cerrado, vía libre)
===========================  ==============================================
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
import uuid
from dataclasses import dataclass
from typing import Any

from sqlalchemy import select, true
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.core.scale_session import get_scale_session_manager
from app.core.semaforo_hal import get_semaforo_hal
from app.models import Balanza, BoletoPesaje, Semaforo

log = logging.getLogger("balansoft_ws.semaforo")

#: Peso (kg) por debajo del cual la plataforma se considera libre.
UMBRAL_CERO_KG_DEFECTO = 5.0
#: Cadencia del vigilante (segundos): suficiente para reaccionar al peso.
INTERVALO_VIGILANTE = 0.5

MODO_OFF = "off"
MODO_ON = "on"
MODO_FLASH = "flash"

FASE_SIN_BALANZA = "SIN_BALANZA"
FASE_AUTORIZADO = "AUTORIZADO"
FASE_ESPERANDO = "ESPERANDO"
FASE_PESANDO = "PESANDO"
FASE_INESTABLE = "INESTABLE"
FASE_SALIDA = "SALIDA"

_COLORES = ("rojo", "amarillo", "verde")


@dataclass(frozen=True)
class Luces:
    """Estado deseado de las cuatro salidas del semáforo."""

    rojo: str = MODO_OFF
    amarillo: str = MODO_OFF
    verde: str = MODO_OFF
    zumbador: bool = False

    def para(self, color: str) -> str:
        return getattr(self, color)

    def como_comandos(self) -> list[dict[str, Any]]:
        """Comandos que fijan TODAS las salidas (uso manual/reset)."""
        cmds: list[dict[str, Any]] = [
            {"color": color, "action": self.para(color)} for color in _COLORES
        ]
        cmds.append({"zumbador": "on" if self.zumbador else "off"})
        return cmds

    def diferencias(self, actual: Luces) -> list[dict[str, Any]]:
        """Solo los comandos que cambian respecto de ``actual``."""
        cmds: list[dict[str, Any]] = [
            {"color": color, "action": self.para(color)}
            for color in _COLORES
            if self.para(color) != actual.para(color)
        ]
        if self.zumbador != actual.zumbador:
            cmds.append({"zumbador": "on" if self.zumbador else "off"})
        return cmds

    def como_dict(self) -> dict[str, Any]:
        return {
            "rojo": self.rojo,
            "amarillo": self.amarillo,
            "verde": self.verde,
            "zumbador": self.zumbador,
        }


@dataclass(frozen=True)
class ContextoSemaforo:
    """Entradas del ciclo de pesaje para decidir el LED."""

    conectado: bool
    peso_kg: float | None
    estable: bool
    hay_pendiente: bool
    salida_concedida: bool
    umbral_cero_kg: float = UMBRAL_CERO_KG_DEFECTO


@dataclass(frozen=True)
class DecisionSemaforo:
    """Fase y luces decididas para un contexto dado."""

    fase: str
    luces: Luces


#: Luces por defecto al arrancar un ciclo sin información (reposo seguro).
_LUCES_ROJO = Luces(rojo=MODO_ON)
_LUCES_VERDE = Luces(verde=MODO_ON)
_LUCES_INESTABLE = Luces(rojo=MODO_ON, amarillo=MODO_FLASH)


def decidir_semaforo(ctx: ContextoSemaforo) -> DecisionSemaforo:
    """Decide fase y luces a partir del contexto (función pura).

    Orden de precedencia (docs/SEMAFORO.md):

    1. Sin lectura viva de la báscula → **ROJO** (el vehículo espera fuera).
    2. Boleto cerrado (salida concedida) → **VERDE** (vía libre para salir),
       aunque todavía haya peso sobre la plataforma.
    3. Plataforma libre (peso ≤ umbral):
       - con boleto pendiente → **ROJO** (ciclo abierto sin peso: no autorizar),
       - sin ciclo → **VERDE** (autorización para subir).
    4. Vehículo sobre la plataforma (peso > umbral):
       - inestable → **ROJO + AMARILLO intermitente** (esperando estabilidad),
       - estable → **ROJO** (pesaje en curso / capturado: no moverse).
    """
    if not ctx.conectado or ctx.peso_kg is None:
        return DecisionSemaforo(FASE_SIN_BALANZA, _LUCES_ROJO)

    if ctx.salida_concedida:
        return DecisionSemaforo(FASE_SALIDA, _LUCES_VERDE)

    if ctx.peso_kg <= ctx.umbral_cero_kg:
        if ctx.hay_pendiente:
            return DecisionSemaforo(FASE_ESPERANDO, _LUCES_ROJO)
        return DecisionSemaforo(FASE_AUTORIZADO, _LUCES_VERDE)

    if not ctx.estable:
        return DecisionSemaforo(FASE_INESTABLE, _LUCES_INESTABLE)
    return DecisionSemaforo(FASE_PESANDO, _LUCES_ROJO)


def _luces_desde_comando(luces: Luces, comando: dict[str, Any]) -> Luces:
    """Aplica un comando §4 sobre ``luces`` (para el seguimiento manual)."""
    cambios: dict[str, Any] = {}
    if "all" in comando and comando["all"] == "off":
        cambios = {"rojo": MODO_OFF, "amarillo": MODO_OFF, "verde": MODO_OFF, "zumbador": False}
    elif "reset" in comando and comando["reset"]:
        cambios = {"rojo": MODO_OFF, "amarillo": MODO_OFF, "verde": MODO_OFF, "zumbador": False}
    else:
        color = comando.get("color")
        action = comando.get("action")
        if color in _COLORES and action in (MODO_ON, MODO_OFF, MODO_FLASH):
            cambios[color] = action
        zumbador = comando.get("zumbador")
        if zumbador in ("on", "off"):
            cambios["zumbador"] = zumbador == "on"
    return Luces(**{**luces.como_dict(), **cambios})


class SemaforoController:
    """Vigilante por semáforo: peso/estabilidad/boleto → comandos de LED."""

    def __init__(self, intervalo: float = INTERVALO_VIGILANTE) -> None:
        self._intervalo = intervalo
        self._tareas: dict[str, asyncio.Task[None]] = {}
        self._luces: dict[str, Luces] = {}
        self._fases: dict[str, str] = {}
        self._lock = asyncio.Lock()

    # -- consulta ---------------------------------------------------------

    def activo(self, id_semaforo: str) -> bool:
        tarea = self._tareas.get(str(id_semaforo))
        return tarea is not None and not tarea.done()

    def fase_actual(self, id_semaforo: str) -> str | None:
        return self._fases.get(str(id_semaforo))

    def luces_actuales(self, id_semaforo: str) -> Luces | None:
        return self._luces.get(str(id_semaforo))

    # -- ciclo de vida ----------------------------------------------------

    async def asegurar(self, id_semaforo: Any) -> None:
        """Arranca el vigilante del semáforo si no está corriendo."""
        key = str(id_semaforo)
        async with self._lock:
            tarea = self._tareas.get(key)
            if tarea is not None and not tarea.done():
                return
            self._tareas[key] = asyncio.create_task(
                self._run(key), name=f"semaforo-{key}"
            )

    async def detener(self, id_semaforo: Any) -> None:
        key = str(id_semaforo)
        async with self._lock:
            tarea = self._tareas.pop(key, None)
            self._luces.pop(key, None)
            self._fases.pop(key, None)
        await _cancelar(tarea)

    async def detener_todas(self) -> None:
        async with self._lock:
            tareas = list(self._tareas.values())
            self._tareas.clear()
            self._luces.clear()
            self._fases.clear()
        for tarea in tareas:
            await _cancelar(tarea)

    async def asegurar_activos(self) -> None:
        """Arranca los vigilantes de todos los semáforos con control automático.

        Best-effort: si la BD no está disponible, solo se registra en el log
        (el arranque de la API no debe caerse por el semáforo).
        """
        try:
            async with AsyncSessionLocal() as db:
                filas = (
                    await db.execute(
                        select(Semaforo.id_semaforo).where(
                            Semaforo.control_automatico == true(),
                            Semaforo.activo == true(),
                            Semaforo.id_balanza.is_not(None),
                        )
                    )
                ).scalars().all()
        except Exception as exc:  # noqa: BLE001 - arranque tolerante
            log.warning("No se pudieron cargar los semáforos automáticos: %s", exc)
            return
        for id_semaforo in filas:
            await self.asegurar(id_semaforo)

    # -- envío de comandos ------------------------------------------------

    async def enviar_manual(
        self, semaforo: Semaforo, comando: dict[str, Any]
    ) -> bool:
        """Envía un comando manual y sincroniza el seguimiento en memoria.

        El comando **no** cambia el modo automático: si el vigilante está
        activo, en el siguiente ciclo volverá a imponer la luz del pesaje.
        """
        hal = get_semaforo_hal(semaforo)
        ok = await hal.enviar_comando(comando)
        if ok:
            key = str(semaforo.id_semaforo)
            actual = self._luces.get(key, Luces())
            self._luces[key] = _luces_desde_comando(actual, comando)
        return ok

    # -- bucle ------------------------------------------------------------

    async def _run(self, key: str) -> None:
        try:
            while True:
                try:
                    seguir = await self._tick(key)
                except asyncio.CancelledError:
                    raise
                except Exception as exc:  # noqa: BLE001 - el bucle nunca muere
                    log.debug("Semáforo %s: ciclo con error: %s", key, exc)
                    seguir = True
                if not seguir:
                    return
                await asyncio.sleep(self._intervalo)
        finally:
            async with self._lock:
                # Solo limpiar si la tarea sigue siendo la registrada.
                if self._tareas.get(key) is asyncio.current_task():
                    self._tareas.pop(key, None)

    async def _tick(self, key: str) -> bool:
        """Un ciclo: devuelve ``False`` cuando el vigilante debe terminar."""
        try:
            id_semaforo = uuid.UUID(key)
        except ValueError:
            return False
        async with AsyncSessionLocal() as db:
            semaforo = await db.get(Semaforo, id_semaforo)
            if (
                semaforo is None
                or not semaforo.activo
                or not semaforo.control_automatico
                or semaforo.id_balanza is None
            ):
                return False
            balanza = await db.get(Balanza, semaforo.id_balanza)
            hay_pendiente, salida_concedida = await self._estado_boletos(db, semaforo)

        conectado = False
        peso: float | None = None
        estable = False
        if balanza is not None:
            try:
                sesion = await get_scale_session_manager().obtener(balanza)
                peso = sesion.peso_kg
                estable = sesion.estable
                conectado = peso is not None
            except ValueError:
                conectado = False

        ctx = ContextoSemaforo(
            conectado=conectado,
            peso_kg=peso,
            estable=estable,
            hay_pendiente=hay_pendiente,
            salida_concedida=salida_concedida,
            umbral_cero_kg=float(semaforo.umbral_cero_kg or UMBRAL_CERO_KG_DEFECTO),
        )
        decision = decidir_semaforo(ctx)

        actual = self._luces.get(key, Luces())
        comandos = decision.luces.diferencias(actual)
        if comandos:
            hal = get_semaforo_hal(semaforo)
            for comando in comandos:
                ok = await hal.enviar_comando(comando)
                if not ok:
                    # No se pudo aplicar: no se actualiza el seguimiento para
                    # reintentar el mismo cambio en el próximo ciclo.
                    return True
            self._luces[key] = decision.luces
        self._fases[key] = decision.fase
        return True

    async def _estado_boletos(
        self, db: AsyncSession, semaforo: Semaforo
    ) -> tuple[bool, bool]:
        """(hay_pendiente, salida_concedida) del ciclo de pesaje de la báscula."""
        if semaforo.id_balanza is None:
            return False, False
        filas = (
            await db.execute(
                select(BoletoPesaje.estado_boleto, BoletoPesaje.fecha_hora_salida)
                .where(
                    BoletoPesaje.id_empresa == semaforo.id_empresa,
                    BoletoPesaje.id_balanza == semaforo.id_balanza,
                )
                .order_by(BoletoPesaje.created_at.desc())
                .limit(5)
            )
        ).all()
        if not filas:
            return False, False
        hay_pendiente = any(
            (estado or "").upper() == BoletoPesaje.ESTADO_PENDIENTE
            for estado, _ in filas
        )
        ultimo_estado, fecha_salida = filas[0]
        cerrado = (ultimo_estado or "").upper() in (
            BoletoPesaje.ESTADO_CERRADO,
            BoletoPesaje.ESTADO_MODIFICADO,
        )
        # Vía libre: el último ciclo terminó y no hay otro en curso.
        salida_concedida = cerrado and not hay_pendiente and fecha_salida is not None
        return hay_pendiente, salida_concedida


async def _cancelar(tarea: asyncio.Task[None] | None) -> None:
    if tarea is None:
        return
    tarea.cancel()
    with contextlib.suppress(asyncio.CancelledError, Exception):
        await asyncio.wait_for(tarea, timeout=3.0)


_controller = SemaforoController()


def get_semaforo_controller() -> SemaforoController:
    return _controller
