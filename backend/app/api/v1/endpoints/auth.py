"""Rutas de autenticación y licencias."""

from __future__ import annotations

import asyncio
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import (
    get_current_empresa,
    get_current_user,
    to_user_out,
)
from app.core.config import settings
from app.core.database import get_db
from app.core.license_client import LicenseError, get_license_client
from app.core.monitoring import inc_active_user, inc_license_error
from app.core.security import (
    create_access_token,
    create_refresh_token,
    hash_password,
    verify_password,
    verify_token,
)
from app.models import BoletoPesaje, Empresa, Usuario
from app.schemas import (
    CompanyOut,
    ForgotPasswordRequest,
    LoginRequest,
    LoginResponse,
    RegisterRequest,
    ResetPasswordRequest,
    TokenResponse,
    ValidateLicenseRequest,
)
from app.services.password_reset_service import (
    reset_pwd,
    solicitar_reset_pwd,
)

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"])


def _company_out(e: Empresa) -> CompanyOut:
    return CompanyOut(
        id_empresa=e.id_empresa,
        nombre_fiscal=e.nombre_fiscal,
        nombre_comercial=e.nombre_comercial,
        rif_nit=e.rif_nit,
        licencia_tier=e.licencia_tier,
        licencia_status=e.licencia_status,
        licencia_expira=e.licencia_expira,
    )


@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register(
    payload: RegisterRequest,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Registra una empresa nueva y su primer usuario admin. Requiere una licencia válida."""
    # Validar unicidad de email y rif
    existente = (
        await db.execute(select(Usuario).where(Usuario.email == payload.email.lower()))
    ).scalar_one_or_none()
    if existente:
        raise HTTPException(status_code=400, detail="El email ya está registrado")

    rif_existente = (
        await db.execute(
            select(Empresa).where(Empresa.rif_nit == payload.empresa_rif)
        )
    ).scalar_one_or_none()
    if rif_existente:
        raise HTTPException(status_code=400, detail="El RIF/NIT ya está registrado")

    empresa = Empresa(
        nombre_fiscal=payload.empresa_nombre,
        nombre_comercial=payload.empresa_nombre,
        rif_nit=payload.empresa_rif,
        licencia_key=payload.licencia_key,
    )

    # La licencia es requisito mínimo: validarla siempre contra el LM y cachear tier/status
    try:
        info = await asyncio.to_thread(
            get_license_client().check, payload.licencia_key
        )
        empresa.licencia_tier = info.get("tier")
        empresa.licencia_status = info.get("status")
    except LicenseError as e:
        inc_license_error((empresa.licencia_tier or "UNKNOWN").upper(), "register")
        raise HTTPException(
            status_code=400,
            detail=f"No se pudo verificar la licencia en el LM: {e}",
        ) from e

    db.add(empresa)
    await db.flush()

    usuario = Usuario(
        id_empresa=empresa.id_empresa,
        nombre=payload.usuario_nombre,
        email=payload.email.lower(),
        password_hash=hash_password(payload.password),
        rol="ADMIN",
    )
    db.add(usuario)
    await db.commit()
    await db.refresh(usuario)
    await db.refresh(empresa)

    access = create_access_token(str(usuario.id_usuario), extra={"rol": usuario.rol})
    refresh = create_refresh_token(str(usuario.id_usuario))
    return {
        "access_token": access,
        "refresh_token": refresh,
        "token_type": "bearer",
        "user": to_user_out(usuario).model_dump(),
        "empresa": _company_out(empresa).model_dump(),
    }


@router.post("/login", response_model=LoginResponse)
async def login(
    payload: LoginRequest,
    db: AsyncSession = Depends(get_db),
) -> LoginResponse:
    """Login con validación de licencia de la empresa contra el LM."""
    result = await db.execute(
        select(Usuario).where(Usuario.email == payload.email.lower())
    )
    usuario = result.scalar_one_or_none()
    if usuario is None or not verify_password(payload.password, usuario.password_hash):
        raise HTTPException(status_code=401, detail="Credenciales inválidas")
    if not usuario.activo:
        raise HTTPException(status_code=403, detail="Usuario inactivo")

    empresa = (
        await db.execute(
            select(Empresa).where(Empresa.id_empresa == usuario.id_empresa)
        )
    ).scalar_one()
    if not empresa.activa:
        raise HTTPException(status_code=403, detail="Empresa inactiva")

    # Validar licencia contra el LM local
    licencia: dict | None = None
    if empresa.licencia_key:
        licencia_key = empresa.licencia_key
        try:
            info = await asyncio.to_thread(
                lambda: get_license_client().validate(
                    licencia_key,
                    payload.hardware_id or "desconocido",
                    mac_address=payload.mac_address,
                    device_brand=payload.device_brand,
                    device_model=payload.device_model,
                    os_version=payload.os_version,
                    product_code=settings.license_product_code,
                )
            )
            empresa.licencia_tier = info.tier
            empresa.licencia_status = info.status
            empresa.licencia_expira = info.expires_at
            await db.commit()
            licencia = {
                "valid": info.valid,
                "status": info.status,
                "tier": info.tier,
                "expires_at": info.expires_at.isoformat() if info.expires_at else None,
                "features": info.features,
                "message": info.message,
            }
            if not info.valid:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"Licencia inválida o expirada: {info.message}",
                )
        except LicenseError as e:
            inc_license_error((empresa.licencia_tier or "UNKNOWN").upper(), "login")
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"Error al validar licencia con el LM: {e}",
            ) from e

    inc_active_user((empresa.licencia_tier or "UNKNOWN").upper())
    access = create_access_token(str(usuario.id_usuario), extra={"rol": usuario.rol})
    refresh = create_refresh_token(str(usuario.id_usuario))
    return LoginResponse(
        access_token=access,
        refresh_token=refresh,
        user=to_user_out(usuario),
        empresa=_company_out(empresa),
        license=licencia,
    )


@router.post("/validate-license")
async def validate_license(
    payload: ValidateLicenseRequest,
    db: AsyncSession = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
) -> dict:
    """Valida en tiempo real la licencia de la empresa del usuario contra el LM."""
    empresa = (
        await db.execute(
            select(Empresa).where(Empresa.id_empresa == current_user.id_empresa)
        )
    ).scalar_one()
    try:
        info = await asyncio.to_thread(
            lambda: get_license_client().validate(
                empresa.licencia_key or payload.licencia_key,
                payload.hardware_id or "desconocido",
                product_code=settings.license_product_code,
            )
        )
    except LicenseError as e:
        inc_license_error((empresa.licencia_tier or "UNKNOWN").upper(), "validate")
        raise HTTPException(status_code=503, detail=str(e)) from e
    empresa.licencia_tier = info.tier
    empresa.licencia_status = info.status
    empresa.licencia_expira = info.expires_at
    await db.commit()
    return {
        "valid": info.valid,
        "status": info.status,
        "tier": info.tier,
        "expires_at": info.expires_at.isoformat() if info.expires_at else None,
        "features": info.features,
        "message": info.message,
    }


@router.get("/license")
async def licencia_empresa(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Snapshot de la licencia de la empresa autenticada (ADMIN hacia la UI).

    Incluye tier, estado, vencimiento, límites del tier (features) y el
    conteo actual de boletos de la empresa (uso de registros en DEMO).
    """
    tier = (empresa.licencia_tier or "").upper()
    consumo = await db.scalar(
        select(func.count())
        .select_from(BoletoPesaje)
        .where(BoletoPesaje.id_empresa == empresa.id_empresa)
    )
    max_registros = settings.demo_max_records if tier == "DEMO" else None
    key = empresa.licencia_key or ""
    key_masked = f"{key[:4]}...{key[-4:]}" if len(key) > 8 else ("••••" if key else None)
    return {
        "valid": (empresa.licencia_status or "").upper() == "ACTIVE",
        "status": empresa.licencia_status,
        "tier": empresa.licencia_tier,
        "expires_at": empresa.licencia_expira.isoformat()
        if empresa.licencia_expira
        else None,
        "features": {
            "max_registros": max_registros,
            "max_sesiones": 1,
        },
        "licencia_key_masked": key_masked,
        "registros_actuales": consumo or 0,
    }


@router.post("/refresh-token", response_model=TokenResponse)
async def refresh_token(body: dict, db: AsyncSession = Depends(get_db)) -> TokenResponse:
    refresh = body.get("refresh_token", "")
    payload = verify_token(refresh)
    if payload is None or payload.get("type") != "refresh" or "sub" not in payload:
        raise HTTPException(status_code=401, detail="Refresh token inválido")
    try:
        user_id = uuid.UUID(payload["sub"])
    except (ValueError, TypeError):
        raise HTTPException(status_code=401, detail="Refresh token inválido") from None
    usuario = (
        await db.execute(select(Usuario).where(Usuario.id_usuario == user_id))
    ).scalar_one_or_none()
    if usuario is None:
        raise HTTPException(status_code=401, detail="Usuario no encontrado")
    access = create_access_token(str(usuario.id_usuario), extra={"rol": usuario.rol})
    new_refresh = create_refresh_token(str(usuario.id_usuario))
    return TokenResponse(
        access_token=access,
        refresh_token=new_refresh,
        expires_in=settings.access_token_expire_minutes * 60,
    )


@router.post("/forgot-password")
async def forgot_password(
    payload: ForgotPasswordRequest,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Solicita un enlace de restablecimiento de contraseña.

    Siempre responde 200 (no revela si el correo existe). Si SMTP está
    deshabilitado, el enlace se registra en el log del servidor.
    """
    await solicitar_reset_pwd(db, payload.email)
    return {
        "message": (
            "Si el correo existe, recibirás un enlace para restablecer tu "
            "contraseña"
        )
    }


@router.post("/reset-password")
async def reset_password(
    payload: ResetPasswordRequest,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Restablece la contraseña con el token recibido por correo."""
    ok = await reset_pwd(db, payload.token, payload.new_password)
    if not ok:
        raise HTTPException(status_code=400, detail="Token inválido o expirado")
    return {"message": "Contraseña actualizada correctamente"}


@router.post("/logout")
async def logout(current_user: Usuario = Depends(get_current_user)) -> dict:
    # Stateless JWT: el cliente descarta el token. Se registra a nivel de auditoría.
    return {"message": "Sesión cerrada"}
