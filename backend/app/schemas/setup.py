"""Schemas para el setup inicial de estación (100% local, validación directa al LM)."""

from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, EmailStr


# ---------------------------------------------------------------------------
# POST /api/v1/setup/validar-licencia
# ---------------------------------------------------------------------------


class SetupValidateRequest(BaseModel):
    """Petición para validar una licencia contra el LM antes del setup."""

    license_key: str = Field(
        ...,
        min_length=1,
        max_length=255,
        description="Clave de licencia (formato BWS-XXXX-XXXX-XXXX-XXXX)",
        examples=["BWS-A1B2-C3D4-E5F6-G7H8"],
    )
    hardware_id: str | None = Field(
        None,
        max_length=128,
        description="Huella de hardware de la estación (opcional en este paso)",
    )
    mac_address: str | None = Field(None, max_length=17)
    device_brand: str | None = Field(None, max_length=64)
    device_model: str | None = Field(None, max_length=64)
    os_version: str | None = Field(None, max_length=64)


class SetupValidateResponse(BaseModel):
    """Respuesta con los datos del cliente obtenidos del LM para pre-llenar el formulario."""

    model_config = ConfigDict(from_attributes=True)

    valid: bool = Field(..., description="Si la licencia es válida en el LM")
    status: str | None = Field(None, description="Estado de la licencia en el LM")
    tier: str | None = Field(None, description="Tier/plan de la licencia")
    expires_at: datetime | None = Field(None, description="Fecha de expiración de la licencia")
    client_email: str | None = Field(None, description="Email del cliente en el LM (bloqueado en el formulario)")
    client_name: str | None = Field(None, description="Nombre del cliente en el LM")
    client_id: str | None = Field(None, description="ID del cliente en el LM")
    message: str | None = Field(None, description="Mensaje informativo del LM")
    licencia_key_masked: str | None = Field(
        None, description="Clave de licencia mascarada (no exponer la completa)"
    )


# ---------------------------------------------------------------------------
# POST /api/v1/setup/crear-admin
# ---------------------------------------------------------------------------


class SetupCreateAdminRequest(BaseModel):
    """Petición para crear la empresa y el primer usuario ADMIN en la estación."""

    license_key: str = Field(
        ...,
        min_length=1,
        max_length=255,
        description="Clave de licencia validada previamente",
    )
    password: str = Field(
        ...,
        min_length=8,
        max_length=128,
        description="Contraseña del primer usuario ADMIN (se hashea localmente)",
    )
    nombre_comercial: str = Field(
        ...,
        min_length=3,
        max_length=255,
        description="Nombre comercial de la empresa",
    )
    rif_nit: str = Field(
        ...,
        min_length=5,
        max_length=20,
        description="RIF/NIT de la empresa (tecleado por el usuario; el LM no lo expone por API)",
    )
    direccion: str | None = Field(None, max_length=500)
    telefono: str | None = Field(None, max_length=50)
    logo_url: str | None = Field(None, max_length=500)


class SetupUserOut(BaseModel):
    """Usuario creado en el setup."""

    model_config = ConfigDict(from_attributes=True)

    id_usuario: UUID
    nombre: str
    email: str
    rol: str = "ADMIN"
    id_empresa: UUID


class SetupEmpresaOut(BaseModel):
    """Empresa creada en el setup."""

    model_config = ConfigDict(from_attributes=True)

    id_empresa: UUID
    nombre_fiscal: str
    nombre_comercial: str | None = None
    rif_nit: str
    direccion: str | None = None
    telefono: str | None = None
    email: str | None = None
    logo_url: str | None = None
    licencia_tier: str | None = None
    licencia_status: str | None = None
    licencia_expira: datetime | None = None
    lm_client_id: UUID | None = None
    lm_client_email: str | None = None
    activa: bool = True
    created_at: datetime


class SetupLicenseOut(BaseModel):
    """Snapshot de licencia tras el setup."""

    valid: bool
    status: str | None = None
    tier: str | None = None
    expires_at: datetime | None = None
    message: str | None = None


class SetupCreateAdminResponse(BaseModel):
    """Respuesta completa del endpoint crear-admin."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: SetupUserOut
    empresa: SetupEmpresaOut
    license: SetupLicenseOut
