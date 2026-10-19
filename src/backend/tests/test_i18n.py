"""Pruebas de la capa de internacionalización (es/en/pt).

No requieren base de datos: cubren el diccionario, la precedencia de idioma
(``?idioma=`` > ``Accept-Language`` > empresa > servidor) y el formateo de
números/fechas por idioma.

Referencia: docs/I18N_Y_ONBOARDING.md (REQ-NF-I18N-003, REQ-NF-I18N-004).
"""

from __future__ import annotations

from decimal import Decimal
from typing import cast

from fastapi import Request

from app.core.formato import formatear_fecha, formatear_numero
from app.core.i18n import (
    IDIOMA_DEFAULT,
    IDIOMAS,
    TRANSLATIONS,
    idioma_de_accept_language,
    normalizar_idioma,
    resolve_lang,
    t,
    traducir_estado_boleto,
)


class _FakeRequest:
    """Request mínimo para probar ``resolve_lang`` sin levantar FastAPI."""

    def __init__(self, headers: dict[str, str] | None = None, query: dict | None = None):
        self.headers = {k.lower(): v for k, v in (headers or {}).items()}
        self.query_params = query or {}


def _req(headers: dict[str, str] | None = None, query: dict | None = None) -> Request:
    return cast(Request, _FakeRequest(headers, query))


class TestDiccionario:
    def test_tres_idiomas_soportados(self):
        assert IDIOMAS == ("es", "en", "pt")
        assert IDIOMA_DEFAULT == "es"

    def test_paridad_de_claves_entre_idiomas(self):
        es = set(TRANSLATIONS["es"])
        assert es == set(TRANSLATIONS["en"]), "faltan claves en inglés"
        assert es == set(TRANSLATIONS["pt"]), "faltan claves en portugués"

    def test_traduce_rotulos_institucionales(self):
        assert t("etiqueta_rif", "es") == "RIF"
        assert t("etiqueta_rif", "en") == "Tax ID"
        assert t("etiqueta_direccion", "en") == "Address"
        assert t("etiqueta_direccion", "pt") == "Endereço"
        assert t("pagina", "en") == "Page"

    def test_valores_por_defecto_del_boleto_traducidos(self):
        assert t("sin_placa", "en") == "No Plate"
        assert t("si", "pt") == "Sim"
        assert t("no", "pt") == "Não"
        assert t("boleto_sin_numero", "en") == "Ticket n/a"

    def test_fallback_a_es_y_a_la_clave(self):
        assert t("titulo_boleto", "fr") == TRANSLATIONS["es"]["titulo_boleto"]
        assert t("clave_inexistente", "en") == "clave_inexistente"

    def test_traduce_estado_de_boleto(self):
        assert traducir_estado_boleto("CERRADO", "es") == "CERRADO"
        assert traducir_estado_boleto("CERRADO", "en") == "CLOSED"
        assert traducir_estado_boleto("anulado", "pt") == "ANULADO"
        assert traducir_estado_boleto(None, "en") == ""
        assert traducir_estado_boleto("ESTADO_RARO", "en") == "ESTADO_RARO"


class TestNormalizacion:
    def test_tags_regionales(self):
        assert normalizar_idioma("pt-BR") == "pt"
        assert normalizar_idioma("en_US") == "en"
        assert normalizar_idioma("ES-419") == "es"
        assert normalizar_idioma("ES") == "es"

    def test_idiomas_no_soportados_o_vacios(self):
        assert normalizar_idioma("fr") is None
        assert normalizar_idioma("") is None
        assert normalizar_idioma(None) is None


class TestAcceptLanguage:
    def test_portugues_no_cae_en_ingles(self):
        cabecera = "pt-BR,pt;q=0.9,en;q=0.8"
        assert idioma_de_accept_language(cabecera) == "pt"

    def test_espanol_no_cae_en_ingles(self):
        assert idioma_de_accept_language("es-ES,es;q=0.9,en;q=0.8") == "es"

    def test_respeta_el_orden_por_calidad(self):
        assert idioma_de_accept_language("pt;q=0.5,en;q=0.9") == "en"

    def test_ignora_calidad_cero_y_desconocidos(self):
        assert idioma_de_accept_language("fr;q=1.0,pt;q=0") is None
        assert idioma_de_accept_language("en-US,en;q=0.9") == "en"
        assert idioma_de_accept_language("") is None
        assert idioma_de_accept_language(None) is None

    def test_sin_acentos_usa_el_idioma_del_sistema(self):
        assert idioma_de_accept_language("*") is None


class TestResolveLang:
    def test_query_tiene_prioridad_sobre_header(self):
        req = _req({"Accept-Language": "en"}, {"idioma": "pt"})
        assert resolve_lang(req) == "pt"

    def test_parametro_explicito_tiene_prioridad(self):
        req = _req({"Accept-Language": "en"}, {"idioma": "pt"})
        assert resolve_lang(req, "es") == "es"

    def test_header_si_no_hay_parametro(self):
        req = _req({"Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8"})
        assert resolve_lang(req) == "pt"

    def test_usa_el_idioma_de_la_empresa_como_defecto(self):
        req = _req()
        assert resolve_lang(req, None, "en") == "en"
        assert resolve_lang(req, None, "idioma-inexistente") == IDIOMA_DEFAULT
        assert resolve_lang(None, None, "pt") == "pt"

    def test_sin_request_devuelve_el_defecto(self):
        assert resolve_lang(None) == IDIOMA_DEFAULT

    def test_acepta_alias_lang_en_query(self):
        assert resolve_lang(_req(query={"lang": "en"})) == "en"


class TestFormato:
    def test_numeros_segun_idioma(self):
        assert formatear_numero(Decimal("12345.67"), 2, "es") == "12.345,67"
        assert formatear_numero(Decimal("12345.67"), 2, "pt") == "12.345,67"
        assert formatear_numero(Decimal("12345.67"), 2, "en") == "12,345.67"

    def test_numeros_vacios_y_texto(self):
        assert formatear_numero(None, 2, "es") == "0,00"
        assert formatear_numero(None, 2, "en") == "0.00"
        assert formatear_numero("abc", 2, "es") == "abc"

    def test_fechas_en_formato_regional(self):
        from datetime import datetime

        fecha = datetime(2026, 9, 25, 14, 30)
        assert formatear_fecha(fecha, "es") == "25/09/2026"
        assert formatear_fecha(fecha, "en", con_hora=True) == "25/09/2026 14:30"
        assert formatear_fecha(None, "es") == "—"
        assert formatear_fecha("2026-09-25T14:30:00", "pt", con_hora=True) == "25/09/2026 14:30"
