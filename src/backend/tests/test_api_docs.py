"""Exposición de la documentación de API (H14).

Contexto: hasta la v2.4 la plantilla de WServer traía ``API_DOCS_ENABLED=false``
con intención de no exponer la superficie de la API. Pero esa configuración no
protegía nada: ``openapi_url`` es **independiente** de la bandera, así que
``/openapi.json`` seguía publicando el esquema completo de las 82 rutas. El
resultado era que toda estación instalada servía 404 en ``/docs`` y ``/redoc``
mientras el esquema completo estaba disponible: se pagaba la ausencia de
documentación sin obtener seguridad.

Estos tests fijan la decisión tomada (documentación activa en estaciones) y, sobre
todo, documentan el mecanismo para que nadie intente "arreglar" la seguridad
volviendo a la bandera.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

BACKEND = Path(__file__).resolve().parents[1]
RAIZ = BACKEND.parent


def _flag_de_env(ruta: Path) -> str | None:
    """Valor crudo de ``API_DOCS_ENABLED`` en un archivo ``.env*``."""
    if not ruta.exists():
        return None
    patron = re.compile(r"^\s*API_DOCS_ENABLED\s*=\s*(\S+)\s*$", re.MULTILINE)
    encontrado = patron.search(ruta.read_text(encoding="utf-8"))
    return encontrado.group(1) if encontrado else None


class TestDocumentacionDeAPI:
    """H14: la documentación debe llegar a las instalaciones."""

    def test_plantilla_wserver_habilita_documentacion(self) -> None:
        """Las estaciones nuevas deben exponer /docs, /redoc y /openapi.json."""
        assert _flag_de_env(BACKEND / ".env.plantilla") == "true", (
            ".env.plantilla debe traer API_DOCS_ENABLED=true: con false, toda "
            "estación instalada responde 404 en /docs y /redoc y H14 queda sin "
            "cumplir (objetivo: documentación para integradores)."
        )

    def test_env_example_central_sigue_deshabilitado(self) -> None:
        """El servidor central es internet-facing: su decisión es aparte.

        Que siga en ``false`` es deliberado (perfil de riesgo distinto al de una
        estación en LAN), pero debe seguir siendo una decisión explícita y no un
        descuido: por eso se fija aquí.
        """
        assert _flag_de_env(BACKEND / ".env.example") == "false", (
            ".env.example documenta el servidor central (expuesto a internet). "
            "Si se cambia, que sea una decisión consciente: requiere revisar "
            "MANEJO_DB.md §11.4, que hoy afirma que queda en false."
        )

    def test_openapi_json_no_depende_de_la_bandera(self) -> None:
        """``openapi_url`` NO está condicionado por ``api_docs_enabled``.

        Este es el mecanismo que hizo fracasar el diseño original. Si alguien
        añade ``if settings.api_docs_enabled`` a ``openapi_url`` thinking que
        así se oculta la superficie, este test falla.
        """
        fuente = (BACKEND / "app" / "main.py").read_text(encoding="utf-8")
        bloque = fuente[fuente.index("FastAPI(") : fuente.index("lifespan=lifespan")]

        # /docs y /redoc sí están condicionados por la bandera...
        assert "docs_url" in bloque and "settings.api_docs_enabled" in bloque
        # ...pero openapi_url no aparece en absoluto en ese bloque: es
        # independiente de la bandera y sigue sirviéndose con ella en false.
        assert "openapi_url" not in bloque, (
            "openapi_url no debe condicionarse a la bandera: es independiente "
            "por diseño. Ocultarlo rompería a los integradores que consumen el "
            "esquema, y no protege las rutas (siguen exigiendo JWT). Si se "
            "quiere restringir, el camino es autenticar /docs, /redoc y "
            "/openapi.json — no deshabilitarlos (ver MANEJO_DB.md §11.4)."
        )

    @pytest.mark.parametrize("ruta", ["/docs", "/redoc", "/openapi.json"])
    def test_app_monta_las_tres_rutas(self, ruta: str) -> None:
        """Con la documentación habilitada, las tres rutas existen."""
        from app.main import app

        if not app.docs_url and ruta != "/openapi.json":
            pytest.skip("API_DOCS_ENABLED=false en este entorno")

        rutas = {getattr(r, "path", "") for r in app.routes}
        assert ruta in rutas, f"{ruta} no está montada en la aplicación"


class TestDocumentacionDeColumnasReservadas:
    """B-doc: `multi_despacho_recepcion` es una columna inerte documentada."""

    def test_columna_existe_en_el_esquema(self) -> None:
        """Se documenta como reservada, pero el DDL debe seguir intacto.

        La decisión fue "documentar sí, borrar no": eliminarla rompería clientes
        y el round-trip de sincronización.
        """
        ddl = (BACKEND / "balansoft-ws-local.sql").read_text(encoding="utf-8")
        assert re.search(
            r"multi_despacho_recepcion\s+BOOLEAN\s+NOT\s+NULL\s+DEFAULT\s+FALSE", ddl
        ), "el DDL canónico debe conservar la columna reservada"

    def test_manejodb_la_documenta_como_reservada(self) -> None:
        """La documentación de la columna reservada debe existir y ser explícita."""
        doc = (RAIZ / "docs" / "MANEJO_DB.md").read_text(encoding="utf-8")
        assert "Columnas reservadas" in doc, (
            "MANEJO_DB.md debe tener la sección de columnas reservadas (§6.3)"
        )
        for regla in ("No usarla", "No borrarla", "No quitarla del round-trip"):
            assert regla in doc, f"falta la regla «{regla}» en §6.3"
