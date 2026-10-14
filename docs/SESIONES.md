# BALANSOFT-WS: Sesiones y Equipos de la Cuenta (RB-12)

Modelo de **sesiones = dispositivos** del servidor central y el flujo de
**aprobación de equipos** por parte de la tutora de la cuenta. Documento vigente
del alcance.

**Ver también**: `docs/MANEJO_DB.md` §13 (modelo de cuenta y titular),
`backend/app/api/v1/endpoints/servidor.py` (implementación) y
`frontend/lib/presentation/screens/sesiones/sesiones_screen.dart` (UI).

---

## Encabezado editorial

| Campo | Valor |
|-------|-------|
| Versión | 1.0 |
| Fecha | 2026-10-13 |
| Estado | Vigente |
| Autor | Equipo BALANSOFT |
| Norma | REQ-FN-NNN (funcional), REQ-NF-<área>-NNN (no funcional), UX-NNN (interacción) |
| Fuente | `backend/app/api/v1/endpoints/servidor.py`, `backend/app/schemas_server.py`, `backend/balansoft-ws-server.sql`, `frontend/lib/domain/entities/sesion_equipo.dart`, `docs/MANEJO_DB.md` §13 |

---

## 1. Alcance y terminología

| Término | Significado en WS |
|---------|-------------------|
| **Sesión** | Una **sesión abierta** de un dispositivo contra la API (`dispositivos` + `sesiones` en la BD del servidor). |
| **Equipo** | Un dispositivo físico identificado por su `hardware_id` (fila de `dispositivos`). Una sesión pertenece a un equipo. |
| **Titular / dueño / tutora** | El equipo al que quedó atada la licencia: `licencias.hardware_id`. Es el único que puede aprobar o rechazar a los demás. |
| **Rol de dispositivo** | `SERVIDOR_LOCAL` (el titular) o `LOCAL` (trabajador). Decide si el equipo levanta su propio WServer. `docs/MANEJO_DB.md` §13.1. |
| **Rol de sesión** | `ADMIN \| OPERADOR \| AUDITOR \| TRABAJADOR`. El rol con el que opera **esa sesión**, asignado al aprobar el equipo. |

> Nota de nomenclatura: «Sesiones y Equipos» (navegación Flutter) es el listado
> de **equipos de la cuenta**. No confundir con «Dispositivos de Campo», que en
> WS son las **básculas/impresoras periféricas** de la estación.

RB-12 (acuerdo del 2026-10) añade el **modelo de aprobación de equipos** al
servidor central: un equipo nuevo de una licencia `CENTRAL` nace `PENDIENTE` y
no abre sesión hasta que la tutora lo apruebe con un rol de sesión.

---

## 2. Dónde vive (dos bases)

RB-12 es **exclusivamente del servidor central** (`APP_ROLE=server`,
`balansoft_ws_server`). La estación **no** guarda equipos: la UI de la estación
consulta la API del central con la **credencial global** (`_serverToken`,
obtenida en el `serverLogin` del login central-first) y la cuenta sale siempre
del token, nunca de un parámetro del cliente (multi-tenancy).

| Tabla (server) | Papel en RB-12 |
|----------------|----------------|
| `dispositivos` | Fila por equipo: `hardware_id`, `rol_dispositivo`, `rol_sesion`, `estado`, `activo`. |
| `licencias` | `hardware_id` = titular; `max_equipos` / `max_sesiones` según tier. |
| `sesiones` | Sesiones abiertas; se revocan al rechazar el equipo. |
| `auditoria` | Registra `sesion_aprobada` / `sesion_rechazada` / `sesion_+rol`. |
| `credenciales` | `rol_global` (ADMIN/…) de la credencial del servidor. |

Columnas relevantes de `dispositivos` (migración plegada en
`balansoft-ws-server.sql`):

| Columna | Tipo | Semántica |
|---------|------|-----------|
| `estado` | `VARCHAR` `CHECK (estado IN ('PENDIENTE','APROBADO','RECHAZADO'))` | Estado de aprobación. **Las filas antiguas sin valor se leen como `APROBADO`** (`_estado_equipo`). |
| `rol_sesion` | `VARCHAR` NULL, `CHECK (rol_sesion IN ('ADMIN','OPERADOR','AUDITOR','TRABAJADOR'))` | Rol que tendrá la sesión. NULL mientras no se apruebe. |
| `rol_dispositivo` | `TEXT` | `SERVIDOR_LOCAL` \| `LOCAL` (recalculado en cada login). |
| `activo` | `BOOLEAN` | `false` en un equipo `PENDIENTE`/`RECHAZADO` (no consume cupo). |

---

## 2.1 Titularidad (quién es la tutora)

No se persiste un `es_dueno`: se **deriva** de `licencias.hardware_id`
(`_es_equipo_dueno`). Un equipo es la tutora si y solo si su `hardware_id`
coincide con el de la licencia.

- El dueño **no** puede rechazarse ni cambiársele el rol (`PATCH` responde 422).
- El dueño nace `APROBADO` con `rol_sesion = ADMIN`.
- Cuando la licencia aún **no** tiene titular (`licencias.hardware_id` vacío), el
  primer equipo que la use se amarra como titular (`docs/MANEJO_DB.md` §13.1).
- Cambiar el equipo titular es potestad del proveedor desde el panel
  (`POST /api/v1/panel/cuentas/{id}/titular`), no de la app.

---

## 3. Estados y transiciones

```
                (primer equipo CENTRAL de la licencia)
   sin fila ─────────────────────────────────────────► APROBADO  (dueño, ADMIN)
        │
        │ (segundo equipo CENTRAL)
        ▼
   PENDIENTE ── aprobar (exige rol_sesion) ──► APROBADO
        │                                        │
        │ rechazar                               │ rechazar
        ▼                                        ▼
   RECHAZADO ◄────────────────────────────────────┘
```

- **`PENDIENTE`** — el equipo se registró pero **no abre sesión** (403 en el
  login). No consume cupo de sesiones.
- **`APROBADO`** — puede abrir sesión con su `rol_sesion`.
- **`RECHAZADO`** — inactivo; **además se revocan sus sesiones abiertas**
  (`_revocar_sesiones_dispositivo`): deja de sincronizar de inmediato.
- `PENDIENTE` **no** es un destino válido del `PATCH`: un equipo aprobado no
  vuelve a quedar a la espera; se rechaza y se vuelve a aprobar si hiciera falta
  (`SesionUpdateRequest`).

---

## 4. Cuándo un equipo nace pendiente

```python
es_dueno = licencia.hardware_id == hardware_id
exige_aprobacion = (licencia.licencia_tier == "CENTRAL") and licencia.hardware_id
estado_inicial = PENDIENTE if (exige_aprobacion and not es_dueno) else APROBADO
```

- **`CENTRAL`** con titular ya definido → todo equipo nuevo nace `PENDIENTE`.
- **`DEMO`** → un solo equipo; conserva el comportamiento previo
  (nace `APROBADO`). *(BalanceSoft WS no ofrece MONOPUESTA en este backend: ver
  §8.)*
- Una licencia **virgen** (`hardware_id` vacío) no exige aprobación: el primer
  equipo que la usa queda como titular aprobado.

---

## 5. Gates en el login (`POST /api/v1/auth/login`)

| Momento | Comprobación | Respuesta |
|---------|--------------|-----------|
| Alta del equipo | estado calculado en `_dispositivo` | la fila se persiste **antes** de responder (si no, la tutora no la vería) |
| Estado | `_estado_equipo(disp) != APROBADO` | `403` «pendiente de aprobación» o «rechazado por el administrador de la cuenta» |
| Cupo de equipos (`DEMO`) | equipos activos > `licencia.max_equipos` | `403` «La licencia no autoriza más equipos para sincronizar» |
| Cupo de sesiones | nº de sesiones activas ≥ `licencia.max_sesiones` | `403` «Límite de sesiones de la licencia alcanzado» |
| Sync / push-pull | `get_server_credencial` **re-verifica** el estado en cada petición | `403` si el equipo fue rechazado después de abrir sesión |

El 403 por pendiente se detecta en Flutter con
`esErrorEquipoSinAprobar()` (`frontend/lib/core/utils/mensaje_error.dart`) para
mostrar la guía «Apruébelo desde el equipo titular en "Sesiones y Equipos"».

---

## 6. API (rol `server`, solo ADMIN global)

La cuenta sale **siempre** de la credencial autenticada: el cliente no elige el
tenant.

### `GET /api/v1/auth/sesiones`

```json
{
  "items": [
    {
      "id_dispositivo": "…uuid…",
      "hardware_id": "hw_v2_…",
      "nombre_equipo": "Estación 1",
      "sistema_operativo": "Linux",
      "version_app": "3.24.0",
      "rol_dispositivo": "SERVIDOR_LOCAL",
      "rol_sesion": "ADMIN",
      "estado": "APROBADO",
      "activo": true,
      "es_dueno": true,
      "ultima_conexion": "2026-10-13T11:02:00Z",
      "created_at": "2026-09-01T08:00:00Z"
    }
  ],
  "max_equipos": null,
  "max_sesiones": null,
  "hardware_titular": "hw_v2_…"
}
```

`max_equipos` / `max_sesiones` son `null` cuando el tier es ilimitado. La cuenta
sale **siempre** del token (`cred.id_cuenta`), no de un parámetro.

### `PATCH /api/v1/auth/sesiones/{id_dispositivo}`

```json
{ "estado": "APROBADO", "rol_sesion": "OPERADOR" }
```

| Regla | Respuesta |
|-------|-----------|
| Aprobar sin `rol_sesion` (y sin rol previo) | `422` |
| `estado` fuera de `APROBADO\|RECHAZADO`, o rol fuera de los 4 válidos | `422` (schema) |
| Sin `estado` ni `rol_sesion` | `422` |
| Equipo titular | `422` «El equipo titular de la licencia no puede modificarse» |
| Equipo de otra cuenta | `404` (no se filtra su existencia) |
| Credencial no ADMIN | `403` |

Aprobar pone `activo=true`; rechazar lo pone `false` y **revoca** las sesiones
abiertas. Cada llamada deja traza en `auditoria`
(`sesion_aprobada`, `sesion_rechazada`, `sesion_+rol`) con `id_cuenta` de la
credencial (multi-tenancy).

---

## 6.1 Verificación continua

`get_server_credencial` no confía en el estado del token: en cada petición
autenticada **vuelve a leer `dispositivos.estado`** del equipo del token. Un
equipo rechazado después de entrar deja de poder sincronizar sin esperar a que
expire su JWT.

---

## 7. UI Flutter (RB-12)

`frontend/lib/presentation/screens/sesiones/sesiones_screen.dart`, accesible
desde la barra lateral → **MANTENIMIENTO → Sesiones y Equipos** (solo rol
`ADMIN`). Es una **hoja-acción** (`accion: 'go:sesiones'`), no un módulo de la
matriz de accesos local: su autoridad es el servidor central.

- Lista los equipos con estado, rol de dispositivo y rol de sesión.
- **Aprobar** abre un diálogo para elegir el `rol_sesion` (por defecto
  `OPERADOR`); **Rechazar** pide confirmación.
- El equipo titular se muestra con candado (no editable).
- Sin credencial del servidor central (`_serverToken`), la pantalla lo explica
  en vez de fallar con un error de red.
- Entidades y repositorio: `domain/entities/sesion_equipo.dart`,
  `data/repositories/sesiones_repository.dart` (registrado en `injection.dart`).

El error de login de un equipo pendiente se traduce a un mensaje accionable en
`core/utils/mensaje_error.dart` (`esErrorEquipoSinAprobar`).

---

## 8. Alcance de licencias en WS (nota)

El backend de WS solo admite los tiers **`DEMO`** y **`CENTRAL`**
(`schemas_server.py`, `pattern="^(DEMO|CENTRAL)$"`). En particular:

- **No existe MONOPUESTA** en WS: una estación de pesaje trabaja como mínimo con
  3 tipos de trabajo, por eso `_max_sesiones_default` da `DEMO → 3` y
  `CENTRAL/AUTO → ilimitado`.
- `DEMO` limita a **1 equipo** (`_limite_por_tier`). El resto, ilimitado.
- El tope de boletos de la demo es `DEMO_MAX_RECORDS` (default **10**, ver
  `.env.example`). No debe confundirse con los 200 registros del producto
  ganadero (BALANSOFT SG); `docs/PLANES-PAGOS.md` es de SG, no de WS.

---

## 9. Pruebas

`backend/tests/test_api_server.py` (marca RB-12):

- el dueño nace `APROBADO` con rol `ADMIN` y no se puede rechazar;
- un 2º equipo `CENTRAL` nace `PENDIENTE` y su login responde `403`;
- aprobar sin rol → `422`; aprobar con rol → el login funciona;
- rechazar revoca las sesiones abiertas y bloquea `get_server_credencial`;
- un equipo de otra cuenta responde `404`;
- logout/login no reintroduce un equipo rechazado como aprobado.

Frontend: `test/widget/sesiones_screen_test.dart` (6 casos) y
`test/unit/mensaje_error_test.dart`.

Suites: `uv run pytest tests/test_api_server.py -q` (backend) y
`flutter test test/widget/sesiones_screen_test.dart` (frontend).

---

## 10. Referencias

- `docs/MANEJO_DB.md` §13 — modelo de cuenta, titular y dispositivos.
- `backend/app/api/v1/endpoints/servidor.py` — RB-12 (gates, endpoints).
- `backend/app/schemas_server.py` — contratos `SesionEquipoOut`,
  `SesionesResponse`, `SesionUpdateRequest`.
- `backend/balansoft-ws-server.sql` — esquema canónico del servidor.
- `frontend/lib/presentation/screens/sesiones/sesiones_screen.dart` — UI.
- `docs/NAV.md` — mapa de navegación (entrada «Sesiones y Equipos»).
