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
  echo "[1] Instalando pyinstaller y pillow (dev dep)..."
  uv add --dev pyinstaller pillow
}

echo "[1] PyInstaller: $(uv run python -c 'import PyInstaller; print(PyInstaller.__version__)')"

# 1.5) Preparar icono
if [[ -f "../wserver_icon.jpeg" ]]; then
    echo "[1.5] Generando icono wserver_icon.ico desde JPEG..."
    uv run python -c "
from PIL import Image
try:
    img = Image.open('../wserver_icon.jpeg')
    img.save('wserver_icon.ico', format='ICO', sizes=[(256, 256)])
except Exception as e:
    print('Error generando icono:', e)
"
fi

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

# 4) Integrar al bundle de Flutter (si existe)
BUNDLE_DIR="../frontend/build/linux/x64/release/bundle"
if [[ -d "${BUNDLE_DIR}" ]]; then
  echo "[4] Integrando WServer en el bundle de Flutter Desktop..."
  # Binario junto al ejecutable de la app (lo busca WServerManager) + icono
  # para el .desktop de autostart.
  cp "${BIN}" "${BUNDLE_DIR}/WServer"
  chmod +x "${BUNDLE_DIR}/WServer"
  if [[ -f "../wserver_icon.jpeg" ]]; then
    cp "../wserver_icon.jpeg" "${BUNDLE_DIR}/wserver_icon.jpeg"
  fi
  echo "    ✅ WServer + wserver_icon.jpeg copiados a la raíz del bundle."
fi

# 4.5) Bundle de debug (dev): mismo binario donde lo usa WServerManager en tests locales
for DEBUG_DIR in \
  ../frontend/build/linux/x64/debug/outputs/BALANSOFT-WS-CLIENT_SERVER \
  ../frontend/build/linux/x64/debug/bundle; do
  if [[ -d "${DEBUG_DIR}" ]]; then
    echo "[4.5] Actualizando WServer en el bundle de debug (${DEBUG_DIR})..."
    cp "${BIN}" "${DEBUG_DIR}/WServer"
    chmod +x "${DEBUG_DIR}/WServer"
    echo "    ✅ WServer actualizado."
  fi
done

echo ""
echo "== Listo =="
echo "  Prueba rápida: ${BIN} --version"
echo "  Arranque (primera instalación):"
echo "    WSERVER_HOME=/tmp/wserver-demo ${BIN}"
echo "  Después verifica: curl http://127.0.0.1:8000/api/v1/health"