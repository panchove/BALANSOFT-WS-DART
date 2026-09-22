"""Modelos SQLAlchemy (asíncronos) de Balansoft-WS."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


def _uuid() -> uuid.UUID:
    return uuid.uuid4()


def _now_utc() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


class IdentidadLocal(Base):
    """Vínculo singleton con la cuenta del servidor (solo 1 fila por máquina).

    Guarda el id_cuenta y la licencia cacheados para trabajo offline
    (docs/MANEJO_DB.md §6.2 y §8). La PK booleana forzada a TRUE garantiza
    que solo exista una fila.
    """

    __tablename__ = "identidad_local"

    id: Mapped[bool] = mapped_column(Boolean, primary_key=True, default=True)
    id_cuenta: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    rif_nit: Mapped[str] = mapped_column(String(20))
    nombre_fiscal: Mapped[str] = mapped_column(String(255))
    nombre_comercial: Mapped[str | None] = mapped_column(String(255), nullable=True)
    licencia_key: Mapped[str | None] = mapped_column(String(255), nullable=True)
    licencia_tier: Mapped[str | None] = mapped_column(String(20), nullable=True)
    licencia_status: Mapped[str | None] = mapped_column(String(20), nullable=True)
    licencia_expira: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    hardware_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    rol_dispositivo: Mapped[str] = mapped_column(String(20), default="LOCAL")
    ultima_validacion: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    modo_offline: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )


class Empresa(Base):
    __tablename__ = "empresas"

    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    nombre_fiscal: Mapped[str] = mapped_column(String(255))
    nombre_comercial: Mapped[str | None] = mapped_column(String(255), nullable=True)
    rif_nit: Mapped[str] = mapped_column(String(20), unique=True)
    direccion: Mapped[str | None] = mapped_column(Text, nullable=True)
    telefono: Mapped[str | None] = mapped_column(String(50), nullable=True)
    email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    logo_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    formato_ticket: Mapped[str | None] = mapped_column(
        String(10), nullable=True, default="PDF", server_default="PDF"
    )
    ruta_exportacion_reportes: Mapped[str | None] = mapped_column(
        String(500), nullable=True
    )
    licencia_key: Mapped[str | None] = mapped_column(String(255), nullable=True)
    licencia_tier: Mapped[str | None] = mapped_column(String(20), nullable=True)
    licencia_status: Mapped[str | None] = mapped_column(String(20), nullable=True)
    licencia_expira: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    activa: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )

    usuarios: Mapped[list[Usuario]] = relationship(
        back_populates="empresa", cascade="all, delete-orphan"
    )


class Usuario(Base):
    __tablename__ = "usuarios"

    id_usuario: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    id_credencial: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    nombre: Mapped[str] = mapped_column(String(150))
    email: Mapped[str] = mapped_column(String(255), unique=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    rol: Mapped[str] = mapped_column(String(30), default="OPERADOR")
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )

    empresa: Mapped[Empresa] = relationship(back_populates="usuarios")


# ---------------------------------------------------------------------------
# Catálogos
# ---------------------------------------------------------------------------


class Marca(Base):
    __tablename__ = "marcas"

    id_marca: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    nombre: Mapped[str] = mapped_column(String(100))
    logo_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )


class ModeloCamion(Base):
    __tablename__ = "modelos_camion"

    id_modelo_camion: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    marca_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("marcas.id_marca"), nullable=True
    )
    nombre: Mapped[str] = mapped_column(String(100))
    capacidad_carga_ton: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    foto_referencial_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    ejes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )


class Camion(Base):
    __tablename__ = "camiones"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    placa: Mapped[str] = mapped_column(String(20))
    modelo_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("modelos_camion.id_modelo_camion"), nullable=True
    )
    transporte_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("transportes.id_transporte"), nullable=True
    )
    color: Mapped[str | None] = mapped_column(String(50), nullable=True)
    foto_real_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    tara_habitual: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )


class Remolque(Base):
    __tablename__ = "remolques"

    id_remolque: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    placa: Mapped[str] = mapped_column(String(20))
    tipo_remolque: Mapped[str | None] = mapped_column(String(100), nullable=True)
    tara_habitual: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    foto_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )


class Transporte(Base):
    __tablename__ = "transportes"

    id_transporte: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    codigo: Mapped[str | None] = mapped_column(String(20), nullable=True)
    razon_social: Mapped[str] = mapped_column(String(150))
    identificacion_fiscal: Mapped[str | None] = mapped_column(String(20), nullable=True)
    telefono: Mapped[str | None] = mapped_column(String(50), nullable=True)
    contacto: Mapped[str | None] = mapped_column(String(150), nullable=True)
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )


class Conductor(Base):
    __tablename__ = "conductores"

    cedula_dni: Mapped[str] = mapped_column(String(20), primary_key=True)
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    nombre_completo: Mapped[str] = mapped_column(String(200))
    telefono: Mapped[str | None] = mapped_column(String(50), nullable=True)
    licencia_conducir: Mapped[str | None] = mapped_column(String(50), nullable=True)
    foto_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )


class Categoria(Base):
    __tablename__ = "categorias"

    id_categoria: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    codigo: Mapped[str | None] = mapped_column(String(50), nullable=True)
    nombre: Mapped[str] = mapped_column(String(150))
    descripcion: Mapped[str | None] = mapped_column(String(200), nullable=True)
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )


class Producto(Base):
    __tablename__ = "productos"

    id_producto: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    id_categoria: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("categorias.id_categoria")
    )
    codigo: Mapped[str | None] = mapped_column(String(50), nullable=True)
    nombre: Mapped[str] = mapped_column(String(150))
    descripcion: Mapped[str | None] = mapped_column(String(200), nullable=True)
    densidad_estandar: Mapped[Decimal | None] = mapped_column(Numeric(8, 4), nullable=True)
    unidad_medida: Mapped[str] = mapped_column(String(20), default="TON")
    # Maestra de productos (MODEL.md): denominacion, es_kardex, medida, densidad,
    # tolerancia (%), peso_unidad.
    es_kardex: Mapped[bool] = mapped_column(Boolean, default=False)
    tolerancia: Mapped[Decimal | None] = mapped_column(Numeric(8, 4), nullable=True)
    peso_unidad: Mapped[Decimal | None] = mapped_column(Numeric(12, 4), nullable=True)
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )


class Almacen(Base):
    __tablename__ = "almacenes"

    id_almacen: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    codigo: Mapped[str | None] = mapped_column(String(20), nullable=True)
    nombre: Mapped[str] = mapped_column(String(150))
    ubicacion: Mapped[str | None] = mapped_column(String(255), nullable=True)
    capacidad_max_ton: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    stock_actual_ton: Mapped[Decimal] = mapped_column(
        Numeric(12, 2), default=Decimal("0.00"), nullable=False
    )
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )


class Balanza(Base):
    __tablename__ = "balanzas"

    id_balanza: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    codigo: Mapped[str | None] = mapped_column(String(20), nullable=True)
    descripcion: Mapped[str] = mapped_column(String(150))
    marca: Mapped[str | None] = mapped_column(String(100), nullable=True)
    modelo: Mapped[str | None] = mapped_column(String(100), nullable=True)
    capacidad_max: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    division: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    is_simulada: Mapped[bool] = mapped_column(Boolean, default=False)
    puerto_com: Mapped[str | None] = mapped_column(String(50), nullable=True)
    ip_address: Mapped[str | None] = mapped_column(String(45), nullable=True)
    puerto_tcp: Mapped[int | None] = mapped_column(Integer, nullable=True)
    protocolo: Mapped[str | None] = mapped_column(String(20), default="tcp")
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )


class Tercero(Base):
    __tablename__ = "terceros"

    id_tercero: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    codigo: Mapped[str | None] = mapped_column(String(20), nullable=True)
    tipo: Mapped[str] = mapped_column(String(30))
    razon_social: Mapped[str] = mapped_column(String(200))
    identificacion_fiscal: Mapped[str | None] = mapped_column(String(20), nullable=True)
    direccion: Mapped[str | None] = mapped_column(Text, nullable=True)
    telefono: Mapped[str | None] = mapped_column(String(50), nullable=True)
    email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )


# ---------------------------------------------------------------------------
# Pesaje
# ---------------------------------------------------------------------------


class SerieNumeracion(Base):
    """Modelo de numeración de documentos de una empresa (1..N por empresa).

    La estación selecciona (desde el campo de trabajo) CUÁL serie usa cada
    boleto; `activa` marca la que se usa por defecto. El contador `siguiente`
    se avanza con ``FOR UPDATE`` al emitir el número (sin carreras y sin
    reutilización). Modelado según fichas 015 y el patrón FOR UPDATE de
    ``weighing_service._generar_numero``.
    """

    __tablename__ = "series_numeracion"

    id_serie: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa"), nullable=False
    )
    nombre: Mapped[str] = mapped_column(String(80))
    prefijo: Mapped[str] = mapped_column(String(20))
    inicio: Mapped[int] = mapped_column(Integer, default=1)
    siguiente: Mapped[int] = mapped_column(Integer)
    digitos: Mapped[int] = mapped_column(Integer, default=8)
    activa: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        server_default=func.now(),
        default=lambda: _now_utc(),
        onupdate=lambda: _now_utc(),
    )


class BoletoPesaje(Base):
    __tablename__ = "boletos_pesaje"

    # Estados del spec MODEL.md: PENDIENTE / CERRADO / MODIFICADO / ANULADO.
    # COMPLETADO se conserva como alias legacy (normalizado a CERRADO).
    ESTADO_PENDIENTE = "PENDIENTE"
    ESTADO_CERRADO = "CERRADO"
    ESTADO_MODIFICADO = "MODIFICADO"
    ESTADO_ANULADO = "ANULADO"
    ESTADO_COMPLETADO = "CERRADO"  # alias legacy

    boleto: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    numero_boleto: Mapped[str | None] = mapped_column(String(30), unique=True, nullable=True)
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    id_serie: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("series_numeracion.id_serie"), nullable=True
    )
    id_vehiculo: Mapped[str | None] = mapped_column(String(20), nullable=True)
    remolque: Mapped[bool] = mapped_column(Boolean, default=False)
    id_remolque: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("remolques.id_remolque"), nullable=True
    )
    id_transporte: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("transportes.id_transporte"), nullable=True
    )
    id_conductor: Mapped[str | None] = mapped_column(
        String(20), ForeignKey("conductores.cedula_dni"), nullable=True
    )
    id_producto: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("productos.id_producto"), nullable=True
    )
    id_almacen: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("almacenes.id_almacen"), nullable=True
    )
    id_balanza: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("balanzas.id_balanza"), nullable=True
    )
    tipo_tercero: Mapped[str | None] = mapped_column(String(30), nullable=True)
    id_tercero: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("terceros.id_tercero"), nullable=True
    )
    multi_despacho_recepcion: Mapped[bool] = mapped_column(Boolean, default=False)

    fecha_hora_entrada: Mapped[datetime] = mapped_column(DateTime)
    peso_entrada_vehiculo: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    peso_entrada_remolque: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    foto_entrada_url: Mapped[str | None] = mapped_column(Text, nullable=True)

    fecha_hora_salida: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    peso_salida_vehiculo: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    peso_salida_remolque: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    foto_salida_url: Mapped[str | None] = mapped_column(Text, nullable=True)

    documento: Mapped[str | None] = mapped_column(String(100), nullable=True)
    flete: Mapped[str | None] = mapped_column(String(100), nullable=True)
    costo_flete: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    observaciones: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Auditoría de operativas (MODEL.md): id usuario responsable de cada operación
    creado_por: Mapped[str | None] = mapped_column(String(150), nullable=True)
    salida_por: Mapped[str | None] = mapped_column(String(150), nullable=True)
    modificado_por: Mapped[str | None] = mapped_column(String(150), nullable=True)
    anulado_por: Mapped[str | None] = mapped_column(String(150), nullable=True)
    motivo_anulacion: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Cálculos MODEL.md (firmados): PTE = PEC+PER, PTS = PSC+PSR, PNT = PTE-PTS,
    # PND = peso declarado (guía), PDF = PNT-PND, PDV = PDF/PND (%)
    peso_total_entrada: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    peso_total_salida: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    peso_neto: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    peso_neto_declarado: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    peso_diferencia: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    porcentaje_desviacion: Mapped[Decimal | None] = mapped_column(Numeric(8, 4), nullable=True)
    # Campos legacy (bruto/tara/diferencia) mantenidos por compatibilidad
    peso_bruto: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    peso_tara: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    diferencia_peso: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    porcentaje_diferencia: Mapped[Decimal | None] = mapped_column(Numeric(8, 4), nullable=True)
    densidad: Mapped[Decimal | None] = mapped_column(Numeric(8, 4), nullable=True)
    litros: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    unidades: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)

    estado_boleto: Mapped[str] = mapped_column(String(20), default="PENDIENTE")
    sincronizado: Mapped[bool] = mapped_column(Boolean, default=False)
    sync_intentos: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )


# ---------------------------------------------------------------------------
# Sincronización
# ---------------------------------------------------------------------------


class SyncQueue(Base):
    __tablename__ = "sync_queue"

    id_sync: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    entidad: Mapped[str] = mapped_column(String(50))
    operacion: Mapped[str] = mapped_column(String(20))
    entidad_id: Mapped[str] = mapped_column(String(100))
    payload: Mapped[dict] = mapped_column(JSONB, default=dict)
    pendiente: Mapped[bool] = mapped_column(Boolean, default=True)
    intentos: Mapped[int] = mapped_column(Integer, default=0)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )


class SyncLog(Base):
    __tablename__ = "sync_logs"

    id_log: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    id_empresa: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    tipo: Mapped[str] = mapped_column(String(30))
    entidad: Mapped[str | None] = mapped_column(String(50), nullable=True)
    registros: Mapped[int] = mapped_column(Integer, default=0)
    errores: Mapped[int] = mapped_column(Integer, default=0)
    detalle: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )


# ---------------------------------------------------------------------------
# Auditoría
# ---------------------------------------------------------------------------


class Auditoria(Base):
    __tablename__ = "auditoria"

    id_auditoria: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_usuario: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("usuarios.id_usuario"), nullable=True
    )
    id_empresa: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    accion: Mapped[str] = mapped_column(String(100))
    entidad: Mapped[str | None] = mapped_column(String(50), nullable=True)
    entidad_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    detalle: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    ip: Mapped[str | None] = mapped_column(String(50), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )


class PasswordResetToken(Base):
    """Token único de recuperación de contraseña (solo se guarda su hash SHA-256)."""

    __tablename__ = "password_reset_tokens"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    id_usuario: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("usuarios.id_usuario", ondelete="CASCADE")
    )
    token_hash: Mapped[str] = mapped_column(String(128))
    expira: Mapped[datetime] = mapped_column(DateTime)
    usado: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )


class LogSistema(Base):
    __tablename__ = "logs_sistema"

    id_log: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    nivel: Mapped[str] = mapped_column(String(10))
    modulo: Mapped[str | None] = mapped_column(String(50), nullable=True)
    mensaje: Mapped[str] = mapped_column(Text)
    detalle: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )


# ---------------------------------------------------------------------------
# Imágenes de Pesaje
# ---------------------------------------------------------------------------


class ImagenPesaje(Base):
    __tablename__ = "imagenes_pesaje"

    id_imagen: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    boleto: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("boletos_pesaje.boleto", ondelete="CASCADE")
    )
    tipo: Mapped[str] = mapped_column(String(30))
    url: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )


# ---------------------------------------------------------------------------
# Kardex (MODEL.md)
# ---------------------------------------------------------------------------


class Kardex(Base):
    """Registro de kardex por báscula.

    ID de movimiento: 10 = INGRESO POR BASCULA (positivo),
    60 = DESPACHO POR BASCULA (negativo). Los ANULADOS no participan.
    """

    __tablename__ = "kardex"

    KARDEX_INGRESO = 10
    KARDEX_DESPACHO = 60
    # Rango positivo 01-49, rango negativo 50-99 (MODEL.md)
    RANGO_NEGATIVO_DESDE = 50

    id_kardex: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=_uuid
    )
    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa")
    )
    id_movimiento: Mapped[int] = mapped_column(Integer)
    fecha_kardex: Mapped[datetime] = mapped_column(DateTime)
    id_producto: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("productos.id_producto"), nullable=True
    )
    id_almacen: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("almacenes.id_almacen"), nullable=True
    )
    fecha_documento: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    documento: Mapped[str | None] = mapped_column(String(100), nullable=True)
    valor: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    boleto: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("boletos_pesaje.boleto"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc()
    )


# ---------------------------------------------------------------------------
# Seguridad y Accesos: matriz rol → módulo
# ---------------------------------------------------------------------------


class PermisoAcceso(Base):
    """Acceso de un rol a un módulo de la estación.

    `acceso` admite: ``ver`` (solo lectura), ``editar`` (lectura y escritura),
    ``ninguno`` (oculto). La matriz por defecto vive en
    ``app/core/seguridad_matrix.py``.
    """

    __tablename__ = "permisos_acceso"

    id_empresa: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("empresas.id_empresa"), primary_key=True
    )
    rol: Mapped[str] = mapped_column(String(30), primary_key=True)
    modulo: Mapped[str] = mapped_column(String(50), primary_key=True)
    acceso: Mapped[str] = mapped_column(String(20), default="ver")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), default=lambda: _now_utc(), onupdate=lambda: _now_utc()
    )
