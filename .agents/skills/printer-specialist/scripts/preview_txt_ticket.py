#!/usr/bin/env python3
"""Generador de vista previa de ticket TXT (matricial) desde la base de datos local.

Uso:
    python preview_txt_ticket.py --numero-boleto TA-00000001
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys

# Ajustar sys.path para importar app
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../../backend")))

try:
    from sqlalchemy import select
    from app.core.database import AsyncSessionLocal
    from app.models import BoletoPesaje, Empresa
    from app.services.ticket_service import generar_ticket_txt
except ImportError as exc:
    print(f"Error importando dependencias del backend: {exc}")
    sys.exit(1)


async def obtener_y_mostrar_ticket(num_boleto: str):
    async with AsyncSessionLocal() as db:
        stmt = select(BoletoPesaje).where(BoletoPesaje.numero_boleto == num_boleto)
        res = await db.execute(stmt)
        boleto = res.scalar_one_or_none()
        if not boleto:
            print(f"[-] Boleto '{num_boleto}' no encontrado en la base de datos local.")
            return

        stmt_emp = select(Empresa).where(Empresa.id_empresa == boleto.id_empresa)
        res_emp = await db.execute(stmt_emp)
        empresa = res_emp.scalar_one_or_none()

        txt = await generar_ticket_txt(boleto, empresa, db)
        print("\n" + "=" * 80)
        print(f" VISTA PREVIA TXT MATRICIAL — BOLETO: {num_boleto}")
        print("=" * 80)
        print(txt)
        print("=" * 80 + "\n")


def main():
    parser = argparse.ArgumentParser(description="Previsualizar ticket TXT matricial")
    parser.add_argument("--numero-boleto", type=str, required=True, help="Número de boleto (ej: TA-00000001)")
    args = parser.parse_args()

    asyncio.run(obtener_y_mostrar_ticket(args.numero_boleto))


if __name__ == "__main__":
    main()
