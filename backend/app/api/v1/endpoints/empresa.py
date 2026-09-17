"""Perfil de la empresa local: datos de contacto y logo.

La empresa local (una por máquina) espeja la cuenta del servidor. Los campos
editables (nombre fiscal/comercial, RIF, dirección, teléfono, email, logo)
solo los modifica el ADMIN. El logo se sube por ``POST /api/v1/files/upload``
y aquí solo se persiste la URL relativa devuelta.
"""

from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user
from app.core.database import get_db
from app.models import Empresa, Usuario
from app.schemas import EmpresaPerfilOut, EmpresaPerfilUpdate

router = APIRouter(prefix="/api/v1/empresa", tags=["Empresa"])


@router.get("", response_model=EmpresaPerfilOut)
async def get_empresa_perfil(
    _user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
) -> Empresa:
    """Perfil de la empresa de la sesión (cualquier rol autenticado)."""
    return empresa


@router.put("", response_model=EmpresaPerfilOut)
async def update_empresa_perfil(
    payload: EmpresaPerfilUpdate,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> Empresa:
    """Actualiza el perfil empresarial (solo ADMIN)."""
    if current_user.rol != "ADMIN":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo el ADMIN puede editar el perfil de la empresa.",
        )
    for campo, valor in payload.model_dump(exclude_unset=True).items():
        setattr(empresa, campo, valor)
    empresa.updated_at = datetime.now(UTC).replace(tzinfo=None)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El RIF/NIT ya está registrado en otra empresa.",
        ) from None
    await db.refresh(empresa)
    return empresa
