"""Identificador de hardware de la estación (fingerprint para el LM).

El License Manager exige que el ``hardware_id`` coincida con el dispositivo
registrado en la licencia (tier CENTRAL). El frontend lo calcula con
``DeviceInfo`` y lo envía en el login; este helper ofrece el mismo valor en
el backend cuando aún no está persistido en ``identidad_local``.
"""

from __future__ import annotations

import os
import platform
from pathlib import Path

_MACHINE_ID_PATHS = (
    "/etc/machine-id",
    "/var/lib/dbus/machine-id",
)


def obtener_hardware_id() -> str:
    """Devuelve el fingerprint estable de la máquina.

    Orden de resolución: ``HARDWARE_ID`` (env, override), ``/etc/machine-id``
    (Linux), ``/var/lib/dbus/machine-id`` y, como último recurso, el nombre
    de host. Nunca devuelve cadena vacía.
    """
    override = os.getenv("HARDWARE_ID")
    if override and override.strip():
        return override.strip()
    for ruta in _MACHINE_ID_PATHS:
        try:
            valor = Path(ruta).read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if valor:
            return valor
    return platform.node() or "desconocido"
