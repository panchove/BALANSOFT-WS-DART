#!/usr/bin/env bash
# ============================================================
# BALANSOFT-WS · Reset total para pruebas desde la instalación
#
# Deja la máquina "virgen" y reconstruye el bundle de lanzador:
#   1. Cierra la app y el WServer.
#   2. Respaldar y eliminar el estado de la app (prefs, caches, sesión).
#   3. Elimina los tokens del almacén seguro (keyring/libsecret).
#   4. Elimina el runtime del WServer (~/.balansoft-ws/wserver) para que la
#      primera ejecución lo regenere desde la plantilla.
#   5. Elimina las bases locales de PostgreSQL que crea la instalación
#      (balansoft_ws, balansoft_ws_local, balansoft_ws_server).
#   6. Reconstruye el bundle: flutter build linux + copia WServer e icono.
#
# Uso:
#   scripts/reset_total.sh            # con confirmaciones
#   scripts/reset_total.sh -y         # sin confirmaciones
#   scripts/reset_total.sh --no-build # limpia sin reconstruir el bundle
#   scripts/reset_total.sh --no-db    # no toca PostgreSQL
#   scripts/reset_total.sh --purge-backups   # también borra backups viejos
#
# Variables de entorno opcionales para PostgreSQL (por defecto rol sqlman):
#   PGUSER=sqlman PGPASSWORD=7767 PGHOST=localhost PGPORT=5432
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Configuración ──────────────────────────────────────────────────────────
APP_DATA="$HOME/.local/share/com.balansoft.balansoft_ws"
BACKUP_ROOT="$HOME/.balansoft-ws-reset/backups"
WSRUNTIME="$HOME/.balansoft-ws/wserver"
AUTOSTART_DESKTOP="$HOME/.config/autostart/com.balansoft.wserver.desktop"
SECRET_ACCOUNT="com.balansoft.balansoft_ws.secureStorage"

BUNDLE="$ROOT/frontend/build/linux/x64/release/bundle"
WSERVER_BIN="$ROOT/backend/dist/WServer"
WSERVER_ICON="$ROOT/wserver_icon.jpeg"

DBS_VIRGEN=("balansoft_ws" "balansoft_ws_local" "balansoft_ws_server")

PGUSER="${PGUSER:-sqlman}"
PGPASSWORD="${PGPASSWORD:-7767}"
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"

# ── Flags ──────────────────────────────────────────────────────────────────
CONFIRM=1
DO_BUILD=1
DO_DB=1
PURGE_BACKUPS=0
for arg in "$@"; do
  case "$arg" in
    -y | --yes) CONFIRM=0 ;;
    --no-build) DO_BUILD=0 ;;
    --no-db) DO_DB=0 ;;
    --purge-backups) PURGE_BACKUPS=1 ;;
    -h | --help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      echo "❌ Argumento desconocido: $arg" >&2
      exit 2
      ;;
  esac
done

# ── Utilidades ──────────────────────────────────────────────────────────────
info() { printf '\033[1;34m[1] %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[✓] %s\033[0m\n' "$*"; }
aviso(){ printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31m[✗] %s\033[0m\n' "$*"; }

# ── Banner + confirmación ───────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║   BALANSOFT-WS · Reset total para instalación/ pruebas   ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo ""

if [[ "$CONFIRM" == "1" ]]; then
  echo "Se va a eliminar:"
  echo "  - Estado de la app        → $APP_DATA"
  echo "  - Tokens del keyring      → $SECRET_ACCOUNT"
  echo "  - Runtime del WServer     → $WSRUNTIME"
  if [[ "$DO_DB" == "1" ]]; then
    printf '  - Bases PostgreSQL       → %s\n' "${DBS_VIRGEN[*]}"
  fi
  if [[ "$DO_BUILD" == "1" ]]; then
    echo "  (y reconstruirá el bundle de release)"
  fi
  echo ""
  read -rp 'Escribe "si" (en minúsculas) para continuar: ' RESPUESTA
  [[ "$RESPUESTA" == "si" ]] || { echo "Abortado."; exit 1; }
fi

TS="$(date +%Y%m%d-%H%M%S)"
BP="$BACKUP_ROOT/$TS"

# ── 1. Cerrar app y WServer ─────────────────────────────────────────────────
info "Deteniendo la app y el WServer... "
if pkill -x balansoft_ws 2>/dev/null; then aviso "App cerrada."; else ok "No había app corriendo."; fi
if pkill -x WServer 2>/dev/null; then aviso "WServer detenido."; else ok "No había WServer corriendo."; fi
sleep 1

# ── 2. Estado de la app ─────────────────────────────────────────────────────
info "Limpiando estado de la app... "
rm -f "$AUTOSTART_DESKTOP"
if [[ -e "$APP_DATA" ]]; then
  mkdir -p "$BP"
  mv "$APP_DATA" "$BP/app-data"
  ok "Estado de la app respaldado en $BP/app-data"
else
  ok "No existía estado de la app."
fi

# ── 3. Tokens del almacén seguro ─────────────────────────────────────────────
info "Eliminando tokens del almacén seguro (keyring)... "
python3 - "$SECRET_ACCOUNT" <<'EOF' || aviso "No se pudo consultar el keyring (se omite)."
import sys
import secretstorage
try:
    bus = secretstorage.dbus_init()
    coll = secretstorage.get_default_collection(bus)
    coll.unlock()
except Exception:
    sys.exit(0)
for item in coll.get_all_items():
    if item.get_attributes().get("account") == sys.argv[1]:
        try:
            item.delete()
            print("  [✓] Secreto eliminado:", item.get_label())
        except Exception as e:
            print("  [!] No se pudo eliminar:", e)
EOF

# ── 4. Runtime del WServer ──────────────────────────────────────────────────
info "Limpiando runtime del WServer... "
if [[ -e "$WSRUNTIME" ]]; then
  mkdir -p "$BP"
  mv "$WSRUNTIME" "$BP/wserver"
  ok "Runtime respaldado en $BP/wserver"
else
  ok "No existía runtime del WServer."
fi

if [[ "$PURGE_BACKUPS" == "1" ]] && [[ -d "$BACKUP_ROOT" ]]; then
  rm -rf "$BACKUP_ROOT"/*
  aviso "Backups antiguos eliminados (--purge-backups)."
fi

# ── 5. PostgreSQL ─────────────────────────────────────────────────────────
if [[ "$DO_DB" == "1" ]]; then
  info "Eliminando bases locales (${DBS_VIRGEN[*]})... "
  if ! command -v psql >/dev/null 2>&1; then
    err "No se encontró 'psql' en el PATH. Instala el cliente PostgreSQL o usa --no-db."
    exit 1
  fi

  DBS_SQL=()
  for db in "${DBS_VIRGEN[@]}"; do
    DBS_SQL+=("'$db'")
  done
  DBS_IN="$(IFS=,; echo "${DBS_SQL[*]}")"

  if ! PGPASSWORD="$PGPASSWORD" psql -v ON_ERROR_STOP=1 \
    -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname IN ($DBS_IN) AND pid <> pg_backend_pid();" ; then
    err "No se pudo conectar a PostgreSQL en $PGHOST:$PGPORT con $PGUSER."
    err "Revisa PGPASSWORD/PGUSER o levanta el servicio (sudo systemctl start postgresql)."
    exit 1
  fi
  for db in "${DBS_VIRGEN[@]}"; do
    PGPASSWORD="$PGPASSWORD" psql -v ON_ERROR_STOP=1 \
      -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres \
      -c "DROP DATABASE IF EXISTS $db;"
  done
  ok "Bases PostgreSQL eliminadas."
else
  info "Omitiendo PostgreSQL (--no-db)."
fi

# ── 6. Reconstruir bundle ────────────────────────────────────────────────────
if [[ "$DO_BUILD" == "1" ]]; then
  info "Reconstruyendo bundle de release... "
  if [[ ! -x "$WSERVER_BIN" ]]; then
    err "No existe el binario del WServer. Compílalo primero: backend/scripts/build_wserver.sh"
    exit 1
  fi
  (cd "$ROOT/frontend" && flutter clean >/dev/null && flutter build linux --release)
  cp "$WSERVER_BIN" "$BUNDLE/WServer"
  chmod +x "$BUNDLE/WServer"
  ok "WServer copiado al bundle."
  if [[ -f "$WSERVER_ICON" ]]; then
    cp "$WSERVER_ICON" "$BUNDLE/wserver_icon.jpeg"
    ok "Icono del WServer (wserver_icon.jpeg) copiado al bundle."
  fi
else
  info "Omitiendo rebuild (--no-build)."
fi

# ── Resumen ──────────────────────────────────────────────────────────────────
echo ""
echo "  == Listo =="
if [[ -d "$BP" ]]; then
  echo "  Backups de esta ejecución: $BP"
fi
if [[ "$DO_BUILD" == "1" ]]; then
  echo "  Bundle listo: $BUNDLE"
  echo "  Prueba la instalación con:"
  echo "    $BUNDLE/balansoft_ws"
else
  echo "  Para probar: flutter run -d linux  (desde frontend/)"
fi
echo "  El WServer regenerará su runtime en la primera ejecución."
echo ""