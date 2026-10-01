#!/usr/bin/env bash
# ============================================================
# BALANSOFT-WS - Entorno para el E2E de Flutter (H2b)
#
# Levanta en una base de datos AISLADA lo que la app necesita para correr
# `frontend/integration_test/pesaje_flow_test.dart` contra la API real:
#
#   1. Crea la BD  (E2E_DB, por defecto balansoft_ws_e2e_flutter)
#   2. Aplica el esquema canónico del rol local (balansoft-ws-local.sql)
#   3. Siembra empresa + admin + catálogos SIN báscula  (scripts/seed_e2e_flutter.py)
#      (sin báscula el formulario habilita el peso manual: ver el seed)
#   4. Levanta el stub firmante del LM  (scripts/lm_stub.py)
#   5. Levanta la API en 127.0.0.1:8000 apuntando a esa BD y al stub
#
# Uso:
#   ./scripts/e2e_flutter.sh up      # prepara y levanta (idempotente)
#   ./scripts/e2e_flutter.sh down    # para stub + API
#   ./scripts/e2e_flutter.sh status  # ¿responden?
#
# Variables opcionales:
#   E2E_DB, E2E_API_PORT (8000), E2E_LM_PORT (9100), E2E_EMAIL, E2E_PASSWORD
#
# La API y el stub quedan como procesos independientes (setsid), así que
# sobreviven a que termine este script; `down` los detiene por PID en /tmp.
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."
RAIZ="$(pwd)"

E2E_DB="${E2E_DB:-balansoft_ws_e2e_flutter}"
E2E_API_PORT="${E2E_API_PORT:-8000}"
E2E_LM_PORT="${E2E_LM_PORT:-9100}"
E2E_EMAIL="${E2E_EMAIL:-admin@balansoft.demo}"
E2E_PASSWORD="${E2E_PASSWORD:-demo1234}"
DIR_RUN="/tmp/balansoft-e2e-flutter"
PID_API="${DIR_RUN}/api.pid"
PID_LM="${DIR_RUN}/lm.pid"
LOG_API="${DIR_RUN}/api.log"
LOG_LM="${DIR_RUN}/lm.log"

# ── Utilidades ────────────────────────────────────────────────────────────
log()  { printf '\033[0;36m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[0;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Py del venv del backend (el repo no asume uv en PATH).
if [[ -x "${RAIZ}/.venv/bin/python" ]]; then
  PY="${RAIZ}/.venv/bin/python"
elif command -v uv >/dev/null 2>&1; then
  PY="uv run python"
else
  fail "No hay .venv ni uv en el backend."
fi

# ── Credenciales de PostgreSQL: .env del repo (o entorno) ─────────────────
if [[ -z "${DATABASE_URL_SYNC:-}" && -f .env ]]; then
  DATABASE_URL_SYNC="$(grep -E '^DATABASE_URL_SYNC=' .env | head -1 | sed 's/^DATABASE_URL_SYNC=//' | tr -d '"'"'" | tr -d "'")"
fi
[[ -n "${DATABASE_URL_SYNC:-}" ]] || fail "Define DATABASE_URL_SYNC (o backend/.env)."

# Reescribe el nombre de la BD para obtener la URL del entorno E2E.
# Formato: esquema://usuario:clave@host:puerto/basededatos
URI_SYNC="${DATABASE_URL_SYNC/postgresql+psycopg2:/postgresql:}"
URI_SYNC="${URI_SYNC/postgresql+asyncpg:/postgresql:}"
URI_SYNC="${URI_SYNC%%\?*}"
SIN_ESQUEMA="${URI_SYNC#*://}"
DB_NOMBRE="${SIN_ESQUEMA##*/}"
SIN_BD="${SIN_ESQUEMA%/*}"
HOSTPORT="${SIN_BD##*@}"          # host:puerto
CREDS="${SIN_BD%@*}"              # usuario:clave
export PGPASSWORD="${CREDS#*:}"
SERVER_URI="postgresql://${CREDS}@${HOSTPORT}/postgres"

DSN_ASYNC="postgresql+asyncpg://${CREDS}@${HOSTPORT}/${E2E_DB}"
DSN_SYNC="postgresql+psycopg2://${CREDS}@${HOSTPORT}/${E2E_DB}"
DSN_SERVER_ASYNC="postgresql+asyncpg://${CREDS}@${HOSTPORT}/balansoft_ws_server_test"
DSN_SERVER_SYNC="postgresql+psycopg2://${CREDS}@${HOSTPORT}/balansoft_ws_server_test"

esperar_salud() {
  local url="$1" nombre="$2" intentos="${3:-60}"
  for _ in $(seq 1 "$intentos"); do
    if curl -sf --max-time 2 "$url" >/dev/null 2>&1; then
      log "$nombre responde en $url"
      return 0
    fi
    sleep 0.5
  done
  return 1
}

parar_pid() {
  local archivo="$1"
  [[ -f "$archivo" ]] || return 0
  local pid; pid="$(cat "$archivo")"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 0.5
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$archivo"
}

modo="${1:-up}"
case "$modo" in
  up)
    mkdir -p "$DIR_RUN"

    log "1/5 BD ${E2E_DB}"
    if ! psql "$SERVER_URI" -tAc "SELECT 1 FROM pg_database WHERE datname='${E2E_DB}'" | grep -q 1; then
      psql -w "$SERVER_URI" -c "CREATE DATABASE \"${E2E_DB}\"" >/dev/null
    fi

    log "2/5 esquema canónico + migraciones (balansoft-ws-local.sql, 001-020)"
    # Orden de instalación real (ver wserver.py:asegurar_db): primero el esquema
    # base y después TODAS las migraciones; son idempotentes y `id_serie`
    # (series de numeración) solo existe a partir de la migración 015.
    DATABASE_URL_SYNC="${DSN_SYNC}" ./scripts/setup_db.sh instalar >/dev/null
    DATABASE_URL_SYNC="${DSN_SYNC}" ./scripts/setup_db.sh aplicar-migraciones >/dev/null

    log "3/5 seed determinista (admin + catálogos, sin báscula)"
    PYTHONPATH="${RAIZ}" DATABASE_URL="${DSN_ASYNC}" DATABASE_URL_SYNC="${DSN_SYNC}" \
      APP_ROLE=local EMAIL_E2E="$E2E_EMAIL" PASSWORD_E2E="$E2E_PASSWORD" \
      ${PY} scripts/seed_e2e_flutter.py | sed 's/^/   /'

    log "4/5 stub del LM en 127.0.0.1:${E2E_LM_PORT}"
    parar_pid "$PID_LM"
    if [[ ! -f "${DIR_RUN}/key_privada.pem" ]]; then
      ${PY} scripts/generate_signing_keys.py "$DIR_RUN" >/dev/null
    fi
    setsid env LICENSE_PRIVATE_KEY_PATH="${DIR_RUN}/key_privada.pem" \
      LM_STUB_PORT="$E2E_LM_PORT" \
      ${PY} -m uvicorn scripts.lm_stub:app --host 127.0.0.1 --port "$E2E_LM_PORT" \
      --log-level warning >"$LOG_LM" 2>&1 </dev/null &
    echo $! > "$PID_LM"
    esperar_salud "http://127.0.0.1:${E2E_LM_PORT}/health" "stub del LM" \
      || { tail -20 "$LOG_LM"; fail "el stub del LM no arrancó (ver $LOG_LM)"; }

    log "5/5 API en 127.0.0.1:${E2E_API_PORT}"
    parar_pid "$PID_API"
    setsid env \
      APP_ENV=development APP_ROLE=local DEBUG_MODE=false \
      SECRET_KEY="e2e-flutter-secret-key-000000000000000000000" \
      DATABASE_URL="${DSN_ASYNC}" DATABASE_URL_SYNC="${DSN_SYNC}" \
      SERVER_DATABASE_URL="${DSN_SERVER_ASYNC}" \
      SERVER_DATABASE_URL_SYNC="${DSN_SERVER_SYNC}" \
      LICENSE_API_URL="http://127.0.0.1:${E2E_LM_PORT}" \
      LICENSE_PUBLIC_KEY_PATH="${DIR_RUN}/key_publica.pem" \
      ${PY} -m uvicorn app.main:app --host 127.0.0.1 --port "$E2E_API_PORT" \
      --log-level warning >"$LOG_API" 2>&1 </dev/null &
    echo $! > "$PID_API"
    esperar_salud "http://127.0.0.1:${E2E_API_PORT}/api/v1/health" "API" \
      || { tail -20 "$LOG_API"; fail "la API no arrancó (ver $LOG_API)"; }

    log "Listo. Login E2E: ${E2E_EMAIL} / ${E2E_PASSWORD}"
    log "  API  : http://127.0.0.1:${E2E_API_PORT}  (BD ${DB_NOMBRE} → ${E2E_DB})"
    log "  Stub : http://127.0.0.1:${E2E_LM_PORT}"
    log "  Logs : ${LOG_API} · ${LOG_LM}"
    ;;

  down)
    log "Deteniendo API y stub del LM…"
    parar_pid "$PID_API"
    parar_pid "$PID_LM"
    log "Listo."
    ;;

  status)
    curl -s --max-time 3 "http://127.0.0.1:${E2E_API_PORT}/api/v1/health" && echo
    curl -s --max-time 3 "http://127.0.0.1:${E2E_LM_PORT}/health" && echo
    ;;

  *)
    fail "Uso: $0 [up|down|status]"
    ;;
esac