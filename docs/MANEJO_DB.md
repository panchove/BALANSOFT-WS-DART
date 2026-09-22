# BALANSOFT-WS: Manejo de Base de Datos (Arquitectura Server/Local)

**Versión:** 2.0
**Fecha:** 2026-09-15
**Estado:** Vigente
**Alcance:** Arquitectura de dos bases de datos (server/local), setup de desarrollo, flujo de login, estado actual y roadmap. **Los instaladores de la app (Linux/Windows/Android) quedan fuera de alcance por ahora.**
**Fuente:** `backend/balansoft-ws-server.sql` y `backend/balansoft-ws-local.sql` (schemas canónicos de BD)

---

## 1. Resumen Ejecutivo

BALANSOFT-WS es un sistema de pesaje industrial para camiones con arquitectura **cliente-servidor**. La decisión arquitectónica fundamental es la **separación de la base de datos en dos instancias**:

| Base de Datos | Responsabilidad | Tecnología |
|---------------|-----------------|------------|
| **`balansoft_ws`** (servidor) | Cuenta, licencia, credenciales globales, dispositivos, sesiones, sincronización, panel del proveedor | PostgreSQL 15+ |
| **`balansoft_ws_local`** (máquina del cliente) | Todo lo operativo: usuarios locales, flota, inventario, boletos, kardex, auditoría, configuración | PostgreSQL 15+ |

**Regla fundamental:** Una máquina local = una empresa = una cuenta.

> ⚠️ **Nota de desarrollo:** mientras se hacen las pruebas y el desarrollo, **ambas bases se crean en la máquina local del desarrollador** (la misma instancia de PostgreSQL). En producción, `balansoft_ws` vive en el VPS/nube y `balansoft_ws_local` en el PC del cliente.

---

## 2. Decisión Arquitectónica: Una API con Routers Condicionales

Se adopta **una sola base de código FastAPI** desplegada en dos roles mediante `APP_ROLE=server|local`.

**Justificación:** un solo repo, un solo `main.py`, un solo `pytest`; migrable a paquetes separados cuando crezca.

```python
# (plan) backend/app/main.py
from app.core.config import settings

app = FastAPI()

# Routers comunes (siempre)
app.include_router(auth_router, prefix="/api/v1/auth")
app.include_router(health_router, prefix="/api/v1")

# Routers solo en servidor
if settings.app_role == "server":
    app.include_router(panel_router, prefix="/api/v1/panel")
    app.include_router(licencias_router, prefix="/api/v1/licencias")
    app.include_router(sync_server_router, prefix="/api/v1/sync")

# Routers solo en local
if settings.app_role == "local":
    app.include_router(weighing_router, prefix="/api/v1/weighing")
    app.include_router(catalogo_router, prefix="/api/v1/catalogo")
    app.include_router(flota_router, prefix="/api/v1/flota")
    app.include_router(inventario_router, prefix="/api/v1/inventario")
    app.include_router(directorio_router, prefix="/api/v1/directorio")
    app.include_router(reports_router, prefix="/api/v1/reports")
    app.include_router(kardex_router, prefix="/api/v1/kardex")
    app.include_router(sync_local_router, prefix="/api/v1/sync")
```

> **Estado actual:** ✅ Implementado. `config.py` ya tiene `APP_ROLE=server|local` (+ `SERVER_API_URL`, `SERVER_DATABASE_URL`) y `main.py` monta `SERVER_ROUTERS` o `API_ROUTERS` según el rol. La API y sus endpoints quedan documentados en la sección §9.3.

### 2.1 Responsabilidades por API (objetivo)

| Endpoint | API Server | API Local |
|----------|:----------:|:---------:|
| `POST /auth/register` | ✅ | ❌ |
| `POST /auth/login` (primer login, online) | ✅ | ❌ |
| `POST /auth/login-local` (offline) | ❌ | ✅ |
| `POST /auth/refresh-token` | ✅ | ✅ |
| `POST /licencias/validar` | ✅ | ❌ |
| `GET /licencias/snapshot` | ✅ | ✅ (caché) |
| `POST /sync/push` | ✅ (recibe) | ✅ (envía) |
| `GET /sync/pull` | ✅ (envía) | ✅ (recibe) |
| `POST /weighing/*` | ❌ | ✅ |
| `GET /catalogo/*` | ❌ | ✅ |
| `GET /reports/*` | ❌ | ✅ |
| `POST /panel/*` (proveedor) | ✅ | ❌ |
| `GET /health` | ✅ | ✅ |

---

## 3. Estados de la Transacción (Boleto)

| Estado | Descripción | Reportes |
|--------|-------------|----------|
| **PENDIENTE** | Entrada registrada, esperando salida | Cuenta en "En Tránsito" |
| **CERRADO** | Entrada + salida completas | Cuenta en Ingreso/Despacho |
| **MODIFICADO** | Boleto CERRADO/PENDIENTE editado | Cuenta según su estado base |
| **ANULADO** | Cancelado (requiere auditoría) | **NO** cuenta en reportes, solo en auditoría |

**Regla crítica:** *El peso registrado por la báscula nunca puede ser editado.* Los únicos campos modificables en estado `MODIFICADO` son: `documento`, `flete`, `costo_flete`, `observaciones`, `peso_neto_declarado` (PND).

**Normalización legacy:** `COMPLETADO` → `CERRADO`, `ABIERTO`/`AUTOMATICO` → `PENDIENTE`.

---

## 4. Roles de Usuario

| Rol | Permisos |
|-----|----------|
| **ADMIN** | Todo: catálogos, pesaje, modificar/anular, crear usuarios, configurar balanzas, ver licencia |
| **AUDITOR** | Consultas, reportes, auditoría, modificar/anular. **No** crea usuarios ni configura |
| **OPERADOR** | Pesaje entrada/salida, consulta básica de vehículos |
| **TRABAJADOR** | Pesaje entrada/salida únicamente (rol más restringido) |

**Matriz de permisos por endpoint:**

| Endpoint | ADMIN | AUDITOR | OPERADOR | TRABAJADOR |
|----------|:-----:|:-------:|:--------:|:----------:|
| `POST /weighing/create` | ✅ | ❌ | ✅ | ✅ |
| `POST /weighing/close` | ✅ | ❌ | ✅ | ✅ |
| `PUT /weighing/{boleto}/anular` | ✅ | ✅ | ❌ | ❌ |
| `PUT /weighing/{boleto}` (modificar) | ✅ | ✅ | ❌ | ❌ |
| `GET /catalogo/*` | ✅ | ✅ | ✅ (lectura) | ❌ |
| `POST/PUT/DELETE /catalogo/*` | ✅ | ❌ | ❌ | ❌ |
| `GET /reports/*` | ✅ | ✅ | ❌ | ❌ |
| `POST /panel/*` (proveedor) | ❌ | ❌ | ❌ | ❌ |
| `GET /licencias/snapshot` | ✅ | ✅ | ❌ | ❌ |

---

## 5. Cálculos y Reglas de Negocio

### 5.1 Fórmulas (MODEL.md)

| Sigla | Descripción | Fórmula |
|-------|-------------|---------|
| **PEC** | Peso entrada camión (chuto + trailer) | dato |
| **PER** | Peso entrada remolque (opcional) | dato |
| **PTE** | Peso total entrada | `PEC + PER` |
| **PSC** | Peso salida camión | dato |
| **PSR** | Peso salida remolque | dato |
| **PTS** | Peso total salida | `PSC + PSR` |
| **PNT** | Peso neto total | `PTE − PTS` |
| **PND** | Peso neto declarado (guía) | dato |
| **PDF** | Peso diferencia | `PNT − PND` |
| **PDV** | Porcentaje desviación | `PDF / PND × 100` |

### 5.2 Tolerancia Comercial

Configurada en `productos.tolerancia` (porcentaje). Si `PDV` excede la tolerancia, el sistema **emite una advertencia** (no bloquea el cierre, pero queda registrada en auditoría).

### 5.3 Kardex (MODEL.md)

| ID | Descripción | Signo |
|----|-------------|-------|
| 00 | Saldo Inicial | — |
| 01-09 | Definible por usuario | + |
| **10** | **Ingreso por Báscula** | **+** |
| 11-49 | Definible por usuario | + |
| 50-59 | Definible por usuario | − |
| **60** | **Despacho por Báscula** | **−** |
| 61-99 | Definible por usuario | − |

**Determinación:** `PNT > 0` → Ingreso (ID 10); `PNT < 0` → Despacho (ID 60); `PNT = 0` → sin movimiento.

**Al anular CERRADO:** se registra movimiento **inverso** (10 ↔ 60) conservando historia.

**Saldo:** `SALDO FINAL = SALDO INICIAL + Σ(positivos) − Σ(negativos)` filtrado a fecha de corte.

> El catálogo editable de conceptos (`conceptos_kardex`) está **pendiente de implementar**; hoy los IDs 10/60 son constantes del sistema.

---

## 6. Schema Canónico de Base de Datos

Los archivos **autoridad** del esquema son:

| Archivo | Base | Tablas |
|---------|------|--------|
| `backend/balansoft-ws-server.sql` | `balansoft_ws` (producción) / `balansoft_ws_server` (dev) | 10 |
| `backend/balansoft-ws-local.sql` | `balansoft_ws_local` | 22 |

Ambos son **idempotentes** (`CREATE TABLE IF NOT EXISTS` + `CREATE INDEX IF NOT EXISTS`), en una transacción, y usan `gen_random_uuid()` (pgcrypto). No usan Alembic: los cambios futuros van como migraciones `backend/migrations/*.sql` hacia adelante.

### 6.1 `balansoft_ws` — servidor (cuenta y licencia, NO datos operativos)

| Tabla | Propósito |
|-------|-----------|
| `cuentas` | Empresas registradas por el proveedor (riff_nit único, email_admin único) |
| `licencias` | Licencias por cuenta (tier DEMO/MONOPUESTA/CENTRAL, status, expira, `hardware_id`) |
| `dispositivos` | Equipos autorizados por cuenta (`hardware_id` único) |
| `credenciales` | Credenciales globales de login (email + hash, `rol_global`) |
| `sesiones` | Tokens/sesiones JWT emitidos por el servidor |
| `sync_sesiones` | Sesiones de sincronización orquestadas desde el servidor |
| `sync_cola` | Cola de pendientes recibida de los equipos locales |
| `auditoria_servidor` | Eventos de cuenta/licencia/sync (login, activaciones…) |
| `password_reset_tokens` | Recuperación de contraseña global |
| `proveedores_usuarios` | Usuarios del panel del proveedor (SUPERADMIN/SOPORTE/VENTAS) |

No guarda boletos, kardex ni catálogos: esos viven solo en la máquina local.

### 6.2 `balansoft_ws_local` — máquina del cliente (todo lo operativo)

| Tabla | Propósito |
|-------|-----------|
| `identidad_local` | Vínculo con la cuenta (1 fila): `id_cuenta`, licencia cacheada, `modo_offline` |
| `empresas` | Espejo local de la cuenta (1:1, provee `id_empresa` para FKs) |
| `usuarios` | Usuarios operativos con rol local (ADMIN/OPERADOR/AUDITOR/TRABAJADOR) |
| `transportes` | Empresas de transporte |
| `marcas` / `modelos_camion` / `camiones` / `remolques` | Flota y transporte |
| `conductores` / `terceros` | Directorio (conductores PK = cédula; terceros con `tipo` C/P) |
| `productos` / `almacenes` / `balanzas` | Inventario y dispositivos de pesaje (HAL serial/TCP) |
| `boletos_pesaje` | Transaccional principal (entrada/salida, cálculos MODEL.md, `estado_boleto`) |
| `imagenes_pesaje` | Fotos de entrada/salida |
| `kardex` | Movimientos (10/60), saldo a fecha de corte |
| `sync_queue` / `sync_logs` | Cola local de sincronización hacia el servidor |
| `auditoria` / `logs_sistema` | Auditoría operativa y logs |
| `configuraciones` / `parametros_sistema` | Configuración local |

> **Diferencia con la versión anterior del doc:** se añadieron índices nuevos (`idx_dispositivos_cuenta`, `idx_sesiones_credencial`, `uq_modelos_empresa_nombre`, `idx_camiones_*`, `idx_auditoria_*`, etc.) y se eliminó la tabla `conceptos_kardex` del schema local (queda pendiente como catálogo editable futuro). Síguen los campos legacy de `boletos_pesaje` (`peso_bruto`, `peso_tara`, `litros`, `unidades`, etc.) para compatibilidad.

---

## 7. Setup de Desarrollo (BD del servidor en la máquina local)

Mientras se prueba, la BD del servidor se crea **también en el PostgreSQL local** del desarrollador. Para no interferir con la BD operativa actual (`balansoft_ws`, usada por el backend single-DB en desarrollo), la DB de servidor de pruebas se llama **`balansoft_ws_server`**:

```bash
# 1. Crear las bases (una vez)
PGPASSWORD=7767 psql -U sqlman -h localhost -d postgres \
  -c "CREATE DATABASE balansoft_ws_server OWNER sqlman;"
PGPASSWORD=7767 psql -U sqlman -h localhost -d postgres \
  -c "CREATE DATABASE balansoft_ws_local OWNER sqlman;"

# 2. Aplicar esquemas (idempotente)
PGPASSWORD=7767 psql -U sqlman -h localhost -d balansoft_ws_server \
  -f backend/balansoft-ws-server.sql
PGPASSWORD=7767 psql -U sqlman -h localhost -d balansoft_ws_local \
  -f backend/balansoft-ws-local.sql

# 3. Verificar (10 tablas en server, 22 en local)
PGPASSWORD=7767 psql -U sqlman -h localhost -d balansoft_ws_server -c "\dt"
PGPASSWORD=7767 psql -U sqlman -h localhost -d balansoft_ws_local -c "\dt"
```

- **`balansoft_ws`** (existente) sigue siendo la BD operativa de desarrollo del backend single-DB actual; no se toca.
- **`balansoft_ws_server`** es la BD de cuenta/licencia/sync para probar el rol servidor.
- **`balansoft_ws_local`** es la BD operativa para probar el rol local.
- La BD de tests automatizados es `balansoft_ws_test` (PostgreSQL real).
- En producción: `setup_db.sh` + despliegue (ver `DEPLOY.md`); los instaladores de la app se documentarán más adelante.

---

## 8. Flujo de Login y Sesión

### 8.1 Primer Login (Online)

```
App Flutter arranca
   │
   ├─► ¿Hay conexión al servidor remoto?
   │     │
   │     ├─► SÍ: POST {server}/api/v1/auth/login
   │     │         ├─► Server valida credenciales en balansoft_ws.credenciales
   │     │         ├─► Server valida licencia contra BALANSOFT-LM
   │     │         ├─► Server registra/actualiza balansoft_ws.dispositivos
   │     │         └─► Devuelve JWT + datos de cuenta + licencia
   │     │
   │     ├─► Flutter guarda JWT en flutter_secure_storage
   │     ├─► Flutter guarda datos de cuenta en identidad_local (local)
   │     └─► Flutter crea/actualiza empresas y usuarios locales
   │
   └─► A partir de aquí, TODAS las llamadas van a {local}/api/v1/*
```

> En desarrollo, `{server}` y `{local}` pueden apuntar a la misma máquina (la BD del servidor es local por ahora).

### 8.2 Login Subsecuente (con sesión recordada)

```
App Flutter arranca
   │
   ├─► ¿Hay JWT válido en flutter_secure_storage?
   │     │
   │     ├─► SÍ: Verifica expiración
   │     │         ├─► Válido: entra directo al Dashboard
   │     │         └─► Expirado: POST {server}/auth/refresh-token
   │     │
   │     └─► NO: Muestra pantalla de Login
   │
   └─► Login offline (si no hay internet)
         ├─► POST {local}/api/v1/auth/login-local   (pendiente)
         ├─► Local valida contra usuarios.password_hash
         └─► Devuelve JWT local (válido por N días de gracia)
```

### 8.3 Modo Offline

| Condición | Comportamiento |
|-----------|----------------|
| Sin internet, JWT válido | Opera normalmente contra API local |
| Sin internet, JWT expirado | Permite login local con `usuarios.password_hash` |
| Sin internet por > N días | `modo_offline = TRUE`, advertencia visual |
| Sin internet por > M días | Bloqueo de operaciones nuevas (solo consulta) |

**Configuración:**
```ini
MAX_OFFLINE_DAYS=30
OFFLINE_GRACE_DAYS=7
```

---

## 9. Estado de Implementación

### 9.1 Backend (FastAPI)

| Módulo | Estado | Notas |
|--------|:------:|-------|
| Auth (JWT) | ✅ | Login, register, refresh, forgot/reset password (contra `balansoft_ws`) |
| Pesaje | ✅ | create, close, anular, update, pendientes, list |
| Catálogos | ✅ | CRUD de flota, inventario, directorio |
| Kardex | ✅ | Movimientos 10/60, saldo a fecha de corte |
| Sincronización | ✅ | push/pull/status, catálogo sync |
| Reportes | ✅ | daily, monthly, vehicle, kardex, avanzados |
| Exportación | ✅ | Excel, PDF de kardex |
| Tickets PDF | ✅ | ReportLab, marca de agua ANULADO |
| Auditoría | ✅ | Middleware + `auditoria` + `logs_sistema` |
| Health check | ✅ | `GET /api/v1/health` |
| Licencias LM | ✅ | Ed25519, caché offline, tiers |
| Fotos | ✅ | Multipart upload, visualización |
| Peso en vivo | ✅ | HAL serial/TCP, `/weighing/scale/{id}/live` |
| Dispositivos | ✅ | Configuración y prueba de básculas |

### 9.2 Frontend (Flutter)

| Módulo | Estado | Notas |
|--------|:------:|-------|
| Login | ✅ | Email + password, hardware info |
| Registro | ✅ | Alta de empresa + admin |
| Dashboard | ✅ | KPIs, badge de salud, últimos pesajes |
| Pesajes | ✅ | Lista, detalle, formulario, cierre |
| Catálogos | ✅ | CRUD genérico declarativo (Clientes/Proveedores unificados con filtro C/P/A) |
| Reportes | ✅ | Diario, mensual, export Excel |
| Kardex | ✅ | Filtros, saldo acumulado, export |
| Configuración | ✅ | Perfil, báscula, archivos, tema |
| Sidebar | ✅ | Plegable, atajos NAV.md, Backspace para volver |
| Offline-first | ✅ | sqflite + cola de sync |
| Modo kiosk | ✅ | window_manager |
| Tema claro/oscuro | ✅ | ThemeController persistido |

### 9.3 Brechas Pendientes para la Arquitectura de Dos BDs

| Brecha | Prioridad | Acción requerida |
|--------|:---------:|------------------|
| Schemas split (server/local) | ✅ **Hecho** | `backend/balansoft-ws-server.sql` y `backend/balansoft-ws-local.sql` |
| Variable `APP_ROLE` en config | ✅ **Hecho** | `config.py` (`local`/`server`) + `.env.example` (+ `SERVER_API_URL`, `SERVER_DATABASE_URL`) |
| Routers condicionales en `main.py` | ✅ **Hecho** | `SERVER_ROUTERS`/`API_ROUTERS` según `APP_ROLE` |
| Endpoint `/auth/login-local` | ✅ **Hecho** | Login offline sin LM; token con marca `offline: true` |
| API del servidor (cuenta/licencia) | ✅ **Hecho** | `app/api/v1/endpoints/servidor.py`: register, login, refresh, licencias, panel, sync/server |
| Modelo SQLAlchemy del schema servidor | ✅ **Hecho** | `app/models_server.py` (ServerBase, 10 tablas, metadata independiente) |
| Motor de DB del servidor | ✅ **Hecho** | `server_async_engine` + `get_server_db` en `database.py` |
| Tests del servidor | ✅ **Hecho** | `tests/test_api_server.py` (6 tests sobre `balansoft_ws_server_test`) |
| Tabla `identidad_local` | ✅ **Hecho** | Modelo `IdentidadLocal` (singleton `id=true`) + `GET/PUT /api/v1/identity` (PUT solo ADMIN) + tile "Identidad de la estación" en Ajustes y guardado best-effort tras login |
| Sincronización de usuarios local → credenciales global | ✅ **Hecho** | CRUD `/api/v1/usuarios` encola `sync_queue` (entidad `usuario`); `GET/POST /api/v1/sync/usuarios/pendientes\|entregados`; server `POST /api/v1/sync/users` (upsert/desactivar por `id_cuenta`); orquestador best-effort en `AuthRepository` tras login |
| Validación de tolerancia comercial | ✅ **Hecho** | `_aplicar_tolerancia` en `WeighingService.close` (LogSistema WARN + auditoría) → `WeighingOut.advertencia_tolerancia` |
| Tabla/Catálogo `conceptos_kardex` | **Baja** | Catálogo editable de IDs de movimiento |
| Documentación de migración | **Media** | Script para clientes existentes single-DB |

### 9.4 Backend y frontend añadidos en esta iteración

| Pieza | Dónde | Estado |
|-------|-------|:------:|
| `POST /api/v1/auth/register` (server) | `servidor.py` | ✅ |
| `POST /api/v1/auth/login` (server, sin LM) | `servidor.py` | ✅ |
| `POST /api/v1/auth/refresh-token` (server) | `servidor.py` | ✅ |
| `GET/POST /api/v1/licencias` (server) | `servidor.py` | ✅ |
| `POST /api/v1/panel/login` + `GET /api/v1/panel/cuentas` | `servidor.py` | ✅ |
| `POST /api/v1/sync/server` (recepción de lotes) | `servidor.py` | ✅ |
| `POST /api/v1/auth/login-local` (local, offline) | `auth.py` | ✅ |
| Fallback offline en frontend (login-local) | `AuthRepository` | ✅ |
| URL del servidor configurable (frontend) | `AppConfig.serverApiUrl` | ✅ |
| Pantalla `Conexiones` (setup inicial + ajustes) | `connections_screen.dart` | ✅ |
| `GET/PUT /api/v1/identity` (identidad de estación) | `identity.py` | ✅ |
| CRUD `/api/v1/usuarios` + cola `sync_queue` | `usuarios.py` | ✅ |
| `GET/POST /api/v1/sync/usuarios/pendientes\|entregados` | `sync.py` | ✅ |
| `POST /api/v1/sync/users` (credenciales globales) | `servidor.py` | ✅ |
| Orquestador de usuarios + identidad tras login (best-effort) | `AuthRepository._sincronizarIdentidadYUsuarios` | ✅ |
| Gestión de usuarios en Ajustes (solo ADMIN) | `usuarios_screen.dart` | ✅ |
| Indicador "Sin red" en dashboard | `dashboard_screen.dart` | ✅ |
| Advertencia de tolerancia comercial en cierre | `weighing_service.py` + `pesajes.py` | ✅ |
| `POST /api/v1/panel/verificar-licencia` + `GET/PUT /api/v1/panel/cuentas/{id}` (server) | `servidor.py` + `schemas_server.py` | ✅ |
| Tests backend (identidad, usuarios, tolerancia, sync/server) | `tests/test_identity_usuarios_tolerancia.py` + `test_api_server.py` | ✅ |

### 9.5 Panel administrativo (BALASOFT-UI)

El alta de cuentas de las estaciones se hace desde un **panel web separado**
(`/home/yohander/Documentos/BALASOFT-UI/panel`), HTML + Bootstrap con la marca
`baLnsoft`, que habla contra la API del servidor (`APP_ROLE=server`).

- **Flujo de alta:** el panel llama `POST /api/v1/panel/verificar-licencia`
  (valida la clave contra el **LM local del servidor**, firma Ed25519 vía
  `LicenseClient.validate`) y solo si la licencia existe y está activa llama
  `POST /api/v1/auth/register`. Una clave inexistente en el LM devuelve
  `valida=false` (no 503); un LM caído devuelve 503 y bloquea el alta.
- **Login del proveedor:** `POST /api/v1/panel/login` contra
  `proveedores_usuarios` (roles `SUPERADMIN`/`SOPORTE`/`VENTAS`). Seed con
  `scripts/seed_panel_admin.py` (upsert por email).
- **Consulta:** `GET /api/v1/panel/cuentas` y detalle
  `GET /api/v1/panel/cuentas/{id}` (licencias, credenciales, nº de dispositivos).
- **Actualización de clientes:** `PUT /api/v1/panel/cuentas/{id}` (edita la
  ficha: nombre, RIF, email, teléfono, dirección y **estatus** — `activa` de la
  cuenta y `licencia_status`/`licencia_tier`/`fecha_expira`/`max_*` de su
  licencia; si la cuenta aún no tiene licencia se crea al indicar `licencia_key`).
  PATCH parcial: solo cambia lo que llegue, con checks de unicidad de RIF/email
  y de clave de licencia. Cada edición se registra en `auditoria_servidor`.
- La regla de negocio: un usuario solo puede operar una estación si su cuenta
  fue creada desde el panel con una licencia válida en el LM. Referencia de uso:
  `BALASOFT-UI/README.md`.

### 9.6 WServer y Modo Instalación de la app

El **WServer** es el backend local de la estación compilado con PyInstaller
(one-file) como un binario único llamado `WServer`. Es quien levanta la API
FastAPI local (`APP_ROLE=local`) de la máquina del cliente, sin necesidad de
Python ni de clonar el repo (los fuentes quedan compilados embebidos).

**Comportamiento en la primera instalación:**

1. Al arrancar el WServer por primera vez genera su runtime
   (`WSERVER_HOME` → por defecto `~/.balansoft-ws/wserver`), crea `.env` desde
   `.env.plantilla` (SECRET_KEY aleatoria por máquina), **crea la BD local**
   (`balansoft_ws_local`) si no existe y aplica el esquema canónico +
   migraciones de forma idempotente. Luego levanta la API en `127.0.0.1:8000`.
2. La app Flutter arranca sin `api_base_url` → entra en **modo instalación**:
   `WServerManager` localiza el binario (junto a la app instalada o vía
   `WSERVER_PATH`), lo lanza en detached y espera a que `/api/v1/health`
   responda. Solo entonces muestra `Conexiones` (`setupMode: true`) con la
   URL local prefijada (`http://localhost:8000`), **editable** y comprobada
   automáticamente (badge "WServer local activo").
3. El usuario guarda la URL local + servidor central y continúa al login.

**Piezas:**

| Pieza | Dónde | Estado |
|-------|-------|:------:|
| Entrada WServer (bootstrap BD + uvicorn) | `backend/wserver.py` | ✅ |
| Plantilla de configuración del cliente | `backend/.env.plantilla` | ✅ |
| Spec PyInstaller one-file | `backend/WServer.spec` | ✅ |
| Script de build (salida `dist/WServer/WServer`) | `backend/scripts/build_wserver.sh` | ✅ |
| Vaciado total de BDs (local + server) | `backend/scripts/reset_db.sh` | ✅ |
| Orquestador WServer (lanzar/esperar health) | `frontend/lib/core/services/wserver_manager.dart` | ✅ |
| Asegurado de WServer en primer arranque | `frontend/lib/main.dart` | ✅ |
| Modo instalación en Conexiones (URL por defecto + badge WServer) | `frontend/.../connections_screen.dart` | ✅ |

**Construir el binario:** `cd backend && uv run pyinstaller WServer.spec --noconfirm`
(o `./scripts/build_wserver.sh`). Probarlo: `WSERVER_HOME=/tmp/demo dist/WServer/WServer`.

> Requisito asociado: **REQ-NF-ARQ-013** — el servicio `WServer` debe estar
> elevado al iniciar el sistema por primera vez para que la conexión sea
> editable en la primera instalación (app lo arranca y espera `/health`).

---

## 10. Plan de Implementación

### Fase 1: Separación de Backend por Rol (2 semanas)

- [x] Crear `backend/balansoft-ws-server.sql` (10 tablas)
- [x] Crear `backend/balansoft-ws-local.sql` (22 tablas)
- [x] Añadir `APP_ROLE` a `config.py` + `.env.example`
- [x] Implementar routers condicionales en `main.py`
- [x] Crear endpoint `/auth/login-local`
- [x] Crear API del servidor (`servidor.py`: register, login, refresh, licencias, panel, sync/server)
- [x] Tests: backend en modo server y local (`tests/test_api_server.py` + smoke test sobre `balansoft_ws_server`)
- [x] `identidad_local` como tabla administrada por el backend (modelo + uso tras primer login)
- [x] Panel administrativo para el alta de cuentas (`BALASOFT-UI/panel`) + `scripts/seed_panel_admin.py`
- [x] Configurar `LICENSE_API_URL`/LM local real en la estación (validación de licencias del panel)

### Fase 2: Sincronización Bidireccional (2 semanas)

- [ ] Implementar `sync/push` completo (local → server)
- [ ] Implementar `sync/pull` completo (server → local)
- [x] Sincronización de usuarios (local → credenciales globales, orquestada por Flutter)
- [ ] Sincronización de boletos (local → server)
- [ ] Resolución de conflictos (último timestamp gana)
- [ ] Tests: sync con datos simulados

### Fase 3: Frontend Flutter (2 semanas)

- [x] Login con caché offline y `login-local` (fallback en `AuthRepository` + `AppConfig.offline`)
- [x] Manejo de `identidad_local` (GET/PUT identity + tile en Ajustes + guardado tras login)
- [x] Indicador de modo offline en la UI (badge "Sin red" en dashboard según `AppConfig.offline`)
- [ ] Navegación según `NAV.md`

### Fase 4: Migración y Cierre (1 semana)

- [ ] Script `migrate_to_split.sql` para clientes existentes
- [ ] Documento `MIGRACION-SPLIT.md`
- [ ] Capacitación a proveedores
- [ ] Manual de usuario

> **Instaladores de la app (Linux `.deb`, Windows Inno, Android):** se documentarán en una fase posterior, fuera del alcance actual.

---

## 11. Configuración (`.env`)

### 11.1 Desarrollo actual

```ini
APP_ENV=development
DEBUG_MODE=true

# Backend single-DB actual: opera contra la BD operativa (rol local)
APP_ROLE=local
DATABASE_URL=postgresql+asyncpg://sqlman:7767@localhost:5432/balansoft_ws
DATABASE_URL_SYNC=postgresql+psycopg2://sqlman:7767@localhost:5432/balansoft_ws

# BDs de la arquitectura split (pruebas en este mismo equipo)
# SERVER_API_URL=http://localhost:8002
# SERVER_DATABASE_URL=postgresql+asyncpg://sqlman:7767@localhost:5432/balansoft_ws_server

SECRET_KEY=<generado con openssl rand -hex 32>
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=7

LICENSE_API_URL=http://127.0.0.1:9001/api/v1
LICENSE_ADMIN_URL=http://127.0.0.1:9000
LICENSE_PUBLIC_KEY_PATH=keys/lm_public_key.pem
LICENSE_PRODUCT_CODE=WS
```

### 11.2 Objetivo: servidor (producción)

```ini
APP_ROLE=server
APP_ENV=production
DEBUG_MODE=false

DATABASE_URL=postgresql+asyncpg://balansoft:pass@localhost:5432/balansoft_ws

SECRET_KEY=<generado con openssl rand -hex 32>
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=7

CORS_ORIGINS=["https://app.balansoft.example.com"]
```

### 11.3 Objetivo: local (producción)

```ini
APP_ROLE=local
APP_ENV=production
DEBUG_MODE=false

DATABASE_URL=postgresql+asyncpg://balansoft:pass@localhost:5432/balansoft_ws_local
SERVER_API_URL=http://servidor.empresa.com:8002/api/v1

SECRET_KEY=<generado con openssl rand -hex 32>
ALGORITHM=HS256
LOCAL_TOKEN_EXPIRE_DAYS=7
MAX_OFFLINE_DAYS=30
OFFLINE_GRACE_DAYS=7

CORS_ORIGINS=["http://localhost:8003"]
```

---

## 12. Documentos Relacionados

| Documento | Estado | Descripción |
|-----------|:------:|-------------|
| `MANEJO_DB.md` | **Este documento** | Arquitectura de dos BDs, setup de desarrollo, login, estado y plan |
| `backend/balansoft-ws-server.sql` | Vigente | Schema canónico del servidor (10 tablas) |
| `backend/balansoft-ws-local.sql` | Vigente | Schema canónico local (22 tablas) |
| `ARCH.md` | Requiere actualización | Añadir dos PostgreSQL + `APP_ROLE` |
| `PRD.md` | Requiere actualización | 1 empresa/máquina; licencia fuera de BD local |
| `IMPLEMENTADO.md` | Requiere actualización | Tablas por rol; endpoints condicionales |
| `DEPLOY.md` | Requiere actualización | Dos despliegues; `setup_db_server/local` |
| `RESUMEN-API-LICENCIAS.md` | Requiere actualización | Licencia en `balansoft_ws.cuentas` |
| `MODEL.md` | Vigente | Reglas de negocio, cálculos, kardex |
| `MODELO_ESTANDAR.md` | Vigente | Roles, navegación, reglas de inmutabilidad |
| `NAV.md` | Vigente | Mapa de navegación y atajos |
| `UI-UX.md` | Requiere actualización | Integrar navegación de `NAV.md` |

---

## 13. Referencias

- `backend/balansoft-ws-server.sql` — Schema canónico del servidor
- `backend/balansoft-ws-local.sql` — Schema canónico local
- `MODEL.md` — Reglas de negocio del boleto, cálculos, kardex 10/60
- `MODELO_ESTANDAR.md` — Roles, navegación, reglas de inmutabilidad
- `NAV.md` — Mapa de navegación y atajos de teclado
- `ARCH.md` — Decisiones de arquitectura (a actualizar)
- `PRD.md` — Fuente de verdad del negocio (a actualizar)
- `IMPLEMENTADO.md` — Inventario de lo construido (a actualizar)
- `DEPLOY.md` — Despliegue (a actualizar)
- `RESUMEN-API-LICENCIAS.md` — Validación de licencias (a actualizar)

---

*Documento consolidado a partir de la arquitectura de dos bases de datos, `MODEL.md`, `MODELO_ESTANDAR.md`, `NAV.md` y los schemas canónicos del backend. Instaladores de la app excluidos del alcance por ahora.*