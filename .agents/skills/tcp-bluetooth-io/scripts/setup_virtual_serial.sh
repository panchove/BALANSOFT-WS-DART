#!/usr/bin/env bash
# Crea un par de puertos serie virtuales con socat (/tmp/ttyV0 <-> /tmp/ttyV1)
# para pruebas locales de básculas seriales en BALANSOFT-WS.

set -e

LINK0="/tmp/ttyV0"
LINK1="/tmp/ttyV1"

if ! command -v socat &>/dev/null; then
  echo "Error: socat no está instalado. Instálelo con: sudo apt install socat"
  exit 1
fi

rm -f "$LINK0" "$LINK1"

echo "[*] Creando par de puertos serie virtuales..."
echo "    Extremo emisor (simulador):  $LINK0"
echo "    Extremo receptor (backend):  $LINK1"
echo "[*] Presione Ctrl+C para detener."

exec socat -d -d pty,raw,echo=0,link="$LINK0" pty,raw,echo=0,link="$LINK1"
