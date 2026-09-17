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
    identidad: IdentidadLocal | None = (
        await db.execute(
            select(IdentidadLocal).where(IdentidadLocal.id.is_(True))
        )
    ).scalar_one_or_none()

    consumo = await db.scalar(
        select(func.count())
        .select_from(BoletoPesaje)
        .where(BoletoPesaje.id_empresa == empresa.id_empresa)
    )

    tier_local = (empresa.licencia_tier or "").upper()
    max_registros = settings.demo_max_records if tier_local == "DEMO" else None

    licencia_valida = False
    licencia_features: dict | None = None
    licencia_mensaje: str | None = None
    licencia_en_linea = False

    if empresa.licencia_key:
        try:
            info: LicenseInfo = await asyncio.to_thread(
                get_license_client().validate,
                empresa.licencia_key,
                (identidad.hardware_id if identidad else None)
                or obtener_hardware_id(),
                product_code=settings.license_product_code,
            )
            licencia_valida = info.valid
            licencia_features = {
                "tier": info.tier,
                "plan_type": info.plan_type,
                "expires_at": info.expires_at.isoformat() if info.expires_at else None,
            }
            licencia_en_linea = True

            empresa.licencia_tier = info.tier
            empresa.licencia_status = info.status
            empresa.licencia_expira = info.expires_at.replace(tzinfo=None) if info.expires_at else None
            await db.flush()
        except LicenseError as exc:
            inc_license_error(tier_local or "UNKNOWN", "config_account")
            licencia_mensaje = str(exc)
        except Exception as exc:
            licencia_mensaje = f"Error inesperado: {exc}"

    return _AccountLicenseInfo(
        id_cuenta=identidad.id_cuenta if identidad else None,
        rif_nit=identidad.rif_nit if identidad else empresa.rif_nit,
        nombre_fiscal=identidad.nombre_fiscal if identidad else empresa.nombre_fiscal,
        nombre_comercial=identidad.nombre_comercial if identidad else empresa.nombre_comercial,
        licencia_key_masked=_mask_key(empresa.licencia_key),
        hardware_id=identidad.hardware_id if identidad else None,
        rol_dispositivo=identidad.rol_dispositivo if identidad else "LOCAL",
        modo_offline=identidad.modo_offline if identidad else False,
        licencia_tier=empresa.licencia_tier,
        licencia_status=empresa.licencia_status,
        licencia_expira=empresa.licencia_expira.isoformat() if empresa.licencia_expira else None,
        licencia_valida=licencia_valida,
        licencia_features=licencia_features,
        licencia_mensaje=licencia_mensaje,
        licencia_en_linea=licencia_en_linea,
        registros_actuales=consumo or 0,
        registros_maximos=max_registros,
        server_api_url=settings.server_api_url or None,
        ultima_validacion=identidad.ultima_validacion.isoformat() if identidad and identidad.ultima_validacion else None,
    )
