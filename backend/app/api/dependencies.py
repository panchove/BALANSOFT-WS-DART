"""Dependencias de autenticación y autorización de la API."""

from __future__ import annotations

import uuid

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import verify_token
from app.models import Empresa, Usuario
from app.schemas import UserOut

bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> Usuario:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Autenticación requerida",
            headers={"WWW-Authenticate": "Bearer"},
        )
    payload = verify_token(credentials.credentials)
    if payload is None or "sub" not in payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token inválido o expirado",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        user_id = uuid.UUID(payload["sub"])
    except (ValueError, TypeError):
        raise HTTPException(status_code=401, detail="Token inválido") from None

    result = await db.execute(
        select(Usuario).where(Usuario.id_usuario == user_id, Usuario.activo.is_(True))
    )
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    return user


async def get_current_empresa(
    current_user: Usuario = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Empresa:
    result = await db.execute(
        select(Empresa).where(Empresa.id_empresa == current_user.id_empresa)
    )
    empresa = result.scalar_one_or_none()
    if empresa is None:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")
    return empresa


async def require_catalog_manager(
    current_user: Usuario = Depends(get_current_user),
) -> Usuario:
    """Crear/editar/eliminar catálogos: solo ADMIN y SUPERVISOR."""
    if current_user.rol not in ("ADMIN", "SUPERVISOR"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No tiene permisos para gestionar catálogos",
        )
    return current_user


async def require_admin(
    current_user: Usuario = Depends(get_current_user),
) -> Usuario:
    """Balanzas y usuarios: solo ADMIN."""
    if current_user.rol != "ADMIN":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Se requiere rol ADMIN",
        )
    return current_user


def to_user_out(user: Usuario) -> UserOut:
    return UserOut(
        id_usuario=user.id_usuario,
        nombre=user.nombre,
        email=user.email,
        rol=user.rol,
    )
