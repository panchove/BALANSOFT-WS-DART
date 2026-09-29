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
#   5. Respalda (pg_dump -Fc) y elimina las bases locales de PostgreSQL que
#      crea la instalación (balansoft_ws, balansoft_ws_local,
#      balansoft_ws_server). Sin pg_dump disponible, el script ABORTA y no
#      borra nada: los datos pesan más que la comodidad del reset.
#   6. Reconstruye el bundle: flutter build linux + copia WServer e icono.
#
# Uso:
#   scripts/reset_total.sh            # con confirmaciones
#   scripts/reset_total.sh -y         # sin confirmaciones
#   scripts/reset_total.sh --no-build # limpia sin reconstruir el bundle
#   scripts/reset_total.sh --no-db    # no toca PostgreSQL
#   scripts/reset_total.sh --clean     # rebuild limpio (flutter clean: exige red)
#   scripts/reset_total.sh --purge-legacy    # borra también los tokens de ids viejos
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

# Identificadores de app de versiones anteriores: sus items del keyring ya no
# los lee la app actual, pero contienen tokens viejos. Se purgan con
# --purge-legacy.
SECRET_LEGACY=(
  "com.example.balansoft_client.secureStorage"
  "com.balansoft.bws.secureStorage"
  "com.balansoft.sg.secureStorage"
)

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
CLEAN_BUILD=0
PURGE_LEGACY=0
PURGE_BACKUPS=0
for arg in "$@"; do
  case "$arg" in
    -y | --yes) CONFIRM=0 ;;
    --no-build) DO_BUILD=0 ;;
    --no-db) DO_DB=0 ;;
    --clean) CLEAN_BUILD=1 ;;
    --purge-legacy) PURGE_LEGACY=1 ;;
    --purge-backups) PURGE_BACKUPS=1 ;;
    -h | --help)
      sed -n '2,24p' "$0"
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
    printf '  - Bases PostgreSQL       → %s\n    (antes se respaldan en el backup de la ejecución)\n' "${DBS_VIRGEN[*]}"
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
# flutter_secure_storage_linux guarda TODOS los secretos de la app en un único
# item de libsecret, localizado por el atributo `account`. Por eso se busca
# ese item concreto: recorrer `get_all_items()` es frágil (la colección puede
# tener entradas fantasma que lancen ItemNotFoundException y aborten el
# generador) y además expondría secretos de otras apps.
info "Eliminando tokens del almacén seguro (keyring)... "
LEGACY_ARGS=()
if [[ "$PURGE_LEGACY" == "1" ]]; then
  for cuenta in "${SECRET_LEGACY[@]}"; do
    LEGACY_ARGS+=("$cuenta")
  done
fi

set +e
SECRET_OUT="$(python3 - "$SECRET_ACCOUNT" "${LEGACY_ARGS[@]+"${LEGACY_ARGS[@]}"}" <<'EOF'
import sys

import secretstorage
from secretstorage.exceptions import ItemNotFoundException

principal = sys.argv[1]
cuentas = sys.argv[2:]

try:
    bus = secretstorage.dbus_init()
    coll = secretstorage.get_default_collection(bus)
    coll.unlock()
except Exception as e:  # sin sesión gráfica / sin Secret Service
    print(f"  [!] Keyring no disponible: {e}")
    sys.exit(0)


def purgar(cuenta: str) -> int:
    """Elimina el item de la cuenta indicada. Devuelve cuántos borró."""
    try:
        # Se piden las rutas por D-Bus (SearchItems filtra por atributo) para no
        # construir Items de entradas ajenas o fantasma.
        rutas, = coll._collection.call(
            "SearchItems", "a{ss}", {"account": cuenta}
        )
    except Exception as e:
        print(f"  [!] No se pudo consultar '{cuenta}': {e}")
        return -1

    borrados = 0
    for ruta in list(rutas):
        try:
            item = secretstorage.item.Item(coll.connection, ruta, coll.session)
            etiqueta = item.get_label()
            item.delete()
            borrados += 1
            print(f"  [✓] Secreto eliminado: {etiqueta}")
        except ItemNotFoundException:
            # El índice lo tiene pero el servicio ya no: nada que borrar.
            pass
        except Exception as e:
            print(f"  [!] No se pudo eliminar '{cuenta}': {e}")
    return borrados


principal_borrados = purgar(principal)
for cuenta in cuentas:
    purgar(cuenta)

# Verificación: el item de la app no debe volver a aparecer.
try:
    restante, = coll._collection.call(
        "SearchItems", "a{ss}", {"account": principal}
    )
    if len(list(restante)):
        print("  [!] El keyring todavía tiene secretos de esta app.")
        sys.exit(1)
    print(f"  [i] Tokens eliminados: {max(principal_borrados, 0)}")
    sys.exit(0)
except SystemExit:
    raise
except Exception as e:
    print(f"  [!] No se pudo verificar el keyring: {e}")
    sys.exit(0)
EOF
)"
SECRET_RC=$?
set -e

echo "$SECRET_OUT"
if [[ "$SECRET_RC" == "0" ]]; then
  ok "Almacén seguro limpio."
else
  err "Los tokens de la app NO se pudieron eliminar (quedan en el keyring)."
  err "Si la app entra solo, borra el secreto desde 'Contraseñas y llaves'"
  err "de GNOME o ejecuta: scripts/reset_total.sh --no-build"
fi

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
  # 5b. Respaldo previo de las bases (integridad). Sin pg_dump o si el
  # respaldo falla se ABORTA: nunca se borra una base sin tener su copia.
  if ! command -v pg_dump >/dev/null 2>&1; then
    err "No se encontró 'pg_dump'. Sin respaldo previo NO se eliminan las bases."
    err "Instala el cliente PostgreSQL o ejecuta con --no-db."
    exit 1
  fi
  DB_BK_DIR="$BP/db"
  mkdir -p "$DB_BK_DIR"
  for db in "${DBS_VIRGEN[@]}"; do
    if PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$db';" | grep -q '^1$'; then
      info "Respaldo de '$db' → $DB_BK_DIR/$db.pgdump ..."
      if ! PGPASSWORD="$PGPASSWORD" pg_dump -Fc -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$db" -f "$DB_BK_DIR/$db.pgdump"; then
        err "Falló el respaldo de '$db'. Se ABORTA para no perder datos."
        exit 1
      fi
      ok "Respaldo de '$db' completado."
    else
      ok "Base '$db' no existe: no hay nada que respaldar."
    fi
  done

  for db in "${DBS_VIRGEN[@]}"; do
    PGPASSWORD="$PGPASSWORD" psql -v ON_ERROR_STOP=1 \
      -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres \
      -c "DROP DATABASE IF EXISTS $db;"
  done
  ok "Bases PostgreSQL eliminadas (respaldo previo en $DB_BK_DIR)."
else
  info "Omitiendo PostgreSQL (--no-db)."
fi

# ── 6. Reconstruir bundle ────────────────────────────────────────────────────
BUILD_OK=1
if [[ "$DO_BUILD" == "1" ]]; then
  info "Reconstruyendo bundle de release... "
  if [[ ! -x "$WSERVER_BIN" ]]; then
    err "No existe el binario del WServer. Compílalo primero: backend/scripts/build_wserver.sh"
    BUILD_OK=0
  else
    # `flutter clean` borra .dart_tool y obliga a resolver dependencias (necesita
    # red). Por defecto solo se reconstruye: los resets son frecuentes y el
    # build incremental es mucho más rápido. Usa --clean si lo necesitas.
    set +e
    (
      cd "$ROOT/frontend" || exit 1
      if [[ "$CLEAN_BUILD" == "1" ]]; then
        flutter clean >/dev/null
      fi
      flutter build linux --release
    )
    BUILD_RC=$?
    set -e

    if [[ "$BUILD_RC" != "0" ]] || [[ ! -x "$BUNDLE/balansoft_ws" ]]; then
      err "Falló 'flutter build linux --release' (código $BUILD_RC)."
      if [[ "$CLEAN_BUILD" == "0" ]] && [[ ! -f "$ROOT/frontend/.dart_tool/package_config.json" ]]; then
        err "Faltan las dependencias: ejecuta 'flutter pub get' en frontend/ (revisa la red)."
      else
        err "Prueba otra vez, o usa --no-build y valida con 'flutter run -d linux'."
      fi
      BUILD_OK=0
    else
      install -Dm755 "$WSERVER_BIN" "$BUNDLE/WServer"
      ok "WServer copiado al bundle."
      if [[ -f "$WSERVER_ICON" ]]; then
        install -Dm644 "$WSERVER_ICON" "$BUNDLE/wserver_icon.jpeg"
        ok "Icono del WServer (wserver_icon.jpeg) copiado al bundle."
      fi
    fi
  fi
else
  info "Omitiendo rebuild (--no-build)."
fi

# ── Resumen ──────────────────────────────────────────────────────────────────
echo ""
if [[ "$DO_BUILD" == "1" && "$BUILD_OK" != "1" ]]; then
  err "El reset de estado está hecho, pero el bundle NO quedó reconstruido."
  echo ""
fi
echo "  == Listo =="
if [[ -d "$BP" ]]; then
  echo "  Backups de esta ejecución: $BP"
fi
if [[ "$DO_BUILD" == "1" && "$BUILD_OK" == "1" ]]; then
  echo "  Bundle listo: $BUNDLE"
  echo "  Prueba la instalación con:"
  echo "    $BUNDLE/balansoft_ws"
elif [[ "$DO_BUILD" == "1" ]]; then
  echo "  Para dejar el bundle listo:"
  echo "    cd $ROOT/frontend && flutter pub get && flutter build linux --release"
  echo "    install -Dm755 $WSERVER_BIN $BUNDLE/WServer"
  echo "  (o vuelve a ejecutar este script)"
else
  echo "  Para probar: flutter run -d linux  (desde frontend/)"
fi
echo "  El WServer regenerará su runtime en la primera ejecución."
echo ""