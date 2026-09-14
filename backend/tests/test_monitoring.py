"""Tests de monitoreo (app/core/monitoring.py).

Verifica:
1. La normalización de paths colapsa UUIDs y números.
2. El middleware incrementa contadores por request.
3. Los contadores de negocio funcionan correctamente.
4. El endpoint /metrics retorna texto Prometheus válido.
"""

from __future__ import annotations

from fastapi import FastAPI, Request
from starlette.testclient import TestClient

from app.core.monitoring import (
    LICENSE_ERRORS,
    PESAJES_TOTAL,
    REQUEST_COUNT,
    MetricsMiddleware,
    _normalize_path,
    inc_license_error,
    inc_pesaje_anulado,
    inc_pesaje_cerrado,
    inc_pesaje_creado,
    metrics_text,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _counter_value(metric, **labels) -> float:
    """Valor de un contador prometheus-client por etiquetas."""
    for key, child in metric._metrics.items():
        child_labels = dict(zip(metric._labelnames, key, strict=True))
        if child_labels == labels:
            for sample in child._child_samples():
                if sample.name == "_total":
                    return sample.value
    return 0.0


def _reset_business():
    PESAJES_TOTAL._metrics.clear()
    LICENSE_ERRORS._metrics.clear()


# ---------------------------------------------------------------------------
# Tests de normalización de paths
# ---------------------------------------------------------------------------


def test_normalize_uuid_reemplaza_por_id():
    assert _normalize_path(
        "/api/v1/weighing/boleto/550e8400-e29b-41d4-a716-446655440000"
    ) == "/api/v1/weighing/boleto/{id}"


def test_normalize_numero_reemplaza_por_id():
    assert _normalize_path("/api/v1/weighing/boleto/42") == "/api/v1/weighing/boleto/{id}"


def test_normalize_prefijo_si_falta():
    assert _normalize_path("/api/v1/health") == "/api/v1/health"
    assert _normalize_path("/health") == "/api/v1/health"


# ---------------------------------------------------------------------------
# Tests del middleware
# ---------------------------------------------------------------------------


def _make_test_app() -> FastAPI:
    app = FastAPI()

    @app.get("/api/v1/health")
    async def _health(request: Request):
        return {"ok": True}

    @app.get("/api/v1/weighing/list")
    async def _list(request: Request):
        return {"ok": True}

    app.add_middleware(MetricsMiddleware)
    return app


def test_middleware_incrementa_contador():
    REQUEST_COUNT._metrics.clear()
    app = _make_test_app()
    client = TestClient(app)

    client.get("/api/v1/health")
    client.get("/api/v1/health")

    assert _counter_value(
        REQUEST_COUNT,
        method="GET",
        endpoint="/api/v1/health",
        status="200",
    ) == 2.0


def test_middleware_no_registra_si_desactivado():
    from app.core import config as _cfg

    REQUEST_COUNT._metrics.clear()
    original = _cfg.settings.metrics_enabled
    _cfg.settings.metrics_enabled = False
    try:
        app = FastAPI()

        @app.get("/api/v1/health")
        async def _health(request: Request):
            return {"ok": True}

        app.add_middleware(MetricsMiddleware)
        TestClient(app).get("/api/v1/health")
        assert _counter_value(
            REQUEST_COUNT, method="GET", endpoint="/api/v1/health", status="200"
        ) == 0.0
    finally:
        _cfg.settings.metrics_enabled = original


# ---------------------------------------------------------------------------
# Tests de contadores de negocio
# ---------------------------------------------------------------------------


def test_inc_pesajes_creado_cerrado_anulado():
    _reset_business()
    inc_pesaje_creado("CENTRAL")
    inc_pesaje_creado("CENTRAL")
    inc_pesaje_cerrado("CENTRAL")
    inc_pesaje_anulado("DEMO")

    assert _counter_value(PESAJES_TOTAL, estatus="PENDIENTE", tier="CENTRAL") == 2.0
    assert _counter_value(PESAJES_TOTAL, estatus="CERRADO", tier="CENTRAL") == 1.0
    assert _counter_value(PESAJES_TOTAL, estatus="ANULADO", tier="DEMO") == 1.0


def test_inc_license_errors():
    _reset_business()
    inc_license_error("CENTRAL", "login")
    inc_license_error("DEMO", "validate")

    assert _counter_value(LICENSE_ERRORS, tier="CENTRAL", reason="login") == 1.0
    assert _counter_value(LICENSE_ERRORS, tier="DEMO", reason="validate") == 1.0


# ---------------------------------------------------------------------------
# Test de /metrics (texto Prometheus)
# ---------------------------------------------------------------------------


def test_metrics_serializa_texto_prometheus():
    _reset_business()
    inc_pesaje_creado("CENTRAL")
    text = metrics_text().decode()

    assert "balansoft_pesajes_total" in text
    assert 'estatus="PENDIENTE"' in text
    assert 'tier="CENTRAL"' in text