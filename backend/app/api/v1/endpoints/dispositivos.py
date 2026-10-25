from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

try:
    from app.api.deps import get_current_empresa
except Exception:  # fallback
    from app.api.dependencies import get_current_empresa
try:
    from app.core.database import get_db
except Exception:
    from app.core.database import get_db
from app.core.discovery_smart import (
    escanear_red_si_necesario,
    hay_hardware_serial,
    hay_red_local,
    puertos_serie_disponibles,
)
from app.models import Empresa

router = APIRouter(prefix="/dispositivos", tags=["dispositivos"])


@router.get("/descubrir")
async def descubrir_dispositivos(
    empresa: Empresa = Depends(get_current_empresa),
    db: AsyncSession = Depends(get_db),
    incluir_tcp: bool = Query(True),
    incluir_serie: bool = Query(True),
) -> dict[str, Any]:
    resultado: dict[str, Any] = {"serie": [], "tcp": [], "no_clasificado": []}

    if incluir_serie and hay_hardware_serial():
        for p in puertos_serie_disponibles():
            resultado["no_clasificado"].append(
                {
                    "tipo": "serie",
                    "puerto": p,
                    "sugerido": None,
                    "baudrate_sugerido": 9600,
                }
            )
    elif incluir_serie:
        resultado["serie"] = []
        resultado["no_clasificado"] = []

    if incluir_tcp and hay_red_local():
        for ipcfg in escanear_red_si_necesario([]):
            resultado["tcp"].append({"ip": ipcfg[0], "puerto": ipcfg[1], "sugerido": None})

    return resultado
