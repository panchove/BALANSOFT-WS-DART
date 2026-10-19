#!/usr/bin/env python3
"""Calculadora y validador de distribuciones de peso de camiones para BALANSOFT-WS.

Uso:
    python truck_weight_calculator.py \
      --pe-camion 12500 --ps-camion 4200 \
      --pe-remolque 8500 --ps-remolque 3100 \
      --operacion RECEPCION --declarado 13650
"""

from __future__ import annotations

import argparse
from decimal import Decimal


def calcular(
    pe_c: float,
    ps_c: float,
    pe_r: float = 0.0,
    ps_r: float = 0.0,
    operacion: str = "RECEPCION",
    declarado: float | None = None,
):
    d_pe_c = Decimal(str(pe_c))
    d_ps_c = Decimal(str(ps_c))
    d_pe_r = Decimal(str(pe_r))
    d_ps_r = Decimal(str(ps_r))

    pte = d_pe_c + d_pe_r
    pts = d_ps_c + d_ps_r

    neto_c = abs(d_pe_c - d_ps_c)
    neto_r = abs(d_pe_r - d_ps_r) if (pe_r > 0 or ps_r > 0) else Decimal("0.0")
    neto_total = abs(pte - pts)

    print("=" * 65)
    print(f" CÁLCULO DE PESOS DE CAMIÓN — BALANSOFT-WS ({operacion})")
    print("=" * 65)
    print(f"Camión / Chuto Entrada:   {d_pe_c:12.2f} kg")
    print(f"Camión / Chuto Salida:    {d_ps_c:12.2f} kg")
    print(f"-> Neto Camión:           {neto_c:12.2f} kg")
    print("-" * 65)
    if pe_r > 0 or ps_r > 0:
        print(f"Remolque Entrada:         {d_pe_r:12.2f} kg")
        print(f"Remolque Salida:          {d_ps_r:12.2f} kg")
        print(f"-> Neto Remolque:         {neto_r:12.2f} kg")
        print("-" * 65)
    print(f"PESO TOTAL ENTRADA (PTE): {pte:12.2f} kg")
    print(f"PESO TOTAL SALIDA (PTS):  {pts:12.2f} kg")
    print(f"PESO NETO TOTAL (PNT):    {neto_total:12.2f} kg")
    print("-" * 65)

    if operacion.upper() == "RECEPCION":
        print("KARDEX: ID 10 (INGRESO)   -> +" f"{neto_total:.2f} kg al almacén")
    else:
        print("KARDEX: ID 60 (DESPACHO)  -> -" f"{neto_total:.2f} kg del almacén")

    if declarado is not None:
        d_decl = Decimal(str(declarado))
        dif = neto_total - d_decl
        desv = (dif / d_decl * 100) if d_decl != 0 else Decimal("0.0")
        print("-" * 65)
        print(f"Peso Declarado en Guía:   {d_decl:12.2f} kg")
        print(f"Diferencia (Real - Decl): {dif:12.2f} kg")
        print(f"Desviación Porcentual:    {desv:12.4f} %")
    print("=" * 65)


def main():
    parser = argparse.ArgumentParser(description="Calculadora de pesos de camión")
    parser.add_argument("--pe-camion", type=float, required=True, help="Peso entrada camión (kg)")
    parser.add_argument("--ps-camion", type=float, required=True, help="Peso salida camión (kg)")
    parser.add_argument("--pe-remolque", type=float, default=0.0, help="Peso entrada remolque (kg)")
    parser.add_argument("--ps-remolque", type=float, default=0.0, help="Peso salida remolque (kg)")
    parser.add_argument(
        "--operacion",
        type=str,
        default="RECEPCION",
        choices=["RECEPCION", "DESPACHO"],
        help="Tipo de operación",
    )
    parser.add_argument("--declarado", type=float, help="Peso declarado en guía (kg)")

    args = parser.parse_args()
    calcular(
        args.pe_camion,
        args.ps_camion,
        args.pe_remolque,
        args.ps_remolque,
        args.operacion,
        args.declarado,
    )


if __name__ == "__main__":
    main()
