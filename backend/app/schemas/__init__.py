"""Esquemas Pydantic para la API."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

# ---------------------------------------------------------------------------
# Autenticación
# ---------------------------------------------------------------------------


class RegisterRequest(BaseModel):
    empresa_nombre: str = Field(..., min_length=3, max_length=255)
    empresa_rif: str = Field(..., min_length=5, max_length=20)
    usuario_nombre: str = Field(..., min_length=3, max_length=150)
    email: EmailStr
    password: str = Field(..., min_length=6, max_length=128)
    licencia_key: str = Field(..., min_length=1, max_length=255)
    hardware_id: str | None = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str
    hardware_id: str | None = None
    device_brand: str | None = None
    device_model: str | None = None
    os_version: str | None = None
    mac_address: str | None = None


class ValidateLicenseRequest(BaseModel):
    licencia_key: str | None = None
    hardware_id: str | None = None


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    token: str = Field(..., min_length=10, max_length=128)
    new_password: str = Field(..., min_length=6, max_length=128)


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_usuario: uuid.UUID
    nombre: str
    email: str
    rol: str


class CompanyOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_empresa: uuid.UUID
    nombre_fiscal: str
    nombre_comercial: str | None
    rif_nit: str
    licencia_tier: str | None
    licencia_status: str | None
    licencia_expira: datetime | None


class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserOut
    empresa: CompanyOut
    license: dict[str, Any] | None = None


class LicenseInfoOut(BaseModel):
    valid: bool
    status: str | None
    tier: str | None
    plan_type: str | None
    expires_at: datetime | None
    features: dict[str, Any] = Field(default_factory=dict)
    message: str | None = None


# ---------------------------------------------------------------------------
# Catálogos
# ---------------------------------------------------------------------------


class CatalogItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class CamionOut(CatalogItemOut):
    id: uuid.UUID
    placa: str
    modelo_id: uuid.UUID | None = None
    transporte_id: uuid.UUID | None = None
    color: str | None = None
    foto_real_url: str | None = None
    tara_habitual: Decimal | None = None
    activo: bool = True


class CamionCreate(BaseModel):
    placa: str = Field(..., min_length=2, max_length=20)
    modelo_id: uuid.UUID | None = None
    transporte_id: uuid.UUID | None = None
    color: str | None = None
    foto_real_url: str | None = None
    tara_habitual: Decimal | None = None


class MarcaOut(CatalogItemOut):
    id_marca: uuid.UUID
    nombre: str
    logo_url: str | None = None


class MarcaCreate(BaseModel):
    nombre: str = Field(..., min_length=2, max_length=100)
    logo_url: str | None = None


class ModeloCamionOut(CatalogItemOut):
    id_modelo_camion: uuid.UUID
    marca_id: uuid.UUID | None = None
    nombre: str
    capacidad_carga_ton: Decimal | None = None
    foto_referencial_url: str | None = None
    ejes: int | None = None


class ModeloCamionCreate(BaseModel):
    marca_id: uuid.UUID | None = None
    nombre: str = Field(..., min_length=2, max_length=100)
    capacidad_carga_ton: Decimal | None = None
    foto_referencial_url: str | None = None
    ejes: int | None = None


class RemolqueOut(CatalogItemOut):
    id_remolque: uuid.UUID
    placa: str
    tipo_remolque: str | None = None
    tara_habitual: Decimal | None = None
    foto_url: str | None = None
    activo: bool = True


class RemolqueCreate(BaseModel):
    placa: str = Field(..., min_length=2, max_length=20)
    tipo_remolque: str | None = None
    tara_habitual: Decimal | None = None
    foto_url: str | None = None


class TransporteOut(CatalogItemOut):
    id_transporte: uuid.UUID
    codigo: str | None = None
    razon_social: str
    identificacion_fiscal: str | None = None
    telefono: str | None = None
    contacto: str | None = None


class TransporteCreate(BaseModel):
    codigo: str | None = None
    razon_social: str = Field(..., min_length=2)
    identificacion_fiscal: str | None = None
    telefono: str | None = None
    contacto: str | None = None


class ConductorOut(CatalogItemOut):
    cedula_dni: str
    nombre_completo: str
    telefono: str | None = None
    licencia_conducir: str | None = None
    foto_url: str | None = None


class ConductorCreate(BaseModel):
    cedula_dni: str = Field(..., min_length=4, max_length=20)
    nombre_completo: str = Field(..., min_length=3)
    telefono: str | None = None
    licencia_conducir: str | None = None
    foto_url: str | None = None


class ProductoOut(CatalogItemOut):
    id_producto: uuid.UUID
    codigo: str | None = None
    nombre: str
    descripcion: str | None = None
    densidad_estandar: Decimal | None = None
    unidad_medida: str = "TON"
    es_kardex: bool = False
    tolerancia: Decimal | None = None
    peso_unidad: Decimal | None = None
    activo: bool = True


class ProductoCreate(BaseModel):
    codigo: str | None = None
    nombre: str = Field(..., min_length=2)
    descripcion: str | None = None
    densidad_estandar: Decimal | None = None
    unidad_medida: str = Field(default="TON", max_length=20)
    es_kardex: bool = False
    tolerancia: Decimal | None = None
    peso_unidad: Decimal | None = None


class AlmacenOut(CatalogItemOut):
    id_almacen: uuid.UUID
    codigo: str | None = None
    nombre: str
    ubicacion: str | None = None
    capacidad_max_ton: Decimal | None = None
    stock_actual_ton: Decimal = Decimal("0.00")


class AlmacenCreate(BaseModel):
    codigo: str | None = None
    nombre: str = Field(..., min_length=2)
    ubicacion: str | None = None
    capacidad_max_ton: Decimal | None = None
    stock_actual_ton: Decimal | None = None


class BalanzaOut(CatalogItemOut):
    id_balanza: uuid.UUID
    codigo: str | None = None
    descripcion: str
    marca: str | None = None
    modelo: str | None = None
    capacidad_max: Decimal | None = None
    division: Decimal | None = None
    activo: bool = True
    is_simulada: bool = False
    puerto_com: str | None = None
    ip_address: str | None = None
    puerto_tcp: int | None = None
    protocolo: str | None = None


class BalanzaCreate(BaseModel):
    codigo: str | None = None
    descripcion: str = Field(..., min_length=2)
    marca: str | None = None
    modelo: str | None = None
    capacidad_max: Decimal | None = None
    division: Decimal | None = None
    activo: bool = True
    is_simulada: bool = False
    puerto_com: str | None = None
    ip_address: str | None = None
    puerto_tcp: int | None = Field(None, gt=0, le=65535)
    protocolo: str | None = Field(None, pattern="^(tcp|serial)$")


class BalanzaDescubiertaOut(BaseModel):
    """Báscula detectada por el escaneo automático de dispositivos."""

    descripcion: str
    protocolo: str
    ip_address: str | None = None
    puerto_tcp: int | None = None
    puerto_com: str | None = None
    peso_kg: float | None = None
    is_simulada: bool = False


class BalanzaPruebaOut(BaseModel):
    """Resultado de la prueba de conexión del HAL de una balanza."""

    balanza: str
    conectado: bool
    hardware: str | None = None
    protocolo: str | None = None
    peso_kg: float | None = None
    estable: bool = False
    detalle: str | None = None


class TerceroOut(CatalogItemOut):
    id_tercero: uuid.UUID
    codigo: str | None = None
    tipo: str
    razon_social: str
    identificacion_fiscal: str | None = None
    direccion: str | None = None
    telefono: str | None = None
    email: EmailStr | None = None


class TerceroCreate(BaseModel):
    codigo: str | None = None
    tipo: str = Field(..., pattern="^(CLIENTE|PROVEEDOR|AMBOS)$")
    razon_social: str = Field(..., min_length=2)
    identificacion_fiscal: str | None = None
    direccion: str | None = None
    telefono: str | None = None
    email: EmailStr | None = None


class CatalogSyncResponse(BaseModel):
    camiones: list[CamionOut] = Field(default_factory=list)
    remolques: list[RemolqueOut] = Field(default_factory=list)
    marcas: list[MarcaOut] = Field(default_factory=list)
    modelos_camion: list[ModeloCamionOut] = Field(default_factory=list)
    transportes: list[TransporteOut] = Field(default_factory=list)
    conductores: list[ConductorOut] = Field(default_factory=list)
    productos: list[ProductoOut] = Field(default_factory=list)
    almacenes: list[AlmacenOut] = Field(default_factory=list)
    balanzas: list[BalanzaOut] = Field(default_factory=list)
    terceros: list[TerceroOut] = Field(default_factory=list)
    server_time: datetime = Field(default_factory=lambda: datetime.now(UTC))


# ---------------------------------------------------------------------------
# Pesaje
# ---------------------------------------------------------------------------


class WeighingCreate(BaseModel):
    # Identificadores existentes (si el cliente ya los envió)
    id_vehiculo: str = Field(..., min_length=1, max_length=20)
    remolque: bool = False
    id_remolque: uuid.UUID | None = None
    id_transporte: uuid.UUID | None = None
    id_conductor: str | None = None
    id_producto: uuid.UUID | None = None
    id_almacen: uuid.UUID | None = None
    id_balanza: uuid.UUID | None = None
    tipo_tercero: str | None = None
    id_tercero: uuid.UUID | None = None
    multi_despacho_recepcion: bool = False

    # Creación inline (get-or-create): si no se envía id, se busca o crea por nombre/placa
    remolque_placa: str | None = None
    transporte_nombre: str | None = None
    conductor_cedula: str | None = None
    conductor_nombre: str | None = None
    producto_nombre: str | None = None
    almacen_nombre: str | None = None
    balanza_nombre: str | None = None
    tercero_nombre: str | None = None

    # Pesaje
    es_peso_manual: bool = False
    fecha_hora_entrada: datetime = Field(default_factory=lambda: datetime.now(UTC))
    peso_entrada_vehiculo: Decimal = Field(..., ge=0)
    peso_entrada_remolque: Decimal | None = None
    documento: str | None = None
    flete: str | None = None
    costo_flete: Decimal | None = None
    observaciones: str | None = None

    @field_validator("peso_entrada_vehiculo")
    @classmethod
    def _no_negativo(cls, v: Decimal) -> Decimal:
        if v < 0:
            raise ValueError("El peso no puede ser negativo")
        return v


class WeighingClose(BaseModel):
    es_peso_manual: bool = False
    fecha_hora_salida: datetime = Field(default_factory=lambda: datetime.now(UTC))
    peso_salida_vehiculo: Decimal = Field(..., ge=0)
    peso_salida_remolque: Decimal | None = None
    peso_neto_declarado: Decimal | None = None  # PND (peso declarado en la guía)
    densidad: Decimal | None = None
    unidades: Decimal | None = None
    costo_flete: Decimal | None = None
    observaciones: str | None = None


class WeighingAnular(BaseModel):
    """Schema de anulación: el motivo es obligatorio (mínimo 10 caracteres)."""

    motivo: str = Field(..., min_length=10, max_length=500)


class WeighingUpdate(BaseModel):
    documento: str | None = None
    flete: str | None = None
    costo_flete: Decimal | None = None
    observaciones: str | None = None
    peso_neto_declarado: Decimal | None = None


class WeighingOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    boleto: uuid.UUID
    numero_boleto: str | None = None
    id_vehiculo: str | None = None
    remolque: bool = False
    id_remolque: uuid.UUID | None = None
    id_transporte: uuid.UUID | None = None
    id_conductor: str | None = None
    id_producto: uuid.UUID | None = None
    id_almacen: uuid.UUID | None = None
    id_balanza: uuid.UUID | None = None
    tipo_tercero: str | None = None
    id_tercero: uuid.UUID | None = None
    multi_despacho_recepcion: bool = False
    fecha_hora_entrada: datetime
    peso_entrada_vehiculo: Decimal
    peso_entrada_remolque: Decimal | None = None
    fecha_hora_salida: datetime | None = None
    peso_salida_vehiculo: Decimal | None = None
    peso_salida_remolque: Decimal | None = None
    peso_bruto: Decimal | None = None
    peso_tara: Decimal | None = None
    peso_total_entrada: Decimal | None = None
    peso_total_salida: Decimal | None = None
    peso_neto: Decimal | None = None
    peso_neto_declarado: Decimal | None = None
    peso_diferencia: Decimal | None = None
    porcentaje_desviacion: Decimal | None = None
    diferencia_peso: Decimal | None = None
    porcentaje_diferencia: Decimal | None = None
    densidad: Decimal | None = None
    litros: Decimal | None = None
    unidades: Decimal | None = None
    documento: str | None = None
    flete: str | None = None
    costo_flete: Decimal | None = None
    observaciones: str | None = None
    creado_por: str | None = None
    salida_por: str | None = None
    modificado_por: str | None = None
    motivo_anulacion: str | None = None
    anulado_por: str | None = None
    estado_boleto: str
    sincronizado: bool = False
    advertencia_tolerancia: str | None = None
    created_at: datetime
    updated_at: datetime


class WeighingSyncItem(BaseModel):
    boleto: str
    numero_boleto: str | None = None
    id_vehiculo: str
    remolque: bool = False
    id_remolque: uuid.UUID | None = None
    id_transporte: uuid.UUID | None = None
    id_conductor: str | None = None
    id_producto: uuid.UUID | None = None
    id_almacen: uuid.UUID | None = None
    id_balanza: uuid.UUID | None = None
    tipo_tercero: str | None = None
    id_tercero: uuid.UUID | None = None
    multi_despacho_recepcion: bool = False
    fecha_hora_entrada: datetime
    peso_entrada_vehiculo: Decimal
    peso_entrada_remolque: Decimal | None = None
    fecha_hora_salida: datetime | None = None
    peso_salida_vehiculo: Decimal | None = None
    peso_salida_remolque: Decimal | None = None
    peso_bruto: Decimal | None = None
    peso_tara: Decimal | None = None
    peso_neto: Decimal | None = None
    diferencia_peso: Decimal | None = None
    porcentaje_diferencia: Decimal | None = None
    densidad: Decimal | None = None
    litros: Decimal | None = None
    unidades: Decimal | None = None
    documento: str | None = None
    flete: str | None = None
    costo_flete: Decimal | None = None
    observaciones: str | None = None
    estado_boleto: str = "Abierto"
    created_at: datetime
    updated_at: datetime


class SyncBatchRequest(BaseModel):
    equipos: list[dict[str, Any]] = Field(default_factory=list)
    pesajes: list[WeighingSyncItem] = Field(default_factory=list)


class SyncResultItem(BaseModel):
    boleto: str
    ok: bool
    mensaje: str | None = None


class SyncBatchResponse(BaseModel):
    sincronizados: int = 0
    errores: int = 0
    detalle: list[SyncResultItem] = Field(default_factory=list)


class SyncStatusResponse(BaseModel):
    pendientes: int = 0
    ultima_sync: datetime | None = None
    max_offline_dias: int
    usando_licencia_demo: bool = False


# ---------------------------------------------------------------------------
# Identidad local (vínculo singleton con la cuenta del servidor)
# ---------------------------------------------------------------------------


class IdentidadOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_cuenta: uuid.UUID
    rif_nit: str
    nombre_fiscal: str
    nombre_comercial: str | None = None
    licencia_key: str | None = None
    licencia_tier: str | None = None
    licencia_status: str | None = None
    licencia_expira: datetime | None = None
    hardware_id: str | None = None
    rol_dispositivo: str = "LOCAL"
    ultima_validacion: datetime | None = None
    modo_offline: bool = False
    created_at: datetime
    updated_at: datetime


class IdentidadUpdate(BaseModel):
    id_cuenta: uuid.UUID
    rif_nit: str = Field(..., min_length=3, max_length=20)
    nombre_fiscal: str = Field(..., min_length=3, max_length=255)
    nombre_comercial: str | None = Field(None, max_length=255)
    licencia_key: str | None = None
    licencia_tier: str | None = None
    licencia_status: str | None = None
    licencia_expira: datetime | None = None
    hardware_id: str | None = None
    rol_dispositivo: str = "LOCAL"
    modo_offline: bool = False

    @field_validator("licencia_expira")
    @classmethod
    def _licencia_naive_utc(cls, v):
        if v is not None and v.tzinfo is not None:
            return v.astimezone(UTC).replace(tzinfo=None)
        return v


# ---------------------------------------------------------------------------
# Usuarios locales (roles operativos + vínculo con credencial global)
# ---------------------------------------------------------------------------

_ROLES_LOCALES = "^(ADMIN|OPERADOR|AUDITOR|TRABAJADOR)$"


class UsuarioCreate(BaseModel):
    nombre: str = Field(..., min_length=3, max_length=150)
    email: EmailStr
    password: str = Field(..., min_length=6, max_length=128)
    rol: str = Field("OPERADOR", pattern=_ROLES_LOCALES)


class UsuarioUpdate(BaseModel):
    nombre: str | None = Field(None, min_length=3, max_length=150)
    rol: str | None = Field(None, pattern=_ROLES_LOCALES)
    activo: bool | None = None
    password: str | None = Field(None, min_length=6, max_length=128)


class UsuarioOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_usuario: uuid.UUID
    id_empresa: uuid.UUID
    id_credencial: uuid.UUID | None = None
    nombre: str
    email: EmailStr
    rol: str
    activo: bool
    created_at: datetime
    updated_at: datetime


# ---------------------------------------------------------------------------
# Perfil de la empresa (datos de contacto + logo para tickets/reportes)
# ---------------------------------------------------------------------------


class EmpresaPerfilOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_empresa: uuid.UUID
    nombre_fiscal: str
    nombre_comercial: str | None = None
    rif_nit: str
    direccion: str | None = None
    telefono: str | None = None
    email: str | None = None
    logo_url: str | None = None
    updated_at: datetime


class EmpresaPerfilUpdate(BaseModel):
    nombre_fiscal: str | None = Field(None, min_length=3, max_length=255)
    nombre_comercial: str | None = Field(None, max_length=255)
    rif_nit: str | None = Field(None, min_length=3, max_length=20)
    direccion: str | None = Field(None, max_length=500)
    telefono: str | None = Field(None, max_length=50)
    email: EmailStr | None = None
    logo_url: str | None = Field(None, max_length=500)
