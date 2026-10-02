"""Tests de monitoreo (app/core/monitoring.py).

Verifica:
1. La normalización de paths colapsa UUIDs y números.
2. El middleware incrementa contadores por request.
3. Los contadores de negocio funcionan correctamente.
4. El endpoint /metrics retorna texto Prometheus válido.
5. El andamiaje de observabilidad (deploy/observability) está completo,
   es válido y solo usa métricas que el backend expone de verdad.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest
from fastapi import FastAPI, Request
from starlette.testclient import TestClient

from app.core.monitoring import (
    LICENSE_ERRORS,
    PESAJES_TOTAL,
    REQUEST_COUNT,
    MetricsMiddleware,
    _normalize_path,
    inc_active_user,
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


def test_metrics_expone_las_cinco_metricas_documentadas():
    """El andamiaje de observabilidad (H6) documenta cinco métricas: si el
    backend deja de exponer alguna, el dashboard y las alertas quedan rotos."""
    _reset_business()
    inc_pesaje_creado("CENTRAL")
    inc_license_error("CENTRAL", "login")
    inc_active_user("CENTRAL")
    text = metrics_text().decode()

    for nombre in (
        "balansoft_http_requests_total",
        "balansoft_api_latency_seconds",
        "balansoft_pesajes_total",
        "balansoft_license_errors_total",
        "balansoft_active_users",
    ):
        assert nombre in text, f"falta la métrica documentada {nombre}"


# ---------------------------------------------------------------------------
# Andamiaje de observabilidad (H6)
# ---------------------------------------------------------------------------

DEPLOY_OBS = Path(__file__).resolve().parents[1] / "deploy" / "observability"
RUTAS_OBSERVABILIDAD = {
    "prometheus.yml",
    "alertmanager.yml",
    "alerts/balansoft-alerts.yml",
    "docker-compose.observability.yml",
    "grafana/provisioning/datasources/balansoft.yml",
    "grafana/provisioning/dashboards/dashboards.yml",
    "grafana/dashboards/balansoft-overview.json",
    "README.md",
}


def _metricas_de_backend() -> set[str]:
    """Nombres de métrica definidos en app/core/monitoring.py."""
    fuente = (Path(__file__).resolve().parents[1] / "app" / "core" / "monitoring.py").read_text(
        encoding="utf-8"
    )
    return set(re.findall(r'"\s*(balansoft_[a-z_]+?)(?:_bucket|_sum|_count)?\s*"', fuente))


def test_andamiaje_observabilidad_esta_completo():
    for relativa in RUTAS_OBSERVABILIDAD:
        assert (DEPLOY_OBS / relativa).is_file(), f"falta {relativa}"


def test_yaml_de_observabilidad_es_valido():
    yaml = pytest.importorskip("yaml")
    for relativa in RUTAS_OBSERVABILIDAD - {"grafana/dashboards/balansoft-overview.json"}:
        if not relativa.endswith((".yml", ".yaml")):
            continue
        datos = yaml.safe_load((DEPLOY_OBS / relativa).read_text(encoding="utf-8"))
        assert datos, f"{relativa} está vacío"


def test_dashboard_es_json_valido():
    datos = json.loads(
        (DEPLOY_OBS / "grafana" / "dashboards" / "balansoft-overview.json").read_text(
            encoding="utf-8"
        )
    )
    assert datos["panels"], "el dashboard no tiene paneles"
    assert datos["title"]


def test_alertas_y_dashboard_solo_usan_metricas_existentes():
    """Nada deReferences a métricas inexistentes: una alerta que nunca dispara
    es peor que no tenerla."""
    disponibles = _metricas_de_backend()
    assert disponibles, "no se pudo leer el catálogo de métricas del backend"

    exprs: list[str] = []
    yaml = pytest.importorskip("yaml")
    reglas = yaml.safe_load(
        (DEPLOY_OBS / "alerts" / "balansoft-alerts.yml").read_text(encoding="utf-8")
    )
    assert reglas["groups"], "no hay grupos de reglas"
    for grupo in reglas["groups"]:
        for regla in grupo["rules"]:
            assert {"alert", "expr"} <= regla.keys(), f"regla incompleta: {regla}"
            assert regla.get("labels", {}).get("severity"), f"sin severity: {regla['alert']}"
            assert regla.get("annotations", {}).get("runbook"), f"sin runbook: {regla['alert']}"
            exprs.append(str(regla["expr"]))

    dashboard = json.loads(
        (DEPLOY_OBS / "grafana" / "dashboards" / "balansoft-overview.json").read_text(
            encoding="utf-8"
        )
    )
    for panel in dashboard["panels"]:
        for target in panel.get("targets", []):
            exprs.append(target.get("expr", ""))

    # `up` es de Prometheus y `_bucket` es el sufijo del histograma.
    conocidas = disponibles | {"up"}
    patron = re.compile(r"\b(balansoft_[a-z_]+?)(?:_bucket|_sum|_count)?\b")
    for expr in exprs:
        for nombre in set(patron.findall(expr)):
            assert nombre in conocidas, f"la expresión usa una métrica inexistente: {nombre}"


def test_alertmanager_usa_nombres_de_receptor_como_texto():
    """En YAML `null` sin comillas es el VALOR nulo, no el nombre "null":
    Alertmanager rechaza el arranque con "missing name in receiver"."""
    datos = json.loads(
        json.dumps(__import__("yaml").safe_load(
            (DEPLOY_OBS / "alertmanager.yml").read_text(encoding="utf-8")))
    )
    assert datos["route"]["receiver"] == "null"
    nombres = [r["name"] for r in datos["receivers"]]
    assert "null" in nombres, f"falta el receptor nulo declarado: {nombres}"
    assert all(isinstance(n, str) for n in nombres), "algún receptor quedó como nulo"


def test_alertas_no_usan_id_empresa_como_label():
    """Multi-tenancy: /metrics es agregado. Filtrar por empresa convertiría el
    endpoint en una fuga de datos entre tenant."""
    texto = (DEPLOY_OBS / "alerts" / "balansoft-alerts.yml").read_text(encoding="utf-8")
    assert "id_empresa" not in texto
    prometheus = (DEPLOY_OBS / "prometheus.yml").read_text(encoding="utf-8")
    assert "id_empresa" not in prometheus