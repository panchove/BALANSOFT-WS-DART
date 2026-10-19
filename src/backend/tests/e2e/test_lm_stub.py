"""E2E del contrato de licencia firmado: stub LM + `LicenseClient` real (H2)."""

from __future__ import annotations

import base64
from datetime import UTC, datetime, timedelta
from typing import Any, cast

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

from app.core.license_client import (
    SIGNED_FIELDS,
    LicenseClient,
    LicenseError,
    LicenseSignatureError,
    canonical_json,
)
from tests.e2e.conftest import LICENCIA_TEST

pytestmark = pytest.mark.e2e


def _token(cliente: LicenseClient, key: str = LICENCIA_TEST) -> str:
    resp = cliente._get_token(key)  # noqa: SLF001 - cliente bajo prueba
    return resp


class TestValidateContraStub:
    async def test_licencia_valida_firmada(self, lm_client: LicenseClient):
        info = lm_client.validate_or_activate(LICENCIA_TEST, "HW-E2E-001")
        assert info.valid is True
        assert info.status == "ACTIVE"
        assert info.tier
        assert info.expires_at and info.expires_at > datetime.now(UTC)

    async def test_validate_acepta_firma_del_stub(self, lm_client: LicenseClient):
        """El cliente verifica la firma del stub sin 'relajar' la verificación."""
        assert lm_client.public_key, "la clave pública debe estar inyectada"
        info = lm_client.validate(LICENCIA_TEST, "HW-E2E-002")
        assert info.valid is True
        assert info.raw["signature_algorithm"] == "ed25519"
        assert info.raw["signature_version"] == 1
        assert set(SIGNED_FIELDS) <= set(info.raw)

    async def test_licencia_suspendida(self, lm_client: LicenseClient, lm_modo):
        lm_modo("invalid")
        info = lm_client.validate(LICENCIA_TEST, "HW-E2E-003")
        assert info.valid is False
        assert info.status == "SUSPENDIDA"

    async def test_licencia_vencida(self, lm_client: LicenseClient, lm_modo):
        lm_modo("expired")
        info = lm_client.validate(LICENCIA_TEST, "HW-E2E-004")
        assert info.valid is False
        assert info.status == "EXPIRED"
        assert info.expires_at and info.expires_at < datetime.now(UTC)

    async def test_stub_rechaza_bearer_incorrecto(self, lm_stub: str):
        """Contrato: /validate con Bearer que no corresponde a la clave -> 401.

        Es la respuesta que el cliente real traduce a `LicenseError("Token LM
        inválido o expirado")` (license_client.py:303).
        """
        import httpx  # noqa: PLC0415

        resp = httpx.post(
            f"{lm_stub}/validate",
            json={"license_key": LICENCIA_TEST, "hardware_id": "HW-E2E-005"},
            headers={"Authorization": "Bearer stub-OTRA-CLAVE"},
            timeout=5.0,
        )
        assert resp.status_code == 401
        assert resp.json()["detail"] == "Token inválido"

    async def test_token_para_clave_desconocida_es_license_error(
        self, lm_client: LicenseClient
    ):
        """Formato de clave inválido -> LicenseError antes de llamar al LM."""
        with pytest.raises(LicenseError, match="Formato de clave"):
            lm_client.validate("clave-invalida", "HW-E2E-005")

    async def test_lm_caido_es_license_error(self, lm_client: LicenseClient, lm_modo):
        lm_modo("unreachable")
        with pytest.raises(LicenseError):
            lm_client.validate_or_activate(LICENCIA_TEST, "HW-E2E-006")

    async def test_firma_manipulada_es_rechazada(
        self, lm_client: LicenseClient, lm_modo
    ):
        lm_modo("tamper")
        with pytest.raises(LicenseSignatureError, match="Firma Ed25519"):
            lm_client.validate(LICENCIA_TEST, "HW-E2E-007")

    async def test_nonce_repetido_es_rechazado(
        self, lm_client: LicenseClient, lm_stub: str
    ):
        """Anti-replay: la misma respuesta firmada no se puede reusar."""
        import httpx  # noqa: PLC0415

        token = _token(lm_client)
        payload = {
            "license_key": LICENCIA_TEST,
            "hardware_id": "HW-E2E-008",
            "product_code": "WS",
        }
        resp = httpx.post(
            f"{lm_stub}/validate",
            json=payload,
            headers={"Authorization": f"Bearer {token}"},
            timeout=5.0,
        )
        assert resp.status_code == 200
        data = resp.json()
        from app.core.license_client import validar_respuesta_firmada  # noqa: PLC0415

        validar_respuesta_firmada(data, lm_client.public_key)
        # El segundo uso del mismo nonce debe fallar (anti-replay en memoria).
        with pytest.raises(LicenseSignatureError, match="nonce"):
            validar_respuesta_firmada(data, lm_client.public_key)

    async def test_sin_clave_publica_no_verifica_firma(
        self, lm_client: LicenseClient
    ):
        """`strict=False` (entorno sin clave) omite la verificación, pero no la frescura."""
        lm_client.public_key = ""
        info = lm_client.validate(LICENCIA_TEST, "HW-E2E-009")
        assert info.valid is True

    async def test_server_time_fuera_de_ventana_es_rechazado(
        self, lm_client: LicenseClient
    ):
        from app.core.license_client import check_freshness  # noqa: PLC0415

        pasado = (datetime.now(UTC) - timedelta(days=2)).isoformat()
        with pytest.raises(LicenseSignatureError, match="ventana de tiempo"):
            check_freshness(pasado)

    async def test_metadata_de_firma_incorrecta_es_rechazada(
        self, lm_client: LicenseClient
    ):
        from app.core.license_client import check_signature_metadata  # noqa: PLC0415

        with pytest.raises(LicenseSignatureError, match="algoritmo"):
            check_signature_metadata({"signature_algorithm": "none", "signature_version": 1})

    async def test_check_resumen(self, lm_client: LicenseClient):
        resumen: dict[str, Any] = lm_client.check(LICENCIA_TEST)
        assert resumen["valid"] is True
        assert resumen["status"] == "ACTIVE"


class TestFirmaDelStub:
    """Verifica el formato exacto de la firma que produce el stub."""

    def test_canonical_json_coincide_con_el_cliente(self):
        payload = {"b": 2, "a": 1, "c": [1, 2]}
        assert canonical_json(payload) == b'{"a":1,"b":2,"c":[1,2]}'

    def test_stub_firma_los_signed_fields(self, lm_stub: str):
        import httpx  # noqa: PLC0415

        from scripts.lm_stub import estado as estado_stub  # noqa: PLC0415

        token = httpx.post(
            f"{lm_stub}/token", json={"license_key": LICENCIA_TEST}, timeout=5.0
        ).json()["token"]
        data = httpx.post(
            f"{lm_stub}/validate",
            json={"license_key": LICENCIA_TEST, "hardware_id": "HW", "product_code": "WS"},
            headers={"Authorization": f"Bearer {token}"},
            timeout=5.0,
        ).json()

        firmado = {k: data.get(k) for k in SIGNED_FIELDS}
        publica = cast(
            Ed25519PublicKey,
            serialization.load_pem_public_key(
                estado_stub.llave_publica_pem().encode("utf-8")
            ),
        )
        # Si la firma no fuera válida, `verify` lanzaría InvalidSignature.
        publica.verify(base64.b64decode(data["signature"]), canonical_json(firmado))
        assert data["nonce"] and data["valid"] is True