"""Rutas del módulo BARRERAS: control físico de acceso (abrir/cerrar).

Dispositivo actuador de control de acceso: la app decide la apertura o cierre
(automático o manual) y el HAL lo envía al hardware por HTTP o puerto serie/USB
(docs/DISPOSITIVOS.md §5).
"""

from __future__ import annotations

import os
import uuid
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import (
    get_current_empresa,
    get_current_user,
    require_admin,
)
from app.core.barrera_hal import (
    HttpBarreraHAL,
    SerialBarreraHAL,
    get_barrera_hal,
)
from app.core.database import get_db
from app.core.discovery_smart import (
    hay_hardware_serial,
    puertos_serie_disponibles,
)
from app.models import Barrera, Empresa, Usuario
from app.schemas import (
    BarreraComandoIn,
    BarreraComandoOut,
    BarreraCreate,
    BarreraDescubiertaOut,
    BarreraEstadoOut,
    BarreraOut,
    BarreraPruebaOut,
    BarreraUpdate,
)
from app.services.audit_service import registrar
from app.services.catalog_service import CatalogService

router = APIRouter(prefix="/barreras", tags=["Barreras"])
_SERVICE = CatalogService()

_DEFAULT_HTTP_HOST = "127.0.0.1"
_DEFAULT_HTTP_PUERTO = 8082


async def _obtener_barrera(
    db: AsyncSession, empresa: Empresa, id_barrera: uuid.UUID
) -> Barrera:
    """Carga una barrera de la empresa (404 si no existe) — aislamiento tenant."""
    result = await db.execute(
        select(Barrera).where(
            Barrera.id_barrera == id_barrera,
            Barrera.id_empresa == empresa.id_empresa,
        )
    )
    barrera = result.scalar_one_or_none()
    if barrera is None:
        raise HTTPException(status_code=404, detail="Barrera no encontrada")
    return barrera


def _validar_config(data: dict) -> dict:
    """Normaliza y valida la configuración de hardware antes de persistirla."""
    protocolo = (data.get("protocolo") or "http").lower()
    data["protocolo"] = protocolo

    if protocolo == "serial":
        puerto_com = (data.get("puerto_com") or "").strip()
        if not puerto_com:
            raise HTTPException(
                status_code=400,
                detail="Una barrera serial necesita el puerto (p. ej. /dev/ttyUSB0 o COM3)",
            )
        data["puerto_com"] = puerto_com
        data["ip_address"] = None
        data["puerto_tcp"] = None
    else:
        data["ip_address"] = (data.get("ip_address") or _DEFAULT_HTTP_HOST).strip()
        data["puerto_tcp"] = int(data.get("puerto_tcp") or _DEFAULT_HTTP_PUERTO)
        data["puerto_com"] = None

    ubicacion = (data.get("ubicacion") or "ambos").lower()
    if ubicacion not in ("entrada", "salida", "ambos"):
        ubicacion = "ambos"
    data["ubicacion"] = ubicacion

    return data


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------


@router.get("", response_model=list[BarreraOut])
async def listar_barreras(
    q: str | None = Query(None, description="Texto libre en descripción o código"),
    activo: bool | None = Query(None, description="Filtrar por estado activo"),
    is_simulado: bool | None = Query(None, description="Filtrar simuladas"),
    protocolo: str | None = Query(None, description="http | serial"),
    ubicacion: str | None = Query(None, description="entrada | salida | ambos"),
    control_automatico: bool | None = Query(None, description="Automático"),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[BarreraOut]:
    """Lista las barreras de la empresa aplicando filtros de vista."""
    filas = await _SERVICE.list_filtrado(
        db,
        empresa.id_empresa,
        "barreras",
        q=q,
        columnas_texto=("descripcion", "codigo", "puerto_com", "ip_address"),
        iguales={
            "activo": activo,
            "is_simulado": is_simulado,
            "protocolo": protocolo,
            "ubicacion": ubicacion,
            "control_automatico": control_automatico,
        },
    )
    return [BarreraOut.model_validate(f) for f in filas]


@router.post("", response_model=BarreraOut, dependencies=[Depends(require_admin)])
async def crear_barrera(
    payload: BarreraCreate,
    request: Request,
    empresa: Empresa = Depends(get_current_empresa),
    current_user: Usuario = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> BarreraOut:
    """Registra una barrera para la empresa autenticada."""
    data = payload.model_dump(exclude_unset=True)
    data = _validar_config(data)
    creada = await _SERVICE.create(
        db,
        empresa.id_empresa,
        "barreras",
        data,
        usuario_email=current_user.email,
        ip=request.client.host if request.client else None,
    )
    return BarreraOut.model_validate(creada)


@router.get("/descubrir", response_model=list[BarreraDescubiertaOut])
async def descubrir_barreras(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[BarreraDescubiertaOut]:
    """Detecta puertos serie o dispositivos disponibles para barreras."""
    encontrados: list[BarreraDescubiertaOut] = []

    res_existentes = await db.execute(
        select(Barrera.puerto_com).where(
            Barrera.id_empresa == empresa.id_empresa,
            Barrera.puerto_com.isnot(None),
        )
    )
    com_existentes = {p for (p,) in res_existentes.all() if p}

    if hay_hardware_serial():
        for p in puertos_serie_disponibles():
            if p not in com_existentes:
                encontrados.append(
                    BarreraDescubiertaOut(
                        descripcion=f"Barrera USB/Serie ({p})",
                        protocolo="serial",
                        puerto_com=p,
                        is_simulado=False,
                    )
                )

    return encontrados


@router.get("/{id_barrera}", response_model=BarreraOut)
async def obtener_barrera(
    id_barrera: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> BarreraOut:
    barrera = await _obtener_barrera(db, empresa, id_barrera)
    return BarreraOut.model_validate(barrera)


@router.put("/{id_barrera}", response_model=BarreraOut, dependencies=[Depends(require_admin)])
async def actualizar_barrera(
    id_barrera: uuid.UUID,
    payload: BarreraUpdate,
    request: Request,
    empresa: Empresa = Depends(get_current_empresa),
    current_user: Usuario = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> BarreraOut:
    barrera = await _obtener_barrera(db, empresa, id_barrera)
    data = payload.model_dump(exclude_unset=True)
    if "protocolo" in data or "puerto_com" in data or "ip_address" in data:
        merged = {
            "protocolo": data.get("protocolo", barrera.protocolo),
            "puerto_com": data.get("puerto_com", barrera.puerto_com),
            "ip_address": data.get("ip_address", barrera.ip_address),
            "puerto_tcp": data.get("puerto_tcp", barrera.puerto_tcp),
            "ubicacion": data.get("ubicacion", barrera.ubicacion),
        }
        _validar_config(merged)
        data.update(merged)

    actualizada = await _SERVICE.update(
        db,
        empresa.id_empresa,
        "barreras",
        id_barrera,
        data,
        usuario_email=current_user.email,
        ip=request.client.host if request.client else None,
    )
    return BarreraOut.model_validate(actualizada)


@router.delete("/{id_barrera}", dependencies=[Depends(require_admin)])
async def eliminar_barrera(
    id_barrera: uuid.UUID,
    request: Request,
    empresa: Empresa = Depends(get_current_empresa),
    current_user: Usuario = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, bool]:
    await _obtener_barrera(db, empresa, id_barrera)
    await _SERVICE.delete(
        db,
        empresa.id_empresa,
        "barreras",
        id_barrera,
        usuario_email=current_user.email,
        ip=request.client.host if request.client else None,
    )
    return {"ok": True}


# ---------------------------------------------------------------------------
# Diagnóstico y comandos manuales
# ---------------------------------------------------------------------------


@router.post("/{id_barrera}/probar", response_model=BarreraPruebaOut)
async def probar_barrera(
    id_barrera: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> BarreraPruebaOut:
    """Prueba la conexión con la barrera leyendo su estado."""
    barrera = await _obtener_barrera(db, empresa, id_barrera)
    try:
        hal = get_barrera_hal(barrera)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    estado = await hal.leer_estado()
    if estado is None:
        return BarreraPruebaOut(
            barrera=barrera.descripcion,
            conectado=False,
            protocolo=barrera.protocolo or "http",
            detalle="La barrera no respondió. Verifique conexión y parámetros configurados.",
        )
    return BarreraPruebaOut(
        barrera=barrera.descripcion,
        conectado=True,
        protocolo=barrera.protocolo or "http",
        estado=estado,
        detalle="Conexión correcta",
    )


@router.get("/{id_barrera}/estado", response_model=BarreraEstadoOut)
async def estado_barrera(
    id_barrera: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> BarreraEstadoOut:
    """Consulta el estado actual de la barrera."""
    barrera = await _obtener_barrera(db, empresa, id_barrera)
    estado = None
    try:
        hal = get_barrera_hal(barrera)
        estado = await hal.leer_estado()
    except ValueError:
        estado = None

    return BarreraEstadoOut(
        barrera=barrera.descripcion,
        conectado=estado is not None,
        estado=estado,
        detalle=None if estado is not None else "Sin respuesta del equipo",
    )


@router.post("/{id_barrera}/comando", response_model=BarreraComandoOut)
async def enviar_comando_barrera(
    id_barrera: uuid.UUID,
    payload: BarreraComandoIn,
    request: Request,
    empresa: Empresa = Depends(get_current_empresa),
    current_user: Usuario = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> BarreraComandoOut:
    """Envía un comando de acción ('open' o 'close') a la barrera."""
    barrera = await _obtener_barrera(db, empresa, id_barrera)
    try:
        hal = get_barrera_hal(barrera)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    ok = await hal.enviar_comando(payload.action)
    await registrar(
        db,
        empresa.id_empresa,
        usuario_email=current_user.email,
        accion="COMANDO_BARRERA",
        entidad="barreras",
        entidad_id=str(barrera.id_barrera),
        detalle={
            "action": payload.action,
            "aplicado": ok,
            "protocolo": barrera.protocolo,
        },
        ip=request.client.host if request.client else None,
    )
    return BarreraComandoOut(
        aplicado=ok,
        action=payload.action,
        detalle="Comando ejecutado con éxito" if ok else "El equipo no respondió o rechazó el comando",
    )
