"""Modelos SQLAlchemy de la DB del SERVIDOR (cuenta y licencia).

Arquitectura de dos BDs (docs/MANEJO_DB.md): esta base SOLO contiene
información de la cuenta, licencia, credenciales globales y sincronización.
NO contiene datos operativos del cliente (esos viven en la DB local).

Usan declarative base propia (ServerBase) con metadata independiente de
``app.models.Base`` para que los tests de la estación local no se vean
afectados por tablas del servidor.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class ServerBase(DeclarativeBase):
    pass


def _uuid() -> uuid.UUID:
    return uuid.uuid4()


def _now_utc() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


class Cuenta(ServerBase):
    """Empresas registradas por el proveedor."""

    __tablename__ = "cuentas"

    id_cuenta: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    rif_nit: Mapped[str] = mapped_column(String(20), unique=True)
    nombre_fiscal: Mapped[str] = mapped_column(String(255))
    nombre_comercial: Mapped[str | None] = mapped_column(String(255), nullable=True)
    email_admin: Mapped[str] = mapped_column(String(255), unique=True)
    telefono: Mapped[str | None] = mapped_column(String(50), nullable=True)
    direccion: Mapped[str | None] = mapped_column(Text, nullable=True)
    activa: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now_utc)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=_now_utc, onupdate=_now_utc
    )

    licencias: Mapped[list[Licencia]] = relationship(
        back_populates="cuenta", cascade="all, delete-orphan"
    )


class Licencia(ServerBase):
    """Licencias gestionadas por el proveedor."""

    __tablename__ = "licencias"

    id_licencia: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_cuenta: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("cuentas.id_cuenta", ondelete="CASCADE")
    )
    licencia_key: Mapped[str] = mapped_column(String(255), unique=True)
    licencia_tier: Mapped[str] = mapped_column(String(20))
    licencia_status: Mapped[str] = mapped_column(String(20), default="ACTIVA")
    fecha_emision: Mapped[datetime] = mapped_column(DateTime, default=_now_utc)
    fecha_expira: Mapped[datetime] = mapped_column(DateTime)
    max_usuarios: Mapped[int | None] = mapped_column(Integer, nullable=True)
    max_equipos: Mapped[int | None] = mapped_column(Integer, nullable=True)
    max_sesiones: Mapped[int | None] = mapped_column(Integer, nullable=True)
    hardware_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    notas: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now_utc)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=_now_utc, onupdate=_now_utc
    )

    cuenta: Mapped[Cuenta] = relationship(back_populates="licencias")


class Dispositivo(ServerBase):
    """Máquinas locales autorizadas a sincronizar con la cuenta."""

    __tablename__ = "dispositivos"

    id_dispositivo: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_cuenta: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("cuentas.id_cuenta", ondelete="CASCADE")
    )
    id_licencia: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("licencias.id_licencia"), nullable=True
    )
    hardware_id: Mapped[str] = mapped_column(String(255), unique=True)
    nombre_equipo: Mapped[str | None] = mapped_column(String(150), nullable=True)
    sistema_operativo: Mapped[str | None] = mapped_column(String(100), nullable=True)
    version_app: Mapped[str | None] = mapped_column(String(50), nullable=True)
    rol_dispositivo: Mapped[str] = mapped_column(String(20), default="LOCAL")
    ip_local: Mapped[str | None] = mapped_column(String(45), nullable=True)
    ultima_conexion: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now_utc)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=_now_utc, onupdate=_now_utc
    )


class Credencial(ServerBase):
    """Credencial global para login desde cualquier equipo.

    Solo se guarda lo mínimo: email + hash + cuenta + rol global.
    Los roles operativos viven en la DB local.
    """

    __tablename__ = "credenciales"

    id_credencial: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_cuenta: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("cuentas.id_cuenta", ondelete="CASCADE")
    )
    email: Mapped[str] = mapped_column(String(255), unique=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    rol_global: Mapped[str] = mapped_column(String(30), default="OPERADOR")
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    ultimo_login: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now_utc)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=_now_utc, onupdate=_now_utc
    )

    cuenta: Mapped[Cuenta] = relationship()


class Sesion(ServerBase):
    """Tokens JWT emitidos por el servidor."""

    __tablename__ = "sesiones"

    id_sesion: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_credencial: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("credenciales.id_credencial", ondelete="CASCADE")
    )
    id_dispositivo: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("dispositivos.id_dispositivo"), nullable=True
    )
    token_hash: Mapped[str] = mapped_column(String(128))
    expira: Mapped[datetime] = mapped_column(DateTime)
    revocada: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now_utc)


class SyncSesion(ServerBase):
    """Sincronización orquestada desde el servidor."""

    __tablename__ = "sync_sesiones"

    id_sync: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_cuenta: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("cuentas.id_cuenta")
    )
    id_dispositivo: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("dispositivos.id_dispositivo")
    )
    tipo: Mapped[str] = mapped_column(String(20))
    estado: Mapped[str] = mapped_column(String(20), default="PENDIENTE")
    registros_subidos: Mapped[int] = mapped_column(Integer, default=0)
    registros_bajados: Mapped[int] = mapped_column(Integer, default=0)
    errores: Mapped[int] = mapped_column(Integer, default=0)
    detalle: Mapped[str | None] = mapped_column(Text, nullable=True)
    iniciado: Mapped[datetime] = mapped_column(DateTime, default=_now_utc)
    finalizado: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class SyncColaItem(ServerBase):
    """Cola de sincronización del servidor (entidades recibidas de estaciones)."""

    __tablename__ = "sync_cola"

    id_cola: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_cuenta: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("cuentas.id_cuenta")
    )
    id_dispositivo: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("dispositivos.id_dispositivo")
    )
    entidad: Mapped[str] = mapped_column(String(50))
    operacion: Mapped[str] = mapped_column(String(20))
    entidad_id: Mapped[str] = mapped_column(String(100))
    payload: Mapped[dict] = mapped_column(JSONB)
    pendiente: Mapped[bool] = mapped_column(Boolean, default=True)
    intentos: Mapped[int] = mapped_column(Integer, default=0)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now_utc)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=_now_utc, onupdate=_now_utc
    )


class AuditoriaServidor(ServerBase):
    """Eventos de cuenta/licencia del servidor."""

    __tablename__ = "auditoria_servidor"

    id_auditoria: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_cuenta: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("cuentas.id_cuenta"), nullable=True
    )
    id_credencial: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("credenciales.id_credencial"), nullable=True
    )
    accion: Mapped[str] = mapped_column(String(100))
    entidad: Mapped[str | None] = mapped_column(String(50), nullable=True)
    entidad_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    detalle: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    ip: Mapped[str | None] = mapped_column(String(50), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now_utc)


class PasswordResetToken(ServerBase):
    """Recuperación de contraseña global."""

    __tablename__ = "password_reset_tokens"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_credencial: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("credenciales.id_credencial", ondelete="CASCADE")
    )
    token_hash: Mapped[str] = mapped_column(String(128))
    expira: Mapped[datetime] = mapped_column(DateTime)
    usado: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now_utc)


class ProveedorUsuario(ServerBase):
    """Usuarios del panel del proveedor (gestión interna)."""

    __tablename__ = "proveedores_usuarios"

    id_usuario: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    email: Mapped[str] = mapped_column(String(255), unique=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    nombre: Mapped[str] = mapped_column(String(150))
    rol: Mapped[str] = mapped_column(String(30), default="SOPORTE")
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now_utc)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=_now_utc, onupdate=_now_utc
    )