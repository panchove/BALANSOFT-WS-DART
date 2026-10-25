"""Rutas del módulo INDICADORES: el terminal de peso, separado de la báscula.

La báscula física (plataforma de pesaje, con su capacidad y división) y el
**indicador** (el terminal que muestra/transmite el peso: BKG LP7510, CAS
C12001A, Transcell TI500E, AND AD431, Cardinal UMC555, Toledo T4321, …) son
entidades separadas desde la migración 028. El ADMIN decide qué indicador va
con qué báscula mediante ``POST /indicadores/{id}/asignar`` (que escribe
``balanzas.id_indicador``).

La configuración de comunicación (protocolo, puerto/ip, formato de trama,
baudrate y delimitador) vive en el indicador, porque son propiedades del
*terminal*, no de la plataforma.

Config **local de la estación** (no se sincroniza), igual que
``balanzas``/``semaforos``/``camaras``.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import (
    get_current_empresa,
    get_current_user,
    require_admin,
)
from app.core.database import get_db
from app.models import Balanza, Empresa, Indicador, Usuario
from app.schemas import IndicadorCreate, IndicadorOut
from app.services.catalog_service import CatalogService

router = APIRouter(prefix="/api/v1", tags=["Indicadores"])
_SERVICE = CatalogService()


async def _obtener_indicador(
    db: AsyncSession, empresa: Empresa, id_indicador: uuid.UUID
) -> Indicador:
    """Carga un indicador de la empresa (404 si no existe) — aislamiento tenant."""
    indicador = await db.get(Indicador, id_indicador)
    if indicador is None or indicador.id_empresa != empresa.id_empresa:
        raise HTTPException(status_code=404, detail="Indicador no encontrado")
    return indicador


async def _contar_enlazadas(
    db: AsyncSession, id_empresa: uuid.UUID, id_indicador: uuid.UUID
) -> int:
    """Básculas físicas enlazadas a este indicador."""
    result = await db.execute(
        select(func.count())
        .select_from(Balanza)
        .where(
            Balanza.id_empresa == id_empresa,
            Balanza.id_indicador == id_indicador,
        )
    )
    return int(result.scalar() or 0)


def _validar_config(data: dict) -> dict:
    """Normaliza la configuración antes de persistirla."""
    if data.get("codigo") is not None:
        data["codigo"] = str(data["codigo"]).strip() or None
    return data


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------


@router.get(
    "/indicadores/descubrir",
    response_model=list[IndicadorOut],
)
async def descubrir_indicadores(
    db: AsyncSession = Depends(get_db),
    empresa: Empresa = Depends(get_current_empresa),
) -> list[IndicadorOut]:
    rows = await _SERVICE.list_filtrado(
        db, empresa.id_empresa, "indicadores",
        iguales={"activo": True},
    )
    return [IndicadorOut(**r) for r in rows]


@router.get("/indicadores", response_model=list[IndicadorOut])
async def list_indicadores(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
    q: str | None = Query(None, description="Búsqueda de texto (código, descripción, marca, modelo, IP/puerto)."),
    activo: bool | None = Query(None, description="Filtra por indicadores activos/inactivos."),
    is_simulado: bool | None = Query(None, description="Filtra por indicadores simulados/reales."),
    protocolo: str | None = Query(None, description="Filtra por protocolo de comunicación (tcp/serial)."),
) -> list[IndicadorOut]:
    """Lista los indicadores de la empresa con **filtros de vista** opcionales."""
    rows = await _SERVICE.list_filtrado(
        db,
        empresa.id_empresa,
        "indicadores",
        q=q,
        columnas_texto=("codigo", "descripcion", "marca", "modelo", "ip_address", "puerto_com"),
        iguales={"activo": activo, "is_simulado": is_simulado, "protocolo": protocolo},
    )
    salida: list[IndicadorOut] = []
    for r in rows:
        enlazadas = await _contar_enlazadas(db, empresa.id_empresa, r["id_indicador"])
        salida.append(IndicadorOut(**r, balanzas_enlazadas=enlazadas))
    return salida


@router.post(
    "/indicadores", response_model=IndicadorOut, dependencies=[Depends(require_admin)]
)
async def create_indicador(
    payload: IndicadorCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> IndicadorOut:
    data = _validar_config(payload.model_dump())
    row = await _SERVICE.create(
        db,
        empresa.id_empresa,
        "indicadores",
        data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return IndicadorOut(**row)


@router.put(
    "/indicadores/{id_indicador}",
    response_model=IndicadorOut,
    dependencies=[Depends(require_admin)],
)
async def update_indicador(
    id_indicador: uuid.UUID,
    payload: IndicadorCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> IndicadorOut:
    await _obtener_indicador(db, empresa, id_indicador)
    data = _validar_config(payload.model_dump())
    row = await _SERVICE.update(
        db,
        empresa.id_empresa,
        "indicadores",
        str(id_indicador),
        data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    enlazadas = await _contar_enlazadas(db, empresa.id_empresa, id_indicador)
    return IndicadorOut(**row, balanzas_enlazadas=enlazadas)


@router.delete(
    "/indicadores/{id_indicador}",
    status_code=204,
    dependencies=[Depends(require_admin)],
)
async def delete_indicador(
    id_indicador: uuid.UUID,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _obtener_indicador(db, empresa, id_indicador)
    enlazadas = await _contar_enlazadas(db, empresa.id_empresa, id_indicador)
    if enlazadas:
        raise HTTPException(
            status_code=409,
            detail=(
                f"No se puede eliminar: {enlazadas} báscula(s) usan este "
                "indicador. Desenlácelas primero."
            ),
        )
    await _SERVICE.delete(
        db,
        empresa.id_empresa,
        "indicadores",
        str(id_indicador),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )


# ---------------------------------------------------------------------------
# Enlace báscula ↔ indicador
# ---------------------------------------------------------------------------


@router.post(
    "/indicadores/{id_indicador}/balanzas/{id_balanza}/enlazar",
    response_model=IndicadorOut,
    dependencies=[Depends(require_admin)],
    summary="Enlazar una báscula a este indicador",
)
async def enlazar_balanza(
    id_indicador: uuid.UUID,
    id_balanza: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> IndicadorOut:
    """Enlaza una báscula física a este indicador (`balanzas.id_indicador`).

    La báscula debe pertenecer a la misma empresa (aislamiento multi-tenant);
    si ya estaba enlazada a otro indicador, se reasigna (un indicador por
    báscula).
    """
    return await _fijar_enlace(db, empresa, id_indicador, id_balanza, enlazar=True)


@router.delete(
    "/indicadores/{id_indicador}/balanzas/{id_balanza}/enlazar",
    response_model=IndicadorOut,
    dependencies=[Depends(require_admin)],
    summary="Desenlazar una báscula de este indicador",
)
async def desenlazar_balanza(
    id_indicador: uuid.UUID,
    id_balanza: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> IndicadorOut:
    """Desenlaza una báscula física de este indicador (`id_indicador = NULL`)."""
    return await _fijar_enlace(db, empresa, id_indicador, id_balanza, enlazar=False)


async def _fijar_enlace(
    db: AsyncSession,
    empresa: Empresa,
    id_indicador: uuid.UUID,
    id_balanza: uuid.UUID,
    *,
    enlazar: bool,
) -> IndicadorOut:
    """Escribe (o limpia) ``balanzas.id_indicador`` y devuelve el indicador."""
    indicador = await _obtener_indicador(db, empresa, id_indicador)

    result = await db.execute(
        select(Balanza).where(
            Balanza.id_balanza == id_balanza,
            Balanza.id_empresa == empresa.id_empresa,
        )
    )
    balanza = result.scalar_one_or_none()
    if balanza is None:
        raise HTTPException(status_code=404, detail="Báscula no encontrada")

    if enlazar:
        balanza.id_indicador = id_indicador
    elif balanza.id_indicador == id_indicador:
        balanza.id_indicador = None
    await db.commit()

    enlazadas = await _contar_enlazadas(db, empresa.id_empresa, id_indicador)
    return IndicadorOut(
        id_indicador=indicador.id_indicador,
        codigo=indicador.codigo,
        descripcion=indicador.descripcion,
        marca=indicador.marca,
        modelo=indicador.modelo,
        activo=indicador.activo,
        is_simulado=indicador.is_simulado,
        protocolo=indicador.protocolo,
        puerto_com=indicador.puerto_com,
        ip_address=indicador.ip_address,
        puerto_tcp=indicador.puerto_tcp,
        formato_trama=indicador.formato_trama,
        baudrate=indicador.baudrate,
        delimitador=indicador.delimitador,
        balanzas_enlazadas=enlazadas,
    )
