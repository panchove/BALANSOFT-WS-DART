"""Rutas de pesaje (weighing).

Reglas de negocio críticas:
- Creación inline (get-or-create) para vehículo, remolque, transporte, conductor,
  producto, almacén, balanza y tercero.
- Un camión no puede tener dos boletos PENDIENTE a la vez (400).
- Pesaje manual solo para roles ADMIN / SUPERVISOR (403).
- Anulación con motivo obligatorio; libera el vehículo si estaba PENDIENTE.
- Número de boleto secuencial (prefijo configurable) que nunca se reutiliza.

Versión: 0.4.2-dev.56
Fecha: 2026-10-19
Estado: Vigente
Norma: ISO/IEC 17025 / OIML R 76-1 / ISO/IEC 25010
Fuente: Sistema BALANSOFT-WS
Autor: Lead Architect
"""

from __future__ import annotations

import asyncio
import logging
import os
import uuid
from datetime import UTC, datetime

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    Request,
    Response,
    UploadFile,
)
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import func, or_, select, true
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user
from app.core.config import settings
from app.core.database import get_db
from app.core.hardware import obtener_hardware_id
from app.core.i18n import resolve_lang
from app.core.license_client import LicenseInfo, get_license_client
from app.core.monitoring import inc_pesaje_anulado, inc_pesaje_cerrado, inc_pesaje_creado
from app.core.scale_session import get_scale_session_manager
from app.models import (
    Almacen,
    Balanza,
    BoletoPesaje,
    Camion,
    Categoria,
    Conductor,
    Empresa,
    IdentidadLocal,
    ImagenPesaje,
    Kardex,
    Producto,
    Remolque,
    Tercero,
    Transporte,
    Usuario,
)
from app.schemas import (
    BoletoEdicionOut,
    WeighingAnular,
    WeighingClose,
    WeighingCreate,
    WeighingOut,
    WeighingUpdate,
)
from app.services.ticket_service import generar_ticket_pdf, generar_ticket_txt
from app.services.weighing_service import WeighingService

router = APIRouter(prefix="/api/v1/weighing", tags=["Weighing"])

log = logging.getLogger(__name__)

_SERVICE = WeighingService()

_PERMISOS_PESO_MANUAL = {"ADMIN", "SUPERVISOR"}
_PERMISOS_ANULACION = {"ADMIN", "SUPERVISOR"}


def _es_admin(user: Usuario) -> bool:
    """Solo el ADMIN de la cuenta queda exento del tope de ediciones (RB edición)."""
    return getattr(user, "rol", None) == "ADMIN"


def _verificar_peso_manual(es_manual: bool, user: Usuario) -> None:
    """Solo SUPERVISOR/ADMIN pueden registrar pesos manualmente."""
    if es_manual and user.rol not in _PERMISOS_PESO_MANUAL:
        raise HTTPException(
            status_code=403,
            detail="No tiene permisos para registrar pesajes en modo manual.",
        )


def _verificar_anulacion(user: Usuario) -> None:
    """Solo SUPERVISOR/ADMIN pueden anular boletos."""
    if user.rol not in _PERMISOS_ANULACION:
        raise HTTPException(
            status_code=403,
            detail="No tiene permisos para anular boletos.",
        )


def _resolve_to_weighing_out(p: BoletoPesaje) -> WeighingOut:
    return WeighingOut.model_validate(p)


async def _enriquecer_pesajes_lista(
    db: AsyncSession, pesajes: list[BoletoPesaje]
) -> list[BoletoPesaje]:
    """Resuelve los nombres legibles de una página de boletos con 7 consultas.

    `_enriquecer_pesaje_ticket` está pensado para **un** boleto (impresión,
    PDF, cierre) y lanza hasta 10 consultas por registro. Reutilizarlo en
    `/list` y `/pendientes` convertía una página de 100 boletos en ~1000
    idas y vueltas a PostgreSQL: medido con 50k boletos, el endpoint se iba a
    ~450 ms p50 solo por eso, y con fila por fila el costo escala con el
    `limit` en vez de con la página.

    Aquí se resuelven **una vez por página** y solo los 7 campos que
    `WeighingOut` serializa (el resto —kardex, color, categoría, tara— es
    exclusivo del ticket AVANZADO y no se pierde: `_enriquecer_pesaje_ticket`
    sigue siendo el camino de los endpoints de un solo boleto).

    Todos los catálogos se filtran por `id_empresa`: el tenant lo decide el
    contexto autenticado, nunca el cliente.
    """
    if not pesajes:
        return pesajes

    id_empresa = pesajes[0].id_empresa

    async def _por_id(model, columna, valores):
        """Mapea `valor -> entidad` con una sola consulta (`IN (...)`)."""
        if not valores:
            return {}
        filas = (
            (
                await db.execute(
                    select(model).where(
                        columna.in_(valores), model.id_empresa == id_empresa
                    )
                )
            )
            .scalars()
            .all()
        )
        return {getattr(f, columna.key): f for f in filas}  # type: ignore[attr-defined]

    productos = await _por_id(
        Producto, Producto.id_producto, {p.id_producto for p in pesajes if p.id_producto}
    )
    conductores = await _por_id(
        Conductor, Conductor.cedula_dni, {p.id_conductor for p in pesajes if p.id_conductor}
    )
    transportes = await _por_id(
        Transporte, Transporte.id_transporte,
        {p.id_transporte for p in pesajes if p.id_transporte},
    )
    almacenes = await _por_id(
        Almacen, Almacen.id_almacen, {p.id_almacen for p in pesajes if p.id_almacen}
    )
    balanzas = await _por_id(
        Balanza, Balanza.id_balanza, {p.id_balanza for p in pesajes if p.id_balanza}
    )
    terceros = await _por_id(
        Tercero, Tercero.id_tercero, {p.id_tercero for p in pesajes if p.id_tercero}
    )
    remolques = await _por_id(
        Remolque, Remolque.id_remolque, {p.id_remolque for p in pesajes if p.id_remolque}
    )

    for p in pesajes:
        prod = productos.get(p.id_producto)
        if prod is not None:
            p.producto_nombre = prod.nombre  # type: ignore[attr-defined]
        cond = conductores.get(p.id_conductor)
        if cond is not None:
            nom = (cond.nombre_completo or "").strip()
            p.conductor_nombre = f"{nom} ({cond.cedula_dni})" if nom else cond.cedula_dni  # type: ignore[attr-defined]
        trans = transportes.get(p.id_transporte)
        if trans is not None:
            p.transporte_nombre = trans.razon_social  # type: ignore[attr-defined]
        alm = almacenes.get(p.id_almacen)
        if alm is not None:
            p.almacen_nombre = alm.nombre  # type: ignore[attr-defined]
        bal = balanzas.get(p.id_balanza)
        if bal is not None:
            p.balanza_nombre = bal.descripcion  # type: ignore[attr-defined]
        terc = terceros.get(p.id_tercero)
        if terc is not None:
            p.tercero_nombre = terc.razon_social  # type: ignore[attr-defined]
        rem = remolques.get(p.id_remolque)
        if rem is not None:
            p.remolque_placa = rem.placa  # type: ignore[attr-defined]
    return pesajes


@router.post("/create", response_model=WeighingOut)
async def create_weighing(
    payload: WeighingCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> WeighingOut:
    """Registra un nuevo pesaje de entrada o salida en la estación.
    
    Args:
        payload: Datos del pesaje (vehículo, placa, pesos, producto, conductor, guía).
        request: Objeto de solicitud HTTP para capturar la dirección IP.
        current_user: Usuario autenticado que realiza el pesaje.
        empresa: Empresa asociada al pesaje (contexto multi-tenant).
        db: Sesión de base de datos asíncrona inyectada por FastAPI.
    
    Returns:
        WeighingOut: Objeto del pesaje creado en estado PENDIENTE.
    
    Raises:
        HTTPException 400: Si el peso viola invariantes metrológicas 
            (bruto < tara, peso negativo, sobrecapacidad > 105%).
        HTTPException 400: Si el vehículo ya tiene un boleto PENDIENTE activo 
            (anti-duplicidad).
        HTTPException 401: Si el usuario no tiene permisos OPERADOR o ADMIN.
        HTTPException 403: Si la licencia de la empresa está vigente y 
            corresponde al tier correspondiente.
    
    Notes:
        - El boleto nace en estado `PENDIENTE` al crear la entrada.
        - Se validan tolerancias de capacidad (`TOLERANCIA_CAPACIDAD = 1.05`).
        - El peso neto se firma al cerrar el boleto (no editable después).
        - Si `es_peso_manual=True`, el peso se registra explícitamente como manual
          y requiere autorización de roles ADMIN/SUPERVISOR.
        - Se bloquea la creación si el vehículo tiene un boleto PENDIENTE previo.
    """
    _verificar_peso_manual(payload.es_peso_manual, current_user)

    # Validar licencia contra el LM con caché por turno y sin bloquear el event
    # loop: la llamada al LM es síncrona y el WServer corre con un solo worker,
    # así que se ejecuta en un hilo. Si el LM no responde y no hay validación
    # reciente, se DEGRADA con el estado cacheado en BD (offline-first) en lugar
    # de tumbar la estación: el login/panel re-validan en vivo cuando hay red.
    lic_info: LicenseInfo | None = None
    if empresa.licencia_key:
        identidad = (
            await db.execute(
                select(IdentidadLocal).where(IdentidadLocal.id == true())
            )
        ).scalar_one_or_none()
        hardware_id = (
            identidad.hardware_id if identidad else None
        ) or obtener_hardware_id()
        client = get_license_client()
        info = await asyncio.to_thread(
            client.validate_cached,
            empresa.licencia_key,
            hardware_id,
            product_code=settings.license_product_code,
        )
        if info is None:
            log.warning(
                "Licencia %s sin verificar en LM al registrar entrada; "
                "se usa estado cacheado (tier=%s, status=%s)",
                empresa.licencia_key,
                empresa.licencia_tier,
                empresa.licencia_status,
            )
            lic_info = LicenseInfo(
                valid=(empresa.licencia_status or "").upper()
                in ("ACTIVE", "ACTIVA", "VIGENTE", "AVAILABLE"),
                tier=empresa.licencia_tier,
                status=empresa.licencia_status,
            )
        else:
            lic_info = LicenseInfo(
                valid=info.valid, tier=info.tier, status=info.status
            )
            if not info.valid:
                raise HTTPException(
                    status_code=403,
                    detail=f"Licencia inválida o expirada: {info.message}",
                )

    pesaje = await _SERVICE.create(
        db,
        empresa,
        payload,
        licencia=lic_info,
        creado_por=current_user.nombre,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    tier = (empresa.licencia_tier or "DEMO").upper()
    inc_pesaje_creado(tier)
    pesaje = await _enriquecer_pesaje_ticket(db, pesaje)
    return _resolve_to_weighing_out(pesaje)


def _es_uuid(val: str) -> uuid.UUID | None:
    try:
        return uuid.UUID(str(val).strip())
    except (ValueError, AttributeError):
        return None


async def _buscar_pesaje(
    db: AsyncSession, id_empresa: uuid.UUID, identificador: str
) -> BoletoPesaje | None:
    identificador = str(identificador).strip()
    u = _es_uuid(identificador)
    if u is not None:
        stmt = select(BoletoPesaje).where(
            BoletoPesaje.id_empresa == id_empresa,
            or_(BoletoPesaje.boleto == u, BoletoPesaje.numero_boleto == identificador),
        )
    else:
        stmt = select(BoletoPesaje).where(
            BoletoPesaje.id_empresa == id_empresa,
            BoletoPesaje.numero_boleto == identificador,
        )
    return (await db.execute(stmt)).scalar_one_or_none()


@router.post("/close/{boleto}", response_model=WeighingOut)
async def close_weighing(
    boleto: str,
    payload: WeighingClose,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> WeighingOut:
    """Cierra un boleto de pesaje abierto y registra la salida del vehículo.
    
    Args:
        boleto: Identificador del boleto de pesaje (número de serie o UUID).
        payload: Datos de cierre (peso salida, remolque, conductor, producto, guía).
        request: Objeto de solicitud HTTP para capturar la dirección IP.
        current_user: Usuario autenticado que cierra el pesaje.
        empresa: Empresa asociada al boleto.
        db: Sesión de base de datos asíncrona inyectada por FastAPI.
    
    Returns:
        WeighingOut: Objeto del pesaje cerrado en estado CERRADO con cálculos de neto.
    
    Raises:
        HTTPException 404: Si el boleto no existe o no está en estado PENDIENTE.
        HTTPException 400: Si el peso de salida es inválido o inconsistente
            respecto a la entrada.
        HTTPException 401: Si el usuario no tiene permisos OPERADOR o ADMIN.
        HTTPException 403: Si la licencia expira o no corresponde al tier.
    
    Notes:
        - Al cerrar, el boleto pasa estado `PENDIENTE` → `CERRADO`.
        - Se calcula el peso neto: `abs(pe_c - ps_c)` para camión, `abs(pe_r - ps_r)` para remolque.
        - Se incrementa `ediciones_count` y se registra `BoletoEdicion` si hay cambios.
        - Si `es_peso_manual=True`, la modificación pasa el boleto a estado `MODIFICADO`.
        - Se genera la advertencia de tolerancia si el peso está en rango crítico.
        - Se emite el ticket de pesaje formateado (térmico/hoja suelta PDF).
        - Se actualiza el Kardex de inventario con movimiento ID 60 (DESPACHO) o ID 10 (INGRESO).
    """
    _verificar_peso_manual(payload.es_peso_manual, current_user)
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    pesaje_cerrado = await _SERVICE.close(
        db,
        empresa,
        pesaje.boleto,
        payload,
        salida_por=current_user.nombre,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    tier = (empresa.licencia_tier or "DEMO").upper()
    inc_pesaje_cerrado(tier)
    pesaje_cerrado = await _enriquecer_pesaje_ticket(db, pesaje_cerrado)
    out = _resolve_to_weighing_out(pesaje_cerrado)
    advertencia = getattr(pesaje_cerrado, "_advertencia_tolerancia", None)
    if advertencia:
        out.advertencia_tolerancia = advertencia
    return out


@router.put("/{boleto}/anular", response_model=WeighingOut)
async def anular_weighing(
    boleto: str,
    payload: WeighingAnular,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> WeighingOut:
    """Anula un boleto de pesaje cerrado previamente.
    
    Args:
        boleto: Identificador del boleto de pesaje a anular.
        payload: Motivo de anulación (mínimo 10 caracteres).
        request: Objeto de solicitud HTTP para capturar la dirección IP.
        current_user: Usuario autenticado que anula el boleto.
        empresa: Empresa asociada al boleto.
        db: Sesión de base de datos asíncrona inyectada por FastAPI.
    
    Returns:
        WeighingOut: Objeto del boleto en estado ANULADO.
    
    Raises:
        HTTPException 400: Si el motivo de anulación tiene menos de 10 caracteres.
        HTTPException 404: Si el boleto no existe o no está en estado CERRADO.
        HTTPException 401: Si el usuario no tiene permisos ADMIN or SUPERVISOR.
        HTTPException 409: Si el boleto ya fue anulado previamente.
    
    Notes:
        - La anulación solo es posible sobre boletos en estado CERRADO.
        - Se requiere obligatoriamente un `motivo_anulacion` de mínimo 10 caracteres.
        - Al anular, se registra un contra-asiento en Kardex con movimiento inverso 
          exacto para mantener paridad contable/física.
        - El boleto pasa estado `CERRADO` → `ANULADO`.
        - Se libera el vehículo (quita la restricción de PENDIENTE por placa).
        - Se registra auditoría completa con usuario, IP y motivo de anulación.
        - El historial del boleto se preserva; no se borra la transacción.
    """
    _verificar_anulacion(current_user)
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    pesaje_anulado = await _SERVICE.anular(
        db,
        empresa,
        pesaje.boleto,
        payload,
        anulado_por=current_user.nombre,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    tier = (empresa.licencia_tier or "DEMO").upper()
    inc_pesaje_anulado(tier)
    pesaje_anulado = await _enriquecer_pesaje_ticket(db, pesaje_anulado)
    return _resolve_to_weighing_out(pesaje_anulado)


@router.get("/pendientes", response_model=list[WeighingOut])
async def list_pendientes(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[WeighingOut]:
    """Lista los boletos de pesaje pendientes de la empresa.
    
    Args:
        skip: Número de registros a saltar para paginación (default: 0).
        limit: Número máximo de registros a retornar (default: 100, max: 1000).
        empresa: Empresa cuyos boletos pendientes se listan.
        db: Sesión de base de datos asíncrona inyectada por FastAPI.
    
    Returns:
        list[WeighingOut]: Lista de boletos de pesaje en estado PENDIENTE.
    
    Raises:
        HTTPException 401: Si el usuario no tiene permisos OPERADOR o ADMIN.
    
    Notes:
        - Solo incluye boletos con estado PENDIENTE.
        - Los resultados incluyen enriquecimiento de datos de ticket mediante 
          `_enriquecer_pesajes_lista`.
        - Los resultados finales son resoluciones a formato WeighingOut 
          (pesos neto, bruto, tara, etc.).
        - Esta consulta es útil para el panel de control operador 
          para monitorear boletos pendientes por procesar.
    """
    rows = await _SERVICE.pendientes(db, empresa, skip=skip, limit=limit)
    rows = await _enriquecer_pesajes_lista(db, rows)
    return [_resolve_to_weighing_out(r) for r in rows]


@router.get("/list", response_model=list[WeighingOut])
async def list_weighings(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    date_from: datetime | None = None,
    date_to: datetime | None = None,
    vehicle_id: str | None = None,
    estado: str | None = None,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[WeighingOut]:
    """Lista los boletos de pesaje de la empresa con filtros opcionales.
    
    Args:
        skip: Número de registros a saltar para paginación (default: 0).
        limit: Número máximo de registros a retornar (default: 100, max: 1000).
        date_from: Fecha inicial para filtrar (inclusive).
        date_to: Fecha final para filtrar (inclusive).
        vehicle_id: ID del vehículo para filtrar por placa o identificador.
        estado: Filtrar por estado del boleto (PENDIENTE, CERRADO, MODIFICADO, ANULADO).
        empresa: Empresa cuyos boletos se listan.
        db: Sesión de base de datos asíncrona inyectada por FastAPI.
    
    Returns:
        list[WeighingOut]: Lista de boletos de pesaje con los cálculos de neto correspondientes.
    
    Raises:
        HTTPException 401: Si el usuario no tiene permisos OPERADOR o ADMIN.
    
    Notes:
        - Los resultados incluyen enriquecimiento de datos de ticket mediante 
          `_enriquecer_pesajes_lista`.
        - Los resultados finales son resoluciones a formato WeighingOut 
          (pesos neto, bruto, tara, etc.).
        - Se pueden filtrar por rango de fechas para análisis de producción.
        - El filtrado por vehículo busca en la placa o identificador del vehículo.
        - El filtrado por estado permite ver boletos por su fase en el ciclo de vida.
    """
    rows, _ = await _SERVICE.list(
        db,
        empresa,
        skip=skip,
        limit=limit,
        date_from=date_from,
        date_to=date_to,
        vehicle_id=vehicle_id,
        estado=estado,
    )
    rows = await _enriquecer_pesajes_lista(db, rows)
    return [_resolve_to_weighing_out(r) for r in rows]


@router.get("/boleto/{boleto}", response_model=WeighingOut)
async def get_weighing_by_boleto(
    boleto: str,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> WeighingOut:
    """Obtiene un boleto de pesaje por su identificador.
    
    Args:
        boleto: Identificador del boleto de pesaje (número de serie o UUID).
        empresa: Empresa a la que pertenece el boleto.
        db: Sesión de base de datos asíncrona inyectada por FastAPI.
    
    Returns:
        WeighingOut: Boleto de pesaje con los cálculos de neto correspondientes.
    
    Raises:
        HTTPException 404: Si el boleto no existe.
        HTTPException 401: Si el usuario no tiene permisos OPERADOR o ADMIN.
    
    Notes:
        - Busca el boleto por número de serie o UUID, incluyendo en la empresa especificada.
        - Si el boleto no existe, lanza error 404 con detalle descriptivo.
        - Se Enriquece el ticket con datos de catálogo (conductores, productos, almacenes, etc.)
        - El resultado final incluye pesos neto, bruto, tara y diferencias calculadas.
    """
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    pesaje = await _enriquecer_pesaje_ticket(db, pesaje)
    return _resolve_to_weighing_out(pesaje)


async def _enriquecer_pesaje_ticket(db: AsyncSession, pesaje: BoletoPesaje) -> BoletoPesaje:
    """Resuelve entidades relacionadas con nombres, códigos y datos de catálogo
    para evitar imprimir UUIDs y para que el ticket AVANZADO refleje TODO el
    formulario y sus entidades maestro (empresa, tercero, conductor, transporte,
    remolque, categoría, producto, almacén, balanza) más los registros de
    control derivados (kardex, sincronización).

    Popula atributos dinámicos en el objeto; ``WeighingOut`` solo serializa sus
    campos fijos, así que estos extras los consume el render del ticket.
    """
    if pesaje.id_remolque and not getattr(pesaje, "placa_remolque", None):
        rem = (await db.execute(select(Remolque).where(Remolque.id_remolque == pesaje.id_remolque))).scalar_one_or_none()
        if rem:
            pesaje.placa_remolque = rem.placa  # type: ignore[attr-defined]
            pesaje.remolque_placa = rem.placa  # type: ignore[attr-defined]
            pesaje.tipo_remolque = rem.tipo_remolque  # type: ignore[attr-defined]
            pesaje.tara_habitual = rem.tara_habitual  # type: ignore[attr-defined]
    if pesaje.id_producto:
        prod = (await db.execute(select(Producto).where(Producto.id_producto == pesaje.id_producto))).scalar_one_or_none()
        if prod and not getattr(pesaje, "producto", None):
            pesaje.producto_nombre = prod.nombre  # type: ignore[attr-defined]
            pesaje.producto_codigo = prod.codigo  # type: ignore[attr-defined]
            pesaje.producto_unidad = prod.unidad_medida  # type: ignore[attr-defined]
            pesaje.producto_kardex = bool(prod.es_kardex)  # type: ignore[attr-defined]
            if prod.id_categoria and not getattr(pesaje, "categoria_nombre", None):
                cat = (await db.execute(select(Categoria).where(Categoria.id_categoria == prod.id_categoria))).scalar_one_or_none()
                if cat:
                    pesaje.categoria_nombre = cat.nombre  # type: ignore[attr-defined]
                    pesaje.categoria_codigo = cat.codigo  # type: ignore[attr-defined]
    if pesaje.id_conductor and not getattr(pesaje, "conductor", None):
        cond = (await db.execute(select(Conductor).where(Conductor.cedula_dni == pesaje.id_conductor))).scalar_one_or_none()
        if cond:
            nom = (cond.nombre_completo or "").strip()
            display = f"{nom} ({cond.cedula_dni})" if nom else cond.cedula_dni
            pesaje.conductor = display  # type: ignore[attr-defined]
            pesaje.conductor_nombre = display  # type: ignore[attr-defined]
            pesaje.conductor_cedula = cond.cedula_dni  # type: ignore[attr-defined]
            pesaje.conductor_telefono = cond.telefono  # type: ignore[attr-defined]
            pesaje.conductor_licencia = cond.licencia_conducir  # type: ignore[attr-defined]
    if pesaje.id_transporte and not getattr(pesaje, "transporte", None):
        t = (await db.execute(select(Transporte).where(Transporte.id_transporte == pesaje.id_transporte))).scalar_one_or_none()
        if t:
            pesaje.transporte = t.razon_social  # type: ignore[attr-defined]
            pesaje.transporte_nombre = t.razon_social  # type: ignore[attr-defined]
            pesaje.transporte_codigo = t.codigo  # type: ignore[attr-defined]
            pesaje.transporte_rif = t.identificacion_fiscal  # type: ignore[attr-defined]
    if pesaje.id_tercero and not getattr(pesaje, "razon_social", None):
        terc = (await db.execute(select(Tercero).where(Tercero.id_tercero == pesaje.id_tercero))).scalar_one_or_none()
        if terc:
            pesaje.razon_social = terc.razon_social  # type: ignore[attr-defined]
            pesaje.tercero_nombre = terc.razon_social  # type: ignore[attr-defined]
            pesaje.tercero_codigo = terc.codigo  # type: ignore[attr-defined]
            pesaje.tercero_rif = terc.identificacion_fiscal  # type: ignore[attr-defined]
    if pesaje.id_almacen and not getattr(pesaje, "almacen", None):
        alm = (await db.execute(select(Almacen).where(Almacen.id_almacen == pesaje.id_almacen))).scalar_one_or_none()
        if alm:
            pesaje.almacen = alm.nombre  # type: ignore[attr-defined]
            pesaje.almacen_nombre = alm.nombre  # type: ignore[attr-defined]
            pesaje.almacen_codigo = alm.codigo  # type: ignore[attr-defined]
            pesaje.almacen_capacidad = alm.capacidad_max_ton  # type: ignore[attr-defined]
            pesaje.almacen_stock = alm.stock_actual_ton  # type: ignore[attr-defined]
    if pesaje.id_balanza and not getattr(pesaje, "balanza_desc", None):
        bal = (await db.execute(select(Balanza).where(Balanza.id_balanza == pesaje.id_balanza))).scalar_one_or_none()
        if bal:
            pesaje.balanza_desc = bal.descripcion  # type: ignore[attr-defined]
            pesaje.balanza_nombre = bal.descripcion  # type: ignore[attr-defined]
            pesaje.balanza_codigo = bal.codigo  # type: ignore[attr-defined]
            pesaje.balanza_capacidad = bal.capacidad_max  # type: ignore[attr-defined]
            pesaje.balanza_division = bal.division  # type: ignore[attr-defined]
    # Color del camión desde el catálogo (por placa): lo usa el ticket AVANZADO.
    if pesaje.id_vehiculo and not getattr(pesaje, "color_camion", None):
        color = (
            await db.execute(
                select(Camion.color).where(
                    func.upper(Camion.placa) == pesaje.id_vehiculo.strip().upper(),
                    Camion.id_empresa == pesaje.id_empresa,
                )
            )
        ).scalar_one_or_none()
        if color:
            pesaje.color_camion = color  # type: ignore[attr-defined]
    # Movimiento de kardex derivado del boleto (se registra al completar el ciclo).
    if not getattr(pesaje, "kardex_mov", None):
        k = (
            await db.execute(
                select(Kardex)
                .where(Kardex.boleto == pesaje.boleto, Kardex.id_empresa == pesaje.id_empresa)
                .order_by(Kardex.created_at.desc())
                .limit(1)
            )
        ).scalar_one_or_none()
        if k:
            pesaje.kardex_mov = k.id_movimiento  # type: ignore[attr-defined]
            pesaje.kardex_valor = k.valor  # type: ignore[attr-defined]
    return pesaje


@router.get("/{boleto}/pdf")
async def get_weighing_pdf(
    boleto: str,
    request: Request,
    idioma: str | None = Query(default=None),
    copias: int = Query(default=1, ge=1, le=10),
    tamano_papel: str = Query(default="Letter"),
    orientacion: str = Query(default="portrait"),
    mostrar_encabezado: bool = Query(default=True),
    mostrar_detalles: bool = Query(default=True),
    mostrar_qr: bool = Query(
        default=True,
        description="Imprime el bloque QR del boleto (lo configura la estación en Diseño de ticket)",
    ),
    tipo_ticket: str = Query(default="simple"),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> Response:
    """Genera el PDF del ticket de pesaje para el boleto especificado.
    
    Args:
        boleto: Identificador del boleto de pesaje (número de serie o UUID).
        request: Objeto de solicitud HTTP para resolución de idioma y cliente.
        idioma: Código de idioma para el ticket (ej: 'es', 'en', 'pt'). 
            Si es None, usa el idioma de la empresa.
        copias: Número de copias del ticket (mínimo 1, máximo 10).
        tamano_papel: Formato de papel ('Letter', 'Legal', 'A4', '58mm', '80mm').
        orientacion: Orientación del ticket ('portrait' o 'landscape').
        mostrar_encabezado: Si incluir el encabezado de la estación en el ticket.
        mostrar_detalles: Si incluir los detalles completos del pesaje en el ticket.
        mostrar_qr: Si incluir el bloque QR del boleto (configurable en Diseño de ticket).
        tipo_ticket: Tipo de formato de ticket ('simple', 'avanzado', 'completo').
        empresa: Empresa a la que pertenece el boleto.
        db: Sesión de base de datos asíncrona inyectada por FastAPI.
    
    Returns:
        Response: Archivo PDF del ticket de pesaje con el formato especificado.
    
    Raises:
        HTTPException 404: Si el boleto no existe.
        HTTPException 400: Si el formato de papel o tipo de ticket no es válido.
        HTTPException 401: Si el usuario no tiene permisos OPERADOR o ADMIN.
    
    Notes:
        - El idioma se resolve mediante la cabecera Accept-Language o el idioma 
          configurado en la empresa.
        - El tamaño de papel y orientación deben ser consistentes con la 
          impresora configurada en la estación.
        - El bloque QR se genera según la configuración del diseño de ticket 
          en la estación, no necesariamente aquí.
        - El ticket puede ser 'simple' (solo pesos) o 'avanzado' (con datos completos 
          de tercero, conductor, transporte, etc.).
        - Se respeta la configuración de la estación para formato de ticket térmico 
          (58mm/80mm) u hoja suelta (Letter/A4).
    """
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    pesaje = await _enriquecer_pesaje_ticket(db, pesaje)
    lang = resolve_lang(request, idioma, empresa.idioma)
    return generar_ticket_pdf(
        pesaje,
        empresa=empresa,
        copias=copias,
        tamano_papel=tamano_papel,
        orientacion=orientacion,
        mostrar_encabezado=mostrar_encabezado,
        mostrar_detalles=mostrar_detalles,
        idioma=lang,
        tipo_ticket=tipo_ticket,
        mostrar_qr=mostrar_qr,
    )


@router.get("/{boleto}/txt")
async def get_weighing_txt(
    boleto: str,
    request: Request,
    idioma: str | None = Query(default=None),
    tipo_ticket: str = Query(default="simple"),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> Response:
    """Genera el ticket de pesaje en formato de texto plano (TXT).
    
    Args:
        boleto: Identificador del boleto de pesaje (número de serie o UUID).
        request: Objeto de solicitud HTTP para resolución de idioma y cliente.
        idioma: Código de idioma para el ticket (ej: 'es', 'en', 'pt'). 
            Si es None, usa el idioma de la empresa.
        tipo_ticket: Tipo de formato de ticket ('simple', 'avanzado', 'completo').
        empresa: Empresa a la que pertenece el boleto.
        db: Sesión de base de datos asíncrona inyectada por FastAPI.
    
    Returns:
        Response: Archivo de texto plano (TXT) del ticket de pesaje.
    
    Raises:
        HTTPException 404: Si el boleto no existe.
        HTTPException 400: Si el tipo de ticket no es válido.
        HTTPException 401: Si el usuario no tiene permisos OPERADOR o ADMIN.
    
    Notes:
        - El ticket TXT es el formato de texto plano para impresoras matriciales 
          o visualización rápida en pantalla.
        - El idioma se resolve mediante la cabecera Accept-Language o el idioma 
          configurado en la empresa.
        - El tipo de ticket define el nivel de detalle: 'simple' (solo pesos), 
          'avanzado' (con datos de tercero/conductor) o 'completo' (todos los datos).
        - Este formato es útil para impresoras de impacto (Epson/Lexmark) o 
          visualización rápida sin necesidad de generar PDF.
    """
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    pesaje = await _enriquecer_pesaje_ticket(db, pesaje)
    lang = resolve_lang(request, idioma, empresa.idioma)
    return generar_ticket_txt(pesaje, empresa=empresa, idioma=lang, tipo_ticket=tipo_ticket)


@router.get("/{boleto}/export")
async def get_weighing_export(
    boleto: str,
    request: Request,
    idioma: str | None = Query(default=None),
    tipo_ticket: str = Query(default="simple"),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> Response:
    """Descarga el boleto en el formato configurado en la empresa.

    Es la ruta que usa la app cuando el usuario no elige formato: aplica
    ``empresas.formato_ticket`` (PDF por defecto) —REQ-FN-CFG-004.
    """
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    pesaje = await _enriquecer_pesaje_ticket(db, pesaje)
    lang = resolve_lang(request, idioma, empresa.idioma)
    if (empresa.formato_ticket or "PDF").upper() == "TXT":
        return generar_ticket_txt(pesaje, empresa=empresa, idioma=lang, tipo_ticket=tipo_ticket)
    return generar_ticket_pdf(pesaje, empresa=empresa, idioma=lang, tipo_ticket=tipo_ticket)


@router.put("/{boleto}", response_model=WeighingOut)
async def update_weighing(
    boleto: str,
    payload: WeighingUpdate,
    request: Request,
    idioma: str | None = None,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> WeighingOut:
    """Actualiza un boleto de pesaje ya cerrado o modifica datos complementarios.
    
    Args:
        boleto: Identificador del boleto de pesaje a actualizar.
        payload: Datos a actualizar (justificacion, idioma, u otros campos).
        request: Objeto de solicitud HTTP para resolución de idioma y cliente.
        current_user: Usuario autenticado que realiza la actualización.
        empresa: Empresa a la que pertenece el boleto.
        db: Sesión de base de datos asíncrona inyectada por FastAPI.
    
    Returns:
        WeighingOut: Boleto de pesaje actualizado con los nuevos datos.
    
    Raises:
        HTTPException 404: Si el boleto no existe.
        HTTPException 400: Si el boleto no está en estado MODIFICADO o CERRADO.
        HTTPException 401: Si el usuario no tiene permisos ADMIN o SUPERVISOR.
    
    Notes:
        - Solo es posible actualizar boletos en estado MODIFICADO o CERRADO.
        - El campo `justificacion` es obligatorio para actualizaciones sobre boletos 
          CERRADO (regla de auditoría).
        - Se registra un nuevo registro `BoletoEdicion` con el motivo de la modificación.
        - Si el boleto estaba en estado PENDIENTE, la actualización lo pasa a MODIFICADO.
        - El idioma se aplica según la configuración de la empresa y el usuario.
        - Se actualiza el historial de ediciones (`ediciones_count`) y se registra 
          la fecha/hora de la modificación.
    """
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    lang = resolve_lang(request, idioma, empresa.idioma)
    pesaje_actualizado = await _SERVICE.update(
        db,
        empresa,
        pesaje.boleto,
        payload,
        modificado_por=current_user.nombre,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
        es_admin=_es_admin(current_user),
        rol_usuario=getattr(current_user, "rol", None),
        justificacion=payload.justificacion,
        idioma=lang,
    )
    pesaje_actualizado = await _enriquecer_pesaje_ticket(db, pesaje_actualizado)
    return _resolve_to_weighing_out(pesaje_actualizado)


@router.get("/{boleto}/ediciones", response_model=list[BoletoEdicionOut])
async def listar_ediciones_boleto(
    boleto: str,
    _user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[BoletoEdicionOut]:
    """Historial de ediciones del boleto (justificación obligatoria por edición)."""
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")
    ediciones = await _SERVICE.listar_ediciones(db, empresa, pesaje.boleto)
    return [BoletoEdicionOut.model_validate(e) for e in ediciones]


# ---------------------------------------------------------------------------
# Imágenes de BoletoPesaje
# ---------------------------------------------------------------------------


class ImagenPesajeCreate(BaseModel):
    tipo: str = Field(..., pattern="^(placa|vehiculo|documento|entrada|salida|otros)$")
    url: str


class ImagenPesajeOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id_imagen: uuid.UUID
    boleto: uuid.UUID
    tipo: str
    url: str


@router.get("/{boleto}/imagenes", response_model=list[ImagenPesajeOut])
async def list_imagenes(
    boleto: str,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[ImagenPesajeOut]:
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        return []
    result = await db.execute(
        select(ImagenPesaje).where(ImagenPesaje.boleto == pesaje.boleto)
    )
    return [
        ImagenPesajeOut.model_validate(img) for img in result.scalars().all()
    ]


@router.post("/{boleto}/imagenes", response_model=ImagenPesajeOut, status_code=201)
async def add_imagen(
    boleto: str,
    payload: ImagenPesajeCreate,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ImagenPesajeOut:
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")

    img = ImagenPesaje(boleto=pesaje.boleto, tipo=payload.tipo, url=payload.url)
    db.add(img)
    await db.commit()
    await db.refresh(img)
    return ImagenPesajeOut.model_validate(img)


@router.post("/{boleto}/imagenes/archivo", response_model=ImagenPesajeOut, status_code=201)
async def upload_imagen(
    boleto: str,
    file: UploadFile = File(...),
    tipo: str = Form(..., pattern="^(placa|vehiculo|documento|entrada|salida|otros)$"),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ImagenPesajeOut:
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")

    if file.content_type not in settings.allowed_image_types:
        raise HTTPException(
            status_code=400,
            detail=f"Tipo de archivo no permitido: {file.content_type}. "
            f"Permitidos: {', '.join(settings.allowed_image_types)}",
        )
    raw = await file.read()
    if len(raw) > settings.max_image_bytes:
        raise HTTPException(status_code=400, detail="El archivo supera el tamaño máximo de 10 MB")

    dest_dir = os.path.join(settings.media_dir, str(pesaje.boleto))
    os.makedirs(dest_dir, exist_ok=True)
    ext = os.path.splitext(file.filename or "image.jpg")[1] or ".jpg"
    filename = f"{tipo}_{uuid.uuid4().hex[:12]}{ext}"
    filepath = os.path.join(dest_dir, filename)
    with open(filepath, "wb") as f:
        f.write(raw)

    url = f"/media/{pesaje.boleto}/{filename}"
    img = ImagenPesaje(boleto=pesaje.boleto, tipo=tipo, url=url)
    db.add(img)

    # Update truck's photo if not set
    if tipo == "vehiculo" and pesaje.id_vehiculo:
        from sqlalchemy import select

        from app.models import Camion
        stmt = select(Camion).where(
            Camion.id_empresa == empresa.id_empresa,
            Camion.placa == pesaje.id_vehiculo
        )
        camion = (await db.execute(stmt)).scalar_one_or_none()
        if camion and not camion.foto_real_url:
            camion.foto_real_url = url

    await db.commit()
    await db.refresh(img)
    return ImagenPesajeOut.model_validate(img)


@router.delete("/{boleto}/imagenes/{id_imagen}", status_code=204)
async def delete_imagen(
    boleto: str,
    id_imagen: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, boleto)
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")

    img_result = await db.execute(
        select(ImagenPesaje).where(
            ImagenPesaje.id_imagen == id_imagen,
            ImagenPesaje.boleto == pesaje.boleto,
        )
    )
    img = img_result.scalar_one_or_none()
    if img is None:
        raise HTTPException(status_code=404, detail="Imagen no encontrada")
    await db.delete(img)
    await db.commit()


# ---------------------------------------------------------------------------
# Peso en vivo (HAL de balanza, B7 / REQ-NF-ARQ-004)
# ---------------------------------------------------------------------------


class PesoEnVivoOut(BaseModel):
    peso_kg: float | None
    estable: bool
    conectado: bool = False
    balanza: str
    hardware: str
    timestamp: datetime


@router.get("/scale/{balanza_id}/live", response_model=PesoEnVivoOut)
async def peso_en_vivo(
    balanza_id: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    current_user: Usuario = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PesoEnVivoOut:
    result = await db.execute(
        select(Balanza).where(
            Balanza.id_balanza == balanza_id,
            Balanza.id_empresa == empresa.id_empresa,
        )
    )
    balanza = result.scalar_one_or_none()
    if balanza is None:
        raise HTTPException(status_code=404, detail="Balanza no encontrada")

    try:
        # Sesión persistente: la conexión con la balanza queda emparejada y se
        # reutiliza entre polls (no se abre/cierra en cada lectura).
        sesion = await get_scale_session_manager().obtener(balanza)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    ultimo = sesion.ultimo
    return PesoEnVivoOut(
        peso_kg=sesion.peso_kg,
        estable=sesion.estable,
        conectado=sesion.conectado,
        balanza=balanza.descripcion,
        hardware=sesion.hardware,
        timestamp=ultimo.timestamp if ultimo else datetime.now(UTC),
    )