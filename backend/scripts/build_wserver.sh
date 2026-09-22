#!/usr/bin/env bash
# ============================================================
# BALANSOFT-WS - Build del WServer (backend local compilado)
#
# Empaca la API FastAPI (rol local) en un binario único con
# PyInstaller (one-file) llamado "WServer", con los datos
# embebidos (esquemas SQL, migraciones y plantilla .env).
#
# Uso:
#   ./scripts/build_wserver.sh
#
# Salida: backend/dist/WServer/WServer
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== WServer build =="
echo "Backend: $(pwd)"
echo ""

# 1) Asegurar PyInstaller en el entorno
uv run python -c "import PyInstaller" 2>/dev/null || {
  echo "[1] Instalando pyinstaller (dev dep)..."
  uv add --dev pyinstaller
}

echo "[1] PyInstaller: $(uv run python -c 'import PyInstaller; print(PyInstaller.__version__)')"

# 2) Compilar one-file
echo "[2] Compilando WServer..."
rm -rf build dist
uv run pyinstaller WServer.spec --noconfirm --clean

# 3) Verificar
BIN="dist/WServer"
if [[ ! -x "${BIN}" ]]; then
  echo "❌ No se encontró el binario: ${BIN}" >&2
  exit 1
fi
SIZE=$(du -h "${BIN}" | cut -f1)
echo "[3] ✅ Binario generado: ${BIN} (${SIZE})"

echo ""
echo "== Listo =="
echo "  Prueba rápida: ${BIN} --version"
echo "  Arranque (primera instalación):"
echo "    WSERVER_HOME=/tmp/wserver-demo ${BIN}"
echo "  Después verifica: curl http://127.0.0.1:8000/api/v1/health"