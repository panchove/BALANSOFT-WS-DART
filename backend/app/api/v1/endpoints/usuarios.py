"""Usuarios operativos locales y su vínculo con las credenciales globales.

docs/MANEJO_DB.md §4 y §9.3: los usuarios locales (ADMIN/OPERADOR/AUDITOR/
TRABAJADOR) viven en la DB local; crear/modificar implica encolar la entidad
`usuario` en `sync_queue` para su entrega al servidor (credenciales globales).
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user
from app.core.database import get_db
from app.core.security import hash_password
from app.models import Empresa, SyncQueue, Usuario
from app.schemas import UsuarioCreate, UsuarioOut, UsuarioUpdate

router = APIRouter(prefix="/api/v1/usuarios", tags=["Usuarios"])

_CONSULTA = {"ADMIN", "AUDITOR"}
_EDICION = {"ADMIN"}


async def _enqueue_usuario(
    db: AsyncSession,
    empresa: Empresa,
    usuario: Usuario,
    operacion: str,
) -> None:
    db.add(
        SyncQueue(
            id_empresa=empresa.id_empresa,
            entidad="usuario",
            operacion=operacion,
            entidad_id=str(usuario.id_usuario),
            payload={
                "id_usuario": str(usuario.id_usuario),
                "email": usuario.email,
                "nombre": usuario.nombre,
                "rol": usuario.rol,
                "activo": usuario.activo,
            },
        )
    )


@router.get("", response_model=list[UsuarioOut])
async def list_usuarios(
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[Usuario]:
    if current_user.rol not in _CONSULTA:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No tiene permisos para consultar usuarios.",
        )
    rows = (
        await db.execute(
            select(Usuario)
            .where(Usuario.id_empresa == empresa.id_empresa)
            .order_by(Usuario.nombre)
        )
    ).scalars().all()
    return list(rows)


@router.post("", response_model=UsuarioOut, status_code=status.HTTP_201_CREATED)
async def create_usuario(
    payload: UsuarioCreate,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> Usuario:
    if current_user.rol not in _EDICION:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo el ADMIN puede crear usuarios.",
        )
    email = payload.email.lower()
    existente = (
        await db.execute(select(Usuario).where(Usuario.email == email))
    ).scalar_one_or_none()
    if existente is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ya existe un usuario con ese email.",
        )
    if payload.rol == "ADMIN":
        admin_existente = (
            (
                await db.execute(
                    select(Usuario).where(
                        Usuario.id_empresa == empresa.id_empresa,
                        Usuario.rol == "ADMIN",
                        Usuario.activo.is_(True),
                    )
                )
            )
            .scalars()
            .first()
        )
        if admin_existente is not None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Solo puede existir un ADMIN activo por empresa.",
            )

    usuario = Usuario(
        id_empresa=empresa.id_empresa,
        nombre=payload.nombre,
        email=email,
        password_hash=hash_password(payload.password),
        rol=payload.rol,
        activo=True,
    )
    db.add(usuario)
    await db.flush()
    await _enqueue_usuario(db, empresa, usuario, "upsert")
    await db.commit()
    await db.refresh(usuario)
    return usuario


@router.put("/{id_usuario}", response_model=UsuarioOut)
async def update_usuario(
    id_usuario: uuid.UUID,
    payload: UsuarioUpdate,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> Usuario:
    if current_user.rol not in _EDICION:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo el ADMIN puede modificar usuarios.",
        )
    usuario = (
        await db.execute(
            select(Usuario).where(
                Usuario.id_empresa == empresa.id_empresa,
                Usuario.id_usuario == id_usuario,
            )
        )
    ).scalar_one_or_none()
    if usuario is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Usuario no encontrado.")
    if payload.nombre is not None:
        usuario.nombre = payload.nombre
    if payload.rol is not None:
        usuario.rol = payload.rol
    if payload.activo is not None:
        usuario.activo = payload.activo
    if payload.password is not None:
        usuario.password_hash = hash_password(payload.password)
    await db.flush()
    await _enqueue_usuario(db, empresa, usuario, "upsert")
    await db.commit()
    await db.refresh(usuario)
    return usuario


@router.delete("/{id_usuario}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_usuario(
    id_usuario: uuid.UUID,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    if current_user.rol not in _EDICION:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo el ADMIN puede eliminar usuarios.",
        )
    usuario = (
        await db.execute(
            select(Usuario).where(
                Usuario.id_empresa == empresa.id_empresa,
                Usuario.id_usuario == id_usuario,
            )
        )
    ).scalar_one_or_none()
    if usuario is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Usuario no encontrado.")
    usuario.activo = False
    await db.flush()
    await _enqueue_usuario(db, empresa, usuario, "delete")
    await db.commit()