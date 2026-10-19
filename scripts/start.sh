#!/usr/bin/env bash
# Sirve el panel administrativo de forma estática.
# Uso:  ./start.sh [puerto]   (por defecto 3000)
set -euo pipefail
PUERTO="${1:-3000}"
cd "$(dirname "$0")/panel"
echo "Panel administrativo: http://localhost:${PUERTO}/index.html"
exec python3 -m http.server "${PUERTO}" --bind 127.0.0.1