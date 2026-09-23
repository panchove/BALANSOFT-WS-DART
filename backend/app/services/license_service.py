"""Servicio que orquesta la validación de licencias contra el LM local."""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.hardware import obtener_hardware_id
from app.core.license_client import LicenseClient, LicenseError, LicenseInfo, get_license_client
from app.core.monitoring import inc_license_error
from app.models import Empresa, IdentidadLocal

log = logging.getLogger(__name__)


async def sincronizar_licencia_e_identidad(
    db: AsyncSession,
    empresa: Empresa,
    hardware_id: str | None = None,
    *,
    force_remote: bool = False,
    mac_address: str | None = None,
    device_brand: str | None = None,
    device_model: str | None = None,
    os_version: str | None = None,
) -> IdentidadLocal:
    """Sincroniza la licencia en tiempo real contra el LM y actualiza persistentemente
    tanto Empresa como IdentidadLocal (Mecanismo de detección de licencias SG).
    """
    identidad = (
        await db.execute(
            select(IdentidadLocal).where(IdentidadLocal.id.is_(True))
        )
    ).scalar_one_or_none()

    if identidad is None:
        identidad = IdentidadLocal(id=True)
        db.add(identidad)

    hw_id = hardware_id or identidad.hardware_id or obtener_hardware_id()
    key = empresa.licencia_key

    if key and "..." not in key and "•" not in key:
        client = get_license_client()
        try:
            import asyncio
            info: LicenseInfo = await asyncio.to_thread(
                client.validate_or_activate,
                key,
                hw_id,
                mac_address=mac_address,
                device_brand=device_brand,
                device_model=device_model,
                os_version=os_version,
                product_code=settings.license_product_code,
            )
            # Actualizar Empresa
            empresa.licencia_tier = info.tier
            empresa.licencia_status = info.status
            empresa.licencia_expira = (
                info.expires_at.replace(tzinfo=None) if info.expires_at else None
            )

            # Actualizar IdentidadLocal
            identidad.licencia_tier = info.tier
            identidad.licencia_status = info.status
            identidad.licencia_expira = (
                info.expires_at.replace(tzinfo=None) if info.expires_at else None
            )
            identidad.licencia_key = key
            identidad.hardware_id = hw_id
            identidad.ultima_validacion = datetime.now(UTC).replace(tzinfo=None)
            identidad.modo_offline = False

        except LicenseError as e:
            log.warning("No se pudo validar licencia en LM: %s", e)
            identidad.modo_offline = True
            inc_license_error((empresa.licencia_tier or "UNKNOWN").upper(), "sync")
        except Exception as e:
            log.error("Error inesperado en sincronizar_licencia_e_identidad: %s", e)

    # Asegurar sync espejo de campos empresa -> identidad
    identidad.id_cuenta = empresa.id_empresa
    identidad.rif_nit = empresa.rif_nit
    identidad.nombre_fiscal = empresa.nombre_fiscal
    identidad.nombre_comercial = empresa.nombre_comercial or empresa.nombre_fiscal
    identidad.licencia_key = empresa.licencia_key
    if empresa.licencia_tier:
        identidad.licencia_tier = empresa.licencia_tier
    if empresa.licencia_status:
        identidad.licencia_status = empresa.licencia_status
    if empresa.licencia_expira:
        identidad.licencia_expira = empresa.licencia_expira
    identidad.hardware_id = hw_id
    identidad.updated_at = datetime.now(UTC).replace(tzinfo=None)

    await db.flush()
    await db.refresh(identidad)
    await db.refresh(empresa)
    return identidad


class LicenseService:
    def __init__(self, client: LicenseClient | None = None) -> None:
        self.client = client or get_license_client()

    def validar(
        self,
        empresa: Empresa,
        hardware_id: str | None = None,
        *,
        mac_address: str | None = None,
        device_brand: str | None = None,
        device_model: str | None = None,
        os_version: str | None = None,
    ) -> dict[str, Any]:
        """Valida la licencia de la empresa contra el LM y devuelve un dict JSON."""
        licencia_key = empresa.licencia_key
        if not licencia_key:
            return {
                "valid": False,
                "status": None,
                "message": "La empresa no tiene una licencia asignada",
                "features": {},
            }
        try:
            info = self.client.validate(
                licencia_key,
                hardware_id or "desconocido",
                mac_address=mac_address,
                device_brand=device_brand,
                device_model=device_model,
                os_version=os_version,
                product_code=settings.license_product_code,
            )
        except LicenseError as e:
            log.warning("Validación de licencia fallida para %s: %s", licencia_key, e)
            return {
                "valid": False,
                "status": None,
                "message": str(e),
                "features": {},
            }
        return {
            "valid": info.valid,
            "status": info.status,
            "tier": info.tier,
            "plan_type": info.plan_type,
            "expires_at": info.expires_at.isoformat() if info.expires_at else None,
            "features": info.features,
            "message": info.message,
        }

