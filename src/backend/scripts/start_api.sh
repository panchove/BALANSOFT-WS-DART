#!/usr/bin/env bash
# Inicia la API de Balansoft-WS (FastAPI) en el puerto 8000.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d .venv ]; then
  echo "🔧 Creando entorno virtual con uv..."
  uv sync
fi

HOST="${API_HOST:-0.0.0.0}"
PORT="${API_PORT:-8000}"
RELOAD="${API_RELOAD:-true}"

echo "🚀 Iniciando Balansoft-WS API en http://localhost:${PORT}"
if [ "$RELOAD" = "true" ]; then
  exec uv run uvicorn app.main:app --reload --host "$HOST" --port "$PORT"
else
  exec uv run uvicorn app.main:app --host "$HOST" --port "$PORT"
fi
