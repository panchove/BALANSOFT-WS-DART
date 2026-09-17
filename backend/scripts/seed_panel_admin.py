#!/usr/bin/env python3
"""Seed del usuario del panel administrativo del SERVIDOR (proveedores_usuarios).

El panel web (BALASOFT-UI) inicia sesión en ``POST /api/v1/panel/login`` contra
la API con ``APP_ROLE=server``. Este script crea o actualiza ese usuario en la
DB del servidor (balansoft_ws_server).

Uso:
    uv run python scripts/seed_panel_admin.py \
        --email admin@balansoft.local --password 'segura123' \
        --nombre Administrador --rol SUPERADMIN
"""

from __future__ import annotations

import argparse
import os
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)


def _server_url_sync() -> str:
    from app.core.config import settings

    src = os.environ.get("SERVER_DATABASE_URL") or settings.database_url
    url = src.replace("postgresql+asyncpg://", "postgresql+psycopg2://", 1)
    if not url.startswith(("postgresql://", "postgresql+psycopg2://")):
        raise SystemExit(f"URL del servidor no soportada para el seed: {src}")
    head, _, _ = url.rpartition("/")
    return f"{head}/balansoft_ws_server"


def main() -> None:
    from sqlalchemy import text

    from app.core.security import hash_password

    parser = argparse.ArgumentParser(description="Seed del panel administrativo del servidor")
    parser.add_argument("--email", required=True, help="Email del usuario del panel")
    parser.add_argument("--password", required=True, help="Contraseña (mín. 6 caracteres)")
    parser.add_argument("--nombre", default="Administrador Balansoft", help="Nombre completo")
    parser.add_argument("--rol", default="SUPERADMIN", choices=["SUPERADMIN", "SOPORTE", "VENTAS"],
                        help="Rol en el panel")
    args = parser.parse_args()

    if len(args.password) < 6:
        sys.exit("La contraseña debe tener al menos 6 caracteres.")

    url = _server_url_sync()
    print(f"Conectando al servidor: {url.rsplit('/', 1)[0]}/***")

    from sqlalchemy import create_engine

    engine = create_engine(url, pool_pre_ping=True)
    try:
        with engine.begin() as conn:
            conn.execute(
                text(
                    """
                    INSERT INTO proveedores_usuarios (email, password_hash, nombre, rol, activo)
                    VALUES (:email, :hash, :nombre, :rol, TRUE)
                    ON CONFLICT (email)
                    DO UPDATE SET password_hash = EXCLUDED.password_hash,
                                  nombre = EXCLUDED.nombre,
                                  rol = EXCLUDED.rol,
                                  activo = TRUE,
                                  updated_at = CURRENT_TIMESTAMP
                    """
                ),
                {
                    "email": args.email.lower(),
                    "hash": hash_password(args.password),
                    "nombre": args.nombre,
                    "rol": args.rol,
                },
            )
    except Exception as exc:  # noqa: BLE001
        sys.exit(f"Error al sembrar el usuario del panel: {exc}")

    print(f"Usuario del panel listo: {args.email.lower()} (rol {args.rol})")


if __name__ == "__main__":
    main()