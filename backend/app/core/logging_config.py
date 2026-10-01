"""Logging estructurado con rotación (H5/H7 de ACTUAR.md).

Sustituye el ``logging.basicConfig`` de :mod:`app.main` para permitir:

* formato **JSON** (una línea por evento) para ingestión en agregadores de
  logs, o formato texto legible en desarrollo;
* escritura simultánea en consola (stdout, systemd/journal) y en un archivo
  rotado por tamaño (``RotatingFileHandler``), de modo que el disco no crezca
  indefinidamente en la estación.

Configuración por variables de entorno (ver ``Settings`` en
:mod:`app.core.config`):

``LOG_LEVEL``, ``LOG_FORMAT`` (``text``|``json``), ``LOG_DIR``,
``LOG_MAX_BYTES``, ``LOG_BACKUP_COUNT``.
"""

from __future__ import annotations

import json
import logging
import logging.handlers
import sys
from pathlib import Path


class JsonFormatter(logging.Formatter):
    """Convierte cada registro en una línea JSON (una por evento)."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False, default=str)


def _formatear(formato: str) -> logging.Formatter:
    if formato.lower() == "json":
        return JsonFormatter()
    return logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s")


def configurar_logging(
    *,
    nivel: str = "INFO",
    formato: str = "text",
    directorio: str | None = None,
    max_bytes: int = 5_000_000,
    backup_count: int = 5,
) -> logging.Logger:
    """Configura el logging raíz y devuelve el logger de la aplicación.

    Idempotente: si el logging ya fue configurado, reemplaza los handlers
    previos del logger raíz en vez de duplicarlos (evita líneas repetidas
    bajo ``uvicorn --reload``).
    """
    nivel_real = getattr(logging, nivel.upper(), logging.INFO)
    formateador = _formatear(formato)

    root = logging.getLogger()
    for handler in list(root.handlers):
        root.removeHandler(handler)
    root.setLevel(nivel_real)

    consola = logging.StreamHandler(sys.stdout)
    consola.setLevel(nivel_real)
    consola.setFormatter(formateador)
    root.addHandler(consola)

    if directorio:
        ruta_dir = Path(directorio).expanduser()
        try:
            ruta_dir.mkdir(parents=True, exist_ok=True)
            archivo = logging.handlers.RotatingFileHandler(
                ruta_dir / "balansoft-ws.log",
                maxBytes=max(1, int(max_bytes)),
                backupCount=max(1, int(backup_count)),
                encoding="utf-8",
            )
            archivo.setLevel(nivel_real)
            archivo.setFormatter(formateador)
            root.addHandler(archivo)
        except OSError as exc:  # disco lleno/permisos: no abortar el arranque
            root.warning("No se pudo abrir el log en archivo (%s): %s", directorio, exc)

    # uvicorn.access duplica cada petición con su propia configuración.
    logging.getLogger("uvicorn.access").handlers.clear()
    logging.getLogger("uvicorn.access").propagate = True
    return logging.getLogger("balansoft_ws")