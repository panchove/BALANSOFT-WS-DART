#!/usr/bin/env python3
"""Prueba rápida de tramas contra el parser multi-marca de BALANSOFT-WS.

Uso:
    python test_frame.py "ST,GS,+00320.00kg"
    python test_frame.py "=+000023.5kg"
    python test_frame.py "\x02ST,GS,+00320.00kg\x032B"
"""

from __future__ import annotations

import os
import sys

# Ajustar sys.path para importar app
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../../backend")))

try:
    from app.core.scale_parser import parse_weight_frame
except ImportError:
    print("Error: No se pudo importar app.core.scale_parser. Verifique la ruta del backend.")
    sys.exit(1)


def main():
    if len(sys.argv) < 2:
        print("Uso: python test_frame.py '<trama>' [capacidad_max_kg]")
        sys.exit(1)

    raw_input = sys.argv[1]
    capacidad = float(sys.argv[2]) if len(sys.argv) > 2 else None

    # Procesar secuencias de escape si se pasan por consola (\x02, \r, \n)
    try:
        frame = raw_input.encode("utf-8").decode("unicode_escape")
    except Exception:
        frame = raw_input

    peso, estado, motivo = parse_weight_frame(frame, capacidad_max=capacidad)

    print("=" * 60)
    print(f"Trama evaluada: {repr(frame)}")
    print(f"Bytes hex:      {frame.encode('latin-1', errors='replace').hex()}")
    print("-" * 60)
    print(f"Resultado Peso: {peso} kg" if peso is not None else "Resultado Peso: None (Rechazado)")
    print(f"Estado:         {estado}")
    print(f"Motivo:         {motivo if motivo else 'OK (Válido)'}")
    print("=" * 60)


if __name__ == "__main__":
    main()
