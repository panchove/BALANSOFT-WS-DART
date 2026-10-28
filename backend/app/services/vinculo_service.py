from __future__ import annotations

import asyncio
import logging
from typing import Dict
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.core.indicador_hal import get_indicador_hal
from app.core.scale_session import get_scale_session_manager
from app.models import Balanza, Indicador, VinculoBalanzaIndicador

log = logging.getLogger("balansoft_ws.vinculos")


class VinculoManager:
    def __init__(self):
        self._tasks: Dict[str, asyncio.Task] = {}
        self._stop: Dict[str, asyncio.Event] = {}
        self._estado: Dict[str, str] = {}

    async def iniciar(self, db: AsyncSession, id_empresa: UUID, vinculo: VinculoBalanzaIndicador):
        key = str(vinculo.id_vinculo)
        if key in self._tasks and not self._tasks[key].done():
            return
        ev = asyncio.Event()
        self._stop[key] = ev
        self._estado[key] = "activo"
        self._tasks[key] = asyncio.create_task(self._loop(db, id_empresa, vinculo, ev))

    async def detener(self, id_vinculo: UUID):
        key = str(id_vinculo)
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

    async def estado(self, id_vinculo: UUID) -> str:
        key = str(id_vinculo)
        return self._estado.get(key, "inactivo")

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

    async def _loop(self, db: AsyncSession, id_empresa: UUID, vinculo: VinculoBalanzaIndicador, ev: asyncio.Event):
        key = str(vinculo.id_vinculo)
        fallos_conexion = 0
        log.info("INICIANDO BUCLE para vínculo %s", key)
        
        try:
            mgr = get_scale_session_manager()
            res_b = await db.execute(
                select(Balanza).where(Balanza.id_balanza == vinculo.id_bascula, Balanza.id_empresa == id_empresa)
            )
            bal = res_b.scalar_one_or_none()
            res_i = await db.execute(
                select(Indicador).where(Indicador.id_indicador == vinculo.id_indicador, Indicador.id_empresa == id_empresa)
            )
            ind = res_i.scalar_one_or_none()
            if not bal or not ind:
                log.warning("Vínculo %s sin hardware (bal=%s, ind=%s)", key, bal, ind)
                await self._marcar_inactivo(vinculo.id_vinculo, "sin_hardware")
                return
                
            hal_ind = get_indicador_hal(ind)
            log.info("Vínculo %s: Báscula='%s' (puerto=%s) -> Indicador='%s' (proto=%s, puerto=%s)", 
                     key, bal.descripcion, bal.puerto_com, ind.descripcion, ind.protocolo, ind.puerto_com)
            
            ses = None
            try:
                ses = await mgr.obtener(bal)
                if not ses.conectado:
                    try:
                        ses.iniciar()
                    except Exception:
                        pass
                    try:
                        await ses.esperar_primera(timeout=2.0)
                    except Exception:
                        pass
            except Exception as exc:
                log.debug("vinculo obtener sesion fallo: %s", exc)
                fallos_conexion += 1
                
            ultimo_peso = None
            ultimo_status = None
            
            while not ev.is_set():
                try:
                    if ses is None or not ses.conectado:
                        fallos_conexion += 1
                        try:
                            ses = await mgr.obtener(bal)
                            if ses and not ses.conectado:
                                try:
                                    ses.iniciar()
                                except Exception:
                                    pass
                                try:
                                    await ses.esperar_primera(timeout=1.5)
                                except Exception:
                                    pass
                        except Exception as exc:
                            log.debug("vinculo reconexion fallo: %s", exc)
                        if fallos_conexion >= 10:
                            log.warning("Vínculo %s: pérdida de conexión con báscula tras %s intentos", vinculo.id_vinculo, fallos_conexion)
                            await self._marcar_inactivo(vinculo.id_vinculo, "error_hardware")
                            break
                        await asyncio.sleep(1.0)
                        continue
                    fallos_conexion = 0
                    
                    # Leemos el peso actual y el estado de estabilidad
                    peso_actual = ses.peso_kg
                    estable_actual = getattr(ses, 'estable', True)
                    status_texto = "ok" if estable_actual else "inestable"

                    # Solo enviamos si el peso cambió o el estado cambió
                    if peso_actual is not None and (ultimo_peso != peso_actual or ultimo_status != status_texto):
                        log.info(">>> ENVIANDO PESO AL INDICADOR: %s kg (estado: %s)", peso_actual, status_texto)
                        try:
                            exito = await hal_ind.enviar_peso(peso_actual, None, status_texto)
                            if exito:
                                log.info(">>> PESO ENVIADO CON ÉXITO AL INDICADOR")
                            else:
                                log.warning(">>> FALLÓ EL ENVÍO DEL PESO AL INDICADOR (hal devolvió False)")
                        except Exception as exc:
                            log.error(">>> ERROR CRÍTICO AL ENVIAR PESO: %s", exc)
                        ultimo_peso = peso_actual
                        ultimo_status = status_texto
                except Exception as exc:
                    log.debug("vinculo leer sesion fallo: %s", exc)
                    fallos_conexion += 1
                    if fallos_conexion >= 15:
                        log.warning("Vínculo %s: errores persistentes con sesión de báscula", vinculo.id_vinculo)
                        await self._marcar_inactivo(vinculo.id_vinculo, "error_hardware")
                        break
                    await asyncio.sleep(0.5)
                    continue
                # Pausa de 1 segundo entre comprobaciones
                await asyncio.sleep(1.0)
                
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            log.debug("vinculo loop error: %s", exc)
            await self._marcar_inactivo(vinculo.id_vinculo, "error_hardware")
        finally:
            try:
                res_i2 = await db.execute(
                    select(Indicador).where(Indicador.id_indicador == vinculo.id_indicador, Indicador.id_empresa == id_empresa)
                )
                ind2 = res_i2.scalar_one_or_none()
                if ind2:
                    hal_ind_final = get_indicador_hal(ind2)
                    try:
                        await hal_ind_final.enviar_peso(0.0, None, "stop")
                    except Exception:
                        pass
            except Exception:
                pass
            log.info("DETENIENDO BUCLE para vínculo %s", key)
            self._tasks.pop(key, None)
            self._stop.pop(key, None)


VINCULO_MGR = VinculoManager()
