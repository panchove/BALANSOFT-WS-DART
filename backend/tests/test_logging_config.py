"""Pruebas del logging estructurado y rotado (H5/H7 de ACTUAR.md)."""

from __future__ import annotations

import json
import logging
from pathlib import Path

from app.core.logging_config import JsonFormatter, configurar_logging


class TestJsonFormatter:
    def test_linea_json_con_campos_esperados(self):
        formateador = JsonFormatter()
        registro = logging.LogRecord(
            name="balansoft_ws",
            level=logging.WARNING,
            pathname=__file__,
            lineno=1,
            msg="pesaje cerrado %s",
            args=("TA-1",),
            exc_info=None,
        )
        datos = json.loads(formateador.format(registro))
        assert datos["level"] == "WARNING"
        assert datos["logger"] == "balansoft_ws"
        assert datos["msg"] == "pesaje cerrado TA-1"
        assert datos["ts"]

    def test_incluye_traceback(self):
        formateador = JsonFormatter()
        try:
            raise ValueError("boom")
        except ValueError:
            import sys  # noqa: PLC0415

            registro = logging.LogRecord(
                name="balansoft_ws",
                level=logging.ERROR,
                pathname=__file__,
                lineno=1,
                msg="fallo",
                args=(),
                exc_info=sys.exc_info(),
            )
        datos = json.loads(formateador.format(registro))
        assert "ValueError: boom" in datos["exc"]


class TestConfigurarLogging:
    def test_escribe_archivo_rotado_y_no_duplica_handlers(self, tmp_path: Path):
        log = configurar_logging(nivel="DEBUG", formato="json", directorio=str(tmp_path))
        try:
            total_primera = len(logging.getLogger().handlers)
            log.info("evento uno")
            archivo = tmp_path / "balansoft-ws.log"
            assert archivo.exists()
            lineas = archivo.read_text(encoding="utf-8").strip().splitlines()
            assert len(lineas) == 1
            assert json.loads(lineas[0])["msg"] == "evento uno"

            configurar_logging(
                nivel="DEBUG", formato="json", directorio=str(tmp_path)
            )
            assert len(logging.getLogger().handlers) == total_primera
        finally:
            configurar_logging(nivel="WARNING", formato="text", directorio=None)

    def test_sin_directorio_no_escribe_archivo(self, tmp_path: Path):
        log = configurar_logging(
            nivel="INFO", formato="text", directorio=None
        )
        try:
            assert not list(tmp_path.iterdir())
            assert log.name == "balansoft_ws"
        finally:
            configurar_logging(nivel="WARNING", formato="text", directorio=None)