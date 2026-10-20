"""Módulo llave_activacion.

Versión: 0.4.2-dev.56
Fecha: 2026-10-19
Estado: Vigente
Norma: ISO/IEC 27001 / ISO/IEC 25010
Fuente: Sistema BALANSOFT-WS
Autor: Lead Architect
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import TIMESTAMP, ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from . import Base


def _uuid() -> uuid.UUID:
    return uuid.uuid4()


def _now_utc() -> datetime:
    """UTC naive: convención de los ``TIMESTAMP`` del proyecto (ver datetime_utils)."""
    return datetime.now(UTC).replace(tzinfo=None)


class LlaveActivacion(Base):
    """Llaves de activación de un solo uso para estaciones OPERADOR.

    El código se guarda **hasheado** (SHA-256) y se muestra en claro una sola
    vez al emitirlo. Una misma llave no puede canjearse dos veces; el canje
    registra el equipo (``consumida_por_hw``) y deja constancia de auditoría.
    """

    __tablename__ = "llaves_activacion"

    ESTADO_ACTIVA = "activa"
    ESTADO_CONSUMIDA = "consumida"
    ESTADO_REVOCADA = "revocada"

    id: Mapped[uuid.UUID] = mapped_column(
        "id", UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa", ondelete="CASCADE")
    )
    id_usuario: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("usuarios.id_usuario", ondelete="CASCADE")
    )
    codigo_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    codigo_preview: Mapped[str | None] = mapped_column(String(40), nullable=True)
    estado: Mapped[str] = mapped_column(String(20), nullable=False, default="activa")
    expira_en: Mapped[datetime | None] = mapped_column(TIMESTAMP, nullable=True)
    consumida_en: Mapped[datetime | None] = mapped_column(TIMESTAMP, nullable=True)
    consumida_por_hw: Mapped[str | None] = mapped_column(String(255), nullable=True)
    ip_consumo: Mapped[str | None] = mapped_column(String(45), nullable=True)
    user_agent: Mapped[str | None] = mapped_column(String(255), nullable=True)
    creado_por: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("usuarios.id_usuario"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP, nullable=False, default=_now_utc
    )
    updated_at: Mapped[datetime] = mapped_column(
        TIMESTAMP, nullable=False, default=_now_utc
    )

    __table_args__ = (UniqueConstraint("codigo_hash", name="uq_llaves_codigo_hash"),)