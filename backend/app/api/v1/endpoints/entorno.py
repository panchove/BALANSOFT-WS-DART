"""Estado del entorno de despliegue: verificación de instalación.

Sin autenticación (p. ej. lo consulta la app antes del login durante el modo
instalación). Reporta si PostgreSQL es alcanzable y con esquema listo, y el
estado del hardware de balanza (HAL / pyserial), entre otros datos.
"""

from __future__ import annotations

import platform
import sys
from urllib.parse import urlparse

from fastapi import APIRouter
from sqlalchemy import text

from app.core.config import settings
from app.core.database import AsyncSessionLocal

router = APIRouter(prefix="/api/v1/environment", tags=["Instalación"])

API_VERSION = "1.0.0"

_SQL_TABLAS = text("SELECT count(*) FROM pg_tables WHERE schemaname = 'public'")


def _nombre_bd(url: str) -> str:
    try:
        return urlparse(url).path.rsplit("/", 1)[-1]
    except Exception:
        return ""


async def _estado_postgres() -> dict:
    base: dict = {"conectado": False, "esquema_listo": False, "n_tablas": 0}
    try:
        async with AsyncSessionLocal() as session:
            n = (await session.execute(_SQL_TABLAS)).scalar_one()
        return {
            "conectado": True,
            "esquema_listo": n > 0,
            "n_tablas": n,
        }
    except Exception:
        return base


async def _estado_hardware() -> dict:
    """Detecta pyserial (driver de balanza) y puertos serie disponibles."""
    pyserial = False
    puertos: list[str] = []
    try:
        import serial  # noqa: F401

        pyserial = True
        try:
            from serial.tools import list_ports

            puertos = sorted({p.device for p in list_ports.comports()})[:20]
        except Exception:
            puertos = []
    except Exception:
        pyserial = False

    n_balanzas = -1
    try:
        from app.models import Balanza  # noqa: F401 (modelo importado para validar esquema)

        async with AsyncSessionLocal() as session:
            n_balanzas = (
                await session.execute(text("SELECT count(*) FROM balanzas"))
            ).scalar_one()
    except Exception:
        n_balanzas = -1

    return {
        "pyserial": pyserial,
        "puertos_serial": puertos,
        "balanzas_configuradas": n_balanzas,
    }


@router.get("")
async def environment() -> dict:
    postgres = await _estado_postgres()
    hardware = await _estado_hardware()

    estado = "ok" if postgres["conectado"] and postgres["esquema_listo"] else "incompleto"
    return {
        "estado": estado,
        "sistema": {
            "plataforma": platform.platform(),
            "python": platform.python_version(),
            "frozen": bool(getattr(sys, "frozen", False)),
            "hostname": platform.node(),
            "app_env": settings.app_env,
            "app_role": settings.app_role,
        },
        "api": {"version": API_VERSION},
        "postgres": {
            **postgres,
            "bd": _nombre_bd(settings.database_url),
        },
        "hardware": hardware,
    }