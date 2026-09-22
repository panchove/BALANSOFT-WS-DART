#!/usr/bin/env bash
# ============================================================
# BALANSOFT-WS - Vaciado total de las bases de datos
#
# Deja las BDs con su esquema canónico VACÍO (sin datos):
#   local  -> $DATABASE_URL  (balansoft_ws)  con balansoft-ws-local.sql
#                                    + migrations/*.sql (idempotentes)
#   server -> $SERVER_DATABASE_URL (balansoft_ws_server)
#                                    con balansoft-ws-server.sql
#
# Uso:
#   ./scripts/reset_db.sh            # vacía local + server (desde .env)
#   RESET_DRY_RUN=1 ./scripts/reset_db.sh   # solo imprime el plan
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

DRY="${RESET_DRY_RUN:-0}"

# ---------------------------------------------------------------------------
# 1. Resolver URIs desde el entorno o backend/.env
# ---------------------------------------------------------------------------
_leer_env() {
  if [[ -f .env ]]; then
    grep -E "^$1=" .env | head -1 | sed "s/^$1=//" | tr -d '"' | tr -d "'"
  fi
}

LOCAL_URL="${DATABASE_URL_SYNC:-$(_leer_env DATABASE_URL_SYNC)}"
SERVER_URL="${SERVER_DATABASE_URL_URI:-$(_leer_env SERVER_DATABASE_URL)}"
if [[ -z "${SERVER_URL:-}" ]]; then
  SERVER_URL="${LOCAL_URL}"
fi

if [[ -z "${LOCAL_URL:-}" ]]; then
  echo "ERROR: define DATABASE_URL_SYNC (o en .env)." >&2
  exit 1
fi

_norm() {
  local u="$1"
  u="${u/postgresql+psycopg2:/postgresql:}"
  u="${u/postgresql+asyncpg:/postgresql:}"
  echo "$u"
}

LOCAL_URI="$(_norm "$LOCAL_URL")"
SERVER_URI="$(_norm "$SERVER_URL")"

# ---------------------------------------------------------------------------
# 2. Vaciado de una BD (drop schema public + recrear + esquema canónico)
# ---------------------------------------------------------------------------
_vaciar() {
  local uri="$1"  schema_file="$2"  aplicar_migraciones="$3"  etiqueta="$4"

  local esc rest hostpart dbname
  esc="${uri%%://*}"; rest="${uri#*://}"; rest="${rest%%\#*}"; rest="${rest%%\?*}"
  hostpart="${rest%/*}"; dbname="${rest##*/}"

  echo "==> ${etiqueta}: ${dbname} en ${hostpart}"

  if [[ "${DRY}" == "1" ]]; then
    echo "    (dry-run) drop schema public, schema: ${schema_file}, migraciones: ${aplicar_migraciones}"
    return 0
  fi

  # Borra TODOS los objetos (tablas, índices, FKs, tipos, funciones auxiliares)
  # EJECUTADO CONTRA LA PROPIA BD OBJETIVO (no contra 'postgres').
  psql "${uri}" -v ON_ERROR_STOP=1 \
    -c "DROP SCHEMA IF EXISTS public CASCADE;" \
    -c "CREATE SCHEMA public;" \
    -c "GRANT ALL ON SCHEMA public TO PUBLIC;"

  echo "    aplicando esquema canónico..."
  psql "${uri}" -v ON_ERROR_STOP=1 -f "${schema_file}"

  if [[ "${aplicar_migraciones}" == "1" ]]; then
    echo "    aplicando migraciones (idempotentes)..."
    for f in migrations/*.sql; do
      psql "${uri}" -v ON_ERROR_STOP=1 -q -f "${f}"
    done
  fi

  echo "    ✅ ${etiqueta} vaciada y esquemada."
}

# ---------------------------------------------------------------------------
# 3. Ejecutar sobre local y server
# ---------------------------------------------------------------------------
_vaciar "${LOCAL_URI}"  "balansoft-ws-local.sql"  "1" "BD LOCAL"
_vaciar "${SERVER_URI}" "balansoft-ws-server.sql" "0" "BD SERVER"

echo "✔ Vaciado completado. Databases listas para una instalación limpia."