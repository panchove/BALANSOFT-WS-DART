"""Esquemas Pydantic para la API."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
    ValidationInfo,
    field_validator,
    model_validator,
)

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


class LoginCentralRequest(BaseModel):
    """Login CENTRAL-first: valida la cuenta en el servidor central y si es
    válida hace espejo local (empresa + usuario admin) para seguir offline."""

    email: EmailStr
    password: str
    server_url: str | None = None
    hardware_id: str | None = None
    mac_address: str | None = None
    device_brand: str | None = None
    device_model: str | None = None
    os_version: str | None = None
    nombre_equipo: str | None = None
    sistema_operativo: str | None = None
    version_app: str | None = None
    #: Rol que la estación quiere tomar en la instalación. ``SERVIDOR`` solo se
    #: acepta si el central reconoce a este equipo como titular de la licencia
    #: (``dispositivo.rol_dispositivo = SERVIDOR_LOCAL``). ``None`` = login normal.
    #: El antiguo ``TRABAJADOR`` se conserva como alias de ``OPERADOR`` para no
    #: romper instaladores ya desplegados (el término visible es "Operador").
    modo_solicitado: Literal["SERVIDOR", "TRABAJADOR", "OPERADOR"] | None = None


class ValidateLicenseRequest(BaseModel):
    licencia_key: str | None = None
    hardware_id: str | None = None
    mac_address: str | None = None
    device_brand: str | None = None
    device_model: str | None = None
    os_version: str | None = None


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
    formato_ticket: str | None = "PDF"
    formato_reporte: str | None = "EXCEL"
    idioma: str = "es"
    logo_url: str | None = None
    ruta_exportacion_reportes: str | None = None
    # Datos de contacto: los trae el central al validar la cuenta y son los
    # que la estación precarga en el formulario de empresa (paso 4).
    direccion: str | None = None
    telefono: str | None = None
    email: str | None = None
    # Tipografía del ticket (REQ-FN-009): la estación la necesita al arrancar,
    # antes de que exista la pantalla de ajustes (T7/T10a).
    tamano_ticket_pdf: Literal["AUTOMATICO", "GRANDE", "MEDIANO", "PEQUENO"] = "AUTOMATICO"
    fuente_ticket_pdf: Literal["DejaVu"] = "DejaVu"


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


class CategoriaOut(CatalogItemOut):
    id_categoria: uuid.UUID
    codigo: str | None = None
    nombre: str
    descripcion: str | None = None
    activo: bool = True


class CategoriaCreate(BaseModel):
    codigo: str | None = None
    nombre: str = Field(..., min_length=2)
    descripcion: str | None = None
    activo: bool = True


class ProductoOut(CatalogItemOut):
    id_producto: uuid.UUID
    id_categoria: uuid.UUID
    categoria_nombre: str | None = None
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
    id_categoria: uuid.UUID = Field(
        ..., description="Categoría a la que pertenece el producto (obligatoria)"
    )
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
    formato_trama: str | None = None
    baudrate: int | None = None
    delimitador: str | None = None
    #: Indicador (terminal) asignado, o None si aún no se ha enlazado.
    id_indicador: uuid.UUID | None = None


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
    formato_trama: str = Field("auto", pattern="^(auto|json|ascii)$")
    baudrate: int = Field(9600)
    delimitador: str | None = Field(None, pattern="^(lf|cr|crlf|stx_etx)$")
    #: Indicador (terminal) a enlazar con esta báscula física (migración 028).
    id_indicador: uuid.UUID | None = None

    @field_validator("baudrate")
    @classmethod
    def _validar_baudrate(cls, v: int) -> int:
        # Debe coincidir con el CHECK `ck_balanzas_baudrate` de la BD (evita
        # que un valor intermedio pase Pydantic y reviente como IntegrityError).
        permitidos = {1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200}
        if v not in permitidos:
            raise ValueError(
                "baudrate debe ser uno de: 1200, 2400, 4800, 9600, 19200, "
                "38400, 57600, 115200"
            )
        return v


class BalanzaDescubiertaOut(BaseModel):
    """Báscula detectada por el escaneo automático de dispositivos."""

    descripcion: str
    protocolo: str
    ip_address: str | None = None
    puerto_tcp: int | None = None
    puerto_com: str | None = None
    peso_kg: float | None = None
    is_simulada: bool = False
    formato_trama: str | None = None
    baudrate: int | None = None
    delimitador: str | None = None


class BalanzaPruebaOut(BaseModel):
    """Resultado de la prueba de conexión del HAL de una balanza."""

    balanza: str
    conectado: bool
    hardware: str | None = None
    protocolo: str | None = None
    peso_kg: float | None = None
    estable: bool = False
    detalle: str | None = None
    formato_trama: str | None = None
    delimitador: str | None = None


class SemaforoOut(CatalogItemOut):
    """Semáforo de pesaje registrado (actuador de salida)."""

    id_semaforo: uuid.UUID
    codigo: str | None = None
    descripcion: str
    activo: bool = True
    is_simulado: bool = False
    protocolo: str | None = None
    ip_address: str | None = None
    puerto_tcp: int | None = None
    puerto_com: str | None = None
    baudrate: int | None = None
    id_balanza: uuid.UUID | None = None
    control_automatico: bool = False
    umbral_cero_kg: Decimal | None = None


class SemaforoCreate(BaseModel):
    codigo: str | None = None
    descripcion: str = Field(..., min_length=2)
    activo: bool = True
    is_simulado: bool = False
    protocolo: str = Field("http", pattern="^(http|serial)$")
    ip_address: str | None = None
    puerto_tcp: int | None = Field(None, gt=0, le=65535)
    puerto_com: str | None = None
    baudrate: int = Field(9600)
    id_balanza: uuid.UUID | None = None
    control_automatico: bool = False
    umbral_cero_kg: Decimal = Field(Decimal("5.0"), ge=0, le=100000)

    @field_validator("baudrate")
    @classmethod
    def _validar_baudrate_semaforo(cls, v: int) -> int:
        # Mismo conjunto que las básculas/`ck_semaforos_baudrate`.
        permitidos = {1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200}
        if v not in permitidos:
            raise ValueError(
                "baudrate debe ser uno de: 1200, 2400, 4800, 9600, 19200, "
                "38400, 57600, 115200"
            )
        return v


class SemaforoDescubiertoOut(BaseModel):
    """Semáforo detectado por el escaneo automático de dispositivos."""

    descripcion: str
    protocolo: str
    ip_address: str | None = None
    puerto_tcp: int | None = None
    puerto_com: str | None = None
    is_simulado: bool = False
    estado: dict[str, Any] | None = None


class SemaforoPruebaOut(BaseModel):
    """Resultado de la prueba de conexión del HAL de un semáforo."""

    semaforo: str
    conectado: bool
    protocolo: str | None = None
    estado: dict[str, Any] | None = None
    detalle: str | None = None


class SemaforoComandoIn(BaseModel):
    """Comando de LED del semáforo (SPEC §4/§5.6, mismo JSON en todos los canales).

    Forma canónica: ``{"color":"rojo","action":"on"|"off"|"flash"}``,
    ``{"zumbador":"on"|"off"}``, ``{"all":"off"}``, ``{"reset":true}`` o
    ``{"automatico":false}``. Se aceptan además el alias ``luz`` de ``color`` y
    los **atajos planos** del SPEC §5.6 (``{"rojo":true}``, ``{"verde":"flash"}``,
    ``{"rojo":false}``).
    """

    color: Literal["rojo", "amarillo", "verde"] | None = None
    luz: Literal["rojo", "amarillo", "verde"] | None = None
    action: Literal["on", "off", "flash"] | None = None
    #: Atajos planos por color: booleano (encender/apagar) o acción del SPEC.
    rojo: bool | Literal["on", "off", "flash"] | None = None
    amarillo: bool | Literal["on", "off", "flash"] | None = None
    verde: bool | Literal["on", "off", "flash"] | None = None
    zumbador: bool | Literal["on", "off"] | None = None
    all: Literal["off"] | None = None
    reset: bool | None = None
    automatico: bool | None = None


class SemaforoEstadoOut(BaseModel):
    """Estado publicado por el semáforo (SPEC §3) más metadatos de la app."""

    semaforo: str
    conectado: bool
    automatico: bool = False
    estado: dict[str, Any] | None = None
    #: Fase decidida por la app (memoria del vigilante): AUTORIZADO, PESANDO, …
    fase: str | None = None
    #: Últimas luces ordenadas por la app: {rojo, amarillo, verde, zumbador}.
    luces: dict[str, Any] | None = None
    detalle: str | None = None


class SemaforoAutomaticoIn(BaseModel):
    """Activa/desactiva el control automático (vigilante backend)."""

    activo: bool


class SemaforoComandoOut(BaseModel):
    """Resultado de un comando manual al semáforo."""

    aplicado: bool
    comando: dict[str, Any]
    detalle: str | None = None


# ---------------------------------------------------------------------------
# Cámaras de captura de placa (migración 027)
# ---------------------------------------------------------------------------


class CamaraOut(CatalogItemOut):
    """Cámara registrada. La ``password`` NUNCA se expone."""

    id_camara: uuid.UUID
    codigo: str | None = None
    descripcion: str
    marca: str | None = None
    modelo: str | None = None
    fabricante: str | None = None
    por_donde: str | None = None
    activo: bool = True
    is_simulada: bool = False
    #: ip|local. Las locales (USB/integradas) capturan el *frame* con ffmpeg.
    origen: Literal["ip", "local"] = "ip"
    url_snapshot: str = ""
    #: Ruta del dispositivo para las locales (ej. ``/dev/video0``).
    dispositivo: str | None = None
    usuario: str | None = None
    ubicacion: Literal["entrada", "salida", "ambos"] = "ambos"
    #: True si hay contraseña guardada (el valor no se devuelve).
    password_configurada: bool = False


class CamaraCreate(BaseModel):
    codigo: str | None = Field(None, max_length=20)
    descripcion: str = Field(..., min_length=2, max_length=150)
    marca: str | None = Field(None, max_length=100)
    modelo: str | None = Field(None, max_length=100)
    fabricante: str | None = Field(None, max_length=100)
    activo: bool = True
    is_simulada: bool = False
    origen: Literal["ip", "local"] = "ip"
    #: Obligatoria solo para ``origen='ip'`` (se valida en la ruta).
    url_snapshot: str = Field("", max_length=500)
    #: Obligatoria solo para ``origen='local'`` (se valida en la ruta).
    dispositivo: str | None = Field(None, max_length=255)
    usuario: str | None = Field(None, max_length=100)
    password: str | None = Field(None, max_length=255)
    ubicacion: Literal["entrada", "salida", "ambos"] = "ambos"


class CamaraDescubiertaOut(BaseModel):
    """Cámara detectada por el escaneo (red local o dispositivo del equipo)."""

    descripcion: str
    origen: Literal["ip", "local"] = "ip"
    url_snapshot: str = ""
    dispositivo: str | None = None
    marca: str | None = None
    modelo: str | None = None
    fabricante: str | None = None
    por_donde: str | None = None
    ubicacion: Literal["entrada", "salida", "ambos"] = "ambos"
    is_simulada: bool = False
    detalle: str | None = None


class CamaraPruebaOut(BaseModel):
    """Resultado de la prueba de conexión (descarga del snapshot sin persistir)."""

    camara: str
    conectado: bool
    detalle: str | None = None
    ancho: int | None = None
    alto: int | None = None
    tamano_kb: float | None = None


class CamaraCapturarIn(BaseModel):
    """Captura una foto de placa del boleto desde la cámara."""

    boleto: uuid.UUID
    #: placa_trasera | frente | placa_remolque (sufijo del nombre del archivo).
    foto: Literal["placa_trasera", "frente", "placa_remolque"]


# ---------------------------------------------------------------------------
# Indicadores (terminal de peso) — migración 028
# ---------------------------------------------------------------------------


class IndicadorOut(CatalogItemOut):
    """Indicador (terminal) registrado, enlazable a una báscula física."""

    id_indicador: uuid.UUID
    codigo: str | None = None
    descripcion: str
    marca: str | None = None
    modelo: str | None = None
    activo: bool = True
    is_simulado: bool = False
    protocolo: str | None = None
    puerto_com: str | None = None
    ip_address: str | None = None
    puerto_tcp: int | None = None
    formato_trama: str | None = None
    baudrate: int | None = None
    delimitador: str | None = None
    #: Básculas físicas enlazadas (para mostrar «en uso» en la UI).
    balanzas_enlazadas: int = 0


class IndicadorCreate(BaseModel):
    codigo: str | None = Field(None, max_length=20)
    descripcion: str = Field(..., min_length=2, max_length=150)
    marca: str | None = Field(None, max_length=100)
    modelo: str | None = Field(None, max_length=100)
    activo: bool = True
    is_simulado: bool = False
    protocolo: str | None = Field(None, pattern="^(tcp|serial)$")
    puerto_com: str | None = Field(None, max_length=50)
    ip_address: str | None = Field(None, max_length=45)
    puerto_tcp: int | None = Field(None, gt=0, le=65535)
    formato_trama: str = Field("auto", pattern="^(auto|json|ascii)$")
    baudrate: int = Field(9600)
    delimitador: str | None = Field(None, pattern="^(lf|cr|crlf|stx_etx)$")

    @field_validator("baudrate")
    @classmethod
    def _validar_baudrate(cls, v: int) -> int:
        # Debe coincidir con el CHECK `ck_indicadores_baudrate` de la BD.
        permitidos = {1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200}
        if v not in permitidos:
            raise ValueError(
                "baudrate debe ser uno de: 1200, 2400, 4800, 9600, 19200, "
                "38400, 57600, 115200"
            )
        return v


# ---------------------------------------------------------------------------
# Conceptos de inventario (catálogo de motivos de kardex) — migración 029
# ---------------------------------------------------------------------------


class ConceptoInventarioOut(CatalogItemOut):
    """Concepto de inventario (motivo de un movimiento de kardex)."""

    id_concepto: uuid.UUID
    codigo: str | None = None
    nombre: str
    descripcion: str | None = None
    tipo_movimiento: str | None = None
    activo: bool = True


class ConceptoInventarioCreate(BaseModel):
    """Alta/edición de un concepto de inventario."""

    codigo: str | None = Field(None, max_length=20)
    nombre: str = Field(..., min_length=2, max_length=150)
    descripcion: str | None = Field(None, max_length=255)
    tipo_movimiento: str | None = Field(
        None, pattern="^(ingreso|despacho|ajuste|ambos)$"
    )
    activo: bool = True


class ConceptoKardexOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id_concepto: int
    id_empresa: uuid.UUID
    nombre: str
    descripcion: str | None = None
    signo: str
    es_sistema: bool = False
    activo: bool = True
    aplica_a: str = "AMBOS"
    created_at: datetime | None = None
    updated_at: datetime | None = None


class ConceptoKardexCreate(BaseModel):
    id_concepto: int = Field(..., ge=0, le=99)
    nombre: str = Field(..., min_length=2)
    descripcion: str | None = None
    signo: str = Field(..., pattern="^(inicial|positivo|negativo)$")
    es_sistema: bool = False
    activo: bool = True
    aplica_a: str = Field(default="AMBOS", pattern="^(INGRESO|DESPACHO|AJUSTE|AMBOS)$")

    @model_validator(mode="after")
    def validar_coherencia(self):
        if self.id_concepto == 0 and self.signo != "inicial":
            raise ValueError("El concepto 0 debe tener signo 'inicial'")
        if 1 <= self.id_concepto <= 49 and self.signo != "positivo":
            raise ValueError("Los conceptos 1-49 deben tener signo 'positivo'")
        if 50 <= self.id_concepto <= 99 and self.signo != "negativo":
            raise ValueError("Los conceptos 50-99 deben tener signo 'negativo'")
        return self


class ConceptoKardexUpdate(BaseModel):
    nombre: str | None = Field(default=None, min_length=2)
    descripcion: str | None = None
    activo: bool | None = None
    aplica_a: str | None = Field(default=None, pattern="^(INGRESO|DESPACHO|AJUSTE|AMBOS)$")

    # Se acepta para poder **rechazar** el cambio de forma explícita: el signo
    # es derivado del ID (regla de oro del kardex) y nunca se modifica. Sin este
    # campo el cliente mandaría el signo y recibiría un 200 engañoso.
    signo: str | None = Field(default=None, pattern="^(inicial|positivo|negativo)$")


# ---------------------------------------------------------------------------
# Barreras de tránsito (control de acceso) — migración 032
# ---------------------------------------------------------------------------


class BarreraOut(CatalogItemOut):
    """Barrera de control de acceso registrada."""

    id_barrera: uuid.UUID
    codigo: str | None = None
    descripcion: str
    activo: bool = True
    is_simulado: bool = False
    protocolo: str = "http"
    ip_address: str | None = None
    puerto_tcp: int | None = None
    puerto_com: str | None = None
    baudrate: int = 9600
    ubicacion: str = "ambos"
    control_automatico: bool = False
    tiempo_espera_segundos: int = 5
    comando_abrir: str | None = None
    comando_cerrar: str | None = None


class BarreraCreate(BaseModel):
    codigo: str | None = Field(None, max_length=20)
    descripcion: str = Field(..., min_length=2, max_length=150)
    activo: bool = True
    is_simulado: bool = False
    protocolo: str = Field("http", pattern="^(http|serial)$")
    ip_address: str | None = Field(None, max_length=45)
    puerto_tcp: int | None = Field(None, gt=0, le=65535)
    puerto_com: str | None = Field(None, max_length=50)
    baudrate: int = Field(9600)
    ubicacion: str = Field("ambos", pattern="^(entrada|salida|ambos)$")
    control_automatico: bool = False
    tiempo_espera_segundos: int = Field(5, ge=1, le=3600)
    comando_abrir: str | None = Field(None, max_length=255)
    comando_cerrar: str | None = Field(None, max_length=255)

    @field_validator("baudrate")
    @classmethod
    def _validar_baudrate(cls, v: int) -> int:
        permitidos = {1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200}
        if v not in permitidos:
            raise ValueError(
                "baudrate debe ser uno de: 1200, 2400, 4800, 9600, 19200, "
                "38400, 57600, 115200"
            )
        return v


class BarreraUpdate(BaseModel):
    codigo: str | None = Field(None, max_length=20)
    descripcion: str | None = Field(None, min_length=2, max_length=150)
    activo: bool | None = None
    is_simulado: bool | None = None
    protocolo: str | None = Field(None, pattern="^(http|serial)$")
    ip_address: str | None = Field(None, max_length=45)
    puerto_tcp: int | None = Field(None, gt=0, le=65535)
    puerto_com: str | None = Field(None, max_length=50)
    baudrate: int | None = None
    ubicacion: str | None = Field(None, pattern="^(entrada|salida|ambos)$")
    control_automatico: bool | None = None
    tiempo_espera_segundos: int | None = Field(None, ge=1, le=3600)
    comando_abrir: str | None = Field(None, max_length=255)
    comando_cerrar: str | None = Field(None, max_length=255)

    @field_validator("baudrate")
    @classmethod
    def _validar_baudrate(cls, v: int | None) -> int | None:
        if v is None:
            return None
        permitidos = {1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200}
        if v not in permitidos:
            raise ValueError(
                "baudrate debe ser uno de: 1200, 2400, 4800, 9600, 19200, "
                "38400, 57600, 115200"
            )
        return v


class BarreraDescubiertaOut(BaseModel):
    descripcion: str
    protocolo: str
    ip_address: str | None = None
    puerto_tcp: int | None = None
    puerto_com: str | None = None
    is_simulado: bool = False
    estado: dict[str, Any] | None = None


class BarreraPruebaOut(BaseModel):
    barrera: str
    conectado: bool
    protocolo: str | None = None
    estado: dict[str, Any] | None = None
    detalle: str | None = None


class BarreraEstadoOut(BaseModel):
    barrera: str
    conectado: bool
    estado: dict[str, Any] | None = None
    detalle: str | None = None


class BarreraComandoIn(BaseModel):
    action: Literal["open", "close"]


class BarreraComandoOut(BaseModel):
    aplicado: bool
    action: str
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
    categorias: list[CategoriaOut] = Field(default_factory=list)
    balanzas: list[BalanzaOut] = Field(default_factory=list)
    terceros: list[TerceroOut] = Field(default_factory=list)
    server_time: datetime = Field(default_factory=lambda: datetime.now(UTC))
    # H11: paginación de /catalogo/sync. `totales` es el número real de
    # registros por catálogo y `truncado` indica si la respuesta quedó
    # recortada por `limit` (el cliente debe pedir la página siguiente).
    totales: dict[str, int] = Field(default_factory=dict)
    truncado: bool = False


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
    id_serie: uuid.UUID | None = None
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
    peso_neto_declarado: Decimal | None = None  # PND (peso declarado en la guía)
    documento: str | None = None
    guia_sunagro: str | None = None
    medida: str | None = None
    flete: str | None = None
    costo_flete: Decimal | None = None
    densidad: Decimal | None = None
    litros: Decimal | None = None
    unidades: Decimal | None = None
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
    litros: Decimal | None = None
    unidades: Decimal | None = None
    costo_flete: Decimal | None = None
    observaciones: str | None = None
    guia_sunagro: str | None = None
    medida: str | None = None
    documento: str | None = None
    flete: str | None = None


class WeighingAnular(BaseModel):
    """Schema de anulación: el motivo es obligatorio (mínimo 10 caracteres)."""

    motivo: str = Field(..., min_length=10, max_length=500)


class WeighingUpdate(BaseModel):
    documento: str | None = None
    guia_sunagro: str | None = None
    medida: str | None = None
    flete: str | None = None
    costo_flete: Decimal | None = None
    observaciones: str | None = None
    peso_neto_declarado: Decimal | None = None
    densidad: Decimal | None = None
    litros: Decimal | None = None
    unidades: Decimal | None = None
    # Justificación obligatoria de la edición (RB: editar exige motivo y queda
    # registrado por edición en `boletos_ediciones`).
    justificacion: str = Field(..., min_length=10, max_length=500)


class BoletoEdicionOut(BaseModel):
    """Una edición registrada de un boleto (historial inmutable)."""

    model_config = ConfigDict(from_attributes=True)
    id_edicion: uuid.UUID
    boleto: uuid.UUID
    numero_boleto: str | None = None
    id_usuario: uuid.UUID | None = None
    usuario_nombre: str | None = None
    rol_usuario: str | None = None
    fecha_edicion: datetime
    ip: str | None = None
    justificacion: str
    estado_anterior: str
    estado_nuevo: str
    campos_modificados: dict | None = None
    edicion_numero: int


class WeighingOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    boleto: uuid.UUID
    numero_boleto: str | None = None
    id_serie: uuid.UUID | None = None
    serie_nombre: str | None = None
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
    guia_sunagro: str | None = None
    medida: str | None = None
    flete: str | None = None
    costo_flete: Decimal | None = None
    observaciones: str | None = None
    es_peso_manual: bool = False
    creado_por: str | None = None
    salida_por: str | None = None
    modificado_por: str | None = None
    motivo_anulacion: str | None = None
    anulado_por: str | None = None
    estado_boleto: str
    sincronizado: bool = False
    ediciones_count: int = 0
    motivo_modificacion_ultima: str | None = None
    ultimo_editor_nombre: str | None = None
    advertencia_tolerancia: str | None = None
    created_at: datetime
    updated_at: datetime
    # Nombres legibles (enriquecidos por el servidor, no almacenados en DB)
    transporte_nombre: str | None = None
    conductor_nombre: str | None = None
    producto_nombre: str | None = None
    almacen_nombre: str | None = None
    balanza_nombre: str | None = None
    tercero_nombre: str | None = None
    remolque_placa: str | None = None
    # Movimiento de kardex del boleto: 10 INGRESO / 60 DESPACHO / None sin
    # asiento (boleto PENDIENTE). Alimenta INGRESOS / DESPACHOS en la lista.
    kardex_mov: int | None = None
    # Fotos de placa (migración 027): TRUE cuando ya se pidieron una vez.
    fotos_placa_tomadas: bool = False


class WeighingSyncItem(BaseModel):
    boleto: str
    numero_boleto: str | None = None
    id_serie: uuid.UUID | None = None
    nombre_serie: str | None = None
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

_ROLES_LOCALES = "^(ADMIN|OPERADOR|AUDITOR)$"


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
    formato_ticket: str | None = "PDF"
    formato_reporte: str | None = "EXCEL"
    idioma: Literal["es", "en", "pt"] = "es"
    ruta_exportacion_reportes: str | None = None
    tamano_ticket_pdf: Literal["AUTOMATICO", "GRANDE", "MEDIANO", "PEQUENO"] = "AUTOMATICO"
    fuente_ticket_pdf: Literal["DejaVu"] = "DejaVu"
    # Edición de boletos + impresión automática (config por empresa)
    max_ediciones_boleto: int | None = None
    impresion_automatica: bool = False
    protocolo_impresion: str | None = None
    impresora_nombre: str | None = None
    impresora_host: str | None = None
    impresora_puerto: int | None = None
    # Fotos de placa (migración 027)
    fotos_placa_activas: bool = False
    fotos_placa_obligatorias: bool = False
    updated_at: datetime

    @field_validator("tamano_ticket_pdf", "fuente_ticket_pdf", mode="before")
    @classmethod
    def _nulo_a_default(cls, valor: object, info: ValidationInfo) -> object:
        """Las columnas son `nullable=True` por compatibilidad (REQ-FN-012).

        Una fila heredada con NULL no puede tumbar `GET /empresa` con un 500: se
        devuelve el default de negocio, que es lo que la estación ya usaba.
        """
        if valor is not None:
            return valor
        return "DejaVu" if info.field_name == "fuente_ticket_pdf" else "AUTOMATICO"


class EmpresaPerfilUpdate(BaseModel):
    nombre_fiscal: str | None = Field(None, min_length=3, max_length=255)
    nombre_comercial: str | None = Field(None, max_length=255)
    rif_nit: str | None = Field(None, min_length=3, max_length=20)
    direccion: str | None = Field(None, max_length=500)
    telefono: str | None = Field(None, max_length=50)
    email: EmailStr | None = None
    logo_url: str | None = Field(None, max_length=500)
    formato_ticket: Literal["PDF", "TXT"] | None = Field(None)
    formato_reporte: Literal["EXCEL", "PDF"] | None = Field(None)
    idioma: Literal["es", "en", "pt"] | None = Field(None)
    ruta_exportacion_reportes: str | None = Field(None, max_length=500)
    tamano_ticket_pdf: Literal["AUTOMATICO", "GRANDE", "MEDIANO", "PEQUENO"] | None = Field(None)
    fuente_ticket_pdf: Literal["DejaVu"] | None = Field(None)
    # Edición de boletos + impresión automática
    max_ediciones_boleto: int | None = Field(None, ge=0, le=1000)
    impresion_automatica: bool | None = Field(None)
    protocolo_impresion: (
        Literal["predeterminada_so", "raw_9100", "lpd_cups", "nombre_impresora"] | None
    ) = Field(None)
    impresora_nombre: str | None = Field(None, max_length=255)
    impresora_host: str | None = Field(None, max_length=100)
    impresora_puerto: int | None = Field(None, ge=1, le=65535)
    fotos_placa_activas: bool | None = Field(None)
    fotos_placa_obligatorias: bool | None = Field(None)


# ---------------------------------------------------------------------------
# Seguridad y Accesos – matriz de módulos por rol
# ---------------------------------------------------------------------------


class AccesoModuloOut(BaseModel):
    clave: str
    titulo: str
    accesos: dict[str, str]


class MatrizAccesosOut(BaseModel):
    modulos: list[AccesoModuloOut] = Field(default_factory=list)


class AccesoUpdate(BaseModel):
    rol: str = Field(..., min_length=1)
    modulo: str = Field(..., min_length=1)
    acceso: str = Field(..., pattern=r"^(ver|editar|ninguno)$")


class RolOut(BaseModel):
    """Rol local de la estación con su descripción y usuarios asignados."""

    clave: str
    nombre: str
    descripcion: str
    usuarios: int = 0
    modulos_editar: int = 0
    modulos_ver: int = 0
    modulos_ninguno: int = 0


class SerieNumeracionCreate(BaseModel):
    nombre: str = Field(..., min_length=1, max_length=80)
    prefijo: str = Field(..., min_length=1, max_length=20)
    inicio: int = Field(1, ge=1)
    digitos: int = Field(8, ge=1, le=20)
    activa: bool = False


class SerieNumeracionUpdate(BaseModel):
    nombre: str | None = Field(None, min_length=1, max_length=80)
    prefijo: str | None = Field(None, min_length=1, max_length=20)
    digitos: int | None = Field(None, ge=1, le=20)


class SerieNumeracionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_serie: uuid.UUID
    id_empresa: uuid.UUID
    nombre: str
    prefijo: str
    inicio: int
    siguiente: int
    digitos: int
    activa: bool
    created_at: datetime
    updated_at: datetime


# ---------------------------------------------------------------------------
# Ajustes de inventario (movimiento kardex manual)
# ---------------------------------------------------------------------------


class AjusteInventarioCreate(BaseModel):
    """Movimiento de ajuste manual de inventario (kardex)."""

    id_producto: uuid.UUID
    id_almacen: uuid.UUID
    id_concepto: int = Field(..., ge=1, le=99)
    cantidad: Decimal = Field(..., description="Cantidad con signo según concepto")
    motivo: str = Field(..., min_length=10, max_length=200)
    documento: str | None = Field(None, max_length=100)
    fecha_documento: datetime | None = None


class AjusteInventarioOut(BaseModel):
    """Registro de kardex generado por el ajuste."""

    model_config = ConfigDict(from_attributes=True)
    id_kardex: uuid.UUID
    id_empresa: uuid.UUID
    id_movimiento: int
    id_producto: uuid.UUID | None
    id_almacen: uuid.UUID | None
    id_concepto: uuid.UUID | None = None
    valor: Decimal
    documento: str | None
    fecha_kardex: datetime
    created_at: datetime


class SeedCatalogosResponse(BaseModel):
    """Resultado de la siembra inicial de catálogos (REQ-FN-023)."""

    aplicado: bool
    categorias: int
    productos: int
    almacenes: int


class BackupOut(BaseModel):
    """Metadatos de un snapshot de estación (REQ-NF-BKP-001/002/003)."""

    archivo: str
    creado_en: datetime
    motivo: str
    tamano_bytes: int
    id_empresa: uuid.UUID
    empresa_nombre: str | None
    empresa_rif: str | None
    conteos: dict[str, int]
    version: int


class BackupRestoreRequest(BaseModel):
    confirmar: bool = False


class BackupRestoreResponse(BaseModel):
    archivo: str
    restaurados: dict[str, int]
    advertencia: str


# ---------------------------------------------------------------------------
# Llaves de activación (estaciones OPERADOR / cliente delgado)
# ---------------------------------------------------------------------------


class LlaveActivacionCreateRequest(BaseModel):
    """El ADMIN emite una llave de un solo uso para un usuario de su empresa."""

    id_usuario: uuid.UUID
    #: Vigencia en horas desde la emisión (1 a 90 días).
    expira_horas: int = Field(24, ge=1, le=24 * 90)


class LlaveActivacionCreateResponse(BaseModel):
    """``codigo`` se devuelve **una sola vez**: en la BD solo queda el hash."""

    ok: bool = True
    id: uuid.UUID
    codigo: str
    codigo_preview: str
    expira_en: datetime | None = None
    mensaje: str


class LlaveActivacionValidarRequest(BaseModel):
    """Canje desde el instalador de una estación cliente (sin autenticación)."""

    codigo: str = Field(..., min_length=8, max_length=64)
    hardware_id: str | None = Field(None, max_length=255)


class LlaveActivacionValidarResponse(BaseModel):
    ok: bool = True
    usuario_email: str
    empresa_nombre: str
    mensaje: str


from app.schemas.setup import (  # noqa: E402
    SetupCreateAdminRequest,
    SetupCreateAdminResponse,
    SetupEmpresaOut,
    SetupLicenseOut,
    SetupUserOut,
    SetupValidateRequest,
    SetupValidateResponse,
)
