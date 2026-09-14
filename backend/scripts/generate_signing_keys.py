#!/usr/bin/env python3
"""Genera un par de claves Ed25519 para la firma de respuestas.

Uso:  uv run python scripts/generate_signing_keys.py [output_dir]
Por defecto escribe en ./keys/ (clave_privada.pem, clave_publica.pem).

NOTA: para integrarse con el LM local, el backend de Balansoft-WS usa la
clave PÚBLICA del LM (LICENSE_PUBLIC_KEY en .env) para verificar las firmas
de /validate. Este script sirve si se desea un par propio para otros usos.
"""

from __future__ import annotations

import sys
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def main() -> None:
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("keys")
    out_dir.mkdir(parents=True, exist_ok=True)

    private_key = Ed25519PrivateKey.generate()
    public_key = private_key.public_key()

    private_pem = private_key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    public_pem = public_key.public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )

    (out_dir / "key_privada.pem").write_bytes(private_pem)
    (out_dir / "key_publica.pem").write_bytes(public_pem)

    print(f"✅ Claves generadas en {out_dir.resolve()}")
    print("   - key_privada.pem")
    print("   - key_publica.pem")


if __name__ == "__main__":
    main()
