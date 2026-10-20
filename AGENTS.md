# AGENTS.md — BALANSOFT-WS

Sistema estación pesaje industrial multi-empresa: FastAPI + Flutter + WServer.
Idioma oficial: español. Repositorio: `src/backend/` (FastAPI/Postgres) + `src/frontend/` (Flutter/Dart).

## Comandos canónicos

| Comando | Lugar | Notas |
|---|---|---|
| `make test` / `make lint` | raíz | Pruebas+linter ambos stacks |
| `uv sync` | `src/backend/` | Requerido: `uv` no está en PATH; usa `backend/.venv/` |
| `uv run pytest -q -m "not e2e"` | `src/backend/` | 935 tests rápidos; incluye `-m "not e2e"` o se ejecutarán los 3 E2E |
| `uv run pytest -m mssql` | `src/backend/` | 3 tests SQL Server; requiere `MSSQL_TEST_URL_SYNC` |
| `uv run ruff check app tests` | `src/backend/` | Linter ruff; line-length 100 |
| `uv run mypy tests/` | `src/backend/` | Type checker |
| `flutter test` / `flutter analyze` | `src/frontend/` | 405 tests unit/widget |
| `./scripts/build_wserver.sh` | `src/backend/` | Compila WServer PyInstaller one-file |
| `./scripts/reset_total.sh` | raíz | **Respalda** con `pg_dump -Fc` antes; aborta si falla |
| `uv run python scripts/seed_volumen.py --crear-bd` | `src/backend/` | Semilla P2: 50k boletos coherentes |
| `uvicorn app.main:app --port 8000` | `src/backend/` | API local dev |

⚠️ **En este entorno `uv` no está en PATH**: usar `backend/.venv/bin/python -m pytest -q` como fallback. No usar `backend/.venv.broken`.

---

## Arquitectura esencial (lo NO obvio)

- **Dos roles por `APP_ROLE=local|server`** en `.env`:
  - `local` → estación operativa (boletos, catálogos, login offline). Monta `API_ROUTERS`.
  - `server` → central de cuenta/licencia/sync/panel. Monta `SERVER_ROUTERS`.
  - Definido en `app/main.py`; modelos servidor en `app/models_server.py` + `server_async_engine` (`app/core/database.py`).
- **Sin Alembic:** Migraciones hand-made `src/backend/migrations/*.sql` (001–025), idempotentes.
- **Motor de BD por prefijo de `DATABASE_URL`** (`src/backend/db_engine.py`): solo `postgresql…` o `mssql…`; sin env vars nuevas. `DATABASE_URL_SYNC` se deriva en memoria.
- **WServer:** PyInstaller one-file (`src/backend/wserver.py` + `WServer.spec`). Primera instalación crea runtime y genera `.env` desde `.env.plantilla` (SECRET_KEY aleatoria).
- **Licencia:** Estación WS **no** gatea por `features`/`plan_type`. Único tope local: sesiones (`DEMO` = 3); resto usa `licencias.max_sesiones` del LM/central.
- **Llaves de activación:** `POST /api/v1/activacion/llaves` (ADMIN) emite llave **un solo uso por usuario** (`BS-XXXX-XXXX-XXXX`, SHA-256, 7 días máx. 90). `POST /api/v1/activacion/validar` la canjea con `SELECT … FOR UPDATE`.
- **i18n:** 621 claves por idioma en backend (`app/core/i18n.py`) y frontend (`translations.dart`). Backend recibe idioma vía `?idioma=`/`Accept-Language`.
- **Series numeración** (`series_numeracion`, migración `015`): 1..N por empresa, contador transaccional `SELECT … FOR UPDATE`. `DELETE` de serie usada responde **409**.
- **Permisos por categoría** (`app/core/seguridad_matrix.py`, migración `012`): 18 módulos × 3 roles (ADMIN/OPERADOR/AUDITOR) con acceso `ver`/`editar`/`ninguno`; ADMIN forzado a `editar` en todo. `TRABAJADOR` se fusionó en `OPERADOR` (migración `025`).
- **Multi-tenancy obligatorio:** `id_empresa` debe aparecer en **todo** consulta, filtro, inserción o validación en BD local y central. Ninguna métrica Prometheus ni log público debe exponer `id_empresa`.

---

## Configuración `.env`

- `DATABASE_URL`/`DATABASE_URL_SYNC`: par async/sync obligatorio; motor decide por prefijo de `DATABASE_URL` (§11.5 de MANEJO_DB.md).
- `APP_ROLE`, `SERVER_API_URL` + `SERVER_DATABASE_URL` (solo rol local).
- `SECRET_KEY`: generar con `openssl rand -hex 32`.
- `API_HOST`/`API_PORT`: dev `127.0.0.1:8000`; servidor real `0.0.0.0:8002`.
- `LICENSE_API_URL`: estaciones `https://lm.balansoft.com.ve/api/v1`; central con LM local `127.0.0.1:9001/api/v1`.
- `LICENSE_PRODUCT_CODE=WS` (default de `config.py` es `BWS` — ojo).
- `METRICS_ENABLED`, `BACKUP_DIR` + rotación GFS (`BACKUP_KEEP_DAILY`=7, `BACKUP_KEEP_WEEKLY`=5, `BACKUP_KEEP_MONTHLY`=12).
- **Dev actual:** `APP_ROLE=local` contra `balansoft_ws_local`; `balansoft_ws_server` es réplica local (rol server, puerto dev `8002`).

---

## Tests

- **Requieren PostgreSQL real:** BD de tests `balansoft_ws_test` deriva de `settings.database_url` (overridable con `TEST_DATABASE_URL`) en `src/backend/tests/conftest.py`. Sin BD levantada los tests fallan antes de correr.
- Cada test recibe sesión limpia y al finalizar se **truncan todas las tablas** (`TRUNCATE ... RESTART IDENTITY CASCADE`).
- `tests/test_api_server.py` prueba rol `server` sobre `balansoft_ws_server_test`; `tests/test_scale_hal.py` usa sessions TCP reales (se cierran tras cada test via `scale_session`).
- **Orden de verificación:** `ruff check` → `mypy` → `pytest -q -m "not e2e"`.
- Worker de sesiones de balanza global (`app/core/scale_session.py`): **no dejarlo abierto entre tests**.
- Estado actual: backend **935 rápidos + 3 mssql saltados + 34 E2E** (972 con SQL Server real); frontend **405/405** unit/widget.

---

## CI (`.github/workflows/ci.yml`)

- **backend**: PostgreSQL 16, `uv sync --all-groups`, `ruff check app tests`, `mypy tests/`, `pytest -q -m "not e2e"`.
- **e2e**: necesita backend; genera claves Ed25519 **nunca commiteadas** (`/tmp/lm-keys`); `pytest tests/e2e -q`.
- **frontend**: necesita backend; `flutter analyze`, `flutter test`.
- **e2e-flutter**: necesita backend + frontend; requiere deps de escritorio Linux (GTK/CMake/Ninja), `flutter config --enable-linux-desktop`, `scripts/e2e_flutter.sh up` y `xvfb-run -a flutter test integration_test/pesaje_flow_test.dart -d linux` con reintento.

⚠️ **E2E de UI no se ejecuta** en sesiones locales: la estación real ocupa el puerto 8000 y `WServerManager.detener()` hace `fuser -k 8000/tcp` al cerrar la app. Ejecutar con estación detenida o en CI (xvfb).

---

## Política de Versionado y Tags Git (SemVer 2.0.0)

- **Versión Oficial:** Sincronizada en todo el repositorio. Pre-lanzamiento bajo `0.y.z-dev.B` (SemVer pre-release; primer release oficial será `1.0.0`).
- **Commits de desarrollo regular:** **NO llevan tag**. Convención *Conventional Commits* (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`).
- **Commits de Release / Hito:** **SÍ llevan Git Tag** anotado.
  - Mensaje: `chore(release): bump version to 0.4.2-dev.56`.
  - `git tag -a v0.4.2-dev.56 -m "Release v0.4.2-dev.56"`.
  - Disparan pipelines CI/CD para compilación de instaladores y empaquetado WServer.
- **Archivos sincronizados en cada release:** `opencode.json`, `src/frontend/pubspec.yaml`, `src/frontend/lib/core/config/app_config.dart`, `src/backend/pyproject.toml`, `CHANGELOG.md` y documentos editoriales ISO (`PRD.md`, `AGENTS_SKILLS_ISO_AUDIT.md`, `EULA.md`).

---

## Herramientas MCP (configuradas en `opencode.json`)

Servidor MCP sobre stdio (JSON-RPC 2.0) en `backend/scripts/mcp_hardware_server.py`. Expone:
- `parse_scale_frame` — parser multi-marca puro
- `simulate_scale_frame` — Toledo, Yaohua, Rice Lake, Torrey, Keli con XOR checksum, MT-SICS
- `calculate_truck_weights` — totales entrada/salida, netos por vehículo, desviación sobre guía y kardex 10/60
- `format_ticket_weights_table` — representación canónica de tabla 5 columnas v3.24
- `inspect_db_table` — DDL de esquemas local y servidor

Uso: `opencode.json` → `mcpServers.balansoft-hardware`; o manualmente: `python3 src/backend/scripts/mcp_hardware_server.py`.