"""Endpoints de configuración inicial de estación (100% local, validación directa al LM).

Estos endpoints son públicos (no requieren autenticación previa) porque se
ejecutan en el primer arranque de la estación, antes de que exista cualquier
sesión de usuario. Están protegidos únicamente por rate limiting.

Flujo:
1. POST /validar-licencia  → consulta al LM y retorna datos del cliente para pre-llenar el formulario.
2. POST /crear-admin        → crea Empresa + Usuario ADMIN en DB local y retorna JWT para login automático.
"""

from __future__ import annotations

import asyncio
import logging
import re
import uuid
from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_db
from app.core.config import settings
from app.core.datetime_utils import naive_utc
from app.core.hardware import obtener_hardware_id
from app.core.license_client import LicenseError, LicenseInfo, get_license_client
from app.core.security import create_access_token, create_refresh_token, hash_password
from app.models import Empresa, Usuario
from app.schemas.setup import (
    SetupCreateAdminRequest,
    SetupCreateAdminResponse,
    SetupEmpresaOut,
    SetupLicenseOut,
    SetupUserOut,
    SetupValidateRequest,
    SetupValidateResponse,
)

router = APIRouter(prefix="/api/v1/setup", tags=["Setup inicial"])

logger = logging.getLogger(__name__)


def _mask_license_key(key: str | None) -> str | None:
    """Devuelve la clave de licencia mascarada para no exponerla completa."""
    if not key or len(key) <= 8:
        return "••••" if key else None
    return f"{key[:4]}...{key[-4:]}"


@router.post(
    "/validar-licencia",
    response_model=SetupValidateResponse,
    status_code=status.HTTP_200_OK,
    summary="Valida una licencia contra el LM antes del setup",
    description=(
        "Consulta el License Manager para verificar que la licencia exista, "
        "tenga un cliente asignado y obtener sus datos (email, nombre, ID) para "
        "pre-llenar el formulario de setup inicial. No requiere autenticación."
    ),
)
async def validar_licencia(
    payload: SetupValidateRequest,
    db: AsyncSession = Depends(get_db),
) -> SetupValidateResponse:
    license_key = payload.license_key.strip().upper()

    # Validar formato básico (misma convención que el LM: B+PREFIX-XXXX-...)
    if not re.match(
        r"^[A-Z0-9]{2,11}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$",
        license_key,
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Formato de clave de licencia inválido (esperado BWS-XXXX-XXXX-XXXX-XXXX)",
        )

    client = get_license_client()

    try:
        # /check no requiere token y retorna datos del cliente asociado
        check_data = await asyncio.to_thread(client.check, license_key)
    except LicenseError as e:
        logger.warning("LM inaccesible para validar-licencia: %s", e)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"El License Manager no está disponible: {e}",
        ) from e

    if not check_data.get("exists", False):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="La licencia no existe en el License Manager",
        )

    if not check_data.get("has_client", False):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La licencia no tiene un cliente asignado en el License Manager. Contacte a su distribuidor.",
        )

    # Si se proveyó hardware_id, intentar validar en tiempo real para obtener
    # expires_at y confirmar vigencia.
    expires_at: datetime | None = None
    valid = True
    license_status = check_data.get("status")
    tier = check_data.get("tier")

    if payload.hardware_id:
        try:
            info: LicenseInfo = await asyncio.to_thread(
                client.validate_or_activate,
                license_key,
                payload.hardware_id,
                mac_address=payload.mac_address,
                device_brand=payload.device_brand,
                device_model=payload.device_model,
                os_version=payload.os_version,
                product_code=settings.license_product_code,
            )
            valid = bool(info.valid)
            license_status = info.status or license_status
            tier = info.tier or tier
            expires_at = naive_utc(info.expires_at)
            if not info.valid:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"La licencia no es válida: {info.message or 'Estado no permitido'}",
                )
        except LicenseError as e:
            logger.warning("LM validate_or_activate falló en validar-licencia: %s", e)
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"El License Manager no respondió a la validación: {e}",
            ) from e

    return SetupValidateResponse(
        valid=valid,
        status=license_status,
        tier=tier,
        expires_at=expires_at,
        client_email=check_data.get("client_email"),
        client_name=check_data.get("client_name"),
        client_id=check_data.get("client_id"),
        message=check_data.get("message") or "Licencia válida en el License Manager",
        licencia_key_masked=_mask_license_key(license_key),
    )


@router.post(
    "/crear-admin",
    response_model=SetupCreateAdminResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Crea la empresa y el primer usuario ADMIN en la estación",
    description=(
        "Crea la Empresa y el Usuario ADMIN en la base de datos local, válida la "
        "licencia contra el LM y retorna un JWT para iniciar sesión automáticamente. "
        "Solo puede ejecutarse una vez (si ya existe una empresa responde 409). "
        "No requiere autenticación previa."
    ),
)
async def crear_admin(
    payload: SetupCreateAdminRequest,
    db: AsyncSession = Depends(get_db),
) -> SetupCreateAdminResponse:
    license_key = payload.license_key.strip().upper()

    # --- Idempotencia: la DB local no debe tener ya una empresa ---
    existe = (
        await db.execute(select(Empresa).limit(1))
    ).scalar_one_or_none()
    if existe is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="La estación ya tiene una empresa configurada. No se puede crear otra.",
        )

    # --- Validar licencia contra el LM (obtener client_email y client_id) ---
    client = get_license_client()

    try:
        check_data = await asyncio.to_thread(client.check, license_key)
    except LicenseError as e:
        logger.warning("LM inaccesible en crear-admin: %s", e)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"El License Manager no está disponible: {e}",
        ) from e

    if not check_data.get("exists", False):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="La licencia no existe en el License Manager",
        )

    if not check_data.get("has_client", False):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La licencia no tiene un cliente asignado en el License Manager.",
        )

    client_email = check_data.get("client_email")
    client_id = check_data.get("client_id")
    client_name = check_data.get("client_name")

    if not client_email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El License Manager no devolvió un email de cliente para esta licencia.",
        )

    # --- Validar vigencia en tiempo real contra el LM ---
    hardware_id = obtener_hardware_id()
    try:
        info: LicenseInfo = await asyncio.to_thread(
            client.validate_or_activate,
            license_key,
            hardware_id,
            product_code=settings.license_product_code,
        )
    except LicenseError as e:
        logger.warning("LM validate_or_activate falló en crear-admin: %s", e)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"El License Manager no respondió a la validación: {e}",
        ) from e

    if not bool(info.valid):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"La licencia no es válida: {info.message or 'Estado no permitido'}",
        )

    # --- Validación de tier: solo CENTRAL o DEMO ---
    if info.tier == 'MONOPUESTO':
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Licencia MONOPUESTO no soportada. Esta versión requiere licencia CENTRAL o DEMO.",
        )

    # --- Crear Empresa ---
    ahora = datetime.now(UTC).replace(tzinfo=None)
    lm_client_id_uuid: uuid.UUID | None = None
    if client_id:
        try:
            lm_client_id_uuid = uuid.UUID(str(client_id))
        except (ValueError, AttributeError):
            lm_client_id_uuid = None

    empresa = Empresa(
        nombre_fiscal=client_name or client_email.split("@")[0],
        nombre_comercial=payload.nombre_comercial,
        rif_nit=payload.rif_nit,
        direccion=payload.direccion,
        telefono=payload.telefono,
        email=client_email,
        logo_url=payload.logo_url,
        licencia_key=license_key,
        licencia_tier=info.tier,
        licencia_status=info.status,
        licencia_expira=naive_utc(info.expires_at),
        lm_client_id=lm_client_id_uuid,
        lm_client_email=client_email,
        activa=True,
        created_at=ahora,
        updated_at=ahora,
    )
    db.add(empresa)
    await db.flush()  # para obtener id_empresa

    # --- Crear Usuario ADMIN ---
    usuario = Usuario(
        id_empresa=empresa.id_empresa,
        nombre=client_email.split("@")[0],
        email=client_email,
        password_hash=hash_password(payload.password),
        rol="ADMIN",
        activo=True,
        created_at=ahora,
        updated_at=ahora,
    )
    db.add(usuario)
    await db.commit()
    await db.refresh(empresa)
    await db.refresh(usuario)

    # --- Generar JWT local ---
    access_token = create_access_token(
        str(usuario.id_usuario), extra={"rol": usuario.rol}
    )
    refresh_token = create_refresh_token(str(usuario.id_usuario))

    return SetupCreateAdminResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
        expires_in=settings.access_token_expire_minutes * 60,
        user=SetupUserOut(
            id_usuario=usuario.id_usuario,
            nombre=usuario.nombre,
            email=usuario.email,
            rol=usuario.rol,
            id_empresa=usuario.id_empresa,
        ),
        empresa=SetupEmpresaOut(
            id_empresa=empresa.id_empresa,
            nombre_fiscal=empresa.nombre_fiscal,
            nombre_comercial=empresa.nombre_comercial,
            rif_nit=empresa.rif_nit,
            direccion=empresa.direccion,
            telefono=empresa.telefono,
            email=empresa.email,
            logo_url=empresa.logo_url,
            licencia_tier=empresa.licencia_tier,
            licencia_status=empresa.licencia_status,
            licencia_expira=empresa.licencia_expira,
            lm_client_id=empresa.lm_client_id,
            lm_client_email=empresa.lm_client_email,
            activa=empresa.activa,
            created_at=empresa.created_at,
        ),
        license=SetupLicenseOut(
            valid=bool(info.valid),
            status=info.status,
            tier=info.tier,
            expires_at=info.expires_at,
            message=info.message or "Licencia activada y verificada",
        ),
    )
