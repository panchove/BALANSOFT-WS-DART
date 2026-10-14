"""Programador residente de notificaciones (tarea de fondo del backend local).

Es la pieza que cumple el requisito «las notificaciones funcionan aunque la app
Flutter esté cerrada»: el backend de la estación (WServer, rol ``local``) es el
único proceso que queda vivo, así que un ciclo ``asyncio`` evalúa eventos y
recordatorios y dibuja el aviso nativo del SO.

Se arranca y se detiene desde el ``lifespan`` de ``app.main``. En rol ``server``
no se arranca: la central no tiene la tabla ``notificaciones``.

Un fallo de un ciclo **nunca** tumba al servidor: se registra y se reintenta en
el siguiente intervalo.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging

from app.core.config import settings

log = logging.getLogger(__name__)

#: Migración que crea ``notificaciones``/``recordatorios``. Se nombra en el
#: aviso de esquema incompleto para que el operador sepa qué aplicar.
MIGRACION_NOTIFICACIONES = "023"


def falta_tabla(exc: BaseException) -> bool:
    """¿El fallo se debe a una tabla ausente (esquema sin migrar)?

    Reconoce el error de PostgreSQL/SQL Server tanto por la clase del error
    original (``UndefinedTableError``, ``ProgrammingError`` de SQL Server) como
    por el texto, que es lo que sobrevive al envoltorio de SQLAlchemy.
    """
    orig = getattr(exc, "orig", exc)
    if type(orig).__name__ in ("UndefinedTableError", "InvalidObjectName"):
        return True
    texto = str(orig).lower()
    return "does not exist" in texto or "invalid object name" in texto


class NotificationScheduler:
    """Bucle de fondo que evalúa eventos y despacha avisos al SO."""

    def __init__(self, interval_seconds: int | None = None) -> None:
        self._intervalo = max(int(interval_seconds or settings.notifications_interval_seconds), 5)
        self._tarea: asyncio.Task | None = None
        self._parar: asyncio.Event | None = None

    @property
    def activo(self) -> bool:
        return self._tarea is not None and not self._tarea.done()

    def iniciar(self) -> None:
        """Arranca el bucle (idempotente)."""
        if self.activo:
            return
        if not settings.notifications_enabled:
            log.info("Notificaciones deshabilitadas (NOTIFICATIONS_ENABLED=false)")
            return
        if settings.app_role == "server":
            return
        self._parar = asyncio.Event()
        self._tarea = asyncio.create_task(self._bucle(), name="balansoft-notificaciones")
        log.info("Programador de notificaciones activo (cada %ss)", self._intervalo)

    async def detener(self) -> None:
        """Detiene el bucle y espera a que termine."""
        if self._tarea is None:
            return
        if self._parar is not None:
            self._parar.set()
        self._tarea.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await self._tarea
        self._tarea = None
        self._parar = None
        log.info("Programador de notificaciones detenido")

    async def _bucle(self) -> None:
        while self._parar is not None and not self._parar.is_set():
            try:
                await self._tick()
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001 - un ciclo fallido no mata el bucle
                if falta_tabla(exc):
                    # Esquema incompleto (migración sin aplicar): un aviso
                    # accionable en vez de un traceback por cada ciclo.
                    log.error(
                        "Notificaciones deshabilitadas: faltan las tablas locales "
                        "(aplique la migración %s con "
                        "./scripts/setup_db.sh aplicar-migraciones)",
                        MIGRACION_NOTIFICACIONES,
                    )
                else:
                    log.exception("Fallo en el ciclo de notificaciones")
            if self._parar is None:
                return
            with contextlib.suppress(TimeoutError):
                await asyncio.wait_for(self._parar.wait(), timeout=self._intervalo)

    async def _tick(self) -> None:
        # Import diferido: evita cargar el motor de BD al importar la app.
        from app.core.database import AsyncSessionLocal
        from app.services.notification_service import (
            despachar_os_pendientes,
            evaluar_eventos,
        )

        async with AsyncSessionLocal() as db:
            try:
                creadas = await evaluar_eventos(db)
                enviados = await despachar_os_pendientes(db)
                await db.commit()
            except Exception:
                await db.rollback()
                raise
        if creadas or enviados:
            log.info(
                "Notificaciones: %s nuevas, %s despachadas al SO", creadas, enviados
            )


_scheduler: NotificationScheduler | None = None


def get_notification_scheduler() -> NotificationScheduler:
    global _scheduler
    if _scheduler is None:
        _scheduler = NotificationScheduler()
    return _scheduler
