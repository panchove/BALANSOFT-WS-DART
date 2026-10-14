#!/usr/bin/env bash
# ============================================================
# BALANSOFT-WS — Reconciliar el equipo TITULAR de una cuenta (rol server)
#
# Sirve cuando hay que mover la titularidad de una licencia a OTRA huella de
# máquina (p. ej. el equipo titular se reinstaló y su /etc/machine-id cambió, o
# la licencia quedó amarrada a una huella de desarrollo y la estación real no
# puede entrar como ADMIN). Reutiliza la fila existente cuando puede, para no
# perder sesiones/sincronización, y NUNCA borra filas.
#
# Uso:
#   CUENTA=<uuid-de-la-cuenta> HW_NUEVO=<machine-id-real> [HW_VIEJO=<huella-vieja>] \
#     ./scripts/reconcile_titular.sh              # ENSAYO (no cambia nada)
#   ... APPLY=1 ./scripts/reconcile_titular.sh    # aplica
#
# Variables:
#   CUENTA     (obligatorio) UUID de la cuenta (tabla cuentas.id_cuenta)
#   HW_NUEVO   (obligatorio) huella de la máquina que debe ser titular
#   HW_VIEJO   (opcional)  huella actual del titular; si se omite se toma de la
#                          licencia activa de la cuenta
#   APPLY      (opcional)  "1" confirma; sin él, solo muestra el resultado
#   DATABASE_URL_SYNC      URI del central (o se lee de backend/.env)
#
# Nota: el `hardware_id` del Linux es el contenido de /etc/machine-id
#       (cat /etc/machine-id); en Windows, el deviceId de WinRT.
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

: "${CUENTA:?define CUENTA=<uuid de la cuenta>}"
: "${HW_NUEVO:?define HW_NUEVO=<machine-id real>}"
HW_VIEJO="${HW_VIEJO:-}"
APPLY="${APPLY:-0}"

if [[ -z "${DATABASE_URL_SYNC:-}" && -f .env ]]; then
  DATABASE_URL_SYNC="$(grep -E '^DATABASE_URL_SYNC=' .env | head -1 | sed 's/^DATABASE_URL_SYNC=//' | tr -d '"' | tr -d "'")"
fi
if [[ -z "${DATABASE_URL_SYNC:-}" ]]; then
  echo "ERROR: define DATABASE_URL_SYNC (o en backend/.env)." >&2
  exit 1
fi

# URI de SQLAlchemy -> URI estándar de psql
URI="${DATABASE_URL_SYNC/postgresql+psycopg2:/postgresql:}"
URI="${URI/postgresql+asyncpg:/postgresql:}"

echo "→ Cuenta:        ${CUENTA}"
echo "→ Hardware nuevo: ${HW_NUEVO}"
echo "→ Hardware viejo: ${HW_VIEJO:-<de la licencia activa>}"
echo "→ Modo:          $([[ "${APPLY}" == "1" ]] && echo APLICAR || echo ENSAYO)"

psql "${URI}" -v ON_ERROR_STOP=1 \
  -v cuenta="${CUENTA}" -v hw_nuevo="${HW_NUEVO}" -v hw_viejo="${HW_VIEJO}" \
  -v apply="${APPLY}" \
  -f scripts/reconcile_titular.sql

if [[ "${APPLY}" == "1" ]]; then
  echo "✅ Reconciliación aplicada. Reinicia el servicio SOLO si desplegaste código."
else
  echo "ℹ️  Ensayo completado. Repite con APPLY=1 para aplicar."
fi
