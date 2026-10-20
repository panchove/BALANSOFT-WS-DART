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
  ``ToastText02`` o ``ToastGeneric`` con ``appLogoOverride``), **con el AUMID
  registrado antes de emitirlo** (ver :data:`CLAVE_AUMID`): sin ese registro
  Windows descarta el aviso en silencio, sin excepción ni traza.

El aviso lleva siempre el **icono de la app** (``assets/balansoft-ws.png``) y el
nombre ``BALANSOFT-WS`` como aplicación emisora, para que el operador lo
identifique de un vistazo entre las notificaciones de la estación.

**Nota de despliegue**: un toast solo se dibuja si quien lo emite corre en la
sesión interactiva del operador. El WServer que arranca la tarea programada del
instalador corre como SYSTEM (sesión 0) y sus avisos no llegan al escritorio;
los de la app Flutter y los del WServer arrancado por la app sí, porque viven en
la sesión del usuario.

Versión: 0.4.2-dev.56
Fecha: 2026-10-19
Estado: Vigente
Norma: ISO/IEC 25010 / ISO/IEC 27001
Fuente: Sistema BALANSOFT-WS
Autor: Lead Architect
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

#: AppUserModelID: la identidad con la que Windows reconoce al emisor de un
#: aviso. Es el mismo que usa la app Flutter (``flutter_local_notifications``),
#: de modo que los avisos del WServer y los de la app comparten emisor, nombre
#: e icono en el Centro de notificaciones, y el operador identifica de un
#: vistazo que el aviso es de BALANSOFT-WS.
AUMID = "BALANSOFT-WS"

#: Claves del registro que le dan identidad a un emisor **sin identidad de
#: paquete** (sin instalador MSIX). Sin ellas, ``CreateToastNotifier(AUMID)``
#: **no lanza ninguna excepción y descarta el aviso en silencio**: el aviso se
#: pierde sin error, que es exactamente el fallo que reportó la estación. Son
#: las mismas dos claves que escribe ``flutter_local_notifications_windows``
#: (``src/plugin.cpp``, ``UpdateRegistry``), que es la ruta que Microsoft
#: documenta para apps de escritorio:
#:
#: * ``...\Classes\AppUserModelId\<AUMID>`` — nombre e icono del emisor.
#: * ``...\CurrentVersion\PushNotifications\Backup\<AUMID>`` — declara que es
#:   una app de escritorio (``app:desktop``) con banner y sonido.
CLAVE_AUMID = rf"HKCU:\Software\Classes\AppUserModelId\{AUMID}"
CLAVE_AUMID_BACKUP = (
    "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion"
    f"\\PushNotifications\\Backup\\{AUMID}"
)

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


def _ps_registrar_aumid(icono: str | None) -> list[str]:
    """Sentencias de PowerShell que registran el AUMID (idempotentes).

    Se ejecutan **antes** de mostrar el aviso, en la misma llamada a
    PowerShell: registrar el emisor y mostrar el toast en procesos distintos
    multiplicaría los arranques de PowerShell (que es lo caro de esta vía).

    Las claves se crean solo si faltan, y los valores se escriben solo si no
    existen, **sin tocar los demás**: la app Flutter registra el mismo AUMID
    y añade su ``CustomActivator`` —el que hace que al pulsar el aviso se abra
    la app—, y reescribir la clave desde aquí dejaría el aviso sin ese
    reenviar el clic. Registrarlo en ambos sentidos es lo que hace que los
    avisos del WServer y los de la app compartan emisor en Windows.
    """
    partes = [
        f"$ka = {_ps_cadena(CLAVE_AUMID)};",
        "if (-not (Test-Path $ka)) {",
        "New-Item -Path $ka -Force > $null;",
        "};",
    ]
    propiedades = {
        "DisplayName": APP_NAME,
        "IconUri": str(Path(icono).resolve().as_uri()) if icono else None,
    }
    for nombre, valor in propiedades.items():
        if not valor:
            continue
        partes += [
            # Sin `Test-Path` sobre el valor (el proveedor de registro de
            # PowerShell no distingue bien nombre de clave), se pregunta por
            # el dato.
            f"$v = Get-ItemProperty -Path $ka -Name {nombre}"
            " -ErrorAction SilentlyContinue;",
            "if ($null -eq $v) {",
            f"Set-ItemProperty -Path $ka -Name {nombre} -Value "
            f"{_ps_cadena(valor)} -Force;",
            "};",
        ]
    partes += [
        f"$kb = {_ps_cadena(CLAVE_AUMID_BACKUP)};",
        "if (-not (Test-Path $kb)) {",
        "New-Item -Path $kb -Force > $null;",
        "Set-ItemProperty -Path $kb -Name appType -Value 'app:desktop' -Force;",
        "Set-ItemProperty -Path $kb -Name Setting -Value "
        "'s:banner,s:toast,s:audio,c:toast,c:ringing' -Force;",
        "Set-ItemProperty -Path $kb -Name wnsId -Value 'NonImmersivePackage' -Force;",
        "};",
    ]
    return partes


def _comando_windows(titulo: str, mensaje: str) -> list[str] | None:
    """Toast de Windows. Con icono usa ``ToastGeneric`` + ``appLogoOverride``.

    El notificador se crea con el **AUMID** registrado (no con el nombre
    visible): un emisor sin identidad de paquete que no esté en el registro
    hace que Windows descarte el aviso sin error alguno.
    """
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
    ]
    partes += _ps_registrar_aumid(icono)
    partes += [
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
        f"CreateToastNotifier({_ps_cadena(AUMID)}).Show("
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
