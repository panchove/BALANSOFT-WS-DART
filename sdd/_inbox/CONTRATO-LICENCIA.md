# planes-pagos

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 25010
**Fuente:** Sistema BALANSOFT-WS
**Norma:** ISO/IEC 25010
**Fuente:** Sistema BALANSOFT-WS


# BALANSOFT-WS — Licencias, Planes y Alcances

Planes de licencia de **BALANSOFT-WS** (estación de pesaje industrial):
tiers, límites técnicos, validación criptográfica y reglas de negocio.

**Ver también**: `docs/SESIONES.md` (sesiones y aprobación de equipos),
`backend/app/core/license_client.py` (cliente del LM) y
`backend/app/api/v1/endpoints/auth.py` (contratos `/license`).

---

## Encabezado editorial

| Campo   | Valor                                                                                                                                                                                  |
|---------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Versión | 1.0                                                                                                                                                                                    |
| Fecha   | 2026-10-13                                                                                                                                                                             |
| Estado  | Vigente                                                                                                                                                                                |
| Autor   | Equipo BALANSOFT                                                                                                                                                                       |
| Norma   | REQ-FN-NNN (funcional), REQ-NF-<área>-NNN (no funcional), UX-NNN (interacción)                                                                                                         |
| Fuente  | `backend/app/api/v1/endpoints/auth.py`, `auth.py::/license`, `backend/app/api/v1/endpoints/servidor.py`, `backend/app/core/config.py`, `backend/app/schemas_server.py`, `.env.example` |

> Este documento reemplaza a la versión anterior, que describía **BALANSOFT SG**
> (producto ganadero: MONOPUESTO/Premium, 1 hato, 50 animales, 200 registros).
> WS es un producto distinto: **no ofrece MONOPUESTO** (§2) y sus límites son
> los de una estación de pesaje.

---

## 1. Introducción

Este documento define los planes de licencia de BALANSOFT-WS, sus alcances
funcionales, límites técnicos y reglas de negocio. Sirve como guía para:

- **Clientes y distribuidores:** entender qué incluye cada plan.
- **Desarrolladores:** implementar las validaciones correspondientes.
- **Soporte**: resolver dudas sobre capacidades y limitaciones.

---

## 2. Tipos de licencia (`tier`)

BALANSOFT-WS solo admite **dos** tiers:

| Tier        | Modelo                   | Equipos    | Sesiones simultáneas | Registros (boletos)                     |
|-------------|--------------------------|------------|----------------------|-----------------------------------------|
| **DEMO**    | Prueba de un solo puesto | **1**      | **3**                | **`DEMO_MAX_RECORDS`** (default **10**) |
| **CENTRAL** | Cuenta multiequipo       | Ilimitados | Ilimitadas           | Ilimitados                              |

- **No existe MONOPUESTO en WS.** Una estación de pesaje necesita, como mínimo,
  3 tipos de trabajo simultáneos (báscula, reportes, administración); un plan de
  un solo puesto no encaja. El backend rechaza cualquier `licencia_tier` que no
  sea `DEMO` o `CENTRAL` (`schemas_server.py`, `pattern="^(DEMO|CENTRAL)$"`) y
  `servidor.py` documenta la misma decisión en `_max_sesiones_default`.
- El **LM (SGLB)** es compartido entre productos y *sí* puede tener tiers de
  otros productos (p. ej. MONOPUESTO, de BALANSOFT SG). Para el producto WS el
  LM debe emitir **solo `DEMO` o `CENTRAL`** (`LICENSE_PRODUCT_CODE=WS`).
- **Defensa en la estación:** un tier **desconocido no degrada** a «mínimo
  seguro»: solo `DEMO` aplica topes locales (`auth.py::/license`) y cualquier
  otro tier opera sin límites funcionales, con la concurrencia real fijada por
  `licencias.max_sesiones` del LM/central. Los planes **Básico/Premium**
  (`plan_type`) **no** restringen módulos: la estación WS ignora `features` para
  gatear funciones (`MANEJO_DB.md` §13.6).
- **Aprobación de equipos (RB-12):** solo aplica a `CENTRAL` (el tier que admite
  varios equipos). `DEMO` conserva el comportamiento previo (`docs/SESIONES.md` §4).

---

## 3. Qué incluye cada plan

| Alcance                            | DEMO                     | CENTRAL                           |
|------------------------------------|--------------------------|-----------------------------------|
| Boletos de pesaje (entrada/salida) | Hasta `DEMO_MAX_RECORDS` | Sin límite                        |
| Equipos de la cuenta               | 1                        | Ilimitados (sujeto a la licencia) |
| Sesiones simultáneas               | 3                        | Ilimitadas                        |
| Sincronización con el central      | No                       | Sí                                |
| Aprobación de equipos (RB-12)      | No aplica (un equipo)    | Sí                                |
| Marca de agua en el ticket         | No                       | No                                |
| Panel del proveedor                | Sí                       | Sí                                |

> El **tope de la demo** se cuenta sobre los boletos de la empresa
> (`registros_actuales`) y se expone al cliente vía `GET /api/v1/auth/license`.
> Al alcanzarlo, el alta de boletos responde `403` con el tope alcanzado.

---

## 4. Validación de licencia

- **Firma:** Ed25519 verificada por el **LM (SGLB)**.
  La clave **pública** se lee de `LICENSE_PUBLIC_KEY_PATH`; la **privada** nunca
  sale del LM ni viaja al cliente.
- **Producto:** `LICENSE_PRODUCT_CODE=WS` (ojo: el default histórico del código
  era `BWS`; en WS es `WS`).
- **Endpoint del LM:** `LICENSE_API_URL` (estaciones reales:
  `https://lm.balansoft.com.ve/api/v1`; servidor central con LM local:
  `127.0.0.1:9001/api/v1`).
- **Contrato firmado:** el cliente verifica firma, identidad, empresa,
  estación (`hardware_id`), expiración y ventana de `server_time`
  (anti-replay de `nonce`). Ver `backend/tests/e2e/` y `scripts/lm_stub.py`.
- **Estados:**
  | Estado                                | ¿Vigente? | Significado                                                                        |
  |---------------------------------------|-----------|------------------------------------------------------------------------------------|
  | `ACTIVA`                              | Sí        | Licencia en uso.                                                                   |
  | `AVAILABLE`                           | Sí        | Virgen: aún sin equipo titular; se normaliza a `ACTIVA` (`_normalizar_estado_lm`). |
  | `SUSPENDIDA` / `VENCIDA` / `INACTIVA` | No        | Bloquean login y operación.                                                        |
- La licencia se **re-valida en vivo** contra el LM en `GET /api/v1/auth/license`
  y `POST /api/v1/auth/validate-license`; si el LM no responde, se conserva el
  estado cacheado sin bloquear (operación offline).

---

## 5. API de licencia (rol local, ADMIN)

`GET /api/v1/auth/license` — snapshot para la UI:

```json
{
  "valid": true,
  "status": "ACTIVA",
  "tier": "DEMO",
  "expires_at": "2027-12-31T00:00:00",
  "features": {
    "max_registros": 10,
    "max_sesiones": 3,
    "max_equipos": 1,
    "max_usuarios": 1
  },
  "licencia_key_masked": "BWS-…ABCD",
  "registros_actuales": 4
}
```

`features` lleva `null` donde el tier no limita. La clave se devuelve
**enmascarada**; nunca se expone completa.

---

## 6. Errores de licencia

| Código                       | HTTP | Cuándo                                                                       |
|------------------------------|------|------------------------------------------------------------------------------|
| `LICENSE_DEVICE_MISMATCH`    | 403  | El login viene de un equipo distinto al titular (DEMO / equipo ya amarrado). |
| `DEMO_LIMIT_REACHED`         | 403  | La demo alcanzó `DEMO_MAX_RECORDS` boletos.                                  |
| `espacio_de_trabajo_ocupado` | 403  | La cuenta supera las sesiones concurrentes del tier.                         |
| Licencia no vigente          | 403  | Estado `SUSPENDIDA` / `VENCIDA` / `INACTIVA`.                                |

---

## 7. Preguntas frecuentes

**¿Puedo usar una licencia DEMO en varios dispositivos?**
No. DEMO es de **un solo equipo** (`max_equipos = 1`).

**¿Cómo paso de DEMO a CENTRAL?**
El proveedor actualiza el tier en el LM; el panel y la estación lo reflejan en
la siguiente validación (sin reinstalar), incluidos los límites
(`features`) y el flujo de aprobación de equipos.

**¿Se pierden los boletos al superar el tope de la demo?**
No se pierde nada: el alta se rechaza con `403` al alcanzar el tope.

**¿Hay marca de agua en la demo?**
No. El ticket de WS no lleva marca de agua por tier (sí lleva el rótulo
`ANULADO` cuando el boleto está anulado).

---

## 8. Documentos relacionados

- `docs/SESIONES.md` — sesiones, equipos y aprobación (RB-12).
- `docs/MANEJO_DB.md` §11 y §13 — configuración y modelo de cuenta.
- `backend/app/core/license_client.py` — cliente del LM.
- `backend/scripts/lm_stub.py` — LM de desarrollo/CI (firma Ed25519 real).
- `docs/BALANZAS_SOPORTADAS.md` — básculas soportadas (no depende del tier).
