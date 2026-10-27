# AGENTS.md — BALANSOFT-WS

Sistema de estación de pesaje industrial multi-empresa: **backend FastAPI + frontend Flutter + panel del proveedor**. **Idioma oficial: español**.

---

## Comandos canónicos

| Comando                                                                         | Lugar       | Notas                                                                                       |
|---------------------------------------------------------------------------------|-------------|---------------------------------------------------------------------------------------------|
| `uv sync`                                                                       | `backend/`  | Stack uv (`pyproject.toml` + `uv.lock`); `uv sync --extra sqlserver` añade drivers ODBC     |
| `uv run pytest -q`                                                              | `backend/`  | **~1100 tests rápidos** + 3 `mssql` saltados; `-m "not e2e"`; requiere PostgreSQL real      |
| `uv run pytest tests/e2e`                                                       | `backend/`  | **34 tests E2E** (~15 s) contra stub LM firmante (Ed25519)                                  |
| `MSSQL_TEST_URL_SYNC=... uv run pytest -m mssql`                                | `backend/`  | **3 tests SQL Server** (N1: 2, N2: 1). 16 completos en 3 archivos. Requiere SQL Server real |
| `uv run ruff check app tests`                                                   | `backend/`  | line-length 100                                                                             |
| `uv run mypy tests/`                                                            | `backend/`  |                                                                                             |
| `flutter test` / `flutter analyze`                                              | `frontend/` | **508 tests** unit/widget                                                                   |
| `bash scripts/e2e_flutter.sh up`                                                | `backend/`  | Entorno E2E Flutter: BD aislada + seed + stub LM + API en `127.0.0.1:8000`                  |
| `flutter test integration_test/pesaje_flow_test.dart -d linux`                  | `frontend/` | **1 E2E UI** (login → entrada → salida → `CERRADO`); local `DISPLAY=:0`, CI `xvfb-run -a`   |
| `uvicorn app.main:app --port 8000`                                              | `backend/`  | Levanta API local dev                                                                       |
| `python scripts/mcp_hardware_server.py`                                         | `backend/`  | Servidor MCP stdio (JSON-RPC) para simulaciones de básculas, camiones, tickets, DDL         |
| `./scripts/build_wserver.sh`                                                    | `backend/`  | Compila WServer one-file (PyInstaller)                                                      |
| `./scripts/setup_db.sh instalar`                                                | `backend/`  | Aplica esquema local                                                                        |
| `./scripts/verify.sh`                                                           | `backend/`  | Verificación de estación                                                                    |
| `docker compose -f deploy/observability/docker-compose.observability.yml up -d` | `backend/`  | Prometheus :9090, Grafana :3000 `admin/admin`, Alertmanager :9093                           |
| `./scripts/reset_db.sh`                                                         | `backend/`  | Vacía ambas BD con esquema canónico                                                         |
| `./scripts/reset_total.sh`                                                      | raíz        | Reset total (respalda con `pg_dump -Fc` antes)                                              |
| `uv run python scripts/seed_volumen.py --crear-bd`                              | `backend/`  | Semilla P2: 50k boletos coherentes                                                          |
| `uv run python scripts/benchmark_volumen.py`                                    | `backend/`  | P2: mide 11 endpoints p50/p95/p99                                                           |
| `uv run python scripts/benchmark_concurrencia.py`                               | `backend/`  | P2c: JWT + TCP reales y concurrencia                                                        |

⚠️ **`uv` no está en PATH** en esta máquina. Usar `backend/.venv/bin/python -m pytest -q` como fallback. No usar `backend/.venv.broken`.

---

## Arquitectura clave (lo NO obvio)

- **Una app FastAPI, dos roles** (`APP_ROLE=local|server` en `.env`):
  - `local` → estación operativa (boletos, catálogos, login offline). Monta `API_ROUTERS`.
  - `server` → central (cuenta/licencia/credenciales/sync/panel). Monta `SERVER_ROUTERS` (`app/api/v1/endpoints/servidor.py`).
  - Selector en `app/main.py`; modelos server en `app/models_server.py` + `server_async_engine`.
- **No existe `schema.sql`**. Esquemas canónicos: `backend/balansoft-ws-local.sql` (**31 tablas**, **33** con migraciones) y `balansoft-ws-server.sql` (10 tablas). Migraciones idempotentes en `backend/migrations/*.sql` (**001–030**), sin Alembic.
- **Motor de BD por prefijo** (`app/core/db_engine.py`): el motor sale **solo** del prefijo de `DATABASE_URL` (`postgresql…` | `mssql…`). `DATABASE_URL_SYNC` se deriva en memoria si está vacía/incoherente. Con `mssql` los drivers son opcionales (extra `sqlserver`), WServer **no aplica DDL** (Fase 2), esquema ausente/servidor caído → **503** (`esquema_mssql_pendiente` / `sqlserver_sin_conexion`).
- **WServer**: backend local compilado PyInstaller one-file (`backend/wserver.py` + `WServer.spec`). Crea runtime en `~/.balansoft-ws/wserver` (o `WSERVER_HOME`), genera `.env` desde `.env.plantilla`, levanta BD local + API en `0.0.0.0:8000`. Flutter lo lanza vía `wserver_manager.dart` (en estaciones `SERVIDOR`).
- **Regla: 1 máquina = 1 empresa = 1 cuenta**. Primera máquina = `SERVIDOR_LOCAL`; demás = `LOCAL` (operador). El rol lo decide el instalador y queda en `config.json`:
  - `SERVIDOR`: escribe `rol=SERVIDOR` en `config.json`; app arranca en `/login`, asegura WServer, aplica borrador empresa al primer login ADMIN.
  - `OPERADOR`: escribe `rol=OPERADOR` + URL del titular en `config.json`; exige llave de activación; `/login` contra API del servidor titular. `TRABAJADOR` = alias de `OPERADOR`.
- **Licencia (v3.28)**: **no gatea por plan** (Básico/Premium). Único tope local = **sesiones** (`DEMO` = 3; resto = `licencias.max_sesiones` del LM). Fuente única: `limite_sesiones_por_tier()` (`app/services/llave_activacion_service.py`).
- **Llaves activación (v3.28)**: `POST /api/v1/activacion/llaves` (solo ADMIN, tabla `llaves_activacion`, migración 025) emite llave un solo uso (`BS-XXXX-XXXX-XXXX`, SHA-256, 7 días default, máx 90). `POST /api/v1/activacion/validar` (sin auth) la canjea con `FOR UPDATE`. Instalador la exige en paso 1c; sin llave válida = no recibe cuenta.
- **HAL de balanza SÍ existe** (`app/core/scale_hal.py`, serial/TCP + `GET /weighing/scale/{id}/live`, `POST /balanzas/{id}/probar`, descubrimiento).
- **Dispositivos en vistas independientes (v3.33)**: Básculas (13), Indicadores (27), Semáforos (28), Cámaras (29), Impresoras (30) —cada una con su barra de filtros propia. Helper reutilizable `CatalogService.list_filtrado(...)` (texto `ILIKE` + igualdades, siempre acotado por `id_empresa`).
- **Permisos por categoría**: `app/core/seguridad_matrix.py` + endpoint `seguridad.py` (migración 012). 18 módulos × 3 roles (ADMIN/OPERADOR/AUDITOR) con acceso `ver`/`editar`/`ninguno`; ADMIN forzado a `editar`.
- **i18n es/en/pt**: backend (`app/core/i18n.py`) y frontend (`translations.dart`, **621 claves/idioma**). Backend recibe idioma vía `?idioma=`/`Accept-Language`.
- **Observabilidad**: `MetricsMiddleware` + `GET /metrics` (Prometheus), flag `METRICS_ENABLED`. Métricas: `balansoft_http_requests_total`, `balansoft_api_latency_seconds`, `balansoft_pesajes_total`, `balansoft_license_errors_total`, `balansoft_active_users`. `_normalize_path()` sustituye UUIDs/IDs por `{id}`; **ninguna métrica lleva `id_empresa`**. Rate limiting propio (sliding window); no se comparte entre workers (Redis pendiente).
- **Auditoría**: `GET /api/v1/auditoria` devuelve tabla completa con filtros; solo ADMIN/AUDITOR.
- **CI**: 4 jobs encadenados en `.github/workflows/ci.yml`: `backend` → `e2e` + `frontend` → `e2e-flutter`. Claves Ed25519 generadas en runner (nunca commiteadas).

---

## Configuración (`.env`)

Referencias: `backend/.env.example` (prod), `backend/.env.plantilla` (WServer), `docs/MANEJO_DB.md §11`.

Claves críticas:
- `DATABASE_URL`/`DATABASE_URL_SYNC` (par async/sync obligatorio; **motor decidido por prefijo de `DATABASE_URL`**)
- `APP_ROLE` (`local`|`server`)
- `SERVER_API_URL` + `SERVER_DATABASE_URL` (solo rol local)
- `SECRET_KEY` (generar: `openssl rand -hex 32`)
- `API_HOST`/`API_PORT` (dev `127.0.0.1:8000`; server real `0.0.0.0:8002`)
- `LICENSE_API_URL` (estaciones `https://lm.balansoft.com.ve/api/v1`; server central `127.0.0.1:9001/api/v1`)
- `LICENSE_PRODUCT_CODE=WS` (default `config.py` es `BWS` — **ojo**)
- `API_DOCS_ENABLED` (estaciones: `true` desde v2.4 → `/docs`, `/redoc`, `/openapi.json` expuestos por diseño)
- `METRICS_ENABLED`, `MEDIA_DIR`, `MAX_IMAGE_BYTES`, `ALLOWED_IMAGE_TYPES`
- `BACKUP_DIR` + GFS: `BACKUP_RETENTION_DAYS` (0 = sin límite), `BACKUP_KEEP_DAILY` (7), `BACKUP_KEEP_WEEKLY` (5), `BACKUP_KEEP_MONTHLY` (12)

Dev actual: `APP_ROLE=local` contra `balansoft_ws_local`; `balansoft_ws_server` = réplica local central (rol `server`, puerto 8002).

---

## Tests

- **Requieren PostgreSQL real**: BD `balansoft_ws_test` se deriva de `settings.database_url` (override con `TEST_DATABASE_URL`) en `backend/tests/conftest.py`. Sin DB = fallan antes de correr. BD server test = `balansoft_ws_server_test`.
- Cada test: sesión limpia + `TRUNCATE ... RESTART IDENTITY CASCADE` al final.
- `tests/test_api_server.py` prueba rol `server` sobre `balansoft_ws_server_test`.
- `tests/test_scale_hal.py` usa sessions TCP reales (cierran via `scale_session`).
- Worker global de sesiones balanza (`app/core/scale_session.py`) —no dejarlo abierto entre tests.
- **Estado actual**: backend 1102 rápidos + 3 `mssql` saltados + 34 E2E; frontend 508/508 unit/widget. `ruff`, `mypy`, `flutter analyze` limpios.
- **E2E UI (1/1) no ejecutado en sesiones 3.26–3.33**: estación real ocupa puerto 8000 y `WServerManager.detener()` hace `fuser -k 8000/tcp`. Correr con estación detenida o en CI.
- **Spec 001 (tipografía) implementada NO cerrada**: familia UI (5), factor 0.85–1.40, iconos escalados, `tamano_ticket_pdf` por empresa. **T10b bloqueada**: Ajustes desborda 60 px con `Serif` 1.40.

---

## Documentación autoritativa (`docs/`)

- **Vigente**: `MANEJO_DB.md` (arquitectura 2 BDs, setup dev, flujo login, estado/plan), `NAV.md`, `INPUTS_MAP.md`, `MODELO_ESTANDAR.md`, `I18N_Y_ONBOARDING.md`, `USO-API.md`, `SESIONES.md`, `PLANES-PAGOS.md`, `OBSERVABILIDAD.md`, `BALANZAS_SOPORTADAS.md`, `SEMAFORO.md`.
- **Inventario**: `IMPLEMENTADO.md` v2.0 (2026-10-01) — verificado contra código.
- **Legacy (NO fiarse)**: `docs/DOCUMENTACION VIEJA/` — contradicen implementación (.NET/WinForms, "sin HAL", `schema.sql`).
- **Reglas invariables**: boleto 4 estados `PENDIENTE → CERRADO/MODIFICADO → ANULADO`; kardex ID `10` INGRESO (+) / `60` DESPACHO (-); anular CERRADO = movimiento inverso; peso capturado **nunca se edita**; timestamps UTC (conversión local solo en Flutter).
- **Tabla LECTURA DE PESOS (v3.24)**: 5 columnas fijas para rollo térmico, hoja y TXT — `_REQUIERE_TABLA_PESOS`/`_RATIOS_TABLA_PESOS` reparten ancho; `_tamano_tabla_pesos()` fija tamaño único (80mm ≈ 6.3pt, 58mm ≈ 4.5pt; < 4.5pt = corte por carácter).

---

## Convenciones

- MD con cabecera editorial (Versión, Fecha, Estado, Autor, Norma, Fuente) + IDs trazables `REQ-FN-NNN`, `REQ-NF-<área>-NNN`, `AR-NNN`, `INT-NNN`, `UX-NNN`.
- **ISO/IEC obligatorios** (`.agents/rules/iso-iec-compliance.md`):
  - 25010: calidad (p50<50ms, p95<200ms, modularidad, testabilidad)
  - 17025/OIML R 76-1: metrología legal — inmutabilidad peso, tolerancia 105%, trazabilidad
  - 27001: multi-tenant obligatorio (`id_empresa` en cada query), JWT, Ed25519, auditoría completa
  - 8601: UTC `YYYY-MM-DDTHH:MM:SSZ` en backend/BD
  - 10646/8859-1: UTF-8 en API/BD, Latin-1 en impresión física
  - 18004/15417: QR y Code 128 en boletos
- Cambios de requisitos/rutas/roles → actualizar doc vigente (MANEJO_DB/PRD) **antes** que código.

---

## Deuda técnica abierta

| #  | Deuda                                                                                                                         | Ubicación                                          | Estado                         |
|----|-------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------|--------------------------------|
| D5 | Rate limiting no se comparte entre workers (4× efectivo)                                                                      | `backend/app/core/rate_limit.py`                   | ⚠️ Documentado; Redis pendiente |
| D7 | Título ticket incoherente: PDF usa `titulo_boleto` sin marca; Flutter `ticket_title` = "BOLETO DE PESAJE DE BALANSOFT"        | `ticket_service.py` / `ticket_preview_dialog.dart` | ⚠️ Pendiente decisión           |
| D8 | "Instalador no termina en modo operador": callejón paso 1c corregido (re-envío llave canjeada), falta síntoma exacto original | `BALANSOFT-INSTALLER/gui/steps/*`                  | ⚠️ Parcial                      |
| P1 | Pruebas con balanza física (Toledo/Rice Lake/Sartorius)                                                                       | Hardware real                                      | Pendiente                      |
| P3 | HTTPS/TLS con nginx                                                                                                           | Dominio + certificado                              | Pendiente                      |
| P8 | Regenerar WServer + bundles Flutter/APK                                                                                       | Build                                              | Pendiente                      |

---

## Gotchas operativos

1. **Multi-tenancy estricto**: **toda** query debe filtrar por `id_empresa`. Sin excepción.
2. **Peso inmutable**: el valor leído de la báscula **nunca** se edita. Manual = `es_manual=True` + auditoría.
3. **Serie numeración**: `FOR UPDATE` transaccional obligatorio. `DELETE` serie usada = 409.
4. **Ticket layout parity**: canónico en Flutter (`ticket_preview_dialog.dart`); backend (`ticket_service.py`) debe reflejarlo **exacto** (tabla 5 columnas v3.24).
5. **Serial/TCP concurrency**: `threading.Lock` por puerto en `SerialScaleHAL` (dentro de `asyncio.to_thread`); timeout seguro en `writer.wait_closed()`.
6. **Metrics cardinalidad**: `_normalize_path()` = `{id}`; **nunca** `id_empresa` en métricas.
7. **License snapshot**: `/auth/license` usa `limite_sesiones_por_tier()` — única fuente de verdad del tope.
8. **API_DOCS_ENABLED**: stations = `true` (`.env.plantilla`); central = `false` (`.env.example`). `openapi_url` independiente.
9. **SQL Server Fase 2**: WServer no aplica DDL; si falta esquema → 503. Drivers opcionales (`uv sync --extra sqlserver`).
10. **E2E UI**: necesita `libsecret-1-dev` en Linux (flutter_secure_storage_linux). Sin él falla build antes de testear.