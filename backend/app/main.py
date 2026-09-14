"""Punto de entrada de la API de Balansoft-WS."""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from datetime import UTC, datetime

from fastapi import FastAPI, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.v1.endpoints import API_ROUTERS
from app.core.audit import AuditMiddleware
from app.core.config import settings
from app.core.monitoring import MetricsMiddleware, metrics_text
from app.core.rate_limit import RateLimitMiddleware

logging.basicConfig(
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("balansoft_ws")
API_VERSION = "1.0.0"

# --- CORS hardening --------------------------------------------------------
_origins = settings.cors_origins_list
if "*" in _origins and settings.app_env != "development":
    log.warning(
        "⚠  CORS permite '*' en entorno no-desarrollo (%s). "
        "Esto debería restringirse en producción.",
        settings.app_env,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info("Balansoft-WS API iniciando (env=%s)", settings.app_env)
    yield
    log.info("Balansoft-WS API detenida")


app = FastAPI(
    title=settings.app_name,
    version=API_VERSION,
    summary="API REST de estación de pesaje industrial para camiones (multi-empresa).",
    description=(
        "API REST de estación de pesaje industrial para camiones "
        "(multi-empresa). Autenticación JWT, boletos con máquina de estados "
        "PENDIENTE/CERRADO/MODIFICADO/ANULADO, kardex numérico (10 INGRESO / "
        "60 DESPACHO), auditoría, licencias (SGLB) y HAL de balanza para "
        "lectura de peso en vivo (serial/TCP).\n\n"
        "**Esquema de autenticación:** `Authorization: Bearer <access_token>` "
        "(JWT HS256). El refresco se realiza con `POST /api/v1/auth/refresh-token`.\n\n"
        "**Trazabilidad:** REQ-NF-ARQ-001 (multi-empresa), REQ-NF-ARQ-002 "
        "(máquina de estados del boleto), REQ-NF-ARQ-003 (kardex numérico), "
        "REQ-NF-ARQ-004 (estabilidad 3 s / HAL), REQ-NF-ARQ-007 (roles "
        "ADMIN/SUPERVISOR/OPERADOR), REQ-NF-SEG-001 (auditoría), "
        "REQ-NF-ARQ-010 (timestamps UTC)."
    ),
    openapi_tags=[
        {
            "name": "Health",
            "description": "Estado y versión de la API.",
        },
        {
            "name": "Authentication",
            "description": "Registro, login, refresh/logout, JWT y administración de licencias de la empresa.",
        },
        {
            "name": "Weighing",
            "description": "Boletos de pesaje (entrada/salida/cierre/anulación), pendientes y lectura de peso en vivo vía HAL (REQ-NF-ARQ-004).",
        },
        {
            "name": "Catalogo",
            "description": "Sincronización combinada de catálogos para operación offline.",
        },
        {
            "name": "Flota",
            "description": "Camiones y remolques.",
        },
        {
            "name": "Inventario",
            "description": "Productos, almacenes y balanzas.",
        },
        {
            "name": "Directorio",
            "description": "Transportes, conductores y terceros (clientes/proveedores).",
        },
        {
            "name": "Reports",
            "description": "Reportes diarios/mensuales/kardex y avanzados (transportista, tercero, rango de peso, comparativo mensual).",
        },
        {
            "name": "Sync",
            "description": "Sincronización offline-first entre estaciones y servidor.",
        },
        {
            "name": "Archivos",
            "description": "Subida/descarga de archivos adjuntos (fotos de pesajes).",
        },
    ],
    contact={
        "name": "Equipo BALANSOFT",
        "url": "https://balansoft.local",
    },
    docs_url="/docs" if settings.api_docs_enabled else None,
    redoc_url="/redoc" if settings.api_docs_enabled else None,
    lifespan=lifespan,
)

# --- Middleware (orden: último añadido = más externo) ------------------------
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

for router in API_ROUTERS:
    app.include_router(router)

os.makedirs(settings.media_dir, exist_ok=True)
app.mount("/media", StaticFiles(directory=settings.media_dir), name="media")


@app.get("/api/v1/health", tags=["Health"])
async def health() -> dict:
    return {
        "status": "healthy",
        "version": API_VERSION,
        "timestamp": datetime.now(UTC).isoformat(),
    }


@app.get("/metrics", include_in_schema=False)
async def metrics_endpoint() -> Response:
    return Response(content=metrics_text(), media_type="text/plain; charset=utf-8")
