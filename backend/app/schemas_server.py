"""Esquemas Pydantic de la API del SERVIDOR (cuenta y licencia).

Estos DTOs corresponden a la DB del servidor (docs/MANEJO_DB.md) y se usan
únicamente en despliegues con ``APP_ROLE=server`` (registro central, login
global, licencias, panel del proveedor y recepción de sync).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, EmailStr, Field


class ServerRegisterRequest(BaseModel):
    """Alta central: crea cuenta, licencia y credencial ADMIN."""

    empresa_nombre: str = Field(..., min_length=3, max_length=255)
    empresa_rif: str = Field(..., min_length=5, max_length=20)
    email_admin: EmailStr
    telefono: str | None = None
    direccion: str | None = None
    usuario_nombre: str = Field(..., min_length=3, max_length=150)
    password: str = Field(..., min_length=6, max_length=128)
    licencia_key: str = Field(..., min_length=10, max_length=255)
    licencia_tier: str = Field(default="DEMO", pattern="^(DEMO|CENTRAL)$")
    fecha_expira: datetime
    max_usuarios: int | None = None
    max_equipos: int | None = None
    max_sesiones: int | None = None


class ServerLoginRequest(BaseModel):
    email: EmailStr
    password: str
    hardware_id: str = Field(..., min_length=1, max_length=255)
    nombre_equipo: str | None = Field(None, max_length=150)
    sistema_operativo: str | None = Field(None, max_length=100)
    version_app: str | None = Field(None, max_length=50)
    mac_address: str | None = None
    device_brand: str | None = None
    device_model: str | None = None


class ServerCredencialOut(BaseModel):
    model_config = {"from_attributes": True}
    id_credencial: uuid.UUID
    id_cuenta: uuid.UUID
    email: str
    rol_global: str


class ServerCuentaOut(BaseModel):
    model_config = {"from_attributes": True}
    id_cuenta: uuid.UUID
    rif_nit: str
    nombre_fiscal: str
    nombre_comercial: str | None = None
    email_admin: str | None = None
    telefono: str | None = None
    direccion: str | None = None
    activa: bool


class ServerLicenciaOut(BaseModel):
    model_config = {"from_attributes": True}
    id_licencia: uuid.UUID
    id_cuenta: uuid.UUID
    licencia_key: str
    licencia_tier: str
    licencia_status: str
    fecha_emision: datetime
    fecha_expira: datetime
    max_usuarios: int | None = None
    max_equipos: int | None = None
    max_sesiones: int | None = None


class ServerLoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: ServerCredencialOut
    cuenta: ServerCuentaOut
    licencia: ServerLicenciaOut
    dispositivo: dict[str, Any] | None = None


class ServerTokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class PanelLoginRequest(BaseModel):
    email: EmailStr
    password: str


class PanelLoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: dict[str, Any] | None = None


class PanelVerificarLicenciaRequest(BaseModel):
    """Verificación de una licencia existente en el LM (anti-fake-server)."""

    licencia_key: str = Field(..., min_length=10, max_length=255)
    hardware_id: str | None = Field(None, max_length=255)


class PanelVerificarLicenciaResponse(BaseModel):
    valida: bool
    status: str | None = None
    tier: str | None = None
    plan_type: str | None = None
    expires_at: datetime | None = None
    features: dict[str, Any] = Field(default_factory=dict)
    message: str | None = None


class PanelCredencialOut(BaseModel):
    model_config = {"from_attributes": True}
    id_credencial: uuid.UUID
    email: str
    rol_global: str
    activo: bool
    ultimo_login: datetime | None = None


class PanelCuentaDetalleOut(BaseModel):
    cuenta: ServerCuentaOut
    licencias: list[ServerLicenciaOut] = Field(default_factory=list)
    credenciales: list[PanelCredencialOut] = Field(default_factory=list)
    total_dispositivos: int = 0


class PanelCuentaUpdateRequest(BaseModel):
    """Actualización parcial de la ficha de un cliente, incluye su estatus.

    Campos de la cuenta y/o de su licencia. Solo se tocan los que llegan
    (``None`` = no cambiar). El ``activa`` controla el estado de la cuenta y
    ``licencia_status`` el de la licencia (ACTIVA/INACTIVA/SUSPENDIDA/...).
    """

    nombre_fiscal: str | None = Field(None, min_length=3, max_length=255)
    nombre_comercial: str | None = Field(None, min_length=3, max_length=255)
    rif_nit: str | None = Field(None, min_length=5, max_length=20)
    email_admin: EmailStr | None = None
    telefono: str | None = Field(None, max_length=50)
    direccion: str | None = Field(None, max_length=1000)
    activa: bool | None = None

    licencia_key: str | None = Field(None, min_length=10, max_length=255)
    licencia_tier: str | None = Field(
        None, pattern="^(DEMO|CENTRAL)$"
    )
    licencia_status: str | None = Field(
        None, pattern="^(ACTIVA|INACTIVA|SUSPENDIDA|VENCIDA|ANULADA)$"
    )
    fecha_expira: datetime | None = None
    max_usuarios: int | None = None
    max_equipos: int | None = None
    max_sesiones: int | None = None
    password: str | None = Field(None, min_length=6, max_length=128)


class ServerLicenciaNuevaRequest(BaseModel):
    """Registro de licencia adicional para una cuenta existente."""

    id_cuenta: uuid.UUID
    licencia_key: str = Field(..., min_length=10, max_length=255)
    licencia_tier: str = Field(default="DEMO", pattern="^(DEMO|CENTRAL)$")
    fecha_expira: datetime
    max_usuarios: int | None = None
    max_equipos: int | None = None
    max_sesiones: int | None = None


class ServerSyncItem(BaseModel):
    entidad: str = Field(..., max_length=50)
    operacion: str = Field(..., pattern="^(create|update|delete)$")
    entidad_id: str = Field(..., max_length=100)
    payload: dict[str, Any] = Field(default_factory=dict)


class ServerSyncPushRequest(BaseModel):
    """Lote recibido por una estación local."""

    tipo: str = Field(default="push", pattern="^(push|full)$")
    items: list[ServerSyncItem] = Field(default_factory=list)


class ServerSyncPushResponse(BaseModel):
    recibidos: int = 0
    ok: bool = True
    ids: list[str] = Field(default_factory=list)


class ServerUsuarioSyncItem(BaseModel):
    """Usuario operativo entregado por una estación (→ credencial global)."""

    email: EmailStr
    nombre: str | None = Field(None, max_length=150)
    rol_global: str = Field("OPERADOR", pattern="^(ADMIN|OPERADOR|AUDITOR|TRABAJADOR)$")
    activo: bool = True
    operacion: str = Field("upsert", pattern="^(upsert|delete)$")


class ServerSyncUsersRequest(BaseModel):
    items: list[ServerUsuarioSyncItem] = Field(default_factory=list)


class ServerSyncUsersResponse(BaseModel):
    procesados: int = 0
    errores: int = 0
    detalle: list[str] = Field(default_factory=list)