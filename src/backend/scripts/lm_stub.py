#!/usr/bin/env python3
"""Stub del License Manager (BALANSOFT-SGLB) para pruebas E2E y CI (H2).

Implementa el contrato que consume ``app/core/license_client.py``:

* ``POST /token``            -> ``{"token": "stub-<LICENSE_KEY>"}``
* ``POST /validate``         -> respuesta **firmada con Ed25519** sobre los 9
  ``SIGNED_FIELDS`` (``valid``, ``status``, ``expires_at``, ``tier``,
  ``plan_type``, ``features``, ``server_time``, ``nonce``, ``validada_en``),
  más ``signature_algorithm="ed25519"``, ``signature_version=1`` y ``signature``
  en base64 (firma sobre el JSON canónico, tal como espera el cliente real).
* ``POST /activate``         -> ``{"ok": true, "status": "ACTIVE"}``
* ``GET  /{license_key}/check`` -> resumen de la licencia
* ``GET  /health``           -> ``{"status": "ok", "mode": ...}``
* ``POST /__mode/{modo}``    -> cambia el modo en caliente (solo pruebas)

Modos (``LM_STUB_MODE`` o endpoint ``/__mode``):

==========  ==========================================================
``valid``   licencia activa, tier configurable (``LM_STUB_TIER``)
``invalid`` ``valid=false`` con estado SUSPENDIDA
``expired`` ``valid=false`` con estado EXPIRED y ``expires_at`` pasado
``unreachable`` el LM "cae": ``/token`` y ``/validate`` responden 503
``tamper``  firma un payload y luego altera un campo (firma inválida)
==========  ==========================================================

La clave Ed25519 se toma de ``LM_STUB_PRIVATE_KEY_PATH`` (o
``LICENSE_PRIVATE_KEY_PATH``); si no existe se genera en memoria y se escribe
la pública en ``LM_STUB_PUBLIC_KEY_PATH`` para que las pruebas apunten
``settings.license_public_key`` a ella. Nunca se commitean claves.

Uso manual:

    python scripts/lm_stub.py --port 9100
    LM_STUB_MODE=expired python scripts/lm_stub.py
"""

from __future__ import annotations

import argparse
import base64
import os
import sys
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from fastapi import Body, FastAPI, Header, HTTPException

# Reutiliza el canonicalizado y la lista de campos firmados del cliente real
# (si el paquete `app` está disponible) para que la firma coincida siempre.
try:  # pragma: no cover - depende del entorno de ejecución
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from app.core.license_client import SIGNED_FIELDS, canonical_json
except Exception:  # pragma: no cover - fallback standalone
    SIGNED_FIELDS = [
        "valid", "status", "expires_at", "tier", "plan_type",
        "features", "server_time", "nonce", "validada_en",
    ]

    def canonical_json(payload: dict[str, Any]) -> bytes:  # type: ignore[misc]
        import json

        return json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")


MODOS = ("valid", "invalid", "expired", "unreachable", "tamper")
_NOMBRES_CLAVE_PRIVADA = ("key_privada.pem", "private.pem", "clave_privada.pem")
_NOMBRES_CLAVE_PUBLICA = ("key_publica.pem", "public.pem", "clave_publica.pem")


class EstadoStub:
    """Estado mutable del stub (modo, tier, clave firmante)."""

    def __init__(self) -> None:
        self.modo = os.environ.get("LM_STUB_MODE", "valid")
        if self.modo not in MODOS:
            raise SystemExit(f"LM_STUB_MODE inválido: {self.modo} (use {MODOS})")
        self.tier = os.environ.get("LM_STUB_TIER", "ENTERPRISE")
        self.plan_type = os.environ.get("LM_STUB_PLAN_TYPE", "ANNUAL")
        self.ruta_publica: Path | None = None
        self.clave = self._cargar_clave()

    def _ruta_privada(self) -> Path | None:
        for var in ("LM_STUB_PRIVATE_KEY_PATH", "LICENSE_PRIVATE_KEY_PATH"):
            valor = os.environ.get(var)
            if not valor:
                continue
            ruta = Path(valor)
            if ruta.is_file():
                return ruta
            for nombre in _NOMBRES_CLAVE_PRIVADA:
                if (ruta / nombre).is_file():
                    return ruta / nombre
        return None

    def _cargar_clave(self) -> Ed25519PrivateKey:
        ruta = self._ruta_privada()
        if ruta is not None:
            pem = ruta.read_bytes()
            clave = serialization.load_pem_private_key(pem, password=None)
            assert isinstance(clave, Ed25519PrivateKey)
            self.ruta_publica = ruta.with_name(
                _NOMBRES_CLAVE_PUBLICA[_NOMBRES_CLAVE_PRIVADA.index(ruta.name)]
                if ruta.name in _NOMBRES_CLAVE_PRIVADA
                else "key_publica.pem"
            )
            return clave
        # Sin clave configurada: par efímero en memoria (solo para CI/dev).
        clave = Ed25519PrivateKey.generate()
        self.ruta_publica = None
        return clave

    def llave_publica_pem(self) -> str:
        return self.clave.public_key().public_bytes(
            serialization.Encoding.PEM,
            serialization.PublicFormat.SubjectPublicKeyInfo,
        ).decode("utf-8")

    def escribir_clave_publica(self, destino: str | Path | None) -> str:
        pem = self.llave_publica_pem()
        if destino:
            ruta = Path(destino)
            ruta.parent.mkdir(parents=True, exist_ok=True)
            ruta.write_text(pem, encoding="utf-8")
            return str(ruta)
        if self.ruta_publica is not None:
            self.ruta_publica.write_text(pem, encoding="utf-8")
            return str(self.ruta_publica)
        return pem


estado = EstadoStub()

app = FastAPI(
    title="LM Stub (Balansoft-SGLB)",
    version="1.0.0-stub",
    summary="License Manager de pruebas que firma con Ed25519 (H2).",
)


@app.get("/health")
async def health() -> dict[str, Any]:
    return {"status": "ok", "mode": estado.modo, "tier": estado.tier}


@app.post("/__mode/{modo}")
async def set_modo(modo: str) -> dict[str, Any]:
    if modo not in MODOS:
        raise HTTPException(status_code=400, detail=f"Modo inválido: {modo}")
    estado.modo = modo
    return {"status": "ok", "mode": estado.modo}


def _firmar(payload: dict[str, Any]) -> str:
    firma = estado.clave.sign(canonical_json(payload))
    return base64.b64encode(firma).decode("ascii")


def _respuesta(modo: str, license_key: str, product_code: str | None) -> dict[str, Any]:
    ahora = datetime.now(UTC)
    payload: dict[str, Any] = {
        "valid": True,
        "status": "ACTIVE",
        "tier": estado.tier,
        "plan_type": estado.plan_type,
        "features": {"max_users": 10, "modules": "ALL", "reports": True},
        "expires_at": (ahora + timedelta(days=365)).isoformat(),
        "server_time": ahora.isoformat(),
        "validada_en": ahora.isoformat(),
        "nonce": uuid.uuid4().hex,
        "license_key": license_key,
        "product_code": product_code,
    }
    if modo == "invalid":
        payload.update(valid=False, status="SUSPENDIDA", message="Licencia suspendida")
    elif modo == "expired":
        payload.update(
            valid=False,
            status="EXPIRED",
            expires_at=(ahora - timedelta(days=30)).isoformat(),
            message="Licencia vencida",
        )

    firmado = {k: payload.get(k) for k in SIGNED_FIELDS}
    respuesta: dict[str, Any] = {
        **payload,
        "signature_algorithm": "ed25519",
        "signature_version": 1,
        "signature": _firmar(firmado),
    }
    if modo == "tamper":
        # Altera un campo firmado DESPUÉS de firmar: el cliente real debe
        # rechazar la respuesta por firma inválida.
        respuesta["tier"] = "ENTERPRISE-ALTERADO"
    return respuesta


def _rechazar_si_caido() -> None:
    """Simula el LM caído (503) para probar el camino offline-first."""
    if estado.modo == "unreachable":
        raise HTTPException(status_code=503, detail="LM no disponible")


@app.post("/token")
async def token(payload: dict[str, Any] = Body(...)) -> dict[str, Any]:
    _rechazar_si_caido()
    license_key = str(payload.get("license_key", "")).upper()
    if not license_key:
        raise HTTPException(status_code=400, detail="license_key requerido")
    return {"token": f"stub-{license_key}", "expires_in": 3600}


@app.post("/validate")
async def validate(
    payload: dict[str, Any] = Body(...),
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    _rechazar_si_caido()
    license_key = str(payload.get("license_key", "")).upper()
    if authorization != f"Bearer stub-{license_key}":
        raise HTTPException(status_code=401, detail="Token inválido")
    return _respuesta(estado.modo, license_key, payload.get("product_code"))


@app.post("/activate")
async def activate(
    payload: dict[str, Any] = Body(...),
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    _rechazar_si_caido()
    license_key = str(payload.get("license_key", "")).upper()
    if authorization != f"Bearer stub-{license_key}":
        # El cliente real lee detail.message cuando `detail` es un dict.
        raise HTTPException(status_code=400, detail={"message": "Token inválido"})
    return {"ok": True, "status": "ACTIVE", "hardware_id": payload.get("hardware_id")}


@app.get("/{license_key}/check")
async def check(license_key: str) -> dict[str, Any]:
    _rechazar_si_caido()
    modo = estado.modo
    return {
        "license_key": license_key.upper(),
        "valid": modo == "valid",
        "status": {"valid": "ACTIVE", "invalid": "SUSPENDIDA"}.get(modo, "EXPIRED"),
        "tier": estado.tier,
    }


def main() -> None:  # pragma: no cover - ejecución manual
    import uvicorn

    parser = argparse.ArgumentParser(description="Stub del License Manager (H2)")
    parser.add_argument("--host", default=os.environ.get("LM_STUB_HOST", "127.0.0.1"))
    parser.add_argument(
        "--port", type=int, default=int(os.environ.get("LM_STUB_PORT", "9100"))
    )
    parser.add_argument(
        "--write-public-key",
        default=os.environ.get("LM_STUB_PUBLIC_KEY_PATH"),
        help="Escribe la clave pública Ed25519 en esa ruta",
    )
    args = parser.parse_args()

    destino = estado.escribir_clave_publica(args.write_public_key)
    print(f"🔑 LM stub en http://{args.host}:{args.port} (modo={estado.modo})")
    print(f"   clave pública: {destino}")
    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")


if __name__ == "__main__":  # pragma: no cover
    main()