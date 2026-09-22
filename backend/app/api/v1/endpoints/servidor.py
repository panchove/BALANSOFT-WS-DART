"""API del SERVIDOR: cuenta, licencia, credenciales globales y sync.

Solo se monta cuando ``APP_ROLE=server`` (docs/MANEJO_DB.md). Opera sobre la
DB del servidor (``app.models_server``) y NO toca datos operativos de las
estaciones. Las estaciones locales usan la API estándar (APP_ROLE=local).
"""

from __future__ import annotations

import asyncio
import hashlib
import uuid
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_server_db
from app.core.license_client import LicenseError, get_license_client
from app.core.security import (
    create_access_token,
    create_refresh_token,
    hash_password,
    verify_password,
    verify_token,
)
from app.models_server import (
    AuditoriaServidor,
    Credencial,
    Cuenta,
    Dispositivo,
    Licencia,
    ProveedorUsuario,
    Sesion,
    SyncColaItem,
    SyncSesion,
)
from app.schemas_server import (
    PanelCredencialOut,
    PanelCuentaDetalleOut,
    PanelCuentaUpdateRequest,
    PanelLoginRequest,
    PanelLoginResponse,
    PanelVerificarLicenciaRequest,
    PanelVerificarLicenciaResponse,
    ServerCredencialOut,
    ServerCuentaOut,
    ServerLicenciaNuevaRequest,
    ServerLicenciaOut,
    ServerLoginRequest,
    ServerLoginResponse,
    ServerRegisterRequest,
    ServerSyncPushRequest,
    ServerSyncPushResponse,
    ServerSyncUsersRequest,
    ServerSyncUsersResponse,
    ServerTokenResponse,
)

router = APIRouter()


def _naive_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is not None:
        return value.astimezone(UTC).replace(tzinfo=None)
    return value


def _token_digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _max_sesiones_default(tier: str) -> int | None:
    """Sesiones concurrentes por defecto según tier de la licencia.

    DEMO → 1, MONOPUESTA → 2, CENTRAL/AUTO → ilimitado (None).
    """
    upper = (tier or "").strip().upper()
    if upper.startswith("MONO"):
        return 2
    if upper == "DEMO":
        return 1
    return None


async def _auditar(
    db: AsyncSession,
    accion: str,
    id_cuenta: uuid.UUID | None = None,
    id_credencial: uuid.UUID | None = None,
    entidad: str | None = None,
    entidad_id: str | None = None,
    detalle: dict | None = None,
    ip: str | None = None,
) -> None:
    db.add(
        AuditoriaServidor(
            id_cuenta=id_cuenta,
            id_credencial=id_credencial,
            accion=accion,
            entidad=entidad,
            entidad_id=entidad_id,
            detalle=detalle,
            ip=ip,
        )
    )


async def _licencia_activa(db: AsyncSession, id_cuenta: uuid.UUID) -> Licencia:
    result = await db.execute(
        select(Licencia)
        .where(
            Licencia.id_cuenta == id_cuenta,
            Licencia.licencia_status == "ACTIVA",
            Licencia.fecha_expira >= datetime.now(UTC).replace(tzinfo=None),
        )
        .order_by(Licencia.fecha_expira)
        .limit(1)
    )
    licencia = result.scalar_one_or_none()
    if licencia is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="La cuenta no dispone de una licencia activa",
        )
    return licencia


async def _dispositivo(
    db: AsyncSession, id_cuenta: uuid.UUID, hardware_id: str, payload: ServerLoginRequest
) -> Dispositivo:
    result = await db.execute(
        select(Dispositivo).where(Dispositivo.hardware_id == hardware_id)
    )
    disp = result.scalar_one_or_none()
    now = datetime.now(UTC).replace(tzinfo=None)
    if disp is None:
        disp = Dispositivo(
            id_cuenta=id_cuenta,
            hardware_id=hardware_id,
            nombre_equipo=payload.nombre_equipo,
            sistema_operativo=payload.sistema_operativo,
            version_app=payload.version_app,
            rol_dispositivo="LOCAL",
            ultima_conexion=now,
        )
        db.add(disp)
    else:
        if disp.id_cuenta != id_cuenta:
            raise HTTPException(
                status_code=403, detail="Dispositivo registrado en otra cuenta"
            )
        if disp.id_licencia is not None:
            lic = await db.get(Licencia, disp.id_licencia)
            if lic is not None and lic.licencia_status != "ACTIVA":
                disp.activo = False
        disp.ultima_conexion = now
        disp.nombre_equipo = payload.nombre_equipo or disp.nombre_equipo
        disp.sistema_operativo = payload.sistema_operativo or disp.sistema_operativo
        disp.version_app = payload.version_app or disp.version_app
    await db.flush()
    return disp


async def _verificar_limite_sync(db: AsyncSession, cred: Credencial) -> None:
    """Blinda la sincronización contra cuentas que estén sobre su límite de
    sesiones.

    Cuando una cuenta supera las sesiones concurrentes autorizadas por su
    licencia (``max_sesiones``), las estaciones ya abiertas se mantienen
    operando en local pero NO pueden compartir información entre sí: cualquier
    push/pull de sync se rechaza con 403 hasta liberar una sesión.
    """
    licencia = await _licencia_activa(db, cred.id_cuenta)
    if licencia.max_sesiones is None:
        return
    now = datetime.now(UTC).replace(tzinfo=None)
    activas = (
        await db.execute(
            select(Sesion.id_sesion)
            .join(Credencial, Sesion.id_credencial == Credencial.id_credencial)
            .where(
                Credencial.id_cuenta == cred.id_cuenta,
                Sesion.revocada.is_(False),
                Sesion.expira > now,
            )
        )
    ).scalars().all()
    if len(activas) > licencia.max_sesiones:
        raise HTTPException(
            status_code=403,
            detail=(
                "La cuenta supera el límite de sesiones de la licencia "
                f"({licencia.max_sesiones}); cierre sesiones para sincronizar"
            ),
        )


# ---------------------------------------------------------------------------
# Dependencia de autenticación del servidor (credencial global)
# ---------------------------------------------------------------------------


async def get_server_credencial(
    authorization: str | None = Header(None),
    db: AsyncSession = Depends(get_server_db),
) -> Credencial:
    """Valida el Bearer JWT contra la tabla de credenciales globales."""
    from fastapi.security.utils import get_authorization_scheme_param

    if authorization is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Autenticación requerida",
            headers={"WWW-Authenticate": "Bearer"},
        )
    scheme, token = get_authorization_scheme_param(authorization)
    if scheme.lower() != "bearer":
        raise HTTPException(status_code=401, detail="Esquema de autenticación inválido")
    payload = verify_token(token)
    if payload is None or "sub" not in payload:
        raise HTTPException(status_code=401, detail="Token inválido o expirado")
    try:
        cred_id = uuid.UUID(payload["sub"])
    except (ValueError, TypeError):
        raise HTTPException(status_code=401, detail="Token inválido") from None
    cred = (
        await db.execute(
            select(Credencial).where(
                Credencial.id_credencial == cred_id, Credencial.activo.is_(True)
            )
        )
    ).scalar_one_or_none()
    if cred is None:
        raise HTTPException(status_code=404, detail="Credencial no encontrada")
    return cred


async def get_server_proveedor(
    authorization: str | None = Header(None),
    db: AsyncSession = Depends(get_server_db),
) -> ProveedorUsuario:
    """Valida el Bearer JWT contra el panel del proveedor."""
    from fastapi.security.utils import get_authorization_scheme_param

    if authorization is None:
        raise HTTPException(status_code=401, detail="Autenticación requerida")
    scheme, token = get_authorization_scheme_param(authorization)
    if scheme.lower() != "bearer":
        raise HTTPException(status_code=401, detail="Esquema de autenticación inválido")
    payload = verify_token(token)
    if payload is None or "sub" not in payload or payload.get("tipo") != "proveedor":
        raise HTTPException(status_code=401, detail="Token inválido o expirado")
    try:
        user_id = uuid.UUID(payload["sub"])
    except (ValueError, TypeError):
        raise HTTPException(status_code=401, detail="Token inválido") from None
    user = (
        await db.execute(
            select(ProveedorUsuario).where(
                ProveedorUsuario.id_usuario == user_id,
                ProveedorUsuario.activo.is_(True),
            )
        )
    ).scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=404, detail="Usuario del panel no encontrado")
    return user


# ---------------------------------------------------------------------------
# Autenticación del servidor
# ---------------------------------------------------------------------------


@router.post("/api/v1/auth/register", status_code=status.HTTP_201_CREATED)
async def server_register(
    payload: ServerRegisterRequest,
    db: AsyncSession = Depends(get_server_db),
) -> ServerLoginResponse:
    """Alta central de una cuenta con licencia y credencial ADMIN."""
    cif = payload.empresa_rif.strip().upper()
    email = payload.email_admin.lower()
    if (await db.execute(select(Cuenta).where(Cuenta.rif_nit == cif))).scalar_one_or_none():
        raise HTTPException(status_code=400, detail="El RIF/NIT ya está registrado")
    if (await db.execute(select(Cuenta).where(Cuenta.email_admin == email))).scalar_one_or_none():
        raise HTTPException(status_code=400, detail="El email ya está registrado")
    if (await db.execute(select(Credencial).where(Credencial.email == email))).scalar_one_or_none():
        raise HTTPException(status_code=400, detail="La credencial ya existe")

    cuenta = Cuenta(
        rif_nit=cif,
        nombre_fiscal=payload.empresa_nombre,
        nombre_comercial=payload.empresa_nombre,
        email_admin=email,
        telefono=payload.telefono,
        direccion=payload.direccion,
        activa=True,
    )
    db.add(cuenta)
    await db.flush()

    licencia = Licencia(
        id_cuenta=cuenta.id_cuenta,
        licencia_key=payload.licencia_key.strip().upper(),
        licencia_tier=payload.licencia_tier,
        licencia_status="ACTIVA",
        fecha_expira=_naive_utc(payload.fecha_expira) or datetime.now(UTC),
        max_usuarios=payload.max_usuarios,
        max_equipos=payload.max_equipos,
        max_sesiones=(
            payload.max_sesiones
            if payload.max_sesiones is not None
            else _max_sesiones_default(payload.licencia_tier)
        ),
    )
    db.add(licencia)

    credencial = Credencial(
        id_cuenta=cuenta.id_cuenta,
        email=email,
        password_hash=hash_password(payload.password),
        rol_global="ADMIN",
    )
    db.add(credencial)
    await _auditar(
        db,
        "cuenta_registrada",
        id_cuenta=cuenta.id_cuenta,
        detalle={"tier": payload.licencia_tier, "empresa": payload.empresa_nombre},
    )
    await db.commit()

    await db.refresh(cuenta)
    await db.refresh(licencia)
    await db.refresh(credencial)
    access = create_access_token(str(credencial.id_credencial), extra={"rol": "ADMIN"})
    refresh = create_refresh_token(str(credencial.id_credencial))
    return ServerLoginResponse(
        access_token=access,
        refresh_token=refresh,
        user=ServerCredencialOut(
            id_credencial=credencial.id_credencial,
            id_cuenta=credencial.id_cuenta,
            email=credencial.email,
            rol_global=credencial.rol_global,
        ),
        cuenta=ServerCuentaOut.model_validate(cuenta),
        licencia=ServerLicenciaOut.model_validate(licencia),
    )


@router.post("/api/v1/auth/login", response_model=ServerLoginResponse)
async def server_login(
    payload: ServerLoginRequest,
    db: AsyncSession = Depends(get_server_db),
) -> ServerLoginResponse:
    """Login global: valida credencial + licencia y registra el dispositivo."""
    email = payload.email.lower()
    cred = (
        await db.execute(select(Credencial).where(Credencial.email == email))
    ).scalar_one_or_none()
    if cred is None or not verify_password(payload.password, cred.password_hash):
        raise HTTPException(status_code=401, detail="Credenciales inválidas")
    if not cred.activo:
        raise HTTPException(status_code=403, detail="Credencial inactiva")
    cuenta = await db.get(Cuenta, cred.id_cuenta)
    if cuenta is None or not cuenta.activa:
        raise HTTPException(status_code=403, detail="Cuenta inactiva")

    licencia = await _licencia_activa(db, cuenta.id_cuenta)
    disp = await _dispositivo(db, cuenta.id_cuenta, payload.hardware_id, payload)
    if licencia.max_equipos is not None:
        equipo_count = (
            await db.execute(
                select(Dispositivo.id_dispositivo).where(
                    Dispositivo.id_cuenta == cuenta.id_cuenta, Dispositivo.activo.is_(True)
                )
            )
        ).scalars().all()
        if len(equipo_count) > licencia.max_equipos:
            raise HTTPException(
                status_code=403,
                detail="La licencia no autoriza más equipos para sincronizar",
            )
    disp.id_licencia = licencia.id_licencia

    # Rotación por dispositivo: quien vuelve a entrar aquí cierra sus sesiones
    # anteriores para no auto-bloquearse con su propio límite.
    now = datetime.now(UTC).replace(tzinfo=None)
    sesiones_previas = (
        await db.execute(
            select(Sesion).where(
                Sesion.id_credencial == cred.id_credencial,
                Sesion.id_dispositivo == disp.id_dispositivo,
                Sesion.revocada.is_(False),
                Sesion.expira > now,
            )
        )
    ).scalars().all()
    for sen_prev in sesiones_previas:
        sen_prev.revocada = True
    # La sesión del servidor no usa autoflush: materializar la rotación antes
    # de contar las sesiones activas para evitar auto-bloqueos.
    await db.flush()

    # Límite de sesiones concurrentes de la licencia, contadas a nivel de
    # cuenta (todas las credenciales y dispositivos de la misma empresa).
    if licencia.max_sesiones is not None:
        activas = (
            await db.execute(
                select(Sesion.id_sesion)
                .join(Credencial, Sesion.id_credencial == Credencial.id_credencial)
                .where(
                    Credencial.id_cuenta == cuenta.id_cuenta,
                    Sesion.revocada.is_(False),
                    Sesion.expira > now,
                )
            )
        ).scalars().all()
        if len(activas) >= licencia.max_sesiones:
            raise HTTPException(
                status_code=403,
                detail=(
                    f"Límite de sesiones de la licencia alcanzado "
                    f"({licencia.max_sesiones} simultáneas)"
                ),
            )

    cred.ultimo_login = now
    access = create_access_token(str(cred.id_credencial), extra={"rol": cred.rol_global})
    refresh = create_refresh_token(str(cred.id_credencial))
    db.add(
        Sesion(
            id_credencial=cred.id_credencial,
            id_dispositivo=disp.id_dispositivo,
            token_hash=_token_digest(refresh),
            expira=now + timedelta(days=7),
        )
    )
    await _auditar(
        db,
        "login",
        id_cuenta=cuenta.id_cuenta,
        id_credencial=cred.id_credencial,
        entidad="dispositivo",
        entidad_id=disp.hardware_id,
    )
    await db.commit()
    await db.refresh(disp)

    return ServerLoginResponse(
        access_token=access,
        refresh_token=refresh,
        user=ServerCredencialOut(
            id_credencial=cred.id_credencial,
            id_cuenta=cred.id_cuenta,
            email=cred.email,
            rol_global=cred.rol_global,
        ),
        cuenta=ServerCuentaOut.model_validate(cuenta),
        licencia=ServerLicenciaOut.model_validate(licencia),
        dispositivo={
            "id_dispositivo": str(disp.id_dispositivo),
            "hardware_id": disp.hardware_id,
            "rol": disp.rol_dispositivo,
            "activo": disp.activo,
        },
    )


@router.post("/api/v1/auth/refresh-token", response_model=ServerTokenResponse)
async def server_refresh_token(
    body: dict,
    db: AsyncSession = Depends(get_server_db),
) -> ServerTokenResponse:
    refresh = body.get("refresh_token", "")
    payload = verify_token(refresh)
    if payload is None or payload.get("type") != "refresh" or "sub" not in payload:
        raise HTTPException(status_code=401, detail="Refresh token inválido")

    # Revocar la sesión previa (por huella del refresh) y emitir un par nuevo.
    sen = (
        await db.execute(
            select(Sesion).where(Sesion.token_hash == _token_digest(refresh))
        )
    ).scalar_one_or_none()
    if sen is not None:
        sen.revocada = True
    try:
        cred_id = uuid.UUID(payload["sub"])
    except (ValueError, TypeError):
        raise HTTPException(status_code=401, detail="Refresh token inválido") from None
    cred = await db.get(Credencial, cred_id)
    if cred is None or not cred.activo:
        raise HTTPException(status_code=401, detail="Credencial no encontrada")
    access = create_access_token(str(cred.id_credencial), extra={"rol": cred.rol_global})
    new_refresh = create_refresh_token(str(cred.id_credencial))
    db.add(
        Sesion(
            id_credencial=cred.id_credencial,
            token_hash=_token_digest(new_refresh),
            expira=datetime.now(UTC).replace(tzinfo=None) + timedelta(days=7),
        )
    )
    await db.commit()
    return ServerTokenResponse(
        access_token=access, refresh_token=new_refresh, expires_in=1800
    )


# ---------------------------------------------------------------------------
# Licencias (consulta y alta)
# ---------------------------------------------------------------------------


@router.get("/api/v1/licencias")
async def listar_licencias(
    cred: Credencial = Depends(get_server_credencial),
    db: AsyncSession = Depends(get_server_db),
) -> list[dict]:
    """Licencias de la cuenta autenticada."""
    result = await db.execute(
        select(Licencia).where(Licencia.id_cuenta == cred.id_cuenta)
    )
    return [
        ServerLicenciaOut.model_validate(lic).model_dump(mode="json")
        for lic in result.scalars()
    ]


@router.post("/api/v1/licencias", status_code=status.HTTP_201_CREATED)
async def alta_licencia(
    payload: ServerLicenciaNuevaRequest,
    cred: Credencial = Depends(get_server_credencial),
    db: AsyncSession = Depends(get_server_db),
) -> dict:
    """Da de alta una licencia adicional (solo ADMIN global)."""
    if cred.rol_global != "ADMIN":
        raise HTTPException(status_code=403, detail="Se requiere rol ADMIN global")
    cuenta = await db.get(Cuenta, payload.id_cuenta)
    if cuenta is None:
        raise HTTPException(status_code=404, detail="Cuenta no encontrada")
    existe = (
        await db.execute(
            select(Licencia).where(
                Licencia.licencia_key == payload.licencia_key.strip().upper()
            )
        )
    ).scalar_one_or_none()
    if existe:
        raise HTTPException(status_code=400, detail="La licencia ya está registrada")
    lic = Licencia(
        id_cuenta=payload.id_cuenta,
        licencia_key=payload.licencia_key.strip().upper(),
        licencia_tier=payload.licencia_tier,
        licencia_status="ACTIVA",
        fecha_expira=_naive_utc(payload.fecha_expira) or datetime.now(UTC),
        max_usuarios=payload.max_usuarios,
        max_equipos=payload.max_equipos,
        max_sesiones=(
            payload.max_sesiones
            if payload.max_sesiones is not None
            else _max_sesiones_default(payload.licencia_tier)
        ),
    )
    db.add(lic)
    await _auditar(
        db,
        "licencia_activada",
        id_cuenta=payload.id_cuenta,
        id_credencial=cred.id_credencial,
        entidad="licencia",
        entidad_id=lic.licencia_key,
    )
    await db.commit()
    await db.refresh(lic)
    return ServerLicenciaOut.model_validate(lic).model_dump(mode="json")


# ---------------------------------------------------------------------------
# Panel del proveedor
# ---------------------------------------------------------------------------


@router.post("/api/v1/panel/login", response_model=PanelLoginResponse)
async def panel_login(
    payload: PanelLoginRequest,
    db: AsyncSession = Depends(get_server_db),
) -> PanelLoginResponse:
    """Login de administración interna del proveedor."""
    user = (
        await db.execute(
            select(ProveedorUsuario).where(
                ProveedorUsuario.email == payload.email.lower()
            )
        )
    ).scalar_one_or_none()
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Credenciales inválidas")
    if not user.activo:
        raise HTTPException(status_code=403, detail="Usuario inactivo")
    access = create_access_token(
        str(user.id_usuario), extra={"rol": user.rol, "tipo": "proveedor"}
    )
    return PanelLoginResponse(
        access_token=access,
        user={
            "id": str(user.id_usuario),
            "nombre": user.nombre,
            "email": user.email,
            "rol": user.rol,
        },
    )


@router.get("/api/v1/panel/cuentas")
async def panel_cuentas(
    prov: ProveedorUsuario = Depends(get_server_proveedor),
    db: AsyncSession = Depends(get_server_db),
) -> list[dict]:
    """Listado de cuentas (visibles para el panel del proveedor)."""
    result = await db.execute(
        select(Cuenta).order_by(Cuenta.created_at.desc()).limit(500)
    )
    return [
        ServerCuentaOut.model_validate(cuenta).model_dump(mode="json")
        for cuenta in result.scalars()
    ]


@router.get(
    "/api/v1/panel/cuentas/{id_cuenta}", response_model=PanelCuentaDetalleOut
)
async def panel_cuenta_detalle(
    id_cuenta: uuid.UUID,
    prov: ProveedorUsuario = Depends(get_server_proveedor),
    db: AsyncSession = Depends(get_server_db),
) -> PanelCuentaDetalleOut:
    """Detalle de una cuenta: licencias, credenciales y nº de dispositivos."""
    cuenta = await db.get(Cuenta, id_cuenta)
    if cuenta is None:
        raise HTTPException(status_code=404, detail="Cuenta no encontrada")
    licencias = (
        await db.execute(select(Licencia).where(Licencia.id_cuenta == id_cuenta))
    ).scalars().all()
    credenciales = (
        await db.execute(select(Credencial).where(Credencial.id_cuenta == id_cuenta))
    ).scalars().all()
    dispositivos = (
        await db.execute(select(Dispositivo).where(Dispositivo.id_cuenta == id_cuenta))
    ).scalars().all()
    return PanelCuentaDetalleOut(
        cuenta=ServerCuentaOut.model_validate(cuenta),
        licencias=[ServerLicenciaOut.model_validate(x) for x in licencias],
        credenciales=[
            PanelCredencialOut.model_validate(c) for c in credenciales
        ],
        total_dispositivos=len(dispositivos),
    )


@router.put(
    "/api/v1/panel/cuentas/{id_cuenta}", response_model=PanelCuentaDetalleOut
)
async def panel_cuenta_actualizar(
    id_cuenta: uuid.UUID,
    payload: PanelCuentaUpdateRequest,
    prov: ProveedorUsuario = Depends(get_server_proveedor),
    db: AsyncSession = Depends(get_server_db),
) -> PanelCuentaDetalleOut:
    """Actualiza la ficha de un cliente (datos y estatus de cuenta/licencia).

    PATCH parcial: solo cambia lo que llegue. ``activa`` conmuta la cuenta;
    ``licencia_status``/``licencia_key``/``fecha_expira`` etc. ajustan la
    licencia vigente de la cuenta (o la crean si aún no tiene).
    """
    cuenta = await db.get(Cuenta, id_cuenta)
    if cuenta is None:
        raise HTTPException(status_code=404, detail="Cuenta no encontrada")

    cambios: list[str] = []
    if payload.nombre_fiscal is not None:
        cuenta.nombre_fiscal = payload.nombre_fiscal
        cambios.append("nombre_fiscal")
    if payload.nombre_comercial is not None:
        cuenta.nombre_comercial = payload.nombre_comercial
        cambios.append("nombre_comercial")
    if payload.rif_nit is not None:
        rif = payload.rif_nit.strip().upper()
        dup = (
            await db.execute(
                select(Cuenta).where(Cuenta.rif_nit == rif, Cuenta.id_cuenta != id_cuenta)
            )
        ).scalar_one_or_none()
        if dup:
            raise HTTPException(status_code=400, detail="El RIF/NIT ya está registrado")
        cuenta.rif_nit = rif
        cambios.append("rif_nit")
    if payload.email_admin is not None:
        email = payload.email_admin.lower()
        dup_cuenta = (
            await db.execute(
                select(Cuenta).where(
                    Cuenta.email_admin == email, Cuenta.id_cuenta != id_cuenta
                )
            )
        ).scalar_one_or_none()
        dup_cred = (
            await db.execute(
                select(Credencial).where(
                    Credencial.email == email,
                    Credencial.id_cuenta != id_cuenta,
                )
            )
        ).scalar_one_or_none()
        if dup_cuenta or dup_cred:
            raise HTTPException(status_code=400, detail="El email ya está registrado")
        cuenta.email_admin = email
        cambios.append("email_admin")
    if payload.telefono is not None:
        cuenta.telefono = payload.telefono
        cambios.append("telefono")
    if payload.direccion is not None:
        cuenta.direccion = payload.direccion
        cambios.append("direccion")
    if payload.activa is not None:
        cuenta.activa = payload.activa
        cambios.append("activa")

    licencia = (
        await db.execute(
            select(Licencia)
            .where(Licencia.id_cuenta == id_cuenta)
            .order_by(Licencia.fecha_emision)
            .limit(1)
        )
    ).scalar_one_or_none()
    lic_campos = {
        "licencia_key": (payload.licencia_key or "").strip().upper() or None,
        "licencia_tier": payload.licencia_tier,
        "licencia_status": payload.licencia_status,
        "fecha_expira": _naive_utc(payload.fecha_expira),
        "max_usuarios": payload.max_usuarios,
        "max_equipos": payload.max_equipos,
        "max_sesiones": payload.max_sesiones,
    }
    lic_toca = {k for k, v in lic_campos.items() if v is not None}
    if lic_toca:
        if licencia is None and payload.licencia_key:
            licencia = Licencia(
                id_cuenta=id_cuenta,
                licencia_key=lic_campos["licencia_key"],
                licencia_tier=lic_campos["licencia_tier"] or "DEMO",
                licencia_status=lic_campos["licencia_status"] or "ACTIVA",
                fecha_expira=lic_campos["fecha_expira"]
                or datetime.now(UTC).replace(tzinfo=None) + timedelta(days=365),
                max_usuarios=lic_campos["max_usuarios"],
                max_equipos=lic_campos["max_equipos"],
            )
            db.add(licencia)
            cambios.append("licencia")
        elif licencia is not None:
            if "licencia_key" in lic_toca:
                dup_lic = (
                    await db.execute(
                        select(Licencia).where(
                            Licencia.licencia_key == lic_campos["licencia_key"],
                            Licencia.id_licencia != licencia.id_licencia,
                        )
                    )
                ).scalar_one_or_none()
                if dup_lic:
                    raise HTTPException(
                        status_code=400, detail="La licencia ya está registrada"
                    )
                licencia.licencia_key = (payload.licencia_key or "").strip().upper()
            for campo in sorted(lic_toca - {"licencia_key"}):
                setattr(licencia, campo, lic_campos[campo])
            cambios.append("licencia")
        elif licencia is None:
            raise HTTPException(
                status_code=400,
                detail="La cuenta no posee licencia: indique licencia_key para crearla",
            )

    if payload.password is not None:
        credenciales_pw = (
            await db.execute(
                select(Credencial).where(Credencial.id_cuenta == id_cuenta)
            )
        ).scalars().all()
        target = next(
            (c for c in credenciales_pw if c.email == cuenta.email_admin),
            None,
        ) or next(
            (c for c in credenciales_pw if c.rol_global == "ADMIN"),
            None,
        ) or (credenciales_pw[0] if credenciales_pw else None)
        if target is None:
            raise HTTPException(
                status_code=400,
                detail="La cuenta no tiene credenciales para actualizar la contraseña",
            )
        target.password_hash = hash_password(payload.password)
        cambios.append("password_admin")

    if cambios:
        await _auditar(
            db,
            "cuenta_actualizada",
            id_cuenta=id_cuenta,
            entidad="cuenta",
            entidad_id=str(id_cuenta),
            detalle={"campos": sorted(cambios)},
        )
        await db.commit()
        await db.refresh(cuenta)
        if licencia is not None:
            await db.refresh(licencia)

    licencias = (
        await db.execute(select(Licencia).where(Licencia.id_cuenta == id_cuenta))
    ).scalars().all()
    credenciales = (
        await db.execute(select(Credencial).where(Credencial.id_cuenta == id_cuenta))
    ).scalars().all()
    dispositivos = (
        await db.execute(select(Dispositivo).where(Dispositivo.id_cuenta == id_cuenta))
    ).scalars().all()
    return PanelCuentaDetalleOut(
        cuenta=ServerCuentaOut.model_validate(cuenta),
        licencias=[ServerLicenciaOut.model_validate(x) for x in licencias],
        credenciales=[PanelCredencialOut.model_validate(c) for c in credenciales],
        total_dispositivos=len(dispositivos),
    )


@router.post(
    "/api/v1/panel/verificar-licencia",
    response_model=PanelVerificarLicenciaResponse,
)
async def panel_verificar_licencia(
    payload: PanelVerificarLicenciaRequest,
    prov: ProveedorUsuario = Depends(get_server_proveedor),
) -> PanelVerificarLicenciaResponse:
    """Verifica que la licencia sea APTA para dar de alta en el LM del servidor.

    Consulta ``GET /api/v1/{key}/check`` del LM (estado real, no exige VS) y
    exige, según la política del LM, que la licencia:
      1. pertenezca al producto WS (``product_code`` = LICENSE_PRODUCT_CODE),
      2. tenga cliente asociado (``has_client``),
      3. tenga distribuidor asignado (``distributor_id``),
      4. esté en estado ``AVAILABLE`` (disponible, aún NO activada): si ya está
         ``ACTIVE``, está vinculada al hardware de otra persona y la cuenta
         nueva no podría activarla; inactiva/vencida/suspendida tampoco sirven.
    Una AVAILABLE apta da de alta la cuenta; la estación la activará en su
    primer uso. Se llama desde el panel ANTES de dar de alta. Existe/404 y
    caídas de red se reportan igual que antes.
    """
    try:
        info = await asyncio.to_thread(
            lambda: get_license_client().check(payload.licencia_key.strip().upper())
        )
    except LicenseError as e:
        msg = str(e)
        # El LM confirmó que la clave no existe: resultado determinista, no una caída.
        if "no encontrada" in msg.lower() or "404" in msg:
            return PanelVerificarLicenciaResponse(
                valida=False,
                message="La licencia no existe en el LM del servidor",
            )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"LM no disponible: {msg}",
        ) from e

    if not info.get("exists"):
        return PanelVerificarLicenciaResponse(
            valida=False,
            message="La licencia no existe en el LM del servidor",
        )

    def _devolver_no_valida(mensaje: str) -> PanelVerificarLicenciaResponse:
        return PanelVerificarLicenciaResponse(
            valida=False,
            status=(info.get("status") or "").upper() or None,
            tier=info.get("tier"),
            plan_type=info.get("plan_type"),
            features={
                "product_code": info.get("product_code"),
                "client_name": info.get("client_name"),
                "distributor_name": info.get("distributor_name"),
            },
            message=mensaje,
        )

    producto = (info.get("product_code") or "").upper()
    if producto != settings.license_product_code.upper():
        return _devolver_no_valida(
            f"La licencia es del producto «{producto or 'desconocido'}», "
            f"no de «{settings.license_product_code}»"
        )
    if not info.get("has_client"):
        return _devolver_no_valida(
            "La licencia no tiene cliente asociado en el LM"
        )
    if not info.get("distributor_id") and not info.get("distributor_name"):
        return _devolver_no_valida(
            "La licencia no tiene distribuidor asignado en el LM"
        )

    estado = (info.get("status") or "AVAILABLE").upper()
    requiere_activacion = bool(info.get("requires_activation"))
    if estado != "AVAILABLE":
        if estado == "ACTIVE":
            return _devolver_no_valida(
                "La licencia ya está activada en otro equipo; "
                "no puede asociarse a una cuenta nueva."
            )
        if estado == "INACTIVE":
            return _devolver_no_valida(
                "La licencia está inactiva en el LM; "
                "no puede asociarse a una cuenta nueva."
            )
        return _devolver_no_valida(f"La licencia no es válida (estado {estado}).")
    message = (
        "Válida en el LM (estado AVAILABLE). "
        "Se activará en el primer uso de la estación."
    )
    return PanelVerificarLicenciaResponse(
        valida=True,
        status=estado,
        tier=info.get("tier"),
        plan_type=info.get("plan_type"),
        expires_at=info.get("expires_at"),
        features={
            "requires_activation": requiere_activacion,
            "product_code": info.get("product_code"),
            "client_name": info.get("client_name"),
            "distributor_name": info.get("distributor_name"),
        },
        message=message,
    )


# ---------------------------------------------------------------------------
# Sincronización (acepción de lotes de estaciones locales)
# ---------------------------------------------------------------------------


@router.post("/api/v1/sync/server", response_model=ServerSyncPushResponse)
async def server_sync_push(
    payload: ServerSyncPushRequest,
    cred: Credencial = Depends(get_server_credencial),
    db: AsyncSession = Depends(get_server_db),
) -> ServerSyncPushResponse:
    """Recibe y encola un lote sincrónico de una estación local."""
    await _verificar_limite_sync(db, cred)
    disp = (
        await db.execute(
            select(Dispositivo)
            .where(Dispositivo.id_cuenta == cred.id_cuenta, Dispositivo.activo.is_(True))
            .order_by(Dispositivo.ultima_conexion.desc())
        )
    ).scalar_one_or_none()
    sesion_sync = SyncSesion(
        id_cuenta=cred.id_cuenta,
        id_dispositivo=disp.id_dispositivo if disp else None,
        tipo=payload.tipo,
        estado="PENDIENTE",
        registros_subidos=len(payload.items),
        iniciado=datetime.now(UTC).replace(tzinfo=None),
    )
    db.add(sesion_sync)
    await db.flush()

    ids: list[str] = []
    for item in payload.items:
        cola = SyncColaItem(
            id_cuenta=cred.id_cuenta,
            id_dispositivo=sesion_sync.id_dispositivo,
            entidad=item.entidad,
            operacion=item.operacion,
            entidad_id=item.entidad_id,
            payload=item.payload,
            pendiente=True,
            intentos=0,
        )
        db.add(cola)
        ids.append(item.entidad_id)

    sesion_sync.estado = "OK"
    sesion_sync.finalizado = datetime.now(UTC).replace(tzinfo=None)
    await _auditar(
        db,
        "sync",
        id_cuenta=cred.id_cuenta,
        id_credencial=cred.id_credencial,
        entidad="sync",
        detalle={"tipo": payload.tipo, "items": len(payload.items)},
    )
    await db.commit()
    return ServerSyncPushResponse(recibidos=len(payload.items), ok=True, ids=ids)


@router.post("/api/v1/sync/users", response_model=ServerSyncUsersResponse)
async def server_sync_users(
    payload: ServerSyncUsersRequest,
    cred: Credencial = Depends(get_server_credencial),
    db: AsyncSession = Depends(get_server_db),
) -> ServerSyncUsersResponse:
    """Sincroniza usuarios operativos de una estación → credenciales globales.

    Cada envío de la estación (credencial autenticada) hace upsert/desactivación
    en `credenciales` acotado a SU cuenta. El resto de credenciales globales no
    se toca.
    """
    await _verificar_limite_sync(db, cred)
    procesados = 0
    errores = 0
    detalle: list[str] = []
    for item in payload.items:
        email = str(item.email).lower()
        cred_existente = (
            await db.execute(select(Credencial).where(Credencial.email == email))
        ).scalar_one_or_none()
        if cred_existente is not None and cred_existente.id_cuenta != cred.id_cuenta:
            errores += 1
            detalle.append(f"{email}: ya existe en otra cuenta")
            continue
        if item.operacion == "delete" and cred_existente is not None:
            cred_existente.activo = False
            cred_existente.updated_at = datetime.now(UTC).replace(tzinfo=None)
            procesados += 1
            continue
        if cred_existente is None:
            cred_existente = Credencial(
                id_cuenta=cred.id_cuenta,
                email=email,
                password_hash=hash_password(uuid.uuid4().hex + email),
                rol_global=item.rol_global,
                activo=item.activo,
            )
            db.add(cred_existente)
        else:
            cred_existente.rol_global = item.rol_global
            cred_existente.activo = item.activo
            cred_existente.updated_at = datetime.now(UTC).replace(tzinfo=None)
        procesados += 1
        detalle.append(f"{email}: upsert")

    await _auditar(
        db,
        "sync_usuarios",
        id_cuenta=cred.id_cuenta,
        id_credencial=cred.id_credencial,
        entidad="credenciales",
        detalle={"procesados": procesados, "errores": errores},
    )
    await db.commit()
    return ServerSyncUsersResponse(procesados=procesados, errores=errores, detalle=detalle)