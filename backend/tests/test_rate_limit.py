"""Tests del rate limiter (app/core/rate_limit.py).

Utiliza una mini-app FastAPI con el middleware habilitado y rutas dummy.
Es 100 % hermético (sin base de datos).
"""

from __future__ import annotations

import asyncio
import json
import time

import httpx
import pytest
from fastapi import FastAPI, Request
from starlette.testclient import TestClient

from app.core import config as _config
from app.core.rate_limit import RateLimitMiddleware, reset_limiter_cache


@pytest.fixture(autouse=True)
def _clean():
    """Restablece el cache del limiter y config entre tests."""
    reset_limiter_cache()
    yield
    reset_limiter_cache()
    _config.settings.rate_limit_login = 5
    _config.settings.rate_limit_register = 3
    _config.settings.rate_limit_password = 5
    _config.settings.rate_limit_trust_proxy = False


# ---------------------------------------------------------------------------
# Helpers: mini-app de prueba
# ---------------------------------------------------------------------------

def _make_app(rate_limit_login: int = 2, trust_proxy: bool = False) -> FastAPI:
    app = FastAPI()

    @app.post("/api/v1/auth/login")
    async def _login(request: Request):
        return {"ok": True}

    @app.post("/api/v1/auth/forgot-password")
    async def _forgot_password(request: Request):
        return {"ok": True}

    @app.get("/api/v1/health")
    async def _health(request: Request):
        return {"ok": True}

    @app.get("/metrics")
    async def _metrics(request: Request):
        return {"ok": True}

    _config.settings.rate_limit_login = rate_limit_login
    _config.settings.rate_limit_register = 100  # alto, no se prueba aquí
    _config.settings.rate_limit_password = 100
    _config.settings.rate_limit_trust_proxy = trust_proxy

    app.add_middleware(RateLimitMiddleware)
    return app


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_health_no_esta_limitado():
    """GET /api/v1/health nunca debe retornar 429 aunque sea infinito."""
    client = TestClient(_make_app(rate_limit_login=2))
    for _ in range(20):
        r = client.get("/api/v1/health")
        assert r.status_code == 200


def test_metrics_no_esta_limitado():
    client = TestClient(_make_app(rate_limit_login=2))
    for _ in range(20):
        r = client.get("/metrics")
        assert r.status_code == 200


def test_login_se_limita_por_ip():
    """POST /login con el mismo IP supera el límite y devuelve 429."""
    app = _make_app(rate_limit_login=2)
    client = TestClient(app)
    body = {"email": "a@test.com", "password": "x"}
    r1 = client.post("/api/v1/auth/login", json=body)
    r2 = client.post("/api/v1/auth/login", json=body)
    r3 = client.post("/api/v1/auth/login", json=body)

    assert r1.status_code == 200
    assert r2.status_code == 200
    assert r3.status_code == 429
    assert r3.json()["detail"] == "Demasiadas peticiones. Intente más tarde."
    assert "Retry-After" in r3.headers


def test_login_key_separada_por_email():
    """Distinto email genera distinta clave: uno limitado no bloquea al otro."""
    app = _make_app(rate_limit_login=1)
    client = TestClient(app)

    r1 = client.post("/api/v1/auth/login", json={"email": "a@test.com", "password": "x"})
    assert r1.status_code == 200

    r2 = client.post("/api/v1/auth/login", json={"email": "a@test.com", "password": "x"})
    assert r2.status_code == 429  # misma clave

    r3 = client.post("/api/v1/auth/login", json={"email": "b@test.com", "password": "x"})
    assert r3.status_code == 200  # distinta clave


def test_forgot_password_limitado_independiente():
    """forgot-password y login tienen claves independientes."""
    app = _make_app(rate_limit_login=1)
    client = TestClient(app)

    r1 = client.post("/api/v1/auth/login", json={"email": "a@test.com", "password": "x"})
    assert r1.status_code == 200

    r2 = client.post("/api/v1/auth/login", json={"email": "a@test.com", "password": "x"})
    assert r2.status_code == 429

    r3 = client.post("/api/v1/auth/forgot-password", json={"email": "a@test.com"})
    assert r3.status_code == 200  # clave diferente (/forgot-password vs /login)


def test_body_legible_despues_del_middleware():
    """El body del POST sigue llegando al handler correctamente."""
    received_emails: list[str] = []

    app = FastAPI()

    @app.post("/api/v1/auth/login")
    async def _login_handler(request: Request):
        body = await request.body()
        data = json.loads(body)
        received_emails.append(data.get("email"))
        return {"ok": True}

    app.add_middleware(RateLimitMiddleware)
    client = TestClient(app)

    client.post("/api/v1/auth/login", json={"email": "test@test.com", "password": "x"})
    assert received_emails == ["test@test.com"]


def test_xyf_trust_proxy_ip_real():
    """Sin trust_proxy, X-Forwarded-For se ignora y la IP real acumula."""
    app = _make_app(rate_limit_login=2, trust_proxy=False)
    client = TestClient(app)
    body = {"email": "a@test.com", "password": "x"}

    client.post("/api/v1/auth/login", json=body)
    r2 = client.post(
        "/api/v1/auth/login",
        json=body,
        headers={"X-Forwarded-For": "1.2.3.4"},
    )
    assert r2.status_code == 200  # misma IP real, misma clave → acumula


def test_xyf_trust_proxy_independiente():
    """Con trust_proxy, X-Forwarded-For crea claves diferentes."""
    app = _make_app(rate_limit_login=1, trust_proxy=True)
    client = TestClient(app)
    body = {"email": "a@test.com", "password": "x"}

    r1 = client.post(
        "/api/v1/auth/login",
        json=body,
        headers={"X-Forwarded-For": "1.1.1.1, 2.2.2.2"},
    )
    assert r1.status_code == 200

    r2 = client.post(
        "/api/v1/auth/login",
        json=body,
        headers={"X-Forwarded-For": "1.1.1.1, 3.3.3.3"},
    )
    # misma IP primaria → misma clave → excede
    assert r2.status_code == 429


# ---------------------------------------------------------------------------
# Sliding window real + concurrencia
# ---------------------------------------------------------------------------


def test_sliding_window_real():
    """Ventana deslizante: los hits fuera de la ventana expiran y se permite.

    Con una ventana de 1 s y límite 3, tras esperar >1 s los hits previos se
    podan (línea de corte por timestamp), no por bucket de ventana fija.
    """
    _config.settings.rate_limit_window = 1  # ventana de 1 segundo
    _config.settings.rate_limit_login = 3
    app = _make_app(rate_limit_login=3)
    client = TestClient(app)
    body = {"email": "a@test.com", "password": "x"}

    reset_limiter_cache()
    for _ in range(3):
        assert client.post("/api/v1/auth/login", json=body).status_code == 200
    # 4º dentro de la ventana → 429
    assert client.post("/api/v1/auth/login", json=body).status_code == 429

    time.sleep(1.1)  # la ventana se desliza y los 3 hits previos expiran

    assert client.post("/api/v1/auth/login", json=body).status_code == 200


@pytest.mark.asyncio
async def test_rate_limit_concurrent():
    """10 requests concurrentes → exactamente 5 pasan y 5 reciben 429.

    Ejercita el Lock interno: sin un lock correcto habría más de 5 aciertos
    (race condition sobre el conteo).
    """
    app = _make_app(rate_limit_login=5)
    transport = httpx.ASGITransport(app=app)
    body = {"email": "a@test.com", "password": "x"}

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:

        async def hit():
            return await ac.post("/api/v1/auth/login", json=body)

        results = await asyncio.gather(*[hit() for _ in range(10)])
        statuses = [r.status_code for r in results]

    assert statuses.count(200) == 5
    assert statuses.count(429) == 5


@pytest.mark.asyncio
async def test_rate_limit_concurrent_distintas_claves():
    """Con 3 emails distintos cada uno tiene su propio contador."""
    app = _make_app(rate_limit_login=1)
    transport = httpx.ASGITransport(app=app)

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:

        async def hit(email: str):
            return await ac.post(
                "/api/v1/auth/login", json={"email": email, "password": "x"}
            )

        # 3 emails × 2 llamadas concurrentes → solo 1 por email pasa
        emails = ["a@test.com", "b@test.com", "c@test.com"]
        results = await asyncio.gather(
            *[hit(e) for e in emails for _ in range(2)]
        )
        statuses = [r.status_code for r in results]

    assert statuses.count(200) == 3
    assert statuses.count(429) == 3