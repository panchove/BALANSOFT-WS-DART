"""Punto de entrada de la API de Balansoft-WS."""

from __future__ import annotations

import os
from contextlib import asynccontextmanager
from datetime import UTC, datetime

from fastapi import FastAPI, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import select

from app.api.v1.endpoints import API_ROUTERS, SERVER_ROUTERS
from app.api.v1.endpoints.auth import _MAX_INTENTOS_CENTRAL
from app.core.audit import AuditMiddleware
from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.core.db_engine import registrar_manejadores_bd
from app.core.logging_config import configurar_logging
from app.core.monitoring import MetricsMiddleware, metrics_text
from app.core.notification_scheduler import get_notification_scheduler
from app.core.rate_limit import RateLimitMiddleware
from app.core.scale_session import get_scale_session_manager
from app.models import VinculoBalanzaIndicador
from app.services.semaforo_service import get_semaforo_controller
from app.services.vinculo_service import VINCULO_MGR

log = configurar_logging(
    nivel=settings.log_level,
    formato=settings.log_format,
    directorio=settings.log_dir,
    max_bytes=settings.log_max_bytes,
    backup_count=settings.log_backup_count,
)
API_VERSION = "1.0.0"

ROUTERS = SERVER_ROUTERS if settings.app_role == "server" else API_ROUTERS

_origins = settings.cors_origins_list
if "*" in _origins and settings.app_env != "development":
    log.warning(
        "⚠  CORS permite '*' en entorno no-desarrollo (%s). "
        "Esto debería restringirse en producción.",
        settings.app_env,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info(
        "Balansoft-WS API iniciando (env=%s, rol=%s)", settings.app_env, settings.app_role
    )
    programador = get_notification_scheduler()
    programador.iniciar()
    await get_semaforo_controller().asegurar_activos()
    
    try:
        async with AsyncSessionLocal() as db:
            res = await db.execute(
                select(VinculoBalanzaIndicador).where(VinculoBalanzaIndicador.activo == True)
            )
            for vinc in res.scalars().all():
                try:
                    await VINCULO_MGR.iniciar(db, vinc.id_empresa, vinc)
                except Exception as exc:
                    log.debug("No se pudo restaurar vínculo %s: %s", vinc.id_vinculo, exc)
            log.info("Vínculos activos restaurados")
    except Exception as exc:
        log.debug("Error restaurando vínculos: %s", exc)
        
    yield
    
    await programador.detener()
    await get_semaforo_controller().detener_todas()
    try:
        await VINCULO_MGR.detener_todos()
    except Exception:
        pass
    await get_scale_session_manager().cerrar_todas()
    log.info("Balansoft-WS API detenida")


app = FastAPI(
    title=settings.app_name,
    version=API_VERSION,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials="*" not in _origins,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(AuditMiddleware)
if settings.rate_limit_enabled:
    app.add_middleware(RateLimitMiddleware)
if settings.metrics_enabled:
    app.add_middleware(MetricsMiddleware)

# Registro de routers SIN prefijo global
for router in ROUTERS:
    app.include_router(router)

registrar_manejadores_bd(app)

os.makedirs(settings.media_dir, exist_ok=True)
app.mount("/media", StaticFiles(directory=settings.media_dir), name="media")


@app.get("/api/v1/health", tags=["Health"])
async def health() -> dict:
    return {
        "status": "healthy",
        "version": API_VERSION,
        "timestamp": datetime.now(UTC).isoformat(),
        "central": {
            "timeout_s": settings.central_timeout,
            "max_intentos": _MAX_INTENTOS_CENTRAL,
        },
    }


@app.get("/metrics", include_in_schema=False)
async def metrics_endpoint() -> Response:
    return Response(content=metrics_text(), media_type="text/plain; charset=utf-8")
