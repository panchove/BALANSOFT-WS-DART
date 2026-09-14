"""Middleware de auditoría automática para operaciones write."""

from __future__ import annotations

import logging
import time
from collections.abc import Callable

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

log = logging.getLogger("balansoft_ws.audit")

# Métodos HTTP que se consideran "escritura"
WRITE_METHODS = {"POST", "PUT", "PATCH", "DELETE"}

# Rutas que se excluyen de auditoría (health, docs, etc.)
EXCLUDED_PATHS = {"/api/v1/health", "/docs", "/redoc", "/openapi.json"}


class AuditMiddleware(BaseHTTPMiddleware):
    """Registra automáticamente cada operación write en logs_sistema."""

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        if request.method not in WRITE_METHODS:
            return await call_next(request)

        if request.url.path in EXCLUDED_PATHS:
            return await call_next(request)

        start = time.monotonic()
        response = await call_next(request)
        elapsed_ms = int((time.monotonic() - start) * 1000)

        try:
            from app.core.database import AsyncSessionLocal
            from app.models import LogSistema

            async with AsyncSessionLocal() as session:
                log_entry = LogSistema(
                    nivel="INFO" if response.status_code < 400 else "WARNING",
                    modulo="audit",
                    mensaje=(
                        f"{request.method} {request.url.path} "
                        f"-> {response.status_code} ({elapsed_ms}ms)"
                    ),
                    detalle={
                        "method": request.method,
                        "path": str(request.url.path),
                        "status": response.status_code,
                        "elapsed_ms": elapsed_ms,
                        "query": str(request.url.query) if request.url.query else None,
                    },
                )
                session.add(log_entry)
                await session.commit()
        except Exception:
            log.debug("Audit write failed (non-critical)", exc_info=True)

        return response
