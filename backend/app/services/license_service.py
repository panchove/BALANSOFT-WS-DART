"""Servicio que orquesta la validación de licencias contra el LM local."""

from __future__ import annotations

import logging
from typing import Any

from app.core.config import settings
from app.core.license_client import LicenseClient, LicenseError, get_license_client
from app.models import Empresa

log = logging.getLogger(__name__)


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
