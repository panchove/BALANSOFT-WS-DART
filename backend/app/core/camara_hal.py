"""HAL (Hardware Abstraction Layer) de la cámara de captura de placa.

La cámara **no** decide nada: la estación le pide un *frame* y lo guarda como
media del boleto. Hay dos canales implementados:

- **IP** (Fase 2): se descarga el JPEG de ``url_snapshot`` (p. ej.
  ``http://192.168.1.50/snapshot.jpg`` o una ruta ISAPI de la marca) con
  credenciales HTTP basic opcionales.
- **Local / USB** (Fase 3): la cámara está enchufada a la computadora
  (``/dev/video*`` en Linux, índice de MediaFoundation en Windows). No tiene URL:
  el *frame* se captura con ``ffmpeg``/``v4l2`` y se devuelve como JPEG.

En la app, la captura primaria es por la cámara registrada; si ninguna responde,
el formulario de pesaje cae a la **cámara del dispositivo** (``image_picker``,
ver ``photo_picker_field.dart``). Esa vía no pasa por este HAL: sube los bytes
igual que las demás imágenes de pesaje.

Reglas de oro:

- El HAL **nunca** loggea credenciales.
- El tamaño de la imagen se acota a ``settings.max_image_bytes``; el tipo de
  contenido debe ser una imagen (``image/jpeg|png|webp``).
"""

from __future__ import annotations

import asyncio
import glob
import logging
import os
import shutil
import subprocess
import sys
import tempfile
import threading
from collections.abc import AsyncIterator
from typing import Any

import httpx

log = logging.getLogger("balansoft_ws.camara")

#: Tipos MIME aceptados como snapshot.
TIPOS_IMAGEN: tuple[str, ...] = ("image/jpeg", "image/png", "image/webp")

TIEMPO_ESPERA_DEFECTO = 5.0
#: Tope por defecto del cuerpo descargado (10 MB, igual que la API de archivos).
_MAX_BYTES_DEFECTO = 10 * 1024 * 1024

#: Tiempo máximo de una captura local (ffmpeg tarda ~1 s en abrir el sensor).
TIEMPO_CAPTURA_LOCAL = 15.0
#: Patrón de los nodos de captura locales (Linux).
GLOB_VIDEO_LINUX = "/dev/video*"

#: Intervalo entre cuadros de la previsualización en vivo (≈4 fps).
INTERVALO_FRAME = 0.25
#: Máximo de cuadros que emite un ``obtener_frames`` antes de cortar. La UI
#: reconecta: el corte evita dejar un bucle infinito vivo si el cliente muere.
MAX_FRAMES = 900

#: Cerrojo por dispositivo local para evitar accesos concurrentes a /dev/video*
_CAMARA_LOCKS: dict[str, threading.Lock] = {}
_CAMARA_LOCKS_MUTEX = threading.Lock()

def _lock_para_dispositivo(dispositivo: str) -> threading.Lock:
    """Devuelve (crea si no existe) el cerrojo para un dispositivo local."""
    with _CAMARA_LOCKS_MUTEX:
        lock = _CAMARA_LOCKS.get(dispositivo)
        if lock is None:
            lock = threading.Lock()
            _CAMARA_LOCKS[dispositivo] = lock
        return lock

_PROTOCOLOS_URL = ("http://", "https://")


class CamaraHAL:
    """Descarga el snapshot JPEG de la cámara por HTTP."""

    def __init__(
        self,
        url_snapshot: str,
        usuario: str | None = None,
        password: str | None = None,
        timeout: float = TIEMPO_ESPERA_DEFECTO,
        max_bytes: int = _MAX_BYTES_DEFECTO,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self.url_snapshot = url_snapshot
        self.usuario = usuario
        self.password = password
        self.timeout = timeout
        self.max_bytes = max_bytes
        #: Transporte alternativo (solo pruebas: ``httpx.MockTransport``).
        self.transport = transport

    def _auth(self) -> httpx.BasicAuth | None:
        if self.usuario and self.password:
            return httpx.BasicAuth(self.usuario, self.password)
        return None

    async def obtener_snapshot(self) -> bytes | None:
        """Devuelve los bytes del snapshot o ``None`` si no se puede obtener.

        Nunca levanta: el fallo se traduce a ``None`` para que el llamador
        (prueba de conexión o captura) responda con un mensaje accionable.
        """
        try:
            async with httpx.AsyncClient(
                timeout=self.timeout, transport=self.transport, auth=self._auth()
            ) as client:
                resp = await client.get(self.url_snapshot)
            if resp.status_code != 200:
                log.debug(
                    "Cámara %s: snapshot HTTP %s", _sanear(self.url_snapshot), resp.status_code
                )
                return None
            tipo = (resp.headers.get("content-type") or "").split(";")[0].strip().lower()
            if tipo and tipo not in TIPOS_IMAGEN:
                log.debug("Cámara %s: content-type no es imagen: %s", _sanear(self.url_snapshot), tipo)
                return None
            datos = resp.content
        except (httpx.HTTPError, ValueError, OSError) as exc:
            log.debug("Cámara %s: snapshot ilegible: %s", _sanear(self.url_snapshot), exc)
            return None
        if not datos:
            return None
        if len(datos) > self.max_bytes:
            log.debug(
                "Cámara %s: snapshot de %s bytes excede el máximo %s",
                _sanear(self.url_snapshot),
                len(datos),
                self.max_bytes,
            )
            return None
        return datos

    async def probar(self) -> tuple[bool, dict[str, Any] | None]:
        """Prueba la conexión y devuelve ``(conectado, metadatos)``.

        Los metadatos incluyen el tipo de contenido, el tamaño en KB y las
        dimensiones si Pillow puede abrir la imagen.
        """
        datos = await self.obtener_snapshot()
        if datos is None:
            return (False, None)
        meta: dict[str, Any] = {
            "tamano_kb": round(len(datos) / 1024, 1),
        }
        dimensiones = _dimensiones(datos)
        if dimensiones is not None:
            meta["ancho"], meta["alto"] = dimensiones
        return (True, meta)

    async def obtener_frames(self) -> AsyncIterator[bytes]:
        """Emite *frames* JPEG en bucle para la previsualización en vivo.

        La cámara IP no tiene un flujo MJPEG universal (la ruta y el formato
        dependen de la marca), así que el «video» se arma **repidiendo** el
        snapshot: la UI ve la imagen moverse sin depender de la marca. Nunca
        levanta: si un intento falla, se salta ese cuadro.
        """
        for _ in range(MAX_FRAMES):
            datos = await self.obtener_snapshot()
            if datos is not None:
                yield datos
            await asyncio.sleep(INTERVALO_FRAME)


class CamaraLocalHAL:
    """Captura un *frame* de una cámara local/USB con ``ffmpeg``.

    El dispositivo (``/dev/video0`` en Linux, o un índice/nombre de cámara en
    Windows) no tiene snapshot HTTP: se abre con ffmpeg, se toma **un** frame y
    se devuelve el JPEG en memoria. El proceso se aísla con ``asyncio.to_thread``
    y timeout para que un sensor colgado nunca bloquee la API.
    """

    def __init__(
        self,
        dispositivo: str,
        timeout: float = TIEMPO_CAPTURA_LOCAL,
        max_bytes: int = _MAX_BYTES_DEFECTO,
    ) -> None:
        self.dispositivo = dispositivo
        self.timeout = timeout
        self.max_bytes = max_bytes

    def _comando(self, destino: str) -> list[str]:
        """Construye el comando de captura según la plataforma."""
        ffmpeg = shutil.which("ffmpeg") or "ffmpeg"
        if sys.platform.startswith("linux"):
            entrada = ["-f", "v4l2", "-i", self.dispositivo]
        elif sys.platform == "darwin":
            entrada = ["-f", "avfoundation", "-i", self.dispositivo]
        else:  # Windows: el dispositivo es el nombre o índice de DirectShow.
            entrada = ["-f", "dshow", "-i", f"video={self.dispositivo}"]
        return [
            ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            *entrada,
            "-frames:v",
            "1",
            "-f",
            "image2",
            destino,
        ]

    def _capturar_sync(self) -> bytes | None:
        """Ejecuta ffmpeg de forma síncrona y devuelve los bytes del JPEG.

        Usa un cerrojo por dispositivo para evitar accesos concurrentes
        (``Device or resource busy`` en Linux cuando dos hilos abren /dev/video*).
        """
        lock = _lock_para_dispositivo(self.dispositivo)
        acquired = lock.acquire(timeout=5.0)
        if not acquired:
            log.debug("Cámara local %s: no se pudo obtener el cerrojo (timeout)", self.dispositivo)
            return None
        try:
            if shutil.which("ffmpeg") is None:
                log.debug("Cámara local %s: ffmpeg no está instalado", self.dispositivo)
                return None
            if sys.platform.startswith("linux") and not os.path.exists(self.dispositivo):
                log.debug("Cámara local %s: el dispositivo no existe", self.dispositivo)
                return None
            tmp = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
            tmp.close()
            try:
                proc = subprocess.run(  # noqa: S603 - comando construido por nosotros
                    self._comando(tmp.name),
                    capture_output=True,
                    timeout=self.timeout,
                    check=False,
                )
                if proc.returncode != 0:
                    log.debug(
                        "Cámara local %s: ffmpeg falló (%s): %s",
                        self.dispositivo,
                        proc.returncode,
                        proc.stderr.decode(errors="replace")[:200],
                    )
                    return None
                with open(tmp.name, "rb") as fh:  # noqa: PTH123 - ruta temporal propia
                    datos = fh.read()
            except (subprocess.SubprocessError, OSError) as exc:
                log.debug("Cámara local %s: captura ilegible: %s", self.dispositivo, exc)
                return None
            finally:
                try:
                    os.unlink(tmp.name)  # noqa: PTH108 - ruta temporal propia
                except OSError:
                    pass
            if not datos or len(datos) > self.max_bytes:
                return None
            return datos
        finally:
            lock.release()

    async def obtener_snapshot(self) -> bytes | None:
        """Devuelve el JPEG capturado o ``None`` si el dispositivo no responde."""
        return await asyncio.to_thread(self._capturar_sync)

    async def probar(self) -> tuple[bool, dict[str, Any] | None]:
        """Prueba la cámara local verificando que el dispositivo exista y
        ffmpeg esté disponible.

        No se captura un *frame* aquí: el flujo en vivo (``stream``) es el que
        abre el dispositivo. Capturar aquí provocaría ``Device or resource busy``
        porque el dispositivo ya está en uso por el stream.
        """
        if shutil.which("ffmpeg") is None:
            log.debug("Cámara local %s: ffmpeg no está instalado", self.dispositivo)
            return (False, None)
        if sys.platform.startswith("linux") and not os.path.exists(self.dispositivo):
            log.debug("Cámara local %s: el dispositivo no existe", self.dispositivo)
            return (False, None)
        meta: dict[str, Any] = {"tamano_kb": 0.0}
        return (True, meta)

    def _comando_stream(self) -> list[str]:
        """Comando ffmpeg que emite varios JPEG por *stdout* (un solo proceso).

        Arrancar ffmpeg por cuadro costaría ~1 s cada uno; para el «video» se
        abre **una vez** y se leen los JPEG concatenados que va escribiendo
        (``image2pipe``), que es lo barato para una webcam local.
        """
        ffmpeg = shutil.which("ffmpeg") or "ffmpeg"
        if sys.platform.startswith("linux"):
            entrada = ["-f", "v4l2", "-i", self.dispositivo]
        elif sys.platform == "darwin":
            entrada = ["-f", "avfoundation", "-i", self.dispositivo]
        else:
            entrada = ["-f", "dshow", "-i", f"video={self.dispositivo}"]
        return [
            ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            *entrada,
            "-f",
            "image2pipe",
            "-vcodec",
            "mjpeg",
            "-q:v",
            "7",
            "-r",
            f"{1 / INTERVALO_FRAME:.0f}",
            "-",
        ]

    async def obtener_frames(self) -> AsyncIterator[bytes]:
        """Emite *frames* JPEG de la cámara local leyendo un ffmpeg continuo.

        Los JPEG se separan por los marcadores ``FFD8`` (inicio) / ``FFD9``
        (fin), que es como ``image2pipe`` los concatena. Si ffmpeg no está o el
        dispositivo no responde, no emite nada (la UI muestra «sin señal»).
        Nunca levanta.
        """
        if shutil.which("ffmpeg") is None:
            log.debug("Cámara local %s: ffmpeg no está instalado", self.dispositivo)
            return
        if sys.platform.startswith("linux") and not os.path.exists(self.dispositivo):
            log.debug("Cámara local %s: el dispositivo no existe", self.dispositivo)
            return
        try:
            proc = await asyncio.create_subprocess_exec(
                *self._comando_stream(),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
        except (OSError, ValueError) as exc:
            log.debug("Cámara local %s: no se pudo abrir ffmpeg: %s", self.dispositivo, exc)
            return
        try:
            async for frame in _leer_jpegs(proc.stdout, self.max_bytes):
                yield frame
        finally:
            await _cerrar_proceso(proc)


async def _leer_jpegs(
    stream: asyncio.StreamReader | None,
    max_bytes: int,
) -> AsyncIterator[bytes]:
    """Trocea el flujo ``image2pipe`` de ffmpeg en JPEG completos.

    ``image2pipe`` concatena los JPEG sin longitud previa: cada imagen empieza
    con ``FFD8`` y termina con ``FFD9``, así que se busca ese par. Un cuadro
    mayor que ``max_bytes`` se descarta (sensor mal configurado).
    """
    if stream is None:
        return
    buffer = bytearray()
    while True:
        try:
            trozo = await stream.read(65536)
        except (OSError, ValueError):
            return
        if not trozo:
            return
        buffer.extend(trozo)
        while True:
            inicio = buffer.find(b"\xff\xd8")
            if inicio < 0:
                buffer.clear()
                break
            fin = buffer.find(b"\xff\xd9", inicio + 2)
            if fin < 0:
                if inicio > 0:
                    del buffer[:inicio]
                break
            frame = bytes(buffer[inicio : fin + 2])
            del buffer[: fin + 2]
            if 0 < len(frame) <= max_bytes:
                yield frame


async def _cerrar_proceso(proc: asyncio.subprocess.Process) -> None:
    """Cierra el ffmpeg con SIGTERM y espera acotado (nunca cuelga)."""
    if proc.returncode is not None:
        return
    try:
        proc.terminate()
    except ProcessLookupError:
        return
    try:
        await asyncio.wait_for(proc.wait(), timeout=2.0)
    except (TimeoutError, OSError, ValueError):
        try:
            proc.kill()
        except ProcessLookupError:
            pass


def _dimensiones(datos: bytes) -> tuple[int, int] | None:
    """Lee ancho/alto del JPEG con Pillow (best-effort, nunca levanta)."""
    try:
        import io

        from PIL import Image, ImageOps

        with Image.open(io.BytesIO(datos)) as origen:
            img = ImageOps.exif_transpose(origen)
            return (img.width, img.height)
    except Exception:  # noqa: BLE001 - dimensiones son informativas
        return None


def _sanear(url: str) -> str:
    """Quita credenciales embebidas de la URL antes de logeárla."""
    if "@" in url:
        esquema, _, resto = url.partition("://")
        _, _, host = resto.rpartition("@")
        return f"{esquema}://{host}" if esquema else host
    return url


def get_camara_hal(camara: Any) -> CamaraHAL | CamaraLocalHAL:
    """Crea el HAL a partir de una cámara (modelo o dict).

    Acepta tanto la instancia ORM (``Camara``) como un ``dict`` del
    ``CatalogService``. Si la cámara es ``origen='local'`` usa el canal
    ffmpeg con ``dispositivo``; en caso contrario, el snapshot HTTP.
    """
    if isinstance(camara, dict):
        origen = str(camara.get("origen") or "ip")
        dispositivo = camara.get("dispositivo")
        url = str(camara.get("url_snapshot") or "")
        usuario = camara.get("usuario")
        password = camara.get("password")
    else:
        origen = str(getattr(camara, "origen", "ip") or "ip")
        dispositivo = getattr(camara, "dispositivo", None)
        url = str(getattr(camara, "url_snapshot", "") or "")
        usuario = getattr(camara, "usuario", None)
        password = getattr(camara, "password", None)

    if origen == "local":
        return CamaraLocalHAL(str(dispositivo or ""))
    return CamaraHAL(url_snapshot=url, usuario=usuario, password=password)


def es_url_valida(url: str) -> bool:
    """True si la URL declara un esquema http(s) (no se valida el host)."""
    return url.strip().lower().startswith(_PROTOCOLOS_URL)


# ---------------------------------------------------------------------------
# Descubrimiento de cámaras locales del equipo
# ---------------------------------------------------------------------------


def descubrir_camaras_locales() -> list[dict[str, Any]]:
    """Enumera las cámaras locales/USB enchufadas a la computadora.

    Linux: lee ``v4l2-ctl --list-devices`` (con respaldo de ``/dev/video*``),
    tomando **un nodo de captura por cámara** (los equipos exponen varios nodos
    —captura + metadata—; se quedan solo los que ffmpeg puede enumerar).
    Windows/macOS: enumeran con ``ffmpeg -list_devices`` si está disponible.

    Nunca levanta: sin herramientas o sin cámaras devuelve ``[]``.
    """
    if sys.platform.startswith("linux"):
        return _descubrir_locales_linux()
    return _descubrir_locales_ffmpeg()


def deducir_marca_modelo(nombre: str) -> tuple[str, str, str]:
    """Extrae (marca, modelo, fabricante) a partir del nombre reportado por el driver.

    Ejemplos:
    - 'HD Pro Webcam C920' -> ('Logitech', 'C920', 'Logitech')
    - 'Integrated_Webcam_HD' -> ('Webcam Integrada', 'Integrated HD', 'Equipo Local')
    - 'USB Composite Device' -> ('Genérica', 'USB Composite Device', 'Genérico')
    - 'Hikvision DS-2CD...' -> ('Hikvision', 'DS-2CD...', 'Hikvision')
    """
    if not nombre:
        return ("Genérica", "Cámara Estándar", "Genérico")

    texto = nombre.replace("_", " ").strip()
    texto_lower = texto.lower()

    marcas_conocidas = [
        ("Logitech", ["logitech", "c920", "c922", "c930", "brio", "c270", "c310"]),
        ("Hikvision", ["hikvision", "ds-2cd", "ezviz"]),
        ("Dahua", ["dahua", "imou", "ipc-"]),
        ("Axis", ["axis"]),
        ("Microsoft", ["microsoft", "lifecam"]),
        ("Dell", ["dell"]),
        ("HP", ["hp", "hewlett"]),
        ("Lenovo", ["lenovo"]),
        ("Sunplus", ["sunplus"]),
        ("Realtek", ["realtek"]),
        ("Webcam Integrada", ["integrated", "internal", "builtin", "integrada"]),
        ("Genérica", ["usb composite", "usb camera", "usb 2.0", "webcam", "video capture"]),
    ]

    marca_detectada = None
    fabricante_detectado = None
    for marca, patrones in marcas_conocidas:
        if any(p in texto_lower for p in patrones):
            marca_detectada = marca
            fabricante_detectado = (
                marca
                if marca not in ("Webcam Integrada", "Genérica")
                else ("Equipo Local" if marca == "Webcam Integrada" else "Genérico")
            )
            break

    marca_final = marca_detectada or "Genérica"
    fabricante_final = fabricante_detectado or marca_final
    modelo_final = texto
    return (marca_final, modelo_final, fabricante_final)


def _descubrir_locales_linux() -> list[dict[str, Any]]:
    """Enumera cámaras V4L2 en Linux agrupadas por dispositivo físico."""
    dispositivos = sorted(glob.glob(GLOB_VIDEO_LINUX))
    if not dispositivos:
        return []

    nombres: dict[str, str] = {}
    if shutil.which("v4l2-ctl"):
        try:
            salida = subprocess.run(  # noqa: S603 - binario del sistema
                ["v4l2-ctl", "--list-devices"],
                capture_output=True,
                timeout=5,
                check=False,
            ).stdout.decode(errors="replace")
            nombres = _parsear_v4l2(salida)
        except (subprocess.SubprocessError, OSError):
            nombres = {}

    encontradas: list[dict[str, Any]] = []
    vistos: set[str] = set()
    for nodo in dispositivos:
        # Solo los nodos de captura reales: ``v4l2-ctl --list-formats`` responde.
        if not _es_nodo_de_captura(nodo):
            continue
        nombre = nombres.get(nodo) or os.path.basename(nodo)  # noqa: PTH119 - etiqueta
        # Un equipo físico expone varios nodos (captura + metadata): se registra
        # una sola vez por nombre de dispositivo.
        if nombre in vistos:
            continue
        vistos.add(nombre)
        marca, modelo, fabricante = deducir_marca_modelo(nombre)
        encontradas.append(
            {
                "origen": "local",
                "dispositivo": nodo,
                "descripcion": nombre,
                "marca": marca,
                "modelo": modelo,
                "fabricante": fabricante,
                "por_donde": f"USB ({nodo})",
                "url_snapshot": "",
            }
        )
    return encontradas


def _parsear_v4l2(salida: str) -> dict[str, str]:
    """Mapea ``/dev/videoN`` -> nombre de la cámara desde ``v4l2-ctl``.

    La salida tiene la forma::

        Integrated_Webcam_HD: Integrate (usb-0000:00:14.0-11):
            /dev/video0
            /dev/video1
            /dev/media0
    """
    mapa: dict[str, str] = {}
    actual = ""
    for linea in salida.splitlines():
        if not linea.strip():
            continue
        if not linea.startswith(("\t", " ")):
            # Línea de cabecera: "Nombre: Detalle (bus):"
            actual = linea.split(":")[0].strip()
            continue
        nodo = linea.strip()
        if nodo.startswith("/dev/video"):
            mapa[nodo] = actual or os.path.basename(nodo)  # noqa: PTH119 - etiqueta
    return mapa


def _es_nodo_de_captura(nodo: str) -> bool:
    """True si el nodo V4L2 ofrece captura de video (no solo metadata).

    ``v4l2-ctl --list-formats`` responde con ``Type: Video Capture`` y la lista
    de formatos en los nodos de captura; en los nodos de metadata (``/dev/videoN``
    sin captura) devuelve error o no lista formatos.
    """
    if not shutil.which("v4l2-ctl"):
        return True  # sin la herramienta no se puede filtrar: se acepta el nodo
    try:
        proc = subprocess.run(  # noqa: S603 - binario del sistema
            ["v4l2-ctl", "--list-formats", "-d", nodo],
            capture_output=True,
            timeout=5,
            check=False,
        )
    except (subprocess.SubprocessError, OSError):
        return True
    texto = proc.stdout.decode(errors="replace")
    if "Video Capture" not in texto:
        return False
    # Un nodo de captura lista al menos un formato (``[0]: 'MJPG'`` …).
    return "[0]" in texto


def _descubrir_locales_ffmpeg() -> list[dict[str, Any]]:
    """Enumera cámaras locales por ``ffmpeg -list_devices`` (Windows/macOS)."""
    if not shutil.which("ffmpeg"):
        return []
    if sys.platform == "darwin":
        entrada = ["-f", "avfoundation", "-list_devices", "true", "-i", ""]
    else:
        entrada = ["-list_devices", "true", "-f", "dshow", "-i", "dummy"]

    try:
        proc = subprocess.run(  # noqa: S603 - binario del sistema
            ["ffmpeg", "-hide_banner", *entrada],
            capture_output=True,
            timeout=8,
            check=False,
        )
    except (subprocess.SubprocessError, OSError):
        return []

    texto = proc.stderr.decode(errors="replace")
    encontradas: list[dict[str, Any]] = []
    for linea in texto.splitlines():
        marca = "(video)" if sys.platform == "darwin" else '"'
        if marca not in linea:
            continue
        if sys.platform == "darwin":
            nombre = linea.split("(video)")[-1].strip()
        else:
            nombre = linea.split('"')[1] if linea.count('"') >= 2 else ""
        if not nombre:
            continue
        marca_nom, modelo_nom, fabricante_nom = deducir_marca_modelo(nombre)
        encontradas.append(
            {
                "origen": "local",
                "dispositivo": nombre,
                "descripcion": nombre,
                "marca": marca_nom,
                "modelo": modelo_nom,
                "fabricante": fabricante_nom,
                "por_donde": f"DirectShow ({nombre})" if sys.platform != "darwin" else f"AVFoundation ({nombre})",
                "url_snapshot": "",
            }
        )
    return encontradas
