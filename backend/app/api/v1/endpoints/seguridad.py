"""Rutas del módulo SEGURIDAD Y ACCESOS: matriz de módulos por rol.

- GET  /api/v1/seguridad/matriz   → matriz completa (por defecto ⊕ sobrescrituras)
- PUT  /api/v1/seguridad/matriz   → actualiza el acceso de un (rol, módulo)

Solo ADMIN puede escribir. La matriz por defecto vive en
``app/core/seguridad_matrix.py``; los cambios se persisten por empresa.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user, require_admin
from app.core.database import get_db
from app.core.seguridad_matrix import MODULOS, ROLES_LOCALES
from app.models import Empresa, PermisoAcceso, Usuario
from app.schemas import AccesoModuloOut, AccesoUpdate, MatrizAccesosOut

router = APIRouter(prefix="/api/v1/seguridad", tags=["Seguridad"])


async def _accesos_persistidos(db: AsyncSession, empresa: Empresa) -> dict[tuple[str, str], str]:
    rows = (
        (
            await db.execute(
                select(PermisoAcceso).where(PermisoAcceso.id_empresa == empresa.id_empresa)
            )
        )
        .scalars()
        .all()
    )
    return {(r.rol, r.modulo): r.acceso for r in rows}


@router.get("/matriz", response_model=MatrizAccesosOut)
async def obtener_matriz(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> MatrizAccesosOut:
    from app.core.seguridad_matrix import MATRIZ_DEFECTO

    persistidos = await _accesos_persistidos(db, empresa)
    modulos = []
    for clave, titulo in MODULOS.items():
        accesos: dict[str, str] = {}
        for rol, fila in MATRIZ_DEFECTO.items():
            accesos[rol] = persistidos.get((rol, clave), fila.get(clave, "ninguno"))
        modulos.append(AccesoModuloOut(clave=clave, titulo=titulo, accesos=accesos))
    return MatrizAccesosOut(modulos=modulos)


@router.put("/matriz", response_model=AccesoModuloOut, dependencies=[Depends(require_admin)])
async def actualizar_acceso(
    payload: AccesoUpdate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> AccesoModuloOut:
    from app.core.seguridad_matrix import MATRIZ_DEFECTO

    if payload.rol not in ROLES_LOCALES:
        raise HTTPException(status_code=400, detail=f"Rol desconocido: {payload.rol}")
    if payload.modulo not in MODULOS:
        raise HTTPException(status_code=400, detail=f"Módulo desconocido: {payload.modulo}")

    # Regla de gobierno inviolable: ADMIN siempre tiene acceso "editar" en
    # TODOS los módulos. No se puede degradar (REQ-NF-ARQ-007 + regla interna).
    if payload.rol == "ADMIN":
        payload.acceso = "editar"

    registro = (
        await db.execute(
            select(PermisoAcceso).where(
                PermisoAcceso.id_empresa == empresa.id_empresa,
                PermisoAcceso.rol == payload.rol,
                PermisoAcceso.modulo == payload.modulo,
            )
        )
    ).scalar_one_or_none()

    if registro is None:
        registro = PermisoAcceso(
            id_empresa=empresa.id_empresa,
            rol=payload.rol,
            modulo=payload.modulo,
            acceso=payload.acceso,
        )
        db.add(registro)
    else:
        registro.acceso = payload.acceso
    await db.commit()
    await db.refresh(registro)

    from app.services.audit_service import registrar

    await registrar(
        db,
        id_usuario=current_user.id_usuario,
        id_empresa=empresa.id_empresa,
        accion="UPDATE",
        entidad="permisos_acceso",
        detalle={
            "rol": payload.rol,
            "modulo": payload.modulo,
            "acceso": payload.acceso,
            "ip": request.client.host if request.client else None,
        },
    )

    accesos: dict[str, str] = {}
    persistidos = await _accesos_persistidos(db, empresa)
    for rol, fila in MATRIZ_DEFECTO.items():
        accesos[rol] = persistidos.get((rol, payload.modulo), fila.get(payload.modulo, "ninguno"))
    return AccesoModuloOut(
        clave=payload.modulo,
        titulo=MODULOS[payload.modulo],
        accesos=accesos,
    )
