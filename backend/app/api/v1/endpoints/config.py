"""Configuración unificada de la estación: cuenta + licencia + sync.

Endpoint ``GET /api/v1/config/account`` combina la identidad local (espejo
del servidor), la empresa local y una validación en vivo contra el LM para
que la pantalla de Configuración del Flutter refleje la información real.
"""

from __future__ import annotations

import asyncio
import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user
from app.core.config import settings
from app.core.database import get_db
from app.core.hardware import obtener_hardware_id
from app.core.license_client import LicenseError, LicenseInfo, get_license_client
from app.core.monitoring import inc_license_error
from app.models import BoletoPesaje, Empresa, IdentidadLocal, Usuario

router = APIRouter(prefix="/api/v1/config", tags=["Config"])


class _AccountLicenseInfo(BaseModel):
    """Cuenta (mirror servidor) + licencia (validada en vivo contra LM)."""

    id_cuenta: uuid.UUID | None = None
    rif_nit: str | None = None
    nombre_fiscal: str | None = None
    nombre_comercial: str | None = None
    licencia_key_masked: str | None = None
    hardware_id: str | None = None
    rol_dispositivo: str = "LOCAL"
    modo_offline: bool = False

    licencia_tier: str | None = None
    licencia_status: str | None = None
    licencia_expira: str | None = None
    licencia_valida: bool = False
    licencia_features: dict | None = None
    licencia_mensaje: str | None = None
    licencia_en_linea: bool = False

    registros_actuales: int = 0
    registros_maximos: int | None = None

    server_api_url: str | None = None
    ultima_validacion: str | None = None


def _mask_key(key: str | None) -> str | None:
    if not key:
        return None
    if len(key) <= 8:
        return "••••"
    return f"{key[:4]}...{key[-4:]}"


@router.get("/account", response_model=_AccountLicenseInfo)
async def get_account_info(
    _user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> _AccountLicenseInfo:
    """Información unificada de la estación: cuenta espejo del servidor + licencia en vivo.

    Combina identidad_local (espejo del servidor), empresa (licencia cacheada)
    y una validación en tiempo real contra el LM. Si el LM falla, devuelve la
    caché local sin bloquear.
    """
    from app.services.license_service import sincronizar_licencia_e_identidad
    identidad = await sincronizar_licencia_e_identidad(db, empresa, force_remote=True)

    consumo = await db.scalar(
        select(func.count())
        .select_from(BoletoPesaje)
        .where(BoletoPesaje.id_empresa == empresa.id_empresa)
    )

    tier_local = (identidad.licencia_tier or empresa.licencia_tier or "").upper()
    max_registros = settings.demo_max_records if tier_local == "DEMO" else None

    licencia_valida = (identidad.licencia_status or "").upper() in ("ACTIVE", "ACTIVA", "VIGENTE")
    licencia_en_linea = not identidad.modo_offline

    return _AccountLicenseInfo(
        id_cuenta=identidad.id_cuenta,
        rif_nit=identidad.rif_nit,
        nombre_fiscal=identidad.nombre_fiscal,
        nombre_comercial=identidad.nombre_comercial,
        licencia_key_masked=_mask_key(empresa.licencia_key),
        hardware_id=identidad.hardware_id,
        rol_dispositivo=identidad.rol_dispositivo,
        modo_offline=identidad.modo_offline,
        licencia_tier=identidad.licencia_tier,
        licencia_status=identidad.licencia_status,
        licencia_expira=identidad.licencia_expira.isoformat() if identidad.licencia_expira else None,
        licencia_valida=licencia_valida,
        licencia_features={
            "tier": identidad.licencia_tier,
            "status": identidad.licencia_status,
            "expires_at": identidad.licencia_expira.isoformat() if identidad.licencia_expira else None,
        },
        licencia_mensaje=None,
        licencia_en_linea=licencia_en_linea,
        registros_actuales=consumo or 0,
        registros_maximos=max_registros,
        server_api_url=settings.server_api_url or None,
        ultima_validacion=identidad.ultima_validacion.isoformat() if identidad.ultima_validacion else None,
    )
