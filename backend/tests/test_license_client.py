"""Pruebas unitarias del cliente de licencias (seguridad/validaciones con el LM).

Cubren las validaciones portadas desde BALANSOFT-SG: verificación de firma
Ed25519 (incluido `validada_en`), algoritmo/versión de la firma, ventana de
`server_time` (-5 min .. +24 h), anti-replay por `nonce` y formato de clave.
"""

from __future__ import annotations

import base64
from datetime import UTC, datetime, timedelta

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from app.core.license_client import (
    SIGNED_FIELDS,
    LicenseError,
    LicenseInfo,
    LicenseSignatureError,
    _verify_signature,
    canonical_json,
    check_freshness,
    check_nonce,
    check_signature_metadata,
    get_license_client,
    validar_respuesta_firmada,
    validate_license_key_format,
)

# Clave PEM de un par Ed25519 efímero (solo para pruebas).
_PRIV = Ed25519PrivateKey.generate()
_PUB_PEM = (
    _PRIV.public_key()
    .public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    .decode("ascii")
)


def _firmar(payload: dict) -> str:
    return base64.b64encode(_PRIV.sign(canonical_json(payload))).decode("ascii")


def _respuesta_valida(**overrides) -> dict:
    server_time = datetime.now(UTC).replace(tzinfo=None).isoformat()
    datos = {
        "valid": True,
        "status": "ACTIVE",
        "tier": "CENTRAL",
        "plan_type": "basic",
        "features": {"core": True},
        "expires_at": None,
        "server_time": server_time,
        "validada_en": server_time,
        "nonce": "abc123cabecera-unica",
        "signature_algorithm": "ed25519",
        "signature_version": 1,
        "message": "OK",
    }
    datos.update(overrides)
    signed = {k: datos[k] for k in SIGNED_FIELDS}
    datos["signature"] = _firmar(signed)
    return datos


class TestFormatoClave:
    def test_acepta_clave_ws(self):
        assert validate_license_key_format("bws-A1B2-C3D4-E5F6-G7H8") == "BWS-A1B2-C3D4-E5F6-G7H8"

    def test_rechaza_formato_invalido(self):
        for mala in (
            "LIC-DEMO-001",
            "BWS-123-1234-1234-1234",
            "BWS-AAAA-AAAA-AAAA-AAAA-EXTRA",
            "----",
            "",
        ):
            with pytest.raises(LicenseError):
                validate_license_key_format(mala)


class TestFirmaEd25519:
    def test_respuesta_valida_pasa(self):
        validar_respuesta_firmada(_respuesta_valida(nonce="nonce-1"), _PUB_PEM)

    def test_alg_version_incorrecta(self):
        with pytest.raises(LicenseSignatureError):
            validar_respuesta_firmada(
                _respuesta_valida(nonce="nonce-2", signature_algorithm="rsa"),
                _PUB_PEM,
            )
        with pytest.raises(LicenseSignatureError):
            validar_respuesta_firmada(
                _respuesta_valida(nonce="nonce-3", signature_version=99),
                _PUB_PEM,
            )

    def test_firma_tamperada(self):
        resp = _respuesta_valida(nonce="nonce-4")
        resp["valid"] = False  # cambiar la decisión invalida la firma
        with pytest.raises(LicenseSignatureError):
            validar_respuesta_firmada(resp, _PUB_PEM)

    def test_clave_publica_ausente(self):
        with pytest.raises(LicenseSignatureError):
            validar_respuesta_firmada(_respuesta_valida(nonce="nonce-5"), None)

    def test_firma_incluye_validada_en(self):
        """SG y WS firmamos los mismos 9 campos; sin validada_en la firma difiere."""
        resp = _respuesta_valida(nonce="nonce-6")
        resp_sin_ancla = {
            k: v
            for k, v in resp.items()
            if k in SIGNED_FIELDS and k != "validada_en"
        }
        # Re-firmar sin validada_en: una verificación con los campos WS anteriores
        # (sin validada_en) NO debe pasar contra esta firma que sí lo incluye.
        assert not _verify_signature(
            resp_sin_ancla, resp["signature"], _PUB_PEM
        )
        # Con validada_en sí pasa.
        assert _verify_signature(
            {k: resp[k] for k in SIGNED_FIELDS}, resp["signature"], _PUB_PEM
        )


class TestVentanaTiempo:
    def _resp_para(self, cuando: datetime):
        return _respuesta_valida(nonce="nonce-t1", server_time=cuando.isoformat())

    def test_dentro_de_ventana(self):
        ahora = datetime.now(UTC)
        resp = self._resp_para(ahora + timedelta(hours=1))
        validar_respuesta_firmada(resp, _PUB_PEM)

    def test_demasiado_vieja(self):
        resp = self._resp_para(datetime.now(UTC) - timedelta(minutes=6))
        with pytest.raises(LicenseSignatureError):
            validar_respuesta_firmada(resp, _PUB_PEM)

    def test_demasiado_futura(self):
        resp = self._resp_para(datetime.now(UTC) + timedelta(hours=25))
        with pytest.raises(LicenseSignatureError):
            validar_respuesta_firmada(resp, _PUB_PEM)


class TestAntiReplay:
    def test_nonce_repetido_rechazado(self):
        check_nonce("nonce-replay-2026")
        with pytest.raises(LicenseSignatureError):
            check_nonce("nonce-replay-2026")

    def test_sin_nonce_rechazado(self):
        resp = _respuesta_valida(nonce=None)
        with pytest.raises(LicenseSignatureError):
            validar_respuesta_firmada(resp, _PUB_PEM)

    def test_respuesta_repetida_rechazada(self):
        resp = _respuesta_valida(nonce="nonce-resp-2026")
        validar_respuesta_firmada(resp, _PUB_PEM)
        with pytest.raises(LicenseSignatureError):
            validar_respuesta_firmada(resp, _PUB_PEM)


class TestMetadata:
    def test_sin_metadata_fallida(self):
        resp = _respuesta_valida(nonce="nonce-m1")
        resp.pop("signature_algorithm")
        with pytest.raises(LicenseSignatureError):
            check_signature_metadata(resp)

    def test_check_freshness_manual(self):
        ahora_naive = datetime.now(UTC).replace(tzinfo=None)
        check_freshness(ahora_naive.isoformat())
        with pytest.raises(LicenseSignatureError):
            check_freshness((ahora_naive - timedelta(days=2)).isoformat())
        with pytest.raises(LicenseSignatureError):
            check_freshness("no-es-fecha")


class TestValidarOAutoactivar:
    """Pruebas de la lógica de auto-activación (validate_or_activate)."""

    def test_autoactiva_cuando_licencia_disponible(self) -> None:
        client = get_license_client()
        seq = {"n": 0}

        def fake_validate(key, hw, **kw):
            if seq["n"] == 0:
                seq["n"] = 1
                return LicenseInfo(
                    valid=False,
                    status="AVAILABLE",
                    tier="DEMO",
                    message="Licencia no activada — debe activarse primero mediante /activate",
                )
            return LicenseInfo(valid=True, status="ACTIVE", tier="DEMO", message="ok")

        def fake_activate(key, hw, **kw):
            return {"ok": True}

        client.validate = fake_validate  # type: ignore[method-assign]
        client.activate = fake_activate  # type: ignore[method-assign]

        info = client.validate_or_activate("BWS-A1B2-C3D4-E5F6-G7H8", "HW-1")
        assert info.valid is True
        assert info.status == "ACTIVE"

    def test_autoactiva_dispositivo_central_no_registrado(self) -> None:
        client = get_license_client()
        seq = {"n": 0}

        def fake_validate(key, hw, **kw):
            if seq["n"] == 0:
                seq["n"] = 1
                return LicenseInfo(
                    valid=False,
                    status="DEVICE_NOT_REGISTERED",
                    tier="CENTRAL",
                    message="Dispositivo no registrado en esta licencia CENTRAL",
                )
            return LicenseInfo(valid=True, status="ACTIVE", tier="CENTRAL", message="ok")

        def fake_activate(key, hw, **kw):
            return {"ok": True}

        client.validate = fake_validate  # type: ignore[method-assign]
        client.activate = fake_activate  # type: ignore[method-assign]

        info = client.validate_or_activate("BWS-A1B2-C3D4-E5F6-G7H8", "HW-1")
        assert info.valid is True
        assert info.tier == "CENTRAL"

    def test_no_autoactiva_en_hardware_mismatch(self) -> None:
        client = get_license_client()

        info_original = LicenseInfo(
            valid=False,
            status="HARDWARE_MISMATCH",
            tier="DEMO",
            message="Hardware fingerprint no coincide",
        )

        client.validate = lambda *a, **k: info_original  # type: ignore[method-assign]
        llamado = {"activado": False}

        def fake_activate(key, hw, **kw):
            llamado["activado"] = True
            return {"ok": True}

        client.activate = fake_activate  # type: ignore[method-assign]

        info = client.validate_or_activate("BWS-A1B2-C3D4-E5F6-G7H8", "HW-OTRO")
        assert info is info_original  # debe devolver la info original sin activar
        assert not llamado["activado"]

    def test_no_autoactiva_en_estado_suspendida(self) -> None:
        client = get_license_client()

        info_original = LicenseInfo(
            valid=False,
            status="SUSPENDIDA",
            tier="CENTRAL",
            message="Licencia en estado SUSPENDIDA",
        )

        client.validate = lambda *a, **k: info_original  # type: ignore[method-assign]
        llamado = {"activado": False}

        def fake_activate(key, hw, **kw):
            llamado["activado"] = True
            return {"ok": True}

        client.activate = fake_activate  # type: ignore[method-assign]

        info = client.validate_or_activate("BWS-A1B2-C3D4-E5F6-G7H8", "HW-1")
        assert info is info_original
        assert not llamado["activado"]


class TestValidateCached:
    """Caché de validación por turno (offline-first en operación de pesaje)."""

    def _client_limpio(self):
        client = get_license_client()
        client._cache.clear()  # type: ignore[attr-defined]
        client._last_fallback.clear()  # type: ignore[attr-defined]
        return client

    def test_validacion_cacheada_dentro_ttl(self) -> None:
        client = self._client_limpio()
        llamadas = {"n": 0}

        def fake_validate_or_activate(key, hw, **kw):
            llamadas["n"] += 1
            return LicenseInfo(valid=True, status="ACTIVE", tier="CENTRAL", message="ok")

        client.validate_or_activate = fake_validate_or_activate  # type: ignore[method-assign]

        info1 = client.validate_cached(
            "BWS-A1B2-C3D4-E5F6-G7H8", "HW-1", ttl=timedelta(minutes=5)
        )
        info2 = client.validate_cached(
            "BWS-A1B2-C3D4-E5F6-G7H8", "HW-1", ttl=timedelta(minutes=5)
        )
        assert info1 is not None and info1.valid
        assert info2 is info1  # misma instancia cacheada
        assert llamadas["n"] == 1

    def test_resultado_invalido_no_se_cachea(self) -> None:
        client = self._client_limpio()
        llamadas = {"n": 0}
        no_valida = LicenseInfo(valid=False, status="EXPIRED", tier="DEMO", message="x")

        def fake_validate_or_activate(key, hw, **kw):
            llamadas["n"] += 1
            return no_valida

        client.validate_or_activate = fake_validate_or_activate  # type: ignore[method-assign]

        info = client.validate_cached(
            "BWS-A1B2-C3D4-E5F6-G7H8", "HW-1", ttl=timedelta(minutes=5)
        )
        assert info is no_valida
        assert client._cache == {}  # type: ignore[attr-defined]

    def test_lm_inalcanzable_devuelve_none_sin_repreguntar(self) -> None:
        client = self._client_limpio()
        llamadas = {"n": 0}

        def fake_validate_or_activate(key, hw, **kw):
            llamadas["n"] += 1
            raise LicenseError("LM no responde")

        client.validate_or_activate = fake_validate_or_activate  # type: ignore[method-assign]

        info1 = client.validate_cached(
            "BWS-A1B2-C3D4-E5F6-G7H8", "HW-1", ttl=timedelta(minutes=5)
        )
        info2 = client.validate_cached(
            "BWS-A1B2-C3D4-E5F6-G7H8", "HW-1", ttl=timedelta(minutes=5)
        )
        assert info1 is None
        assert info2 is None
        assert llamadas["n"] == 1  # el fallback evita martillar el LM

    def test_ttl_0_siempre_revalida(self) -> None:
        client = self._client_limpio()
        llamadas = {"n": 0}

        def fake_validate_or_activate(key, hw, **kw):
            llamadas["n"] += 1
            return LicenseInfo(valid=True, status="ACTIVE", tier="DEMO", message="ok")

        client.validate_or_activate = fake_validate_or_activate  # type: ignore[method-assign]

        client.validate_cached("BWS-A1B2-C3D4-E5F6-G7H8", "HW-1", ttl=timedelta(0))
        client.validate_cached("BWS-A1B2-C3D4-E5F6-G7H8", "HW-1", ttl=timedelta(0))
        assert llamadas["n"] == 2

    def test_ttl_expirado_revalida_y_renueva(self) -> None:
        client = self._client_limpio()
        ahora = datetime.now(UTC).replace(tzinfo=None)
        vencida = LicenseInfo(valid=True, status="ACTIVE", tier="CENTRAL", message="ok")
        client._cache["BWS-A1B2-C3D4-E5F6-G7H8"] = type(
            "LC", (), {"info": vencida, "cached_at": ahora - timedelta(minutes=30)}
        )()
        llamadas = {"n": 0}

        def fake_validate_or_activate(key, hw, **kw):
            llamadas["n"] += 1
            return vencida

        client.validate_or_activate = fake_validate_or_activate  # type: ignore[method-assign]

        client.validate_cached("BWS-A1B2-C3D4-E5F6-G7H8", "HW-1", ttl=timedelta(minutes=1))
        assert llamadas["n"] == 1