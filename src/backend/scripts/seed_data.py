#!/usr/bin/env python3
"""Seed de datos de desarrollo para Balansoft-WS.

Crea una empresa demo, su usuario admin y catálogos básicos en la BD de negocio
(balansoft_ws). No crea licencias en el LM.

Uso:  uv run python scripts/seed_data.py
"""

from __future__ import annotations

import asyncio

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.core.security import hash_password
from app.models import (
    Almacen,
    Balanza,
    Camion,
    Categoria,
    Conductor,
    Empresa,
    Producto,
    Remolque,
    Tercero,
    Transporte,
    Usuario,
)

DEMO = {
    "empresa_nombre": "Empresa Demo Balansoft",
    "empresa_rif": "J-12345678-0",
    "usuario_email": "admin@balansoft.demo",
    "usuario_nombre": "Administrador Demo",
    "password": "demo1234",
}


async def _existe(db, empresa_id) -> bool:
    result = await db.execute(
        select(Camion).where(Camion.id_empresa == empresa_id)
    )
    return result.scalar_one_or_none() is not None


async def main() -> None:
    async with AsyncSessionLocal() as db:
        # Empresa
        existing = (
            await db.execute(
                select(Empresa).where(Empresa.rif_nit == DEMO["empresa_rif"])
            )
        ).scalar_one_or_none()
        if existing is None:
            empresa = Empresa(
                nombre_fiscal=DEMO["empresa_nombre"],
                nombre_comercial=DEMO["empresa_nombre"],
                rif_nit=DEMO["empresa_rif"],
                licencia_status="SIN_LICENCIA",
            )
            db.add(empresa)
            await db.flush()
        else:
            empresa = existing
            print("ℹ️  Ya existe la empresa demo. Reutilizando.")
            if await _existe(db, empresa.id_empresa):
                print("✅ Catálogos ya poblados. Nada que hacer.")
                return

        # Usuario admin
        usuario = (
            await db.execute(
                select(Usuario).where(Usuario.email == DEMO["usuario_email"])
            )
        ).scalar_one_or_none()
        if usuario is None:
            db.add(
                Usuario(
                    id_empresa=empresa.id_empresa,
                    nombre=DEMO["usuario_nombre"],
                    email=DEMO["usuario_email"],
                    password_hash=hash_password(DEMO["password"]),
                    rol="ADMIN",
                )
            )

        # Catálogos demo (si no existen)
        if not await _existe(db, empresa.id_empresa):
            _cat_cemento = Categoria(
                id_empresa=empresa.id_empresa,
                codigo="CAT-CEM",
                nombre="Cemento y agregados",
            )
            db.add(_cat_cemento)
            await db.flush()

            db.add_all(
                [
                    Camion(
                        placa="ABC123",
                        id_empresa=empresa.id_empresa,
                        color="Blanco",
                        tara_habitual="3200.00",
                    ),
                    Camion(
                        placa="XYZ789",
                        id_empresa=empresa.id_empresa,
                        color="Rojo",
                        tara_habitual="3500.00",
                    ),
                    Conductor(
                        cedula_dni="V-12345678", id_empresa=empresa.id_empresa,
                        nombre_completo="Juan Pérez",
                    ),
                    Conductor(
                        cedula_dni="V-87654321", id_empresa=empresa.id_empresa,
                        nombre_completo="María López",
                    ),
                    Transporte(
                        id_empresa=empresa.id_empresa,
                        razon_social="Transporte Los Andes",
                        codigo="T001",
                    ),
                    Producto(
                        id_empresa=empresa.id_empresa,
                        nombre="Cemento", descripcion="Cemento gris tipo I",
                        codigo="CEM", densidad_estandar="3.15",
                        id_categoria=_cat_cemento.id_categoria,
                    ),
                    Producto(
                        id_empresa=empresa.id_empresa,
                        nombre="Arena", descripcion="Arena lavada",
                        codigo="ARN", densidad_estandar="1.60",
                        id_categoria=_cat_cemento.id_categoria,
                    ),
                    Almacen(
                        id_empresa=empresa.id_empresa, nombre="Planta Principal",
                        codigo="A1",
                    ),
                    Balanza(
                        id_empresa=empresa.id_empresa, descripcion="Balanza 1",
                        codigo="BALANZA1", marca="Digi", capacidad_max="80000.00",
                    ),
                    Tercero(
                        id_empresa=empresa.id_empresa, tipo="CLIENTE",
                        codigo="C001", razon_social="Constructora Demo",
                    ),
                    Remolque(
                        id_empresa=empresa.id_empresa, placa="R-ABC123",
                        tipo_remolque="PLATAFORMA", tara_habitual="7500.00",
                    ),
                ]
            )

        await db.commit()

    print("✅ Seed completado.")
    print(f"   Empresa : {DEMO['empresa_nombre']} ({DEMO['empresa_rif']})")
    print(f"   Usuario : {DEMO['usuario_email']} / {DEMO['password']}")
    print("   Nota: asigna licencia_key a la empresa para la integración con el LM.")


if __name__ == "__main__":
    asyncio.run(main())
