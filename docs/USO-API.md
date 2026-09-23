# Integración del Software Cliente - Sistema de Licencias

Explicación del flujo completo desde el lado del software cliente (basada en `docs/integracion-software-cliente.md`, que refleja el código de `app/api/validation.py` y del repo `Inventariodeproductos`).

---

## 1. Flujo de Vida de una Licencia en el Cliente

```text
POST /api/v1/token  ──>  Bearer token (24h, firmado Ed25519, revoca anteriores)
       │
       ▼
POST /api/v1/validate  ──┬──>  valid=true   ──>  firmada, guardar y usar
                         └──>  valid=false  ──>  status ∈ {AVAILABLE, IN_INVENTORY}
                                     │
                                     ▼
                               POST /api/v1/activate  ──>  (persiste hardware, status -> ACTIVE)
                                     │
                                     ▼
                               POST /api/v1/validate  ──>  firma post-activación  ──>  guardar
```

En la app Android eso es `LicenseManager.validateAndStore(licenseKey)` (`License/LicenseManager.kt`).

---

## 2. Endpoints y qué Envía el Cliente

**Base:** `https://<servidor>/api/v1`  
**Cabeceras en `/activate` y `/validate`:** `Authorization: Bearer <token>` + `Content-Type: application/json`.  
**Timeouts:** 10s.

| Endpoint | Uso | Cuerpo |
| :--- | :--- | :--- |
| `POST /token` | Obtener Bearer token por licencia | `{"license_key": "BIDP-XXXX-..."}` |
| `POST /validate` | Decisión de validez (firma decisiva) | `license_key`, `hardware_id`, `mac_address`, `device_brand`, `device_model`, `os_version`, `product_code` ("IDP") |
| `POST /activate` | Activación inicial | Mismos campos + opcionalmente `client_name`/`email`/`phone`/`company`/`distributor_id` (auto-activación) |
| `GET /{license_key}/check` | Informativo pre-activación (no firmado) | — |

**Token (anti-DDoS):** Si `/activate` / `/validate` devuelven `401 "Token inválido o expirado"`, se re-pide un token (1 sola vez) y se reintenta. Cada `POST /token` incrementa `auth_token_version` → **solo un token activo por licencia.**

---

## 3. Decisión de Validez (`/validate`)

`valid: true` solo si licencia **ACTIVE**, no expirada y `hardware_id` coincide. Respuesta firmada:

```json
{
  "valid": true,
  "status": "ACTIVE",
  "expires_at": "...",
  "tier": "MONOPUESTO",
  "plan_type": "basic",
  "features": {
    "core": true,
    "max_users": 1,
    "max_categorias": 10,
    "max_productos": 100
  },
  "server_time": "...",
  "nonce": "...",
  "signature": "...",
  "signature_algorithm": "ed25519",
  "signature_version": 1
}
```

**Estados de rechazo:** `AVAILABLE`/`IN_INVENTORY` (hay que activar), `EXPIRED`, `HARDWARE_MISMATCH`, `INACTIVE`/`CANCELLED` (no utilizable).

### 3.1 Distribuidor responsable (`distributor_*`)

Los 3 endpoints de validación exponen al **distribuidor responsable** de la licencia, resuelto **en vivo en cada request** (`_distributor_for(lic)`, `validation.py:447`): consulta la BD al momento, así que refleja reasignaciones al instante:

- Si la licencia está en inventario de un distribuidor (`owner_type == DISTRIBUTOR_INVENTORY`) → el `distributor_owner` de la licencia.
- Si no, si tiene cliente asignado → el `distributor` de ese cliente.
- Si no hay ninguno (pool del Desarrollador, sin cliente) → todos los campos van `null`.

Campos devueltos (en todos los endpoints): `id`, `name` (=`full_name`), `email`, `phone`, `company`.

| Endpoint | Dónde va | Formato |
| :--- | :--- | :--- |
| `GET /{license_key}/check` (público) | planos en la raíz | `distributor_id`, `distributor_name`, `distributor_email`, `distributor_phone`, `distributor_company` |
| `POST /validate` (Bearer) | planos en la raíz | mismos campos (`ValidateResponse`) |
| `POST /activate` (Bearer) | anidados en `license.*` | `ActivateLicenseResponse.license = _license_to_dict(lic)` |

**Importante para el software cliente:** en `/validate` el contacto del distribuidor es **metadata NO firmada** (ver `_build_signed_response`, `validation.py:564`). La firma Ed25519 cubre solo `valid`/`status`/`expires_at`/`tier`/`plan_type`/`features`/`server_time`/`nonce`; `distributor_*` se añade después y **no participa de la firma ni del anti-replay**. El cliente debe mostrarlo como *"a quién acudir por soporte/renovación"*, nunca usarlo para decisiones de seguridad.

Ejemplo de `/validate` para una licencia con cliente cuya distribución es *Distribuidora Ejemplo*:

```json
{
  "valid": true, "status": "ACTIVE", "tier": "CENTRAL", "plan_type": "basic",
  "features": {...},
  "server_time": "...", "nonce": "...", "signature": "...",
  "distributor_id": "d1a2b3c4-...",
  "distributor_name": "Distribuidora Ejemplo",
  "distributor_email": "distribuidor@ejemplo.com",
  "distributor_phone": "+58 412 123 4567",
  "distributor_company": "Distribuidora Ejemplo C.A."
}
```

---

## 4. Activación (`/activate`)

- **Persiste** `hardware_id`/`MAC`/`marca`/`modelo`/`OS` en la licencia y pasa a `ACTIVE`.
- **Anti-duplicado:** Rechaza si ya hay otra licencia del mismo producto `ACTIVE` (no expirada) en ese dispositivo.
- **Cliente obligatorio:** Una licencia solo se activa si está **preasignada a un cliente** o se usa la auto-activación (abajo). En el portal de gestión (Mis Licencias) no se permite activar una licencia sin cliente asignado → el admin debe asignarla antes.
- **Auto-activación (`ALLOW_SELF_ACTIVATION=true`):** permitida solo para licencias con `owner_type=DISTRIBUTOR_INVENTORY`. Si el payload incluye `client_name`/`client_email`/`client_phone`/`client_company`, el servidor **crea el cliente** y lo vincula; si no incluye datos de cliente, la licencia se activa igualmente pero queda sin cliente asociado.
- **Re-activación:** MONOPUESTO/DEMO rechazan una segunda activación ("Licencia ya activada"); CENTRAL admite activar dispositivos adicionales hasta `max_activations`.
- **Errores:** HTTP `400` con detail: `{"error": true, "message": "..."}`.

---

## 5. Alcances / Límites según Tipo de Licencia

El servidor calcula features por tier (`_get_features_for_tier` en `validation.py`). Para el producto **IDP** se agregan límites de inventario (configurables por `system_configurations`):

| Tier | max_categorias | max_productos | Otros |
| :--- | :--- | :--- | :--- |
| **DEMO** | 1 | 5 | + `days_remaining`; 15 días gratis |
| **MONOPUESTO** | 10 | 100 | `max_users`: 1, sin multi-empresa |
| **CENTRAL** | null (∞) | null (∞) | `max_users`: 10, multi-empresa |

En la app, `InventoryViewModel.insertCategoria()` / `insertProducto()` **bloquean** la escritura local si `lic.valid != true` o se alcanzó el tope (`max == null` → ilimitado).

**Acceso por plan (`plan_type`):** además del tier, la respuesta de `/validate` incluye `plan_type` (`basic` = Básica | `premium` = Avanzada), que la app usa para habilitar u ocultar módulos/funciones según el plan contratado. `tier` rige la concurrencia y vigencia (`DEMO` expira, `MONOPUESTO` = 1 usuario, `CENTRAL` = multi-usuario); `plan_type` rige el **alcance de funciones** dentro del software. Como va dentro de la firma Ed25519, se aplica solo tras verificar firma + `server_time`.

---

## 6. Seguridad que Debe Implementar el Cliente

- **Verificación de firma Ed25519 de `/validate`:** Firmar exactamente los **9 campos** `valid`, `status`, `expires_at`, `tier`, `plan_type`, `features`, `server_time`, `nonce`, `validada_en` con JSON canónico (`json.dumps(sort_keys=True, separators=(",", ":"), ensure_ascii=True)`), verificar contra la clave pública embebida (`ResponseSignatureVerifier.kt`, `CanonicalJson.kt`). `validada_en` es el ancla de tiempo del servidor y va firmado para que un atacante no pueda fabricar un valor futuro.
- **Anti-replay:** Exigir `server_time` en ventana -5 min .. +24 h.
- **Offline:** Guardar la respuesta firmada; re-verificar firma al arrancar y validar expiración combinando `server_time` + `SystemClock.elapsedRealtime()` (inmune a cambios de hora). Mientras la app está abierta, `refreshSilently()` cada 30 min.

---

### Pre-requisitos del lado servidor
`scripts/generate_signing_keys.py` genera el par Ed25519; la privada va en `.env` como `API_SIGNING_PRIVATE_KEY` y la pública embebida en la app (`AppConfig.kt`). Sin firma verificable, `/validate` no debe confiarse.
