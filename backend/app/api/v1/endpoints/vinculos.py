from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user, require_admin
from app.core.database import get_db
from app.models import Balanza, Empresa, Indicador, Usuario, VinculoBalanzaIndicador
from app.schemas.vinculos import VinculoCreate, VinculoOut
from app.services.vinculo_service import VINCULO_MGR

router = APIRouter(prefix="/api/v1/vinculos", tags=["vinculos"])

@router.post("", response_model=VinculoOut, dependencies=[Depends(require_admin)])
async def crear_vinculo(
    payload: VinculoCreate,
    request: Request,
    empresa: Empresa = Depends(get_current_empresa),
    current_user: Usuario = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res_b = await db.execute(
        select(Balanza).where(Balanza.id_balanza == payload.id_bascula, Balanza.id_empresa == empresa.id_empresa)
    )
    bal = res_b.scalar_one_or_none()
    res_i = await db.execute(
        select(Indicador).where(Indicador.id_indicador == payload.id_indicador, Indicador.id_empresa == empresa.id_empresa)
    )
    ind = res_i.scalar_one_or_none()
    if not bal or not ind:
        raise HTTPException(status_code=404, detail="Báscula o indicador no encontrado")

    # Evitar duplicados
    res_dup_b = await db.execute(
        select(VinculoBalanzaIndicador).where(
            VinculoBalanzaIndicador.id_empresa == empresa.id_empresa,
            VinculoBalanzaIndicador.id_bascula == payload.id_bascula,
            VinculoBalanzaIndicador.activo.is_(True),
        )
    )
    if res_dup_b.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Esta báscula ya tiene un indicador vinculado")

    res_cnt = await db.execute(
        select(VinculoBalanzaIndicador).where(
            VinculoBalanzaIndicador.id_empresa == empresa.id_empresa,
            VinculoBalanzaIndicador.activo.is_(True),
        )
    )
    activos = res_cnt.scalars().all()
    if len(activos) >= 2:
        raise HTTPException(status_code=400, detail="Solo se permiten hasta 2 vínculos activos")

    vinc = VinculoBalanzaIndicador(
        id_empresa=empresa.id_empresa,
        id_bascula=payload.id_bascula,
        id_indicador=payload.id_indicador,
        activo=True,
    )
    db.add(vinc)
    await db.commit()
    await db.refresh(vinc)
    try:
        await VINCULO_MGR.iniciar(db, empresa.id_empresa, vinc)
    except Exception:
        pass
    return vinc


@router.get("", response_model=list[VinculoOut])
async def listar_vinculos(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(select(VinculoBalanzaIndicador).where(VinculoBalanzaIndicador.id_empresa == empresa.id_empresa))
    return res.scalars().all()


@router.put("/{id_vinculo}/activar", response_model=VinculoOut, dependencies=[Depends(require_admin)])
async def activar_vinculo(
    id_vinculo: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        select(VinculoBalanzaIndicador).where(
            VinculoBalanzaIndicador.id_vinculo == id_vinculo,
            VinculoBalanzaIndicador.id_empresa == empresa.id_empresa,
        )
    )
    vinc = res.scalar_one_or_none()
    if not vinc:
        raise HTTPException(status_code=404, detail="Vínculo no encontrado")

    if not vinc.activo:
        vinc.activo = True
        await db.commit()
        await db.refresh(vinc)

    try:
        await VINCULO_MGR.iniciar(db, empresa.id_empresa, vinc)
    except Exception:
        pass
    return vinc


@router.delete("/{id_vinculo}", dependencies=[Depends(require_admin)])
async def eliminar_vinculo(
    id_vinculo: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        select(VinculoBalanzaIndicador).where(
            VinculoBalanzaIndicador.id_vinculo == id_vinculo,
            VinculoBalanzaIndicador.id_empresa == empresa.id_empresa,
        )
    )
    vinc = res.scalar_one_or_none()
    if not vinc:
        raise HTTPException(status_code=404, detail="Vínculo no encontrado")
    try:
        await VINCULO_MGR.detener(vinc.id_vinculo)
    except Exception:
        pass
    await db.delete(vinc)
    await db.commit()
    return {"ok": True}
