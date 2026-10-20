# AGENTS.md — BALANSOFT-WS

Estación de pesaje industrial multi-empresa. Stack: **FastAPI** (backend) + **Flutter**
(cliente de escritorio) + **WServer** (runtime instalable PyInstaller) + **HAL** de básculas.
Idioma del código, comentarios y documentación: **español**. Responder siempre en español.

## Mapa del repo (monorepo `src/`)

| Ruta | Contenido | Entry point |
|---|---|---|
| `src/backend/` | API FastAPI, ORM SQLAlchemy, HAL de básculas, WServer | `app/main.py` · `wserver.py` |
| `src/frontend/` | Cliente Flutter (Linux/Windows/Android) | `lib/main.dart` |
| `src/panel/` | Panel web legacy (HTML/JS estático, "BALASOFT-UI"). Consume la API del rol `server` vía `/api/v1/panel/*`; FastAPI **no** lo monta. | `index.html` |
| `sdd/` | Spec-Driven Development (ISO 29148/42010/1016/12207) — **fuente de verdad** de requisitos y arquitectura | `sdd/README.md` |
| `docs/` | Solo legal (`TERMINOS_CONDICIONES.md`, `PROPRIETARY_NOTICE.md`) | — |
| `.opencode/` | `rules/` (normativa), `skills/`, `agents/` (11 subagentes), `commands/update-all.md` | — |

- Las 4 reglas de `.opencode/rules/*.md` (ISO/IEC, seguridad industrial, concurrencia hardware,
  paridad de tickets) se cargan solas vía `instructions` de `opencode.json` → **son normativas**;
  no duplicarlas aquí, pero sí cumplirlas.
- `sdd/architecture/overview.md` + `sdd/architecture/adr/` son la referencia de arquitectura;
  `sdd/specs/<NNN>-<slug>/{spec,design,tasks,plan}.md` el de cada funcionalidad.

⚠️ **El CI (.github/workflows/ci.yml) usa las rutas del monorepo `src/`**: `uv … --directory
src/backend`, `cd src/frontend`, `bash src/backend/scripts/e2e_flutter.sh up`. Si agregas un job,
copia esas rutas — no las de un repo plano.

## Comandos

`make help` lista todos los targets del `Makefile` (raíz). El backend usa `uv`
(ya está en PATH: `~/.local/bin/uv`); fallback `src/backend/.venv/bin/python -m pytest -q`.

| Qué | Comando | Dónde |
|---|---|---|
| Lint backend | `uv run ruff check app tests` | `src/backend` |
| Tipos backend | `uv run mypy tests/` | `src/backend` |
| Tests backend (rápidos) | `uv run pytest -q -m "not e2e"` | `src/backend` |
| Un test / una clase | `uv run pytest tests/test_weighing_service.py::TestCierre -q` | `src/backend` |
| SQL Server (opcional) | `uv run pytest -m mssql` | `src/backend` (requiere `MSSQL_TEST_URL_SYNC`) |
| E2E backend | ver abajo | `src/backend` |
| Análisis frontend | `flutter analyze` | `src/frontend` |
| Tests frontend | `flutter test` | `src/frontend` |
| API dev | `uv run uvicorn app.main:app --port 8000 --reload` | `src/backend` |
| Empaquetar WServer | `./scripts/build_wserver.sh` | `src/backend` |
| MCP hardware | `uv run python scripts/mcp_hardware_server.py` | `src/backend` |

- **Orden de verificación**: `ruff check` → `mypy` → `pytest` → `flutter analyze` → `flutter test`.
- `make lint` / `make test` cubren ambos stacks. El `Makefile` exporta `PATH` con
  `/home/panchove/development/flutter/bin` (Flutter 3.44 local; CI usa 3.47.2).
- `opencode.json` → `scripts` duplica estos comandos con prefijo (`backend:test`, `frontend:test`, …).
- **E2E backend** exige claves Ed25519 **nunca commiteadas** — se generan en `/tmp`:
  ```bash
  cd src/backend
  uv run python scripts/generate_signing_keys.py /tmp/lm-keys
  LICENSE_PRIVATE_KEY_PATH=/tmp/lm-keys/key_privada.pem \
  LICENSE_PUBLIC_KEY_PATH=/tmp/lm-keys/key_publica.pem \
  LM_STUB_PORT=9100 uv run pytest tests/e2e -q
  ```

## Prerrequisitos de test (backend)

- **PostgreSQL real es obligatorio.** `tests/conftest.py` deriva la BD `balansoft_ws_test` de
  `settings.database_url` (override con `TEST_DATABASE_URL`). pytest crea el *esquema* dentro con
  `drop_all`/`create_all` del metadata ORM, **pero no crea la base**: hay que crearla a mano
  (`CREATE DATABASE balansoft_ws_test;`) o todo test que toque BD revienta con
  `InvalidCatalogNameError`. `balansoft_ws_server_test` también hace falta para `tests/test_api_server.py`.
- **No hay `.env` en el repo.** `app/core/config.py` usa `SettingsConfigDict(env_file=".env")`
  relativo al CWD → sin `.env` se usan los defaults
  (`postgresql+asyncpg://sqlman:7767@localhost:5432/balansoft_ws`). Crear `src/backend/.env`
  desde `.env.plantilla` (instalación real) o `.env.example` (referencia completa de variables).
- Entre tests se trunca todo (`TRUNCATE ... RESTART IDENTITY CASCADE` sobre el metadata ORM)
  → **las migraciones SQL no se aplican en tests**: el metadata ORM debe estar completo.
- Fixture autouse `_cerrar_sesiones_balanza`: cierra las sesiones TCP globales de
  `app/core/scale_session.py`. `tests/test_scale_hal.py` abre sockets TCP reales.
- **Línea base verificada (todo en verde)**: backend `935 pass` + `3 skip` (mssql) = `938` no-E2E
  y `34` E2E; frontend `407` unit/widget. La BD de test se crea desde cero en cada sesión
  (`drop_all`/`create_all`), pero **la base debe existir** (ver arriba).

## Arquitectura (lo no obvio)

- **Dos roles según `APP_ROLE=local|server`** (`app/main.py`):
  - `local` → estación operativa (boletos, catálogos, login offline). Monta `API_ROUTERS` (22 entradas).
  - `server` → central de cuenta/licencia/sync/panel. Monta `SERVER_ROUTERS` (`servidor`, `entorno`).
  - Modelos del server en `app/models_server.py` + `server_async_engine` (`app/core/database.py`).
- **Motor de BD por prefijo de `DATABASE_URL`** (`app/core/db_engine.py`): solo `postgresql…` o
  `mssql…`; sin env vars nuevas. `DATABASE_URL_SYNC` se deriva en memoria. SQL Server es
  **Fase 1 modo degradado**: sin drivers ODBC la API responde 503 y el arranque lo avisa.
- **Sin Alembic:** migraciones hand-made en `src/backend/migrations/*.sql` (001–025), idempotentes,
  aplicadas por el WServer al arrancar. Los `*.mssql.sql` se excluyen del runner PostgreSQL.
- **WServer** (`src/backend/wserver.py` + `WServer.spec`): binario PyInstaller one-file. En la 1ª
  instalación resuelve el runtime, genera `.env` desde `.env.plantilla` (SECRET_KEY aleatoria) y
  aplica migraciones.
- **Licencia:** la estación **no** gatea por `features`/`plan_type`. Único tope local:
  `limite_sesiones_por_tier()` → DEMO = 3, resto `None`; el tope real lo pone `licencias.max_sesiones`
  del LM/central.
- **Llaves de activación:** `POST /api/v1/activacion/llaves` (ADMIN) emite llave de **un solo uso
  por usuario** (`BS-XXXX-XXXX-XXXX`, SHA-256, expira 1 h–90 días, default 7).
  `POST /api/v1/activacion/validar` la canjea con `SELECT … FOR UPDATE`.
- **Series de numeración** (`series_numeracion`, migración 015): 1..N por empresa, contador
  transaccional `SELECT … FOR UPDATE`. `DELETE` de una serie ya usada responde **409**.
- **Permisos por categoría** (`app/core/seguridad_matrix.py`, migración 012): 18 módulos × 3 roles
  (ADMIN/OPERADOR/AUDITOR) con `ver`/`editar`/`ninguno`; ADMIN forzado a `editar`.
  `TRABAJADOR` se fusionó en `OPERADOR` (migración 025).
- **Multi-tenancy obligatorio:** `id_empresa` debe aparecer en **toda** consulta, filtro, inserción o
  validación (BD local y central). Ninguna métrica Prometheus ni log público debe exponerlo.
- **i18n:** backend `app/core/i18n.py` (139 claves × es/en/pt), frontend
  `lib/core/i18n/translations.dart` (848 × es/en/pt). El backend recibe idioma vía `?idioma=` /
  `Accept-Language`.
- **Paridad de ticket:** el layout canónico vive en **Flutter**
  (`lib/presentation/widgets/ticket_preview_dialog.dart`); el backend
  (`app/services/ticket_service.py`) debe reflejarlo exactamente (tabla LECTURA DE PESOS de
  5 columnas, v3.24). Cambiar uno obliga a cambiar el otro.
- **Kardex:** movimiento 10 = INGRESO (+), 60 = DESPACHO (−). Anular un boleto CERRADO registra
  el contra-asiento exacto; nunca se borra historial.

## Trampas conocidas

- `docs/MANEJO_DB.md` **ya no existe** (la arquitectura migró a `sdd/architecture/`), pero **decenas
  de comentarios del backend todavía lo citan** (`app/api/v1/endpoints/*.py`, `app/core/config.py`,
  `app/models_server.py`…) → son referencias colgadas; usar `sdd/architecture/overview.md` y los ADR.
- **Columnas reservadas:** `multi_despacho_recepcion` es una columna inerte (persiste y se
  sincroniza, 0 consultas la leen). Su contrato — *no usarla, no borrarla, no quitarla del
  round-trip* — vive en `sdd/architecture/views/logical-view.md` §2.3.1 y lo vigila
  `tests/test_api_docs.py::TestDocumentacionDeColumnasReservadas`. Si mueves esa sección, mueves
  el test.
- `TODO.md` y `PRD.md` están en `sdd/_inbox/`, no en la raíz; el comando `/update-all`
  (`.opencode/commands/update-all.md`) todavía los busca en la raíz.
- **El E2E de UI choca con la estación viva**: `lib/core/services/wserver_manager.dart` hace
  `fuser -k 8000/tcp` al cerrar la app → si la app Flutter está corriendo, el E2E falla por el
  puerto. **Sí se puede correr en local** (verificado) con la estación detenida:
  ```bash
  cd src/backend
  DATABASE_URL_SYNC=postgresql+psycopg2://sqlman:7767@localhost:5432/balansoft_ws_test \
    ./scripts/e2e_flutter.sh up      # BD + seed + stub LM + API en :8000
  cd ../frontend
  xvfb-run -a flutter test integration_test/pesaje_flow_test.dart -d linux
  cd ../backend && ./scripts/e2e_flutter.sh down
  ```
  Requiere `xvfb` + `libgtk-3-dev` + `libsecret-1-dev` (`flutter_secure_storage_linux`).
- `make test-e2e-ui` invoca `flutter test integration_test/… -d linux` **sin** `xvfb` → en headless
  falla; usar `xvfb-run -a`.
- `scripts/reset_total.sh` (raíz) respalda con `pg_dump -Fc` y **aborta si falta pg_dump**:
  los datos pesan más que la comodidad del reset.
- **Migraciones**: `setup_db.sh aplicar-migraciones` y el runtime WServer ignoran las variantes
  `*.mssql.sql` (son T-SQL). Si añades una migración para SQL Server, créala con ese sufijo.
- `scripts/setup_db.sh` y `e2e_flutter.sh` exigen `DATABASE_URL_SYNC` en el entorno o en
  `src/backend/.env` — incluso en modos que no tocan la BD (`down`).

## Versionado y releases

- SemVer pre-release `0.y.z-dev.B`; la **fuente de versión es `opencode.json`**.
- Commits de desarrollo: **sin tag**, Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`).
- Commits de release: **con tag anotado** — `git tag -a v0.4.2-dev.56 -m "Release v0.4.2-dev.56"`
  (dispara el pipeline de instaladores y empaquetado del WServer).
- Archivos a sincronizar en cada release: `opencode.json`, `src/frontend/pubspec.yaml`,
  `src/frontend/lib/core/config/app_config.dart`, `src/backend/pyproject.toml`
  (**PEP 440: `0.4.2.dev56`, sin guiones**), `CHANGELOG.md`.

## MCP de hardware

`opencode.json` → `mcpServers.balansoft-hardware` (stdio, `src/backend/scripts/mcp_hardware_server.py`).
6 herramientas: `parse_scale_frame`, `simulate_scale_frame`, `calculate_truck_weights`,
`format_ticket_weights_table`, `inspect_db_table`, `verify_iso_standards`.
Manual: `make run-mcp` o `python3 src/backend/scripts/mcp_hardware_server.py`.
