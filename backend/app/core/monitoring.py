"""Métricas y monitoreo de Balansoft-WS (prometheus-client).

Métricas:
- ``balansoft_http_requests_total`` — contador de requests por método, ruta, status.
- ``balansoft_http_request_duration_seconds`` — histograma de latencia.
- ``balansoft_pesajes_total`` — pesajes por estatus y tier.
- ``balansoft_license_errors_total`` — errores de licencia por tier y reason.
"""

from __future__ import annotations

import re
import time
from collections.abc import Callable

from fastapi import Request, Response
from prometheus_client import Counter, Histogram, generate_latest
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.config import settings

# ---------------------------------------------------------------------------
# Histogramas / contadores
# ---------------------------------------------------------------------------

# Cardinalidad de endpoints se acota sustituyendo UUIDs y IDs numéricos.
_PATH_PATTERN = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
    re.IGNORECASE,
)
_NUM_PATH = re.compile(r"\b\d+\b")

REQUEST_COUNT = Counter(
    "balansoft_http_requests_total",
    "Total de requests HTTP",
    ["method", "endpoint", "status"],
)

REQUEST_LATENCY = Histogram(
    "balansoft_api_latency_seconds",
    "Latencia de API por endpoint",
    ["method", "endpoint"],
    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)

PESAJES_TOTAL = Counter(
    "balansoft_pesajes_total",
    "Total de pesajes creados/cerrados",
    ["estatus", "tier"],
)

LICENSE_ERRORS = Counter(
    "balansoft_license_errors_total",
    "Errores de licencia (LM inalcanzable o inválida)",
    ["tier", "reason"],
)

ACTIVE_USERS = Counter(
    "balansoft_active_users",
    "Sesiones activas estimadas (login exitoso)",
    ["tier"],
)


# ---------------------------------------------------------------------------
# Helper de normalización de paths
# ---------------------------------------------------------------------------

def _normalize_path(path: str) -> str:
    """Reemplaza UUIDs y segmentos numéricos por ``{id}``."""
    path = _PATH_PATTERN.sub("{id}", path)
    path = _NUM_PATH.sub("{id}", path)
    # Asegurar prefijo /api/v1 si falta
    if not path.startswith("/api/"):
        path = "/api/v1" + path
    return path


# ---------------------------------------------------------------------------
# Middleware de métricas HTTP
# ---------------------------------------------------------------------------

class MetricsMiddleware(BaseHTTPMiddleware):
    """Middleware ASGI puro que registra requests y latencia."""

    async def dispatch(self, request: Request, call_next: Callable) -> Response:  # type: ignore[override]
        if not settings.metrics_enabled:
            return await call_next(request)

        start = time.monotonic()
        response = await call_next(request)
        elapsed = time.monotonic() - start

        endpoint = _normalize_path(request.url.path)
        method = request.method
        status = str(response.status_code)

        REQUEST_COUNT.labels(method=method, endpoint=endpoint, status=status).inc()
        REQUEST_LATENCY.labels(method=method, endpoint=endpoint).observe(elapsed)

        return response


# ---------------------------------------------------------------------------
# Helpers para contadores de negocio (llamar desde endpoints)
# ---------------------------------------------------------------------------

def inc_pesaje_creado(tier: str) -> None:
    PESAJES_TOTAL.labels(estatus="PENDIENTE", tier=tier).inc()


def inc_pesaje_cerrado(tier: str) -> None:
    PESAJES_TOTAL.labels(estatus="CERRADO", tier=tier).inc()


def inc_pesaje_anulado(tier: str) -> None:
    PESAJES_TOTAL.labels(estatus="ANULADO", tier=tier).inc()


def inc_license_error(tier: str, reason: str) -> None:
    LICENSE_ERRORS.labels(tier=tier, reason=reason).inc()


def inc_active_user(tier: str) -> None:
    ACTIVE_USERS.labels(tier=tier).inc()


def metrics_text() -> bytes:
    """Serializa todas las métricas en formato Prometheus text."""
    return generate_latest()
