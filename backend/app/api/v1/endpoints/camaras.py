"""Rutas del módulo CÁMARAS: captura de placa (snapshot IP o cámara local).

La cámara **no** decide: la estación le pide un *frame* y lo guarda como media
del boleto. Estas rutas son la superficie de **configuración** (CRUD), de
**descubrimiento** (``descubrir``), de **diagnóstico** (``probar``/``snapshot``)
y de **captura** por boleto (``capturar``).

Dos clases de cámara (columna ``origen``):

- ``ip``: cámara de red; su JPEG se descarga de ``url_snapshot``.
- ``local``: cámara USB/integrada del equipo; el *frame* lo captura el HAL con
  ``ffmpeg`` a partir de ``dispositivo`` (``/dev/video*`` en Linux).

Reglas del negocio (confirmadas por el cliente):

- Las fotos de placa se piden **una sola vez por boleto**, en la pesada que el
  operador elija (entrada o salida); una vez capturadas no se vuelven a pedir.
- Se guardan como media del boleto (``media/<boleto>/placa_*.jpg``) con fila en
  ``imagenes_pesaje.tipo = 'placa'`` y **nunca** entran al ticket/PDF/TXT.
- La obligatoriedad es configurable por empresa
  (``empresas.fotos_placa_activas`` / ``fotos_placa_obligatorias``).

La configuración de cámaras es **local de la estación** (no se sincroniza).
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from collections.abc import AsyncIterator

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import (
    get_current_empresa,
    get_current_user,
    require_admin,
)
from app.api.v1.endpoints.pesajes import (
    ImagenPesajeOut,
    _buscar_pesaje,
    guardar_media_boleto,
    marcar_fotos_placa_si_aplica,
)
from app.core.camara_hal import descubrir_camaras_locales, es_url_valida, get_camara_hal
from app.core.database import get_db
from app.models import Camara, Empresa, ImagenPesaje, Usuario
from app.schemas import (
    CamaraCapturarIn,
    CamaraCreate,
    CamaraDescubiertaOut,
    CamaraOut,
    CamaraPruebaOut,
)
from app.services.audit_service import registrar
from app.services.catalog_service import CatalogService

router = APIRouter(prefix="/api/v1", tags=["Cámaras"])
_SERVICE = CatalogService()

log = logging.getLogger("balansoft_ws.camara")

#: Tipos MIME por extensión para el proxy del snapshot.
_EXT_POR_TIPO = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}


async def _obtener_camara(db: AsyncSession, empresa: Empresa, id_camara: uuid.UUID) -> Camara:
    """Carga una cámara de la empresa (404 si no existe) — aislamiento tenant."""
    camara = await db.get(Camara, id_camara)
    if camara is None or camara.id_empresa != empresa.id_empresa:
        raise HTTPException(status_code=404, detail="Cámara no encontrada")
    return camara


def _salida(row: dict) -> CamaraOut:
    """Construye ``CamaraOut`` sin exponer la contraseña guardada."""
    datos = dict(row)
    datos["password_configurada"] = bool(datos.pop("password", None))
    if not datos.get("por_donde"):
        if datos.get("origen") == "local":
            disp = datos.get("dispositivo")
            datos["por_donde"] = f"USB ({disp})" if disp else "USB / Local"
        else:
            url = datos.get("url_snapshot")
            datos["por_donde"] = f"Red IP ({url})" if url else "Red IP"
    return CamaraOut(**datos)


def _validar_config(data: dict) -> dict:
    """Normaliza la configuración antes de persistirla, según el ``origen``.

    - ``ip``: exige una ``url_snapshot`` http(s) y descarta el ``dispositivo``.
    - ``local``: exige un ``dispositivo`` (``/dev/video*``, índice, nombre) y
      deja la ``url_snapshot`` vacía.
    """
    origen = str(data.get("origen") or "ip")
    if origen == "local":
        dispositivo = (data.get("dispositivo") or "").strip()
        if not dispositivo:
            raise HTTPException(
                status_code=400,
                detail="La cámara local necesita la ruta/nombre del dispositivo",
            )
        data["dispositivo"] = dispositivo
        data["url_snapshot"] = ""
    else:
        url = (data.get("url_snapshot") or "").strip()
        if not es_url_valida(url):
            raise HTTPException(
                status_code=400,
                detail="La URL del snapshot debe empezar por http:// o https://",
            )
        data["url_snapshot"] = url
        data["dispositivo"] = None
    if data.get("codigo") is not None:
        data["codigo"] = str(data["codigo"]).strip() or None
    return data


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------


@router.get("/camaras", response_model=list[CamaraOut])
async def list_camaras(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
    q: str | None = Query(None, description="Búsqueda de texto (código, descripción, URL)."),
    activo: bool | None = Query(None, description="Filtra por cámaras activas/inactivas."),
    is_simulada: bool | None = Query(None, description="Filtra por cámaras simuladas/reales."),
    ubicacion: str | None = Query(None, description="Filtra por ubicación (entrada/salida/ambos)."),
    origen: str | None = Query(None, description="Filtra por origen (ip/local)."),
) -> list[CamaraOut]:
    """Lista las cámaras de la empresa con **filtros de vista** opcionales."""
    rows = await _SERVICE.list_filtrado(
        db,
        empresa.id_empresa,
        "camaras",
        q=q,
        columnas_texto=(
            "codigo",
            "descripcion",
            "marca",
            "modelo",
            "fabricante",
            "url_snapshot",
            "dispositivo",
        ),
        iguales={
            "activo": activo,
            "is_simulada": is_simulada,
            "ubicacion": ubicacion,
            "origen": origen,
        },
    )
    return [_salida(r) for r in rows]


@router.get("/camaras/descubrir", response_model=list[CamaraDescubiertaOut])
async def descubrir_camaras(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
    incluir_locales: bool = Query(
        True, description="Incluye las cámaras locales/USB del equipo (Linux/Windows)."
    ),
    incluir_registradas: bool = Query(
        True, description="Reprueba las cámaras IP ya registradas en la tabla."
    ),
) -> list[CamaraDescubiertaOut]:
    """Escanea las cámaras disponibles para registrarlas desde la UI.

    Cubre dos clases de cámara:

    - **Locales/USB**: las enchufadas a la computadora (``/dev/video*`` en
      Linux, dispositivos DirectShow en Windows). No tienen URL: el backend
      captura el *frame* con ffmpeg.
    - **IP registradas**: las ya configuradas en la empresa, reprobadas por si
      la URL cambió. (No se escanea la subred: el alta de una IP nueva es
      manual, con su URL de snapshot.)

    Devuelve los candidatos **sin persistir**; el auto-registro deduplicado lo
    hace la UI, igual que básculas y semáforos.
    """
    encontrados: list[CamaraDescubiertaOut] = []

    if incluir_locales:
        for local in descubrir_camaras_locales():
            encontrados.append(
                CamaraDescubiertaOut(
                    descripcion=str(local.get("descripcion") or "Cámara local"),
                    origen="local",
                    dispositivo=local.get("dispositivo"),
                    marca=local.get("marca"),
                    modelo=local.get("modelo"),
                    fabricante=local.get("fabricante"),
                    por_donde=local.get("por_donde"),
                    detalle="Cámara conectada a este equipo",
                )
            )

    if incluir_registradas:
        for row in await _SERVICE.list_by_name(db, empresa.id_empresa, "camaras"):
            url = str(row.get("url_snapshot") or "")
            origen = str(row.get("origen") or "ip")
            disp = row.get("dispositivo")
            por_donde = (
                f"USB ({disp})"
                if origen == "local" and disp
                else (f"Red IP ({url})" if url else "Red IP")
            )
            encontrados.append(
                CamaraDescubiertaOut(
                    descripcion=str(row.get("descripcion") or "Cámara IP"),
                    origen=origen,  # type: ignore[arg-type]
                    url_snapshot=url,
                    dispositivo=disp,
                    marca=row.get("marca"),
                    modelo=row.get("modelo"),
                    fabricante=row.get("fabricante"),
                    por_donde=por_donde,
                    ubicacion=str(row.get("ubicacion") or "ambos"),  # type: ignore[arg-type]
                    is_simulada=bool(row.get("is_simulada")),
                    detalle="Cámara IP ya registrada",
                )
            )

    return encontrados


@router.post("/camaras", response_model=CamaraOut, dependencies=[Depends(require_admin)])
async def create_camara(
    payload: CamaraCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> CamaraOut:
    data = _validar_config(payload.model_dump())
    row = await _SERVICE.create(
        db,
        empresa.id_empresa,
        "camaras",
        data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return _salida(row)


@router.put(
    "/camaras/{id_camara}",
    response_model=CamaraOut,
    dependencies=[Depends(require_admin)],
)
async def update_camara(
    id_camara: uuid.UUID,
    payload: CamaraCreate,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> CamaraOut:
    await _obtener_camara(db, empresa, id_camara)
    data = _validar_config(payload.model_dump())
    row = await _SERVICE.update(
        db,
        empresa.id_empresa,
        "camaras",
        str(id_camara),
        data,
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )
    return _salida(row)


@router.delete(
    "/camaras/{id_camara}", status_code=204, dependencies=[Depends(require_admin)]
)
async def delete_camara(
    id_camara: uuid.UUID,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _obtener_camara(db, empresa, id_camara)
    await _SERVICE.delete(
        db,
        empresa.id_empresa,
        "camaras",
        str(id_camara),
        id_usuario=current_user.id_usuario,
        ip=request.client.host if request.client else None,
    )


# ---------------------------------------------------------------------------
# Diagnóstico y captura
# ---------------------------------------------------------------------------


@router.post(
    "/camaras/{id_camara}/probar",
    response_model=CamaraPruebaOut,
    dependencies=[Depends(require_admin)],
)
async def probar_camara(
    id_camara: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> CamaraPruebaOut:
    """Descarga el snapshot (sin persistir) para verificar la conexión."""
    camara = await _obtener_camara(db, empresa, id_camara)
    hal = get_camara_hal(camara)
    conectado, meta = await hal.probar()
    meta = meta or {}
    return CamaraPruebaOut(
        camara=camara.descripcion,
        conectado=conectado,
        detalle=None if conectado else "La cámara no devolvió una imagen válida",
        ancho=meta.get("ancho"),
        alto=meta.get("alto"),
        tamano_kb=meta.get("tamano_kb"),
    )


@router.get("/camaras/{id_camara}/snapshot")
async def snapshot_camara(
    id_camara: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> Response:
    """Proxy del snapshot: **un** *frame* JPEG para previsualizar o capturar."""
    camara = await _obtener_camara(db, empresa, id_camara)
    hal = get_camara_hal(camara)
    datos = await hal.obtener_snapshot()
    if datos is None:
        raise HTTPException(status_code=502, detail="La cámara no devolvió una imagen válida")
    return Response(content=datos, media_type="image/jpeg")


@router.get("/camaras/{id_camara}/stream")
async def stream_camara(
    id_camara: uuid.UUID,
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> StreamingResponse:
    """Previsualización **en vivo** (``multipart/x-mixed-replace``, MJPEG).

    Es el «modo video» de la cámara: el backend emite los *frames* que produce
    el HAL (repite el snapshot si es IP; lee un ffmpeg continuo si es local) y
    el visor los muestra uno tras otro. La conexión se cierra cuando el cliente
    se va (``is_disconnected``) o al alcanzar ``MAX_FRAMES``; la UI reconecta.
    """
    camara = await _obtener_camara(db, empresa, id_camara)
    hal = get_camara_hal(camara)

    async def _generar() -> AsyncIterator[bytes]:
        try:
            async for frame in hal.obtener_frames():
                yield (
                    b"--frame\r\n"
                    b"Content-Type: image/jpeg\r\n"
                    b"Content-Length: " + str(len(frame)).encode() + b"\r\n\r\n"
                    + frame
                    + b"\r\n"
                )
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - un fallo del flujo cierra la conexión
            log.debug("Cámara %s: el flujo en vivo terminó", camara.descripcion)

    return StreamingResponse(
        _generar(),
        media_type="multipart/x-mixed-replace; boundary=frame",
    )


@router.post("/camaras/{id_camara}/capturar", response_model=ImagenPesajeOut, status_code=201)
async def capturar_foto_placa(
    id_camara: uuid.UUID,
    payload: CamaraCapturarIn,
    request: Request,
    current_user: Usuario = Depends(get_current_user),
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
) -> ImagenPesajeOut:
    """Captura una foto de placa del boleto desde la cámara y la persiste.

    Descarga el snapshot y lo guarda como media del boleto con
    ``tipo = 'placa'``; la primera captura marca ``fotos_placa_tomadas`` (la
    regla "una sola vez por boleto").
    """
    camara = await _obtener_camara(db, empresa, id_camara)
    pesaje = await _buscar_pesaje(db, empresa.id_empresa, str(payload.boleto))
    if pesaje is None:
        raise HTTPException(status_code=404, detail="Boleto de pesaje no encontrado")

    hal = get_camara_hal(camara)
    datos = await hal.obtener_snapshot()
    if datos is None:
        raise HTTPException(
            status_code=502,
            detail="La cámara no devolvió una imagen válida (revise la URL del snapshot)",
        )

    url = guardar_media_boleto(pesaje.boleto, datos, tipo=payload.foto, ext=".jpg")
    img = ImagenPesaje(boleto=pesaje.boleto, tipo="placa", url=url)
    db.add(img)
    await marcar_fotos_placa_si_aplica(db, pesaje, "placa")
    await db.commit()
    await db.refresh(img)

    await registrar(
        db,
        id_usuario=current_user.id_usuario if current_user else None,
        id_empresa=empresa.id_empresa,
        accion="CAPTURA",
        entidad="camaras",
        entidad_id=str(camara.id_camara),
        detalle={
            "foto": payload.foto,
            "boleto": str(pesaje.boleto),
            "numero_boleto": pesaje.numero_boleto,
        },
        ip=request.client.host if request.client else None,
    )
    await db.commit()
    return ImagenPesajeOut.model_validate(img)
