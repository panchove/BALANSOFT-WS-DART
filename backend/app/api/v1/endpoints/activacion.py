"""Endpoints de llaves de activación (un solo uso) para estaciones OPERADOR.

- ``POST /activacion/llaves``  — el ADMIN emite la llave de un usuario local.
- ``POST /activacion/validar`` — el instalador de la estación cliente la canjea
  (sin autenticación: todavía no existe sesión en esa máquina).

La lógica vive en ``app/services/llave_activacion_service.py``.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user
from app.core.database import get_db
from app.models import Empresa, Usuario
from app.schemas import (
    LlaveActivacionCreateRequest,
    LlaveActivacionCreateResponse,
    LlaveActivacionValidarRequest,
    LlaveActivacionValidarResponse,
)
from app.services import llave_activacion_service as llaves

router = APIRouter(prefix="/api/v1/activacion", tags=["Activación"])


@router.post(
    "/llaves",
    response_model=LlaveActivacionCreateResponse,
    status_code=status.HTTP_201_CREATED,
)
async def crear_llave(
    datos: LlaveActivacionCreateRequest,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> LlaveActivacionCreateResponse:
    """Emite una llave de activación de un solo uso (solo ADMIN)."""
    if current_user.rol != "ADMIN":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo el ADMIN puede generar llaves de activación",
        )
    llave, codigo = await llaves.crear_llave(
        db,
        empresa=empresa,
        admin=current_user,
        id_usuario=datos.id_usuario,
        expira_horas=datos.expira_horas,
    )
    return LlaveActivacionCreateResponse(
        id=llave.id,
        codigo=codigo,
        codigo_preview=llave.codigo_preview or codigo[-6:],
        expira_en=llave.expira_en,
        mensaje="Código mostrado una sola vez. Compártelo de forma segura.",
    )


@router.post("/validar", response_model=LlaveActivacionValidarResponse)
async def validar_llave(
    datos: LlaveActivacionValidarRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> LlaveActivacionValidarResponse:
    """Canjea la llave y la consume (un solo uso). Sin autenticación."""
    _, usuario, empresa = await llaves.validar_y_consumir(
        db,
        codigo=datos.codigo,
        hardware_id=datos.hardware_id,
        ip=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )
    return LlaveActivacionValidarResponse(
        usuario_email=usuario.email,
        empresa_nombre=empresa.nombre_fiscal,
        mensaje="Código válido. Instalación autorizada.",
    )
