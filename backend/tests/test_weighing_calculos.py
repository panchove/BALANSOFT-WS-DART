"""Pruebas de los cálculos puros del servicio de pesaje (MODEL.md).

Cubre: PTE=PEc+PER, PTS=PSc+PSR, PNT=PTE-PTS, PND, PDF=PNT-PND, PDV=PDF/PND,
bruto/tara, litros y normalización de estados legacy.
"""

from __future__ import annotations

from decimal import Decimal

from app.services.weighing_service import (
    WeighingService,
    normalizar_estado,
)

Z = Decimal("0.00")
SVC = WeighingService()  # sin estado; _calcular es puro


class TestCalculoCierre:
    def test_entrada_sin_salida(self):
        r = SVC._calcular(Z, None, None, None)
        assert r["peso_total_entrada"] == Z
        assert r["peso_total_salida"] is None
        assert r["peso_neto"] is None
        assert r["peso_bruto"] == Z

    def test_peso_neto_parte_de_camion(self):
        # PTE=53000, PTS=48000 -> PNT=5000
        r = SVC._calcular(Decimal("53000"), None, Decimal("48000"), None)
        assert r["peso_total_entrada"] == Decimal("53000.00")
        assert r["peso_total_salida"] == Decimal("48000.00")
        assert r["peso_neto"] == Decimal("5000.00")

    def test_remolque_sumar_al_total(self):
        # PTE=52000+7500=59500, PTS=41500+7500=49000 -> PNT=10500
        r = SVC._calcular(Decimal("52000"), Decimal("7500"), Decimal("41500"), Decimal("7500"))
        assert r["peso_total_entrada"] == Decimal("59500.00")
        assert r["peso_total_salida"] == Decimal("49000.00")
        assert r["peso_neto"] == Decimal("10500.00")

    def test_bruto_y_tara(self):
        r = SVC._calcular(Decimal("50000"), None, Decimal("45000"), None)
        assert r["peso_bruto"] == Decimal("50000.00")
        assert r["peso_tara"] == Decimal("45000.00")

    def test_diferencia_neto_declarado(self):
        # PNT=10500, PND=10000 -> PDF=500, PDV=5%
        r = SVC._calcular(
            Decimal("52000"), Decimal("7500"), Decimal("41500"), Decimal("7500"),
            peso_neto_declarado=Decimal("10000"),
        )
        assert r["peso_neto_declarado"] == Decimal("10000.00")
        assert r["peso_diferencia"] == Decimal("500.00")
        assert r["porcentaje_desviacion"] == Decimal("0.0500")

    def test_redondeo_a_dos_decimales(self):
        r = SVC._calcular(Decimal("1.995"), None, Decimal("1.00"), None)
        assert r["peso_total_entrada"] == Decimal("2.00")


class TestLitros:
    def test_litros_peso_neto_sobre_densidad(self):
        p = type("P", (), {})()  # objeto simple
        p.peso_neto = Decimal("8000.00")
        p.densidad = Decimal("1.6000")
        p.litros = None
        SVC._apply_litros(p, Decimal("1.6000"))
        assert p.litros == Decimal("5000.00")

    def test_sin_neto_no_calcula(self):
        p = type("P", (), {})()
        p.peso_neto = None
        p.densidad = Decimal("1.6")
        p.litros = Decimal("999")
        SVC._apply_litros(p)
        # no debería tocar nada porque no hay neto
        assert p.litros == Decimal("999")

    def test_densidad_cero_no_calcula(self):
        p = type("P", (), {})()
        p.peso_neto = Decimal("8000")
        p.densidad = Decimal("0")
        p.litros = None
        SVC._apply_litros(p, Decimal("0"))
        assert p.litros is None


class TestNormalizarEstado:
    def test_legacy_abierto(self):
        assert normalizar_estado("ABIERTO") == "PENDIENTE"
        assert normalizar_estado("AUTOMÁTICO") == "PENDIENTE"

    def test_legacy_cerrado(self):
        assert normalizar_estado("COMPLETADO") == "CERRADO"
        assert normalizar_estado("Cerrado") == "CERRADO"

    def test_sin_valor(self):
        assert normalizar_estado(None) == "PENDIENTE"

    def test_passthrough(self):
        assert normalizar_estado("ANULADO") == "ANULADO"
        assert normalizar_estado("MODIFICADO") == "MODIFICADO"
