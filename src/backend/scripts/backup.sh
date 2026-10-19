#!/usr/bin/env bash
# ============================================================
# BALANSOFT-WS - Backup de base de datos + archivos adjuntos
#
# Uso:
#   DATABASE_URL_SYNC="postgresql+psycopg2://user:pass@host:5432/balansoft_ws" \
#     ./scripts/backup.sh
#
# Variables opcionales:
#   BACKUP_DIR            Directorio destino (default: backups/)
#   BACKUP_RETENTION_DAYS Días a conservar (default: 30)
#   MEDIA_DIR             Carpeta de adjuntos (default: media/)
#
# Si DATABASE_URL_SYNC no viene en el entorno, se lee de backend/.env.
# Prerrequisitos: pg_dump instalado y usuario con permisos de lectura.
#
# Cron sugerido (diario 02:30):
#   30 2 * * * /home/balansoft/balansoft-ws/backend/scripts/backup.sh >> /var/log/balansoft-backup.log 2>&1
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

BACKUP_DIR="${BACKUP_DIR:-backups}"
MEDIA_DIR="${MEDIA_DIR:-media}"
RETENTION="${BACKUP_RETENTION_DAYS:-30}"
STAMP="$(date +%Y%m%d-%H%M%S)"

# ---------------------------------------------------------------------------
# 1. Resolver URI de conexión (env o .env) — mismo patrón que setup_db.sh
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

URI="${DATABASE_URL_SYNC/postgresql+psycopg2:/postgresql:}"
URI="${URI/postgresql+asyncpg:/postgresql:}"

DBNAME="${URI##*/}"
DBNAME="${DBNAME%%\?*}"
DBNAME="${DBNAME%%#*}"

# ---------------------------------------------------------------------------
# 2. Preparar directorios
# ---------------------------------------------------------------------------
mkdir -p "${BACKUP_DIR}/db" "${BACKUP_DIR}/media"

echo "→ Backup de '${DBNAME}' iniciado a las $(date '+%F %T')"

# ---------------------------------------------------------------------------
# 3. Backup de la base de datos (formato custom, comprimido por defecto)
# ---------------------------------------------------------------------------
DB_FILE="${BACKUP_DIR}/db/${DBNAME}.${STAMP}.dump"
echo "→ pg_dump → ${DB_FILE}"
pg_dump "${URI}" --format=custom --file="${DB_FILE}"
echo "   Tamaño: $(du -h "${DB_FILE}" | cut -f1)"

# ---------------------------------------------------------------------------
# 4. Backup de archivos adjuntos (solo si la carpeta existe)
# ---------------------------------------------------------------------------
MEDIA_FILE="${BACKUP_DIR}/media/${DBNAME}.media.${STAMP}.tar.gz"
if [[ -d "${MEDIA_DIR}" ]] && [[ -n "$(ls -A "${MEDIA_DIR}" 2>/dev/null)" ]]; then
  echo "→ tar.gz ${MEDIA_DIR} → ${MEDIA_FILE}"
  tar -czf "${MEDIA_FILE}" -C "$(dirname "${MEDIA_DIR}")" "$(basename "${MEDIA_DIR}")"
  echo "   Tamaño: $(du -h "${MEDIA_FILE}" | cut -f1)"
else
  echo "→ Sin archivos en '${MEDIA_DIR}', se omite el backup de media."
fi

# ---------------------------------------------------------------------------
# 5. Retención: borrar copias más antiguas que RETENTION días
# ---------------------------------------------------------------------------
echo "→ Limpieza de backups con > ${RETENTION} días..."
KEEP_DB="$(find "${BACKUP_DIR}/db" -name "*.dump" -type f -mtime "+${RETENTION}" -print)"
KEEP_MEDIA="$(find "${BACKUP_DIR}/media" -name "*.tar.gz" -type f -mtime "+${RETENTION}" -print 2>/dev/null || true)"
if [[ -n "${KEEP_DB}" ]]; then
  echo "   Borrando (db):"
  echo "${KEEP_DB}" | while read -r f; do echo "   - $f"; done
  echo "${KEEP_DB}" | xargs -r rm -f
fi
if [[ -n "${KEEP_MEDIA}" ]]; then
  echo "   Borrando (media):"
  echo "${KEEP_MEDIA}" | while read -r f; do echo "   - $f"; done
  echo "${KEEP_MEDIA}" | xargs -r rm -f
fi

echo "✅ Backup completado a las $(date '+%F %T')"