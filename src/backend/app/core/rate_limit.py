"""Rate limiter propio con cachetools.TTLCache (sin dependencias externas).

Diseño:
- Sliding window por clave (IP + email del body para endpoints de auth).
- Thread-safe (Lock por instancia).
- Los límites se consultan en Settings; cuando ``rate_limit_enabled=False``
  el middleware no se registra y todo funciona como si no existiera.

Nota: cada proceso de uvicorn lleva su propia cuenta (no distribuido). Es
suficiente como defensa brute-force; para multi-worker estricto usar Redis.
"""

from __future__ import annotations

import json
import logging
import time
from collections.abc import Awaitable, Callable, MutableMapping
from threading import Lock
from typing import Any

from cachetools import TTLCache
from fastapi.responses import JSONResponse

from app.core.config import settings

log = logging.getLogger("balansoft_ws.rate_limit")

Message = dict[str, Any]
Receive = Callable[[], Awaitable[Message]]
Send = Callable[[MutableMapping[str, Any]], Awaitable[None]]

# ---------------------------------------------------------------------------
# Límites por endpoint: path_suffix → (setting_key, default_limit)
# ---------------------------------------------------------------------------

_AUTH_PATHS: dict[str, tuple[str, int]] = {
    "/login": ("rate_limit_login", 5),
    "/register": ("rate_limit_register", 3),
    "/forgot-password": ("rate_limit_password", 5),
    "/reset-password": ("rate_limit_password", 5),
}


def _resolve_limit(setting_key: str, default: int) -> tuple[int, int]:
    return getattr(settings, setting_key, default), settings.rate_limit_window


# ---------------------------------------------------------------------------
# Limiter — sliding window sencillo
# ---------------------------------------------------------------------------

class RateLimiter:
    """Límite por clave usando una ventana deslizante (no fija)."""

    def __init__(self, window_seconds: int) -> None:
        self._cache: TTLCache[str, list[float]] = TTLCache(
            maxsize=20000,
            ttl=float(window_seconds),
        )
        self._lock = Lock()

    def is_limited(self, key: str, max_calls: int, window: int) -> bool:
        now = time.monotonic()
        cutoff = now - window
        with self._lock:
            hits = self._cache.get(key)
            if hits is None:
                self._cache[key] = [now]
                return False
            hits = [t for t in hits if t >= cutoff]
            if len(hits) >= max_calls:
                self._cache[key] = hits
                return True
            hits.append(now)
            self._cache[key] = hits
            return False


_limiter = RateLimiter(window_seconds=settings.rate_limit_window)


def reset_limiter_cache() -> None:
    """Limpia el cache del limiter (para tests)."""
    _limiter._cache.clear()


# ---------------------------------------------------------------------------
# Helpers de clave
# ---------------------------------------------------------------------------

def _client_ip(scope: Message) -> str:
    headers = {k.decode().lower(): v.decode() for k, v in scope.get("headers", [])}
    if settings.rate_limit_trust_proxy:
        xff = headers.get("x-forwarded-for")
        if xff:
            return xff.split(",")[0].strip()
    client = scope.get("client")
    return client[0] if client else "unknown"


def _parse_email(body: bytes) -> str | None:
    if not body:
        return None
    try:
        data = json.loads(body)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    if isinstance(data, dict):
        email = str(data.get("email", "")).lower().strip()
        return email or None
    return None


def _match_auth_route(path: str) -> tuple[str, int, int] | None:
    for suffix, (setting_key, default) in _AUTH_PATHS.items():
        if path.endswith(suffix):
            max_calls, window = _resolve_limit(setting_key, default)
            return f"{suffix}:{max_calls}:{window}", max_calls, window
    return None


async def _read_body(scope: Message, receive: Receive) -> bytes:
    """Lee el body completo de una sola pasada."""
    body = b""
    while True:
        message = await receive()
        if message["type"] != "http.request":
            break
        body += message.get("body", b"")
        if not message.get("more_body", False):
            break
    return body


def _replay_receive(body: bytes, receive: Receive) -> Receive:
    """Devuelve un ``receive`` que reemite *body* y luego delega."""
    sent = False

    async def replay() -> Message:
        nonlocal sent
        if not sent:
            sent = True
            return {"type": "http.request", "body": body, "more_body": False}
        return await receive()

    return replay


# ---------------------------------------------------------------------------
# Middleware
# ---------------------------------------------------------------------------

class RateLimitMiddleware:
    """Middleware ASGI de rate-limiting.

    Solo aplica a las 4 rutas de autenticación definidas en ``_AUTH_PATHS``.
    ``/health``, ``/metrics`` y el resto de rutas no se ven afectadas.
    """

    def __init__(self, app: Callable[..., Awaitable[None]]) -> None:
        self.app = app

    async def __call__(self, scope: Message, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            return await self.app(scope, receive, send)

        path: str = scope["path"]
        match = _match_auth_route(path)
        if match is None:
            return await self.app(scope, receive, send)

        route_key, max_calls, window = match
        ip = _client_ip(scope)

        email: str | None = None
        if scope.get("method") == "POST":
            body = await _read_body(scope, receive)
            email = _parse_email(body)
            receive = _replay_receive(body, receive)

        key = f"{ip}:{email}:{route_key}" if email else f"{ip}:{route_key}"

        if _limiter.is_limited(key, max_calls, window):
            log.warning("Rate limit excedido: %s", key)
            remaining = max(1, window)
            response = JSONResponse(
                status_code=429,
                content={"detail": "Demasiadas peticiones. Intente más tarde."},
                headers={"Retry-After": str(remaining)},
            )
            return await response(scope, receive, send)

        return await self.app(scope, receive, send)
