# AGENTS.md — BALANSOFT-WS

Sistema estación pesaje industrial multi-empresa: FastAPI + Flutter + WServer runtime.
Idioma oficial: español (docs, comentarios, comunicación).
Repositorio: `src/backend/` (FastAPI/Postgres) + `src/frontend/` (Flutter/Dart).

## Comandos canónicos

> **Tip:** El proyecto cuenta con un [`Makefile`](file:///home/panchove/Projects/I+D-SYSTEM/BALANSOFT-WS-DART/Makefile) en la raíz para ejecutar todo con comandos directos (`make help`, `make test`, `make lint`, `make dev-backend`, `make version-info`).

| Comando | Lugar | Notas |
|---|---|---|
| `make test` / `make lint` | raíz | Ejecuta pruebas o linter completo de ambos stacks con un solo comando |
| `uv sync` | `src/backend/` | Stack uv (`pyproject.toml` + `uv.lock`); `--extra sqlserver` añade `aioodbc`/`pyodbc` (Fase 1 SQL Server) |
| `uv run pytest -q` | `src/backend/` | **935 tests rápidos** (~7,7 min) + 3 `mssql` que se saltan sin SQL Server; requiere PostgreSQL real. `-m "not e2e"` |
| `uv run pytest tests/e2e` | `src/backend/` | **34 tests E2E** (~15 s) contra el stub firmante del LM |
| `MSSQL_TEST_URL_SYNC=... uv run pytest -m mssql` | `src/backend/` | 3 tests SQL Server (T8): N1 esquema/idempotencia/paridad + N2 flujo funcional |
| `uv run ruff check app tests` | `src/backend/` | line-length 100 |
| `uv run mypy tests/` | `src/backend/` | |
| `flutter test` / `flutter analyze` | `src/frontend/` | **405 tests** unit/widget |
| `bash scripts/e2e_flutter.sh up` | `src/backend/` | E2E Flutter: BD aislada + seed + stub LM + API en `127.0.0.1:8000` (`down` / `status` también) |
| `flutter test integration_test/pesaje_flow_test.dart -d linux` | `src/frontend/` | **1 E2E de UI** (login → entrada → salida → `CERRADO`); en local con `DISPLAY=:0`, en CI con `xvfb-run -a` |
| `uvicorn app.main:app --port 8000` | `src/backend/` | Levanta API local dev |
| `python scripts/mcp_hardware_server.py` | `src/backend/` | Servidor MCP sobre stdio (JSON-RPC) para simulaciones de básculas, camiones, tickets y DDL |
| `./scripts/build_wserver.sh` | `src/backend/` | Compila WServer one-file (PyInstaller) |
| `./scripts/setup_db.sh instalar` | `src/backend/` | Aplica esquema local |
| `./scripts/verify.sh` | `src/backend/` | Verificación de estación |
| `./scripts/reset_db.sh` | `src/backend/` | Vacía ambas BD con esquema canónico |
| `./scripts/reset_total.sh` | raíz | Reset total (respalda con `pg_dump -Fc` antes; aborta si falla) |
| `uv run python scripts/seed_volumen.py --crear-bd` | `src/backend/` | Semilla P2: 50k boletos coherentes en `balansoft_ws_volumen` (`--drop-bd` la borra) |
| `uv run python scripts/benchmark_volumen.py` | `src/backend/` | P2: mide 11 endpoints con p50/p95/p99 contra la BD de volumen |
| `uv run python scripts/benchmark_concurrencia.py` | `src/backend/` | P2c: JWT + TCP reales y concurrencia (1/5/10 operadores) levantando su propio uvicorn de 1 worker |

⚠️ **En este entorno `uv` no está en PATH**: hay un `backend/.venv/` gitignored con pytest/ruff/mypy (usar `backend/.venv/bin/python -m pytest -q` como fallback). No usar `backend/.venv.broken`.

---

## Arquitectura esencial (lo NO obvio)

- **Una sola app FastAPI con dos roles** (dos bases de datos), decidido por `APP_ROLE=local|server` en `.env`:
  - `local` → estación operativa (boletos, catálogos, login-local offline). Monta `API_ROUTERS`.
  - `server` → central de cuenta/licencia/credenciales/sync/panel. Monta `SERVER_ROUTERS` (`app/api/v1/endpoints/servidor.py`).
  - Selector en `app/main.py`; modelos del servidor en `app/models_server.py` + motor `server_async_engine` (`app/core/database.py`).
- **No existe `backend/schema.sql`.** Los esquemas canónicos son **`src/backend/balansoft-ws-local.sql`** (28 tablas; 30 tras migraciones `001–025`) y **`src/balansoft-ws-server.sql`** (10 tablas). Migraciones hacia adelante en `src/backend/migrations/*.sql` (001–025), idempotentes, **sin Alembic**.
- **Motor de BD por prefijo** (`src/backend/db_engine.py`): el motor sale **solo** del prefijo de `DATABASE_URL` (`postgresql…` | `mssql…`), **sin env vars nuevas**; `DATABASE_URL_SYNC` se deriva en memoria si está vacía/incoherente y `Settings.db_engine` + `_coherencia_motores` validan el par. Con `mssql` los drivers son opcionales y perezosos (extra `sqlserver`); el WServer **no aplica DDL** (Fase 2); esquema ausente/servidor caído responde **503** (`esquema_mssql_pendiente` / `sqlserver_sin_conexion`); la ruta PG conserva `raise` y 500 idénticos.
- **WServer**: backend local de la estación compilado con PyInstaller one-file (`src/backend/wserver.py` + `WServer.spec` + `scripts/build_wserver.sh`). En primera instalación crea runtime (`~/.balansoft-ws/wserver`, o `WSERVER_HOME`), genera `.env` desde `.env.plantilla` (SECRET_KEY aleatoria) y levanta la BD local + API en `0.0.0.0:8000` (accesible desde la LAN por IP; migra `API_HOST=127.0.0.1` previo y abre el puerto en ufw vía `pksec`).
- **Licencia**: la estación WS **no** gatea funciones por `features`/`plan_type` (Básico/Premium): todos los módulos quedan disponibles. El **único tope local** es el de **sesiones** (`DEMO` = 3); en el resto manda `licencias.max_sesiones` del LM/central. Fuente única del tope de la estación: `limite_sesiones_por_tier()` (`app/services/llave_activacion_service.py`).
- **Llaves de activación**: `POST /api/v1/activacion/llaves` (solo ADMIN, tabla `llaves_activacion`, migración `025`) emite una llave de **un solo uso por usuario** (`BS-XXXX-XXXX-XXXX`, SHA-256 en BD, 7 días por defecto, máx. 90 días) y `POST /api/v1/activacion/validar` (sin auth) la canjea con `SELECT … FOR UPDATE`, la pasa a `consumida` y **avisa al dueño** con un `Notificacion` de `dedup_key = llave_activacion:{id}` y las sesiones usadas. **Sin llave válida esa máquina no recibe cuenta**.
- **i18n es/en/pt** en backend (`app/core/i18n.py`) y frontend (`translations.dart`, **621 claves por idioma**, paridad verificada por test). El backend recibe idioma vía `?idioma=`/`Accept-Language`.
- **Series de numeración** (`series_numeracion` + `boletos_pesaje.id_serie`, migración `015`): 1..N por empresa, contador transaccional (`FOR UPDATE`), prefijo/dígitos configurables. `DELETE` de serie usada responde **409**.
- **Permisos por categoría**: `app/core/seguridad_matrix.py` + endpoint `seguridad.py` (migración `012`), en vez de solo roles globales. 18 módulos × **3 roles** (ADMIN/OPERADOR/AUDITOR) con acceso `ver`/`editar`/`ninguno`; ADMIN forzado a `editar` en todo. El rol histórico `TRABAJADOR` se fusionó en `OPERADOR` (migración `025`) y se sigue leyendo como alias.
- **Observabilidad**: `MetricsMiddleware` (`app/core/monitoring.py`) + `GET /metrics` (Prometheus), bajo el flag `METRICS_ENABLED`; contadores `balansoft_http_requests_total`, `balansoft_api_latency_seconds`, `balansoft_pesajes_total`, `balansoft_license_errors_total`, `balansoft_active_users`. **Ninguna métrica lleva `id_empresa`** (multi-tenancy: `/metrics` no puede filtrar por tenant). Rate limiting propio (sliding window, `rate_limit.py`); **no se comparte entre workers** (Redis pendiente). Logging en `app/core/logging_config.py` (consola + archivo rotado por tamaño, formato `text|json` vía `LOG_FORMAT`).
- **Auditoría**: `GET /api/v1/auditoria` (`app/api/v1/endpoints/auditoria.py`) devuelve la tabla `auditoria` completa con filtros `entidad/accion/fecha_desde/fecha_hasta/skip/limit`; solo roles ADMIN/AUDITOR.

---

## Configuración `.env`

- Referencias: `src/backend/.env.example` (producción), `src/backend/.env.plantilla` (plantilla embebida del WServer), `docs/MANEJO_DB.md §11`.
- Claves clave: `DATABASE_URL`/`DATABASE_URL_SYNC` (obligatorio el par async/sync; **el motor lo decide solo el prefijo de `DATABASE_URL`**, §11.5), `APP_ROLE`, `SERVER_API_URL` + `SERVER_DATABASE_URL` (solo rol local), `SECRET_KEY` (generar con `openssl rand -hex 32`), `API_HOST`/`API_PORT` (dev `127.0.0.1:8000`; servidor real `0.0.0.0:8002`), `LICENSE_API_URL` (en estaciones `https://lm.balansoft.com.ve/api/v1`; en servidor central con LM local `127.0.0.1:9001/api/v1`), `LICENSE_PRODUCT_CODE=WS` (ojo: el default de `config.py` es `BWS`), `METRICS_ENABLED`, `BACKUP_DIR` + rotación GFS `BACKUP_RETENTION_DAYS` (0 = sin límite duro de edad), `BACKUP_KEEP_DAILY` (default 7), `BACKUP_KEEP_WEEKLY` (default 5), `BACKUP_KEEP_MONTHLY` (default 12).
- **En dev actual**: `APP_ROLE=local` contra la BD `balansoft_ws_local` (el `.env` apunta ahí); `balansoft_ws_server` es la réplica local del central (rol `server`, puerto dev `8002`). `reset_total.sh` (v1.2.7) **respalda las BD con `pg_dump -Fc` antes de borrarlas** y aborta si el respaldo falla.

---

## Tests

- Requieren **PostgreSQL real**: la BD de tests `balansoft_ws_test` se deriva de `settings.database_url` (overridable con `TEST_DATABASE_URL`) en `src/backend/tests/conftest.py`. Sin DB levantada los tests fallan antes de correr. La BD de tests del rol `server` es `balansoft_ws_server_test`.
- Cada test recibe sesión limpia y al finalizar se **truncan todas las tablas** (`TRUNCATE ... RESTART IDENTITY CASCADE`).
- `tests/test_api_server.py` prueba el rol `server` sobre `balansoft_ws_server_test`; `tests/test_scale_hal.py` usa sessions TCP reales (se cierran tras cada test via `scale_session`).
- Hay worker de sesiones de balanza global (`app/core/scale_session.py`), **no dejarlo abierto entre tests**.
- **Orden de verificación**: `ruff check` → `mypy` → `pytest -q -m "not e2e"`.
- **Estado actual**: backend **935 rápidos + 3 `mssql` saltados + 34 E2E** (972 con SQL Server real); frontend **405/405** unit/widget.

---

## CI (`.github/workflows/ci.yml`)

Cuatro jobs encadenados:
- **backend**: PostgreSQL 16, `uv sync --all-groups`, `ruff check app tests`, `mypy tests/`, `pytest -q -m "not e2e"`.
- **e2e**: necesita backend; genera claves Ed25519 **nunca commiteadas** (`/tmp/lm-keys`); `pytest tests/e2e -q`.
- **frontend**: necesita backend; `flutter analyze`, `flutter test`.
- **e2e-flutter**: necesita backend + frontend; requiere deps de escritorio Linux (GTK/CMake/Ninja), `flutter config --enable-linux-desktop`, `scripts/e2e_flutter.sh up` y `xvfb-run -a flutter test integration_test/pesaje_flow_test.dart -d linux` con reintento; en fallo vuelca `/tmp/balansoft-e2e-flutter/api.log` y `lm.log`.

⚠️ **E2E de UI no se ejecuta** en sesiones locales: la estación real ocupa el puerto 8000 y `WServerManager.detener()` hace `fuser -k 8000/tcp` al cerrar la app, así que debe correrse con la estación detenida o en CI (xvfb + `scripts/e2e_flutter.sh`).

---

## Herramientas MCP

Servidor MCP nativo sobre stdio (JSON-RPC 2.0) en `backend/scripts/mcp_hardware_server.py`, configurado en `opencode.json`. Expone 5 herramientas:
- `parse_scale_frame` — parser multi-marca puro
- `simulate_scale_frame` — Toledo, Yaohua, Rice Lake, Torrey, Keli con XOR checksum, MT-SICS
- `calculate_truck_weights` — totales entrada/salida, netos por vehículo, desviación sobre guía y kardex 10/60
- `format_ticket_weights_table` — representación canónica de la tabla de 5 columnas v3.24
- `inspect_db_table` — DDL de esquemas local y servidor

Uso: `opencode.json` → `mcpServers.balansoft-hardware`; o manualmente: `python3 backend/scripts/mcp_hardware_server.py`.

---

## Flujos críticos

- **E2E Flutter** modo seed: `admin@balansoft.demo`/`demo1234` contra BD creada por `scripts/e2e_flutter.sh`, company/license sembradas en memoria. **No escribe en preferencias** para no falsear el estado de instalación de una estación real en la misma máquina.
- **E2E Flutter** modo instalada: `--dart-define E2E_INSTALADA=true E2E_EMAIL=… E2E_PASS=…`, contra la estación real sin falsear empresa ni licencia.
- **Variables E2E**: `E2E_EMAIL`, `E2E_PASS`, `E2E_BASE_URL` (default `http://localhost:8000`); si la estación real ocupa el 8000, levantar en otro puerto: `E2E_API_PORT=8010 E2E_LM_PORT=9110 bash scripts/e2e_flutter.sh up` + `--dart-define=E2E_BASE_URL=http://127.0.0.1:8010`.
- **Sin báscula** (seed): el formulario habilita el peso manual; el FAB pasa a «Detectar»; siempre se incluyen simuladas por defecto.
- **LM Stub modos**: `valid` (default), `invalid` (SUSPENDIDA), `expired`, `tamper` (altera un campo firmado después de firmar), `unreachable` (503). Claves por `LM_STUB_PRIVATE_KEY_PATH`/`LICENSE_PRIVATE_KEY_PATH`, puerto `LM_STUB_PORT` (9100).

---

## Política de Versionado y Tags Git (SemVer 2.0.0)

- **Versión Oficial**: Única y sincronizada en todo el repositorio. Previo al lanzamiento comercial formal, el sistema opera bajo **`0.y.z-dev.B`** (`pre-release` SemVer; primer release oficial será `1.0.0`).
- **Commits de desarrollo regular**: **NO llevan tag**. Se usa la convención *Conventional Commits* (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`).
- **Commits de Release / Hito**: **SÍ llevan Git Tag**.
  - Son commits dedicados con mensaje: `chore(release): bump version to 0.4.2-dev.56`.
  - El tag debe ser anotado: `git tag -a v0.4.2-dev.56 -m "Release v0.4.2-dev.56"`.
  - Disparan pipelines de CI/CD para compilación de instaladores y empaquetado WServer.
- **Archivos sincronizados en cada release**:
  `opencode.json`, `src/frontend/pubspec.yaml`, `src/frontend/lib/core/config/app_config.dart`, `src/backend/pyproject.toml`, `CHANGELOG.md` y documentos editoriales ISO (`PRD.md`, `AGENTS_SKILLS_ISO_AUDIT.md`, `EULA.md`).

---