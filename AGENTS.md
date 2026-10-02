# AGENTS.md — BALANSOFT-WS

Sistema de estación de pesaje industrial multi-empresa: **backend FastAPI + frontend Flutter + panel del proveedor** cliente-servidor. **Idioma oficial del repo: español** (docs, comentarios, comunicación).

| Atributo      | Valor                                            |
|---------------|--------------------------------------------------|
| Versión       | 3.12                                             |
| Fecha         | 2026-10-02                                       |
| Estado        | Vigente                                          |
| Fuente        | `docs/MANEJO_DB.md` (arquitectura vigente) y código real |

---

## Comandos canónicos

| Comando                          | Lugar | Notas |
|----------------------------------|-------|-------|
| `uv sync`                        | `backend/` | Stack uv (`pyproject.toml` + `uv.lock`) |
| `uv run pytest -q`               | `backend/` | **328 tests rápidos** (~90 s), `-m "not e2e"`; requiere PostgreSQL real (ver Tests) |
| `uv run pytest tests/e2e`         | `backend/` | **34 tests E2E** (~15 s) contra el stub firmante del LM |
| `uv run ruff check app tests`    | `backend/` | line-length 100 |
| `uv run mypy tests/`             | `backend/` | |
| `flutter test` / `flutter analyze` | `frontend/` | **158 tests** unit/widget |
| `bash scripts/e2e_flutter.sh up`  | `backend/` | Entorno E2E Flutter: BD aislada + seed + stub LM + API en `127.0.0.1:8000` (`down` / `status` también) |
| `flutter test integration_test/pesaje_flow_test.dart -d linux` | `frontend/` | **1 E2E de UI** (login → entrada → salida → `CERRADO`); en local con `DISPLAY=:0`, en CI con `xvfb-run -a` |
| `uvicorn app.main:app --port 8000` | `backend/` | Levanta API local dev |
| `./scripts/build_wserver.sh`     | `backend/` | Compila WServer one-file (PyInstaller) |
| `./scripts/setup_db.sh instalar` | `backend/` | Aplica esquema local |
| `./scripts/verify.sh`            | `backend/` | Verificación de estación |
| `docker compose -f deploy/observability/docker-compose.observability.yml up -d` | `backend/` | Stack de observabilidad (Prometheus :9090, Grafana :3000 `admin/admin` solo dev, Alertmanager :9093) |
| `./scripts/reset_db.sh`          | `backend/` | Vacía ambas BD con esquema canónico |
| `./scripts/reset_total.sh`       | raíz | Reset total (respalda con `pg_dump -Fc` antes) |
| `uv run python scripts/seed_volumen.py --crear-bd` | `backend/` | Semilla P2: 50k boletos coherentes en `balansoft_ws_volumen` (`--drop-bd` la borra) |
| `uv run python scripts/benchmark_volumen.py` | `backend/` | P2: mide 11 endpoints con p50/p95/p99 contra la BD de volumen |
| `uv run python scripts/benchmark_concurrencia.py` | `backend/` | P2c: JWT + TCP reales y concurrencia (1/5/10 operadores) levantando su propio uvicorn de 1 worker |

⚠️ En esta máquina `uv` **no está en PATH**; hay un `backend/.venv/` gitignored con pytest/ruff/mypy (usar `backend/.venv/bin/python -m pytest -q` como fallback). No usar `backend/.venv.broken`.

---

## Arquitectura (lo NO obvio)

- **Una sola app FastAPI con dos roles** (dos bases de datos), decidido por `APP_ROLE=local|server` en `.env`:
  - `local` → estación operativa (boletos, catálogos, login-local offline). Monta `API_ROUTERS`.
  - `server` → central de cuenta/licencia/credenciales/sync/panel. Monta `SERVER_ROUTERS` (`app/api/v1/endpoints/servidor.py`).
  - Selector en `app/main.py`; modelos del servidor en `app/models_server.py` + motor `server_async_engine` (`app/core/database.py`).
- **No existe `backend/schema.sql`.** Los esquemas canónicos son **`backend/balansoft-ws-local.sql`** (**24 tablas**) y **`balansoft-ws-server.sql`** (10 tablas). Migraciones hacia adelante en `backend/migrations/*.sql` (**001–020**), idempotentes, sin Alembic.
- **Regla: 1 máquina local = 1 empresa = 1 cuenta.** Reglas, setup dev y flujo de login en `docs/MANEJO_DB.md`.
- **WServer**: backend local de la estación compilado con PyInstaller one-file (`backend/wserver.py` + `WServer.spec` + `scripts/build_wserver.sh`). En primera instalación crea runtime (`~/.balansoft-ws/wserver`, o `WSERVER_HOME`), genera `.env` desde `.env.plantilla` (SECRET_KEY aleatoria) y levanta la BD local + API en `0.0.0.0:8000` (accesible desde la LAN por IP; migra `API_HOST=127.0.0.1` previo y abre el puerto en ufw vía `pkexec`). La app Flutter lo lanza vía `frontend/lib/core/services/wserver_manager.dart` y muestra `Conexiones` en modo instalación (URL local prefijada `http://localhost:8000`).
- **Panel administrativo del proveedor** separado: `panel/` (HTML/Bootstrap) contra la API `APP_ROLE=server`. Seed: `backend/scripts/seed_panel_admin.py`. Licencia siempre se valida contra el LM (SGLB, firma Ed25519, `LICENSE_PUBLIC_KEY_PATH`).
- **HAL de balanza SÍ existe** (`app/core/scale_hal.py`, serial/TCP + `GET /weighing/scale/{id}/live`, `POST /balanzas/{id}/probar`, descubrimiento). Docs legacy que dicen "sin HAL" están desactualizados (ver Documentación).
- **Permisos por categoría**: `app/core/seguridad_matrix.py` + endpoint `seguridad.py` (migración `012`), en vez de solo roles globales. 18 módulos × 4 roles (ADMIN/OPERADOR/AUDITOR/TRABAJADOR) con acceso `ver`/`editar`/`ninguno`; ADMIN forzado a `editar` en todo.
- **Modelo de cuenta y dispositivos** (`docs/MANEJO_DB.md` §13): la primera máquina que activa la cuenta queda `SERVIDOR_LOCAL` en `servidor.dispositivos.rol`; las demás solo `LOCAL` (trabajador). La app instala en dos modos, persistido en `AppConfig.modoEstacion`:
  - `SERVIDOR` (titular, levanta WServer + BD local): preferencias → modo → entorno → BD → `/activation` (correo+contraseña contra el central con `modo_solicitado: SERVIDOR`; 403 si no es titular) → `/company_setup` **precargado** desde el central → dashboard con la sesión ya abierta.
  - `TRABAJADOR` (cliente delgado, sin BD ni WServer propios): preferencias → modo → `/worker_connection` (IP/puerto + `/health`) → login contra la API del servidor titular con usuarios locales.
- **i18n es/en/pt** en backend (`app/core/i18n.py`) y frontend (`translations.dart`, **621 claves por idioma**, paridad verificada por test). El backend recibe idioma vía `?idioma=`/`Accept-Language`.
- **Series de numeración** (`series_numeracion` + `boletos_pesaje.id_serie`, migración `015`): 1..N por empresa, contador transaccional (`FOR UPDATE`), prefijo/dígitos configurables. `DELETE` de serie usada responde **409**.
- **Identidad local** (`identidad_local`, singleton): vínculo con la cuenta central.
- **Observabilidad**: `MetricsMiddleware` (`app/core/monitoring.py`) + `GET /metrics` (Prometheus), bajo el flag `METRICS_ENABLED`; contadores `balansoft_http_requests_total`, `balansoft_api_latency_seconds`, `balansoft_pesajes_total`, `balansoft_license_errors_total`, `balansoft_active_users`. `_normalize_path()` sustituye UUIDs e IDs por `{id}` para acotar cardinalidad, y **ninguna métrica lleva `id_empresa`** (multi-tenancy: `/metrics` no puede filtrar por tenant). Andamiaje H6 en `backend/deploy/observability/` (scrape, 8 alertas, Alertmanager con receptor vacío, dashboard Grafana de 7 paneles) y `docs/OBSERVABILIDAD.md`; `tests/test_monitoring.py` falla si el andamiaje referencia una métrica inexistente o introduce `id_empresa` (el `null` del receptor de Alertmanager va entrecomillado: en YAML sin comillas es el valor nulo y el servicio no arranca). Rate limiting propio (sliding window, `rate_limit.py`); no se comparte entre workers (Redis pendiente). Logging en `app/core/logging_config.py` (consola + archivo rotado por tamaño, formato `text|json` vía `LOG_FORMAT`; rotación de sistema en `backend/deploy/balansoft-ws.logrotate`).
- **Auditoría (D4 cerrado)**: `GET /api/v1/auditoria` (`app/api/v1/endpoints/auditoria.py`) devuelve la tabla `auditoria` completa (acción, entidad, entidad_id, detalle, email de usuario, IP, `created_at` UTC) con filtros `entidad/accion/fecha_desde/fecha_hasta/skip/limit`; solo roles ADMIN/AUDITOR. La UI de Auditoría tiene pestañas "Transaccional" / "Registro".
- **CI (H1 + H2 + H2b)**: `.github/workflows/ci.yml` con cuatro jobs encadenados: `backend` (PostgreSQL 16 en servicio, `uv sync --all-groups`, `ruff check app tests`, `mypy tests/`, `pytest -q -m "not e2e"`), `e2e` (PostgreSQL 16 + `generate_signing_keys.py` en el runner → claves **nunca commiteadas** → `pytest tests/e2e`), `frontend` (Flutter 3.47.2 estable, `flutter analyze`, `flutter test`) y **`e2e-flutter`** (necesita `backend` + `frontend`: PostgreSQL 16, deps de escritorio Linux (GTK/CMake/Ninja), `flutter config --enable-linux-desktop`, `backend/scripts/e2e_flutter.sh up` y `xvfb-run -a flutter test integration_test/pesaje_flow_test.dart -d linux` con un reintento; en fallo vuelca `/tmp/balansoft-e2e-flutter/api.log` y `lm.log`).
- **Stub del LM (H2)**: `backend/scripts/lm_stub.py` es un LM FastAPI que **firma de verdad** con Ed25519. Rutas `/health`, `/token`, `/validate`, `/activate`, `/{license_key}/check` y `/__mode/{modo}`; modos `valid` (default), `invalid` (SUSPENDIDA), `expired`, `tamper` (altera un campo firmado después de firmar) y `unreachable` (503). Claves por `LM_STUB_PRIVATE_KEY_PATH`/`LICENSE_PRIVATE_KEY_PATH`, puerto `LM_STUB_PORT` (9100); sin clave genera un par efímero en memoria (solo dev/CI). Uso manual: `python -m scripts.lm_stub` + `LICENSE_API_URL=http://127.0.0.1:9100`.
- **E2E de UI (H2b)**: `frontend/integration_test/pesaje_flow_test.dart` recorre el flujo real de la estación (`/login` → Reportes → Entradas → `nuevo_pesaje_btn` → entrada confirmada → salida desde `_BoletoPendienteDialog` → diálogo de impresión → historial con el boleto `CERRADO`). Dos modos: **seed** (hermético, `admin@balansoft.demo`/`demo1234` contra la BD que crea `scripts/e2e_flutter.sh`, company/license sembradas en memoria) e **instalada** (`--dart-define E2E_INSTALADA=true E2E_EMAIL=… E2E_PASS=…`, contra la estación real sin falsear empresa ni licencia). Variables: `E2E_EMAIL`, `E2E_PASS`, `E2E_BASE_URL` (default `http://localhost:8000`; si la estación real ya ocupa el 8000, levantar el entorno E2E en otro puerto: `E2E_API_PORT=8010 E2E_LM_PORT=9110 bash scripts/e2e_flutter.sh up` + `--dart-define=E2E_BASE_URL=http://127.0.0.1:8010`). El modo seed asigna los campos estáticos de `AppConfig` **sin escribir en las preferencias**, para no falsear el estado de instalación de una estación real en la misma máquina. Se apoya en keys estables añadidas para el E2E (`menu_${clave}`, `menu_grupo_${label}`, `capturar_peso_button`, `boleto_pendiente_${placa}`, `boleto_fila_${placa}`). El E2E detectó y corrigió bugs reales: sin báscula el peso manual tecleado no se podía fijar (`Capturar peso` deshabilitado y `weighing_state_confirm` se saltaba), y `AutocompleteCreatable` llamaba `setState` durante el build.
- **E2E (H2)**: `backend/tests/e2e/` (marcador `e2e`, 34 tests) levanta el stub en un hilo de uvicorn con claves efímeras e inyecta la clave pública en el `LicenseClient` (firma verificada de verdad, sin bypass): contrato firmado (firma, `tamper`, anti-replay de `nonce`, ventana de `server_time`, metadata), flujo de licencia por API (login, `validate-license`, `GET /auth/license`, pesajes) y ciclo offline (`/sync/push` idempotente, `/sync/status`, `/sync/pull`, `sync_logs`).

---

## Configuración (`.env`)

- Referencias: `backend/.env.example` (producción), `backend/.env.plantilla` (plantilla embebida del WServer), `docs/MANEJO_DB.md §11`.
- Claves clave: `DATABASE_URL`/`DATABASE_URL_SYNC` (obligatorio el par async/sync), `APP_ROLE`, `SERVER_API_URL` + `SERVER_DATABASE_URL` (solo rol local), `SECRET_KEY` (generar con `openssl rand -hex 32`), `API_HOST`/`API_PORT` (dev `127.0.0.1:8000`; servidor real `0.0.0.0:8002`), `LICENSE_API_URL` (en estaciones `https://lm.balansoft.com.ve/api/v1`; en el servidor central con LM local `127.0.0.1:9001/api/v1`), `LICENSE_PRODUCT_CODE=WS` (ojo: el default de `config.py` es `BWS`), `RATE_LIMIT_*`, `API_DOCS_ENABLED` (estaciones: `true` desde v2.4 → `/docs`, `/redoc` y `/openapi.json` expuestos **por diseño**; ver `MANEJO_DB.md` §11.4), `METRICS_ENABLED`, `MEDIA_DIR`, `MAX_IMAGE_BYTES`, `ALLOWED_IMAGE_TYPES`, `PASSWORD_RESET_*`, `SMTP_*`, `BACKUP_DIR`/`BACKUP_RETENTION_DAYS`.
- En dev actual: `APP_ROLE=local` contra la BD `balansoft_ws_local` (el `.env` apunta ahí); `balansoft_ws_server` es la **réplica local del central** (rol `server`, puerto dev `8002`, redoc en §7.1 de MANEJO_DB). `reset_total.sh` (v1.2.7) **respalda las BD con `pg_dump -Fc` antes de borrarlas** y aborta si el respaldo falla.

---

## Tests

- Requieren **PostgreSQL real**: la BD de tests `balansoft_ws_test` se deriva de `settings.database_url` (overridable con `TEST_DATABASE_URL`) en `backend/tests/conftest.py`. Sin DB levantada los tests fallan antes de correr. La BD de tests del rol `server` es `balansoft_ws_server_test`.
- Cada test recibe sesión limpia y al finalizar se **truncan todas las tablas** (`TRUNCATE ... RESTART IDENTITY CASCADE`).
- `tests/test_api_server.py` prueba el rol `server` sobre `balansoft_ws_server_test`; `tests/test_scale_hal.py` usa sessions TCP reales (se cierran tras cada test via `scale_session`).
- Hay worker de sesiones de balanza global (`app/core/scale_session.py`), no dejarlo abierto entre tests.
- **Estado actual**: backend **362/362** en verde (328 rápidos ~89 s + 34 E2E ~15 s); frontend **158/158** unit/widget + **1/1** E2E de UI en verde; `flutter analyze` limpio. Ruff y mypy sin hallazgos.
- Comandos: `uv run pytest -q`, `uv run pytest tests/e2e`, `uv run ruff check app tests`, `uv run mypy tests/` (backend); `flutter test`, `flutter analyze`, `flutter test integration_test/pesaje_flow_test.dart -d linux`, `flutter build linux --release` (frontend).

---

## Documentación (`docs/`)

- **Vigente / autoritativa**: `docs/MANEJO_DB.md` (arquitectura de dos BDs, setup dev, flujo login, estado y plan), `docs/NAV.md` (navegación/sidebar), `docs/INPUTS_MAP.md` (atajos de teclado de la UI), `docs/MODELO_ESTANDAR.md` (roles y reglas de negocio), `docs/I18N_Y_ONBOARDING.md` (i18n y onboarding), `docs/USO-API.md`, `docs/SESIONES.md`, `docs/PLANES-PAGOS.md`, `docs/OBSERVABILIDAD.md` (métricas, alertas y diagnóstico).
- **Inventario de implementación**: `IMPLEMENTADO.md` v2.0 (2026-10-01) — inventario de lo construido, verificado contra código.
- **Legacy, NO fiarse**: `docs/DOCUMENTACION VIEJA/` (PRD, ARCH, MODEL, UI-UX, DEPLOY, ...). Contienen afirmaciones que contradicen la implementación (stack .NET/WinForms, "sin HAL", `schema.sql`) y MANEJO_DB §12 los marca "requieren actualización". Ante conflicto, mandan el código y MANEJO_DB.
- **Reglas de negocio invariables**: boleto con 4 estados `PENDIENTE → CERRADO/MODIFICADO → ANULADO` (abrir = ruleta secuencial `TA-00000001`); kardex numérico ID `10` INGRESO (positivo) / `60` DESPACHO (negativo), al anular un CERRADO se registra el movimiento **inverso**; el peso capturado por la báscula nunca se edita; timestamps en UTC (conversión a local solo en Flutter).

---

## Convenciones

- Los MD siguen cabecera editorial (Versión, Fecha, Estado, Autor, Norma, Fuente) e identificadores trazables `REQ-FN-NNN`, `REQ-NF-<área>-NNN`, `AR-NNN`, `INT-NNN`, `UX-NNN`.
- Al cambiar requisitos/rutas/roles, actualizar primero la doc vigente (MANEJO_DB/PRD) antes que el código.

---

## Deuda técnica conocida

**Cerrada el 2026-10-01** (tanda `/update-all`); se conserva el registro:

| # | Deuda | Ubicación | Estado |
|---|-------|-----------|--------|
| D1 | `AppConstants.dbVersion = 1` vs `version: 5` real | `frontend/lib/core/constants/` vs `database_helper.dart` | ✅ Corregido (`dbVersion = 5`) |
| D2 | `LicenseConfig.productCode = 'BWS'` vs backend `LICENSE_PRODUCT_CODE=WS` | `frontend/lib/core/config/` vs `backend/.env` | ✅ Corregido (`WS`) |
| D3 | Ajustes → Sincronización sin efecto | `frontend/lib/presentation/screens/settings/` | ✅ Cableado al `SyncBloc` |
| D4 | UI Auditoría sin volcado completo de `auditoria` | `frontend/lib/presentation/screens/auditoria/` | ✅ `GET /api/v1/auditoria` + pestaña "Registro" |
| D5 | Rate limiting no se comparte entre workers (4× efectivo en prod) | `backend/app/core/rate_limit.py` | ⚠️ Documentado; Redis sigue pendiente |
| D6 | `docs/MANEJO_DB.md` citaba 22 tablas locales; el esquema tiene 24 | `docs/MANEJO_DB.md` | ✅ Corregido |

---

## Pendientes aceptados (requieren entorno/cliente)

| # | Pendiente | Requiere |
|---|-----------|----------|
| P1 | Pruebas con balanza física (Toledo/Rice Lake/Sartorius) | Hardware real |
| P3 | HTTPS/TLS con nginx | Dominio + certificado |
| P4 | Manuales de usuario con capturas | Producto final |
| P5 | Proceso de soporte formal (SLA, escalación) | Proceso |
| P6 | CI/CD completo | Pipeline |
| P7 | Automatización de backups del LM | Infra |
| P8 | Regenerar WServer + bundles Flutter/APK | Build |

---

## Historial

| Versión | Fecha | Cambios |
|---------|-------|---------|
| 3.12 | 2026-10-02 | **CI en verde por primera vez: los cuatro jobs pasaban a la vez.** El job `Frontend` llevaba rojo desde `30eff14` (v3.11) y el `E2E Flutter` **nunca se había ejecutado con éxito**: estaba enmascarado porque `Frontend` fallaba antes y lo dejaba en `skipped`. Al arreglar el warning aparecieron dos fallos reales que nadie había visto: (1) **faltaba `libsecret-1-dev`** en las dependencias de escritorio del workflow, y el plugin `flutter_secure_storage_linux` lo exige (`pkg_check_modules libsecret-1>=0.18.4`), así que la compilación de Linux abortaba con "Unable to generate build files" antes de ejecutar un test; (2) un **overflow de 4,3 px** en el `DropdownButtonFormField` de "Tipo de Tercero" (`weighing_form_screen.dart:2194`), que comparte fila con "Razón Social" — el campo hermano "Medida" del mismo archivo ya usaba `isExpanded: true` y este se había quedado sin él. Con `isExpanded: true` el texto se elipsiza. Las 2 excepciones restantes del log eran en cascada del inspector sobre el árbol que el overflow dejaba inestable. Nota: el push de los commits de P2/H6 **subió también 2dbce89 (H2b) y 8db9a3f**, que seguían sin publicar; la rama quedó 4 commits por detrás de lo que se creía. |
| 3.11 | 2026-10-02 | **El job `Frontend` de CI estaba en rojo, y `AGENTS.md` lo describía falsamente como "warning preexistente inocuo".** `flutter analyze` trata los warnings como **error** (salida 1), así que la variable muerta `esRojo` en `scale_monitor_widget.dart` tumbaba el job entero desde el commit `30eff14`. No era cosmético: `CI main` salía rojo mientras la documentación afirmaba que el análisis estaba limpio. La variable era código muerto (el ternario de color usa `esVerde`/`esAmarillo` y cae a `danger` por abandono, igual que `estadoTexto` con su `else`), así que se eliminó: **cero cambio de comportamiento**. `flutter analyze` → `No issues found!`; 158/158 tests unit/widget en verde. Lección: un warning "conocido" en un job que falla es un job rojo, no una nota al pie. |
| 3.10 | 2026-10-02 | Corrección del conteo de tests en este documento (era una mentira en tres sitios, no uno: la tabla de comandos decía **310 tests rápidos**, que con los 34 E2E daba 344, y el estado actual decía 354; las filas históricas 3.7/3.8 se conservan tal cual porque eran exactas en su momento). Estado real verificado por separado: **328** rápidos (`pytest -m "not e2e"`, 89 s) + **34** E2E = **362**. La fila 3.9 decía «Tests 354 sin cambios de lógica», pero ese hito sí añadió 8 tests (`test_api_docs.py`), así que se corrige a 354 → 362. Sin cambios de código. |
| 3.9 | 2026-10-02 | Cierre de `multi_despacho_recepcion` (B-doc) y H14 corregido. **La columna queda documentada como RESERVADA/INERTE en `docs/MANEJO_DB.md` §6.3**: se persiste (DDL, modelos, create, sync, mapper Flutter) pero tiene **0 apariciones en cualquier consulta**, ninguna UI la expone y ningún documento vigente define su semántica. Decisión explícita: **documentar sí, tocar el sync no** — quitarlo del round-trip ahorraría ~35 bytes/boleto (~17,5 MB en una década) a cambio de un riesgo real de pérdida (si una estación tuviera el flag en `true`, el backend escribiría `FALSE` encima) y rompería la preservación del valor si algún día se implementa. **H14 (Redoc) estaba "cerrada" pero no llegaba a los integradores**: `.env.plantilla` traía `API_DOCS_ENABLED=false`, así que toda estación instalada servía 404 en `/docs` y `/redoc`, mientras `/openapi.json` publicaba las 82 rutas igualmente (`openapi_url` es independiente de la bandera): se pagaba la documentación sin obtener seguridad. Ahora `.env.plantilla` va con `true` y la exposición queda **explícita y documentada** (`MANEJO_DB.md` §11.4), con la recomendación de que restringir exija **autenticación**, no volver a la bandera. Verificado: `/redoc` 200 HTML, `/docs` 200, `/openapi.json` 200 (136 KB). Ojo: solo afecta a instalaciones **nuevas**; las que ya tengan su `.env` generado conservan el valor previo. `.env.example` (servidor central, internet-facing) sigue en `false` a propósito, con perfil de riesgo distinto. También se corrigió el conteo de tablas de §6 en MANEJO_DB (22 → **24**, D6 hadn't reached this doc). Se añaden 8 tests de regresión en `backend/tests/test_api_docs.py` que fijan ambas decisiones (la plantilla habilita documentación, `.env.example` sigue en `false`, y **`openapi_url` no se condiciona a la bandera**); verificados en negativo. Tests 354 → **362**, sin cambios de lógica de negocio. Pendientes: H3, H4, H12, H15, D5 y P1, P3-P8. |
| 3.8 | 2026-10-02 | P2b falsado y P2c cerrado. **`multi_despacho_recepcion` es una columna inerte**: se persiste (esquema, 3 modelos, create, sync, mapper Flutter) pero tiene **0 apariciones en cualquier `SELECT`/`WHERE`/`GROUP BY`/`ORDER BY`**, ninguna UI la expone y ningún documento define su semántica (solo aparece en el DDL de `ARCH.md`). Probado empíricamente: 10 000 boletos marcados con el flag dieron `reports/daily` 4,0→4,6 ms y `reports/monthly` 3,9→3,9 ms, idénticos dentro del ruido; la degradación 2-5× hipótesis **no puede ocurrir porque la condición no está implementada**. No se borró la columna (rompe clientes y sync) ni se implementó (exige decisión de negocio): queda documentado en `docs/evidencia/volumen-analisis.md` §7. P2c (`scripts/benchmark_concurrencia.py`) midió el costo real de JWT + TCP contra un uvicorn de 1 worker como el de `wserver.py`: **~20 ms** de sobrecoste (no los 5-15 supuestos), `/weighing/list` p50 39,8 ms con 1 operador y **p95 200,5 ms con 10** (en el umbral); bajo saturación el rendimiento se plafona en **~40-45 req/s** y la latencia crece linealmente, con **cero 5xx hasta 50 operadores**. Control: `/health` alcanza 660 req/s con el mismo cliente, luego el techo es del servidor. Tests 354 en verde (sin cambios de lógica). Pendientes: H3, H4, H12, H15 y P1, P3-P8. |
| 3.7 | 2026-10-02 | P2 (prueba de volumen) cerrado: `scripts/seed_volumen.py` (50k boletos coherentes en `balansoft_ws_volumen`, 10 invariantes verificados) y `scripts/benchmark_volumen.py` (11 endpoints, p50/p95/p99 con umbrales). **Bug real de producción encontrado y corregido**: `/weighing/list` y `/weighing/pendientes` enriquecían fila por fila (`_enriquecer_pesaje_ticket`, hasta 10 consultas por registro → ~1000 idas y vueltas por página de 100 boletos), con 450 ms p50 a 50k. No era un problema de índices: SQL 0,6 ms + `COUNT` 4,7 ms de los 450 ms. Resuelto con `_enriquecer_pesajes_lista` (7 consultas por página, constante, y todas filtradas por `id_empresa`): 445→20 ms y 463→13 ms. **No** se creó la migración 021 de índices porque la hipótesis inicial no se confirmó. 3 tests de regresión (`TestListadoNoEsNMasUno`) verificados en negativo. Tests backend 351 → 354 (320 + 34 E2E). Evidencia: `docs/evidencia/volumen-analisis.md` y `volumen-benchmark.txt`. Pendientes: H3, H4, H12, H15 y P1, P3-P8. |
| 3.6 | 2026-10-01 | H6 (andamiaje): `backend/deploy/observability/` con `prometheus.yml` (job `balansoft-api`), 8 reglas de alerta en `alerts/balansoft-alerts.yml` (caída, latencia p95, 5xx, 4xx, licencia, sin uso, pesajes detenidos), `alertmanager.yml` (receptor `null` en dev y silenciado de síntomas cuando la API está caída), `grafana/` con datasource y dashboard provisionado de 7 paneles sobre las 5 métricas existentes, `docker-compose.observability.yml` y README. Documento vigente `docs/OBSERVABILIDAD.md` (métricas, cardinalidad, alertas, multi-tenancy, diagnóstico). Tests nuevos en `tests/test_monitoring.py`: el andamiaje está completo y es válido, y ninguna alerta ni panel referencia una métrica inexistente ni `id_empresa`. Tests backend 344 → 351 (317 + 34 E2E). Sin métricas nuevas ni cambios en la lógica de negocio. Pendiente de infra: canal de notificación, retención y TLS. Pendientes: H3, H4, H12, H15 y P1–P8. |
| 3.5 | 2026-10-01 | H2b cerrado: `frontend/integration_test/pesaje_flow_test.dart` (E2E de UI del flujo completo login → entrada → salida → `CERRADO`) con modo seed hermético y modo estación instalada; keys estables de navegación (`menu_*`) y de filas (`boleto_pendiente_*`, `boleto_fila_*`) para que el test no dependa del texto; `backend/scripts/e2e_flutter.sh` (BD aislada + seed + stub LM + API) y `seed_e2e_flutter.py`; job `e2e-flutter` en CI (xvfb + GTK + reintento). Bugs reales corregidos por el E2E: el peso manual sin báscula no se podía fijar en el formulario y `AutocompleteCreatable` llamaba `setState` durante el build. Verificado en verde contra la estación real activada (WServer + BD `balansoft_ws_local`, empresa `Variedades S&S`, licencia `ACTIVA`) y dos corridas consecutivas en modo seed. Tests backend 343 → 344 (310 + 34 E2E); frontend 158 unit/widget + 1 E2E. Pendientes: H3, H4, H6, H12, H15 y P1–P8. |
| 3.4 | 2026-10-01 | H2 cerrado: stub del LM firmante con Ed25519 (`scripts/lm_stub.py`), 33 tests E2E (`tests/e2e/`), marcador `e2e` y job `e2e` en CI con claves generadas en el runner. El E2E detectó y se corrigió un bug real: `SyncService.process_batch` insertaba fechas con offset en columnas naive (`DataError`, lote offline caído) → `_naive_utc()`. Tests backend 305 → 343 (310 + 33 E2E). Pendientes: H2b (E2E Flutter), H3, H4, H6, H12, H15 y P1–P8. |
| 3.3 | 2026-10-01 | Cierre de la tanda `/update-all`: D1 (`dbVersion=5`), D2 (`productCode=WS`), D3 (sincronización de Ajustes real), D4 (`GET /api/v1/auditoria` + pestaña "Registro" en la UI), D6 (24 tablas) y D5 documentado; H1 (CI en `.github/workflows/ci.yml`), H5 (`app/core/logging_config.py`, JSON + rotación), H7 (`deploy/balansoft-ws.logrotate`), H8 (fail-fast de producción en `config.py`), H10 (`app/core/image_compress.py`, Pillow) y H11 (`limit`/`skip`/`catalogo` en `/catalogo/sync`). Tests backend 289 → 305. Pendientes: H2 (stub del LM), H3, H4, H6, H12, H15 y P1–P8. |
| 3.2 | 2026-10-01 | Alineación con `IMPLEMENTADO.md` v2.0: tests 289 backend + 158 frontend; i18n es/en/pt (621 claves); HAL de balanza confirmado (serial/TCP); series de numeración; identidad local; observabilidad (Prometheus + rate limiting); comandos de scripts (`build_wserver.sh`, `setup_db.sh`, `verify.sh`, `reset_db.sh`, `reset_total.sh`); deuda técnica D1–D6 y pendientes P1–P8 documentados; panel del proveedor en `panel/` (no `BALASOFT-UI/panel`). |
| 3.1 | 2026-09-29 | Dev actual a dos BDs (`balansoft_ws_local` + réplica central `balansoft_ws_server` dev :8002, seed titular + panel en §7.1); `reset_total.sh` v1.2.7 respalda las BDs (`pg_dump -Fc`) antes de borrar y aborta si falla; `seed_reset_demo.sql` repone la operación demo local. |
| 3.0 | 2026-09-21 | Re-alineación: repo es git; docs activas (MANEJO_DB/NAV/INPUTS_MAP/MODELO_ESTANDAR); arquitectura de dos BDs (`APP_ROLE`), WServer/PyInstaller, panel BALASOFT-UI, seguridad por categorías; sin `schema.sql` (local/server.sql); tests 268; `uv` ausente en PATH. |

---

**Documento vivo**: actualizar al cambiar arquitectura, comandos, tests o documentación autoritativa.