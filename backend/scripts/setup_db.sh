#!/usr/bin/env bash
# ============================================================
# BALANSOFT-WS - Preparación de la base de datos en servidor
#
# Modos:
#   instalar (default)  Crea la BD si no existe y aplica schema.sql (esquema final).
#   aplicar-migraciones  Actualiza una BD existente aplicando migrations/*.sql en orden.
#   seed                 Inserta empresa demo, admin y catálogos base (opcional).
#
# Uso:
#   DATABASE_URL_SYNC="postgresql+psycopg2://user:pass@host:5432/balansoft_ws" \
#     ./scripts/setup_db.sh [instalar|aplicar-migraciones|seed]
#
# Si DATABASE_URL_SYNC no viene en el entorno, se lee de backend/.env.
# Prerrequisitos: psql instalado y usuario con permisos de creación de BD.
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

MODO="${1:-instalar}"
ON_ERROR_STOP=1
export ON_ERROR_STOP

# ---------------------------------------------------------------------------
# 1. Resolver URI de conexión (env o .env)
# ---------------------------------------------------------------------------
if [[ -z "${DATABASE_URL_SYNC:-}" ]]; then
  if [[ -f .env ]]; then
    DATABASE_URL_SYNC="$(grep -E '^DATABASE_URL_SYNC=' .env | head -1 | sed 's/^DATABASE_URL_SYNC=//' | tr -d '"' | tr -d "'")"
  fi
fi
if [[ -z "${DATABASE_URL_SYNC:-}" ]]; then
  echo "ERROR: define DATABASE_URL_SYNC (o en .env)." >&2
  exit 1
fi

# Convertir driver de SQLAlchemy -> URI estándar de psql
URI="${DATABASE_URL_SYNC/postgresql+psycopg2:/postgresql:}"
URI="${URI/postgresql+asyncpg:/postgresql:}"

SCHEME="${URI%%://*}"
REST="${URI#*://}"
REST="${REST%%#*}"                       # sin fragmento
REST="${REST%%\?*}"                      # sin query string
HOSTPART="${REST%/*}"                    # user:pass@host:port
DBNAME="${REST##*/}"

echo "→ Base de datos: ${DBNAME} en ${HOSTPART}"

# Permitir override para credenciales con caracteres especiales en la password
SERVER_URI="${PG_SERVER_URI:-${SCHEME}://${HOSTPART}/postgres}"

# ---------------------------------------------------------------------------
# 2. Acciones
# ---------------------------------------------------------------------------
case "${MODO}" in
  instalar)
    # Crear la BD si no existe (conectar al server 'postgres' para CREATE DATABASE)
    if psql "${SERVER_URI}" -tAc "SELECT 1 FROM pg_database WHERE datname='${DBNAME}'" | grep -q 1; then
      echo "→ La BD '${DBNAME}' ya existe."
    else
      echo "→ Creando BD '${DBNAME}'..."
      psql "${SERVER_URI}" -c "CREATE DATABASE \"${DBNAME}\""
    fi

    echo "→ Aplicando schema.sql..."
    psql "${URI}" -v ON_ERROR_STOP=1 -f schema.sql
    echo "✅ Esquema instalado."
    ;;

  aplicar-migraciones)
    echo "→ Aplicando migraciones en orden a '${DBNAME}'..."
    for f in migrations/*.sql; do
      echo "   - ${f}"
      psql "${URI}" -v ON_ERROR_STOP=1 -f "${f}"
    done
    echo "✅ Migraciones aplicadas."
    ;;

  seed)
    echo "→ Insertando datos demo (empresa + admin + catálogos base)..."
    uv run python scripts/seed_data.py
    echo "✅ Seed aplicado."
    ;;

  *)
    echo "Uso: $0 [instalar|aplicar-migraciones|seed]" >&2
    exit 1
    ;;
esac

echo "✔ Listo. Sigue con: uv run uvicorn app.main:app --host 0.0.0.0 --port 8000"