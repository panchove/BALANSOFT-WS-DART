#!/usr/bin/env bash
# ============================================================
# BALANSOFT-WS - Instalación del cliente (backend)
#
# Crea .env, prepara la BD, instala el servicio systemd y verifica.
#
# Variables de configuración:
#   INSTALL_PREFIX  Directorio raíz del deploy (default: /opt/balansoft-ws)
#   APP_USER        Usuario del servicio systemd (default: balansoft)
#   SEED            Insertar datos demo (default: false)
#
# Uso:
#   cd /ruta/al/repo/backend
#   ./scripts/install_cliente.sh
#   # o con seed y prefijo personalizado:
#   SEED=true INSTALL_PREFIX=/home/balansoft APP_USER=$(whoami) ./scripts/install_cliente.sh
#
# Requiere permisos sudo para systemd (o ejecutar como root).
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."
SCRIPTS="$(pwd)/scripts"
BACKEND="$(pwd)"

INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/balansoft-ws}"
APP_USER="${APP_USER:-balansoft}"
SEED="${SEED:-false}"
API_PORT="${API_PORT:-8002}"
API_HOST="${API_HOST:-127.0.0.1}"

echo "== BALANSOFT-WS install =="
echo "Backend:    ${BACKEND}"
echo "Prefijo:    ${INSTALL_PREFIX}"
echo "Usuario:    ${APP_USER}"
echo ""

# ---------------------------------------------------------------------------
# 1. Pre-requisitos del sistema
# ---------------------------------------------------------------------------
echo "[1] Pre-requisitos"
command -v python3 >/dev/null 2>&1 || { echo "❌ python3 no encontrado. Instala Python ≥3.12." >&2; exit 1; }
PYVER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
echo "  Python: ${PYVER}"

if ! command -v psql >/dev/null 2>&1; then
  echo "⚠️  psql no encontrado — ensure PostgreSQL client installed."
fi

if [[ "${SEED}" == "true" ]]; then
  command -v openssl >/dev/null 2>&1 || true
fi
echo ""

# ---------------------------------------------------------------------------
# 2. Crear .env si falta
# ---------------------------------------------------------------------------
echo "[2] Configuración (.env)"
if [[ -f .env ]]; then
  echo "  .env ya existe — sin cambios."
else
  cp .env.example .env
  # Generar SECRET_KEY fuerte si no se ha cambiado del valor de desarrollo
  CURRENT_KEY="$(grep -E '^SECRET_KEY=' .env | head -1 | sed 's/^SECRET_KEY=//' | tr -d '"' | tr -d "'")"
  if [[ "${CURRENT_KEY}" == "dev_secret_key_balansoft_ws_2026" ]]; then
    NEW_KEY="$(openssl rand -hex 32)"
    sed -i "s|^SECRET_KEY=.*|SECRET_KEY=${NEW_KEY}|" .env
    echo "  SECRET_KEY generado y guardado en .env"
  fi
  echo "  ⚠️  Revisa .env — especialmente CORS_ORIGINS, LICENSE_PUBLIC_KEY_PATH y DATABASE_URL_SYNC"
fi

# Verificar que SECRET_KEY no sigue débil
FINAL_KEY="$(grep -E '^SECRET_KEY=' .env | head -1 | sed 's/^SECRET_KEY=//' | tr -d '"' | tr -d "'")"
if [[ -z "${FINAL_KEY}" ]] || [[ ${#FINAL_KEY} -lt 32 ]]; then
  echo "  ❌ SECRET_KEY inseguro en .env (≤32 chars o vacío). Aborta."
  exit 1
fi
echo ""

# ---------------------------------------------------------------------------
# 3. Base de datos: instalar esquema + migraciones
# ---------------------------------------------------------------------------
echo "[3] Base de datos"
if ! bash "${SCRIPTS}/setup_db.sh" instalar; then
  echo "❌ Error al instalar esquema."
  exit 1
fi
echo ""
echo "[3.1] Migraciones"
bash "${SCRIPTS}/setup_db.sh" aplicar-migraciones
echo ""

if [[ "${SEED}" == "true" ]]; then
  echo "[3.2] Seed demo"
  bash "${SCRIPTS}/setup_db.sh" seed
  echo ""
fi

# ---------------------------------------------------------------------------
# 4. Servicio systemd
# ---------------------------------------------------------------------------
echo "[4] Servicio systemd"
if ! command -v systemctl >/dev/null 2>&1; then
  echo "  ⚠️  systemctl no disponible — se omite la instalación del servicio."
  echo "  Inicia manualmente: .venv/bin/uvicorn app.main:app --host ${API_HOST} --port ${API_PORT}"
else
  UNIT_DIR="/etc/systemd/system"
  UNIT_FILE="${UNIT_DIR}/balansoft-ws.service"
  TMPFILE="$(mktemp)"

  sed -e "s|/opt/balansoft-ws/backend|${BACKEND}|g" \
      -e "s|User=balansoft|User=${APP_USER}|g" \
      -e "s|Group=balansoft|Group=${APP_USER}|g" \
      -e "s|--port 8000|--port ${API_PORT}|g" \
      deploy/balansoft-ws.service > "${TMPFILE}"

  if sudo install -m 0644 "${TMPFILE}" "${UNIT_FILE}" 2>/dev/null; then
    sudo systemctl daemon-reload
    sudo systemctl enable balansoft-ws
    echo "  Servicio instalado y habilitado. Para arrancarlo:"
    echo "    sudo systemctl start balansoft-ws"
    echo "  Logs:"
    echo "    journalctl -u balansoft-ws -f"
  else
    echo "  ⚠️  Sin permisos sudo — mostrando pasos manuales:"
    echo "    sudo cp deploy/balansoft-ws.service ${UNIT_FILE}"
    echo "    # Ajusta WorkingDirectory a: ${BACKEND}"
    echo "    sudo systemctl daemon-reload && sudo systemctl enable balansoft-ws"
    echo "    sudo systemctl start balansoft-ws"
  fi
  rm -f "${TMPFILE}"
fi
echo ""

# ---------------------------------------------------------------------------
# 5. Verificación
# ---------------------------------------------------------------------------
echo "[5] Verificación"
bash "${SCRIPTS}/verify.sh"
echo ""

echo "== Instalación completada =="
echo "Siguientes pasos:"
echo "  1. Revisa .env (CORS_ORIGINS restringido para producción, LICENSE_PUBLIC_KEY_PATH)."
echo "  2. sudo systemctl start balansoft-ws"
echo "  3. http://${API_HOST}:${API_PORT}/docs"
echo "  4. Genera backups periódicos: ${SCRIPTS}/backup.sh (o cron)"