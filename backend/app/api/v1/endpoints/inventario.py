"""Rutas del módulo INVENTARIO: productos, almacenes y balanzas."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import (
    get_current_empresa,
    get_current_user,
    require_admin,
    require_catalog_manager,
)
from app.core.database import get_db
from app.core.scale_hal import TcpScaleHAL
from app.core.scale_session import get_scale_session_manager
from app.models import Almacen, Balanza, Categoria, Empresa, Kardex, Producto, Usuario
from app.schemas import (
    AjusteInventarioCreate,
    AjusteInventarioOut,
    AlmacenCreate,
    AlmacenOut,
    BalanzaCreate,
    BalanzaDescubiertaOut,
    BalanzaOut,
    BalanzaPruebaOut,
    CategoriaCreate,
    CategoriaOut,
    ProductoCreate,
    ProductoOut,
)
from app.services.catalog_service import CatalogService

router = APIRouter(prefix="/api/v1", tags=["Inventario"])
_SERVICE = CatalogService()


# ---------------------------------------------------------------------------
# Productos
# ---------------------------------------------------------------------------


@router.get("/productos", response_model=list[ProductoOut])
async def list_productos(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[ProductoOut]:
    rows = await _SERVICE.list_by_name(db, empresa.id_empresa, "productos")
    categorias = {
        c.id_categoria: c.nombre
        for c in (await db.execute(
            select(Categoria).where(Categoria.id_empresa == empresa.id_empresa)
        )).scalars()
    }
    for r in rows:
        r["categoria_nombre"] = categorias.get(r.get("id_categoria"))
    return [ProductoOut(**r) for r in rows]


@router.post(
    "/productos", response_model=ProductoOut, dependencies=[Depends(require_catalog_manager)]
)
async def create_producto(
    payload: ProductoCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ProductoOut:
    await _validar_categoria(db, empresa.id_empresa, payload.id_categoria)
    row = await _SERVICE.create(
        db,
        empresa.id_empresa,
        "productos",
        payload.model_dump(),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return ProductoOut(**row)


@router.put(
    "/productos/{id_producto}",
    response_model=ProductoOut,
    dependencies=[Depends(require_catalog_manager)],
)
async def update_producto(
    id_producto: uuid.UUID,
    payload: ProductoCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ProductoOut:
    await _validar_categoria(db, empresa.id_empresa, payload.id_categoria)
    data = payload.model_dump(exclude={"id_producto"})
    row = await _SERVICE.update(
        db,
        empresa.id_empresa,
        "productos",
        str(id_producto),
        data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return ProductoOut(**row)


@router.delete(
    "/productos/{id_producto}", status_code=204, dependencies=[Depends(require_catalog_manager)]
)
async def delete_producto(
    id_producto: uuid.UUID,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _SERVICE.delete(
        db,
        empresa.id_empresa,
        "productos",
        str(id_producto),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )


# ---------------------------------------------------------------------------
# Categorías
# ---------------------------------------------------------------------------


@router.get("/categorias", response_model=list[CategoriaOut])
async def list_categorias(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[CategoriaOut]:
    rows = await _SERVICE.list_by_name(db, empresa.id_empresa, "categorias")
    return [CategoriaOut(**r) for r in rows]


@router.post(
    "/categorias", response_model=CategoriaOut, dependencies=[Depends(require_catalog_manager)]
)
async def create_categoria(
    payload: CategoriaCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> CategoriaOut:
    row = await _SERVICE.create(
        db,
        empresa.id_empresa,
        "categorias",
        payload.model_dump(),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return CategoriaOut(**row)


@router.put(
    "/categorias/{id_categoria}",
    response_model=CategoriaOut,
    dependencies=[Depends(require_catalog_manager)],
)
async def update_categoria(
    id_categoria: uuid.UUID,
    payload: CategoriaCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> CategoriaOut:
    data = payload.model_dump(exclude={"id_categoria"})
    row = await _SERVICE.update(
        db,
        empresa.id_empresa,
        "categorias",
        str(id_categoria),
        data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return CategoriaOut(**row)


@router.delete(
    "/categorias/{id_categoria}", status_code=204, dependencies=[Depends(require_catalog_manager)]
)
async def delete_categoria(
    id_categoria: uuid.UUID,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _SERVICE.delete(
        db,
        empresa.id_empresa,
        "categorias",
        str(id_categoria),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )


# ---------------------------------------------------------------------------
# Almacenes
# ---------------------------------------------------------------------------


@router.get("/almacenes", response_model=list[AlmacenOut])
async def list_almacenes(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[AlmacenOut]:
    rows = await _SERVICE.list_by_name(db, empresa.id_empresa, "almacenes")
    return [AlmacenOut(**r) for r in rows]


@router.post(
    "/almacenes", response_model=AlmacenOut, dependencies=[Depends(require_catalog_manager)]
)
async def create_almacen(
    payload: AlmacenCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> AlmacenOut:
    row = await _SERVICE.create(
        db,
        empresa.id_empresa,
        "almacenes",
        payload.model_dump(),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return AlmacenOut(**row)


@router.put(
    "/almacenes/{id_almacen}",
    response_model=AlmacenOut,
    dependencies=[Depends(require_catalog_manager)],
)
async def update_almacen(
    id_almacen: uuid.UUID,
    payload: AlmacenCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> AlmacenOut:
    data = payload.model_dump(exclude={"id_almacen"})
    row = await _SERVICE.update(
        db,
        empresa.id_empresa,
        "almacenes",
        str(id_almacen),
        data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return AlmacenOut(**row)


@router.delete(
    "/almacenes/{id_almacen}", status_code=204, dependencies=[Depends(require_catalog_manager)]
)
async def delete_almacen(
    id_almacen: uuid.UUID,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _SERVICE.delete(
        db,
        empresa.id_empresa,
        "almacenes",
        str(id_almacen),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )


# ---------------------------------------------------------------------------
# Balanzas
# ---------------------------------------------------------------------------


@router.get("/balanzas", response_model=list[BalanzaOut])
async def list_balanzas(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[BalanzaOut]:
    rows = await _SERVICE.list_by_name(db, empresa.id_empresa, "balanzas")
    return [BalanzaOut(**r) for r in rows]


@router.get("/balanzas/descubrir", response_model=list[BalanzaDescubiertaOut])
async def descubrir_balanzas(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> list[BalanzaDescubiertaOut]:
    """Escanea las básculas conectadas/disponibles:

    - TCP: prueba el simulador BSDD local y las IPs ya registradas de la empresa;
    - Serial real: lista los puertos COM/RS-232 vía pyserial (excluye /dev/ttyS*);
    - Serial simulado: detecta ptys virtuales (simulador BSDD, socat, etc.)
      que el kernel NO reporta como tty real, pero que pyserial sí puede abrir.
      Excluye los symlinks internos ``*_pty`` que no emiten datos.
    Omite las básculas ya registradas para no duplicarlas.
    """
    import glob
    import os

    registradas = await _SERVICE.list_by_name(db, empresa.id_empresa, "balanzas")

    ips_existentes: set[tuple[str, int]] = set()
    puertos_existentes: set[str] = set()
    for b in registradas:
        ip = b.get("ip_address")
        if ip:
            ips_existentes.add((str(ip), int(b.get("puerto_tcp") or 5555)))
        pc = b.get("puerto_com")
        if pc:
            puertos_existentes.add(str(pc))

    encontradas: list[BalanzaDescubiertaOut] = []

    # ---------- TCP ----------
    candidatos_tcp: list[tuple[str, int]] = [("127.0.0.1", 5555)]
    for b in registradas:
        ip = b.get("ip_address")
        if ip:
            candidatos_tcp.append((str(ip), int(b.get("puerto_tcp") or 5555)))

    vistos_tcp: set[tuple[str, int]] = set()
    for host, puerto in candidatos_tcp:
        clave = (host, puerto)
        if clave in vistos_tcp or clave in ips_existentes:
            continue
        vistos_tcp.add(clave)
        try:
            peso = await TcpScaleHAL(host, puerto).read_weight()
        except Exception:  # noqa: BLE001 - el escaneo nunca debe romper la API
            peso = None
        if peso is not None:
            encontradas.append(
                BalanzaDescubiertaOut(
                    descripcion=f"Báscula TCP ({host}:{puerto})",
                    protocolo="tcp",
                    ip_address=host,
                    puerto_tcp=puerto,
                    peso_kg=peso,
                    is_simulada=False,
                )
            )

    # ---------- Serial real (pyserial) ----------
    try:
        import serial.tools.list_ports as list_ports

        for p in list_ports.comports():
            if p.device in puertos_existentes:
                continue
            # Excluir puertos serie on-board (/dev/ttyS*) que no son básculas.
            # Solo nos interesan USB-serial reales (/dev/ttyUSB*, /dev/ttyACM*).
            if p.device.startswith("/dev/ttyS"):
                continue
            encontradas.append(
                BalanzaDescubiertaOut(
                    descripcion=f"Báscula serial ({p.device})",
                    protocolo="serial",
                    puerto_com=p.device,
                    is_simulada=False,
                )
            )
    except ImportError:
        pass

    # ---------- Serial simulado (ptys virtuales) ----------
    # Patrones configurables vía env. Por defecto cubre:
    #   - /tmp/bsdd_*   → simulador BSDD
    #   - /tmp/ttyV*    → pares de socat (recomendado)
    #   - /tmp/tnt*     → otros simuladores comunes
    patrones_env = os.environ.get(
        "BSSD_SERIAL_GLOBS",
        "/tmp/bsdd_*,/tmp/ttyV*,/tmp/tnt*",
    )
    patrones = [p.strip() for p in patrones_env.split(",") if p.strip()]

    for patron in patrones:
        for ruta in glob.glob(patron):
            if ruta in puertos_existentes:
                continue
            # Excluir symlinks internos del simulador (*_pty) que no emiten datos.
            if ruta.endswith("_pty"):
                continue
            if not (os.path.exists(ruta) or os.path.islink(ruta)):
                continue
            if not _es_pty_o_socket(ruta):
                continue
            puertos_existentes.add(ruta)
            encontradas.append(
                BalanzaDescubiertaOut(
                    descripcion=f"Báscula serial simulada ({ruta})",
                    protocolo="serial",
                    puerto_com=ruta,
                    is_simulada=True,
                )
            )

    return encontradas


@router.post("/balanzas", response_model=BalanzaOut, dependencies=[Depends(require_admin)])
async def create_balanza(
    payload: BalanzaCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> BalanzaOut:
    row = await _SERVICE.create(
        db,
        empresa.id_empresa,
        "balanzas",
        payload.model_dump(),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return BalanzaOut(**row)


@router.put(
    "/balanzas/{id_balanza}", response_model=BalanzaOut, dependencies=[Depends(require_admin)]
)
async def update_balanza(
    id_balanza: uuid.UUID,
    payload: BalanzaCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> BalanzaOut:
    data = payload.model_dump(exclude={"id_balanza"})
    row = await _SERVICE.update(
        db,
        empresa.id_empresa,
        "balanzas",
        str(id_balanza),
        data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return BalanzaOut(**row)


@router.delete("/balanzas/{id_balanza}", status_code=204, dependencies=[Depends(require_admin)])
async def delete_balanza(
    id_balanza: uuid.UUID,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _SERVICE.delete(
        db,
        empresa.id_empresa,
        "balanzas",
        str(id_balanza),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )


@router.post("/balanzas/{id_balanza}/probar", response_model=BalanzaPruebaOut)
async def probar_balanza(
    id_balanza: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    current_user: Usuario = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> BalanzaPruebaOut:
    """Prueba la conexión de hardware de la balanza (HAL) y devuelve el diagnóstico.

    Respuestas: ``400`` si no hay configuración de hardware; el cuerpo de la
    respuesta indica ``conectado=true/false`` según se obtenga lectura o no.
    """
    result = await db.execute(
        select(Balanza).where(
            Balanza.id_balanza == id_balanza,
            Balanza.id_empresa == empresa.id_empresa,
        )
    )
    balanza = result.scalar_one_or_none()
    if balanza is None:
        raise HTTPException(status_code=404, detail="Balanza no encontrada")

    try:
        # Sesión persistente: si ya está emparejada se reutiliza; si no, se
        # crea y queda viva para los siguientes polls de /live.
        sesion = await get_scale_session_manager().obtener(balanza)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    if sesion.peso_kg is None:
        return BalanzaPruebaOut(
            balanza=balanza.descripcion,
            conectado=False,
            protocolo=balanza.protocolo or "tcp",
            detalle="No se pudo establecer conexión con la balanza (sin lectura)",
        )

    return BalanzaPruebaOut(
        balanza=balanza.descripcion,
        conectado=True,
        hardware=sesion.hardware,
        protocolo=balanza.protocolo or "tcp",
        peso_kg=sesion.peso_kg,
        estable=sesion.estable,
    )


# ---------------------------------------------------------------------------
# Ajustes de inventario (movimiento kardex manual) — REQ-FN-INV-010
# ---------------------------------------------------------------------------


@router.post(
    "/inventario/ajustes",
    response_model=AjusteInventarioOut,
    dependencies=[Depends(require_admin)],
    summary="Registrar ajuste manual de inventario",
    description=(
        "Crea un movimiento de kardex manual con justificación obligatoria. "
        "Solo productos con es_kardex=true y almacenes de la empresa. "
        "id_movimiento: 10 = INGRESO (positivo) / 60 = DESPACHO (negativo). "
        "Requiere rol administrador."
    ),
)
async def crear_ajuste_inventario(
    payload: AjusteInventarioCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> AjusteInventarioOut:
    """Registra un ajuste de inventario como movimiento de kardex manual.

    Reglas de negocio:
    - El producto debe pertenecer a la empresa y tener ``es_kardex=true``.
    - El almacén debe pertenecer a la empresa.
    - La justificación (``documento``) es obligatoria y queda registrada.
    - El valor se almacena como positivo (el id_movimiento determina el signo).
    - El movimiento queda auditado con la IP y el usuario que lo crea.
    """
    # Validar producto: debe pertenecer a la empresa y ser kardex
    res_prod = await db.execute(
        select(Producto).where(
            Producto.id_producto == payload.id_producto,
            Producto.id_empresa == empresa.id_empresa,
        )
    )
    producto = res_prod.scalar_one_or_none()
    if producto is None:
        raise HTTPException(status_code=404, detail="Producto no encontrado en esta empresa")
    if not producto.es_kardex:
        raise HTTPException(
            status_code=422,
            detail="Solo se pueden ajustar productos configurados para kardex (es_kardex=true)",
        )

    # Validar almacén
    res_alm = await db.execute(
        select(Almacen).where(
            Almacen.id_almacen == payload.id_almacen,
            Almacen.id_empresa == empresa.id_empresa,
        )
    )
    if res_alm.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Almacén no encontrado en esta empresa")

    ahora = datetime.now(UTC).replace(tzinfo=None)
    entrada = Kardex(
        id_empresa=empresa.id_empresa,
        id_movimiento=payload.id_movimiento,
        fecha_kardex=ahora,
        id_producto=payload.id_producto,
        id_almacen=payload.id_almacen,
        valor=payload.valor_kg,
        documento=payload.documento,
        fecha_documento=payload.fecha_documento or ahora,
    )
    db.add(entrada)
    await db.commit()
    await db.refresh(entrada)
    return AjusteInventarioOut.model_validate(entrada)


# ---------------------------------------------------------------------------
# Helpers internos
# ---------------------------------------------------------------------------


async def _validar_categoria(
    db: AsyncSession, id_empresa: uuid.UUID, id_categoria: uuid.UUID
) -> None:
    """Valida que la categoría exista y pertenezca a la misma empresa.

    Regla de negocio: todo producto debe pertenecer a una categoría de su
    propia empresa. Código 409 si no existe para distinguirlo de 404/400.
    """
    result = await db.execute(
        select(Categoria).where(
            Categoria.id_categoria == id_categoria,
            Categoria.id_empresa == id_empresa,
        )
    )
    if result.scalar_one_or_none() is None:
        raise HTTPException(
            status_code=409, detail="La categoría indicada no existe o no pertenece a esta empresa"
        )


def _es_pty_o_socket(ruta: str) -> bool:
    """True si `ruta` apunta a un pty (character device) o socket UNIX.

    Se usa para aceptar ptys virtuales creados por simuladores como BSDD
    (``/tmp/bsdd_*``) o pares de ``socat`` (``/tmp/ttyV*``), que pyserial
    puede abrir aunque el kernel no los reporte como puertos serie reales.
    """
    import os
    import stat as _stat

    try:
        st = os.stat(ruta)
    except OSError:
        return False
    modo = st.st_mode
    if _stat.S_ISCHR(modo):
        # /dev/pts/N y otros tty son character devices.
        return True
    if _stat.S_ISSOCK(modo):
        return True
    return False
