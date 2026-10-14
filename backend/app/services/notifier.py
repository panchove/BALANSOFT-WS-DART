"""Notificador nativo del sistema operativo (tarea residente del backend local).

Es la pieza que cumple el requisito «la notificación llega aunque la app Flutter
esté cerrada»: el backend de la estación (WServer, rol ``local``) es el único
proceso que queda vivo, así que el programador
(``app/core/notification_scheduler.py``) evalúa eventos y recordatorios y llama
aquí para dibujar el aviso del SO.

Canales:

* **Linux** — ``notify-send`` (libnotify), con el icono de la app y la urgencia
  según la severidad.
* **Windows** — toast de la API WinRT vía PowerShell (plantilla
  ``ToastText02`` o ``ToastGeneric`` con ``appLogoOverride``).

El aviso lleva siempre el **icono de la app** (``assets/balansoft-ws.png``) y el
nombre ``BALANSOFT-WS`` como aplicación emisora, para que el operador lo
identifique de un vistazo entre las notificaciones de la estación.
"""

from __future__ import annotations

import logging
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

log = logging.getLogger(__name__)

APP_NAME = "BALANSOFT-WS"

#: Nombre del icono dentro de ``assets/`` (copiado de ``BALANSOFT-WS.png``).
ICONO_NOMBRE = "balansoft-ws.png"

#: Icono de reserva si no se encuentra el de la app (tema de iconos del SO).
ICONO_RESPALDO = "dialog-information"

# notify-send: urgencia visual según la severidad del aviso.
_URGENCIA_LINUX: dict[str, str] = {
    "info": "low",
    "media": "normal",
    "alta": "normal",
    "critica": "critical",
}


def ruta_icono() -> str | None:
    """Ruta absoluta del icono de la app, o ``None`` si no se encuentra.

    Se resuelve en cada llamada (el aviso es poco frecuente) y en este orden:

    1. ``BALANSOFT_ICON_PATH`` — override manual del operador.
    2. ``sys._MEIPASS/assets`` — bundle one-file del WServer (PyInstaller).
    3. ``backend/assets`` — repositorio o instalación en disco.
    4. ``~/.balansoft-ws/wserver/assets`` — runtime del WServer.

    Que no exista **no** es un error: se cae al icono genérico del tema.
    """
    candidatas: list[Path] = []
    override = os.environ.get("BALANSOFT_ICON_PATH")
    if override:
        candidatas.append(Path(override))
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        candidatas.append(Path(meipass) / "assets" / ICONO_NOMBRE)
    candidatas.append(Path(__file__).resolve().parents[2] / "assets" / ICONO_NOMBRE)
    candidatas.append(
        Path.home() / ".balansoft-ws" / "wserver" / "assets" / ICONO_NOMBRE
    )
    for candidata in candidatas:
        try:
            if candidata.is_file():
                return str(candidata)
        except OSError:  # pragma: no cover - ruta inaccesible según el SO
            continue
    return None


def _icono_notify_send() -> str:
    """Valor de ``-i`` para ``notify-send``: el de la app o el genérico."""
    return ruta_icono() or ICONO_RESPALDO


def _comando_linux(titulo: str, mensaje: str, severidad: str) -> list[str] | None:
    binario = shutil.which("notify-send")
    if not binario:
        return None
    return [
        binario,
        "-a",
        APP_NAME,
        "-u",
        _URGENCIA_LINUX.get(severidad, "normal"),
        "-i",
        _icono_notify_send(),
        # ``--`` corta las opciones: un título que empiece por ``-`` es texto,
        # no un flag de notify-send (evita que un aviso se interprete como
        # opción). No hay shell de por medio, así que no es inyección de
        # comandos — solo higiene de argumentos.
        "--",
        titulo,
        mensaje,
    ]


def _ps_cadena(valor: str) -> str:
    """Literal de PowerShell entre comillas simples (duplica las internas)."""
    return "'" + valor.replace("'", "''") + "'"


def _comando_windows(titulo: str, mensaje: str) -> list[str] | None:
    """Toast de Windows. Con icono usa ``ToastGeneric`` + ``appLogoOverride``."""
    powershell = shutil.which("powershell") or shutil.which("pwsh")
    if not powershell:
        return None
    icono = ruta_icono()
    # ``ToastText02`` es la plantilla antigua (sin imagen): no admite logo, así
    # que el icono de la app obliga a la plantilla genérica.
    plantilla = "ToastGeneric" if icono else "ToastText02"
    partes = [
        "[Windows.UI.Notifications.ToastNotificationManager, "
        "Windows.UI.Notifications, ContentType = WindowsRuntime] > $null;",
        "[Windows.UI.Notifications.ToastNotification, "
        "Windows.UI.Notifications, ContentType = WindowsRuntime] > $null;",
        "$t = [Windows.UI.Notifications.ToastNotificationManager]::"
        "GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::"
        f"{plantilla});",
        "$b = $t.GetElementsByTagName('binding').Item(0);",
    ]
    if plantilla == "ToastGeneric":
        # ``ToastGeneric`` nace sin nodos ``text``: se crean a mano.
        for indice, texto in enumerate((titulo, mensaje or titulo)):
            partes.append(
                f"$t{indice} = $t.CreateElement('text');"
                f"$t{indice}.AppendChild($t.CreateTextNode({_ps_cadena(texto)})) > $null;"
                f"$b.AppendChild($t{indice}) > $null;"
            )
    else:
        partes.append("$x = $t.GetElementsByTagName('text');")
        for indice, texto in enumerate((titulo, mensaje or titulo)):
            partes.append(
                f"$x.Item({indice}).AppendChild($t.CreateTextNode({_ps_cadena(texto)}))"
                " > $null;"
            )
    if icono:
        partes.append(
            "$img = $t.CreateElement('image');"
            "$img.SetAttribute('placement', 'appLogoOverride');"
            f"$img.SetAttribute('src', {_ps_cadena(Path(icono).resolve().as_uri())});"
            "$b.AppendChild($img) > $null;"
        )
    partes.append(
        "[Windows.UI.Notifications.ToastNotificationManager]::"
        f"CreateToastNotifier({_ps_cadena(APP_NAME)}).Show("
        "[Windows.UI.Notifications.ToastNotification]::new($t));"
    )
    return [powershell, "-NoProfile", "-NonInteractive", "-Command", "".join(partes)]


def _comando_actual(titulo: str, mensaje: str, severidad: str) -> list[str] | None:
    sistema = platform.system()
    if sistema == "Linux":
        return _comando_linux(titulo, mensaje, severidad)
    if sistema == "Windows":
        return _comando_windows(titulo, mensaje)
    return None


def notificar_os(titulo: str, mensaje: str, severidad: str = "info") -> bool:
    """Muestra una notificación nativa. Devuelve si se llegó a enviar.

    Pensada para invocarse con ``asyncio.to_thread`` desde el programador
    (``subprocess`` bloquea). Cualquier fallo se traga y se registra a nivel
    *debug*: en CI o en un contenedor sin bus de sesión lo normal es ``False``.
    """
    comando = _comando_actual(titulo, mensaje or titulo, severidad)
    if comando is None:
        log.debug(
            "Notificación OS omitida (sin canal notify-send/PowerShell): %s", titulo
        )
        return False
    try:
        subprocess.run(
            comando,
            check=True,
            capture_output=True,
            timeout=10,
        )
        return True
    except Exception as exc:  # noqa: BLE001 - best-effort deliberado
        log.debug("No se pudo mostrar la notificación OS (%s): %s", titulo, exc)
        return False


def canal_disponible() -> str | None:
    """Canal que se usaría ('linux'|'windows'|None), para diagnóstico."""
    sistema = platform.system()
    if sistema == "Linux":
        return "linux" if shutil.which("notify-send") else None
    if sistema == "Windows":
        return "windows" if (shutil.which("powershell") or shutil.which("pwsh")) else None
    return None
