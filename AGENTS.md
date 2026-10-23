# AGENTS.md — BALANSOFT-WS

Estación de pesaje industrial multi-empresa. Stack: **FastAPI** (backend) + **Flutter** (cliente de escritorio) + **WServer** (runtime PyInstaller) + **HAL** de básculas. Idioma del código, comentarios y documentación: **español**. Responder siempre en español.

## Mapa del repo (monorepo `src/`)

| Ruta | Contenido | Entry point |
|---|---|---|
| `src/backend/` | API FastAPI, ORM SQLAlchemy, HAL básculas, WServer | `app/main.py` · `wserver.py` |
| `src/frontend/` | Cliente Flutter (Linux/Windows/Android) | `lib/main.dart` |
| `sdd/` | Spec-Driven Development — **fuente de verdad** de requisitos y arquitectura | `sdd/README.md` |

- Las reglas ISO en `.opencode/rules/*.md` se cargan vía `opencode.json`; no duplicarlas, cumplirlas.
- `sdd/architecture/overview.md` + `sdd/architecture/adr/` son la referencia de arquitectura; `sdd/specs/<NNN>-<slug>` por funcionalidad.

## Comandos (órden: lint → mypy → test → flutter analyze → flutter test)

| Qué | Comando | Dónde |
|---|---|---|
| Lint backend | `uv run ruff check app tests` | `src/backend` |
| Tipos backend | `uv run mypy tests/` | `src/backend` |
| Tests backend (rápidos) | `uv run pytest -q -m "not e2e"` | `src/backend` |
| Un test / clase | `uv run pytest tests/test_weighing_service.py::TestCierre -q` | `src/backend` |
| SQL Server (opcional) | `uv run pytest -m mssql` | `src/backend` (requiere `MSSQL_TEST_URL_SYNC`) |
| Análisis frontend | `flutter analyze` | `src/frontend` |
| Tests frontend | `flutter test` | `src/frontend` |
| API dev | `uv run uvicorn app.main:app --port 8000 --reload` | `src/backend` |
| Empaquetar WServer | `./scripts/build_wserver.sh` | `src/backend` |
| MCP hardware | `uv run python scripts/mcp_hardware_server.py` | `src/backend` |
| Versión y tag | `make version-info` / `make release-tag` | Raíz |

- **E2E backend** exige claves Ed25519 **nunca commiteadas** — se generan en `/tmp`:
  ```bash
  cd src/backend
  uv run python scripts/generate_signing_keys.py /tmp/lm-keys
  LICENSE_PRIVATE_KEY_PATH=/tmp/lm-keys/key_privada.pem \
  LICENSE_PUBLIC_KEY_PATH=/tmp/lm-keys/key_publica.pem \
  LM_STUB_PORT=9100 uv run pytest tests/e2e -q
  ```
- **No hay `.env` commiteado.** `app/core/config.py` usa `SettingsConfigDict(env_file=".env")` relativo al CWD → sin `.env` se usan defaults (`postgresql+asyncpg://sqlman:7767@localhost:5432/balansoft_ws`). Crear `src/backend/.env` desde `.env.plantilla` o `.env.example`.

## Prerrequisitos de test (backend)

- **PostgreSQL real es obligatorio.** `tests/conftest.py` deriva la BD `balansoft_ws_test` de `settings.database_url`. pytest crea el esquema con `drop_all`/`create_all` del metadata ORM, **pero no crea la base**: hay que crearla a mano (`CREATE DATABASE balansoft_ws_test;`) o todo test que toque BD revienta con `InvalidCatalogNameError`. `balansoft_ws_server_test` también hace falta para `tests/test_api_server.py`.
- **Entre tests se trunca todo** (`TRUNCATE ... RESTART IDENTITY CASCADE` sobre el metadata ORM) → **las migraciones SQL no se aplican en tests**: el metadata ORM debe estar completo.
- Fixture autouse `_cerrar_sesiones_balanza`: cierra sesiones TCP globales de `app/core/scale_session.py`. `tests/test_scale_hal.py` abre sockets TCP reales.
- **Línea base verificada:** backend `935 pass` + `3 skip` (mssql) = `938` no-E2E y `34` E2E; frontend `407` unit/widget. La BD de test se crea desde cero en cada sesión (`drop_all`/`create_all`), pero **la base debe existir** (ver arriba).

## Arquitectura (lo no obvio)

- **Dos roles según `APP_ROLE=local|server`** (`app/main.py`):
  - `local` → estación operativa (boletos, catálogos, login offline). Monta `API_ROUTERS` (22 entradas).
  - `server` → central de cuenta/licencia/sync/panel. Monta `SERVER_ROUTERS` (`servidor`, `entorno`).
  - Modelos server en `app/models_server.py` + `server_async_engine` (`app/core/database.py`).
- **Motor de BD por prefijo de `DATABASE_URL`** (`app/core/db_engine.py`): solo `postgresql…` o `mssql…`; sin env vars nuevas. `DATABASE_URL_SYNC` se deriva en memoria. SQL Server es **Fase 1 modo degradado**: sin drivers ODBC la API responde 503 y el arranque lo avisa.
- **Sin Alembic:** migraciones hand-made en `src/backend/migrations/*.sql` (001–025), idempotentes, aplicadas por el WServer al arrancar. Los `*.mssql.sql` se excluyen del runner PostgreSQL.
- **WServer** (`src/backend/wserver.py` + `WServer.spec`): binario PyInstaller one-file. 1ª instalación resuelve el runtime, genera `.env` desde `.env.plantilla` (SECRET_KEY aleatoria) y aplica migraciones.
- **Licencia:** la estación **no** gatea por `features`/`plan_type`. Único tope local: `limite_sesiones_por_tier()` → DEMO = 3, resto `None`; el tope real lo pone `licencias.max_sesiones` del LM/central.
- **Llaves de activación:** `POST /api/v1/activacion/llaves` (ADMIN) emite llave de **un solo uso por usuario** (`BS-XXXX-XXXX-XXXX`, SHA-256, expira 1 h–90 días, default 7). `POST /api/v1/activacion/validar` la canjea con `SELECT … FOR UPDATE`.
- **Series de numeración** (`series_numeracion`, migración 015): 1..N por empresa, contador transaccional `SELECT … FOR UPDATE`. `DELETE` de una serie ya usada responde **409**.
- **Permisos por categoría** (`app/core/seguridad_matrix.py`, migración 012): 18 módulos × 3 roles (ADMIN/OPERADOR/AUDITOR) con `ver`/`editar`/`ninguno`; ADMIN forzado a `editar`. `TRABAJADOR` se fusionó en `OPERADOR` (migración 025).
- **Multi-tenencia obligatoria:** `id_empresa` debe aparecer en **toda** consulta, filtro, inserción o validación (BD local y central). Ninguna métrica Prometheus ni log público debe exponerlo.
- **i18n:** backend `app/core/i18n.py` (139 claves × es/en/pt), frontend `lib/core/i18n/translations.dart` (848 × es/en/pt). El backend recibe idioma vía `?idioma=` / `Accept-Language`.
- **Paridad de ticket:** el layout canónico vive en **Flutter** (`lib/presentation/widgets/ticket_preview_dialog.dart`); el backend (`app/services/ticket_service.py`) debe reflejarlo exactamente (tabla LECTURA DE PESOS de 5 columnas, v3.24). Cambiar uno obliga a cambiar el otro.
- **Kardex:** movimiento 10 = INGRESO (+), 60 = DESPACHO (−). Anular un boleto CERRADO registra el contra-asiento exacto; nunca se borra historial.

## CI Pipeline (`.github/workflows/ci.yml`)

| Job | Qué hace | Dependencias |
|---|---|---|
| `backend` | ruff → mypy → pytest (938 tests) | PostgreSQL 16 service |
| `e2e` | 34 tests E2E con stub LM (Ed25519) | `backend`, PostgreSQL 16 |
| `frontend` | flutter analyze → flutter test (407) | `backend`, Flutter 3.47.2 |
| `e2e-flutter` | Test integración pesaje flow (Linux GTK + xvfb) | `backend`, `frontend`, PostgreSQL 16 |

- **E2E Flutter requiere**: `libsecret-1-dev`, `libgtk-3-dev`, `xvfb` (instalados en el job CI).
- El script `src/backend/scripts/e2e_flutter.sh up` levanta BD + seed + stub LM + API en :8000.
- `e2e-flutter` corre con `xvfb-run -a flutter test integration_test/pesaje_flow_test.dart -d linux`.

⚠️ **El E2E de UI choca con la estación viva:** `lib/core/services/wserver_manager.dart` hace `fuser -k 8000/tcp` al cerrar la app → si la app Flutter está corriendo, el E2E falla por el puerto. **Sí se puede correr en local** con la estación detenida:
```bash
cd src/backend
DATABASE_URL_SYNC=postgresql+psycopg2://sqlman:7767@localhost:5432/balansoft_ws_test \
  ./scripts/e2e_flutter.sh up      # BD + seed + stub LM + API en :8000
cd ../frontend
xvfb-run -a flutter test integration_test/pesaje_flow_test.dart -d linux
cd ../backend && ./scripts/e2e_flutter.sh down
```
Requiere `xvfb` + `libgtk-3-dev` + `libsecret-1-dev` (`flutter_secure_storage_linux`).
- `make test-e2e-ui` invoca `flutter test integration_test/… -d linux` **sin** `xvfb` → en headless falla; usar `xvfb-run -a`.
- `scripts/reset_total.sh` (raíz) respalda con `pg_dump -Fc` y **aborta si falta pg_dump**: los datos pesan más que la comodidad del reset.
- **Migraciones:** `setup_db.sh aplicar-migraciones` y el runtime WServer ignoran las variantes `*.mssql.sql` (son T-SQL). Si añades una migración para SQL Server, créla con ese sufijo.
- `scripts/setup_db.sh` y `e2e_flutter.sh` exigen `DATABASE_URL_SYNC` en el entorno o en `src/backend/.env` — incluso en modos que no tocan la BD (`down`).

## Versionado y releases

- SemVer pre-release `0.y.z-dev.B`; la **fuente de versión es `opencode.json`**.
- Commits de desarrollo: **sin tag**, Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`).
- Commits de release: **con tag anotado** — `git tag -a v0.4.2-dev.56 -m "Release v0.4.2-dev.56"` (dispara el pipeline de instaladores y empaquetado del WServer).
- Archivos a sincronizar en cada release: `opencode.json`, `src/frontend/pubspec.yaml`, `src/frontend/lib/core/config/app_config.dart`, `src/backend/pyproject.toml` (**PEP 440: `0.4.2.dev56`, sin guiones**), `CHANGELOG.md`.

## MCP de hardware

`opencode.json` → `mcpServers.balansoft-hardware` (stdio, `src/backend/scripts/mcp_hardware_server.py`). 6 herramientas: `parse_scale_frame`, `simulate_scale_frame`, `calculate_truck_weights`, `format_ticket_weights_table`, `inspect_db_table`, `verify_iso_standards`. Manual: `make run-mcp` o `python3 src/backend/scripts/mcp_hardware_server.py`.

## Knowledge Graph (codebase-memory-mcp)

El proyecto está indexado en codebase-memory-mcp. Antes de cambios estructurales:
- `search_graph` para encontrar símbolos, `trace_path` para callers/callees, `get_code_snippet` para fuente exacta.
- `check_index_coverage` con paths/scopes afectados antes de afirmaciones negativas o exhaustivas.
- `list_projects` / `index_status` para confirmar proyecto y generación al iniciar sesión.