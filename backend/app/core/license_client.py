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
import re
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import httpx
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

from app.core.config import settings

log = logging.getLogger(__name__)

SIGNED_FIELDS = ["valid", "status", "expires_at", "tier", "plan_type",
                 "features", "server_time", "nonce", "validada_en"]

# Ventana de frescura del `server_time` (mismo contrato que BALANSOFT-SG,
# docs/USO-API.md §6): -5 min .. +24 h. El LM usa `validada_en` como ancla de
# tiempo del servidor para decisiones de vigencia.
_MAX_CLOCK_SKEW = timedelta(minutes=5)   # servidor demasiado adelantado
_MAX_FUTURE_ALLOWED = timedelta(hours=24)  # ventana de frescura del server_time

# Formato de clave: `{B+prefijo}-XXXX-XXXX-XXXX-XXXX` (marca B + iniciales del
# producto 2-10 letras, ej. BWS-…). Mismo regex que BALANSOFT-SG.
LICENSE_KEY_RE = re.compile(
    r"^[A-Z0-9]{2,11}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"
)

# Anti-replay: nonces ya vistos en memoria (se reinician al arrancar el proceso).
# Igual patrón que BALANSOFT-SG. Al correr con varios workers, la protección es
# por proceso.
_nonces_vistos: set[str] = set()


def _now_naive() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


MAC_PATTERN = re.compile(r"^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$")


def _sanitize_mac(value: str | None) -> str | None:
    """Normaliza una MAC a 00:1A:2B:3C:4D:5E; None si no tiene ese formato
    (evita rechazos 422 del LM por `mac_address` con max_length=17)."""
    if not value:
        return None
    mac = value.strip().upper()
    return mac if MAC_PATTERN.match(mac) else None


def _sanitize_text(value: str | None, max_length: int) -> str | None:
    if not value:
        return None
    value = value.strip()
    return value if len(value) <= max_length else value[:max_length]


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


def canonical_json(payload: dict[str, Any]) -> bytes:
    """Serialización canónica de la firma (USO-API.md §6): claves ordenadas,
    separadores compactos, sin espacios. Idéntica a BALANSOFT-SG / LM para que
    la firma Ed25519 coincida."""
    return json.dumps(
        payload, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


_canonical_json = canonical_json


def validate_license_key_format(key: str) -> str:
    """Normaliza y valida el formato de la clave (no la valida en el LM).

    Portado desde BALANSOFT-SG: mayúsculas y patrón ``{B+PREFIJO}-XXXX-XXXX-XXXX-XXXX``.
    """
    normalized = key.strip().upper()
    if not LICENSE_KEY_RE.match(normalized):
        raise LicenseError(
            "Formato de clave de licencia inválido (esperado BWS-XXXX-XXXX-XXXX-XXXX)"
        )
    return normalized


def _verify_signature(payload: dict[str, Any], signature: str, public_key_pem: str) -> bool:
    try:
        key_bytes = (
            public_key_pem.encode("utf-8")
            if isinstance(public_key_pem, str)
            else public_key_pem
        )
        public_key = serialization.load_pem_public_key(key_bytes)
        if not isinstance(public_key, Ed25519PublicKey):
            return False
        raw = base64.b64decode(signature)
        public_key.verify(raw, canonical_json(payload))
        return True
    except Exception:
        return False


def check_signature_metadata(response: dict[str, Any]) -> None:
    """Exige que la respuesta declare algoritmo y versión de firma esperados.

    Portado desde BALANSOFT-SG: `signature_algorithm=ed25519`,
    `signature_version=1`.
    """
    if (
        response.get("signature_algorithm") != "ed25519"
        or response.get("signature_version") != 1
    ):
        raise LicenseSignatureError(
            "Respuesta de validación no firmada correctamente (algoritmo/versión)"
        )


def check_freshness(server_time: str, now: datetime | None = None) -> None:
    """Rechaza respuestas demasiado viejas o del futuro (-5 min .. +24 h, §6).

    Portado desde BALANSOFT-SG: la ventana es ASIMÉTRICA (el LM puede estar
    hasta 5 min adelantado o 24 h atrasado respecto de `server_time`).
    """
    if not server_time:
        raise LicenseSignatureError("server_time ausente en la respuesta")
    try:
        ts = datetime.fromisoformat(server_time)
    except ValueError:
        raise LicenseSignatureError("server_time inválido en la respuesta") from None
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=UTC)
    ahora = now if now is not None else datetime.now(UTC)
    if ahora.tzinfo is None:
        ahora = ahora.replace(tzinfo=UTC)
    if ts < ahora - _MAX_CLOCK_SKEW or ts > ahora + _MAX_FUTURE_ALLOWED:
        raise LicenseSignatureError(
            "Respuesta de validación fuera de la ventana de tiempo"
        )


def check_nonce(nonce: str) -> None:
    """Anti-replay: un `nonce` ya visto invalida la respuesta (en memoria)."""
    if not nonce:
        raise LicenseSignatureError("Respuesta de validación sin nonce")
    if nonce in _nonces_vistos:
        raise LicenseSignatureError(
            "Respuesta de validación repetida (nonce ya usado)"
        )
    _nonces_vistos.add(nonce)


def validar_respuesta_firmada(
    response: dict[str, Any],
    public_key_pem: str | bytes | None,
) -> None:
    """Valida una respuesta de /validate: metadatos + firma + frescura + anti-replay.

    Portado desde BALANSOFT-SG (`licencia_ml.py`): cubre exactamente
    `SIGNED_FIELDS` (los 9 campos, incluido `validada_en`).
    """
    check_signature_metadata(response)
    if public_key_pem is None:
        raise LicenseSignatureError("No hay clave pública del LM configurada")
    signature = response.get("signature")
    if not signature:
        raise LicenseSignatureError("Respuesta de validación sin firma")
    signed_payload = {k: response.get(k) for k in SIGNED_FIELDS}
    if not _verify_signature(signed_payload, signature, public_key_pem):
        raise LicenseSignatureError("Firma Ed25519 de /validate inválida")
    check_freshness(response.get("server_time", ""))
    check_nonce(response.get("nonce", ""))


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
        license_key = validate_license_key_format(license_key)
        token = self._get_token(license_key)
        payload = {
            "license_key": license_key,
            "hardware_id": hardware_id,
            "mac_address": _sanitize_mac(mac_address),
            "device_brand": _sanitize_text(device_brand, 64),
            "device_model": _sanitize_text(device_model, 64),
            "os_version": _sanitize_text(os_version, 64),
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

        # Verificación de la respuesta firmada Ed25519 (anti-fake-server).
        # Mismo contrato que BALANSOFT-SG: metadatos + firma de los 9 campos
        # (incluido `validada_en`) + frescura asimétrica + anti-replay por nonce.
        validar_respuesta_firmada(data, self.public_key)

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
            "mac_address": _sanitize_mac(mac_address),
            "device_brand": _sanitize_text(device_brand, 64),
            "device_model": _sanitize_text(device_model, 64),
            "os_version": _sanitize_text(os_version, 64),
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
