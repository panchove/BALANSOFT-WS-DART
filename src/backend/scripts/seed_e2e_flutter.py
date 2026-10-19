#!/usr/bin/env python3
"""Seed determinista para el E2E de Flutter (`frontend/integration_test/`).

Deja la BD lista para que la app entre directo al login y complete un pesaje:

- empresa + usuario ADMIN con credenciales fijas;
- catálogos mínimos (camión, conductor, transporte, producto, almacén, tercero);
- **sin básculas**: el formulario calcula `_esPesoManual = !hayBascula`, así que
  sin báscula los campos de peso son editables (una báscula en el catálogo
  vuelve el peso `readOnly` y el E2E no podría capturar nada);
- licencia activa apuntando al stub firmante del LM (`LICENSE_API_URL`), con
  `licencia_tier=CENTRAL` para que la UI no muestre límites de DEMO.

No crea la cuenta en el servidor central: es solo la estación local (rol local).

Uso (respeta `DATABASE_URL` del entorno o de `backend/.env`):
    uv run python scripts/seed_e2e_flutter.py
    EMAIL_E2E=otro@demo.test PASSWORD_E2E=clave123 uv run python scripts/seed_e2e_flutter.py
"""

from __future__ import annotations

import asyncio
import os
from decimal import Decimal

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.core.security import hash_password
from app.models import (
    Almacen,
    Camion,
    Categoria,
    Conductor,
    Empresa,
    Producto,
    Tercero,
    Transporte,
    Usuario,
)

EMAIL = os.environ.get("EMAIL_E2E", "admin@balansoft.demo")
PASSWORD = os.environ.get("PASSWORD_E2E", "demo1234")
LICENCIA = os.environ.get("LICENCIA_E2E", "BWS-TEST-TEST-TEST-TEST")
RIF = "J-99999999-9"
EMPRESA = "Empresa E2E Flutter"


async def main() -> None:
    async with AsyncSessionLocal() as db:
        empresa = (
            await db.execute(select(Empresa).where(Empresa.rif_nit == RIF))
        ).scalar_one_or_none()
        if empresa is None:
            empresa = Empresa(nombre_fiscal=EMPRESA, nombre_comercial=EMPRESA, rif_nit=RIF)
            db.add(empresa)
            await db.flush()
            print(f"→ Empresa creada: {empresa.id_empresa}")
        else:
            print(f"ℹ️  Empresa ya existía: {empresa.id_empresa}")

        empresa.licencia_key = LICENCIA
        empresa.licencia_tier = "CENTRAL"
        empresa.licencia_status = "ACTIVE"
        empresa.activa = True

        usuario = (
            await db.execute(select(Usuario).where(Usuario.email == EMAIL))
        ).scalar_one_or_none()
        if usuario is None:
            db.add(
                Usuario(
                    id_empresa=empresa.id_empresa,
                    nombre="Administrador E2E",
                    email=EMAIL,
                    password_hash=hash_password(PASSWORD),
                    rol="ADMIN",
                    activo=True,
                )
            )
            print(f"→ Usuario ADMIN creado: {EMAIL}")
        else:
            usuario.id_empresa = empresa.id_empresa
            usuario.password_hash = hash_password(PASSWORD)
            usuario.rol = "ADMIN"
            usuario.activo = True
            print(f"ℹ️  Usuario actualizado: {EMAIL}")

        # ── Catálogos mínimos (sin Balanza a propósito) ────────────────────
        ya_tiene = (
            await db.execute(
                select(Camion).where(Camion.id_empresa == empresa.id_empresa).limit(1)
            )
        ).scalar_one_or_none()
        if ya_tiene is None:
            categoria = Categoria(
                id_empresa=empresa.id_empresa,
                codigo="CAT-E2E",
                nombre="Cementos E2E",
            )
            db.add(categoria)
            await db.flush()
            db.add_all(
                [
                    Camion(
                        placa="E2E123",
                        id_empresa=empresa.id_empresa,
                        color="Blanco",
                        tara_habitual=Decimal("3200.00"),
                    ),
                    Conductor(
                        cedula_dni="V-11111111",
                        id_empresa=empresa.id_empresa,
                        nombre_completo="Conductor E2E",
                    ),
                    Transporte(
                        id_empresa=empresa.id_empresa,
                        razon_social="Transporte E2E",
                        codigo="T-E2E",
                    ),
                    Producto(
                        id_empresa=empresa.id_empresa,
                        nombre="Cemento E2E",
                        descripcion="Cemento para la prueba E2E",
                        codigo="CEM-E2E",
                        densidad_estandar="3.15",
                        id_categoria=categoria.id_categoria,
                    ),
                    Almacen(
                        id_empresa=empresa.id_empresa,
                        nombre="Almacén E2E",
                        codigo="A-E2E",
                    ),
                    Tercero(
                        id_empresa=empresa.id_empresa,
                        tipo="CLIENTE",
                        codigo="C-E2E",
                        razon_social="Cliente E2E",
                    ),
                ]
            )
            print("→ Catálogos creados (sin báscula: el peso queda editable).")
        else:
            print("ℹ️  Catálogos ya poblados.")

        await db.commit()

    print("✅ Seed E2E listo.")
    print(f"   Login    : {EMAIL} / {PASSWORD}")
    print(f"   Licencia : {LICENCIA} (el LM debe ser scripts/lm_stub.py)")


if __name__ == "__main__":
    asyncio.run(main())