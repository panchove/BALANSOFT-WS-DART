"""Rutas del módulo SEMÁFORO: torre de 3 luces como dispositivo actuador.

El semáforo **no** mide: obedece. Esta app decide el LED a partir del peso en
vivo de la báscula vinculada y del estado del boleto (``docs/SEMAFORO.md``), y
el ``SemaforoController`` (``app/services/semaforo_service.py``) mantiene viva la
decisión. Estas rutas son la superficie de **configuración** (CRUD), de
**descubrimiento** (simulador BSDD o hardware real), de **diagnóstico**
(``probar``/``estado``) y de **comando manual** (banco de pruebas y override).

Canales soportados (SPEC del simulador BSDD):

- HTTP/REST (Fase 2): ``127.0.0.1:8080/api/semaforo``.
- USB serie CDC-ACM (Fase 3): ``/dev/bsdd_semaforo_acm``.
"""

from __future__ import annotations

import glob
import os
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import (
    get_current_empresa,
    get_current_user,
    require_admin,
)
from app.core.database import get_db
from app.core.semaforo_hal import (
    HttpSemaforoHAL,
    SemaforoHAL,
    SerialSemaforoHAL,
    get_semaforo_hal,
    normalizar_comando,
)
from app.models import Balanza, Empresa, Semaforo, Usuario
from app.schemas import (
    SemaforoAutomaticoIn,
    SemaforoComandoIn,
    SemaforoComandoOut,
    SemaforoCreate,
    SemaforoDescubiertoOut,
    SemaforoEstadoOut,
    SemaforoOut,
    SemaforoPruebaOut,
)
from app.services.audit_service import registrar
from app.services.catalog_service import CatalogService

router = APIRouter(prefix="/api/v1", tags=["Semáforos"])
_SERVICE = CatalogService()

#: Endpoint del simulador BSDD (Fase 2, HTTP/REST) y dispositivo serie (Fase 3).
_BSDD_HOST = "127.0.0.1"
_BSDD_PUERTO = 8080
_BSDD_SERIAL = "/dev/bsdd_semaforo_acm"


async def _obtener_semaforo(
    db: AsyncSession, empresa: Empresa, id_semaforo: uuid.UUID
) -> Semaforo:
    """Carga un semáforo de la empresa (404 si no existe) — aislamiento tenant."""
    result = await db.execute(
        select(Semaforo).where(
            Semaforo.id_semaforo == id_semaforo,
            Semaforo.id_empresa == empresa.id_empresa,
        )
    )
    semaforo = result.scalar_one_or_none()
    if semaforo is None:
        raise HTTPException(status_code=404, detail="Semáforo no encontrado")
    return semaforo


async def _validar_config(db: AsyncSession, empresa: Empresa, data: dict) -> dict:
    """Normaliza y valida la configuración de hardware antes de persistirla."""
    protocolo = (data.get("protocolo") or "http").lower()
    data["protocolo"] = protocolo

    if protocolo == "serial":
        if not (data.get("puerto_com") or "").strip():
            raise HTTPException(
                status_code=400,
                detail="Un semáforo serial necesita el puerto (p. ej. /dev/bsdd_semaforo_acm)",
            )
        data["puerto_com"] = str(data["puerto_com"]).strip()
        data["ip_address"] = None
        data["puerto_tcp"] = None
    else:
        data["ip_address"] = (data.get("ip_address") or _BSDD_HOST).strip()
        data["puerto_tcp"] = int(data.get("puerto_tcp") or _BSDD_PUERTO)
        data["puerto_com"] = None

    id_balanza = data.get("id_balanza")
    if id_balanza is not None:
        existe = (
            await db.execute(
                select(Balanza.id_balanza).where(
                    Balanza.id_balanza == id_balanza,
                    Balanza.id_empresa == empresa.id_empresa,
                )
            )
        ).scalar_one_or_none()
        if existe is None:
            raise HTTPException(status_code=404, detail="Báscula no encontrada")
    elif data.get("control_automatico"):
        raise HTTPException(
            status_code=400,
            detail=(
                "El control automático necesita una báscula vinculada "
                "(id_balanza) de la que leer peso y estabilidad"
            ),
        )
    return data


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------


@router.get("/semaforos", response_model=list[SemaforoOut])
async def list_semaforos(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
    q: str | None = Query(None, description="Búsqueda de texto (código, descripción, IP/puerto)."),
    activo: bool | None = Query(None, description="Filtra por semáforos activos/inactivos."),
    is_simulado: bool | None = Query(None, description="Filtra por semáforos simulados/reales."),
    protocolo: str | None = Query(None, description="Filtra por protocolo (http/serial)."),
    control_automatico: bool | None = Query(None, description="Filtra por control automático activo/inactivo."),
) -> list[SemaforoOut]:
    """Lista los semáforos de la empresa con **filtros de vista** opcionales."""
    rows = await _SERVICE.list_filtrado(
        db,
        empresa.id_empresa,
        "semaforos",
        q=q,
        columnas_texto=("codigo", "descripcion", "ip_address", "puerto_com"),
        iguales={
            "activo": activo,
            "is_simulado": is_simulado,
            "protocolo": protocolo,
            "control_automatico": control_automatico,
        },
    )
    return [SemaforoOut(**r) for r in rows]


@router.post("/semaforos", response_model=SemaforoOut, dependencies=[Depends(require_admin)])
async def create_semaforo(
    payload: SemaforoCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> SemaforoOut:
    data = await _validar_config(db, empresa, payload.model_dump())
    row = await _SERVICE.create(
        db,
        empresa.id_empresa,
        "semaforos",
        data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    if data.get("control_automatico") and data.get("id_balanza"):
        from app.services.semaforo_service import get_semaforo_controller

        await get_semaforo_controller().asegurar(row["id_semaforo"])
    return SemaforoOut(**row)


@router.put(
    "/semaforos/{id_semaforo}",
    response_model=SemaforoOut,
    dependencies=[Depends(require_admin)],
)
async def update_semaforo(
    id_semaforo: uuid.UUID,
    payload: SemaforoCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> SemaforoOut:
    await _obtener_semaforo(db, empresa, id_semaforo)
    data = await _validar_config(db, empresa, payload.model_dump())
    row = await _SERVICE.update(
        db,
        empresa.id_empresa,
        "semaforos",
        str(id_semaforo),
        data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    from app.services.semaforo_service import get_semaforo_controller

    controller = get_semaforo_controller()
    # La configuración cambió: se reinicia el vigilante con los valores nuevos.
    await controller.detener(id_semaforo)
    if data.get("control_automatico") and data.get("id_balanza"):
        await controller.asegurar(id_semaforo)
    return SemaforoOut(**row)


@router.delete(
    "/semaforos/{id_semaforo}", status_code=204, dependencies=[Depends(require_admin)]
)
async def delete_semaforo(
    id_semaforo: uuid.UUID,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _obtener_semaforo(db, empresa, id_semaforo)
    await _SERVICE.delete(
        db,
        empresa.id_empresa,
        "semaforos",
        str(id_semaforo),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    from app.services.semaforo_service import get_semaforo_controller

    await get_semaforo_controller().detener(id_semaforo)


# ---------------------------------------------------------------------------
# Descubrimiento
# ---------------------------------------------------------------------------


def _es_pty_o_socket(ruta: str) -> bool:
    """True si ``ruta`` es un pty, un socket o un carácter de dispositivo."""
    try:
        import stat

        modo = os.stat(ruta).st_mode
        return (
            stat.S_ISCHR(modo)
            or stat.S_ISFIFO(modo)
            or stat.S_ISSOCK(modo)
        )
    except OSError:
        return False


async def _probar_candidato(protocolo: str, host: str | None, puerto: int | None, com: str | None):
    """Devuelve ``(activo, estado)`` al probar un candidato a semáforo."""
    try:
        hal: SemaforoHAL
        if protocolo == "serial":
            hal = SerialSemaforoHAL(str(com), timeout=0.6)
        else:
            hal = HttpSemaforoHAL(str(host), int(puerto or _BSDD_PUERTO), timeout=1.5)
        estado = await hal.leer_estado()
    except Exception:  # noqa: BLE001 - el escaneo nunca debe romper la API
        estado = None
    return (estado is not None, estado)


@router.get("/semaforos/descubrir", response_model=list[SemaforoDescubiertoOut])
async def descubrir_semaforos(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
    incluir_simulados: bool = Query(
        True,
        description=(
            "Probar también el simulador BSDD (HTTP 127.0.0.1:8080 y serie "
            "/dev/bsdd_semaforo_acm) y los ptys virtuales. Por defecto sí."
        ),
    ),
) -> list[SemaforoDescubiertoOut]:
    """Escanea los semáforos conectados y los que respondan con estado.

    - **HTTP/REST**: prueba el simulador BSDD local (``127.0.0.1:8080``) y las
      direcciones ya registradas por la empresa.
    - **Serie**: prueba ``/dev/bsdd_semaforo_acm`` (BSDD) y los puertos
      USB-serie reales; también ptys/sockets virtuales (socat, simuladores).
    Solo se devuelven los que responden con el JSON de estado del SPEC; las
    direcciones/puertos ya registrados se omiten para no duplicar.
    """
    registrados = await _SERVICE.list_by_name(db, empresa.id_empresa, "semaforos")
    http_existentes: set[tuple[str, int]] = set()
    com_existentes: set[str] = set()
    for s in registrados:
        if s.get("ip_address"):
            http_existentes.add((str(s["ip_address"]), int(s.get("puerto_tcp") or _BSDD_PUERTO)))
        if s.get("puerto_com"):
            com_existentes.add(str(s["puerto_com"]))

    encontrados: list[SemaforoDescubiertoOut] = []

    # ---------- HTTP/REST ----------
    candidatos_http: list[tuple[str, int]] = []
    if incluir_simulados:
        candidatos_http.append((_BSDD_HOST, _BSDD_PUERTO))
    for s in registrados:
        if s.get("ip_address"):
            candidatos_http.append(
                (str(s["ip_address"]), int(s.get("puerto_tcp") or _BSDD_PUERTO))
            )

    vistos_http: set[tuple[str, int]] = set()
    for host, puerto in candidatos_http:
        clave = (host, puerto)
        if clave in vistos_http or clave in http_existentes:
            continue
        vistos_http.add(clave)
        activo, estado = await _probar_candidato("http", host, puerto, None)
        if activo:
            es_simulado = host == _BSDD_HOST and puerto == _BSDD_PUERTO
            encontrados.append(
                SemaforoDescubiertoOut(
                    descripcion=f"Semáforo HTTP ({host}:{puerto})",
                    protocolo="http",
                    ip_address=host,
                    puerto_tcp=puerto,
                    is_simulado=es_simulado,
                    estado=estado,
                )
            )

    # ---------- Serie (BSDD + USB real + ptys virtuales) ----------
    candidatos_serial: list[tuple[str, bool]] = []
    if incluir_simulados:
        candidatos_serial.append((_BSDD_SERIAL, True))
        patrones_env = os.environ.get(
            "BSDD_SEMAFORO_SERIAL_GLOBS",
            "/dev/bsdd_semaforo_*,/tmp/bsdd_semaforo*,/tmp/ttyV*",
        )
        for patron in (p.strip() for p in patrones_env.split(",") if p.strip()):
            for ruta in glob.glob(patron):
                if ruta.endswith("_pty"):
                    continue
                if os.path.exists(ruta) or os.path.islink(ruta):
                    candidatos_serial.append((ruta, True))

    try:
        import serial.tools.list_ports as list_ports

        for p in list_ports.comports():
            if p.device.startswith("/dev/ttyS"):
                continue
            candidatos_serial.append((p.device, False))
    except ImportError:
        pass

    vistos_com: set[str] = set()
    for ruta, es_simulado in candidatos_serial:
        if ruta in vistos_com or ruta in com_existentes:
            continue
        vistos_com.add(ruta)
        if not (os.path.exists(ruta) or os.path.islink(ruta)):
            continue
        if es_simulado and not _es_pty_o_socket(ruta) and not ruta.startswith(_BSDD_SERIAL):
            # Los globs de simulación deben apuntar a pty/socket, no a archivos.
            continue
        activo, estado = await _probar_candidato("serial", None, None, ruta)
        if activo:
            encontrados.append(
                SemaforoDescubiertoOut(
                    descripcion=f"Semáforo serie ({ruta})",
                    protocolo="serial",
                    puerto_com=ruta,
                    is_simulado=es_simulado,
                    estado=estado,
                )
            )

    return encontrados


# ---------------------------------------------------------------------------
# Diagnóstico y control
# ---------------------------------------------------------------------------


@router.post("/semaforos/{id_semaforo}/probar", response_model=SemaforoPruebaOut)
async def probar_semaforo(
    id_semaforo: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> SemaforoPruebaOut:
    """Prueba la conexión del semáforo leyendo su estado publicado (SPEC §3)."""
    semaforo = await _obtener_semaforo(db, empresa, id_semaforo)
    try:
        hal = get_semaforo_hal(semaforo)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    estado = await hal.leer_estado()
    if estado is None:
        return SemaforoPruebaOut(
            semaforo=semaforo.descripcion,
            conectado=False,
            protocolo=semaforo.protocolo or "http",
            detalle=(
                "El semáforo no respondió con su estado. Verifique que esté "
                "encendido y accesible en la dirección/puerto configurados."
            ),
        )
    return SemaforoPruebaOut(
        semaforo=semaforo.descripcion,
        conectado=True,
        protocolo=semaforo.protocolo or "http",
        estado=estado,
        detalle="Conexión correcta",
    )


@router.get("/semaforos/{id_semaforo}/estado", response_model=SemaforoEstadoOut)
async def estado_semaforo(
    id_semaforo: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> SemaforoEstadoOut:
    """Estado del semáforo: el publicado por el equipo + fase/luces de la app."""
    semaforo = await _obtener_semaforo(db, empresa, id_semaforo)

    estado = None
    try:
        hal = get_semaforo_hal(semaforo)
        estado = await hal.leer_estado()
    except ValueError:
        estado = None

    from app.services.semaforo_service import get_semaforo_controller

    controller = get_semaforo_controller()
    luces = controller.luces_actuales(str(id_semaforo))

    return SemaforoEstadoOut(
        semaforo=semaforo.descripcion,
        conectado=estado is not None,
        automatico=bool(semaforo.control_automatico),
        estado=estado,
        fase=controller.fase_actual(str(id_semaforo)),
        luces=luces.como_dict() if luces is not None else None,
        detalle=None if estado is not None else "Sin respuesta del equipo",
    )


@router.post("/semaforos/{id_semaforo}/comando", response_model=SemaforoComandoOut)
async def comando_semaforo(
    id_semaforo: uuid.UUID,
    payload: SemaforoComandoIn,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> SemaforoComandoOut:
    """Envía un comando manual de LED (mismo JSON del SPEC, banco de pruebas)."""
    semaforo = await _obtener_semaforo(db, empresa, id_semaforo)
    datos = payload.model_dump(exclude_none=True)
    datos.pop("automatico", None)  # el modo se cambia con /automatico
    try:
        comando = normalizar_comando(datos)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    from app.services.semaforo_service import get_semaforo_controller

    try:
        aplicado = await get_semaforo_controller().enviar_manual(semaforo, comando)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    await registrar(
        db,
        id_usuario=current_user.id_usuario,
        id_empresa=empresa.id_empresa,
        accion="COMANDO",
        entidad="semaforos",
        entidad_id=str(id_semaforo),
        detalle={"comando": comando, "aplicado": aplicado},
        ip=request.client.host if request.client else None,
    )
    await db.commit()

    return SemaforoComandoOut(
        aplicado=aplicado,
        comando=comando,
        detalle=None if aplicado else "El semáforo no aceptó el comando (sin conexión)",
    )


@router.post("/semaforos/{id_semaforo}/automatico", response_model=SemaforoOut)
async def automatico_semaforo(
    id_semaforo: uuid.UUID,
    payload: SemaforoAutomaticoIn,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> SemaforoOut:
    """Activa/desactiva el control automático (vigilante peso → LED)."""
    semaforo = await _obtener_semaforo(db, empresa, id_semaforo)
    if payload.activo and semaforo.id_balanza is None:
        raise HTTPException(
            status_code=400,
            detail=(
                "El control automático necesita una báscula vinculada; "
                "edite el semáforo y seleccione una."
            ),
        )
    semaforo.control_automatico = payload.activo
    await registrar(
        db,
        id_usuario=current_user.id_usuario,
        id_empresa=empresa.id_empresa,
        accion="AUTOMATICO",
        entidad="semaforos",
        entidad_id=str(id_semaforo),
        detalle={"activo": payload.activo},
        ip=request.client.host if request.client else None,
    )
    await db.commit()
    await db.refresh(semaforo)

    from app.services.semaforo_service import get_semaforo_controller

    controller = get_semaforo_controller()
    if payload.activo:
        await controller.asegurar(id_semaforo)
    else:
        await controller.detener(id_semaforo)

    return SemaforoOut(**{c.key: getattr(semaforo, c.key) for c in semaforo.__table__.columns})
