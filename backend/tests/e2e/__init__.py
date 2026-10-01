"""Pruebas E2E (H2): flujo real contra el stub del License Manager.

A diferencia de `tests/` (que usa dobles rápidos), aquí el cliente de licencias
real habla por HTTP con `scripts/lm_stub.py`, que firma con Ed25519. Sirve para
detectar cambios en el contrato firmado y para el job `e2e` de CI.
"""