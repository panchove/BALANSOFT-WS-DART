"""Servicio de pesaje: creación inline, cierre, anulación y estados del spec.

Estados (MODEL.md): PENDIENTE / CERRADO / MODIFICADO / ANULADO.
Número de boleto: secuencial {prefijo}XXXXXXX (default TA-), nunca se reutiliza.

Cálculos (MODEL.md):
- PTE = PEC + PER   (peso total entrada)
- PTS = PSC + PSR   (peso total salida)
- PNT = PTE - PTS   (peso neto total, firmado)
- PND = peso neto declarado (guía)
- PDF = PNT - PND   (diferencia, +/-)
- PDV = PDF / PND   (porcentaje de desviación)
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.license_client import LicenseInfo
from app.models import (
    Almacen,
    Balanza,
    BoletoPesaje,
    Camion,
    Conductor,
    Empresa,
    Kardex,
    Producto,
    Remolque,
    Tercero,
    Transporte,
)
from app.schemas import WeighingAnular, WeighingClose, WeighingCreate, WeighingUpdate
from app.services.audit_service import registrar

ZERO = Decimal("0.00")

# Mapa de normalización de estados legacy del cliente/offline
_ESTADO_LEGACY = {
    "ABIERTO": BoletoPesaje.ESTADO_PENDIENTE,
    "AUTOMATICO": BoletoPesaje.ESTADO_PENDIENTE,
    "AUTOMÁTICO": BoletoPesaje.ESTADO_PENDIENTE,
    "COMPLETADO": BoletoPesaje.ESTADO_CERRADO,
    "CERRADO": BoletoPesaje.ESTADO_CERRADO,
    "ANULADO": BoletoPesaje.ESTADO_ANULADO,
}

_ESTADOS_ABIERTOS = (BoletoPesaje.ESTADO_PENDIENTE, BoletoPesaje.ESTADO_MODIFICADO)


def normalizar_estado(estado: str | None) -> str:
    """Normaliza valores legacy (Abierto/Cerrado/Automático/COMPLETADO) a los del spec."""
    if not estado:
        return BoletoPesaje.ESTADO_PENDIENTE
    return _ESTADO_LEGACY.get(estado.strip().upper(), estado.strip().upper())


def _d(v: float | int | Decimal | None) -> Decimal | None:
    return Decimal(str(v)) if v is not None else None


def _fmt(v: Decimal, dec: int = 2) -> Decimal:
    return v.quantize(Decimal(f"1.{'0' * dec}"))


def _s(v: str | None) -> str | None:
    if v is None:
        return None
    v = v.strip()
    return v or None


class WeighingService:
    # ------------------------------------------------------------------
    # Auditoría
    # ------------------------------------------------------------------

    async def _auditar(
        self,
        db: AsyncSession,
        *,
        id_usuario: uuid.UUID | None,
        id_empresa: uuid.UUID,
        accion: str,
        entidad: str,
        entidad_id: str,
        detalle: dict[str, Any] | None = None,
        ip: str | None = None,
    ) -> None:
        await registrar(
            db,
            id_usuario=id_usuario,
            id_empresa=id_empresa,
            accion=accion,
            entidad=entidad,
            entidad_id=entidad_id,
            detalle=detalle,
            ip=ip,
        )

    # ------------------------------------------------------------------
    # Utilidades
    # ------------------------------------------------------------------

    async def generar_numero_boleto(self, db: AsyncSession) -> str:
        """Genera número de boleto secuencial (TA-00000001). Nunca se reutiliza."""
        rows = (await db.execute(select(BoletoPesaje.numero_boleto))).scalars().all()
        max_numero = 0
        for numero in rows:
            if numero and "-" in numero:
                try:
                    max_numero = max(max_numero, int(numero.rsplit("-", 1)[1]))
                except (ValueError, IndexError):
                    continue
        digitos = max(settings.boleto_digitos, len(str(max_numero + 1)))
        return f"{settings.boleto_prefix}{max_numero + 1:0{digitos}d}"

    async def _get_or_create(
        self,
        db: AsyncSession,
        empresa_id: uuid.UUID,
        model: type[Any],
        search_fields: dict[str, Any],
        create_fields: dict[str, Any],
    ) -> Any:
        """Creación inline genérica: obtiene el registro o lo crea si no existe."""
        stmt = select(model).where(*[getattr(model, k) == v for k, v in search_fields.items()])
        existing = (await db.execute(stmt)).scalar_one_or_none()
        if existing is not None:
            return existing
        obj = model(**create_fields)
        obj.id_empresa = empresa_id
        db.add(obj)
        await db.flush()
        return obj

    async def _resolver_catalogo(
        self,
        db: AsyncSession,
        empresa_id: uuid.UUID,
        *,
        id_value: str | uuid.UUID | None,
        name_value: str | None,
        model: type[Any],
        id_col: str,
        search_name_cols: list[str],
        create_name_col: str,
        extra_search: dict[str, Any] | None = None,
        extra_create: dict[str, Any] | None = None,
    ) -> str | uuid.UUID | None:
        """Resuelve el id de un catálogo: por id existente o por creación inline."""
        if id_value is not None:
            return id_value
        nombre = _s(name_value)
        if not nombre:
            return None
        search: dict[str, Any] = {"id_empresa": empresa_id}
        for col in search_name_cols:
            search[col] = nombre
        search.update(extra_search or {})
        create: dict[str, Any] = {create_name_col: nombre}
        create.update(extra_create or {})
        obj = await self._get_or_create(db, empresa_id, model, search, create)
        return getattr(obj, id_col)

    async def _resolver_vehiculo(self, db: AsyncSession, empresa_id: uuid.UUID, placa: str) -> str:
        """Creación inline del vehículo (camiones) por placa."""
        placa = placa.upper()
        stmt = select(Camion).where(
            Camion.id_empresa == empresa_id,
            func.upper(Camion.placa) == placa,
        )
        existing = (await db.execute(stmt)).scalar_one_or_none()
        if existing is not None:
            return existing.placa
        camion = Camion(placa=placa, id_empresa=empresa_id)
        db.add(camion)
        await db.flush()
        return placa

    async def _resolver_remolque(
        self,
        db: AsyncSession,
        empresa_id: uuid.UUID,
        *,
        id_remolque: uuid.UUID | None,
        placa: str | None,
    ) -> uuid.UUID | None:
        if id_remolque is not None:
            return id_remolque
        placa = _s(placa)
        if not placa:
            return None
        placa = placa.upper()
        stmt = select(Remolque).where(
            Remolque.id_empresa == empresa_id,
            func.upper(Remolque.placa) == placa,
        )
        existing = (await db.execute(stmt)).scalar_one_or_none()
        if existing is not None:
            return existing.id_remolque
        obj = Remolque(placa=placa, id_empresa=empresa_id)
        db.add(obj)
        await db.flush()
        return obj.id_remolque

    async def _resolver_conductor(
        self,
        db: AsyncSession,
        empresa_id: uuid.UUID,
        *,
        cedula: str | None,
        nombre: str | None,
    ) -> str | None:
        cedula = _s(cedula)
        nombre = _s(nombre)
        if cedula:
            return cedula
        if not nombre:
            return None
        stmt = select(Conductor).where(
            Conductor.id_empresa == empresa_id,
            func.upper(Conductor.nombre_completo) == nombre.upper(),
        )
        existing = (await db.execute(stmt)).scalar_one_or_none()
        if existing is not None:
            return existing.cedula_dni
        # Especificación: el conductor se identifica por cédula o nombre.
        # Sin cédula, usamos el nombre como identificador del registro.
        obj = Conductor(cedula_dni=nombre, nombre_completo=nombre, id_empresa=empresa_id)
        db.add(obj)
        await db.flush()
        return obj.cedula_dni

    # ------------------------------------------------------------------
    # Cálculos MODEL.md
    # ------------------------------------------------------------------

    def _calcular(
        self,
        peso_entrada_vehiculo: Decimal,
        peso_entrada_remolque: Decimal | None,
        peso_salida_vehiculo: Decimal | None,
        peso_salida_remolque: Decimal | None,
        peso_neto_declarado: Decimal | None = None,
    ) -> dict[str, Decimal | None]:
        """Cálculos firmados: PTE, PTS, PNT, PND, PDF, PDV (más bruto/tara legacy)."""
        pec = _fmt(peso_entrada_vehiculo or ZERO)
        per = _fmt(peso_entrada_remolque or ZERO)
        psc = _fmt(peso_salida_vehiculo or ZERO)
        psr = _fmt(peso_salida_remolque or ZERO)

        pte = _fmt(pec + per)
        pts = _fmt(psc + psr) if (peso_salida_vehiculo is not None or peso_salida_remolque is not None) else None
        if pts is None:
            # Entrada: solo PTE, aún sin salida
            pnd = _d(peso_neto_declarado)
            return {
                "peso_total_entrada": pte,
                "peso_total_salida": None,
                "peso_neto": None,
                "peso_neto_declarado": pnd,
                "peso_diferencia": None,
                "porcentaje_desviacion": None,
                "peso_bruto": pte,
                "peso_tara": None,
                "diferencia_peso": None,
                "porcentaje_diferencia": None,
            }
        pnt = _fmt(pte - pts)
        pnd = _d(peso_neto_declarado)
        pfd = _fmt(pnt - pnd) if pnd else None  # PDF = PNT - PND
        pdv = _fmt(pfd / pnd, 4) if pnd and pnd != 0 and pfd is not None else None
        bruto = max(pte, pts)
        tara = min(pte, pts)
        return {
            "peso_total_entrada": pte,
            "peso_total_salida": pts,
            "peso_neto": pnt,
            "peso_neto_declarado": pnd,
            "peso_diferencia": pfd,
            "porcentaje_desviacion": pdv,
            "peso_bruto": bruto,
            "peso_tara": tara,
            "diferencia_peso": pfd,
            "porcentaje_diferencia": pdv,
        }

    def _apply_litros(self, pesaje: BoletoPesaje, densidad: Decimal | None = None) -> None:
        if pesaje.peso_neto is not None:
            dens = densidad or pesaje.densidad
            if dens and dens != 0:
                pesaje.litros = _fmt(pesaje.peso_neto / dens)
            else:
                pesaje.litros = None

    async def _registrar_kardex(
        self,
        db: AsyncSession,
        pesaje: BoletoPesaje,
    ) -> None:
        """Genera movimiento de kardex al cerrar el boleto.

        - PNT >= 0 -> INGRESO POR BASCULA (ID 10, positivo)
        - PNT <  0 -> DESPACHO POR BASCULA (ID 60, negativo)
        Solo para productos marcados como ES_KARDEX.
        """
        if pesaje.peso_neto is None or not pesaje.id_producto:
            return
        producto = (
            await db.execute(
                select(Producto).where(Producto.id_producto == pesaje.id_producto)
            )
        ).scalar_one_or_none()
        if producto is None or not producto.es_kardex:
            return

        es_ingreso = pesaje.peso_neto >= 0
        kardex = Kardex(
            id_empresa=pesaje.id_empresa,
            id_movimiento=Kardex.KARDEX_INGRESO if es_ingreso else Kardex.KARDEX_DESPACHO,
            fecha_kardex=pesaje.fecha_hora_salida or pesaje.fecha_hora_entrada,
            id_producto=pesaje.id_producto,
            id_almacen=pesaje.id_almacen,
            fecha_documento=pesaje.fecha_hora_salida,
            documento=pesaje.documento,
            valor=abs(pesaje.peso_neto),
            boleto=pesaje.boleto,
        )
        db.add(kardex)

    async def _registrar_kardex_inverso(
        self, db: AsyncSession, pesaje: BoletoPesaje
    ) -> None:
        """Registra el movimiento inverso de kardex al anular un boleto cerrado.

        Cada asiento original se cancela con su opuesto (INGRESO 10 <-> DESPACHO 60)
        conservando la historia; no se eliminan registros (MODEL.md / ARCH.md).
        """
        movimientos = (
            (
                await db.execute(
                    select(Kardex).where(
                        Kardex.id_empresa == pesaje.id_empresa,
                        Kardex.boleto == pesaje.boleto,
                    )
                )
            )
            .scalars()
            .all()
        )
        for mov in movimientos:
            es_ingreso = mov.id_movimiento == Kardex.KARDEX_INGRESO
            db.add(
                Kardex(
                    id_empresa=pesaje.id_empresa,
                    id_movimiento=(
                        Kardex.KARDEX_DESPACHO if es_ingreso else Kardex.KARDEX_INGRESO
                    ),
                    fecha_kardex=mov.fecha_kardex,
                    id_producto=mov.id_producto,
                    id_almacen=mov.id_almacen,
                    fecha_documento=mov.fecha_documento,
                    documento=mov.documento,
                    valor=mov.valor,
                    boleto=pesaje.boleto,
                )
            )

    # ------------------------------------------------------------------
    # Límites de licencia
    # ------------------------------------------------------------------

    async def verificar_limite_demo(
        self, db: AsyncSession, empresa_id: uuid.UUID, licencia: LicenseInfo | None
    ) -> None:
        """Si la licencia es DEMO, limita a DEMO_MAX_RECORDS registros."""
        if licencia is None or not licencia.is_demo:
            return
        try:
            result = await db.execute(
                select(func.count())
                .select_from(BoletoPesaje)
                .where(BoletoPesaje.id_empresa == empresa_id)
            )
            total = result.scalar() or 0
            if total >= settings.demo_max_records:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"Límite de {settings.demo_max_records} registros DEMO excedido",
                )
        except HTTPException:
            raise
        except Exception:
            pass

    # ------------------------------------------------------------------
    # Operaciones
    # ------------------------------------------------------------------

    async def create(
        self,
        db: AsyncSession,
        empresa: Empresa,
        data: WeighingCreate,
        licencia: LicenseInfo | None = None,
        creado_por: str | None = None,
        *,
        id_usuario: uuid.UUID | None = None,
        ip: str | None = None,
    ) -> BoletoPesaje:
        await self.verificar_limite_demo(db, empresa.id_empresa, licencia)

        # Validación: un camión NO puede tener dos boletos PENDIENTE a la vez.
        placa = data.id_vehiculo.strip().upper()
        pendiente = (
            await db.execute(
                select(BoletoPesaje).where(
                    BoletoPesaje.id_empresa == empresa.id_empresa,
                    BoletoPesaje.id_vehiculo == placa,
                    BoletoPesaje.estado_boleto.in_(_ESTADOS_ABIERTOS),
                )
            )
        ).scalar_one_or_none()
        if pendiente is not None:
            raise HTTPException(
                status_code=400,
                detail=(
                    f"El vehículo {placa} ya tiene un boleto pendiente "
                    f"(N° {pendiente.numero_boleto or pendiente.boleto})."
                ),
            )

        # Creación inline del vehículo (camiones) por placa.
        await self._resolver_vehiculo(db, empresa.id_empresa, placa)

        id_remolque = await self._resolver_remolque(
            db, empresa.id_empresa, id_remolque=data.id_remolque, placa=data.remolque_placa
        )
        id_transporte = await self._resolver_catalogo(
            db, empresa.id_empresa,
            id_value=data.id_transporte,
            name_value=data.transporte_nombre,
            model=Transporte,
            id_col="id_transporte",
            search_name_cols=["razon_social"],
            create_name_col="razon_social",
        )
        id_conductor = await self._resolver_conductor(
            db, empresa.id_empresa,
            cedula=data.id_conductor or data.conductor_cedula,
            nombre=data.conductor_nombre,
        )
        id_producto = await self._resolver_catalogo(
            db, empresa.id_empresa,
            id_value=data.id_producto,
            name_value=data.producto_nombre,
            model=Producto,
            id_col="id_producto",
            search_name_cols=["nombre"],
            create_name_col="nombre",
        )
        id_almacen = await self._resolver_catalogo(
            db, empresa.id_empresa,
            id_value=data.id_almacen,
            name_value=data.almacen_nombre,
            model=Almacen,
            id_col="id_almacen",
            search_name_cols=["nombre"],
            create_name_col="nombre",
        )
        id_balanza = await self._resolver_catalogo(
            db, empresa.id_empresa,
            id_value=data.id_balanza,
            name_value=data.balanza_nombre,
            model=Balanza,
            id_col="id_balanza",
            search_name_cols=["descripcion"],
            create_name_col="descripcion",
        )
        tipo_tercero = (data.tipo_tercero or "CLIENTE").upper()
        id_tercero = await self._resolver_catalogo(
            db, empresa.id_empresa,
            id_value=data.id_tercero,
            name_value=data.tercero_nombre,
            model=Tercero,
            id_col="id_tercero",
            search_name_cols=["razon_social"],
            create_name_col="razon_social",
            extra_search={"tipo": tipo_tercero} if data.tercero_nombre else None,
            extra_create={"tipo": tipo_tercero} if data.tercero_nombre else None,
        )

        numero_boleto = await self.generar_numero_boleto(db)
        pesaje = BoletoPesaje(
            id_empresa=empresa.id_empresa,
            numero_boleto=numero_boleto,
            id_vehiculo=placa,
            remolque=data.remolque,
            id_remolque=id_remolque,
            id_transporte=id_transporte,
            id_conductor=id_conductor,
            id_producto=id_producto,
            id_almacen=id_almacen,
            id_balanza=id_balanza,
            tipo_tercero=tipo_tercero if data.id_tercero or data.tercero_nombre else None,
            id_tercero=id_tercero,
            multi_despacho_recepcion=data.multi_despacho_recepcion,
            fecha_hora_entrada=data.fecha_hora_entrada.replace(tzinfo=None),
            peso_entrada_vehiculo=_d(data.peso_entrada_vehiculo) or ZERO,
            peso_entrada_remolque=_d(data.peso_entrada_remolque),
            documento=data.documento,
            flete=data.flete,
            costo_flete=_d(data.costo_flete),
            observaciones=data.observaciones,
            estado_boleto=BoletoPesaje.ESTADO_PENDIENTE,
            creado_por=creado_por,
        )
        calculos = self._calcular(
            pesaje.peso_entrada_vehiculo,
            pesaje.peso_entrada_remolque,
            None,
            None,
        )
        for campo, valor in calculos.items():
            setattr(pesaje, campo, valor)
        db.add(pesaje)
        await db.flush()
        await self._auditar(
            db,
            id_usuario=id_usuario,
            id_empresa=empresa.id_empresa,
            accion="CREATE",
            entidad="boletos_pesaje",
            entidad_id=str(pesaje.boleto),
            detalle={
                "numero_boleto": pesaje.numero_boleto,
                "id_vehiculo": pesaje.id_vehiculo,
                "peso_entrada_vehiculo": float(pesaje.peso_entrada_vehiculo),
            },
            ip=ip,
        )
        await db.commit()
        await db.refresh(pesaje)
        return pesaje

    async def close(
        self,
        db: AsyncSession,
        empresa: Empresa,
        boleto: uuid.UUID,
        data: WeighingClose,
        salida_por: str | None = None,
        *,
        id_usuario: uuid.UUID | None = None,
        ip: str | None = None,
    ) -> BoletoPesaje:
        result = await db.execute(
            select(BoletoPesaje).where(
                BoletoPesaje.id_empresa == empresa.id_empresa, BoletoPesaje.boleto == boleto
            )
        )
        pesaje = result.scalar_one_or_none()
        if pesaje is None:
            raise HTTPException(status_code=404, detail="Boleto no encontrado.")

        estado = normalizar_estado(pesaje.estado_boleto)
        if estado == BoletoPesaje.ESTADO_CERRADO:
            raise HTTPException(status_code=400, detail="El boleto está en estado CERRADO.")
        if estado == BoletoPesaje.ESTADO_ANULADO:
            raise HTTPException(status_code=400, detail="Este boleto ya está anulado.")
        if pesaje.peso_salida_vehiculo is not None:
            raise HTTPException(status_code=400, detail="El boletilo ya registró la salida.")

        fecha_salida = data.fecha_hora_salida or datetime.now(UTC)
        pesaje.fecha_hora_salida = fecha_salida.replace(tzinfo=None)
        pesaje.peso_salida_vehiculo = _d(data.peso_salida_vehiculo)
        pesaje.peso_salida_remolque = _d(data.peso_salida_remolque)
        if data.densidad is not None:
            pesaje.densidad = _d(data.densidad)
        if data.unidades is not None:
            pesaje.unidades = _d(data.unidades)
        if data.observaciones is not None:
            pesaje.observaciones = data.observaciones
        if data.costo_flete is not None:
            pesaje.costo_flete = _d(data.costo_flete)

        calculos = self._calcular(
            pesaje.peso_entrada_vehiculo,
            pesaje.peso_entrada_remolque,
            pesaje.peso_salida_vehiculo,
            pesaje.peso_salida_remolque,
            peso_neto_declarado=_d(data.peso_neto_declarado),
        )
        for campo, valor in calculos.items():
            setattr(pesaje, campo, valor)
        self._apply_litros(pesaje, pesaje.densidad)
        pesaje.estado_boleto = BoletoPesaje.ESTADO_CERRADO
        pesaje.salida_por = salida_por
        pesaje.updated_at = datetime.now(UTC).replace(tzinfo=None)
        await self._registrar_kardex(db, pesaje)
        await self._auditar(
            db,
            id_usuario=id_usuario,
            id_empresa=empresa.id_empresa,
            accion="CLOSE",
            entidad="boletos_pesaje",
            entidad_id=str(pesaje.boleto),
            detalle={
                "numero_boleto": pesaje.numero_boleto,
                "peso_salida_vehiculo": float(pesaje.peso_salida_vehiculo or 0),
            },
            ip=ip,
        )
        await db.commit()
        await db.refresh(pesaje)
        return pesaje

    async def update(
        self,
        db: AsyncSession,
        empresa: Empresa,
        boleto: uuid.UUID,
        data: WeighingUpdate,
        modificado_por: str | None = None,
        *,
        id_usuario: uuid.UUID | None = None,
        ip: str | None = None,
    ) -> BoletoPesaje:
        result = await db.execute(
            select(BoletoPesaje).where(
                BoletoPesaje.id_empresa == empresa.id_empresa, BoletoPesaje.boleto == boleto
            )
        )
        pesaje = result.scalar_one_or_none()
        if pesaje is None:
            raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
        if normalizar_estado(pesaje.estado_boleto) == BoletoPesaje.ESTADO_ANULADO:
            raise HTTPException(status_code=400, detail="No se puede modificar un boleto anulado.")

        campos = data.model_dump(exclude_unset=True, exclude_none=True)
        if not campos:
            return pesaje
        for k, v in campos.items():
            setattr(pesaje, k, v)
        # Recalcular si cambió el peso declarado
        if "peso_neto_declarado" in campos and pesaje.peso_salida_vehiculo is not None:
            calculos = self._calcular(
                pesaje.peso_entrada_vehiculo,
                pesaje.peso_entrada_remolque,
                pesaje.peso_salida_vehiculo,
                pesaje.peso_salida_remolque,
                peso_neto_declarado=pesaje.peso_neto_declarado,
            )
            for campo, valor in calculos.items():
                setattr(pesaje, campo, valor)
        estado_previo = normalizar_estado(pesaje.estado_boleto)
        if estado_previo == BoletoPesaje.ESTADO_CERRADO:
            pesaje.estado_boleto = BoletoPesaje.ESTADO_MODIFICADO
        elif estado_previo == BoletoPesaje.ESTADO_PENDIENTE:
            pesaje.estado_boleto = BoletoPesaje.ESTADO_MODIFICADO
        pesaje.modificado_por = modificado_por
        pesaje.updated_at = datetime.now(UTC).replace(tzinfo=None)
        await self._auditar(
            db,
            id_usuario=id_usuario,
            id_empresa=empresa.id_empresa,
            accion="UPDATE",
            entidad="boletos_pesaje",
            entidad_id=str(pesaje.boleto),
            detalle={"campos_modificados": sorted(campos.keys())},
            ip=ip,
        )
        await db.commit()
        await db.refresh(pesaje)
        return pesaje

    async def anular(
        self,
        db: AsyncSession,
        empresa: Empresa,
        boleto: uuid.UUID,
        data: WeighingAnular,
        anulado_por: str | None = None,
        *,
        id_usuario: uuid.UUID | None = None,
        ip: str | None = None,
    ) -> BoletoPesaje:
        """Anula un boleto en cualquier estado. Motivo obligatorio.

        Si estaba PENDIENTE, libera el vehículo (ya no existe PENDIENTE).
        El número de boleto no se reutiliza y sus movimientos de kardex se
        cancelan con su inverso (10 <-> 60), sin eliminar la historia.
        """
        result = await db.execute(
            select(BoletoPesaje).where(
                BoletoPesaje.id_empresa == empresa.id_empresa, BoletoPesaje.boleto == boleto
            )
        )
        pesaje = result.scalar_one_or_none()
        if pesaje is None:
            raise HTTPException(status_code=404, detail="Boleto no encontrado.")

        if normalizar_estado(pesaje.estado_boleto) == BoletoPesaje.ESTADO_ANULADO:
            raise HTTPException(status_code=400, detail="Este boleto ya está anulado.")

        motivo = data.motivo.strip()
        if not motivo:
            raise HTTPException(status_code=422, detail="El motivo de anulación es obligatorio.")

        pesaje.estado_boleto = BoletoPesaje.ESTADO_ANULADO
        pesaje.motivo_anulacion = motivo
        pesaje.anulado_por = anulado_por
        obs = _s(pesaje.observaciones)
        pesaje.observaciones = (
            f"{obs}\n[ANULADO] Motivo: {motivo}".strip()
            if obs
            else f"[ANULADO] Motivo: {motivo}"
        )
        pesaje.updated_at = datetime.now(UTC).replace(tzinfo=None)
        await self._registrar_kardex_inverso(db, pesaje)
        await self._auditar(
            db,
            id_usuario=id_usuario,
            id_empresa=empresa.id_empresa,
            accion="ANULAR",
            entidad="boletos_pesaje",
            entidad_id=str(pesaje.boleto),
            detalle={
                "numero_boleto": pesaje.numero_boleto,
                "motivo": motivo,
            },
            ip=ip,
        )
        await db.commit()
        await db.refresh(pesaje)
        return pesaje

    async def pendientes(
        self,
        db: AsyncSession,
        empresa: Empresa,
        *,
        skip: int = 0,
        limit: int = 100,
    ) -> list[BoletoPesaje]:
        """Lista los boletos abiertos (PENDIENTE/MODIFICADO sin salida) en planta."""
        stmt = (
            select(BoletoPesaje)
            .where(
                BoletoPesaje.id_empresa == empresa.id_empresa,
                BoletoPesaje.estado_boleto.in_(_ESTADOS_ABIERTOS),
                BoletoPesaje.peso_salida_vehiculo.is_(None),
            )
            .order_by(BoletoPesaje.fecha_hora_entrada.desc())
            .offset(skip)
            .limit(limit)
        )
        rows = (await db.execute(stmt)).scalars().all()
        return list(rows)

    async def list(
        self,
        db: AsyncSession,
        empresa: Empresa,
        *,
        skip: int = 0,
        limit: int = 100,
        date_from: datetime | None = None,
        date_to: datetime | None = None,
        vehicle_id: str | None = None,
        estado: str | None = None,
    ) -> tuple[list[BoletoPesaje], int]:
        stmt = select(BoletoPesaje).where(BoletoPesaje.id_empresa == empresa.id_empresa)
        count_stmt = (
            select(func.count()).select_from(BoletoPesaje).where(
                BoletoPesaje.id_empresa == empresa.id_empresa
            )
        )
        if date_from is not None:
            stmt = stmt.where(BoletoPesaje.fecha_hora_entrada >= date_from)
            count_stmt = count_stmt.where(BoletoPesaje.fecha_hora_entrada >= date_from)
        if date_to is not None:
            stmt = stmt.where(BoletoPesaje.fecha_hora_entrada <= date_to)
            count_stmt = count_stmt.where(BoletoPesaje.fecha_hora_entrada <= date_to)
        if vehicle_id:
            stmt = stmt.where(BoletoPesaje.id_vehiculo == vehicle_id)
            count_stmt = count_stmt.where(BoletoPesaje.id_vehiculo == vehicle_id)
        if estado:
            estado_norm = normalizar_estado(estado)
            stmt = stmt.where(BoletoPesaje.estado_boleto == estado_norm)
            count_stmt = count_stmt.where(BoletoPesaje.estado_boleto == estado_norm)

        total = (await db.execute(count_stmt)).scalar() or 0
        stmt = stmt.order_by(BoletoPesaje.fecha_hora_entrada.desc()).offset(skip).limit(limit)
        rows = (await db.execute(stmt)).scalars().all()
        return list(rows), total