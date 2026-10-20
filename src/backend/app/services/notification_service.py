"""Centro de notificaciones de la estación (in-app + aviso nativo del SO).

Aquí vive la lógica de negocio del subsistema:

* ``crear_notificacion`` — inserta con **idempotencia** por ``dedup_key``
  (única por empresa).
* ``despachar_os_pendientes`` — muestra en el SO (`notifier.notificar_os`)
  los avisos aún no entregados. Lo llama el programador
  (`app/core/notification_scheduler.py`), no cada endpoint.
* ``evaluar_eventos`` — recorre las empresas locales y genera los avisos de
  evento (licencia, sincronización, boletos, series) y los recordatorios
  vencidos.

Multi-tenant: **todas** las consultas filtran por ``id_empresa``; el valor sale
de la propia BD (o del JWT en los endpoints), nunca del cliente.

Versión: 0.4.2-dev.56
Fecha: 2026-10-19
Estado: Vigente
Norma: ISO/IEC 25010 / ISO/IEC 27001
Fuente: Sistema BALANSOFT-WS
Autor: Lead Architect
"""

from __future__ import annotations

import asyncio
import calendar
import logging
import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select, true
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.i18n import normalizar_idioma, t
from app.models import (
    BoletoPesaje,
    Empresa,
    Notificacion,
    Recordatorio,
    SerieNumeracion,
    SyncQueue,
)
from app.services.notifier import canal_disponible, notificar_os

log = logging.getLogger(__name__)

# Umbrales de los avisos basados en datos.
_SYNC_ATRASADO = timedelta(minutes=30)
_BOLETO_ANTIGUO = timedelta(hours=24)
_MARGEN_SERIE = 100
_RECURRENCIAS = ("daily", "weekly", "monthly")


def _ahora() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


def _fmt(dt: datetime | None) -> str:
    return dt.strftime("%d/%m/%Y") if dt else ""


def _ymd(dt: datetime) -> str:
    return dt.strftime("%Y%m%d")


def _idioma(empresa: Empresa) -> str:
    return normalizar_idioma(empresa.idioma) or settings.idioma_default


# ---------------------------------------------------------------------------
# Alta y despacho
# ---------------------------------------------------------------------------


async def crear_notificacion(
    db: AsyncSession,
    *,
    id_empresa: uuid.UUID,
    tipo: str,
    titulo: str,
    mensaje: str | None = None,
    severidad: str = "info",
    origen: str = "evento",
    dedup_key: str | None = None,
    acciones: dict | None = None,
    id_referencia: uuid.UUID | None = None,
    id_recordatorio: uuid.UUID | None = None,
    programada_para: datetime | None = None,
    expira_en: datetime | None = None,
) -> Notificacion | None:
    """Crea una notificación salvo que ``dedup_key`` ya exista (idempotencia).

    Devuelve la fila nueva o ``None`` si el aviso ya estaba registrado.
    """
    if severidad not in Notificacion.SEVERIDADES:
        severidad = "info"
    if dedup_key is not None:
        existe = (
            await db.execute(
                select(Notificacion.id).where(
                    Notificacion.id_empresa == id_empresa,
                    Notificacion.dedup_key == dedup_key,
                )
            )
        ).scalar_one_or_none()
        if existe is not None:
            return None

    notificacion = Notificacion(
        id_empresa=id_empresa,
        tipo=tipo,
        titulo=titulo[:200],
        mensaje=mensaje,
        severidad=severidad,
        estado=Notificacion.ESTADO_NO_LEIDA,
        origen=origen,
        dedup_key=dedup_key,
        acciones=acciones,
        id_referencia=id_referencia,
        id_recordatorio=id_recordatorio,
        programada_para=programada_para,
        expira_en=expira_en,
    )
    try:
        # SAVEPOINT (con el ``add`` dentro): si dos procesos compiten por el
        # mismo ``dedup_key`` y el otro gana la carrera entre el SELECT y este
        # INSERT, la violación del índice único se interpreta como "ya existe"
        # y no aborta la transacción del llamador (el ciclo del programador).
        # El SAVEPOINT debe envolver también el ``add``: si la fila ya está en
        # la sesión antes de abrir el savepoint, el fallo del flush desactiva
        # la transacción entera y el ``try/except`` no sirve de nada.
        async with db.begin_nested():
            db.add(notificacion)
            await db.flush()
    except IntegrityError:
        if notificacion in db:
            db.expunge(notificacion)
        return None
    return notificacion


async def _avisar(
    db: AsyncSession,
    empresa: Empresa,
    *,
    tipo: str,
    severidad: str,
    titulo: str,
    mensaje: str,
    dedup_key: str,
) -> int:
    creada = await crear_notificacion(
        db,
        id_empresa=empresa.id_empresa,
        tipo=tipo,
        titulo=titulo,
        mensaje=mensaje,
        severidad=severidad,
        dedup_key=dedup_key,
    )
    return 1 if creada is not None else 0


async def despachar_os_pendientes(db: AsyncSession, *, limit: int = 50) -> int:
    """Muestra en el SO los avisos aún no entregados. Devuelve cuántos envió.

    Best-effort: en un entorno sin canal (CI, contenedor) devuelve 0 sin ruido
    y sin marcar nada como entregado. Se consulta **empresa a empresa** (el
    resto del módulo hace lo mismo) para que ninguna consulta cruce tenants,
    aunque la estación trabaje con una sola empresa.
    """
    if not settings.notifications_os_enabled or canal_disponible() is None:
        return 0

    ids_empresas = (await db.execute(select(Empresa.id_empresa))).scalars().all()
    enviados = 0
    for id_empresa in ids_empresas:
        filas = (
            (
                await db.execute(
                    select(Notificacion)
                    .where(
                        Notificacion.id_empresa == id_empresa,
                        Notificacion.entregada_os_en.is_(None),
                    )
                    .order_by(Notificacion.created_at)
                    .limit(limit)
                )
            )
            .scalars()
            .all()
        )
        for notificacion in filas:
            ok = await asyncio.to_thread(
                notificar_os,
                notificacion.titulo,
                notificacion.mensaje or notificacion.tipo,
                notificacion.severidad,
            )
            if ok:
                notificacion.entregada_os_en = _ahora()
                enviados += 1
    if enviados:
        await db.flush()
    return enviados


# ---------------------------------------------------------------------------
# Evaluación de eventos
# ---------------------------------------------------------------------------


async def evaluar_eventos(db: AsyncSession) -> int:
    """Genera los avisos de evento y de recordatorios vencidos de todas las empresas."""
    ahora = _ahora()
    creadas = 0
    empresas = (await db.execute(select(Empresa))).scalars().all()
    for empresa in empresas:
        creadas += await _evaluar_empresa(db, empresa, ahora)
    creadas += await _evaluar_recordatorios(db, ahora)
    if creadas:
        await db.flush()
    return creadas


async def _evaluar_empresa(db: AsyncSession, empresa: Empresa, ahora: datetime) -> int:
    return (
        await _evaluar_licencia(db, empresa, ahora)
        + await _evaluar_sync(db, empresa, ahora)
        + await _evaluar_boletos(db, empresa, ahora)
        + await _evaluar_series(db, empresa, ahora)
    )


async def _evaluar_licencia(db: AsyncSession, empresa: Empresa, ahora: datetime) -> int:
    if empresa.licencia_expira is None:
        return 0
    idioma = _idioma(empresa)
    dias = int((empresa.licencia_expira - ahora).days)
    if dias < 0:
        return await _avisar(
            db,
            empresa,
            tipo="licencia_vencida",
            severidad="critica",
            titulo=t("notif_licencia_vencida_titulo", idioma),
            mensaje=t("notif_licencia_vencida_mensaje", idioma).format(
                fecha=_fmt(empresa.licencia_expira)
            ),
            dedup_key=f"licencia-vencida:{_ymd(ahora)}",
        )
    if dias <= settings.notifications_license_warning_days:
        return await _avisar(
            db,
            empresa,
            tipo="licencia_por_vencer",
            severidad="alta",
            titulo=t("notif_licencia_por_vencer_titulo", idioma),
            mensaje=t("notif_licencia_por_vencer_mensaje", idioma).format(
                dias=dias, fecha=_fmt(empresa.licencia_expira)
            ),
            dedup_key=f"licencia-por-vencer:{_ymd(ahora)}",
        )
    return 0


async def _evaluar_sync(db: AsyncSession, empresa: Empresa, ahora: datetime) -> int:
    idioma = _idioma(empresa)
    creadas = 0

    pendientes = (
        await db.execute(
            select(func.count())
            .select_from(SyncQueue)
            .where(
                SyncQueue.id_empresa == empresa.id_empresa,
                SyncQueue.pendiente == true(),
            )
        )
    ).scalar_one() or 0
    if pendientes:
        mas_antiguo = (
            await db.execute(
                select(func.min(SyncQueue.created_at)).where(
                    SyncQueue.id_empresa == empresa.id_empresa,
                    SyncQueue.pendiente == true(),
                )
            )
        ).scalar_one()
        if mas_antiguo is not None and mas_antiguo <= ahora - _SYNC_ATRASADO:
            creadas += await _avisar(
                db,
                empresa,
                tipo="sync_pendiente",
                severidad="media",
                titulo=t("notif_sync_pendiente_titulo", idioma),
                mensaje=t("notif_sync_pendiente_mensaje", idioma).format(
                    n=pendientes, fecha=_fmt(mas_antiguo)
                ),
                dedup_key=f"sync-pendiente:{_ymd(ahora)}",
            )

    fallidos = (
        await db.execute(
            select(func.count())
            .select_from(SyncQueue)
            .where(
                SyncQueue.id_empresa == empresa.id_empresa,
                SyncQueue.pendiente == true(),
                SyncQueue.error.is_not(None),
                SyncQueue.intentos >= settings.max_sync_retries,
            )
        )
    ).scalar_one() or 0
    if fallidos:
        creadas += await _avisar(
            db,
            empresa,
            tipo="sync_fallido",
            severidad="critica",
            titulo=t("notif_sync_fallido_titulo", idioma),
            mensaje=t("notif_sync_fallido_mensaje", idioma).format(n=fallidos),
            dedup_key=f"sync-fallido:{_ymd(ahora)}",
        )
    return creadas


async def _evaluar_boletos(db: AsyncSession, empresa: Empresa, ahora: datetime) -> int:
    idioma = _idioma(empresa)
    antiguos = (
        await db.execute(
            select(func.count())
            .select_from(BoletoPesaje)
            .where(
                BoletoPesaje.id_empresa == empresa.id_empresa,
                BoletoPesaje.estado_boleto == BoletoPesaje.ESTADO_PENDIENTE,
                BoletoPesaje.fecha_hora_entrada <= ahora - _BOLETO_ANTIGUO,
            )
        )
    ).scalar_one() or 0
    if not antiguos:
        return 0
    return await _avisar(
        db,
        empresa,
        tipo="boletos_pendientes",
        severidad="media",
        titulo=t("notif_boletos_pendientes_titulo", idioma),
        mensaje=t("notif_boletos_pendientes_mensaje", idioma).format(n=antiguos),
        dedup_key=f"boletos-pendientes:{_ymd(ahora)}",
    )


async def _evaluar_series(db: AsyncSession, empresa: Empresa, ahora: datetime) -> int:
    idioma = _idioma(empresa)
    series = (
        (
            await db.execute(
                select(SerieNumeracion).where(
                    SerieNumeracion.id_empresa == empresa.id_empresa,
                    SerieNumeracion.activa == true(),
                )
            )
        )
        .scalars()
        .all()
    )
    creadas = 0
    for serie in series:
        limite = 10 ** int(serie.digitos or 0)
        if limite <= 0 or serie.siguiente < limite - _MARGEN_SERIE:
            continue
        creadas += await _avisar(
            db,
            empresa,
            tipo="serie_por_agotar",
            severidad="media",
            titulo=t("notif_serie_por_agotar_titulo", idioma),
            mensaje=t("notif_serie_por_agotar_mensaje", idioma).format(
                serie=serie.nombre, limite=limite - 1
            ),
            dedup_key=f"serie-por-agotar:{serie.id_serie}:{_ymd(ahora)}",
        )
    return creadas


async def _evaluar_recordatorios(db: AsyncSession, ahora: datetime) -> int:
    vencidos = (
        (
            await db.execute(
                select(Recordatorio).where(
                    Recordatorio.activo == true(),
                    Recordatorio.programada_para <= ahora,
                )
            )
        )
        .scalars()
        .all()
    )
    creadas = 0
    for recordatorio in vencidos:
        nueva = await crear_notificacion(
            db,
            id_empresa=recordatorio.id_empresa,
            tipo="recordatorio",
            titulo=recordatorio.titulo,
            mensaje=recordatorio.mensaje,
            severidad="media",
            origen="recordatorio",
            id_recordatorio=recordatorio.id,
            programada_para=recordatorio.programada_para,
            dedup_key=(
                f"recordatorio:{recordatorio.id}:"
                f"{recordatorio.programada_para.isoformat()}"
            ),
        )
        if nueva is not None:
            creadas += 1
        _reprogramar(recordatorio, ahora)
    return creadas


# ---------------------------------------------------------------------------
# Recordatorios: recurrencia
# ---------------------------------------------------------------------------


def _mes_siguiente(programada: datetime) -> datetime:
    mes = programada.month
    anio = programada.year
    if mes == 12:
        mes, anio = 1, anio + 1
    else:
        mes += 1
    dia = min(programada.day, calendar.monthrange(anio, mes)[1])
    return programada.replace(year=anio, month=mes, day=dia)


def _siguiente(programada: datetime, recurrencia: str) -> datetime | None:
    if recurrencia == "daily":
        return programada + timedelta(days=1)
    if recurrencia == "weekly":
        return programada + timedelta(days=7)
    if recurrencia == "monthly":
        return _mes_siguiente(programada)
    return None


def _reprogramar(recordatorio: Recordatorio, ahora: datetime) -> None:
    """Avanza (o desactiva) el recordatorio tras dispararlo."""
    recordatorio.ultima_ejecucion = ahora
    if recordatorio.recurrencia not in _RECURRENCIAS:
        recordatorio.activo = False
        return
    siguiente = _siguiente(recordatorio.programada_para, recordatorio.recurrencia)
    # Si la estación estuvo apagada, salta los ciclos ya vencidos (sin
    # generar un aviso por cada uno) hasta quedar por delante de ``ahora``.
    intentos = 0
    while siguiente is not None and siguiente <= ahora and intentos < 10_000:
        siguiente = _siguiente(siguiente, recordatorio.recurrencia)
        intentos += 1
    if siguiente is not None:
        recordatorio.programada_para = siguiente
