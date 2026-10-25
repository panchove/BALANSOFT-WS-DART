from __future__ import annotations

import glob
import logging
import os
import socket
from typing import Any

log = logging.getLogger("balansoft_ws.discovery")

SERIAL_GLOBS_USB_ACM = ("/dev/ttyUSB*", "/dev/ttyACM*")
SERIAL_ALL = ("/dev/ttyUSB*", "/dev/ttyACM*", "/dev/ttyS*", "/dev/ttyAMA*", "/dev/rfcomm*", "/dev/ttyGS*")


def hay_hardware_serial() -> bool:
    """Solo considera USB/ACM físicos para el bucle de escaneo serie."""
    for patron in SERIAL_GLOBS_USB_ACM:
        try:
            if glob.glob(patron):
                return True
        except Exception:
            continue
    try:
        for entry in os.listdir("/sys/class/tty"):
            if entry.startswith(("ttyUSB", "ttyACM")):
                return True
    except Exception:
        pass
    return False


def puertos_serie_disponibles() -> list[str]:
    puertos: list[str] = []
    for patron in SERIAL_ALL:
        try:
            puertos.extend(glob.glob(patron))
        except Exception:
            continue
    vistos = set()
    out: list[str] = []
    for p in puertos:
        if p in vistos:
            continue
        vistos.add(p)
        out.append(p)
    return out


def hay_red_local() -> bool:
    """Chequeo ligero: intenta socket UDP a 8.8.8.8 para saber si hay ruta de red."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(1.0)
        s.connect(("8.8.8.8", 53))
        s.close()
        return True
    except Exception:
        return False


def escanear_red_si_necesario(ips_configuradas: list[tuple[str, int]] | None = None) -> list[tuple[str, int]]:
    ips_configuradas = ips_configuradas or []
    if not ips_configuradas:
        return []
    if not hay_red_local():
        return []
    return list(ips_configuradas)
