"""Pruebas del parser multi-marca de tramas de báscula.

``app/core/scale_parser.py`` es un módulo **puro** (sin red, serial ni BD): lo
comparten ``SerialScaleHAL`` y ``TcpScaleHAL`` para que la robustez numérica viva
en un único sitio y sea testeable sin hardware. Estas pruebas fijan el contrato
de las tramas reales (Toledo/GSI, Rice Lake/iQ, MT-SICS) y, sobre todo, el
**principio anti-falso-positivo**: un número desnudo nunca se acepta como peso.
"""

from __future__ import annotations

import pytest

from app.core.scale_parser import clasificar_trama, parse_weight_frame

# ---------------------------------------------------------------------------
# Tramas reales: (línea, peso esperado, status esperado, motivo esperado)
# ---------------------------------------------------------------------------
CASOS_REALES: list[tuple[str, float | None, str | None, str | None]] = [
    # Toledo/GSI: ST (estable), GS (bruto), signo, ceros de relleno, unidad.
    ("ST,GS,+00320.00kg", 320.0, "stable", None),
    # Espacio entre signo y dígitos (indicadores que alinean a la derecha).
    ("ST,GS,+  320.00 kg", 320.0, "stable", None),
    ("ST,GS,-00012.50kg", -12.5, "stable", None),
    # Rice Lake / iQ: dirección adherida al número con signo embebido.
    ("01+000320.0", 320.0, None, None),
    ("01-000015.5", -15.5, None, None),
    # Signo suelto en un token propio (habitual en tramas de campos).
    ("  -  12.50KG", -12.5, None, None),
    # Inestable / sobrecarga.
    ("US,GS,+00100.0kg", 100.0, "unstable", None),
    ("OL", None, "overload", "sobrecarga"),
    # Cero con unidad.
    ("ST,GS,    0.00 kg", 0.0, "stable", None),
    # Sin prefijo de estado, con unidad (flujo continuo crudo).
    ("320.00kg", 320.0, None, None),
    # Yaohua XK3190 (indicadores chinos estilo "="): modo PC continuo de 10
    # bytes `= + 8 datos + stop`, con o sin espacios, sin token de estado.
    ("=+000023.5kg", 23.5, None, None),
    ("=+000000.0kg", 0.0, None, None),
    ("=-001234.0kg", -1234.0, None, None),
    ("= 00023.5 kg", 23.5, None, None),
    # Torrey LQ (México) en salida continua: mismo formato Toledo/GSI.
    ("ST,GS,+00042.5kg", 42.5, "stable", None),
    # Keli (indicador clon Toledo, división de 1 decimal).
    ("ST,GS,+00320.0kg", 320.0, "stable", None),
]

# Rechazos: (línea, motivo esperado)
CASOS_RECHAZO: list[tuple[str, str]] = [
    # Número desnudo: la dirección ``01`` o un checksum NO son un peso.
    ("1234567890", "sin_numero"),
    ("01", "sin_numero"),
    # Dos números distintos: ambiguo (mejor None que un peso equivocado).
    ("123.4 567.8", "ambiguo"),
    # Prefijo "=" (Yaohua) + entero desnudo sin signo/decimal/unidad: rechazar.
    ("=000001", "sin_numero"),
]


@pytest.mark.parametrize(
    "linea,peso,status,motivo", CASOS_REALES, ids=[c[0].strip() or "vacio" for c in CASOS_REALES]
)
def test_parse_weight_frame_tramas_reales(linea, peso, status, motivo):
    assert parse_weight_frame(linea) == (peso, status, motivo)


@pytest.mark.parametrize("linea,motivo", CASOS_RECHAZO)
def test_parse_weight_frame_rechaza_falsos_positivos(linea, motivo):
    valor, _status, razon = parse_weight_frame(linea)
    assert valor is None
    assert razon == motivo


def test_conserva_el_signo_negativo():
    """Regresión: ``-  12.50KG`` antes se leía como +12.5 (signo perdido)."""
    valor, _status, motivo = parse_weight_frame("-  12.50KG")
    assert valor == -12.5
    assert motivo is None


def test_direccion_adherida_con_signo_embebido():
    """``01+000320.0`` antes devolvía ``None``; ahora se lee el peso."""
    assert parse_weight_frame("01+000320.0")[0] == 320.0


# ---------------------------------------------------------------------------
# Vacío / checksum / capacidad / precisión
# ---------------------------------------------------------------------------
def test_linea_vacia():
    assert parse_weight_frame("") == (None, None, "vacio")
    assert parse_weight_frame("   ") == (None, None, "vacio")


def test_checksum_valido_se_acepta():
    # XOR de los bytes de ``ST,GS,+00320.00kg`` == 0x2B.
    trama = "\x02ST,GS,+00320.00kg\x032B"
    assert parse_weight_frame(trama, validar_checksum=True) == (320.0, "stable", None)


def test_checksum_invalido_se_rechaza():
    trama = "\x02ST,GS,+00320.00kg\x0300"
    valor, status, motivo = parse_weight_frame(trama, validar_checksum=True)
    assert valor is None
    assert status is None
    assert motivo == "checksum"


def test_stx_etx_sin_checksum_tambien_parsea():
    trama = "\x02ST,GS,+00320.00kg\x03"
    assert parse_weight_frame(trama) == (320.0, "stable", None)


def test_etx_suelto_en_payload_no_rompe_el_numero():
    """Regresión L1: un frame leído con ``readuntil(b'\\x03')`` conserva el ETX
    final; el parser debe quitarlo (con signo o sin él) para leer el peso.
    """
    assert parse_weight_frame("ST,GS,320.00kg\x03") == (320.0, "stable", None)
    assert parse_weight_frame("ST,GS,+00320.00kg\x03") == (320.0, "stable", None)


def test_sobre_capacidad():
    valor, _status, motivo = parse_weight_frame(
        "ST,GS,+00320.00kg", capacidad_max=100
    )
    assert valor is None
    assert motivo == "sobre_capacidad"


def test_capacidad_dentro_del_margen_tolerado():
    # 105 == 100 * 1.05 exacto: todavía admisible (no es > capacidad*1.05).
    valor, _status, motivo = parse_weight_frame(
        "ST,GS,+00105.00kg", capacidad_max=100
    )
    assert valor == 105.0
    assert motivo is None


def test_precision_excesiva():
    valor, _status, motivo = parse_weight_frame("ST,GS,+00320.0001kg")
    assert valor is None
    assert motivo == "precision"


# ---------------------------------------------------------------------------
# clasificar_trama: auto-detección JSON vs ASCII (la usa TcpScaleHAL)
# ---------------------------------------------------------------------------
def test_clasificar_json_del_simulador():
    assert clasificar_trama('{"weight_kg": 12.3, "status": "stable"}') == "json"


def test_clasificar_json_sin_weight_kg_no_es_json():
    assert clasificar_trama('{"action": "get_state"}') is None


def test_clasificar_ascii():
    assert clasificar_trama("ST,GS,+00320.00kg") == "ascii"


def test_clasificar_basura():
    assert clasificar_trama("no-es-json") is None
    assert clasificar_trama("") is None
