"""Rutas de pesaje (weighing).

Reglas de negocio críticas:
- Creación inline (get-or-create) para vehículo, remolque, transporte, conductor,
  producto, almacén, balanza y tercero.
- Un camión no puede tener dos boletos PENDIENTE a la vez (400).
- Pesaje manual solo para roles ADMIN / SUPERVISOR (403).
- Anulación con motivo obligatorio; libera el vehículo si estaba PENDIENTE.
- Número de boleto secuencial (prefijo configurable) que nunca se reutiliza.
"""

from __future__ import annotations

import os
import uuid
from datetime import UTC, datetime

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    Request,
    Response,
    UploadFile,
)
from pydantic import BaseModel, Field
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user
from app.core.config import settings
from app.core.database import get_db
from app.core.hardware import obtener_hardware_id
from app.core.license_client import LicenseError, LicenseInfo, get_license_client
from app.core.monitoring import inc_pesaje_anulado, inc_pesaje_cerrado, inc_pesaje_creado
from app.core.scale_session import get_scale_session_manager
from app.models import (
    Almacen,
    Balanza,
    BoletoPesaje,
    Conductor,
    Empresa,
    IdentidadLocal,
    ImagenPesaje,
    Producto,
    Remolque,
    Tercero,
    Transporte,
    Usuario,
)
from app.schemas import (
    WeighingAnular,
    WeighingClose,
    WeighingCreate,
    WeighingOut,
    WeighingUpdate,
)
from app.services.ticket_service import generar_ticket_pdf, generar_ticket_txt
from app.services.weighing_service import WeighingService

router = APIRouter(prefix="/api/v1/weighing", tags=["Weighing"])

_SERVICE = WeighingService()

_PERMISOS_PESO_MANUAL = {"ADMIN", "SUPERVISOR"}
_PERMISOS_ANULACION = {"ADMIN", "SUPERVISOR"}


def _verificar_peso_manual(es_manual: bool, user: Usuario) -> None:
    """Solo SUPERVISOR/ADMIN pueden registrar pesos manualmente."""
    if es_manual and user.rol not in _PERMISOS_PESO_MANUAL:
        raise HTTPException(
            status_code=403,
            detail="No tiene permisos para registrar pesajes en modo manual.",
        )


def _verificar_anulacion(user: Usuario) -> None:
    """Solo SUPERVISOR/ADMIN pueden anular boletos."""
    if user.rol not in _PERMISOS_ANULACION:
        raise HTTPException(
            status_code=403,
            detail="No tiene permisos para anular boletos.",
        )


def _resolve_to_weighing_out(p: BoletoPesaje) -> WeighingOut:
    return WeighingOut.model_validate(p)


@router.post("/create", response_model=WeighingOut)
async def create_weighing(
    payload: WeighingCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> WeighingOut:
    _verificar_peso_manual(payload.es_peso_manual, current_user)

    # Validar licencia online (best-effort: si el LM no responde, se bloquea
    # la creación para no operar sin licencia verificada). Si la licencia aún
    # no está activada (AVAILABLE) o el dispositivo de una CENTRAL no está
    # registrado, se auto-activa en el LM antes de validar.
    lic_info: LicenseInfo | None = None
    if empresa.licencia_key:
        identidad = (
            await db.execute(
                select(IdentidadLocal).where(IdentidadLocal.id.is_(True))
            )
        ).scalar_one_or_none()
        hardware_id = (
            identidad.hardware_id if identidad else None
        ) or obtener_hardware_id()
        try:
            info = get_license_client().validate_or_activate(
                empresa.licencia_key,
                hardware_id,
                product_code=settings.license_product_code,
            )
            lic_info = LicenseInfo(
                valid=info.valid, tier=info.tier, status=info.status
            )
        except LicenseError as e:
            raise HTTPException(
                status_code=503, detail=f"Error validando licencia: {e}"
            ) from e
        if not info.valid:
            raise HTTPException(
                status_code=403,
                detail=f"Licencia inválida o expirada: {info.message}",
            )

    pesaje = await _SERVICE.create(
        db,
        empresa,
        payload,
        licencia=lic_info,
        creado_por=current_user.nombre,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    tier = (empresa.licencia_tier or "DEMO").upper()
    inc_pesaje_creado(tier)
    pesaje = await _enriquecer_pesaje_ticket(db, pesaje)
    return _resolve_to_weighing_out(pesaje)


def _es_uuid(val: str) -> uuid.UUID | None:
    try:
        return uuid.UUID(str(val).strip())
    except (ValueError, AttributeError):
        return None


async def _buscar_pesaje(
    db: AsyncSession, id_empresa: uuid.UUID, identificador: str
) -> BoletoPesaje | None:
    identificador = str(identificador).strip()
    u = _es_uuid(identificador)
    if u is not None:
        stmt = select(BoletoPesaje).where(
            BoletoPesaje.id_empresa == id_empresa,
            or_(BoletoPesaje.boleto == u, BoletoPesaje.numero_boleto == identificador),
        )
    else:
        stmt = select(BoletoPesaje).where(
            BoletoPesaje.id_empresa == id_empresa,
            BoletoPesaje.numero_boleto == identificador,
        )
    return (await db.execute(stmt)).scalar_one_or_none()


@router.post("/close/{boleto}", response_model=WeighingOut)
async def close_weighing(
    boleto: str,
    payload: WeighingClose,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> WeighingOut:
    _verificar_peso_manual(payload.es_peso_manual, current_user)
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    pesaje_cerrado = await _SERVICE.close(
        db,
        empresa,
        pesaje.boleto,
        payload,
        salida_por=current_user.nombre,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    tier = (empresa.licencia_tier or "DEMO").upper()
    inc_pesaje_cerrado(tier)
    pesaje_cerrado = await _enriquecer_pesaje_ticket(db, pesaje_cerrado)
    out = _resolve_to_weighing_out(pesaje_cerrado)
    advertencia = getattr(pesaje_cerrado, "_advertencia_tolerancia", None)
    if advertencia:
        out.advertencia_tolerancia = advertencia
    return out


@router.put("/{boleto}/anular", response_model=WeighingOut)
async def anular_weighing(
    boleto: str,
    payload: WeighingAnular,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> WeighingOut:
    _verificar_anulacion(current_user)
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    pesaje_anulado = await _SERVICE.anular(
        db,
        empresa,
        pesaje.boleto,
        payload,
        anulado_por=current_user.nombre,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    tier = (empresa.licencia_tier or "DEMO").upper()
    inc_pesaje_anulado(tier)
    pesaje_anulado = await _enriquecer_pesaje_ticket(db, pesaje_anulado)
    return _resolve_to_weighing_out(pesaje_anulado)


@router.get("/pendientes", response_model=list[WeighingOut])
async def list_pendientes(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[WeighingOut]:
    rows = await _SERVICE.pendientes(db, empresa, skip=skip, limit=limit)
    return [_resolve_to_weighing_out(r) for r in rows]


@router.get("/list", response_model=list[WeighingOut])
async def list_weighings(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    date_from: datetime | None = None,
    date_to: datetime | None = None,
    vehicle_id: str | None = None,
    estado: str | None = None,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[WeighingOut]:
    rows, _ = await _SERVICE.list(
        db,
        empresa,
        skip=skip,
        limit=limit,
        date_from=date_from,
        date_to=date_to,
        vehicle_id=vehicle_id,
        estado=estado,
    )
    result = []
    for r in rows:
        r = await _enriquecer_pesaje_ticket(db, r)
        result.append(_resolve_to_weighing_out(r))
    return result


@router.get("/boleto/{boleto}", response_model=WeighingOut)
async def get_weighing_by_boleto(
    boleto: str,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> WeighingOut:
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    pesaje = await _enriquecer_pesaje_ticket(db, pesaje)
    return _resolve_to_weighing_out(pesaje)


async def _enriquecer_pesaje_ticket(db: AsyncSession, pesaje: BoletoPesaje) -> BoletoPesaje:
    """Resuelve entidades relacionadas con nombres y códigos legibles para evitar imprimir UUIDs.

    Popula atributos dinámicos en el objeto para que ``WeighingOut`` los serialice
    en los campos ``*_nombre`` / ``remolque_placa`` que el frontend usa en la UI.
    """
    if pesaje.id_remolque and not getattr(pesaje, "placa_remolque", None):
        r = (await db.execute(select(Remolque.placa).where(Remolque.id_remolque == pesaje.id_remolque))).scalar_one_or_none()
        if r:
            pesaje.placa_remolque = r  # type: ignore[attr-defined]
            pesaje.remolque_placa = r  # type: ignore[attr-defined]
    if pesaje.id_producto and not getattr(pesaje, "producto", None):
        prod = (await db.execute(select(Producto.nombre).where(Producto.id_producto == pesaje.id_producto))).scalar_one_or_none()
        if prod:
            pesaje.producto = prod  # type: ignore[attr-defined]
            pesaje.producto_nombre = prod  # type: ignore[attr-defined]
    if pesaje.id_conductor and not getattr(pesaje, "conductor", None):
        cond = (await db.execute(select(Conductor).where(Conductor.cedula_dni == pesaje.id_conductor))).scalar_one_or_none()
        if cond:
            nom = (cond.nombre_completo or "").strip()
            display = f"{nom} ({cond.cedula_dni})" if nom else cond.cedula_dni
            pesaje.conductor = display  # type: ignore[attr-defined]
            pesaje.conductor_nombre = display  # type: ignore[attr-defined]
    if pesaje.id_transporte and not getattr(pesaje, "transporte", None):
        t = (await db.execute(select(Transporte.razon_social).where(Transporte.id_transporte == pesaje.id_transporte))).scalar_one_or_none()
        if t:
            pesaje.transporte = t  # type: ignore[attr-defined]
            pesaje.transporte_nombre = t  # type: ignore[attr-defined]
    if pesaje.id_tercero and not getattr(pesaje, "razon_social", None):
        terc = (await db.execute(select(Tercero.razon_social).where(Tercero.id_tercero == pesaje.id_tercero))).scalar_one_or_none()
        if terc:
            pesaje.razon_social = terc  # type: ignore[attr-defined]
            pesaje.tercero_nombre = terc  # type: ignore[attr-defined]
    if pesaje.id_almacen and not getattr(pesaje, "almacen", None):
        alm = (await db.execute(select(Almacen.nombre).where(Almacen.id_almacen == pesaje.id_almacen))).scalar_one_or_none()
        if alm:
            pesaje.almacen = alm  # type: ignore[attr-defined]
            pesaje.almacen_nombre = alm  # type: ignore[attr-defined]
    if pesaje.id_balanza and not getattr(pesaje, "balanza_desc", None):
        bal = (await db.execute(select(Balanza.descripcion).where(Balanza.id_balanza == pesaje.id_balanza))).scalar_one_or_none()
        if bal:
            pesaje.balanza_desc = bal  # type: ignore[attr-defined]
            pesaje.balanza_nombre = bal  # type: ignore[attr-defined]
    return pesaje


@router.get("/{boleto}/pdf")
async def get_weighing_pdf(
    boleto: str,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> Response:
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    pesaje = await _enriquecer_pesaje_ticket(db, pesaje)
    return generar_ticket_pdf(pesaje, empresa=empresa)


@router.get("/{boleto}/txt")
async def get_weighing_txt(
    boleto: str,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> Response:
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    pesaje = await _enriquecer_pesaje_ticket(db, pesaje)
    return generar_ticket_txt(pesaje, empresa=empresa)


@router.put("/{boleto}", response_model=WeighingOut)
async def update_weighing(
    boleto: str,
    payload: WeighingUpdate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> WeighingOut:
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    pesaje_actualizado = await _SERVICE.update(
        db,
        empresa,
        pesaje.boleto,
        payload,
        modificado_por=current_user.nombre,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    pesaje_actualizado = await _enriquecer_pesaje_ticket(db, pesaje_actualizado)
    return _resolve_to_weighing_out(pesaje_actualizado)


# ---------------------------------------------------------------------------
# Imágenes de BoletoPesaje
# ---------------------------------------------------------------------------


class ImagenPesajeCreate(BaseModel):
    tipo: str = Field(..., pattern="^(placa|vehiculo|documento|entrada|salida|otros)$")
    url: str


class ImagenPesajeOut(BaseModel):
    id_imagen: uuid.UUID
    boleto: uuid.UUID
    tipo: str
    url: str


@router.get("/{boleto}/imagenes", response_model=list[ImagenPesajeOut])
async def list_imagenes(
    boleto: str,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[ImagenPesajeOut]:
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        return []
    result = await db.execute(
        select(ImagenPesaje).where(ImagenPesaje.boleto == pesaje.boleto)
    )
    return [
        ImagenPesajeOut.model_validate(img) for img in result.scalars().all()
    ]


@router.post("/{boleto}/imagenes", response_model=ImagenPesajeOut, status_code=201)
async def add_imagen(
    boleto: str,
    payload: ImagenPesajeCreate,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ImagenPesajeOut:
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")

    img = ImagenPesaje(boleto=pesaje.boleto, tipo=payload.tipo, url=payload.url)
    db.add(img)
    await db.commit()
    await db.refresh(img)
    return ImagenPesajeOut.model_validate(img)


@router.post("/{boleto}/imagenes/archivo", response_model=ImagenPesajeOut, status_code=201)
async def upload_imagen(
    boleto: str,
    file: UploadFile = File(...),
    tipo: str = Form(..., pattern="^(placa|vehiculo|documento|entrada|salida|otros)$"),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ImagenPesajeOut:
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")

    if file.content_type not in settings.allowed_image_types:
        raise HTTPException(
            status_code=400,
            detail=f"Tipo de archivo no permitido: {file.content_type}. "
            f"Permitidos: {', '.join(settings.allowed_image_types)}",
        )
    raw = await file.read()
    if len(raw) > settings.max_image_bytes:
        raise HTTPException(status_code=400, detail="El archivo supera el tamaño máximo de 10 MB")

    dest_dir = os.path.join(settings.media_dir, str(pesaje.boleto))
    os.makedirs(dest_dir, exist_ok=True)
    ext = os.path.splitext(file.filename or "image.jpg")[1] or ".jpg"
    filename = f"{tipo}_{uuid.uuid4().hex[:12]}{ext}"
    filepath = os.path.join(dest_dir, filename)
    with open(filepath, "wb") as f:
        f.write(raw)

    url = f"/media/{pesaje.boleto}/{filename}"
    img = ImagenPesaje(boleto=pesaje.boleto, tipo=tipo, url=url)
    db.add(img)
    await db.commit()
    await db.refresh(img)
    return ImagenPesajeOut.model_validate(img)


@router.delete("/{boleto}/imagenes/{id_imagen}", status_code=204)
async def delete_imagen(
    boleto: str,
    id_imagen: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")

    img_result = await db.execute(
        select(ImagenPesaje).where(
            ImagenPesaje.id_imagen == id_imagen,
            ImagenPesaje.boleto == pesaje.boleto,
        )
    )
    img = img_result.scalar_one_or_none()
    if img is None:
        raise HTTPException(status_code=404, detail="Imagen no encontrada")
    await db.delete(img)
    await db.commit()


# ---------------------------------------------------------------------------
# Peso en vivo (HAL de balanza, B7 / REQ-NF-ARQ-004)
# ---------------------------------------------------------------------------


class PesoEnVivoOut(BaseModel):
    peso_kg: float | None
    estable: bool
    conectado: bool = False
    balanza: str
    hardware: str
    timestamp: datetime


@router.get("/scale/{balanza_id}/live", response_model=PesoEnVivoOut)
async def peso_en_vivo(
    balanza_id: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    current_user: Usuario = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PesoEnVivoOut:
    result = await db.execute(
        select(Balanza).where(
            Balanza.id_balanza == balanza_id,
            Balanza.id_empresa == empresa.id_empresa,
        )
    )
    balanza = result.scalar_one_or_none()
    if balanza is None:
        raise HTTPException(status_code=404, detail="Balanza no encontrada")

    try:
        # Sesión persistente: la conexión con la balanza queda emparejada y se
        # reutiliza entre polls (no se abre/cierra en cada lectura).
        sesion = await get_scale_session_manager().obtener(balanza)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    ultimo = sesion.ultimo
    return PesoEnVivoOut(
        peso_kg=sesion.peso_kg,
        estable=sesion.estable,
        conectado=sesion.conectado,
        balanza=balanza.descripcion,
        hardware=sesion.hardware,
        timestamp=ultimo.timestamp if ultimo else datetime.now(UTC),
    )