"""Configuración centralizada de Balansoft-WS mediante pydantic-settings."""

from __future__ import annotations

import json
import logging
from functools import lru_cache
from typing import Annotated, Any

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

log = logging.getLogger("balansoft_ws.config")

_SECRET_KEY_INSEGURA = {
    "dev_secret_key_balansoft_ws_2026",
    "CAMBIAR_ESTA_CLAVE_CON_openssl_rand_hex_32",
}


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    app_name: str = "Balansoft-WS"
    app_env: str = "development"
    debug_mode: bool = True
    api_docs_enabled: bool = True

    # Base de datos de negocio (separada del LM)
    database_url: str = "postgresql+asyncpg://sqlman:7767@localhost:5432/balansoft_ws"
    database_url_sync: str = "postgresql+psycopg2://sqlman:7767@localhost:5432/balansoft_ws"

    # Rol del despliegue (arquitectura de dos BDs, docs/MANEJO_DB.md):
    #   "local"  -> estación: DB operativa (boletos, catálogos, usuarios) + login-local offline
    #   "server" -> central: DB de cuenta y licencia (cuentas, credenciales, licencias, sync)
    app_role: str = "local"
    # URL base del servidor (solo para roles "local"; vacío = no configurado)
    server_api_url: str = ""
    # Timeout (s) de las llamadas HTTP al central desde login-central
    # (env CENTRAL_TIMEOUT, case-insensitive). El arranque en frío contra el
    # central incluye DNS + TLS + cold start de Cloudflare: con 10 s salía un
    # ConnectTimeout intermitente. Ahora 30 s + un reintento único ante
    # ConnectTimeout/ReadTimeout (docs/MANEJO_DB.md §11).
    central_timeout: Annotated[int, Field(ge=1, le=600)] = 30
    # URL de la DB del servidor. En rol "server" se usa database_url si esto es None.
    server_database_url: str | None = None

    # LM Local (SGLB)
    license_api_url: str = "http://localhost:8080/api/v1"
    license_admin_url: str = "http://localhost:5000"
    license_public_key: str | None = None
    # Alternativa a license_public_key: ruta a un archivo PEM (evita problemas
    # de parsing multilínea en .env y en EnvironmentFile de systemd). Es la vía
    # recomendada en servidores (mismo patrón que BALANSOFT-SG: keys/*.pem).
    license_public_key_path: str | None = None
    # Código de producto registrado en el LM (products.code: "WS"). La clave de
    # licencia usa el prefijo BWS-… pero `product_code` enviado al LM es "WS".
    license_product_code: str = "WS"
    # TTL (segundos) de la caché de validación para operación de pesaje: evita
    # un round-trip al LM por cada boleto. La licencia se re-valida en vivo en
    # login, /config/account y el panel (GET /auth/license).
    license_cache_ttl_seconds: int = 300

    # API
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    api_reload: bool = True
    api_workers: int = 1

    # Seguridad JWT de la aplicación (interna)
    secret_key: str = "dev_secret_key_balansoft_ws_2026"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 7

    # CORS
    cors_origins: list[str] = [
        "http://localhost:3000",
        "http://localhost:5000",
        "http://localhost:8080",
        "http://localhost:8000",
    ]

    # Logging
    log_level: str = "INFO"
    log_file: str = "logs/app.log"
    # H5: formato de salida ("text" legible | "json" estructurado) y rotación.
    log_format: str = "text"
    log_dir: str | None = None
    log_max_bytes: int = 5_000_000
    log_backup_count: int = 5

    # Sincronización
    sync_interval_minutes: int = 2
    max_offline_days: int = 30
    max_sync_retries: int = 3

    # Límites de licencia
    demo_max_records: int = 10
    monopuesta_max_users: int = 1
    central_max_users: int = 10

    # Pesaje: serie/boleto secuencial (MODEL.md: TA-00000001)
    boleto_prefix: str = "TA-"
    boleto_digitos: int = 8

    # Internacionalización: idioma por defecto del servidor (es|en|pt).
    # Se usa cuando la petición no trae ?idioma= ni Accept-Language y la
    # empresa aún no tiene idioma configurado (REQ-NF-I18N-003).
    idioma_default: str = "es"

    # Almacenamiento de fotos/imágenes adjuntas
    media_dir: str = "media"
    max_image_bytes: int = 10 * 1024 * 1024
    allowed_image_types: list[str] = ["image/jpeg", "image/png", "image/webp"]

    # Recuperación de contraseña
    password_reset_expire_minutes: int = 15
    password_reset_url_base: str = "http://localhost:8000/reset-password"
    smtp_enabled: bool = False
    smtp_host: str = "smtp.gmail.com"
    smtp_port: int = 587
    smtp_user: str | None = None
    smtp_password: str | None = None
    smtp_from: str | None = None

    # Rate-limiting (implementación propia con cachetools)
    rate_limit_enabled: bool = False
    rate_limit_login: int = 5
    rate_limit_register: int = 3
    rate_limit_password: int = 5
    rate_limit_window: int = 60  # segundos
    rate_limit_trust_proxy: bool = False

    # Monitoreo (prometheus-client)
    metrics_enabled: bool = True

    # Backups
    backup_dir: str = "backups"
    # Rotación GFS (abuelo-padre-hijo): conserva el último snapshot de cada
    # día (hijo), semana ISO (padre) y mes calendario (abuelo) dentro de las
    # últimas N ventanas. ``0`` en un nivel desactiva esa capa. La retención
    # dura por edad es opcional: ``0`` = sin límite (solo gobierna el GFS).
    backup_retention_days: int = 0
    backup_keep_daily: int = 7
    backup_keep_weekly: int = 5
    backup_keep_monthly: int = 12
    #: Minutos de inactividad del operador tras los cuales la app Flutter
    #: dispara ``POST /api/v1/backups/auto`` en estaciones SERVIDOR.
    backup_auto_idle_minutes: int = 5

    @model_validator(mode="after")
    def _validar_entorno_produccion(self) -> Settings:
        """Endurece la configuración cuando APP_ENV es producción.

        Evita arrancar en producción con ``DEBUG_MODE=true`` (filtraría enlaces
        de reset de contraseña) o con la ``SECRET_KEY`` por defecto.
        """
        if self.app_env.strip().lower() not in {"production", "prod"}:
            return self
        problemas: list[str] = []
        if self.debug_mode:
            problemas.append("DEBUG_MODE=true")
        if self.secret_key in _SECRET_KEY_INSEGURA:
            problemas.append("SECRET_KEY por defecto")
        if problemas:
            raise ValueError(
                "Configuración insegura para APP_ENV=production: "
                + "; ".join(problemas)
                + ". Corrige el .env antes de arrancar."
            )
        if "*" in self.cors_origins_list:
            log.warning(
                "CORS_ORIGINS contiene '*' en producción; restringe los orígenes."
            )
        return self

    @model_validator(mode="after")
    def _coherencia_motores(self) -> Settings:
        """Valida el motor derivado de DATABASE_URL y alinea DATABASE_URL_SYNC.

        El motor se decide SOLO por el prefijo de ``DATABASE_URL`` (no hay
        variables de entorno nuevas; ver ``app/core/db_engine.py``):

        1. Prefijo desconocido → ``ValueError`` (fail-fast al arrancar).
        2. ``DATABASE_URL_SYNC`` vacío → se deriva de ``DATABASE_URL``.
        3. Sync con un motor distinto → aviso y se deriva en memoria (NO se
           reescribe el ``.env``: la precedencia es de ``DATABASE_URL``).
        4. Mismo motor → se conserva tal cual (query params incluidos).

        ``SERVER_DATABASE_URL`` no se toca: es la BD del central.
        """
        from app.core.db_engine import derivar_url_sync, detectar_motor

        motor = detectar_motor(self.database_url)  # ValueError si el prefijo no vale
        sync = (self.database_url_sync or "").strip()
        if not sync:
            self.database_url_sync = derivar_url_sync(self.database_url)
            return self
        try:
            motor_sync = detectar_motor(sync)
        except ValueError:
            motor_sync = None
        if motor_sync != motor:
            log.warning(
                "DATABASE_URL_SYNC no corresponde al motor de DATABASE_URL "
                "(sync=%r, async=%r); se deriva en memoria de DATABASE_URL. "
                "Edita el .env para fijarla.",
                sync.split("://", 1)[0],
                self.database_url.split("://", 1)[0],
            )
            self.database_url_sync = derivar_url_sync(self.database_url)
        return self

    @property
    def cors_origins_list(self) -> list[str]:
        if isinstance(self.cors_origins, str):
            try:
                return json.loads(self.cors_origins)
            except json.JSONDecodeError:
                return [o.strip() for o in self.cors_origins.split(",") if o.strip()]
        return list(self.cors_origins)

    @property
    def db_engine(self) -> str:
        """Motor de DATABASE_URL: ``"postgresql"`` | ``"sqlserver"``."""
        from app.core.db_engine import detectar_motor

        return detectar_motor(self.database_url)

    @property
    def active_server_database_url(self) -> str:
        """URL de la DB del servidor (cuenta/licencia). En rol server = database_url."""
        return self.server_database_url or self.database_url


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

# Re-export para compatibilidad con imports de error """noqa"""
IGNORED: Any = None
