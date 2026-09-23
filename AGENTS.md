# AGENTS.md — BALANSOFT-WS

Sistema de estación de pesaje industrial multi-empresa: **backend FastAPI + frontend Flutter** cliente-servidor. **Idioma oficial del repo: español** (docs, comentarios, comunicación).

| Atributo      | Valor                                            |
|---------------|--------------------------------------------------|
| Versión       | 3.0                                              |
| Fecha         | 2026-09-21                                       |
| Estado        | Vigente                                          |
| Fuente        | `docs/MANEJO_DB.md` (arquitectura vigente) y código |

---

## Comandos canónicos

| Comando                          | Lugar | Notas |
|----------------------------------|-------|-------|
| `uv sync`                        | `backend/` | Stack uv (`pyproject.toml` + `uv.lock`) |
| `uv run pytest -q`               | `backend/` | **154 tests** (~75 s); requiere PostgreSQL real (ver Tests) |
| `uv run ruff check app tests`    | `backend/` | line-length 100 |
| `uv run mypy tests/`             | `backend/` | |
| `flutter test` / `flutter analyze` | `frontend/` | |
| `uvicorn app.main:app --port 8000` | `backend/` | Levanta API local dev |

⚠️ En esta máquina `uv` **no está en PATH**; hay un `backend/.venv/` gitignored con pytest/ruff/mypy (usar `backend/.venv/bin/python -m pytest -q` como fallback). No usar `backend/.venv.broken`.

---

## Arquitectura (lo NO obvio)

- **Una sola app FastAPI con dos roles** (dos bases de datos), decidido por `APP_ROLE=local|server` en `.env`:
  - `local` → estación operativa (boletos, catálogos, login-local offline). Monta `API_ROUTERS`.
  - `server` → central de cuenta/licencia/credenciales/sync/panel. Monta `SERVER_ROUTERS` (`app/api/v1/endpoints/servidor.py`).
  - Selector en `app/main.py`; modelos del servidor en `app/models_server.py` + motor `server_async_engine` (`app/core/database.py`).
- **No existe `backend/schema.sql`.** Los esquemas canónicos son **`backend/balansoft-ws-local.sql`** (22 tablas) y **`balansoft-ws-server.sql`** (10 tablas). Migraciones hacia adelante en `backend/migrations/*.sql` (001–012), idempotentes, sin Alembic.
- **Regla: 1 máquina local = 1 empresa = 1 cuenta.** Reglas, setup dev y flujo de login en `docs/MANEJO_DB.md`.
- **WServer**: backend local de la estación compilado con PyInstaller one-file (`backend/wserver.py` + `WServer.spec` + `scripts/build_wserver.sh`). En primera instalación crea runtime (`~/.balansoft-ws/wserver`, o `WSERVER_HOME`), genera `.env` desde `.env.plantilla` (SECRET_KEY aleatoria) y levanta la BD local + API en `127.0.0.1:8000`. La app Flutter lo lanza vía `frontend/lib/core/services/wserver_manager.dart` y muestra `Conexiones` en modo instalación.
- **Panel administrativo del proveedor** separado: `BALASOFT-UI/panel` (HTML/Bootstrap) contra la API `APP_ROLE=server`. Seed: `backend/scripts/seed_panel_admin.py`. Licencia siempre se valida contra el LM (SGLB, firma Ed25519, `LICENSE_PUBLIC_KEY_PATH`).
- **HAL de balanza SÍ existe** (`app/core/scale_hal.py`, serial/TCP + `GET /weighing/scale/{id}/live`). Docs legacy que dicen "sin HAL" están desactualizados (ver Documentación).
- **Permisos por categoría**: `app/core/seguridad_matrix.py` + endpoint `seguridad.py` (migración `012`), en vez de solo roles globales.

---

## Configuración (`.env`)

- Referencias: `backend/.env.example` (producción), `backend/.env.plantilla` (plantilla embebida del WServer), `docs/MANEJO_DB.md §11`.
- Claves clave: `DATABASE_URL`/`DATABASE_URL_SYNC` (obligatorio el par async/sync), `APP_ROLE`, `SERVER_API_URL` + `SERVER_DATABASE_URL` (solo rol local), `SECRET_KEY` (generar con `openssl rand -hex 32`), `API_HOST`/`API_PORT` (dev `127.0.0.1:8000`; servidor real `0.0.0.0:8002`), `LICENSE_API_URL` (en estaciones `https://lm.balansoft.com.ve/api/v1`; en el servidor central con LM local `127.0.0.1:9001/api/v1`), `LICENSE_PRODUCT_CODE=WS` (ojo: el default de `config.py` es `BWS`), `RATE_LIMIT_*`, `METRICS_ENABLED`.
- En dev actual: `APP_ROLE=local` contra la BD `balansoft_ws` (single-DB). Las BDs split de prueba son `balansoft_ws_server` y `balansoft_ws_local` (mismo PostgreSQL local).

---

## Tests

- Requieren **PostgreSQL real**: la BD de tests `balansoft_ws_test` se deriva de `settings.database_url` (overridable con `TEST_DATABASE_URL`) en `backend/tests/conftest.py`. Sin DB levantada los tests fallan antes de correr.
- Cada test recibe sesión limpia y al finalizar se **truncan todas las tablas** (`TRUNCATE ... RESTART IDENTITY CASCADE`).
- `tests/test_api_server.py` prueba el rol `server` sobre `balansoft_ws_server_test`; `tests/test_scale_hal.py` usa sessions TCP reales (se cierran tras cada test via `scale_session`).
- Hay worker de sesiones de balanza global (`app/core/scale_session.py`), no dejarlo abierto entre tests.

---

## Documentación (`docs/`)

- **Vigente / autoritativa**: `docs/MANEJO_DB.md` (arquitectura de dos BDs, setup dev, flujo login, estado y plan), `docs/NAV.md` (navegación/sidebar), `docs/INPUTS_MAP.md` (atajos de teclado de la UI), `docs/MODELO_ESTANDAR.md` (roles y reglas de negocio).
- **Legacy, NO fiarse**: `docs/DOCUMENTACION VIEJA/` (PRD, ARCH, MODEL, UI-UX, DEPLOY, ...). Contienen afirmaciones que contradicen la implementación (stack .NET/WinForms, "sin HAL", `schema.sql`) y MANEJO_DB §12 los marca "requieren actualización". Ante conflicto, mandan el código y MANEJO_DB.
- **Reglas de negocio invariables**: boleto con 4 estados `PENDIENTE → CERRADO/MODIFICADO → ANULADO` (abrir = ruleta secuencial `TA-00000001`); kardex numérico ID `10` INGRESO (positivo) / `60` DESPACHO (negativo), al anular un CERRADO se registra el movimiento **inverso**; el peso capturado por la báscula nunca se edita; timestamps en UTC (conversión a local solo en Flutter).

---

## Convenciones

- Los MD siguen cabecera editorial (Versión, Fecha, Estado, Autor, Norma, Fuente) e identificadores trazables `REQ-FN-NNN`, `REQ-NF-<área>-NNN`, `AR-NNN`, `INT-NNN`, `UX-NNN`.
- Al cambiar requisitos/rutas/roles, actualizar primero la doc vigente (MANEJO_DB/PRD) antes que el código.

## Historial

| Versión | Fecha | Cambios |
|---------|-------|---------|
| 3.0 | 2026-09-21 | Re-alineación: repo es git; docs activas (MANEJO_DB/NAV/INPUTS_MAP/MODELO_ESTANDAR); arquitectura de dos BDs (`APP_ROLE`), WServer/PyInstaller, panel BALASOFT-UI, seguridad por categorías; sin `schema.sql` (local/server.sql); tests 154; `uv` ausente en PATH. |