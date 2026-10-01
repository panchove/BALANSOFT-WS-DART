# Estado de Implementación de BALANSOFT-WS

| Atributo          | Valor                                    |
|-------------------|------------------------------------------|
| **Documento**     | IMPLEMENTADO.md                          |
| **Versión**       | 2.2                                      |
| **Fecha**         | 2026-10-01                               |
| **Estado**        | Vigente (inventario de implementación)   |
| **Autor**         | Equipo BALANSOFT                         |
| **Norma**         | ISO/IEC/IEEE 42010 + 29148               |
| **Fuente**        | Código real (`backend/`, `frontend/`, `panel/`) y `docs/MANEJO_DB.md` (arquitectura vigente) |

> Este documento detalla **lo que realmente está construido** en el repositorio en este momento, verificado contra el código (343 tests backend —310 rápidos + 33 E2E— y 158 tests frontend en verde). No es una especificación de objetivos: es un inventario del estado vigente de implementación.
>
> **Arquitectura vigente:** una sola app FastAPI con **dos roles** (`APP_ROLE=local|server`) y **dos bases de datos**. Para la arquitectura autoritativa ver `docs/MANEJO_DB.md`; este documento es su inventario de implementación.

---

## Historial del documento

**Cambios en v1.2 (2026-09-14):** fotos de camión/remolque en pesaje y catálogos; peso en vivo por TCP (`ScaleTcpClient` + `ScaleMonitorWidget`); módulo de básculas WS en el simulador BSDD; guardado de reportes/tickets/kardex en Descargas; layouts responsive; validadores.

**Cambios en v1.3 (2026-09-14):** HAL de balanza en backend (`scale_hal.py`: SerialScaleHAL, TcpScaleHAL + factory) y endpoint `GET /weighing/scale/{balanza_id}/live`; migración `005_balanza_hardware`; 8 tests de HAL.

**Cambios en v1.4 (2026-09-14):** integración del HAL en el frontend (`ScaleApiClient` API-first + fallback TCP); pantalla de Administración de Licencias (ADMIN); reportes avanzados; pruebas E2E; OpenAPI ampliado.

**Cambios en v1.5 (2026-09-14):** rate-limiting propio (`rate_limit.py`), CORS endurecido, monitoreo Prometheus (`monitoring.py` + `GET /metrics`), scripts `backup.sh`/`verify.sh`/`install_cliente.sh`.

**Cambios en v1.6 (2026-09-14):** módulo de Dispositivos (configuración de hardware, `POST /balanzas/{id}/probar`, monitoreo en vivo).

**Cambios en v2.0 (2026-10-01):** **realineación completa con la arquitectura actual**. La app pasó a **dos roles/BD** (`APP_ROLE=local|server`, `balansoft-ws-local.sql` + `balansoft-ws-server.sql`), se eliminó `backend/schema.sql` (001–020 migraciones), se añadió **WServer** (backend local PyInstaller), el **asistente de primera instalación** en dos modos (`SERVIDOR`/`TRABAJADOR`), **seguridad por categorías** (`seguridad_matrix.py` + `permisos_acceso`), **series de numeración**, **identidad local**, **categorías de productos**, **mensajes i18n es/en/pt** en backend y frontend (`621` claves por idioma), **tickets PDF/TXT** con presets de impresora, **panel administrativo del proveedor** (`panel/`, rol server), **auditoría de UI**, **ajustes de inventario**, y —en el formulario de pesaje— **conversión de unidades**, **captura guiada cabina→remolque**, **tabla de pesos/tolerancia**, **búsqueda rápida con copia**, **protección de datos sin guardar** y **arranque maximizado**. Se actualizan los conteos de tests a la realidad: **backend 310/310** (sin E2E) y **frontend 158/158**.

**Cambios en v2.1 (2026-10-01, tanda `/update-all`):** se cierra la deuda técnica D1-D6 y los ítems de hardening H1, H5, H7, H8, H10 y H11: **volcado completo de `auditoria`** (`GET /api/v1/auditoria` + pestaña "Registro" de la UI), **sincronización de Ajustes** cableada al `SyncBloc`, `dbVersion = 5` y `productCode = 'WS'`, **paginación de `/catalogo/sync`** (`limit`/`skip`/`catalogo`/`totales`/`truncado`), **compresión de imágenes** (`image_compress.py` con Pillow), **logging JSON rotado** (`logging_config.py` + `deploy/balansoft-ws.logrotate`), **fail-fast de producción** en `config.py` y **CI en GitHub Actions**. Tests backend 289 → **305**.

**Cambios en v2.2 (2026-10-01, H2):** se cierra el E2E en CI. Nuevo **stub del License Manager** (`backend/scripts/lm_stub.py`, FastAPI + Ed25519 real, modos `valid`/`invalid`/`expired`/`tamper`/`unreachable`), **33 pruebas E2E** en `backend/tests/e2e/` (contrato firmado, flujo de licencia por API y ciclo offline push/status/pull), marcador `e2e` y **job `e2e`** en CI que genera las claves en el runner (`generate_signing_keys.py`, nunca commiteadas). El E2E detectó un bug real en `SyncService.process_batch`: las fechas con offset del push offline se insertaban en columnas naive (`DataError`) y tumbaban el lote; corregido con `_naive_utc()`. Tests backend 305 → **343** (310 rápidos + 33 E2E).

---

## 1. Resumen del sistema

BALANSOFT-WS es un **sistema de estación de pesaje industrial para camiones**, multi-empresa, con arquitectura **cliente-servidor** y **despliegue en dos roles**:

- **Backend** (`APP_ROLE=local`): API REST **FastAPI** (Python 3.12+, async) que monta `API_ROUTERS`, la API operativa de la **estación** (boletos, catálogos, login-local offline) contra `balansoft-ws-local.sql`.
- **Backend** (`APP_ROLE=server`): la **misma** app monta `SERVER_ROUTERS` (`endpoints/servidor.py`), la API central de **cuenta/licencia/credenciales/sync/panel** contra `balansoft-ws-server.sql` (motor `server_async_engine`).
- **Frontend**: aplicación **Flutter** (Dart) con BLoC, **offline-first** (sqflite + cola de sincronización), instalable en dos modos: **SERVIDOR** (titular, levanta WServer + BD local) o **TRABAJADOR** (cliente delgado).
- **WServer**: backend local de la estación compilado con **PyInstaller one-file** (`backend/wserver.py`), lanzado por la app; en la primera ejecución crea su runtime, genera `.env` (SECRET_KEY aleatoria), crea/migra la BD local y levanta la API en la LAN.
- **Base de datos**: **PostgreSQL 15+**, dos esquemas canónicos (`balansoft-ws-local.sql` de 24 tablas y `balansoft-ws-server.sql` de 10 tablas), con migraciones `001`–`020` idempotentes (sin Alembic).
- **Licencias**: integración con **BALANSOFT-LM (SGLB)** vía HTTP, con verificación de firma **Ed25519** anti-fake-server.
- **Panel del proveedor**: HTML/Bootstrap (`panel/`) contra la API `APP_ROLE=server`.

### Módulos construidos

| Módulo                | Backend | Frontend | Descripción |
|-----------------------|:-------:|:--------:|-------------|
| Auth (JWT)            | ✅ | ✅ | Registro/login local, `login-central`, `login-local` offline, refresh/logout, **forgot/reset** |
| Instalación / onboarding | ✅ | ✅ | `GET /environment`; asistente de primera instalación en 4 pasos y dos modos (`SERVIDOR`/`TRABAJADOR`) |
| Pesaje                | ✅ | ✅ | Boletos: entrada → salida → cierre → modificación → anulación; captura guiada cabina→remolque |
| Flota                 | ✅ | ✅ | Marcas, modelos de camión, camiones, remolques |
| Inventario            | ✅ | ✅ | Categorías, productos (maestra + kardex), almacenes, balanzas, **ajustes de inventario** |
| Directorio            | ✅ | ✅ | Transportes, conductores, terceros (cliente/proveedor/ambos) |
| Kardex                | ✅ | ✅ | Movimientos `10` (ingreso) / `60` (despacho) + saldo a fecha de corte; UI con filtros y export |
| Sincronización        | ✅ | ✅ | Push/pull de pesajes offline + usuarios; `sync_queue`/`sync_cola`; timer automático |
| Reportes              | ✅ | ✅ | Diario, mensual, por vehículo, kardex (saldo/detalle), **avanzados** (transportista, tercero, rango de peso, comparativo mensual) |
| Exportación           | ✅ | ✅ | Excel y **PDF** de pesajes y kardex, con encabezado institucional y formato por empresa |
| Tickets PDF/TXT       | ✅ | ✅ | PDF (ReportLab) y **TXT** (impresora térmica/hoja), con presets de impresora y tipo simple/avanzado |
| Auditoría             | ✅ | ✅ | `AuditMiddleware` + `auditoria`; pantalla con pestañas **Transaccional** (estado de pesajes) y **Registro** (`GET /api/v1/auditoria`) |
| Seguridad / accesos   | ✅ | ✅ | Matriz rol × módulo (`seguridad_matrix.py` + `permisos_acceso`), pantalla "Seguridad y Accesos" |
| Licencias LM          | ✅ | ✅ | Validación online Ed25519, caché offline, snapshot `GET /auth/license`, pantalla ADMIN de renovación |
| Identidad local       | ✅ | ✅ | `GET/PUT /identity` singleton `identidad_local` + tile en Ajustes |
| Series de numeración  | ✅ | ✅ | `series_numeracion` (1..N por empresa), contador transaccional, CRUD + selector en pesaje |
| Usuarios              | ✅ | ✅ | CRUD usuarios locales con roles ADMIN/OPERADOR/AUDITOR/TRABAJADOR + cola de sync de credenciales |
| Fotos                 | ✅ | ✅ | Boleto (multipart) y catálogo (`files/upload`), miniaturas y galería |
| Peso en vivo / HAL    | ✅ | ✅ | HAL serial/TCP (`scale_hal.py`, `scale_session.py`) + `ScaleApiClient` (API-first + fallback TCP) |
| Dispositivos          | ✅ | ✅ | Configuración TCP/serial, descubrimiento de básculas, prueba de conexión y monitoreo en vivo |
| Central / cuenta      | ✅ | — | Rol `server`: cuentas, licencias, credenciales globales, dispositivos, sesiones, recepción de sync |
| Panel proveedor       | ✅ | ✅ (HTML) | `panel/` (Bootstrap): login, cuentas, designar titular, verificar licencia, registrar cuenta |
| Simulador WS          | — | ✅ | Módulo "WS" del simulador BSDD: báscula entrada `:5555`, salida `:5556` |
| i18n                  | ✅ | ✅ | es/en/pt (backend `i18n.py`; frontend `translations.dart`, 621 claves por idioma) |
| WServer (PyInstaller) | ✅ | — | `wserver.py` + `WServer.spec` + `scripts/build_wserver.sh` |
| Modo kiosk / ventana  | — | ✅ | Arranque maximizado, kiosk fullscreen en producción, `onWindowClose` con guard |
| Tema claro/oscuro     | — | ✅ | `ThemeController` persistido en SharedPreferences |

---

## 2. Stack tecnológico

| Capa          | Tecnología | Estado |
|---------------|-----------|:------:|
| Backend       | Python ≥3.12, FastAPI ≥0.112 (async), Pydantic ≥2.7, SQLAlchemy ≥2.0 async (asyncpg), psycopg2 (sync) | ✅ |
| Base datos    | PostgreSQL 15+; local `balansoft_ws_local` (24 tablas), server `balansoft_ws_server` (10 tablas), tests `balansoft_ws_test`/`balansoft_ws_server_test` | ✅ |
| Esquema       | `balansoft-ws-local.sql` y `balansoft-ws-server.sql` (canónicos) + `migrations/001..020` idempotentes (sin Alembic) | ✅ |
| Auth          | JWT access+refresh (python-jose HS256) + BCrypt (passlib) | ✅ |
| Licencias     | Cliente HTTP contra BALANSOFT-LM (SGLB), firma Ed25519, anti-replay, tiers DEMO/MONOPUESTA/CENTRAL | ✅ |
| PDF / Excel   | ReportLab (tickets/reportes PDF) / openpyxl (Excel) | ✅ |
| Frontend      | Flutter/Dart, BLoC (`flutter_bloc`), dio, get_it, connectivity_plus, sqflite, `flutter_secure_storage`, window_manager | ✅ |
| Sync offline  | BD local `balansoft_ws.db` (v5) con `weighing_local` + `catalog_local`; cola `pendiente/sincronizado/intentos_sync/fallido` | ✅ |
| Observabilidad | Rate limiting propio (IP+email, sliding window), Prometheus (`GET /metrics`), auditoría, CORS endurecido | ✅ |
| Hardware      | HAL de balanza (`scale_hal.py`, `scale_session.py`), `GET /weighing/scale/{id}/live`, `POST /balanzas/{id}/probar`, descubrimiento | ✅ |
| Empaquetado   | WServer one-file (PyInstaller) + bundle Flutter Linux; panel HTML estático | ✅ |
| Deploy        | systemd (`deploy/balansoft-ws.service*`), nginx, `scripts/{setup_db,reset_db,backup,verify,install_cliente}.sh` | ✅ |

---

## 3. Estructura del repositorio

```
BALANSOFT-WS-DART/
├── AGENTS.md                  # Reglas del repo (stack canónico, requisitos trazables)
├── CHANGELOG.md               # Historial funcional (v1.x)
├── docs/                      # Documentación vigente + legacy
│   ├── MANEJO_DB.md           # Arquitectura de dos BD, setup, login, cuenta/dispositivos
│   ├── NAV.md, INPUTS_MAP.md  # Navegación/sidebar y atajos de teclado
│   ├── MODELO_ESTANDAR.md, USO-API.md, SESIONES.md, PLANES-PAGOS.md, I18N_Y_ONBOARDING.md
│   └── DOCUMENTACION VIEJA/   # Legacy NO autoritativo (este IMPLEMENTADO.md, PRD/ARCH/MODEL/UI-UX)
├── backend/
│   ├── app/
│   │   ├── main.py            # Selector de rol + middleware (CORS, Audit, RateLimit, Metrics) + /health + /metrics
│   │   ├── core/              # config, database, security, license_client, audit, scale_hal, scale_session,
│   │   │                      #   rate_limit, monitoring, seguridad_matrix, i18n, formato, hardware
│   │   ├── api/dependencies.py# get_current_user/empresa, require_admin, require_catalog_manager, idioma_peticion
│   │   ├── api/v1/endpoints/  # 18 módulos (ver §6) + agregador API_ROUTERS / SERVER_ROUTERS
│   │   ├── models/__init__.py # 19 ORM locales (BD local: 24 tablas)
│   │   ├── models_server.py   # 10 ORM del servidor (ServerBase)
│   │   ├── schemas/__init__.py, schemas_server.py
│   │   └── services/          # weighing, catalog, sync, report, ticket, license, audit, password_reset
│   ├── balansoft-ws-local.sql # Esquema canónico local (24 tablas)
│   ├── balansoft-ws-server.sql# Esquema canónico server (10 tablas)
│   ├── migrations/            # 001..020 (idempotentes, forward-only)
│   ├── wserver.py, WServer.spec
│   ├── scripts/               # build_wserver, setup_db, reset_db, backup, verify, install_cliente, seeds
│   ├── deploy/                # balansoft-ws.service(.prod), nginx, security-setup.sh
│   └── tests/                 # 305 tests (pytest) sobre PostgreSQL real
├── frontend/
│   ├── lib/
│   │   ├── main.dart          # Rutas, DI, arranque maximizado, guard de cierre, kiosk
│   │   ├── core/              # config, constants, theme, i18n, utils (medida_conversion, unsaved_work_guard), services
│   │   ├── data/              # models, mappers, repositories, datasources (API + sqflite)
│   │   ├── domain/            # entities, repository interfaces, usecases
│   │   ├── presentation/      # screens (setup, weighing, catalog, kardex, seguridad, auditoría, ...) + BLoCs
│   │   ├── injection.dart     # get_it DI
│   │   └── integration_test/  # E2E (requiere backend sembrado)
│   └── test/                  # 158 tests (unit/widget/integration)
├── panel/                     # Panel administrativo del proveedor (HTML/Bootstrap) contra APP_ROLE=server
└── scripts/reset_total.sh     # Reset total (respalda BD con pg_dump -Fc antes de borrar)
```

---

## 4. Bases de datos

### 4.1 BD local (`backend/balansoft-ws-local.sql`) — 24 tablas

BD de negocio de la estación, multi-empresa (`id_empresa` UUID). **Una máquina local = una empresa = una cuenta.**

| Grupo | Tablas | Notas |
|-------|--------|-------|
| Cuenta/identidad | `identidad_local` (singleton), `empresas`, `usuarios` | `usuarios.id_credencial` enlaza con la credencial global; `empresas` guarda RIF, `formato_ticket`, `formato_reporte`, `idioma`, `ruta_exportacion_reportes`, logo y snapshot de licencia |
| Directorio | `transportes`, `conductores`, `terceros` | PK cédula en conductores; tipo CLIENTE/PROVEEDOR/AMBOS |
| Flota | `marcas`, `modelos_camion`, `camiones`, `remolques` | placa única por empresa; tara habitual; fotos |
| Inventario | `categorias`, `productos`, `almacenes`, `balanzas` | producto con `es_kardex`, `tolerancia`, `peso_unidad`, densidad, `unidad_medida`, FK a categoría; balanzas con hardware y `is_simulada` |
| Transaccional | `boletos_pesaje`, `imagenes_pesaje`, `kardex` | boleto con 4 estados, pesos/cálculos firmados, `es_peso_manual`, `guia_sunagro`, `medida`, `id_serie`; kardex 10/60 |
| Sync | `sync_queue`, `sync_logs` | cola entidad/operación/payload JSONB |
| Auditoría/config | `auditoria`, `logs_sistema`, `configuraciones`, `parametros_sistema` | escrituras de negocio y de middleware |
| Seguridad | `permisos_acceso` | matriz rol × módulo por empresa (`ver`/`editar`/`ninguno`) |

### 4.2 BD server (`backend/balansoft-ws-server.sql`) — 10 tablas

BD central del proveedor/cuenta (`APP_ROLE=server`):

| Tabla | Contenido |
|-------|-----------|
| `cuentas` | Cuenta del cliente (RIF único, email admin) |
| `licencias` | Licencia (`licencia_key` única, tier, status, emisión/expira, límites, `hardware_id` titular) |
| `dispositivos` | Equipos vinculados; `rol_dispositivo` = `SERVIDOR_LOCAL`/`LOCAL` |
| `credenciales` | Credenciales globales (email único, `rol_global`, hash) |
| `sesiones` | Sesiones del servidor (token_hash, expira, revocada) |
| `sync_sesiones`, `sync_cola` | Recepción/encolado de lotes desde estaciones |
| `auditoria_servidor` | Auditoría de la cuenta/credencial |
| `password_reset_tokens` | Reset de contraseña de credenciales |
| `proveedores_usuarios` | Usuarios del panel del proveedor (SUPERADMIN/SOPORTE/VENTAS) |

### 4.3 Migraciones aplicadas en orden (`001`–`020`)

`001` remolques/fotos/códigos · `002` arquitectura (marcas/modelos/camiones, rename `pesajes→boletos_pesaje`) · `003` reglas MODEL (estados, número secuencial, cálculos, kardex, maestra productos) · `004` password reset · `005` hardware de balanza · `006` `usuarios.id_credencial` + `identidad_local` · `007` `balanzas.is_simulada` · `008` `empresas.logo_url` · `009` `licencias.max_sesiones` (server) · `010` snapshot de licencia en `empresas` · `011` `categorias` · `012` `permisos_acceso` · `013` `productos.id_categoria` (obligatoria) · `014` `empresas.formato_ticket` · `015` `series_numeracion` + `boletos_pesaje.id_serie` · `016` `empresas.ruta_exportacion_reportes` · `017` `empresas.idioma` + `formato_reporte` · `018` índice único parcial `(id_empresa, codigo)` · `019` `guia_sunagro` + `medida` · `020` `es_peso_manual`.

WServer registra las migraciones aplicadas en una tabla `schema_migrations` y las aplica forward-only.

---

## 5. Núcleo de pesaje (`app/services/weighing_service.py`)

### Estados del boleto (4)

`PENDIENTE → CERRADO / MODIFICADO → ANULADO`, más alias legacy normalizados por `WeighingService.normalizar_estado`:

| Legacy | Normaliza a |
|--------|-------------|
| ABIERTO / AUTOMÁTICO | PENDIENTE |
| COMPLETADO / CERRADO | CERRADO |
| ANULADO | ANULADO |

### Número de boleto y series

Secuencial `TA-00000001` (prefijo/dígitos configurables y por **serie** de la empresa), **único y nunca reutilizable**; el contador se reserva de forma transaccional (`FOR UPDATE`, migración `015`). Si el cliente offline no trae número, `SyncService._asignar_numero_boleto` lo genera al hacer push. `DELETE` de una serie usada por boletos responde **409**.

### Cálculos firmados

`WeighingService._calcular` implementa:

- **PTE** = PEC + PER (peso total entrada; cabina + remolque)
- **PTS** = PSC + PSR (peso total salida)
- **PNT** = PTE − PTS
- **PND** = peso neto declarado (guía)
- **PDF** = PNT − PND
- **PDV** = PDF / PND
- **Litros** = PNT / densidad (`_apply_litros`); conversión a litros/galones/toneladas/unidades se resuelve en el frontend (`medida_conversion.dart`).
- **Tolerancia** (`_aplicar_tolerancia`): compara la desviación contra `productos.tolerancia` y marca el boleto.
- Campos legacy `peso_bruto`/`peso_tara`/`diferencia_peso` mantenidos por compatibilidad.

### Reglas de negocio operativas

1. Un camión **no puede tener dos boletos PENDIENTE** a la vez (400 con número del pendiente).
2. **Peso manual** (tecleado) solo ADMIN/SUPERVISOR; se marca `es_peso_manual` y el ticket lo refleja.
3. **Anulación** solo ADMIN/SUPERVISOR, con **motivo obligatorio**; si estaba PENDIENTE libera el vehículo; el número no se reutiliza.
4. **Modificación** de un CERRADO lo pasa a MODIFICADO; un ANULADO no se modifica.
5. **Creación inline (get-or-create)**: vehículo por placa; transporte, conductor, producto, almacén, balanza, remolque, categoría y tercero por nombre — el operador no necesita pre-cargar catálogos.
6. **El peso capturado por la báscula nunca se edita.**

### Kardex

- Al **cerrar**: `PNT ≥ 0` → **INGRESO POR BASCULA (ID 10)**; `PNT < 0` → **DESPACHO POR BASCULA (ID 60)**. Solo productos con `es_kardex=true`.
- Al **anular** un cerrado se registra el movimiento **inverso** (10↔60) sin borrar asientos.
- **Ajustes de inventario** (`POST /inventario/ajustes`) generan movimientos de kardex con justificación obligatoria (ADMIN).
- **Saldo a fecha de corte** = Σ positivos (01-49) − Σ negativos (50-99). Los ANULADOS no cuentan en reportes ni kardex.

---

## 6. API REST (`/api/v1/*`)

Prefijo general, JWT Bearer obligatorio salvo `auth/register`, `auth/login`, `auth/login-central`, `auth/login-local`, `auth/refresh-token`, `auth/forgot-password`, `auth/reset-password`, `environment` y `health`. Swagger en `/docs` si `API_DOCS_ENABLED`. **124 rutas** en 18 módulos.

### Autenticación — `auth.py`

| Método | Ruta | Funcionalidad |
|--------|------|---------------|
| POST | `/auth/register` | Alta empresa + primer admin; valida licencia contra el LM |
| POST | `/auth/login` | Login local + datos de hardware; valida licencia (online) |
| POST | `/auth/login-central` | Login contra el central (espeja empresa+admin+`identidad_local` y emite tokens locales); 502 si el central no responde |
| POST | `/auth/login-local` | Login offline (sin llamar al LM); token con `offline: true` |
| POST | `/auth/validate-license` | Validación en tiempo real de la licencia |
| GET | `/auth/license` | Snapshot para UI (tier, status, expiración, límites, uso DEMO) |
| POST | `/auth/refresh-token` | Nuevo par access+refresh |
| POST | `/auth/forgot-password` | Solicita reset (siempre 200); enlace por SMTP o en el log |
| POST | `/auth/reset-password` | Cambia contraseña con token de un solo uso |
| POST | `/auth/logout` | Logout stateless (auditoría) |

### Pesaje — `pesajes.py`

| Método | Ruta | Funcionalidad |
|--------|------|---------------|
| POST | `/weighing/create` | Alta de boleto (PENDIENTE); valida licencia; limita DEMO; verifica peso manual y doble pendiente |
| POST | `/weighing/close/{boleto}` | Cierre: recalcula PTE/PTS/PNT/PDF/PDV, aplica litros y tolerancia, genera kardex → CERRADO |
| PUT | `/weighing/{boleto}/anular` | Anula con motivo; kardex inverso; libera vehículo → ANULADO |
| PUT | `/weighing/{boleto}` | Modifica campos editables; CERRADO → MODIFICADO |
| GET | `/weighing/pendientes`, `/weighing/list`, `/weighing/boleto/{boleto}` | Pendientes, historial filtrable y detalle |
| GET | `/weighing/{boleto}/pdf` · `/txt` · `/export` | Ticket PDF (paper/tipo/idioma), ticket TXT y export en el formato configurado de la empresa |
| GET/POST/DELETE | `/weighing/{boleto}/imagenes[...]` | Listar/adjuntar/subir/eliminar fotos (`tipo`: placa/vehiculo/documento/entrada/salida/otros) |
| GET | `/weighing/scale/{balanza_id}/live` | Peso en vivo por HAL (sesión persistente) |
| POST | `/files/upload` | Sube foto genérica de catálogo; `media/` servido estático en `/media` |

### Catálogos y empresa

| Módulo | Rutas | Funcionalidad |
|--------|-------|---------------|
| Catálogo | `GET /catalogo/sync` | Snapshot combinado de todos los catálogos para operación offline |
| Flota | CRUD `/marcas`, `/modelos-camion`, `/camiones` (+`/buscar`), `/remolques` | ADMIN/SUPERVISOR edita |
| Inventario | CRUD `/productos`, `/categorias`, `/almacenes`; `/balanzas` (solo ADMIN) + `/balanzas/descubrir` + `/balanzas/{id}/probar`; `POST /inventario/ajustes` | Balanzas incluyen hardware; descubrimiento prueba simulador/IP/puertos seriales |
| Directorio | CRUD `/transportes`, `/conductores`, `/terceros` | ADMIN/SUPERVISOR edita |
| Config | `GET /config/account` | Info unificada de la estación (identidad + empresa + licencia + uso DEMO + `server_api_url`) |
| Empresa | `GET/PUT /empresa` | Perfil fiscal/comercial, logo, formatos e idioma (ADMIN edita) |
| Identidad | `GET/PUT /identity` | Singleton `identidad_local` (vínculo con la cuenta central) |
| Series | `GET/POST /empresa/series`, `PUT .../{id}`, `PUT .../{id}/activa`, `DELETE .../{id}` | Numeración; ADMIN escribe; 409 si tiene boletos |
| Usuarios | `GET/POST/PUT/DELETE /usuarios` | Roles locales; cada cambio encola credencial para sync |
| Seguridad | `GET/PUT /seguridad/matriz` | Matriz efectiva rol × módulo; ADMIN no degradable |
| Entorno | `GET /environment` (sin auth) | Estado de instalación (plataforma, Python, BD, esquema, HAL) |

### Reportes y exportación — `reports.py` + `exports.py`

`GET /reports/{daily,monthly,vehicle/{id},kardex/saldo,kardex/detalle,transportista,tercero,peso-rango,comparativo-mensual}` (JSON) y `GET /reports/export/{excel,pdf}` + `/reports/export/kardex/{excel,pdf}` con encabezado institucional, formato numérico por idioma y logo de empresa.

### Sincronización — `sync.py`

`POST /sync/push`, `GET /sync/status`, `GET /sync/pull`, `GET /sync/usuarios/pendientes`, `POST /sync/usuarios/entregados` (el frontend orquesta el envío de usuarios).

### Rol servidor — `servidor.py` (solo `APP_ROLE=server`)

`POST /auth/register`, `/auth/login`, `/auth/refresh-token`; `GET/POST /licencias`; `POST /panel/login`, `GET /panel/cuentas[/{id}]`, `POST /panel/cuentas/{id}/titular`, `PUT /panel/cuentas/{id}`, `POST /panel/verificar-licencia`; `POST /sync/server`, `POST /sync/users`.

### Health y métricas

`GET /api/v1/health` → `{status, version, timestamp}`; `GET /metrics` (Prometheus, fuera del esquema OpenAPI).

### Auditoría — `auditoria.py`

`GET /api/v1/auditoria` devuelve la tabla `auditoria` completa (acción, entidad, `entidad_id`, detalle en JSON, email del usuario vía join, IP y `created_at` en UTC) con filtros `entidad`, `accion`, `fecha_desde`, `fecha_hasta`, `skip` y `limit` (1-500, por defecto 100). Solo ADMIN y AUDITOR (`403` en otro caso); siempre acotada a la empresa del usuario. La UI (`auditoria_screen.dart`) lo consume en la pestaña "Registro".

### Paginación de catálogos

`GET /api/v1/catalogo/sync` acepta `catalogo` (repetible: solo los catálogos indicados), `limit` (1-5000) y `skip`; la respuesta añade `totales` (filas reales por catálogo) y `truncado` (`true` si hay página siguiente). Sin `limit` el comportamiento es el histórico (catálogo completo).

---

## 7. Seguridad

- **Tokens**: BCrypt (passlib) para contraseñas; **JWT HS256** (access 30 min, refresh 7 días); `verify_token` descarta tokens inválidos.
- **Autorización**: `get_current_user`, `get_current_empresa` (tenancy por `id_empresa`), `require_catalog_manager` (ADMIN/SUPERVISOR), `require_admin` (ADMIN) y chequeos por rol específicos en pesajes/usuarios.
- **Seguridad por categorías** (`app/core/seguridad_matrix.py` + endpoint `seguridad.py`, migración `012`): 18 módulos × 4 roles (ADMIN/OPERADOR/AUDITOR/TRABAJADOR) con acceso `ver`/`editar`/`ninguno`; si no hay override en `permisos_acceso` aplica `MATRIZ_DEFECTO`; **ADMIN se fuerza a `editar` en todos los módulos**. El frontend espeja la matriz (`accesos_default.dart` + `AccesosRepository`) y poda el menú.
- **Auditoría**: `AuditMiddleware` registra cada escritura (POST/PUT/PATCH/DELETE) en `logs_sistema`; `audit_service.py` escribe además en `auditoria` (pesaje y catálogos). No bloquea la petición si falla. La consulta de esa tabla es `GET /api/v1/auditoria` (solo ADMIN/AUDITOR).
- **Configuración fail-fast** (`config.py`): si `APP_ENV=production` con `DEBUG_MODE=true` o con la `SECRET_KEY` de ejemplo, la aplicación **no arranca** (evita filtrar tokens de reset en producción); con CORS `*` en no-desarrollo solo avisa.
- **Logging** (`app/core/logging_config.py`): consola + archivo rotado por tamaño (`RotatingFileHandler`), formato `text` o `json` (una línea por evento con `ts`/`level`/`logger`/`msg`/`exc`) según `LOG_FORMAT`; `LOG_DIR`, `LOG_MAX_BYTES`, `LOG_BACKUP_COUNT`. Rotación de sistema en `backend/deploy/balansoft-ws.logrotate`.
- **Compresión de imágenes** (`app/core/image_compress.py`, Pillow): antes de escribir la foto se respeta la orientación EXIF, se limita el lado mayor a 1600 px y se re-codifica a JPEG q80 (los PNG con alfa se conservan como PNG); si no ahorra peso se guarda el original. `POST /api/v1/files/upload` devuelve además `tamano_kb` y `comprimido`.
- **Rate limiting** (`rate_limit.py`): sliding window propio (cachetools) por IP (+ email en auth); `429` JSON con `Retry-After`; `/health` y `/metrics` exentos. No distribuido entre workers (Redis sugerido a futuro).
- **Monitoreo** (`monitoring.py`): `MetricsMiddleware` + contadores `balansoft_http_requests_total`, `balansoft_api_latency_seconds`, contadores de negocio `pesajes_total`, `license_errors_total`, `active_users`.
- **CORS**: warning si `*` en entorno no-dev; `allow_credentials` solo con orígenes concretos.

---

## 8. Integración con licencias (BALANSOFT-LM / SGLB)

`app/core/license_client.py` implementa el flujo **anti-fake-server**:

1. `POST {LM}/token` con `license_key` → Bearer.
2. `POST {LM}/validate` con hardware + `product_code` + Bearer.
3. Verifica **firma Ed25519** de los campos firmados contra `LICENSE_PUBLIC_KEY`/`LICENSE_PUBLIC_KEY_PATH`; firma inválida → `LicenseSignatureError`.
4. **Anti-replay**: `server_time` fuera de la ventana permitida o `nonce` repetido se rechaza.
5. Caché de validación (`LICENSE_CACHE_TTL_SECONDS`, por defecto 300 s) y degradación offline si el LM no responde.

Tiers: **DEMO** (`DEMO_MAX_RECORDS=10`), **MONOPUESTA** (1 usuario), **CENTRAL** (10). `LICENSE_PRODUCT_CODE=WS` (la clave de licencia usa prefijo `BWS-`). Orquestación en `app/services/license_service.py` (espeja el resultado en `identidad_local` y `empresas`).

### 8.1 Stub del LM para E2E (H2)

`backend/scripts/lm_stub.py` es un LM mínimo **FastAPI que firma de verdad** con Ed25519, para probar el contrato sin el LM real ni en claro en CI:

- Rutas: `GET /health`, `POST /token`, `POST /validate`, `POST /activate`, `GET /{license_key}/check` y `POST /__mode/{modo}` (solo pruebas).
- Modos: `valid` (por defecto), `invalid` (SUSPENDIDA), `expired` (EXPIRED), `tamper` (altera un campo firmado **después** de firmar) y `unreachable` (503).
- Claves: `LM_STUB_PRIVATE_KEY_PATH` (o `LICENSE_PRIVATE_KEY_PATH`) y `LM_STUB_PORT` (por defecto 9100). Si no hay clave configurada genera un par efímero en memoria (solo dev/CI).
- Firma sobre el JSON canónico de los 9 `SIGNED_FIELDS` de `app/core/license_client.py`, en base64.
- Uso manual: `python -m scripts.lm_stub` y `LICENSE_API_URL=http://127.0.0.1:9100` en la estación.

Las 33 pruebas de `backend/tests/e2e/` levantan el stub en un hilo de uvicorn con claves efímeras e inyectan la **clave pública** en el `LicenseClient` (verificación real, sin bypass): cubren el contrato firmado (firma válida, `tamper` rechazado, anti-replay de `nonce`, ventana de `server_time`, metadata `ed25519`/v1), el flujo por API (login, `validate-license`, `GET /auth/license` con y sin LM, creación/cierre de boletos) y el ciclo offline (`POST /sync/push` idempotente, `GET /sync/status`, `GET /sync/pull`, rastro en `sync_logs`).

**Bug real detectado por el E2E**: `SyncService.process_batch` pasaba las fechas recibidas con offset tal cual a columnas `TIMESTAMP WITHOUT TIME ZONE`; asyncpg respondía `DataError` y el lote offline completo se caía. Ahora `_naive_utc()` normaliza a UTC naive (`app/services/sync_service.py`), con regresión en `tests/test_sync_service.py`.

**Modelo de cuenta y dispositivos** (`docs/MANEJO_DB.md` §13): la primera máquina que activa la cuenta queda `SERVIDOR_LOCAL` en `servidor.dispositivos.rol`; las demás solo `LOCAL`. El padrón central vive en la BD server; la estación guarda su vínculo en `identidad_local`.

---

## 9. Frontend Flutter (`frontend/`)

### 9.1 Configuración e instalación

- App `balansoft_ws` (pubspec `1.0.0+1`; `AppConfig.appVersion = '1.0.0'`), SDK Dart ≥3.2, Material 3, target Linux/Android/web.
- **DI** con `get_it`, **estado** con BLoC/Cubit.
- **Rutas nombradas** (`main.dart`): `/setup_preferences`, `/mode_selection`, `/setup`, `/db_config`, `/activation`, `/company_setup`, `/worker_connection`, `/connections`, `/login`, `/register`, `/forgot-password`, `/reset-password`, `/dashboard`, `/weighing/detail`, `/settings`. El resto es navegación imperativa o index-based en `HomeShell`.
- **Seguridad de tokens**: `access_token`/`refresh_token`/licencia/matriz de accesos en `flutter_secure_storage`; SharedPreferences solo guarda tema, último email, hardware_id, host/puerto de báscula y `printer_preset`.
- **Ventana**: arranca **maximizada** (`minimumSize: 1280×800`); modo **kiosk** fullscreen sin bordes en producción (`EnvConfig.isKiosk`); `onWindowClose` intercepta la X y pide confirmación si hay datos sin guardar, luego detiene WServer si corresponde.
- **Dos modos de instalación** (`AppConfig.modoEstacion`):
  - **SERVIDOR** (titular, levanta WServer + BD local): preferencias → modo → entorno (WServer/PostgreSQL/`/environment`) → BD → `/activation` (correo+contraseña contra el central; 403 si no es titular) → `/company_setup` precargado → dashboard.
  - **TRABAJADOR** (cliente delgado, sin BD ni WServer): preferencias → modo → `/worker_connection` (IP/puerto + `/health`) → login contra la API del servidor titular.
- **WServer** (`lib/core/services/wserver_manager.dart`): localiza el binario, `ensureRunning(...)` con polling a `/health`, `detener()`, y autostart (`.desktop`/registro Windows).
- **i18n**: `translations.dart` con **621 claves en es/en/pt** (paridad verificada por test); `locale_controller.dart` (system/es/en/pt, persistido); el backend recibe el idioma vía `?idioma=`/`Accept-Language`.

### 9.2 Pantallas y áreas

| Área | Pantallas principales | Descripción |
|------|-----------------------|-------------|
| Instalación | preferences, mode_selection, environment_check, database_config, activation, company_setup, worker_connection, setup_layout_wrapper | Asistente de primera instalación (dos modos) |
| Auth | login, register, forgot_password, reset_password | Sesión y recuperación de contraseña |
| Inicio | home_shell, dashboard | KPIs, vehículos en planta, pesajes fallidos, badge de salud, FAB nuevo pesaje |
| Pesaje | weighing_list, weighing_form, weighing_detail | Lista, formulario (captura guiada, tolerancia, búsqueda/copia), detalle con fotos |
| Catálogos | catalog_section, catalog_crud, catalog_edit | CRUD genérico declarativo (`catalog_resources.dart`) |
| Kardex | kardex | Filtros, saldo acumulado, export |
| Reportes | reports | Diario/mensual + avanzados + export |
| Auditoría | auditoria | Pestañas Transaccional / Registro; el volcado completo de la tabla llega vía `GET /api/v1/auditoria` |
| Ajustes inventario | ajustes_inventario | Stock y movimientos de ajuste |
| Seguridad | seguridad | Editor de la matriz rol × módulo |
| Dispositivos | dispositivos | Configuración/prueba de básculas y monitoreo en vivo |
| Empresa | documentos_empresa | Perfil de empresa + series de numeración |
| Configuración | settings, connections, initial_setup, license_admin, system_diagnostics, ticket_design, usuarios | Hub de Ajustes (cuenta, licencia, básculas, conexiones, WServer, apariencia/idioma, archivos, diagnóstico) |
| Ayuda | ayuda | Soporte y datos del sistema |

### 9.3 Navegación y atajos

- Sidebar (`app_sidebar.dart`) con 4 secciones (INFORMACIÓN, REPORTES, MANTENIMIENTO, AYUDA Y SOPORTE), podado por la matriz de accesos; en móvil, bottom bar con 4 destinos + "Más".
- `HomeShell` centraliza acciones (`go:...`), paleta de comandos (`Ctrl+K`) y atajos; F1/F2 nuevo pesaje, F5 refrescar, F6 buscar, F7 vehículo, F8 conductor, F9 maximizar, F10 sidebar, F11 fullscreen, F12 cancelar; F3/F4 los atiende el formulario. Detalle en `docs/INPUTS_MAP.md`.

### 9.4 Formulario de pesaje (características v2.0)

- **Atajos**: `F2` entrada, `F3` capturar peso, `F4` guardar, `F5` imprimir, `F6` salida, `Esc` salir con confirmación, `Enter` guardar fuera de inputs.
- **Captura guiada cabina→remolque** (máquina de estados `cabina → remolque → fijado`): `F3` congela la cabina; con remolque, alerta **«Mueva el camión»** y al continuar la báscula/indicador pasan al remolque; segundo `F3` fija ambos; tras guardar, **«¿Desea imprimir?»**.
- **Conversión de unidades** (`medida_conversion.dart`): kg/litros/galones/toneladas/unidades; Litros = PNT/densidad, Galones = Litros/3.78541, Toneladas = PNT/1000, Unidades = PNT/peso_unidad.
- **Tabla de pesos y tolerancia** bajo la lectura: PTE/PTS/PNT/PND/PDF/PDV + tolerancia del producto + Estado (DENTRO/SOBRE/BAJO); `-` cuando falta PND o tolerancia.
- **Búsqueda rápida con copia**: panel con filtros Todos/Pendientes/Cerrados; "Traer al formulario" carga una **copia editable** (nuevo pesaje con fecha actual, sin arrastrar número de boleto; el original no se modifica).
- **Protección de datos sin guardar**: el formulario marca `tieneDatosSinGuardar` (`unsaved_work_guard.dart`) y confirma al salir/cerrar la ventana.

### 9.5 Offline-first

- BD local `balansoft_ws.db` (**v5**) con `weighing_local` (flags `pendiente/sincronizado/intentos_sync/fallido`, ~45 columnas) y `catalog_local` (`extra_json`).
- `WeighingRepository`: intenta API primero y, si falla, guarda local con `pendiente=1`; fusiona pendientes/fallidos locales con los remotos. Reintentos hasta `maxSyncRetries=3`, luego `fallido=1`.
- `CatalogRepository.syncCatalogs()` baja `/catalogo/sync` y reemplaza `catalog_local`; fallback a caché.
- `SyncBloc`: timer de sincronización cada 2 min y health cada 10 s; batch 50.

---

## 10. Tickets (PDF / TXT)

`app/services/ticket_service.py` genera el boleto con **ReportLab** (PDF) y **texto plano** (TXT):

- Encabezado institucional con logo de empresa, número, fecha/hora, camión y remolque.
- Tabla con PTE, PTS, PNT, PND, PDF, PDV, densidad, unidad/medida, litros y estado; el **tipo avanzado** muestra todos los campos y el **básico** marca el peso manual (`es_peso_manual`).
- Variantes **hoja** (Carta/A4) y **térmica** (80/58 mm); `boletos_por_hoja` 1–4, orientación y encabezado/detalles configurables.
- Si el boleto está **ANULADO**: marca de agua "ANULADO" + motivo en rojo.
- Fuente DejaVu para tildes/ñ. El frontend previsualiza con `ticket_preview_dialog.dart` y guarda con presets (`printer_preset.dart`: POS_80/POS_58/SISTEMA_PDF/MATRIZ_PUNTO) en `SaveFileUtils` (subcarpeta `tickets/`).

---

## 11. Configuración (`.env`)

Referencias: `backend/.env.example` (producción), `backend/.env.plantilla` (plantilla embebida del WServer), `docs/MANEJO_DB.md` §11.

Claves principales: `APP_ENV`, `DEBUG_MODE`, `API_DOCS_ENABLED`, `LOG_LEVEL`, `LOG_FILE`, `LOG_FORMAT`/`LOG_DIR`/`LOG_MAX_BYTES`/`LOG_BACKUP_COUNT`, `DATABASE_URL`/`DATABASE_URL_SYNC`, `APP_ROLE`, `SERVER_API_URL` + `SERVER_DATABASE_URL` (rol local), `LICENSE_API_URL`, `LICENSE_ADMIN_URL`, `LICENSE_PUBLIC_KEY`/`LICENSE_PUBLIC_KEY_PATH`, `LICENSE_PRODUCT_CODE`, `LICENSE_CACHE_TTL_SECONDS`, `API_HOST`/`API_PORT`, `API_RELOAD`, `API_WORKERS`, `SECRET_KEY`, `ALGORITHM`, `ACCESS_TOKEN_EXPIRE_MINUTES`, `REFRESH_TOKEN_EXPIRE_DAYS`, `CORS_ORIGINS`, `SYNC_INTERVAL_MINUTES`, `MAX_OFFLINE_DAYS`, `MAX_SYNC_RETRIES`, `DEMO_MAX_RECORDS`/`MONOPUESTA_MAX_USERS`/`CENTRAL_MAX_USERS`, `BOLETO_PREFIX`/`BOLETO_DIGITOS`, `IDIOMA_DEFAULT`, `MEDIA_DIR`, `MAX_IMAGE_BYTES`, `ALLOWED_IMAGE_TYPES`, `PASSWORD_RESET_*`, `SMTP_*`, `RATE_LIMIT_*`, `METRICS_ENABLED`, `BACKUP_DIR`/`BACKUP_RETENTION_DAYS`.

En dev actual: `APP_ROLE=local` contra `balansoft_ws_local`; `balansoft_ws_server` es la réplica local del central (rol server, puerto dev `8002`); la estación dev corre en `:8000` (accesible por LAN en el servidor real).

---

## 12. Scripts, despliegue y empaquetado

| Script / artefacto | Uso |
|--------------------|-----|
| `scripts/build_wserver.sh` | Compila WServer one-file con PyInstaller e integra el binario en los bundles Flutter |
| `scripts/setup_db.sh` | `instalar` (esquema), `aplicar-migraciones`, `seed` (demo) |
| `scripts/reset_db.sh` | Deja ambas BD vacías con el esquema canónico (`RESET_DRY_RUN=1` plan) |
| `scripts/backup.sh` | `pg_dump -Fc` + media con retención (`BACKUP_*`) |
| `scripts/verify.sh` | Verificación de estación (Python/BD/`.env`/SECRET_KEY/API/systemd/LM) |
| `scripts/install_cliente.sh` | Instala backend en cliente (`.env`, BD, systemd, verify) |
| `scripts/seed_data.py` / `seed_simulacion.py` / `seed_reset_demo.sql` | Semillas demo y de operación |
| `scripts/generate_signing_keys.py` | Par Ed25519 (integración LM) |
| `scripts/seed_panel_admin.py` | Crea el usuario del panel del proveedor (`proveedores_usuarios`) |
| `deploy/balansoft-ws.service`, `.service.prod`, `balansoft-ws.nginx`, `security-setup.sh` | systemd (4 workers), nginx y hardening |
| `scripts/reset_total.sh` (raíz) | Reset total de la estación: **respalda las BD con `pg_dump -Fc` antes de borrarlas** y aborta si falla |
| `deploy/balansoft-ws.logrotate` | Rotación de logs del sistema (`/etc/logrotate.d/`); la API además rota por tamaño (`LOG_MAX_BYTES`) |
| `.github/workflows/ci.yml` | CI: job `backend` (PostgreSQL 16 + `uv sync --all-groups` + `ruff` + `mypy` + `pytest`) y job `frontend` (Flutter 3.47.2 + `flutter analyze` + `flutter test`) |
| `panel/` | Panel administrativo del proveedor (HTML/Bootstrap) contra `APP_ROLE=server` |

**WServer** (`wserver.py`, `WServer.spec`): en primera ejecución resuelve el runtime (`WSERVER_HOME` → `~/.balansoft-ws/wserver`), crea `logs/media/keys/backups`, genera `.env` desde `.env.plantilla` (SECRET_KEY aleatoria), migra `API_HOST=127.0.0.1` a `0.0.0.0`, crea/migra la BD local y levanta uvicorn; si el bind es de red, abre el puerto en `ufw` vía `pkexec` (best-effort) y muestra la IP LAN.

**Arranque manual de desarrollo**:

```bash
cd backend
uv sync
uv run uvicorn app.main:app --port 8000     # docs en /docs
```

---

## 13. Tests

**Backend** (pytest, PostgreSQL real `balansoft_ws_test` y `balansoft_ws_server_test`): **343/343 en verde** — **310 rápidos** (`uv run pytest -q -m "not e2e"`, ~90 s) y **33 E2E** (`uv run pytest tests/e2e`, ~15 s) contra el stub firmante del LM. Cada test recibe sesión limpia y al final trunca todas las tablas; las sesiones de balanza se cierran tras cada test.

| Archivo | Cubre |
|---------|-------|
| `test_weighing_service.py` | Creación/cierre/anulación, doble pendiente, número secuencial, kardex e inverso, límite DEMO |
| `test_weighing_calculos.py` | PTE/PTS/PNT/PND/PDF/PDV, litros, normalización de estados |
| `test_endpoints.py` | Endpoints de pesaje/auth, permisos por rol, aislamiento por empresa, dispositivo |
| `test_api_server.py` | Rol `server`: registro, login global con dispositivo, licencias, panel, recepción de sync |
| `test_activacion_instalacion.py` | `login-central` en modo SERVIDOR (403 no titular), espejo de datos y rol de dispositivo |
| `test_identity_usuarios_tolerancia.py` | Identidad local, tolerancia al cerrar, CRUD de usuarios + cola de sync |
| `test_categorias_seguridad.py` | Categorías y matriz de seguridad (ADMIN forzado a `editar`) |
| `test_preferencias_empresa.py` | `PUT /empresa`, idioma de empresa y formato de ticket |
| `test_report_service.py` | Agregaciones de reportes (ANULADOS excluidos) |
| `test_ticket_service.py` | PDF de ticket, contenido extraído, marca de agua ANULADO |
| `test_scale_hal.py` | Factory HAL, lectura TCP y endpoint `.../live` con sockets reales |
| `test_license_client.py` | Verificación de firma Ed25519, ventana `server_time`, anti-replay |
| `test_i18n.py` | Diccionario, precedencia de idioma y formato numérico/fecha |
| `test_rate_limit.py` / `test_monitoring.py` | Rate limiter (hermético) y métricas Prometheus |
| `test_password_reset.py` / `test_audit_service.py` / `test_servidor_unidades.py` | Reset, auditoría y helpers del rol server |
| `test_sync_service.py` | Normalización a UTC naive de las fechas del push offline (bug encontrado por el E2E) |
| `tests/e2e/test_lm_stub.py` | Contrato firmado real contra el stub: firma Ed25519, `tamper`, anti-replay de `nonce`, ventana de `server_time`, metadata, `/token` y 401 |
| `tests/e2e/test_license_flow.py` | Login, `validate-license` (válida/vencida/suspendida), `GET /auth/license` en vivo y degradado, pesajes con licencia activa |
| `tests/e2e/test_offline_sync.py` | `POST /sync/push` (idempotencia, lote inválido), `GET /sync/status`, `GET /sync/pull` y `sync_logs` |

**Frontend** (`flutter test`): **158/158 en verde**. Cubre `medida_conversion`, parsers numéricos, catálogos, `CompanyDraft`, export Excel, health, i18n (paridad es/en/pt), kardex (bloc y repositorio), kiosk, locale, printer preset, `scale_api_client`, secure storage, reintentos de sync y BLoCs de pesaje; widgets de instalación/activación/catálogo/configuración/atajos/monitor de báscula/diagnóstico/ticket/detalle de pesaje. `flutter analyze` limpio.

**Simulador BSDD** (`/home/yohander/Documentos/BSDD`): `flutter analyze` limpio y `flutter test` 27/27 tras añadir el módulo WS.

Comandos canónicos: `uv run pytest -q`, `uv run pytest tests/e2e` (requiere el stub; genera claves efímeras), `uv run ruff check app tests`, `uv run mypy tests/` (backend); `flutter test`, `flutter analyze`, `flutter build linux --release` (frontend).

---

## 14. Estado general y pendientes detectados

**Lo construido y funcional**: API completa en dos roles/BD (estación local + central), pesaje con reglas MODEL (4 estados, cálculos firmados, kardex 10/60, series y número nunca reutilizable), captura guiada cabina→remolque con conversión de unidades y tabla de tolerancia, búsqueda rápida con copia, protección de datos sin guardar; CRUD de flota/inventario/directorio/categorías/usuarios; seguridad por categorías; series de numeración; identidad local; auditoría; ajustes de inventario; olvido/reset de contraseña; sync offline push/pull con reintentos; reportes (básicos + avanzados) con export Excel/PDF; tickets PDF/TXT con presets; fotos de boleto y catálogos; HAL de balanza (serial/TCP) con sesión persistente, descubrimiento y prueba; administración de licencias; i18n es/en/pt en backend y frontend; WServer one-file y asistente de instalación en dos modos; panel administrativo del proveedor; pruebas E2E. Backend **343/343** (310 rápidos + 33 E2E) y frontend **158/158**.

**Calidad continua**: `.github/workflows/ci.yml` ejecuta tres jobs: `backend` (ruff + mypy + `pytest -m "not e2e"` con PostgreSQL 16), `e2e` (genera las claves Ed25519 con `scripts/generate_signing_keys.py` en el runner y corre `pytest tests/e2e`) y `frontend` (`flutter analyze` + `flutter test`). Las claves nunca se commitean.

**Deuda técnica detectada (cerrada el 2026-10-01)**: la tanda `/update-all` resolvió los seis puntos — `dbVersion = 5`, `productCode = 'WS'`, Sincronización de Ajustes cableada al `SyncBloc`, volcado completo de `auditoria` en la UI, limitación de rate limiting documentada (Redis sigue pendiente) y `docs/MANEJO_DB.md` con las **24** tablas reales.

**Pendientes aceptados (requieren entorno/cliente, no código)**:

- Pruebas con balanza física y parsers de fabricantes (Toledo/Rice Lake/Sartorius) en `scale_hal.py`.
- Pruebas de latencia/volumen (semilla de ~50k boletos) y HTTPS/TLS con nginx.
- Manuales de usuario con capturas, proceso de soporte, CI/CD y automatización de backups del LM.
- Regenerar el binario `backend/dist/WServer` y los bundles Flutter/APK con los últimos cambios.

---

## 15. Referencias

- `AGENTS.md` — reglas del repo, stack canónico y requisitos trazables (REQ-FN / REQ-NF / AR / INT / UX).
- `docs/MANEJO_DB.md` — **autoridad** de la arquitectura de dos BD, setup, flujo de login y modelo de cuenta/dispositivos.
- `docs/NAV.md`, `docs/INPUTS_MAP.md` — navegación/sidebar y atajos.
- `docs/MODELO_ESTANDAR.md` — roles y reglas de negocio.
- `docs/I18N_Y_ONBOARDING.md` — i18n y onboarding de primera instalación.
- `docs/USO-API.md`, `docs/SESIONES.md`, `docs/PLANES-PAGOS.md` — licencias, sesiones y planes.
- `backend/balansoft-ws-local.sql`, `backend/balansoft-ws-server.sql`, `backend/migrations/*.sql` — esquemas y migraciones.
- `CHANGELOG.md` — historial funcional de la app (v1.x).
- ⚠️ `docs/DOCUMENTACION VIEJA/legacy/DOCUMENTACION-BALANSOFT-WS.md` — paralelo NO autoritativo (especificaciones históricas .NET/WinForms).
