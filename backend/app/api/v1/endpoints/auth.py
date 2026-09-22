"""Rutas de autenticación y licencias."""

from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime

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
from app.core.hardware import obtener_hardware_id
from app.core.license_client import LicenseError, get_license_client
from app.core.monitoring import inc_active_user, inc_license_error
from app.core.security import (
    create_access_token,
    create_refresh_token,
    hash_password,
    verify_password,
    verify_token,
)
from app.models import BoletoPesaje, Empresa, IdentidadLocal, Usuario
from app.schemas import (
    CompanyOut,
    ForgotPasswordRequest,
    LoginCentralRequest,
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
        formato_ticket=getattr(e, "formato_ticket", "PDF"),
        ruta_exportacion_reportes=getattr(e, "ruta_exportacion_reportes", None),
    )


async def _persistir_hardware_id(
    db: AsyncSession, empresa: Empresa, hardware_id: str
) -> None:
    """Cachea el fingerprint de la estación en ``identidad_local``.

    Así ``create_weighing`` valida la licencia con el mismo ``hardware_id``
    que el login (evita DEVICE_NOT_REGISTERED en licencias CENTRAL).
    """
    identidad = (
        await db.execute(
            select(IdentidadLocal).where(IdentidadLocal.id.is_(True))
        )
    ).scalar_one_or_none()
    if identidad is None:
        identidad = IdentidadLocal(
            id=True,
            id_cuenta=empresa.id_empresa,
            rif_nit=empresa.rif_nit,
            nombre_fiscal=empresa.nombre_fiscal,
            nombre_comercial=empresa.nombre_comercial,
        )
        db.add(identidad)
    identidad.hardware_id = hardware_id
    identidad.ultima_validacion = datetime.now(UTC).replace(tzinfo=None)


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
        hardware_id = payload.hardware_id or obtener_hardware_id()
        try:
            info = await asyncio.to_thread(
                lambda: get_license_client().validate_or_activate(
                    licencia_key,
                    hardware_id,
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
            await _persistir_hardware_id(db, empresa, hardware_id)
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


@router.post("/login-central", response_model=LoginResponse)
async def login_central(
    payload: LoginCentralRequest,
    db: AsyncSession = Depends(get_db),
) -> LoginResponse:
    """Login CENTRAL-first.

    Valida la cuenta+credencial contra el serVIDOR central (la DB del panel
    que mantiene la licencia). Si la cuenta existe y la licencia lo permite,
    hace **espejo local** (empresa + usuario admin + identidad_local) para que
    la estación pueda seguir operando offline y emite los tokens locales.

    Errores de red se propagan como 502 para que el cliente caiga al modo
    offline; 401/403 del central (credencial inválida o límite de sesiones de
    la licencia) se devuelven tal cual.
    """
    server_url = (payload.server_url or settings.server_api_url or "").strip().rstrip("/")
    if not server_url:
        raise HTTPException(
            status_code=400,
            detail="No hay URL del servidor central configurada",
        )

    import socket

    import httpx

    # 1) Validar la cuenta en el panel (DB del servidor central).
    cuerpo = {
        "email": payload.email,
        "password": payload.password,
        "hardware_id": payload.hardware_id or obtener_hardware_id(),
        "nombre_equipo": payload.nombre_equipo or socket.gethostname(),
        "sistema_operativo": payload.sistema_operativo,
        "version_app": payload.version_app,
        "mac_address": payload.mac_address,
        "device_brand": payload.device_brand,
        "device_model": payload.device_model,
    }
    try:
        resp = await httpx.AsyncClient(timeout=10, follow_redirects=True).post(
            f"{server_url}/api/v1/auth/login", json=cuerpo
        )
    except httpx.TransportError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"No se pudo conectar con el servidor central: {exc}",
        ) from exc

    if resp.status_code != 200:
        detalle = "Error al validar la cuenta en el servidor central"
        try:
            datos = resp.json()
            detalle = datos.get("detail") or detalle
        except Exception:  # noqa: BLE001 - respuesta no JSON del central
            pass
        codigo = resp.status_code if resp.status_code in (400, 401, 403) else 502
        raise HTTPException(status_code=codigo, detail=detalle)

    central = resp.json()
    usuario_central = central.get("user") or {}
    cuenta = central.get("cuenta") or {}
    licencia = central.get("licencia") or {}
    now = datetime.now(UTC).replace(tzinfo=None)

    # 2) Espejo local: empresa única por RIF/NIT.
    rif = (cuenta.get("rif_nit") or "").upper()
    if not rif:
        raise HTTPException(status_code=502, detail="El central no devolvió los datos de la cuenta")
    empresa = (
        await db.execute(select(Empresa).where(Empresa.rif_nit == rif))
    ).scalar_one_or_none()
    if empresa is None:
        empresa = Empresa(rif_nit=rif, activa=True)
        db.add(empresa)
    empresa.nombre_fiscal = cuenta.get("nombre_fiscal") or empresa.nombre_fiscal or rif
    empresa.nombre_comercial = cuenta.get("nombre_comercial") or empresa.nombre_fiscal
    empresa.licencia_key = licencia.get("licencia_key") or empresa.licencia_key
    empresa.licencia_tier = licencia.get("licencia_tier") or empresa.licencia_tier
    empresa.licencia_status = licencia.get("licencia_status") or empresa.licencia_status
    fecha_expira = licencia.get("fecha_expira")
    if fecha_expira and isinstance(fecha_expira, str):
        try:
            empresa.licencia_expira = datetime.fromisoformat(
                fecha_expira.replace("Z", "+00:00")
            ).replace(tzinfo=None)
        except ValueError:
            pass
    empresa.activa = bool(cuenta.get("activa", True))
    await db.flush()

    # 3) Usuario admin local = espejo de la credencial global.
    email_local = str(usuario_central.get("email") or payload.email).lower()
    id_credencial = usuario_central.get("id_credencial")
    usuario_admin = (
        await db.execute(
            select(Usuario).where(
                Usuario.email == email_local, Usuario.id_empresa == empresa.id_empresa
            )
        )
    ).scalar_one_or_none()
    if usuario_admin is None:
        usuario_admin = Usuario(
            id_empresa=empresa.id_empresa,
            nombre=str(usuario_central.get("email") or payload.email).split("@")[0],
            email=email_local,
            rol=usuario_central.get("rol_global") or "ADMIN",
        )
        db.add(usuario_admin)
    usuario_admin.password_hash = hash_password(payload.password)
    usuario_admin.activo = True
    if id_credencial:
        usuario_admin.id_credencial = uuid.UUID(str(id_credencial))
    await db.flush()

    # 4) Identidad local (vínculo singleton con la cuenta del servidor).
    identidad = (
        await db.execute(select(IdentidadLocal).where(IdentidadLocal.id.is_(True)))
    ).scalar_one_or_none()
    if identidad is None:
        identidad = IdentidadLocal(id=True)
        db.add(identidad)
    identidad.id_cuenta = uuid.UUID(str(cuenta.get("id_cuenta") or empresa.id_empresa))
    identidad.rif_nit = rif
    identidad.nombre_fiscal = empresa.nombre_fiscal
    identidad.nombre_comercial = empresa.nombre_comercial
    identidad.licencia_key = empresa.licencia_key
    identidad.licencia_tier = empresa.licencia_tier
    identidad.licencia_status = empresa.licencia_status
    identidad.licencia_expira = empresa.licencia_expira
    identidad.hardware_id = payload.hardware_id or obtener_hardware_id()
    identidad.ultima_validacion = now
    identidad.modo_offline = False

    inc_active_user((empresa.licencia_tier or "UNKNOWN").upper())
    await db.commit()
    await db.refresh(usuario_admin)
    await db.refresh(empresa)

    access = create_access_token(str(usuario_admin.id_usuario), extra={"rol": usuario_admin.rol})
    refresh = create_refresh_token(str(usuario_admin.id_usuario))
    licencia_local: dict | None = {
        "valid": True,
        "status": empresa.licencia_status,
        "tier": empresa.licencia_tier,
        "expires_at": empresa.licencia_expira.isoformat()
        if empresa.licencia_expira
        else None,
        "features": {
            "max_usuarios": licencia.get("max_usuarios"),
            "max_equipos": licencia.get("max_equipos"),
            "max_sesiones": licencia.get("max_sesiones"),
        },
        "message": "Cuenta validada en el servidor central",
    }
    return LoginResponse(
        access_token=access,
        refresh_token=refresh,
        user=to_user_out(usuario_admin),
        empresa=_company_out(empresa),
        license=licencia_local,
    )


@router.post("/login-local", response_model=LoginResponse)
async def login_local(
    payload: LoginRequest,
    db: AsyncSession = Depends(get_db),
) -> LoginResponse:
    """Login OFFLINE: valida credenciales locales SIN consultar el LM.

    Pensado para el modo sin conexión de la estación (docs/MANEJO_DB.md):
    en ausencia de red no se puede validar la licencia, pero el operador debe
    poder seguir trabajando. El token emitido lleva la marca ``offline: true``.
    """
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

    access = create_access_token(
        str(usuario.id_usuario), extra={"rol": usuario.rol, "offline": True}
    )
    refresh = create_refresh_token(str(usuario.id_usuario))
    return LoginResponse(
        access_token=access,
        refresh_token=refresh,
        user=to_user_out(usuario),
        empresa=_company_out(empresa),
        license=None,
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
    licencia_key = empresa.licencia_key or payload.licencia_key
    if not licencia_key:
        raise HTTPException(
            status_code=400,
            detail="La empresa no tiene una licencia configurada",
        )
    hardware_id = payload.hardware_id or obtener_hardware_id()
    try:
        info = await asyncio.to_thread(
            lambda: get_license_client().validate_or_activate(
                licencia_key,
                hardware_id,
                product_code=settings.license_product_code,
            )
        )
    except LicenseError as e:
        inc_license_error((empresa.licencia_tier or "UNKNOWN").upper(), "validate")
        raise HTTPException(status_code=503, detail=str(e)) from e
    empresa.licencia_tier = info.tier
    empresa.licencia_status = info.status
    empresa.licencia_expira = info.expires_at
    await _persistir_hardware_id(db, empresa, hardware_id)
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
    max_registros = settings.demo_max_records if tier == "DEMO" else None
    max_sesiones = None if tier == "CENTRAL" else (3 if tier == "DEMO" else 1)
    consumo = await db.scalar(
        select(func.count())
        .select_from(BoletoPesaje)
        .where(BoletoPesaje.id_empresa == empresa.id_empresa)
    )
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
            "max_sesiones": max_sesiones,
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
