"""Configuración centralizada de Balansoft-WS mediante pydantic-settings."""

from __future__ import annotations

import json
from functools import lru_cache
from typing import Any

from pydantic_settings import BaseSettings, SettingsConfigDict


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
    backup_retention_days: int = 30

    @property
    def cors_origins_list(self) -> list[str]:
        if isinstance(self.cors_origins, str):
            try:
                return json.loads(self.cors_origins)
            except json.JSONDecodeError:
                return [o.strip() for o in self.cors_origins.split(",") if o.strip()]
        return list(self.cors_origins)

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
