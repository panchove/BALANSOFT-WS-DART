#!/usr/bin/env bash
# ============================================================
# BALANSOFT-WS - Verificación de la estación (chequeos de producción)
#
# Uso:
#   ./scripts/verify.sh
#
# Salida: 0 si todo correcto, 1 si hay fallos críticos.
# Variables opcionales: API_HOST, API_PORT (para el health check).
# ============================================================
set -uo pipefail

cd "$(dirname "$0")/.."

PASS=0
WARN=0
FAIL=0

API_HOST="${API_HOST:-127.0.0.1}"
API_PORT="${API_PORT:-8002}"

ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
warn() { WARN=$((WARN+1)); echo "  ⚠️  $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }

echo "== BALANSOFT-WS verify =="

# ---------------------------------------------------------------------------
# 1. Python 3.12+
# ---------------------------------------------------------------------------
echo "[1] Python"
if command -v python3 >/dev/null 2>&1; then
  PYVER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  MAJOR="${PYVER%%.*}"; MINOR="${PYVER#*.}"
  if [[ "${MAJOR}" -ge 3 ]] && [[ "${MINOR}" -ge 12 ]]; then
    ok "Python ${PYVER} (≥3.12)"
  else
    fail "Python ${PYVER} < 3.12"
  fi
else
  fail "python3 no encontrado"
fi

# ---------------------------------------------------------------------------
# 2. Cliente PostgreSQL (psql + pg_dump)
# ---------------------------------------------------------------------------
echo "[2] PostgreSQL"
if command -v psql >/dev/null 2>&1; then ok "psql presente"; else fail "psql no encontrado"; fi
if command -v pg_dump >/dev/null 2>&1; then ok "pg_dump presente"; else warn "pg_dump no encontrado (backups no disponibles)"; fi

# ---------------------------------------------------------------------------
# 3. Resolver URI y comprobar conexión/estructura
# ---------------------------------------------------------------------------
echo "[3] Base de datos"
if [[ -z "${DATABASE_URL_SYNC:-}" ]]; then
  if [[ -f .env ]]; then
    DATABASE_URL_SYNC="$(grep -E '^DATABASE_URL_SYNC=' .env | head -1 | sed 's/^DATABASE_URL_SYNC=//' | tr -d '"' | tr -d "'")"
  fi
fi
if [[ -z "${DATABASE_URL_SYNC:-}" ]]; then
  fail "DATABASE_URL_SYNC no definido (ni env ni .env)"
else
  URI="${DATABASE_URL_SYNC/postgresql+psycopg2:/postgresql:}"
  URI="${URI/postgresql+asyncpg:/postgresql:}"
  if psql "${URI}" -tAc "SELECT 1" >/dev/null 2>&1; then
    ok "Conexión a BD OK"
  else
    fail "No se pudo conectar a la BD"
  fi

  TABLES="$(psql "${URI}" -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null || echo 0)"
  if [[ "${TABLES}" -gt 5 ]]; then
    ok "Esquema presente (${TABLES} tablas)"
  else
    fail "Pocas tablas (${TABLES}) — ¿se instaló el esquema?"
  fi
fi

# ---------------------------------------------------------------------------
# 4. .env y SECRET_KEY
# ---------------------------------------------------------------------------
echo "[4] Seguridad"
if [[ -f .env ]]; then
  ok ".env presente"
  SECRET="$(grep -E '^SECRET_KEY=' .env | head -1 | sed 's/^SECRET_KEY=//' | tr -d '"' | tr -d "'")"
  WEAK_VALUES=("" "changeme" "secret" "test" "dev" "secret_key" "change-me")
  WEAK=""
  if [[ -z "${SECRET}" ]]; then
    WEAK="vacío"
  elif [[ ${#SECRET} -lt 32 ]]; then
    WEAK="menos de 32 caracteres (${#SECRET})"
  elif [[ " ${WEAK_VALUES[*]} " == *" ${SECRET,,} "* ]]; then
    WEAK="valor débil conocido"
  elif [[ "${SECRET}" == "dev_secret_key_balansoft_ws_2026" ]]; then
    WEAK="valor por defecto de desarrollo"
  fi
  if [[ -n "${WEAK}" ]]; then
    fail "SECRET_KEY inseguro (${WEAK}) — genera uno con: openssl rand -hex 32"
  else
    ok "SECRET_KEY con entropía suficiente"
  fi
else
  warn ".env no encontrado (el API arrancará con defaults de desarrollo)"
fi

# ---------------------------------------------------------------------------
# 5. Health del API
# ---------------------------------------------------------------------------
echo "[5] API"
if command -v curl >/dev/null 2>&1; then
  STATUS="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://${API_HOST}:${API_PORT}/api/v1/health" 2>/dev/null || echo 000)"
  case "${STATUS}" in
    200) ok "API /api/v1/health → 200" ;;
    000) warn "API no responde en ${API_HOST}:${API_PORT} (¿está corriendo?)" ;;
    *)   warn "API respondió ${STATUS}" ;;
  esac
else
  warn "curl no instalado, no se pudo verificar el health"
fi

# ---------------------------------------------------------------------------
# 6. systemd
# ---------------------------------------------------------------------------
echo "[6] systemd"
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files 2>/dev/null | grep -q "balansoft-ws"; then
    STATE="$(systemctl is-active balansoft-ws 2>/dev/null || echo inactive)"
    if [[ "${STATE}" == "active" ]]; then
      ok "Servicio balansoft-ws activo"
    else
      fail "Servicio balansoft-ws presente pero ${STATE}"
    fi
    if systemctl is-enabled balansoft-ws >/dev/null 2>&1; then
      ok "Servicio habilitado al arranque"
    else
      warn "Servicio no habilitado al arranque (systemctl enable)"
    fi
  else
    warn "Unidad balansoft-ws no registrada (deploy/balansoft-ws.service)"
  fi
else
  warn "systemctl no disponible (no systemd?)"
fi

# ---------------------------------------------------------------------------
# 7. Licencias (LM) — best-effort
# ---------------------------------------------------------------------------
echo "[7] License Manager"
if command -v curl >/dev/null 2>&1 && [[ -f .env ]]; then
  LM_URL="$(grep -E '^LICENSE_API_URL=' .env | head -1 | sed 's/^LICENSE_API_URL=//')"
  if [[ -n "${LM_URL}" ]]; then
    LM_STATUS="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${LM_URL%/}/health" 2>/dev/null || echo 000)"
    if [[ "${LM_STATUS}" == "200" ]] || [[ "${LM_STATUS}" == "404" ]]; then
      ok "LM accesible (${LM_STATUS})"
    else
      warn "LM ${LM_URL} no accesible (${LM_STATUS})"
    fi
  fi
else
  warn "No se pudo verificar el LM (sin .env o curl)"
fi

# ---------------------------------------------------------------------------
# Resumen
# ---------------------------------------------------------------------------
echo ""
echo "== Resumen: ${PASS} OK, ${WARN} avisos, ${FAIL} fallos =="
if [[ "${FAIL}" -gt 0 ]]; then
  echo "❌ Hay fallos críticos que corregir."
  exit 1
fi
echo "✅ Verificación completada."
exit 0