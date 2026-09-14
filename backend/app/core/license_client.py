"""Cliente de integración con el License Manager (SGLB) local.

Flujo de validación (anti-fake-server):
1. POST /token      -> obtiene Bearer token (Ed25519 firmado) para la licencia.
2. ValidateRequest  -> envía hardware + product_code con el Bearer.
3. POST /validate   -> respuesta firmada Ed25519; se verifica firma + server_time.

La clave pública del LM se embebe aquí (settings.license_public_key) y la
respuesta de /validate se verifica antes de confiar en el resultado.
"""

from __future__ import annotations

import base64
import json
import logging
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import httpx
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

from app.core.config import settings

log = logging.getLogger(__name__)

SIGNED_FIELDS = ["valid", "status", "expires_at", "tier", "plan_type",
                 "features", "server_time", "nonce"]


def _now_naive() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


class LicenseError(Exception):
    """Error de validación/activación de licencia."""


class LicenseSignatureError(LicenseError):
    """La firma de /validate no coincide con la clave pública del LM."""


@dataclass
class LicenseInfo:
    valid: bool
    status: str | None = None
    tier: str | None = None
    plan_type: str | None = None
    expires_at: datetime | None = None
    features: dict[str, Any] = field(default_factory=dict)
    message: str | None = None
    raw: dict[str, Any] = field(default_factory=dict)

    @property
    def is_demo(self) -> bool:
        return (self.tier or "").upper() == "DEMO"


def _canonical_json(payload: dict[str, Any]) -> bytes:
    return json.dumps(
        payload, sort_keys=True, separators=(",", ":"), default=str
    ).encode("utf-8")


def _verify_signature(payload: dict[str, Any], signature: str, public_key_pem: str) -> bool:
    try:
        public_key = serialization.load_pem_public_key(public_key_pem.encode("utf-8"))
        if not isinstance(public_key, Ed25519PublicKey):
            return False
        raw = base64.b64decode(signature)
        public_key.verify(raw, _canonical_json(payload))
        return True
    except Exception:
        return False


class LicenseClient:
    """Cliente síncrono del LM. Se usa dentro de dependencias async vía run_in_executor."""

    def __init__(self) -> None:
        self.base_url = settings.license_api_url.rstrip("/")
        self.public_key = settings.license_public_key or self._public_key_from_file()
        self.timeout = httpx.Timeout(10.0)

    def _public_key_from_file(self) -> str:
        """Lee la clave pública del LM desde LICENSE_PUBLIC_KEY_PATH (recomendado)."""
        path = settings.license_public_key_path
        if not path:
            return ""
        try:
            return Path(path).read_text(encoding="utf-8").strip()
        except OSError as e:
            log.warning("No se pudo leer LICENSE_PUBLIC_KEY_PATH=%s: %s", path, e)
            return ""

    def _get_token(self, license_key: str) -> str:
        try:
            resp = httpx.post(
                f"{self.base_url}/token",
                json={"license_key": license_key},
                timeout=self.timeout,
            )
        except httpx.HTTPError as e:
            raise LicenseError(f"Error de red con el LM: {e}") from e
        if resp.status_code != 200:
            raise LicenseError(f"Token LM rechazado ({resp.status_code}): {resp.text}")
        return resp.json()["token"]

    def validate(
        self,
        license_key: str,
        hardware_id: str,
        *,
        mac_address: str | None = None,
        device_brand: str | None = None,
        device_model: str | None = None,
        os_version: str | None = None,
        product_code: str | None = None,
    ) -> LicenseInfo:
        token = self._get_token(license_key)
        payload = {
            "license_key": license_key,
            "hardware_id": hardware_id,
            "mac_address": mac_address,
            "device_brand": device_brand,
            "device_model": device_model,
            "os_version": os_version,
            "product_code": product_code or settings.license_product_code,
        }
        try:
            resp = httpx.post(
                f"{self.base_url}/validate",
                json=payload,
                headers={"Authorization": f"Bearer {token}"},
                timeout=self.timeout,
            )
        except httpx.HTTPError as e:
            # Sin conexión -> no podemos confiar en la validez
            raise LicenseError(f"Error de red al validar con el LM: {e}") from e

        if resp.status_code == 401:
            raise LicenseError("Token LM inválido o expirado")
        if resp.status_code != 200:
            raise LicenseError(f"Validación LM fallida ({resp.status_code}): {resp.text}")

        data = resp.json()

        # Verificación de firma Ed25519 (anti-fake-server)
        signature = data.get("signature")
        signed_payload = {k: data.get(k) for k in SIGNED_FIELDS}
        if not self.public_key or not signature:
            raise LicenseSignatureError("LM no devolvió firma o no hay clave pública")
        if not _verify_signature(signed_payload, signature, self.public_key):
            raise LicenseSignatureError("Firma Ed25519 de /validate inválida")

        # Anti-replay: server_time no debe estar adelantado / desfasado > 5 min
        server_time_raw = data.get("server_time")
        if server_time_raw:
            try:
                server_time = datetime.fromisoformat(server_time_raw)
                drift = abs((_now_naive() - server_time).total_seconds())
                if drift > 300:
                    raise LicenseSignatureError("Respuesta del LM fuera de rango temporal")
            except ValueError:
                pass

        expires = data.get("expires_at")
        return LicenseInfo(
            valid=bool(data.get("valid")),
            status=data.get("status"),
            tier=data.get("tier"),
            plan_type=data.get("plan_type"),
            expires_at=datetime.fromisoformat(expires) if expires else None,
            features=data.get("features") or {},
            message=data.get("message"),
            raw=data,
        )

    def activate(
        self,
        license_key: str,
        hardware_id: str,
        *,
        mac_address: str | None = None,
        device_brand: str | None = None,
        device_model: str | None = None,
        os_version: str | None = None,
    ) -> dict[str, Any]:
        token = self._get_token(license_key)
        payload = {
            "license_key": license_key,
            "hardware_id": hardware_id,
            "mac_address": mac_address,
            "device_brand": device_brand,
            "device_model": device_model,
            "os_version": os_version,
        }
        resp = httpx.post(
            f"{self.base_url}/activate",
            json=payload,
            headers={"Authorization": f"Bearer {token}"},
            timeout=self.timeout,
        )
        if resp.status_code != 200:
            body = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {}
            detail = (body or {}).get("detail") or {}
            if isinstance(detail, dict):
                raise LicenseError(detail.get("message") or resp.text)
            raise LicenseError(resp.text)
        return resp.json()

    def check(self, license_key: str) -> dict[str, Any]:
        resp = httpx.get(
            f"{self.base_url}/{license_key}/check",
            timeout=self.timeout,
        )
        if resp.status_code != 200:
            raise LicenseError(f"Check LM fallido ({resp.status_code})")
        return resp.json()


@dataclass
class LicenseCache:
    info: LicenseInfo
    cached_at: datetime = field(default_factory=_now_naive)


_license_client: LicenseClient | None = None


def get_license_client() -> LicenseClient:
    global _license_client
    if _license_client is None:
        _license_client = LicenseClient()
    return _license_client
