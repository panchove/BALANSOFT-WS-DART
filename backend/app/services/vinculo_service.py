from __future__ import annotations

import asyncio
import logging
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.models import VinculoBalanzaIndicador
from app.services.indicador_bridge import IndicadorBridge

log = logging.getLogger("balansoft_ws.vinculos")


class VinculoManager:
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
        ev = asyncio.Event()
        self._stop[key] = ev
        self._estado[key] = "activo"
        self._tasks[key] = asyncio.create_task(bridge.iniciar(db))

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

    async def _marcar_inactivo(self, id_vinculo: UUID, motivo: str = "error_hardware"):
        key = str(id_vinculo)
        self._estado[key] = motivo
        try:
            async with AsyncSessionLocal() as dbs:
                res = await dbs.execute(select(VinculoBalanzaIndicador).where(VinculoBalanzaIndicador.id_vinculo == id_vinculo))
                v = res.scalar_one_or_none()
                if v and v.activo:
                    v.activo = False
                    await dbs.commit()
        except Exception as exc:
            log.debug("No se pudo marcar vínculo %s como inactivo: %s", id_vinculo, exc)

    async def iniciar_vinculo(self, db: AsyncSession, id_empresa: UUID, vinculo: VinculoBalanzaIndicador):
        """Alias para compatibilidad: iniciar el puente para un vínculo existente."""
        await self.iniciar(db, id_empresa, vinculo)

    async def estado(self, id_vinculo: UUID) -> str:
        key = str(id_vinculo)
        return self._estado.get(key, "inactivo")


VINCULO_MGR = VinculoManager()
