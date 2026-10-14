"""Centro de notificaciones y recordatorios de la estación.

Dos recursos:

* ``/api/v1/notificaciones`` — bandeja de avisos (leer/archivar/probar).
* ``/api/v1/recordatorios`` — recordatorios programados (CRUD, solo ADMIN).

Multi-tenant: el ``id_empresa`` sale **siempre** de la empresa autenticada
(``get_current_empresa``), nunca de la petición; toda consulta filtra por él.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any, cast

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import CursorResult, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, require_admin
from app.core.database import get_db
from app.core.datetime_utils import naive_utc
from app.models import Empresa, Notificacion, Recordatorio, Usuario
from app.services.notification_service import crear_notificacion

router = APIRouter(prefix="/api/v1/notificaciones", tags=["Notificaciones"])
router_recordatorios = APIRouter(prefix="/api/v1/recordatorios", tags=["Recordatorios"])

_MAX_LIMIT = 200


def _ahora() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# ---------------------------------------------------------------------------
# Esquemas
# ---------------------------------------------------------------------------


class NotificacionOut(BaseModel):
    id: str
    tipo: str
    severidad: str
    titulo: str
    mensaje: str | None = None
    estado: str
    leida: bool
    origen: str
    acciones: dict[str, Any] | None = None
    id_referencia: str | None = None
    id_recordatorio: str | None = None
    programada_para: datetime | None = None
    created_at: datetime
    leida_en: datetime | None = None


class ResumenOut(BaseModel):
    no_leidas: int
    total: int
    por_severidad: dict[str, int]


class RecordatorioOut(BaseModel):
    id: str
    titulo: str
    mensaje: str | None = None
    programada_para: datetime
    recurrencia: str
    activo: bool
    ultima_ejecucion: datetime | None = None
    created_at: datetime


class RecordatorioCreate(BaseModel):
    titulo: str = Field(min_length=1, max_length=200)
    mensaje: str | None = Field(default=None, max_length=2000)
    programada_para: datetime
    recurrencia: str = Field(default="none")


class RecordatorioUpdate(BaseModel):
    titulo: str | None = Field(default=None, min_length=1, max_length=200)
    mensaje: str | None = Field(default=None, max_length=2000)
    programada_para: datetime | None = None
    recurrencia: str | None = None
    activo: bool | None = None


def _notificacion_out(n: Notificacion) -> NotificacionOut:
    return NotificacionOut(
        id=str(n.id),
        tipo=n.tipo,
        severidad=n.severidad,
        titulo=n.titulo,
        mensaje=n.mensaje,
        estado=n.estado,
        leida=n.estado != Notificacion.ESTADO_NO_LEIDA,
        origen=n.origen,
        acciones=n.acciones,
        id_referencia=str(n.id_referencia) if n.id_referencia else None,
        id_recordatorio=str(n.id_recordatorio) if n.id_recordatorio else None,
        programada_para=n.programada_para,
        created_at=n.created_at,
        leida_en=n.leida_en,
    )


def _recordatorio_out(r: Recordatorio) -> RecordatorioOut:
    return RecordatorioOut(
        id=str(r.id),
        titulo=r.titulo,
        mensaje=r.mensaje,
        programada_para=r.programada_para,
        recurrencia=r.recurrencia,
        activo=r.activo,
        ultima_ejecucion=r.ultima_ejecucion,
        created_at=r.created_at,
    )


# ---------------------------------------------------------------------------
# Notificaciones
# ---------------------------------------------------------------------------


@router.get("", response_model=list[NotificacionOut])
async def listar_notificaciones(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
    estado: str | None = Query(default=None, description="no_leida|leida|archivado"),
    tipo: str | None = Query(default=None),
    severidad: str | None = Query(default=None),
    solo_no_leidas: bool = Query(default=False),
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=_MAX_LIMIT),
) -> list[NotificacionOut]:
    """Bandeja de la empresa autenticada (más recientes primero)."""
    consulta = select(Notificacion).where(Notificacion.id_empresa == empresa.id_empresa)
    if solo_no_leidas:
        consulta = consulta.where(Notificacion.estado == Notificacion.ESTADO_NO_LEIDA)
    elif estado:
        consulta = consulta.where(Notificacion.estado == estado)
    if tipo:
        consulta = consulta.where(Notificacion.tipo == tipo)
    if severidad:
        consulta = consulta.where(Notificacion.severidad == severidad)
    consulta = (
        consulta.order_by(Notificacion.created_at.desc()).offset(skip).limit(limit)
    )
    filas = (await db.execute(consulta)).scalars().all()
    return [_notificacion_out(n) for n in filas]


@router.get("/resumen", response_model=ResumenOut)
async def resumen_notificaciones(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ResumenOut:
    """Contadores para la campana del *navbar* (badge)."""
    base = select(func.count()).select_from(Notificacion).where(
        Notificacion.id_empresa == empresa.id_empresa
    )
    total = (await db.execute(base)).scalar_one() or 0
    no_leidas = (
        await db.execute(
            base.where(Notificacion.estado == Notificacion.ESTADO_NO_LEIDA)
        )
    ).scalar_one() or 0
    filas = (
        await db.execute(
            select(Notificacion.severidad, func.count())
            .where(
                Notificacion.id_empresa == empresa.id_empresa,
                Notificacion.estado == Notificacion.ESTADO_NO_LEIDA,
            )
            .group_by(Notificacion.severidad)
        )
    ).all()
    return ResumenOut(
        no_leidas=no_leidas,
        total=total,
        por_severidad={severidad: cuenta for severidad, cuenta in filas},
    )


@router.post("/leer-todas")
async def leer_todas(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Marca como leídas todas las notificaciones no leídas de la empresa."""
    resultado = cast(
        "CursorResult[Any]",
        await db.execute(
            update(Notificacion)
            .where(
                Notificacion.id_empresa == empresa.id_empresa,
                Notificacion.estado == Notificacion.ESTADO_NO_LEIDA,
            )
            .values(estado=Notificacion.ESTADO_LEIDA, leida_en=_ahora())
        ),
    )
    await db.commit()
    return {"actualizadas": resultado.rowcount or 0}


@router.post("/probar", response_model=NotificacionOut)
async def probar_notificacion(
    _admin: Usuario = Depends(require_admin),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> NotificacionOut:
    """Genera un aviso de prueba (ADMIN) para validar el canal del SO."""
    nueva = await crear_notificacion(
        db,
        id_empresa=empresa.id_empresa,
        tipo="prueba",
        titulo="Prueba de notificación",
        mensaje="Si ves este aviso, el canal de notificaciones funciona.",
        severidad="info",
        origen="manual",
        dedup_key=f"prueba:{uuid.uuid4()}",
    )
    await db.commit()
    if nueva is None:  # imposible: la clave es única por ejecución
        raise HTTPException(status_code=500, detail="No se pudo crear la notificación")
    return _notificacion_out(nueva)


@router.post("/{id_notificacion}/leer", response_model=NotificacionOut)
async def leer_notificacion(
    id_notificacion: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> NotificacionOut:
    notificacion = await _buscar(db, empresa, id_notificacion)
    if notificacion.estado == Notificacion.ESTADO_NO_LEIDA:
        notificacion.estado = Notificacion.ESTADO_LEIDA
        notificacion.leida_en = _ahora()
        await db.commit()
        await db.refresh(notificacion)
    return _notificacion_out(notificacion)


@router.post("/{id_notificacion}/archivar", response_model=NotificacionOut)
async def archivar_notificacion(
    id_notificacion: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> NotificacionOut:
    notificacion = await _buscar(db, empresa, id_notificacion)
    notificacion.estado = Notificacion.ESTADO_ARCHIVADO
    if notificacion.leida_en is None:
        notificacion.leida_en = _ahora()
    await db.commit()
    await db.refresh(notificacion)
    return _notificacion_out(notificacion)


async def _buscar(
    db: AsyncSession, empresa: Empresa, id_notificacion: uuid.UUID
) -> Notificacion:
    notificacion = (
        await db.execute(
            select(Notificacion).where(
                Notificacion.id == id_notificacion,
                Notificacion.id_empresa == empresa.id_empresa,
            )
        )
    ).scalar_one_or_none()
    if notificacion is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No encontrada")
    return notificacion


# ---------------------------------------------------------------------------
# Recordatorios
# ---------------------------------------------------------------------------


@router_recordatorios.get("", response_model=list[RecordatorioOut])
async def listar_recordatorios(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
    incluir_inactivos: bool = Query(default=True),
) -> list[RecordatorioOut]:
    consulta = select(Recordatorio).where(Recordatorio.id_empresa == empresa.id_empresa)
    if not incluir_inactivos:
        consulta = consulta.where(Recordatorio.activo.is_(True))
    filas = (
        (await db.execute(consulta.order_by(Recordatorio.programada_para))).scalars().all()
    )
    return [_recordatorio_out(r) for r in filas]


@router_recordatorios.post("", response_model=RecordatorioOut, status_code=201)
async def crear_recordatorio(
    payload: RecordatorioCreate,
    _admin: Usuario = Depends(require_admin),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> RecordatorioOut:
    if payload.recurrencia not in Recordatorio.RECURRENCIAS:
        raise HTTPException(status_code=422, detail="Recurrencia inválida")
    recordatorio = Recordatorio(
        id_empresa=empresa.id_empresa,
        id_usuario=_admin.id_usuario,
        titulo=payload.titulo,
        mensaje=payload.mensaje,
        programada_para=naive_utc(payload.programada_para),
        recurrencia=payload.recurrencia,
        activo=True,
    )
    db.add(recordatorio)
    await db.commit()
    await db.refresh(recordatorio)
    return _recordatorio_out(recordatorio)


@router_recordatorios.patch("/{id_recordatorio}", response_model=RecordatorioOut)
async def actualizar_recordatorio(
    id_recordatorio: uuid.UUID,
    payload: RecordatorioUpdate,
    _admin: Usuario = Depends(require_admin),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> RecordatorioOut:
    recordatorio = await _buscar_recordatorio(db, empresa, id_recordatorio)
    if payload.recurrencia is not None:
        if payload.recurrencia not in Recordatorio.RECURRENCIAS:
            raise HTTPException(status_code=422, detail="Recurrencia inválida")
        recordatorio.recurrencia = payload.recurrencia
    if payload.titulo is not None:
        recordatorio.titulo = payload.titulo
    if payload.mensaje is not None:
        recordatorio.mensaje = payload.mensaje
    if payload.programada_para is not None:
        programada = naive_utc(payload.programada_para)
        if programada is not None:
            recordatorio.programada_para = programada
    if payload.activo is not None:
        recordatorio.activo = payload.activo
    await db.commit()
    await db.refresh(recordatorio)
    return _recordatorio_out(recordatorio)


@router_recordatorios.delete("/{id_recordatorio}", status_code=204)
async def eliminar_recordatorio(
    id_recordatorio: uuid.UUID,
    _admin: Usuario = Depends(require_admin),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    recordatorio = await _buscar_recordatorio(db, empresa, id_recordatorio)
    await db.delete(recordatorio)
    await db.commit()


@router_recordatorios.post("/{id_recordatorio}/probar", response_model=NotificacionOut)
async def probar_recordatorio(
    id_recordatorio: uuid.UUID,
    _admin: Usuario = Depends(require_admin),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> NotificacionOut:
    """Dispara el recordatorio ahora mismo, sin alterar su programación."""
    recordatorio = await _buscar_recordatorio(db, empresa, id_recordatorio)
    nueva = await crear_notificacion(
        db,
        id_empresa=empresa.id_empresa,
        tipo="recordatorio",
        titulo=recordatorio.titulo,
        mensaje=recordatorio.mensaje,
        severidad="media",
        origen="recordatorio",
        id_recordatorio=recordatorio.id,
        dedup_key=f"recordatorio-prueba:{uuid.uuid4()}",
    )
    await db.commit()
    if nueva is None:  # imposible: la clave es única por ejecución
        raise HTTPException(status_code=500, detail="No se pudo crear la notificación")
    return _notificacion_out(nueva)


async def _buscar_recordatorio(
    db: AsyncSession, empresa: Empresa, id_recordatorio: uuid.UUID
) -> Recordatorio:
    recordatorio = (
        await db.execute(
            select(Recordatorio).where(
                Recordatorio.id == id_recordatorio,
                Recordatorio.id_empresa == empresa.id_empresa,
            )
        )
    ).scalar_one_or_none()
    if recordatorio is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No encontrado")
    return recordatorio
