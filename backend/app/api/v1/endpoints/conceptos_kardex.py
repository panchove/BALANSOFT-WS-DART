
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.core.database import get_db
from app.models import ConceptoKardex, Kardex, Usuario
from app.schemas import ConceptoKardexCreate, ConceptoKardexOut, ConceptoKardexUpdate

router = APIRouter(prefix="/api/v1/conceptos-kardex", tags=["Conceptos Kardex"])


async def require_admin(current: Usuario = Depends(get_current_user)):
    if current.rol != "ADMIN":
        from fastapi import HTTPException, status
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Solo administradores")
    return current


@router.get("", response_model=list[ConceptoKardexOut])
async def listar(
    activo: bool | None = Query(default=None),
    signo: str | None = Query(default=None, pattern="^(inicial|positivo|negativo)$"),
    db: AsyncSession = Depends(get_db),
    current: Usuario = Depends(get_current_user),
):
    stmt = select(ConceptoKardex).where(ConceptoKardex.id_empresa == current.id_empresa)
    if activo is not None:
        stmt = stmt.where(ConceptoKardex.activo == activo)
    if signo is not None:
        stmt = stmt.where(ConceptoKardex.signo == signo)
    stmt = stmt.order_by(ConceptoKardex.id_concepto)
    res = await db.execute(stmt)
    return res.scalars().all()


@router.post("", response_model=ConceptoKardexOut, status_code=status.HTTP_201_CREATED)
async def crear(
    data: ConceptoKardexCreate,
    db: AsyncSession = Depends(get_db),
    current: Usuario = Depends(require_admin),
):
    if data.id_concepto in (0, 10, 60):
        raise HTTPException(status_code=409, detail="Los conceptos del sistema (0, 10, 60) no pueden crearse manualmente")
    # Validar coherencia con rango
    if data.id_concepto == 0 and data.signo != "inicial":
        raise HTTPException(status_code=422, detail="El concepto 0 debe tener signo 'inicial'")
    if 1 <= data.id_concepto <= 49 and data.signo != "positivo":
        raise HTTPException(status_code=422, detail="Los conceptos 1-49 deben tener signo 'positivo'")
    if 50 <= data.id_concepto <= 99 and data.signo != "negativo":
        raise HTTPException(status_code=422, detail="Los conceptos 50-99 deben tener signo 'negativo'")
    existe = await db.execute(
        select(ConceptoKardex).where(
            ConceptoKardex.id_empresa == current.id_empresa,
            ConceptoKardex.id_concepto == data.id_concepto,
        )
    )
    if existe.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Ya existe un concepto con ese ID")
    obj = ConceptoKardex(
        id_concepto=data.id_concepto,
        id_empresa=current.id_empresa,
        nombre=data.nombre,
        descripcion=data.descripcion,
        signo=data.signo,
        es_sistema=False,
        activo=data.activo,
        aplica_a=data.aplica_a,
    )
    db.add(obj)
    await db.commit()
    await db.refresh(obj)
    return obj


@router.put("/{id_concepto}", response_model=ConceptoKardexOut)
async def actualizar(
    id_concepto: int,
    data: ConceptoKardexUpdate,
    db: AsyncSession = Depends(get_db),
    current: Usuario = Depends(require_admin),
):
    res = await db.execute(
        select(ConceptoKardex).where(
            ConceptoKardex.id_empresa == current.id_empresa,
            ConceptoKardex.id_concepto == id_concepto,
        )
    )
    obj = res.scalar_one_or_none()
    if not obj:
        raise HTTPException(status_code=404, detail="Concepto no encontrado")
    if data.signo is not None and data.signo != obj.signo:
        # El signo es derivado del rango del ID (0=inicial, 1-49=positivo,
        # 50-99=negativo): cambiarlo rompería la coherencia del kardex.
        raise HTTPException(
            status_code=422,
            detail=(
                "El signo del concepto no se puede modificar: lo determina el rango "
                "del ID (0=inicial, 1-49=positivo, 50-99=negativo)"
            ),
        )
    if obj.es_sistema and (data.aplica_a is not None or data.nombre is not None):
        # Los conceptos del sistema conservan su semántica de negocio: solo se
        # permite renombrar/describir y activar o desactivar.
        pass
    if data.nombre is not None:
        obj.nombre = data.nombre
    if data.descripcion is not None:
        obj.descripcion = data.descripcion
    if data.activo is not None:
        obj.activo = data.activo
    if data.aplica_a is not None:
        obj.aplica_a = data.aplica_a
    await db.commit()
    await db.refresh(obj)
    return obj


@router.delete("/{id_concepto}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(
    id_concepto: int,
    db: AsyncSession = Depends(get_db),
    current: Usuario = Depends(require_admin),
):
    if id_concepto in (0, 10, 60):
        raise HTTPException(status_code=409, detail="Los conceptos del sistema no pueden eliminarse")
    res = await db.execute(
        select(ConceptoKardex).where(
            ConceptoKardex.id_empresa == current.id_empresa,
            ConceptoKardex.id_concepto == id_concepto,
        )
    )
    obj = res.scalar_one_or_none()
    if not obj:
        raise HTTPException(status_code=404, detail="Concepto no encontrado")
    if obj.es_sistema:
        raise HTTPException(status_code=409, detail="Los conceptos del sistema no pueden eliminarse")
    # Verificar si tiene movimientos
    cnt = await db.execute(
        select(func.count()).select_from(Kardex).where(
            Kardex.id_empresa == current.id_empresa,
            Kardex.id_movimiento == id_concepto,
        )
    )
    if cnt.scalar() or 0 > 0:
        raise HTTPException(status_code=409, detail="El concepto tiene movimientos en kardex. Desactívelo en su lugar.")
    await db.delete(obj)
    await db.commit()
    return None
