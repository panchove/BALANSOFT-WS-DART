#!/usr/bin/env python3
"""Decodificador e inspector visual de secuencias binarias ESC/POS.

Permite analizar qué comandos contiene un archivo de volcado o stream binario
enviado a una impresora térmica.

Uso:
    python inspect_escpos.py /ruta/a/ticket.bin
"""

from __future__ import annotations

import sys

COMANDOS = {
    b"\x1b@": "ESC @ (Inicializar impresora)",
    b"\x1ba\x00": "ESC a 0 (Alineación: Izquierda)",
    b"\x1ba\x01": "ESC a 1 (Alineación: Centro)",
    b"\x1ba\x02": "ESC a 2 (Alineación: Derecha)",
    b"\x1bE\x01": "ESC E 1 (Negrita ACTIVADA)",
    b"\x1bE\x00": "ESC E 0 (Negrita DESACTIVADA)",
    b"\x1dVA\x00": "GS V A 0 (Corte de papel completo)",
    b"\x1dVA\x03": "GS V A 3 (Corte de papel parcial)",
    b"\x1dV\x01": "GS V 1 (Corte directo)",
    b"\x0c": "FF (Form Feed / Avance de página)",
}


def inspeccionar_bytes(data: bytes):
    pos = 0
    total = len(data)
    print(f"[*] Analizando {total} bytes de stream de impresión...\n")

    while pos < total:
        matched = False
        for cmd_bytes, desc in COMANDOS.items():
            if data.startswith(cmd_bytes, pos):
                print(f"[{pos:04X}] COMANDO -> {desc}")
                pos += len(cmd_bytes)
                matched = True
                break

        if not matched:
            # Si es texto ASCII imprimible
            b = data[pos]
            if 32 <= b <= 126 or b in (10, 13):
                char = chr(b)
                if char == "\n":
                    print(f"[{pos:04X}] TEXTO   -> [LF]")
                elif char == "\r":
                    pass
                else:
                    # Agrupar caracteres consecutivos
                    end = pos + 1
                    while end < total and (32 <= data[end] <= 126):
                        end += 1
                    chunk = data[pos:end].decode("latin-1", errors="replace")
                    print(f"[{pos:04X}] TEXTO   -> \"{chunk}\"")
                    pos = end - 1
            else:
                print(f"[{pos:04X}] BYTE    -> 0x{b:02X}")
            pos += 1


def main():
    if len(sys.argv) < 2:
        print("Uso: python inspect_escpos.py <archivo.bin>")
        sys.exit(1)

    archivo = sys.argv[1]
    with open(archivo, "rb") as f:
        data = f.read()

    inspeccionar_bytes(data)


if __name__ == "__main__":
    main()
