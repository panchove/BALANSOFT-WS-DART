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
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user
from app.core.config import settings
from app.core.database import get_db
from app.core.license_client import LicenseError, LicenseInfo, get_license_client
from app.core.monitoring import inc_pesaje_anulado, inc_pesaje_cerrado, inc_pesaje_creado
from app.core.scale_hal import get_scale_hal
from app.models import Balanza, BoletoPesaje, Empresa, ImagenPesaje, Usuario
from app.schemas import (
    WeighingAnular,
    WeighingClose,
    WeighingCreate,
    WeighingOut,
    WeighingUpdate,
)
from app.services.ticket_service import generar_ticket_pdf
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
    # la creación para no operar sin licencia verificada).
    lic_info: LicenseInfo | None = None
    if empresa.licencia_key:
        try:
            info = get_license_client().validate(
                empresa.licencia_key,
                "server",
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
    return _resolve_to_weighing_out(pesaje)


@router.post("/close/{boleto}", response_model=WeighingOut)
async def close_weighing(
    boleto: uuid.UUID,
    payload: WeighingClose,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> WeighingOut:
    _verificar_peso_manual(payload.es_peso_manual, current_user)
    pesaje = await _SERVICE.close(
        db,
        empresa,
        boleto,
        payload,
        salida_por=current_user.nombre,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    tier = (empresa.licencia_tier or "DEMO").upper()
    inc_pesaje_cerrado(tier)
    return _resolve_to_weighing_out(pesaje)


@router.put("/{boleto}/anular", response_model=WeighingOut)
async def anular_weighing(
    boleto: uuid.UUID,
    payload: WeighingAnular,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> WeighingOut:
    _verificar_anulacion(current_user)
    pesaje = await _SERVICE.anular(
        db,
        empresa,
        boleto,
        payload,
        anulado_por=current_user.nombre,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    tier = (empresa.licencia_tier or "DEMO").upper()
    inc_pesaje_anulado(tier)
    return _resolve_to_weighing_out(pesaje)


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
    return [_resolve_to_weighing_out(r) for r in rows]


@router.get("/boleto/{boleto}", response_model=WeighingOut)
async def get_weighing_by_boleto(
    boleto: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> WeighingOut:
    result = await db.execute(
        select(BoletoPesaje).where(
            BoletoPesaje.id_empresa == empresa.id_empresa, BoletoPesaje.boleto == boleto
        )
    )
    pesaje = result.scalar_one_or_none()
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    return _resolve_to_weighing_out(pesaje)


@router.get("/{boleto}/pdf")
async def get_weighing_pdf(
    boleto: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> Response:
    result = await db.execute(
        select(BoletoPesaje).where(
            BoletoPesaje.id_empresa == empresa.id_empresa, BoletoPesaje.boleto == boleto
        )
    )
    pesaje = result.scalar_one_or_none()
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    return generar_ticket_pdf(pesaje)


@router.put("/{boleto}", response_model=WeighingOut)
async def update_weighing(
    boleto: uuid.UUID,
    payload: WeighingUpdate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> WeighingOut:
    pesaje = await _SERVICE.update(
        db,
        empresa,
        boleto,
        payload,
        modificado_por=current_user.nombre,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return _resolve_to_weighing_out(pesaje)


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
    boleto: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[ImagenPesajeOut]:
    result = await db.execute(
        select(ImagenPesaje).where(ImagenPesaje.boleto == boleto)
    )
    return [
        ImagenPesajeOut.model_validate(img) for img in result.scalars().all()
    ]


@router.post("/{boleto}/imagenes", response_model=ImagenPesajeOut, status_code=201)
async def add_imagen(
    boleto: uuid.UUID,
    payload: ImagenPesajeCreate,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ImagenPesajeOut:
    # Verificar que el pesaje existe y pertenece a la empresa
    result = await db.execute(
        select(BoletoPesaje).where(
            BoletoPesaje.id_empresa == empresa.id_empresa, BoletoPesaje.boleto == boleto
        )
    )
    if result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")

    img = ImagenPesaje(boleto=boleto, tipo=payload.tipo, url=payload.url)
    db.add(img)
    await db.commit()
    await db.refresh(img)
    return ImagenPesajeOut.model_validate(img)


@router.post("/{boleto}/imagenes/archivo", response_model=ImagenPesajeOut, status_code=201)
async def upload_imagen(
    boleto: uuid.UUID,
    file: UploadFile = File(...),
    tipo: str = Form(..., pattern="^(placa|vehiculo|documento|entrada|salida|otros)$"),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ImagenPesajeOut:
    # Verificar que el pesaje existe y pertenece a la empresa
    result = await db.execute(
        select(BoletoPesaje).where(
            BoletoPesaje.id_empresa == empresa.id_empresa, BoletoPesaje.boleto == boleto
        )
    )
    if result.scalar_one_or_none() is None:
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

    dest_dir = os.path.join(settings.media_dir, str(boleto))
    os.makedirs(dest_dir, exist_ok=True)
    ext = os.path.splitext(file.filename or "image.jpg")[1] or ".jpg"
    filename = f"{tipo}_{uuid.uuid4().hex[:12]}{ext}"
    filepath = os.path.join(dest_dir, filename)
    with open(filepath, "wb") as f:
        f.write(raw)

    url = f"/media/{boleto}/{filename}"
    img = ImagenPesaje(boleto=boleto, tipo=tipo, url=url)
    db.add(img)
    await db.commit()
    await db.refresh(img)
    return ImagenPesajeOut.model_validate(img)


@router.delete("/{boleto}/imagenes/{id_imagen}", status_code=204)
async def delete_imagen(
    boleto: uuid.UUID,
    id_imagen: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    # Verificar que el pesaje pertenece a la empresa
    result = await db.execute(
        select(BoletoPesaje).where(
            BoletoPesaje.id_empresa == empresa.id_empresa, BoletoPesaje.boleto == boleto
        )
    )
    if result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")

    img_result = await db.execute(
        select(ImagenPesaje).where(
            ImagenPesaje.id_imagen == id_imagen,
            ImagenPesaje.boleto == boleto,
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
        hal = get_scale_hal(balanza)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    peso = await hal.read_weight()
    estable = await hal.is_stable() if peso is not None else False
    hardware = "tcp" if balanza.ip_address else "serial"

    return PesoEnVivoOut(
        peso_kg=peso,
        estable=estable,
        balanza=balanza.descripcion,
        hardware=hardware,
        timestamp=datetime.now(UTC),
    )