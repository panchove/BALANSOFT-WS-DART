"""Pruebas unitarias de helpers puros del rol servidor.

Cubren la lógica sin BD ni HTTP: normalización de estados del LM, límites por
tier, conversión UTC y resolución de ``hardware_id``.
"""
from datetime import datetime, timedelta, timezone

from app.api.v1.endpoints.servidor import (
    _licencia_vigente,
    _limite_por_tier,
    _max_sesiones_default,
    _naive_utc,
    _normalizar_estado_lm,
)
from app.core.hardware import obtener_hardware_id


def test_naive_utc_convierte_solo_los_aware():
    assert _naive_utc(None) is None

    naive = datetime(2026, 9, 29, 13, 0, 0)
    assert _naive_utc(naive) is naive

    aware = datetime(2026, 9, 29, 9, 30, tzinfo=timezone(-timedelta(hours=4)))
    out = _naive_utc(aware)
    assert out == datetime(2026, 9, 29, 13, 30, 0)
    assert out.tzinfo is None


def test_max_sesiones_por_tier():
    assert _max_sesiones_default("DEMO") == 3
    assert _max_sesiones_default("demo") == 3
    assert _max_sesiones_default("CENTRAL") is None
    assert _max_sesiones_default("AUTO") is None
    assert _max_sesiones_default("") is None
    assert _max_sesiones_default(None) is None


def test_limite_por_tier():
    assert _limite_por_tier("DEMO", "dispositivos") == 1
    assert _limite_por_tier("demo", "usuarios") == 1
    assert _limite_por_tier("CENTRAL", "dispositivos") is None
    assert _limite_por_tier("AUTO", "usuarios") is None


def test_licencia_vigente():
    # `_licencia_vigente` opera sobre estados YA normalizados (ACTIVA/AVAILABLE);
    # los estados crudos del LM se pasan antes por `_normalizar_estado_lm`.
    for vigente in ("ACTIVA", "AVAILABLE", "activa", "available"):
        assert _licencia_vigente(vigente) is True
    for no in (
        "SUSPENDIDA",
        "VENCIDA",
        "INACTIVA",
        "SUSPENSIVE",
        "VENCIDO",
        "REVOCADA",
        "",
    ):
        assert _licencia_vigente(no) is False
    assert _licencia_vigente(None) is False


def test_normalizar_estado_lm():
    casos = {
        "ACTIVE": "ACTIVA",
        "ACTIVA": "ACTIVA",
        "VIGENTE": "ACTIVA",
        "AVAILABLE": "ACTIVA",
        "DEVICE_NOT_REGISTERED": "ACTIVA",
        "SUSPENDED": "SUSPENDIDA",
        "SUSPENDIDA": "SUSPENDIDA",
        "EXPIRED": "VENCIDA",
        "VENCIDA": "VENCIDA",
        "INACTIVE": "INACTIVA",
        "INACTIVA": "INACTIVA",
    }
    for entrada, esperado in casos.items():
        assert _normalizar_estado_lm(entrada) == esperado
    assert _normalizar_estado_lm(None) == "ACTIVA"
    assert _normalizar_estado_lm("OTRO") == "OTRO"


def test_hardware_id_override(monkeypatch):
    monkeypatch.setenv("HARDWARE_ID", "HW-FIJO-01")
    assert obtener_hardware_id() == "HW-FIJO-01"


def test_hardware_id_fallback_no_vacio(monkeypatch):
    monkeypatch.delenv("HARDWARE_ID", raising=False)
    hid = obtener_hardware_id()
    assert hid and hid.strip()