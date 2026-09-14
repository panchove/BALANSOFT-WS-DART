# Estado de Implementación de BALANSOFT-WS

| Atributo          | Valor                                    |
|-------------------|------------------------------------------|
| **Documento**     | IMPLEMENTADO.md                          |
| **Versión**       | 1.5                                      |
| **Fecha**         | 2026-09-14                               |
| **Estado**        | Vigente                                  |
| **Autor**         | Equipo BALANSOFT                         |
| **Norma**         | ISO/IEC/IEEE 42010 + 29148               |
| **Fuente**        | Código fuente real (`backend/`, `frontend/`), `docs/PRD.md`, `docs/MODEL.md` |

> Este documento detalla **lo que realmente está construido** en el repositorio en este momento, verificado contra el código. No es una especificación de objetivos: es un inventario del estado vigente de implementación.

**Cambios en v1.2 (2026-09-14):** fotos de camión/remolque tomadas o cargadas (formulario de pesaje y catálogos de camión/remolque/conductor) con visualización en detalle; peso en vivo por TCP (`ScaleTcpClient` + `ScaleMonitorWidget`) en formulario y cierre; módulo de básculas WS en el simulador BSDD (entrada `:5555`, salida `:5556`); guardado de reportes/tickets/kardex en Descargas con ruta visible (nueva sección "Archivos" en Ajustes); layouts responsive para móvil en Reportes y Kardex; validadores en formularios.

**Cambios en v1.3 (2026-09-14):** HAL de balanza en backend (`scale_hal.py`: SerialScaleHAL, TcpScaleHAL + factory), con endpoint `GET /weighing/scale/{balanza_id}/live` para lectura de peso en vivo (B7, REQ-NF-ARQ-004); migración `005_balanza_hardware` (puerto_com/ip_address/puerto_tcp/protocolo); 8 tests de HAL (`test_scale_hal.py`); corrección de 3 fallos preexistentes en tests backend (conductor duplicado y `P-01` no-UUID en kardex) → 79/79 verdes; descripción OpenAPI ampliada en `main.py`.

**Cambios en v1.4 (2026-09-14):** integración del HAL de balanza en el frontend (`ScaleApiClient` API-first con fallback TCP + `ScaleMonitorWidget` con `balanzaId`/descripción); pantalla de Administración de Licencias (ADMIN) con snapshot `GET /api/v1/auth/license` (tier/vencimiento/key enmascarada/uso DEMO) y renovación vía `validate-license`; **reportes avanzados** backend+UI (ranking por transportista `GET /reports/transportista`, volumen por tercero `GET /reports/tercero`, distribución por rango de peso `GET /reports/peso-rango`, comparativo mensual `GET /reports/comparativo-mensual`) con 7 tests nuevos → **87/87** backend; **pruebas E2E** (`frontend/integration_test/pesaje_flow_test.dart` + Keys de UI); documentación OpenAPI ampliada (summary, tags, contact) y verificación de los nuevos endpoints en `/openapi.json` (60 paths).

**Cambios en v1.5 (2026-09-14):** madurez de producción (planes de ACTUAR.md v1.4, ruta "crítico de código"): **rate-limiting propio** (`app/core/rate_limit.py`, cachetools + sliding window por IP+email, límites configurables por env, middleware 429 JSON, /health y /metrics sin límite; **11 tests en `test_rate_limit.py`** (incluye sliding window real y concurrencia)); **CORS endurecido** (warning en log si `*` en entorno no-dev, `allow_credentials` solo con orígenes concretos); **monitoreo** (`app/core/monitoring.py` + `prometheus-client`): middleware ASGI de requests/latencia por endpoint normalizado (UUID→`{id}`), contadores de negocio `pesajes_total{estatus,tier}` / `license_errors{tier,reason}` / `active_users{tier}` hooks en pesajes/auth, endpoint `GET /metrics` (8 tests en `test_monitoring.py`); **scripts de operaciones**: `scripts/backup.sh` (pg_dump -Fc + tar.gz de media + retención 30 días), `scripts/verify.sh` (Python/BD/`.env`/SECRET_KEY/API/systemd/LM), `scripts/install_cliente.sh` (`.env` + setup_db + migraciones + seed opcional + unidad systemd con rutas reales + verify); nuevas variables de `RATE_LIMIT_*`, `METRICS_ENABLED`, `BACKUP_*` en `config.py` y `.env.example`. **Tests backend → 106/106.**

**Cambios en v1.6 (2026-09-14):** **módulo de Dispositivos** para configurar y probar la conexión de las básculas (B7/REQ-NF-ARQ-004): los esquemas `BalanzaCreate`/`BalanzaOut` y el sync (`/catalogo/sync`) ahora exponen la configuración de hardware (`puerto_com`, `ip_address`, `puerto_tcp`, `protocolo`); **endpoint `POST /api/v1/balanzas/{id}/probar`** que construye el HAL (`get_scale_hal`) y devuelve diagnóstico `{balanza, conectado, hardware, protocolo, peso_kg, estable, detalle}` (400 si no hay configuración hardware, 404 si no existe, `conectado=false` si no hay lectura); frontend: entidad `Scale` con campos de hardware + `PruebaConexion`, nueva pantalla **Dispositivos** (listado de básculas con estado/config, botón rápido "Probar", detalle con formulario de conexión TCP/serial —solo ADMIN guarda—, prueba de conexión con resultado y **monitoreo en vivo** `ScaleMonitorWidget`), integrada en sidebar y navegación inferior. 6 tests nuevos backend + 9 tests nuevos frontend. **Tests backend → 112/112, frontend → 57/57.**

---

## 1. Resumen del sistema

BALANSOFT-WS es un **sistema de estación de pesaje industrial para camiones**, multi-empresa, con arquitectura **cliente-servidor**:

- **Backend**: API REST **FastAPI** (Python 3.12+, asíncrono) que expone `/api/v1/*`.
- **Frontend**: Aplicación **Flutter** (Dart) con BLoC, **offline-first** (sqflite + cola de sincronización).
- **Base de datos**: **PostgreSQL 15+** (BD de negocio `balansoft_ws`, independiente del License Manager).
- **Licencias**: integración con **BALANSOFT-LM (SGLB)** local vía HTTP, con verificación de firma **Ed25519** anti-fake-server.

### Módulos construidos

| Módulo           | Backend | Frontend | Descripción |
|------------------|:-------:|:--------:|-------------|
| Auth (JWT)       | ✅ | ✅ | Registro de empresa + admin, login, refresh token, logout, **forgot/reset de contraseña** |
| Pesaje           | ✅ | ✅ | Boletos de pesaje: entrada → salida → cierre → anulación |
| Flota            | ✅ | ✅ | Marcas, modelos de camión, camiones, remolques |
| Inventario       | ✅ | ✅ | Productos (maestra con kardex), almacenes, balanzas |
| Directorio       | ✅ | ✅ | Transportes, conductores, terceros (cliente/proveedor/ambos) |
| Kardex           | ✅ | ✅ | Movimientos 10 (ingreso) / 60 (despacho) + saldo a fecha de corte; **UI completa** (filtros, saldo acumulado, export PDF/Excel) |
| Sincronización   | ✅ | ✅ | Push/pull de pesajes offline, cola local con reintentos/fail, catálogos por `catalogo/sync`, sync automática por timer |
| Reportes         | ✅ | ✅ | Diario, mensual, por vehículo, saldo y detalle de kardex, **avanzados** (transportista, tercero, rango de peso, comparativo mensual) |
| Exportación      | ✅ | ✅ | Excel (`.xlsx`) de pesajes y de kardex (botón en UI de reportes) |
| Tickets PDF      | ✅ | ⚠️ API | Boleto PDF (ReportLab), marca de agua ANULADO |
| Auditoría        | ✅ | — | Middleware en `logs_sistema` + `auditoria` con escrituras en pesaje y catálogos |
| Health check     | ✅ | ✅ | `GET /api/v1/health` + badge ⬤ Online/○ Offline en dashboard (re-check 30 s) |
| Licencias LM     | ✅ | ✅ | Validación online (Ed25519), caché offline (30 min), **pantalla de administración (ADMIN)**: snapshot tier/vencimiento/uso + renovación, `GET /auth/license` |
| Fotos            | ✅ | ✅ | Boleto: multipart `imagenes/archivo` + vista en detalle; catálogo (camión/remolque/conductor): captura/carga por `files/upload`, miniaturas en listas |
| Peso en vivo     | ✅ | ✅ | Backend HAL (serial/TCP) `GET /weighing/scale/{balanza_id}/live`; frontend `ScaleApiClient` (API-first + fallback TCP) + `ScaleMonitorWidget` con `balanzaId`/descripción (formulario y cierre) |
| Dispositivos     | ✅ | ✅ | Configuración de conexión de básculas (TCP/serial: `puerto_com`, `ip_address`, `puerto_tcp`, `protocolo`), prueba de conexión `POST /balanzas/{id}/probar` y monitoreo en vivo (solo ADMIN guarda) |
| Simulador WS     | — | ✅ | Módulo "WS" en BSDD: báscula de entrada `:5555` y salida `:5556` (cliente-puerto del frontend) |
| Modo kiosk       | — | ✅ | Fullscreen sin bordes en producción (`window_manager`) |
| Tema claro/oscuro| — | ✅ | `ThemeController` persistido en SharedPreferences |

---

## 2. Stack tecnológico

| Capa          | Tecnología | Estado |
|---------------|-----------|:------:|
| Backend       | Python 3.12+, FastAPI (async), Pydantic v2, SQLAlchemy 2.0 async (asyncpg) | ✅ |
| Base datos    | PostgreSQL 15+ (producción y tests reales, `balansoft_ws_test`) | ✅ |
| Esquema       | `schema.sql` (esquema final idempotente) + `migrations/*.sql` versionadas (sin Alembic) | ✅ |
| Auth          | JWT access+refresh (python-jose HS256) + BCrypt (passlib) | ✅ |
| Licencias     | Cliente HTTP contra BALANSOFT-LM (SGLB), firma Ed25519, tiers DEMO/MONOPUESTA/CENTRAL | ✅ |
| PDF / Excel   | ReportLab (tickets PDF) / openpyxl (exportación Excel) | ✅ |
| Frontend      | Flutter/Dart, BLoC (flutter_bloc 8.1.3), dio, get_it, connectivity_plus, sqflite, flutter_secure_storage (tokens), window_manager (kiosk) | ✅ |
| Sync offline  | Tabla local `weighing_local` + `catalog_local`, cola `pendiente/sincronizado/intentos_sync/fallido` con reintentos configurables | ✅ |
| Deploy        | systemd (`balansoft-ws.service`) + `scripts/setup_db.sh` + `scripts/start_api.sh`; operaciones: `scripts/{backup.sh, verify.sh, install_cliente.sh}` | ✅ |
| Rutas de seguridad | Rate limiting propio (IP+email, sliding window), CORS restringido por env, `SECRET_KEY` verificada por `verify.sh` | ✅ |
| Hardware      | ✅ HAL de balanza en backend (`scale_hal.py`: serial RS-232/USB + TCP vía lectura de JSON del simulador BSDD); endpoint `GET /weighing/scale/{balanza_id}/live` para lectura de peso en vivo y `POST /balanzas/{id}/probar` para prueba de conexión (REQ-NF-ARQ-004, B7); módulo de Dispositivos en el frontend | ✅ |

---

## 3. Estructura del repositorio

```
BALANSOFT-WS/
├── AGENTS.md                  # Reglas del repo (stack canónico, requisitos trazables)
├── docs/
│   ├── PRD.md                 # Fuente de verdad del negocio
│   ├── ARCH.md, MODEL.md, UI-UX.md
│   └── legacy/DOCUMENTACION-BALANSOFT-WS.md   # Referencia paralela (NO autoritativa)
├── backend/
│   ├── app/
│   │   ├── main.py            # App FastAPI + CORS (hardened) + AuditMiddleware + RateLimit + Metrics + /metrics
│   │   ├── core/              # config, database, security, license_client, audit, scale_hal, rate_limit, monitoring
│   │   ├── api/dependencies.py# get_current_user/empresa, require_admin, require_catalog_manager
│   │   ├── api/v1/endpoints/  # archivos, auth, pesajes, catalogo, flota, inventario, directorio, sync, reports, exports
│   │   ├── models/__init__.py # Modelos SQLAlchemy (16 ORM de negocio; BD total: 23 tablas)
│   │   ├── schemas/__init__.py# DTOs Pydantic
│   │   └── services/          # weighing, catalog, sync, report, ticket, license, audit, password_reset
│   ├── schema.sql             # Esquema final de BD (PostgreSQL)
│   ├── migrations/            # 001_remolques_y_fotos, 002_spec_arquitectura, 003_reglas_negocio, 004_password_reset, 005_balanza_hardware
│   ├── scripts/               # setup_db.sh, seed_data.py, seed_simulacion.py, generate_signing_keys.py, start_api.sh, backup.sh, verify.sh, install_cliente.sh
│   ├── deploy/balansoft-ws.service
│   ├── .env.example           # Plantilla de configuración de producción (incluye RATE_LIMIT_*, METRICS_ENABLED, BACKUP_*)
│   └── tests/                 # 112 tests (pytest) sobre PostgreSQL real
└── frontend/
    ├── lib/
    │   ├── main.dart          # Entrada, DI, rutas, tema
    │   ├── core/              # config, constants, theme, utils, security (secure_storage), widgets
    │   ├── data/              # models, mappers, repositories, datasources (API + local sqflite)
    │   ├── domain/            # entities, repository interfaces, usecases
    │   ├── presentation/      # screens + BLoCs (auth, weighing, catalog, kardex, license, sync)
    │   └── injection.dart     # get_it DI
    └── test/                  # 52 tests (unit/widget) passing
```

---

## 4. Base de datos (`backend/schema.sql`)

BD de negocio separada **`balansoft_ws`**, PostgreSQL, todo con `id_empresa` (UUID) para multi-empresa. **23 tablas** en `schema.sql`:

| Tabla | Módulo | Notas |
|-------|--------|-------|
| `empresas` | Empresa | RIF único, licencia_key/tier/status/expira (caché del LM) |
| `usuarios` | Empresa | rol ADMIN/OPERADOR/SUPERVISOR, password BCrypt |
| `transportes` | Directorio | razon_social, código, contacto |
| `conductores` | Directorio | PK `cedula_dni` |
| `terceros` | Directorio | tipo CLIENTE/PROVEEDOR/AMBOS |
| `marcas` | Flota | único (empresa, nombre) |
| `modelos_camion` | Flota | marca_id, capacidad, ejes |
| `camiones` | Flota | placa única (empresa), tara_habitual, modelo, transporte |
| `remolques` | Flota | placa, tipo_remolque, tara_habitual |
| `productos` | Inventario | maestra: es_kardex, tolerancia, peso_unidad, densidad, unidad TON/KG/M3/UN |
| `almacenes` | Inventario | stock_actual_ton |
| `balanzas` | Inventario | solo ADMIN puede gestionar |
| `boletos_pesaje` | Transaccional | núcleo del pesaje (ver §5) |
| `imagenes_pesaje` | Transaccional | placa/vehiculo/documento/etc., ON DELETE CASCADE |
| `kardex` | Kardex | ID 10 ingreso / 60 despacho, positivo/negativo según rango 01-49 / 50-99 |
| `sync_queue` | Sync | cola de sincronización entidad/operación/payload JSONB |
| `sync_logs` | Sync | push/pull/full |
| `auditoria` | Auditoría | historia de usuarios/entidad/IP |
| `logs_sistema` | Auditoría | escribido por `AuditMiddleware` |
| `password_reset_tokens` | Auth | token_hash BCrypt, expira, usado (migración 004) |
| `configuraciones` / `parametros_sistema` | Config | pares clave-valor |

**Migraciones aplicables en orden**: `001` (remolques + fotos + códigos), `002` (marcas/modelos/camiones + renombrado `pesajes→boletos_pesaje`), `003` (reglas MODEL: estados 4, numero_boleto único TA-, cálculos PTE/..PDV, kardex, maestra productos), `004` (tabla `password_reset_tokens` para olvido/reset de contraseña).

---

## 5. Núcleo de pesaje (MODEL.md)

### Estados del boleto (4)

`PENDIENTE → CERRADO / MODIFICADO → ANULADO`, más alias legacy normalizados por `WeighingService.normalizar_estado` (`weighing_service.py:46-62`):

| Legacy | Normaliza a |
|--------|-------------|
| ABIERTO / AUTOMÁTICO | PENDIENTE |
| COMPLETADO / CERRADO | CERRADO |
| ANULADO | ANULADO |

### Número de boleto

Secuencial `TA-00000001` (prefijo y dígitos configurables en `settings.boleto_prefix` / `boleto_digitos`), **único y nunca se reutiliza** (`generar_numero_boleto`, `weighing_service.py:85-96`). Si el cliente offline no trae número, `SyncService._asignar_numero_boleto` lo genera al hacer push.

### Cálculos firmados

`WeighingService._calcular` implementa:

- **PTE** = PEC + PER (peso total entrada)
- **PTS** = PSC + PSR (peso total salida)
- **PNT** = PTE − PTS (peso neto total)
- **PND** = peso neto declarado (guía)
- **PDF** = PNT − PND (diferencia ±)
- **PDV** = PDF / PND (porcentaje de desviación)
- Campos legacy `peso_bruto`/`peso_tara` (max/min de PTE/PTS) y `diferencia_peso` mantenidos por compatibilidad.
- **Litros** = PNT / densidad cuando hay densidad (`_apply_litros`).

### Reglas de negocio operativas

1. Un camión **no puede tener dos boletos PENDIENTE** a la vez (HTTP 400 con número del pendiente).
2. **Pesaje manual** (peso tecleado) solo ADMIN/SUPERVISOR (403 si otro rol) — `_PERMISOS_PESO_MANUAL` en `pesajes.py:41`.
3. **Anulación** solo ADMIN/SUPERVISOR (`_PERMISOS_ANULACION`), con **motivo obligatorio** (mín. 10 caracteres vía schema). Si estaba PENDIENTE libera el vehículo. El número de boleto no se reutiliza.
4. **Modificación** de un boleto CERRADO lo pasa a **MODIFICADO**; un ANULADO no se puede modificar.
5. **Creación inline (get-or-create)**: vehículo por placa, y por nombre/razón social transporte, conductor, producto, almacén, balanza, remolque y tercero — el operador no necesita pre-cargar catálogos para operar.

### Kardex

- Al **cerrar** el boleto se registra un movimiento: `PNT ≥ 0` → **INGRESO POR BASCULA (ID 10)**; `PNT < 0` → **DESPACHO POR BASCULA (ID 60)**. Solo para productos con `es_kardex=true` (`_registrar_kardex`, `weighing_service.py:277`).
- Al **anular** un boleto cerrado se genera el **inverso** (10↔60) conservando historia, sin borrar asientos (`_registrar_kardex_inverso`, `weighing_service.py:312`).
- **Saldo a fecha de corte** = Σ positivos (ID 01-49) − Σ negativos (ID 50-99), filtrado por fecha/producto/almacén (`ReportService.kardex_saldo`).
- Los ANULADOS **no cuentan** en reportes ni kardex.

---

## 6. API REST (`/api/v1/*`)

Prefijo general, JWT Bearer obligatorio salvo `auth/register`, `auth/login`, `auth/refresh-token`, `auth/forgot-password`, `auth/reset-password` y `health`. Se expone Swagger en `/docs` (si `api_docs_enabled`).

### Autenticación — `auth.py`

| Método | Ruta | Funcionalidad |
|--------|------|---------------|
| POST | `/auth/register` | Alta empresa + primer admin. Valida licencia contra el LM, cachea tier/status. Devuelve access+refresh, user, empresa. |
| POST | `/auth/login` | Login + datos de hardware; valida licencia online contra el LM (403 si inválida, 503 si el LM no responde); guarda tier/status/expira en la empresa. |
| POST | `/auth/forgot-password` | Solicita restablecimiento de contraseña: genera token aleatorio, guarda `token_hash` (BCrypt) con expiración (15 min), envía email (o lo devuelve en `DEBUG_MODE`). |
| POST | `/auth/reset-password` | Cambia la contraseña con token válido no usado: actualiza BCrypt y marca el token como usado (400 si expirado/usado). |
| POST | `/auth/validate-license` | Validación en tiempo real de la licencia de la empresa (autenticado). |
| POST | `/auth/refresh-token` | Emite nuevo par access+refresh a partir del refresh (tipo `refresh`). |
| POST | `/auth/logout` | Stateless: registra y descarta (auditoría). |

### Pesaje — `pesajes.py`

| Método | Ruta | Funcionalidad |
|--------|------|---------------|
| POST | `/weighing/create` | Alta de boleto (entrada). Valida licencia online; limita DEMO (`DEMO_MAX_RECORDS`); verifica peso manual; 400 si el camión ya tiene pendiente. |
| POST | `/weighing/close/{boleto}` | Cierre (salida): recalcula PTE/PTS/PNT/PDF/PDV, aplica litros, genera kardex, estado → CERRADO. |
| PUT | `/weighing/{boleto}/anular` | Anula con motivo; kardex inverso; estado → ANULADO. |
| PUT | `/weighing/{boleto}` | Modifica documento/flete/costo/observaciones/PND; recalcula si cambió el declarado; CERRADO→MODIFICADO. |
| GET | `/weighing/pendientes` | Boletos abiertos sin salida en planta. |
| GET | `/weighing/list` | Historial filtrable por fechas/placa/estado, paginado (skip/limit ≤1000). |
| GET | `/weighing/boleto/{boleto}` | Detalle de un boleto. |
| GET | `/weighing/{boleto}/pdf` | Descarga el ticket PDF. |
| GET/POST | `/weighing/{boleto}/imagenes` | Listar (devuelve `url` `/media/...`) / registrar metadatos de foto. |
| POST | `/weighing/{boleto}/imagenes/archivo` | Sube la foto (multipart `file` + `tipo`: `placa/vehiculo/documento/entrada/salida/otros`), la guarda en `media/{boleto}/` y registra la URL. |
| DELETE | `/weighing/{boleto}/imagenes/{id_imagen}` | Eliminar foto de un boleto de la misma empresa. |
| POST | `/files/upload` | Sube una foto genérica de catálogo (multipart `file` + `carpeta` opcional); devuelve `{url: "/media/<carpeta>/<archivo>"}`. `media/` se sirve estático en `/media` (StaticFiles). |

### Flota — `flota.py`

CRUD por empresa de **marcas** (`/marcas`), **modelos_camion** (`/modelos-camion`), **camiones** (`/camiones` + búsqueda `/camiones/buscar?placa=`), **remolques** (`/remolques`). Crear/editar/borrar requiere ADMIN o SUPERVISOR (`require_catalog_manager`). Borrar una marca con modelos asociados devuelve 400.

### Inventario — `inventario.py`

CRUD de **productos** y **almacenes** (manager) y de **balanzas** (solo ADMIN con `require_admin`). El CRUD de balanzas incluye configuración de hardware (`puerto_com`, `ip_address`, `puerto_tcp`, `protocolo`).

| Método | Ruta | Funcionalidad |
|--------|------|---------------|
| POST | `/balanzas/{id}/probar` | Prueba la conexión de hardware de la báscula (construye el HAL y lee el peso). Devuelve `{balanza, conectado, hardware, protocolo, peso_kg, estable, detalle}`; 400 si no hay configuración de hardware, 404 si no existe (autenticado, módulo Dispositivos). |

### Directorio — `directorio.py`

CRUD de **transportes**, **conductores** (PK cédula) y **terceros** (manager).

### Catálogo / sincronización offline — `catalogo.py` y `sync.py`

| Método | Ruta | Funcionalidad |
|--------|------|---------------|
| GET | `/catalogo/sync` | Devuelve TODOS los catálogos de la empresa en un solo payload (camiones, remolques, marcas, modelos, transportes, conductores, productos, almacenes, balanzas, terceros + `server_time`). |
| POST | `/sync/push` | Procesa lote de pesajes offline (upsert determinístico por `boleto`, normaliza estados legacy, asigna número si falta). |
| GET | `/sync/status` | Pendientes no sincronizados, última sync, `max_offline_dias`, si usa licencia DEMO. |
| GET | `/sync/pull` | Últimos 500 pesajes sincronizados de la empresa (reconstrucción de caché local). |

### Reportes — `reports.py`

| Método | Ruta | Funcionalidad |
|--------|------|---------------|
| GET | `/reports/daily?fecha=` | Totales diarios (sin ANULADOS), desglose por producto. |
| GET | `/reports/monthly?year=&month=` | Totales mensuales + conteo por día. |
| GET | `/reports/vehicle/{placa}?date_from=&date_to=` | Pesajes, peso total y promedio del vehículo. |
| GET | `/reports/kardex/saldo` | Saldo de kardex a fecha de corte, opcional por producto/almacén. |
| GET | `/reports/kardex/detalle` | Movimientos de kardex del período con saldo acumulado (PRD §9.6). |
| GET | `/reports/export/excel` | Exporta pesajes (no anulados) a `.xlsx` con encabezados formateados y resumen. |
| GET | `/reports/export/kardex/excel` | Exporta movimientos de kardex del período a `.xlsx`. |
| GET | `/reports/export/kardex/pdf` | Exporta movimientos de kardex del período a PDF. |

### Health

| Método | Ruta | Funcionalidad |
|--------|------|---------------|
| GET | `/api/v1/health` | `{status, version, timestamp}` en UTC. |

### Peso en vivo — `pesajes.py` (B7 / REQ-NF-ARQ-004)

| Método | Ruta | Funcionalidad |
|--------|------|---------------|
| GET | `/weighing/scale/{balanza_id}/live` | Lee el peso en tiempo real desde el hardware configurado en la balanza (serial TCP o RS-232). Devuelve `{peso_kg, estable, balanza, hardware, timestamp}`. Si la balanza no tiene IP/puerto configurado → 400; si no pertenece a la empresa → 404. |

---

## 7. Seguridad

### Generación y verificación de tokens (`app/core/security.py`)

- Passwords hasheados con **BCrypt** (`passlib`, `pwd_context`).
- **JWT HS256** con `SECRET_KEY` del `.env`: access token (30 min, claim `sub` + `rol`) y refresh token (7 días, claim `type=refresh`).
- Login/refresh descartan tokens stateless; el `verify_token` devuelve `None` si expiró/inválido.

### Autorización (`app/api/dependencies.py`)

- `get_current_user`: valida Bearer y que el usuario esté activo.
- `get_current_empresa`: resuelve la empresa del JWT (tenancy real por `id_empresa`).
- `require_catalog_manager`: ADMIN/SUPERVISOR para CRUD de catálogos.
- `require_admin`: solo ADMIN (balanzas).
- Pesaje manual y anulación: checks por rol en el router de pesajes.

### Auditoría (`app/core/audit.py`)

`AuditMiddleware` registra automáticamente en `logs_sistema` cada petición **write** (POST/PUT/PATCH/DELETE) con método, path, status, duración ms y query. Excluye health/docs. No bloquea la petición si falla (non-critical).

---

## 8. Integración con licencias (BALANSOFT-LM)

`app/core/license_client.py` implementa el flujo **anti-fake-server**:

1. `POST {LM}/token` con `license_key` → obtiene Bearer token.
2. `POST {LM}/validate` con hardware + `product_code` + Bearer.
3. Verifica **firma Ed25519** de los campos `SIGNED_FIELDS` (valid, status, expires_at, tier, plan_type, features, server_time, nonce) contra `LICENSE_PUBLIC_KEY`. Firma inválida → `LicenseSignatureError`.
4. **Anti-replay**: `server_time` con drift > 300 s se rechaza.
5. Cliente síncrono llamado desde dependencias async vía `asyncio.to_thread`.

Tiers soportados: **DEMO** (max `DEMO_MAX_RECORDS=10` registros), **MONOPUESTA** (1 usuario), **CENTRAL** (10). Service de orquestación: `app/services/license_service.py`. La creación de pesajes **bloquea** (503) si el LM no responde, y rechaza (403) licencias inválidas/expiradas. El login cachea tier/status/expira en `empresas`.

**Frontend**: `license_repository` valida contra `/auth/validate-license` enviando `licencia_key` + `hardware_id` (mac, marca, modelo, OS según plataforma vía `device_info.dart`), cachea 30 min en SharedPreferences y refresca cada 24 h cuando hay conexión.

---

## 9. Frontend Flutter (`frontend/`)

### Características generales

- App `balansoft_ws` 1.0.0, SDK Dart ≥3.2.0, Material 3, target web/desktop/mobile (Linux y Android configurados).
- **DI** con `get_it`, **estado** con BLoC/Cubit.
- **Seguridad de tokens**: `access_token`/`refresh_token`/licencia en **`flutter_secure_storage`** (`secure_storage_service.dart`), con migración one-shot desde SharedPreferences; SharedPreferences solo guarda `tema`, `ultimo_email`, `hardware_id`.
- **Modo kiosk**: `EnvConfig.kioskMode` aplica fullscreen sin bordes vía `window_manager` cuando `APP_ENV=production`.
- **Red** con `dio` (timeouts 15/30 s); interceptor 401 que hace **refresh token** automático y reintenta la petición; `ApiClient.health()` inyectable para el badge de salud.
- **Tema claro/oscuro/sistema** persistente (`ThemeController`, clave `balansoft.tema`), paleta `SwsColors`.
- Utilidades numéricas con locale `es_VE` (kg/toneladas/%), parser robusto de `Decimal` de FastAPI.
- Conversión de TZ a local **solo** en capa de presentación (fechas llegan en UTC, se formatean con `intl`).
- **Peso en vivo por TCP**: `ScaleTcpClient` (ChangeNotifier, `Socket.connect` con timeout 5 s, reconexión hasta 3 intentos, parsea líneas JSON `{"weight_kg":…,"status":"stable"}`) + `ScaleMonitorWidget` (peso en vivo, estado Estable/Inestable/Desconectado, botón "Tomar peso"). Config de IP/puerto en Ajustes → "Báscula / Dispositivo" (persistida en `LocalStorage.getScaleConfig`).
- **Fotos**: `PhotoPickerField` (cámara/galería vía `image_picker`, hasta 4, miniaturas removibles, emite `PhotoCaptured(bytes, nombre)`). En pesaje sube todas las fotos tras crear el boleto vía `ApiClient.uploadImage` (camión → `tipo=vehiculo`, remolque → `tipo=otros`). En catálogos (camión/remolque/conductor) los campos `foto_url`/`foto_real_url` pasaron de pedir una URL a ser captura de foto real (`CatalogFieldType.foto`), subida por `ApiClient.uploadPhotoFile` y mostrada en miniatura en las listas.
- **Guardado de archivos**: `SaveFileUtils` guarda reportes/tickets/kardex en Descargas (fallback Documentos) en subcarpetas `reportes/`, `tickets/`, `kardex/` y muestra la ruta exacta en SnackBar. Ajustes → "Archivos" muestra y copia la carpeta de guardado (`LocalStorage.getDescargasDir`).
- **Responsive móvil**: pantallas de Reportes y Kardex usan tarjetas en pantallas estrechas y tablas en escritorio; fix del `NavigationBar` (destinos y `_index` alineados).

### Pantallas (12)

| Pantalla | Ruta (app) | Descripción |
|----------|-----------|-------------|
| Login | `/login` | Email + password + datos de hardware; al autenticar → `/dashboard`. |
| Registro | `/register` | Alta de empresa (nombre + RIF) y primer usuario admin; licencia `WS-XXXX-...` opcional. |
| Olvido de contraseña | `/forgot-password` | Formulario email → `POST /auth/forgot-password` (real, no mock). |
| Restablecer contraseña | `/reset-password` | Token + nueva contraseña → `POST /auth/reset-password`. |
| Dashboard | `/dashboard` | KPIs del día, vehículos en planta, **pesajes fallidos por reintentos**, **badge de salud del backend** ⬤/○, últimos 5 pesajes, FAB nuevo pesaje, pull-to-refresh = sync. |
| Pesajes | (shell) | Lista con filtros por placa/fechas/estado/producto/cliente. |
| Detalle de pesaje | `/weighing/detail` | Detalle completo, **Cerrar Pesaje** si abierto, **Anular** solo admin/supervisor, **galería de fotos** del boleto (ampliable). |
| Formulario de pesaje | (dialog/screen) | Autocompletado-creable de todos los catálogos; peso manual solo ADMIN/SUPERVISOR; **báscula de entrada en vivo** (`ScaleMonitorWidget`) y **fotos de camión y remolque** tomadas/cargadas. |
| Catálogos | (shell: Flota/Inventario/Directorio) | CRUD genérico declarativo desde `catalog_resources.dart`; campos de foto de camión/remolque/conductor con captura real y miniaturas; ocultos para OPERADOR. |
| Reportes | (shell) | Diario y mensual con KPIs y desglose + **botón Exportar Excel** (guarda en Descargas/`reportes` y muestra la ruta); layout responsive móvil. |
| Kardex | (shell: CONSULTAS, solo ADMIN/SUPERVISOR) | Filtros producto/almacén/fechas, movimientos con saldo acumulado, saldo actual y export PDF/Excel a Descargas/`kardex` con ruta mostrada; responsive móvil. |
| Configuración | `/settings` | Perfil/empresa, **Báscula/Dispositivo** (IP y puerto), **Archivos** (ruta de guardado copiable), licencia (placeholder), sync (placeholder), tema, acerca de, logout. |

### Offline-first

- BD local `balansoft_ws.db` (sqflite, **v4**) con `weighing_local` (flags `sincronizado/pendiente/intentos_sync/fallido`) y `catalog_local` (`extra_json`).
- `WeighingRepository`: cada operación intenta API primero; si falla, persiste local con `pendiente=1`.
- Reintentos configurables: `AppConstants.maxSyncRetries` (3) — al agotarlos el pesaje pasa a **fallido** (`fallido=1`) y deja de reintentarse; la sección del dashboard los lista.
- `SyncWeighingsUseCase` recorre pendientes y hace push; los que fallan quedan en cola e incrementan `intentos_sync`.
- `SyncBloc` con **timer periódico** (`syncIntervalMinutes`, 2 min) y verificación de health cada `healthCheckSeconds` (30 s).
- `CatalogRepository.syncCatalogs`: baja `/catalogo/sync` y reemplaza `catalog_local` en transacción; si falla, usa caché.
- Estados roles: `isAdmin/isSupervisor/isOperador` (`user.dart`).

> **Resuelto en v1.1**: los tokens ya se guardan en `flutter_secure_storage` (no SharedPreferences); `signature_verifier.dart` eliminado (la confianza la valida el backend); modo kiosk implementado.

---

## 10. Tickets / PDF

`app/services/ticket_service.py` genera el boleto con **ReportLab** (platypus):

- Encabezado: "Boleto de Pesaje", número, fecha/hora (dd/mm/aaaa HH:mm), camión, remolque.
- Tabla: documento, PTE, PTS, PNT, PND, PDF, PDV (% desviación), densidad, unidades, litros, estado.
- Observaciones y firma.
- Si el boleto está **ANULADO**: marca de agua "ANULADO" rotada (rojo translúcido) en cada página + motivo en rojo.
- Fuente DejaVu registrada para soportar tildes/ñ.

---

## 11. Configuración (`.env`)

Ver plantilla completa en `backend/.env.example`. Variables vigentes:

`APP_ENV`, `DEBUG_MODE`, `API_DOCS_ENABLED`, `LOG_LEVEL`, `LOG_FILE`, `DATABASE_URL` (asyncpg), `DATABASE_URL_SYNC` (psycopg2), `LICENSE_API_URL`, `LICENSE_ADMIN_URL`, `LICENSE_PUBLIC_KEY` (Ed25519 en una línea), `LICENSE_PRODUCT_CODE`, `API_HOST`, `API_PORT=8000`, `API_RELOAD`, `API_WORKERS`, `SECRET_KEY`, `ALGORITHM=HS256`, `ACCESS_TOKEN_EXPIRE_MINUTES`, `REFRESH_TOKEN_EXPIRE_DAYS`, `CORS_ORIGINS`, `SYNC_INTERVAL_MINUTES`, `MAX_OFFLINE_DAYS`, `MAX_SYNC_RETRIES`, `DEMO_MAX_RECORDS`, `MONOPUESTA_MAX_USERS`, `CENTRAL_MAX_USERS`, `MEDIA_DIR=media`, `MAX_IMAGE_BYTES=10485760`, `ALLOWED_IMAGE_TYPES` (jpeg/png/webp), `PASSWORD_RESET_EXPIRE_MINUTES=15`, `PASSWORD_RESET_URL_BASE` (enlace de la app), `SMTP_ENABLED=false` (si false, el enlace se registra en el log del servidor), `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`. Además, en v1.5: `RATE_LIMIT_ENABLED`, `RATE_LIMIT_LOGIN`, `RATE_LIMIT_REGISTER`, `RATE_LIMIT_PASSWORD`, `RATE_LIMIT_WINDOW`, `RATE_LIMIT_TRUST_PROXY`; `METRICS_ENABLED`; `BACKUP_DIR`, `BACKUP_RETENTION_DAYS` (para `scripts/backup.sh`).

Defaults de desarrollo en `app/core/config.py` (BD local `balansoft_ws`, LM en `localhost:8080`, prefijo de boleto `TA-`, 8 dígitos).

---

## 12. Scripts y despliegue

| Script | Uso |
|--------|-----|
| `scripts/setup_db.sh` | `instalar` (schema.sql), `aplicar-migraciones` (migrations/*.sql en orden), `seed` (datos demo). Crear la BD `balansoft_ws` si no existe. |
| `scripts/seed_data.py` | Empresa Demo (`admin@balansoft.demo` / `demo1234`) + catálogos base (camiones ABC123/XYZ789, conductores, transporte, cemento/arena, almacén, balanza, cliente, remolque). |
| `scripts/seed_simulacion.py` | Datos de simulación de pesaje. |
| `scripts/generate_signing_keys.py` | Genera par Ed25519 para la firma del LM. |
| `scripts/start_api.sh` | `uvicorn app.main:app --reload --host $API_HOST --port $API_PORT`. |
| `deploy/balansoft-ws.service` | systemd: 4 workers uvicorn en `/opt/balansoft-ws/backend`, usuario `balansoft`, `PrivateTmp`, `NoNewPrivileges`. |

**Arranque manual** (módulo correcto es `app.main`, no `main`):

```bash
cd backend
uv sync                                   # si hace falta
uv run uvicorn app.main:app --reload      # http://127.0.0.1:8000, docs en /docs
```

---

## 13. Tests

**Backend** (pytest, BD PostgreSQL real `balansoft_ws_test`): **112 tests — 112 en verde**. Los 3 fallos preexistentes (kardex con `P-01` no-UUID y conductor duplicado) fueron corregidos en v1.3; 8 tests nuevos de HAL de balanza en `test_scale_hal.py` (factory TCP/serial, servidor TCP, endpoint live); **7 tests nuevos de reportes avanzados** en `test_report_service.py` (transportista, tercero, rango de peso, comparativo mensual) + 1 test del snapshot de licencia `GET /auth/license` en `test_endpoints.py`. En v1.5: **11 tests del rate limiter** (`test_rate_limit.py`, hermético sin BD: /health y /metrics sin límite, 429 por IP/email, body legible tras middleware, XFF con `trust_proxy`, **sliding window real**, **concurrencia** (5/5 con `asyncio.gather`), contadores por email) y **8 tests de monitoreo** (`test_monitoring.py`: normalización de paths, middleware de contadores, contadores de negocio, serialización `/metrics`). En v1.6: **6 tests del módulo de dispositivos** en `test_endpoints.py` (`TestDispositivosEndpoints`: crear balanza con hardware, probar sin hardware → 400, probar no encontrada → 404, probar conectado con FakeHAL monkeypatch, probar desconectado, sync incluye campos de hardware).

| Archivo | Cubre |
|---------|-------|
| `test_weighing_service.py` | Creación/cierre/anulación, bloqueo de doble pendiente, estados, número secuencial, kardex e inverso, límite DEMO. |
| `test_weighing_calculos.py` | Cálculos PTE/PTS/PNT/PDF/PDV y litros. |
| `test_endpoints.py` | Endpoints con auth, permisos de rol (peso manual/anulación), aislamiento por empresa, snapshot de licencia. |
| `test_audit_service.py` | Escrituras en `auditoria` para CREATE/ANULAR/UPDATE con detalle y `campos_modificados`. |
| `test_password_reset.py` | forgot/reset: token creado, password actualizado, token expirado/usado → 400. |
| `test_report_service.py` | Reportes diario/mensual/vehículo/saldo kardex, detalle de kardex (`TestKardexDetalle`) y **avanzados** (`TestTransportista`, `TestTercero`, `TestPesoRango`, `TestComparativoMensual`). |
| `test_ticket_service.py` | Generación del PDF y marca de agua ANULADO. |
| `test_rate_limit.py` | Rate limiter (v1.5): /health y /metrics sin límite, 429 por IP, claves separadas por email, body legible post-middleware, X-Forwarded-For con `rate_limit_trust_proxy`. |
| `test_monitoring.py` | Monitoreo (v1.5): normalización de paths (UUID/IDs → `{id}`), middleware de contadores/latencia, contadores de negocio (pesajes/license_errors), serialización Prometheus. |
| `test_endpoints.py` (dispositivos) | Módulo de dispositivos (v1.6): crear balanza con campos de hardware, probar sin configuración → 400, probar inexistente → 404, probar conectado/desconectado con `FakeHAL` monkeypatch, verificación de hardware en `catalogo/sync`. |

**Frontend** (`flutter test`, ejecutado): **57/57 en verde**. Unitarios en `test/unit/` (weighing, num_parser, catalogs con tests de `Scale` hardware/`PruebaConexion`, number_utils, weighing_bloc, secure_storage, kiosk_mode, sync_retries, health, export_excel, kardex_repository, kardex_bloc) + widget test (`weighing_detail_screen_test.dart`). `flutter analyze` limpio (sin warnings/errores; 12 infos preexistentes en temas de estilo).

**Simulador BSDD** (`/home/yohander/Documentos/BSDD`): `flutter analyze` sin warnings/errores y `flutter test` **27/27 en verde** tras añadir el módulo WS (básculas de entrada/salida).

Comandos canónicos: `uv run pytest -q`, `uv run ruff check app tests`, `uv run mypy tests/` (backend); `flutter test`, `flutter analyze`, `flutter build linux --release` (frontend). Build de producción verificado: `build/linux/x64/release/bundle/balansoft_ws`.

---

## 14. Estado general y pendientes detectados

**Lo construido y funcional**: API completa multi-empresa con JWT, pesaje con reglas MODEL (estados, cálculos, kardex, número secuencial), CRUD de flota/inventario/directorio, olvido/reset de contraseña, sincronización offline push/pull con reintentos y marca de fallidos, reportes (diario/mensual/vehículo/kardex + avanzados transportista/tercero/rango de peso/comparativo mensual), exportación Excel con UI y guardado en Descargas, tickets PDF, fotos de boleto y de catálogos (captura/carga y visualización), peso en vivo por TCP + HAL de balanza en backend (serial/TCP) con endpoint `/weighing/scale/{id}/live` integrado al frontend (`ScaleApiClient` API-first con fallback TCP), administración de licencias (ADMIN) en backend y frontend, auditoría en `auditoria` + `logs_sistema`, health check, licencias con verificación Ed25519 y OpenAPI documentado con tags; frontend Flutter con pantallas (incluye Kardex completo, badge de salud, galería de fotos, monitor de báscula, **módulo de Dispositivos** y sección de reportes avanzados), BLoC, offline-first con sync automática por timer, tema persistente y modo kiosk; módulo de básculas WS en el simulador BSDD; pruebas E2E (`integration_test`) con Keys de UI. En v1.5 (madurez de producción): rate-limiting con 429 JSON, CORS endurecido por env, métricas Prometheus en `GET /metrics` con contadores de negocio, scripts de backup/verificación/instalación y plantilla `.env.example` ampliada. En v1.6: módulo de Dispositivos para configurar y probar la conexión de básculas (TCP/serial, prueba de conexión con diagnóstico, monitoreo en vivo, 6 tests backend + 9 tests frontend).

**Brechas resueltas (v1.1)**:

| Brecha | Resuelta | Evidencia |
|--------|----------|-----------|
| B1 · Tokens en `SharedPreferences` | ✅ `flutter_secure_storage` (T1.1) | `frontend/lib/core/security/secure_storage_service.dart` + migración one-shot en `injection.dart` |
| B2 · `signature_verifier.dart` código muerto | ✅ eliminado (T1.2) | `signature_verifier.dart` ya no existe; claves JWT por backend con BCrypt |
| B3 · Olvido de contraseña mock | ✅ endpoint + UI (T1.3) | `backend/app/services/password_reset_service.py`, `forgot-password`/`reset-password`, `reset_password_screen.dart` |
| B4 · Modo kiosk | ✅ fullscreen (T2.1) | `window_manager` + `EnvConfig.kioskMode` |
| B5 · Tabla `auditoria` sin escrituras | ✅ pesaje + catálogos (T2.2) | `backend/app/services/audit_service.py` + caller en pesajes y catálogos |
| B6 · `max_sync_retries`/`SYNC_INTERVAL_MINUTES` sin uso | ✅ consumidos (T2.3) | `AppConstants.{maxSyncRetries,syncIntervalMinutes}`, `pushWeighing`/intentos/`fallido`, `SyncBloc` con timer |
| M1 · Health check frontend | ✅ (T3.1) | `GET /api/v1/health` + badge ⬤ Online/○ Offline en dashboard (re-check 30 s) |
| M2 · Documentación legacy | ✅ (T3.2) | movida a `docs/legacy/DOCUMENTACION-BALANSOFT-WS.md` con header NO AUTORITATIVO |
| M3 · UI exportación Excel | ✅ (T3.3) | botón en `reports_screen.dart` (diario/mensual) |
| M4 · UI Kardex completa | ✅ (T3.4) | `kardex_screen.dart` + BLoC + `GET /reports/kardex/detalle` + exports `kardex/{excel,pdf}` |
| B7 · **HAL de balanza en backend** | ✅ (v1.3/v1.6) | `app/core/scale_hal.py` (ScaleHAL ABC, SerialScaleHAL, TcpScaleHAL + factory); `GET /weighing/scale/{id}/live` + `POST /balanzas/{id}/probar`; migración `005_balanza_hardware`; esquemas `BalanzaCreate`/`BalanzaOut` con campos de hardware; módulo Dispositivos (frontend); 8 tests HAL + 6 tests dispositivos |
| B8 · **HAL en el frontend** | ✅ (v1.4) | `ScaleApiClient` (API-first vía `GET /weighing/scale/{id}/live` + fallback TCP), `ScaleMonitorWidget` con `balanzaId`/descripción, configuración de fallback desde Ajustes |
| B9 · **Pantalla de licencias (ADMIN)** | ✅ (v1.4) | `GET /api/v1/auth/license` (snapshot tier/status/expiración/key enmascarada/uso DEMO) + `license_admin_screen.dart` (renovación vía `validate-license`, limpieza de caché, solo ADMIN) |
| B10 · **Reportes avanzados** | ✅ (v1.4) | `GET /reports/{transportista,tercero,peso-rango,comparativo-mensual}` + sección "Avanzados" en `reports_screen.dart`; 7 tests en `test_report_service.py` |
| B11 · **Pruebas E2E** | ✅ (v1.4) | `integration_test/pesaje_flow_test.dart` (login → nuevo pesaje) con Keys (`email_field`, `placa_field`, `peso_entrada_field`, `guardar_entrada_button`, `new_weighing_fab`); requiere backend sembrado |
| B12 · **OpenAPI ampliado** | ✅ (v1.4) | `main.py`: summary, description con trazabilidad REQ-NF-, `openapi_tags` por módulo, contact; 60 paths verificados en `/openapi.json` |
| B13 · **Rate limiting** | ✅ (v1.5) | `app/core/rate_limit.py` (cachetools + sliding window), clave IP+email por endpoint auth, límites por env (`RATE_LIMIT_*`), 429 JSON con `Retry-After`, `/health` y `/metrics` sin límite; **11 tests** (incl. sliding window real y concurrencia) |
| B14 · **Monitoreo /metrics** | ✅ (v1.5) | `app/core/monitoring.py` (prometheus-client): middleware ASGI requests/latencia por endpoint normalizado (UUID→`{id}`), contadores `pesajes_total{estatus,tier}` / `license_errors{tier,reason}` / `active_users{tier}` con hooks en pesajes/auth, endpoint `GET /metrics`; 8 tests |
| B15 · **CORS endurecido** | ✅ (v1.5) | Warning en log si `'*'` en entorno no-dev; `allow_credentials` solo con orígenes concretos (CORSMiddleware no envía credenciales con `*`) |
| B16 · **Scripts de operaciones** | ✅ (v1.5) | `scripts/backup.sh` (pg_dump `-Fc` + `media/` tar.gz + retención), `scripts/verify.sh` (Python/BD/`.env`/`SECRET_KEY`/API/systemd/LM), `scripts/install_cliente.sh` (.env + setup_db + migraciones + seed opcional + unidad systemd + verify) |

**Pendientes futuros (aceptados)**:

1. Suites frontend/BSDD: `flutter test` (52/52) y `flutter analyze` limpio (12 infos preexistentes); BSDD: `flutter test` (27/27) y `flutter analyze` limpio (re-ejecutar tras cambios en WS).
2. Pruebas E2E en CI: requieren backend + PostgreSQL sembrados (`scripts/seed_data.py`) en el entorno de ejecución (`flutter test integration_test`).
3. Madurez de producción restante de ACTUAR.md v1.4 (requiere entorno/cliente, no es código): pruebas con balanza real (parsers Toledo/Rice Lake/Sartorius en `scale_hal.py`), pruebas de latencia/red y volumen (seed 50k boletos), HTTPS/TLS con nginx, manuales de usuario con capturas y proceso de soporte (ticketing); CI/CD y automatización de backups del LM.

---

## 15. Referencias

- `AGENTS.md` — reglas del repo, stack canónico y requisitos trazables (REQ-FN / REQ-NF / AR / INT / UX).
- `docs/PRD.md` — fuente de verdad del negocio.
- `docs/MODEL.md` — formato operativo de pantalla y cálculos (estados, kardex 10/60, PTE..PDV).
- `docs/ARCH.md` — decisiones de arquitectura.
- `docs/UI-UX.md` — requisitos de interfaz.
- `CHANGELOG.md` — versionado de esta iteración (v1.1.0).
- ⚠️ `docs/legacy/DOCUMENTACION-BALANSOFT-WS.md` — paralelo NO autoritativo (especificaciones históricas .NET/WinForms que deben reinterpretarse como FastAPI/Flutter).