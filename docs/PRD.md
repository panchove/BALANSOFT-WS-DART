# BALANSOFT-WS: Product Requirements Document (PRD)

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 25010, ISO/IEC 17025, ISO/IEC 27001
**Fuente:** Sistema BALANSOFT-WS  
**Norma:** ISO/IEC 25010, ISO/IEC 17025, ISO/IEC 27001, ISO 8601  
**Fuente:** `docs/MANEJO_DB.md` (arquitectura vigente), `docs/MODELO_ESTANDAR.md`, código fuente

---

## 1. Resumen Ejecutivo

**BALANSOFT-WS** es un sistema de pesaje industrial para camiones con arquitectura **cliente-servidor** y **base de datos dual** (server/local). La decisión arquitectónica fundamental es la **separación de la base de datos en dos instancias**:

| Base de Datos                                  | Responsabilidad                                                                                      | Tecnología     |
|------------------------------------------------|------------------------------------------------------------------------------------------------------|----------------|
| **`balansoft_ws`** (servidor)                  | Cuenta, licencia, credenciales globales, dispositivos, sesiones, sincronización, panel del proveedor | PostgreSQL 15+ |
| **`balansoft_ws_local`** (máquina del cliente) | Todo lo operativo: usuarios locales, flota, inventario, boletos, kardex, auditoría, configuración    | PostgreSQL 15+ |

**Regla fundamental:** Una máquina local = una empresa = una cuenta.

Se adopta **una sola base de código FastAPI** desplegada en dos roles mediante `APP_ROLE=server|local`.

---

## 2. Arquitectura

### 2.1 Decisión Arquitectónica: Una API con Routers Condicionales

Una sola base de código FastAPI desplegada en dos roles mediante `APP_ROLE=server|local`.

```python
# backend/app/main.py
ROUTERS = SERVER_ROUTERS if settings.app_role == "server" else API_ROUTERS
```

**Responsabilidades por API:**

| Endpoint                                  | API Server | API Local  |
|-------------------------------------------|:----------:|:----------:|
| `POST /auth/register`                     |     ✅      |     ❌      |
| `POST /auth/login` (primer login, online) |     ✅      |     ❌      |
| `POST /auth/login-local` (offline)        |     ❌      |     ✅      |
| `POST /auth/refresh-token`                |     ✅      |     ✅      |
| `POST /licencias/validar`                 |     ✅      |     ❌      |
| `GET /licencias/snapshot`                 |     ✅      | ✅ (caché)  |
| `POST /sync/push`                         | ✅ (recibe) | ✅ (envía)  |
| `GET /sync/pull`                          | ✅ (envía)  | ✅ (recibe) |
| `POST /weighing/*`                        |     ❌      |     ✅      |
| `GET /catalogo/*`                         |     ❌      |     ✅      |
| `GET /reports/*`                          |     ❌      |     ✅      |
| `POST /panel/*` (proveedor)               |     ✅      |     ❌      |
| `GET /health`                             |     ✅      |     ✅      |

### 2.2 Estados de la Transacción (Boleto)

| Estado         | Descripción                          | Reportes                                     |
|----------------|--------------------------------------|----------------------------------------------|
| **PENDIENTE**  | Entrada registrada, esperando salida | Cuenta en "En Tránsito"                      |
| **CERRADO**    | Entrada + salida completas           | Cuenta en Ingreso/Despacho                   |
| **MODIFICADO** | Boleto CERRADO/PENDIENTE editado     | Cuenta según su estado base                  |
| **ANULADO**    | Cancelado (requiere auditoría)       | **NO** cuenta en reportes, solo en auditoría |

**Regla crítica:** *El peso registrado por la báscula nunca puede ser editado.* Los únicos campos modificables en estado `MODIFICADO` son: `documento`, `flete`, `costo_flete`, `observaciones`, `peso_neto_declarado` (PND).

Normalización legacy: `COMPLETADO` → `CERRADO`, `ABIERTO`/`AUTOMATICO` → `PENDIENTE`.

### 2.3 Roles de Usuario

| Rol          | Permisos                                                                                     |
|--------------|----------------------------------------------------------------------------------------------|
| **ADMIN**    | Todo: catálogos, pesaje, modificar/anular, crear usuarios, configurar balanzas, ver licencia |
| **AUDITOR**  | Consultas, reportes, auditoría, modificar/anular. **No** crea usuarios ni configura          |
| **OPERADOR** | Pesaje entrada/salida, consulta básica de vehículos (absorbe el antiguo rol `TRABAJADOR`)    |

**Matriz de permisos por endpoint:**

| Endpoint                             | ADMIN | AUDITOR |  OPERADOR   |
|--------------------------------------|:-----:|:-------:|:-----------:|
| `POST /weighing/create`              |   ✅   |    ❌    |      ✅      |
| `POST /weighing/close`               |   ✅   |    ❌    |      ✅      |
| `PUT /weighing/{boleto}/anular`      |   ✅   |    ✅    |      ❌      |
| `PUT /weighing/{boleto}` (modificar) |   ✅   |    ✅    |      ❌      |
| `GET /catalogo/*`                    |   ✅   |    ✅    | ✅ (lectura) |
| `POST/PUT/DELETE /catalogo/*`        |   ✅   |    ❌    |      ❌      |
| `GET /reports/*`                     |   ✅   |    ✅    |      ❌      |
| `POST /panel/*` (proveedor)          |   ❌   |    ❌    |      ❌      |
| `GET /licencias/snapshot`            |   ✅   |    ✅    |      ❌      |

---

## 3. Cálculos y Reglas de Negocio

### 3.1 Fórmulas (MODEL.md)

| Sigla   | Descripción                           | Fórmula           |
|---------|---------------------------------------|-------------------|
| **PEC** | Peso entrada camión (chuto + trailer) | dato              |
| **PER** | Peso entrada remolque (opcional)      | dato              |
| **PTE** | Peso total entrada                    | `PEC + PER`       |
| **PSC** | Peso salida camión                    | dato              |
| **PSR** | Peso salida remolque                  | dato              |
| **PTS** | Peso total salida                     | `PSC + PSR`       |
| **PNT** | Peso neto total                       | `PTE − PTS`       |
| **PND** | Peso neto declarado (guía)            | dato              |
| **PDF** | Peso diferencia                       | `PNT − PND`       |
| **PDV** | Porcentaje desviación                 | `PDF / PND × 100` |

### 3.2 Tolerancia Comercial

Configurada en `productos.tolerancia` (porcentaje). Si `PDV` excede la tolerancia, el sistema **emite una advertencia** (no bloquea el cierre, pero queda registrada en auditoría).

### 3.3 Kardex

| ID     | Descripción              | Signo |
|--------|--------------------------|-------|
| 00     | Saldo Inicial            | —     |
| 01-09  | Definible por usuario    | +     |
| **10** | **Ingreso por Báscula**  | **+** |
| 11-49  | Definible por usuario    | +     |
| **60** | **Despacho por Báscula** | **−** |
| 61-99  | Definible por usuario    | −     |

**Determinación:** `PNT > 0` → Ingreso (ID 10); `PNT < 0` → Despacho (ID 60); `PNT = 0` → sin movimiento.

**Al anular CERRADO:** se registra movimiento **inverso** (10 ↔ 60) conservando historia.

**Saldo:** `SALDO FINAL = SALDO INICIAL + Σ(positivos) − Σ(negativos)` filtrado a fecha de corte.

> El catálogo editable de conceptos (`conceptos_kardex`) está **pendiente de implementar**; hoy los IDs 10/60 son constantes del sistema.

### 3.4 Series de Numeración y Concurrencia

- El número secuencial del boleto (`numero_boleto`, ej: `TA-00000001`) se deriva de la tabla `series_numeracion`.
- La obtención del siguiente número debe realizarse **dentro de una transacción con bloqueo pesimista** (`SELECT ... FOR UPDATE`), evitando condiciones de carrera en estaciones con múltiples operadores concurrentes.
- Un número de boleto emitido nunca se reasigna ni se reutiliza.
- No se permite borrar una serie de numeración si ya tiene boletos asociados (código 409).

### 3.5 Aislamiento Multi-Tenant

- Cada consulta, filtro, inserción o validación en la base de datos local y central debe incluir obligatoriamente el filtro por `id_empresa`.
- Ninguna métrica de Prometheus (`/metrics`) ni log público debe exponer el `id_empresa` o datos sensibles de clientes.

### 3.6 Columnas Reservadas (sin semántica definida)

| Atributo                                  | Valor              |
|-------------------------------------------|--------------------|
| `boletos_pesaje.multi_despacho_recepcion` | RESERVADA / INERTE |

**Reglas:**
1. **No usarla** en consultas, reportes, filtros ni UI. No hace nada.
2. **No borrarla** del esquema: rompería clientes existentes y el round-trip de sincronización.
3. **No quitarla del round-trip de sync.** El beneficio sería de ~35 bytes por boleto, a cambio de un riesgo real: si alguna estación tuviera el flag en `true`, al dejar de enviarlo el backend escribiría `FALSE` encima y **se perdería el dato**.
4. **Para implementarla** hace falta una **decisión de negocio** que defina la semántica.

---

## 4. Schema Canónico de Base de Datos

### 4.1 `balansoft_ws` — servidor (cuenta y licencia, NO datos operativos)

| Tabla                   | Propósito                                                                          |
|-------------------------|------------------------------------------------------------------------------------|
| `cuentas`               | Empresas registradas por el proveedor (riff_nit único, email_admin único)          |
| `licencias`             | Licencias por cuenta (tier DEMO/MONOPUESTA/CENTRAL, status, expira, `hardware_id`) |
| `dispositivos`          | Equipos autorizados por cuenta (`hardware_id` único)                               |
| `credenciales`          | Credenciales globales de login (email + hash, `rol_global`)                        |
| `sesiones`              | Tokens/sesiones JWT emitidos por el servidor                                       |
| `sync_sesiones`         | Sesiones de sincronización orquestadas desde el servidor                           |
| `sync_cola`             | Cola de pendientes recibida de los equipos locales                                 |
| `auditoria_servidor`    | Eventos de cuenta/licencia/sync (login, activaciones…)                             |
| `password_reset_tokens` | Recuperación de contraseña global                                                  |
| `proveedores_usuarios`  | Usuarios del panel del proveedor (SUPERADMIN/SOPORTE/VENTAS)                       |

No guarda boletos, kardex ni catálogos: esos viven solo en la máquina local.

### 4.2 `balansoft_ws_local` — máquina del cliente (todo lo operativo)

| Tabla                                                  | Propósito                                                                                                                                                                   |
|--------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `identidad_local`                                      | Vínculo con la cuenta (1 fila): `id_cuenta`, licencia cacheada, `modo_offline`                                                                                              |
| `empresas`                                             | Espejo local de la cuenta (1:1, provee `id_empresa` para FKs)                                                                                                               |
| `usuarios`                                             | Usuarios operativos con rol local (ADMIN/OPERADOR/AUDITOR)                                                                                                                  |
| `transportes`                                          | Empresas de transporte                                                                                                                                                      |
| `marcas` / `modelos_camion` / `camiones` / `remolques` | Flota y transporte                                                                                                                                                          |
| `conductores` / `terceros`                             | Directorio (conductores PK = cédula; terceros con `tipo` C/P)                                                                                                               |
| `productos` / `almacenes` / `categorias`               | Inventario y configuración                                                                                                                                                  |
| `balanzas`                                             | Configuración de básculas (HAL serial/TCP)                                                                                                                                  |
| `boletos_pesaje`                                       | Transaccional principal (entrada/salida, cálculos MODEL.md, `estado_boleto`)                                                                                                |
| `boletos_ediciones`                                    | Historial de modificaciones de boletos CERRADO                                                                                                                              |
| `imagenes_pesaje`                                      | Fotos de entrada/salida                                                                                                                                                     |
| `kardex`                                               | Movimientos (10/60), saldo a fecha de corte                                                                                                                                 |
| `series_numeracion`                                    | Series de numeración de boletos                                                                                                                                             |
| `permisos_acceso`                                      | Permisos por usuario y módulo                                                                                                                                               |
| `sync_queue` / `sync_logs`                             | Cola local de sincronización hacia el servidor                                                                                                                              |
| `auditoria` / `logs_sistema`                           | Auditoría operativa y logs                                                                                                                                                  |
| `configuraciones` / `parametros_sistema`               | Configuración local                                                                                                                                                         |
| `recordatorios` / `notificaciones`                     | Avisos de la estación: recordatorios programados por el ADMIN y la bandeja de avisos (idempotente por `dedup_key`)                                                          |
| `llaves_activacion`                                    | Llaves de activación de **un solo uso** que el ADMIN emite para autorizar una estación OPERADOR (código guardado como SHA-256, `codigo_preview` de 6 caracteres). Ver §13.7 |

**Tablas del esquema local (30, verificadas):** `identidad_local`, `empresas`, `usuarios`, `transportes`, `marcas`, `modelos_camion`, `camiones`, `remolques`, `conductores`, `terceros`, `productos`, `categorias`, `almacenes`, `balanzas`, `boletos_pesaje`, `boletos_ediciones`, `imagenes_pesaje`, `kardex`, `series_numeracion`, `permisos_acceso`, `sync_queue`, `sync_logs`, `auditoria`, `logs_sistema`, `configuraciones`, `parametros_sistema`, `recordatorios`, `notificaciones`, `llaves_activacion`, `password_reset_tokens`.

### 4.3 Columnas Reservadas (ver §6.3)

`boletos_pesaje.multi_despacho_recepcion` — BOOLEAN NOT NULL DEFAULT FALSE, **RESERVADA / INERTE**.

---

## 5. Configuración y Setup

### 5.1 Variables de Entorno Críticas (.env)

```ini
# Rol del despliegue
APP_ROLE=local  # o "server"

# Base de datos
DATABASE_URL=postgresql+asyncpg://sqlman:7767@localhost:5432/balansoft_ws
DATABASE_URL_SYNC=postgresql+psycopg2://sqlman:7767@localhost:5432/balansoft_ws

# Central (solo rol local)
SERVER_API_URL=http://localhost:8002
SERVER_DATABASE_URL=postgresql+asyncpg://sqlman:7767@localhost:5432/balansoft_ws_server
CENTRAL_TIMEOUT=30

# Seguridad
SECRET_KEY=<generado con openssl rand -hex 32>
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30

# LM Local (SGLB)
LICENSE_API_URL=http://localhost:8080/api/v1
LICENSE_PRODUCT_CODE=WS

# API
API_HOST=0.0.0.0
API_PORT=8000

# Internacionalización
IDIOMA_DEFAULT=es
```

### 5.2 Setup de Desarrollo (BD del servidor en la máquina local)

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

# 3. Verificar
PGPASSWORD=7767 psql -U sqlman -h localhost -d balansoft_ws_server -c "\dt"
PGPASSWORD=7767 psql -U sqlman -h localhost -d balansoft_ws_local -c "\dt"

# 4. Aplicar migraciones pendientes
./scripts/setup_db.sh aplicar-migraciones
```

### 5.3 Central local de desarrollo (réplica del rol server)

Para validar el flujo titular sin tocar el central de producción:

```bash
cd backend
APP_ROLE=server \
DATABASE_URL='postgresql+asyncpg://sqlman:7767@localhost:5432/balansoft_ws_server' \
DATABASE_URL_SYNC='postgresql+psycopg2://sqlman:7767@localhost:5432/balansoft_ws_server' \
API_PORT=8002 API_HOST=127.0.0.1 \
  .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8002
```

---

## 6. Flujo de Login y Sesión

### 6.1 Primer Login (Online)

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

### 6.2 Login Subsecuente (con sesión recordada)

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
         ├─► POST {local}/api/v1/auth-login-local   (fallback en AuthRepository)
         ├─► Local valida contra usuarios.password_hash
         └─► Devuelve JWT local (válido por N días de gracia)
```

### 6.3 Modo Offline

| Condición                  | Comportamiento                                   |
|----------------------------|--------------------------------------------------|
| Sin internet, JWT válido   | Opera normalmente contra API local               |
| Sin internet, JWT expirado | Permite login local con `usuarios.password_hash` |
| Sin internet por > N días  | `modo_offline = TRUE`, advertencia visual        |
| Sin internet por > M días  | Bloqueo de operaciones nuevas (solo consulta)    |

**Configuración:**
```ini
MAX_OFFLINE_DAYS=30
OFFLINE_GRACE_DAYS=7
```

---

## 7. Estado de Implementación

### 7.1 Backend (FastAPI)

| Módulo         | Estado | Notas                                           |
|----------------|:------:|-------------------------------------------------|
| Auth (JWT)     |   ✅    | Login, register, refresh, forgot/reset password |
| Pesaje         |   ✅    | create, close, anular, update, pendientes, list |
| Catálogos      |   ✅    | CRUD de flota, inventario, directorio           |
| Kardex         |   ✅    | Movimientos 10/60, saldo a fecha de corte       |
| Sincronización |   ✅    | push/pull/status, catálogo sync                 |
| Reportes       |   ✅    | daily, monthly, vehicle, kardex, avanzados      |
| Exportación    |   ✅    | Excel, PDF de kardex                            |
| Tickets PDF    |   ✅    | ReportLab, marca de agua ANULADO                |
| Auditoría      |   ✅    | Middleware + `auditoria` + `logs_sistema`       |
| Health check   |   ✅    | `GET /api/v1/health`                            |
| Licencias LM   |   ✅    | Ed25519, caché offline, tiers                   |
| Fotos          |   ✅    | Multipart upload, visualización                 |
| Peso en vivo   |   ✅    | HAL serial/TCP, `/weighing/scale/{id}/live`     |
| Dispositivos   |   ✅    | Configuración y prueba de básculas              |

### 7.2 Frontend (Flutter)

| Módulo            | Estado | Notas                                                                        |
|-------------------|:------:|------------------------------------------------------------------------------|
| Login             |   ✅    | Email + password, hardware info                                              |
| Registro          |   ✅    | Alta de empresa + admin                                                      |
| Dashboard         |   ✅    | KPIs, badge de salud, últimos pesajes                                        |
| Pesajes           |   ✅    | Lista, detalle, formulario, cierre                                           |
| Catálogos         |   ✅    | CRUD genérico declarativo (Clientes/Proveedores unificados con filtro C/P/A) |
| Reportes          |   ✅    | Diario, mensual, export Excel                                                |
| Configuración     |   ✅    | Perfil, báscula, archivos, tema                                              |
| Sidebar           |   ✅    | Plegable, atajos NAV.md, Backspace para volver                               |
| Offline-first     |   ✅    | sqflite + cola de sync                                                       |
| Modo kiosk        |   ✅    | window_manager                                                               |
| Tema claro/oscuro |   ✅    | ThemeController persistido                                                   |

### 7.3 Brechas Pendientes para la Arquitectura de Dos BDs

| Brecha                                                 |  Prioridad  | Acción requerida                                                     |
|--------------------------------------------------------|:-----------:|----------------------------------------------------------------------|
| Schemas split (server/local)                           | ✅ **Hecho** | `backend/balansoft-ws-server.sql` y `backend/balansoft-ws-local.sql` |
| Variable `APP_ROLE` en config                          | ✅ **Hecho** | `config.py` (`local`/`server`) + `.env.example`                      |
| Routers condicionales en `main.py`                     | ✅ **Hecho** | `SERVER_ROUTERS`/`API_ROUTERS` según `APP_ROLE`                      |
| Endpoint `/auth/login-local`                           | ✅ **Hecho** | Login offline sin LM; token con marca `offline: true`                |
| API del servidor (cuenta/licencia)                     | ✅ **Hecho** | `app/api/v1/endpoints/servidor.py`                                   |
| Modelo SQLAlchemy del schema servidor                  | ✅ **Hecho** | `app/models_server.py` (10 tablas)                                   |
| Motor de DB del servidor                               | ✅ **Hecho** | `server_async_engine` + `get_server_db`                              |
| Tests del servidor                                     | ✅ **Hecho** | `tests/test_api_server.py` (6 tests)                                 |
| Tabla `identidad_local`                                | ✅ **Hecho** | Modelo + `GET/PUT /api/v1/identity`                                  |
| Sincronización de usuarios local → credenciales global | ✅ **Hecho** | CRUD `/api/v1/usuarios` encola `sync_queue`                          |
| Validación de tolerancia comercial                     | ✅ **Hecho** | `_aplicar_tolerancia` en `WeighingService.close`                     |
| Tabla/Catálogo `conceptos_kardex`                      |  **Baja**   | Catálogo editable de IDs de movimiento                               |
| Documentación de migración                             |  **Media**  | Script para clientes single-DB                                       |

### 7.4 Piezas Añadidas en esta Iteración

| Pieza                                                                          | Dónde                                                               | Estado |
|--------------------------------------------------------------------------------|---------------------------------------------------------------------|:------:|
| `POST /api/v1/auth/register` (server)                                          | `servidor.py`                                                       |   ✅    |
| `POST /api/v1/auth/login` (server, sin LM)                                     | `servidor.py`                                                       |   ✅    |
| `POST /api/v1/auth/refresh-token` (server)                                     | `servidor.py`                                                       |   ✅    |
| `GET/POST /api/v1/licencias` (server)                                          | `servidor.py`                                                       |   ✅    |
| `POST /api/v1/panel/login` + `GET /api/v1/panel/cuentas`                       | `servidor.py`                                                       |   ✅    |
| `POST /api/v1/sync/server` (recepción de lotes)                                | `servidor.py`                                                       |   ✅    |
| `POST /api/v1/auth/login-local` (local, offline)                               | `auth.py`                                                           |   ✅    |
| Fallback offline en frontend (login-local)                                     | `AuthRepository`                                                    |   ✅    |
| URL del servidor configurable (frontend)                                       | `AppConfig.serverApiUrl`                                            |   ✅    |
| Pantalla `Conexiones` (setup inicial + ajustes)                                | `connections_screen.dart`                                           |   ✅    |
| `GET/PUT /api/v1/identity` (identidad de estación)                             | `identity.py`                                                       |   ✅    |
| CRUD `/api/v1/usuarios` + cola `sync_queue`                                    | `usuarios.py`                                                       |   ✅    |
| `GET/POST /api/v1/sync/usuarios/pendientes\|entregados`                        | `sync.py`                                                           |   ✅    |
| `POST /api/v1/sync/users` (credenciales globales)                              | `servidor.py`                                                       |   ✅    |
| Orquestador de usuarios + identidad tras login (best-effort)                   | `AuthRepository._sincronizarIdentidadYUsuarios`                     |   ✅    |
| Gestión de usuarios en Ajustes (solo ADMIN)                                    | `usuarios_screen.dart`                                              |   ✅    |
| Indicador "Sin red" en dashboard                                               | `dashboard_screen.dart`                                             |   ✅    |
| Advertencia de tolerancia comercial en cierre                                  | `weighing_service.py` + `pesajes.py`                                |   ✅    |
| `POST /api/v1/panel/verificar-licencia` + `GET/PUT /api/v1/panel/cuentas/{id}` | `servidor.py` + `schemas_server.py`                                 |   ✅    |
| Tests backend (identidad, usuarios, tolerancia, sync/server)                   | `tests/test_identity_usuarios_tolerancia.py` + `test_api_server.py` |   ✅    |

---

## 8. Plan de Implementación

### Fase 1: Separación de Backend por Rol (2 semanas)
- [x] Crear `backend/balansoft-ws-server.sql` (10 tablas)
- [x] Crear `backend/balansoft-ws-local.sql` (26 tablas)
- [x] Añadir `APP_ROLE` a `config.py` + `.env.example`
- [x] Implementar routers condicionales en `main.py`
- [x] Crear endpoint `/auth/login-local`
- [x] Crear API del servidor (`servidor.py`: register, login, refresh, licencias, panel, sync/server)
- [x] Tests: backend en modo server y local (`tests/test_api_server.py` + smoke test)
- [x] `identidad_local` como tabla administrada por el backend
- [x] Panel administrativo para el alta de cuentas (`BALASOFT-UI/panel`) + `scripts/seed_panel_admin.py`
- [x] Configurar `LICENSE_API_URL`/LM local real en la estación

### Fase 2: Sincronización Bidireccional (2 semanas)
- [ ] Implementar `sync/push` completo (local → server)
- [ ] Implementar `sync/pull` completo (server → local)
- [ ] Sincronización de usuarios (local → credenciales globales)
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

### Configuración (.env) (ver §11)

---

## 9. Normativa y Cumplimiento ISO/IEC

### 9.1 ISO/IEC 25010 — Calidad del Producto Software (SQuaRE)

- **Adecuación Funcional:** Reglas de negocio de pesaje, cálculo de netos, tolerancia de merma y movimientos Kardex (10/60) son exactas, completas y verificadas por pruebas unitarias.
- **Eficiencia de Desempeño:** Latencias de endpoints de pesaje y catálogos: p50 < 50 ms, p95 < 200 ms bajo concurrencia normal. Paginación obligatoria (`limit`, `skip`) y consultas optimizadas sin problemas de N+1.
- **Compatibilidad e Interoperabilidad:** Interoperabilidad probada con hardware multi-marca (Toledo, Yaohua, Rice Lake, Torrey, Keli, Epson, OKI). Coexistencia pacífica en red LAN (`0.0.0.0:8000`) y con puertos seriales locales.
- **Fiabilidad y Resiliencia:** Manejo de desconexiones abruptas en sockets TCP con timeout en `writer.wait_closed()`. Recuperación automática ante cortes de red y persistencia offline con cola de sincronización (`sync_queue`).
- **Seguridad:** Confidencialidad: Aislamiento multi-tenant por `id_empresa` en el 100% de las consultas. Integridad: Inmutabilidad física del peso capturado. Firma digital Ed25519 en validación de licencias. No repudio y Trazabilidad: Registro auditable de cada creación, modificación (`BoletoEdicion`) y anulación con usuario responsable, IP y timestamp.
- **Mantenibilidad:** Modularidad estricta: Capa HAL desacoplada del parser de texto; servicios desacoplados de rutas FastAPI; blocs desacoplados de vistas Flutter. Código limpio sin warnings (`ruff check` y `flutter analyze` siempre en verde).
- **Portabilidad:** WServer empaquetado en binario autocontenido (PyInstaller one-file). Compatibilidad multiplataforma Linux y Windows.

### 9.2 ISO/IEC 17025 & OIML R 76-1 — Metrología Legal e Integridad de Medición

- **Inmutabilidad Metrológica:** El software no debe permitir la alteración arbitraria ni el suavizado falseado de pesos físicos una vez capturados y firmados por el operador.
- **Trazabilidad de la Medición:** Cada pesaje registrado debe almacenar:
  - Identificador único de la báscula (`id_balanza`).
  - Marca de tiempo en UTC (ISO 8601).
  - Estado de estabilidad metrológica (`stable` / `unstable`).
  - Modo de captura (`es_manual = false` si provino de hardware real).
- **Control de Sobrecapacidad:** Rechazo estricto si el valor supera el 105% de la capacidad nominal de la báscula (`TOLERANCIA_CAPACIDAD = 1.05`).
- **Seguimiento de Cero:** Validación metrológica para impedir el pesaje de boletos con peso neto nulo o negativo.

### 9.3 ISO/IEC 27001 — Seguridad de la Información

- **Criptografía:** Contraseñas con hashing robusto (bcrypt/argon2). Tokens JWT firmados con HMAC-SHA256 y secreto criptográfico aleatorio de alta entropía (`openssl rand -hex 32`). Licencias validadas con firmas asimétricas Ed25519 de curva elíptica.
- **Control de Acceso:** Matriz de permisos por módulo y rol (`ADMIN`, `OPERADOR`, `AUDITOR`, `TRABAJADOR`). Verificación en backend mediante dependencias FastAPI (`require_admin`, etc.).
- **Privacidad y Multi-Tenancy:** Ninguna métrica de Prometheus (`/metrics`) ni log de sistema debe exponer identificadores de empresas clientes (`id_empresa`) ni información fiscal confidencial.

### 9.4 ISO 8601 — Representación de Fecha y Hora

- **Almacenamiento y Tránsito:** Todas las fechas y horas se procesan, persisten y transmiten en **UTC** con formato estándar ISO 8601: `YYYY-MM-DDTHH:MM:SSZ`.
- **Presentación:** La conversión a la zona horaria local del cliente se realiza exclusivamente en la capa de presentación de Flutter al renderizar componentes o tickets.

### 9.5 ISO/IEC 10646 & Estándares de Codificación

- **Unicode / UTF-8:** Codificación predeterminada para base de datos, API REST, logs y archivos de configuración.
- **ISO/IEC 8859-1 (Latin-1) / CP850:** Utilizado de forma estricta en el spooling binario para impresoras térmicas ESC/POS e impresoras matriciales ESC/P para garantizar la correcta reproducción de tildes, diéresis y la letra `Ñ` sin secuencias corruptas.
- **ISO/IEC 18004:** Especificación para la generación de códigos QR bidimensionales impresos en tickets de pesaje.
- **ISO/IEC 15417:** Especificación para códigos de barras Code 128 lineales.

### 9.6 ISO/IEC/IEEE 29119 — Pruebas de Software

- Todos los cambios deben contar con pruebas automatizadas en suite:
  - Unit tests y widget tests (FastAPI / Flutter).
  - Tests E2E herméticos con stub criptográfico del License Manager.
  - Verificación por mutación: comprobar que los tests fallen si se revierte o corrompe el comportamiento probado.

---

## 10. Referencias

- `docs/MANEJO_DB.md` — Arquitectura de dos BDs, setup dev, flujo login, modelo de cuenta y dispositivos (§13), estado actual y roadmap.
- `docs/MODELO_ESTANDAR.md` — Estatus de transacciones, roles de usuario, mapa de navegación, consultas, reportes.
- `IMPLEMENTADO.md` v2.0 — Inventario de lo construido, verificado contra código.
- `docs/BALANZAS_SOPORTADAS.md` — Matriz marca→protocolo→config y limitaciones de indicadores reales.
- `docs/OBSERVABILIDAD.md` — Métricas, cardinalidad, alertas, multi-tenancy, diagnóstico.
- `docs/I18N_Y_ONBOARDING.md` — Internacionalización es/en/pt y onboarding.
- `docs/NAV.md` — Navegación/sidebar y atajos de teclado.
- `docs/INPUTS_MAP.md` — Atajos de teclado de la UI.
- `docs/USO-API.md` — Documentación de la API.
- `docs/PLANES-PAGOS.md` — Planes y pagos del sistema.
- `docs/legal/TERMINOS_CONDICIONES.md` — Términos y condiciones.
- `EULA.md` — Acuerdo de licencia de usuario final.
- `docs/legal/PROPRIETARY_NOTICE.md` — Aviso de propiedad intelectual.
- `AGENTS.md` — Atributos del repositorio, comandos canónicos y convenciones.
- `.agents/rules/iso-iec-compliance.md` — Norma ISO/IEC en BALANSOFT-WS.
- `.agents/rules/industrial-weighing-safety.md` — Reglas invariables de seguridad operativa.
- `.agents/rules/hardware-io-concurrency.md` — Reglas de concurrencia e I/O para hardware.
- `.agents/rules/ticket-layout-parity.md` — Regla de paridad de layout de tickets (Flutter ↔ Backend).
- `backend/app/main.py` — Punto de entrada de la API FastAPI.
- `backend/app/core/config.py` — Configuración centralizada pydantic-settings.
- `backend/balansoft-ws-server.sql` — Schema canónico servidor (10 tablas).
- `backend/balansoft-ws-local.sql` — Schema canónico local (26+4 tablas).
- `backend/migrations/*.sql` — Migraciones hacia adelante (001–025).
- `app/api/v1/endpoints/servidor.py` — Endpoints del rol servidor.
- `app/api/v1/endpoints/activacion.py` — Endpoints de activación de llaves.
- `app/services/ticket_service.py` — Servicio de generación de tickets PDF/TXT.
- `app/core/db_engine.py` — Motor de BD por prefijo de DATABASE_URL.
- `app/core/scale_hal.py` — HAL de balanza serial/TCP.
- `app/core/scale_parser.py` — Parser de frames de báscula.
- `app/models_server.py` — Modelos SQLAlchemy del schema servidor.
- `app/core/monitoring.py` — Middleware de métricas Prometheus.
- `app/core/seguridad_matrix.py` — Matriz de permisos por categoría.
- `app/services/llave_activacion_service.py` — Servicio de llaves de activación.
- `app/core/notification_scheduler.py` — Programador de notificaciones residente.
- `frontend/lib/presentation/widgets/ticket_preview_dialog.dart` — Widget de preview de ticket (fuente de verdad de layout).
- `frontend/lib/core/config/station_config.dart` — Configuración de estación (rol, URL API).
- `frontend/lib/core/services/wserver_manager.dart` — Gestor WServer (lanzar/esperar health).
- `frontend/integration_test/pesaje_flow_test.dart` — Test E2E de flujo de pesaje.
- `backend/scripts/lm_stub.py` — Stub del License Manager firmante Ed25519.
- `backend/scripts/mcp_hardware_server.py` — Servidor MCP industrial JSON-RPC 2.0.
- `backend/scripts/seed_panel_admin.py` — Seed de admin del panel proveedor.
- `backend/scripts/e2e_flutter.sh` — Entorno E2E Flutter: BD aislada + seed + stub LM + API.
- `tests/test_api_server.py` — Tests E2E del rol server sobre `balansoft_ws_server_test`.
- `tests/test_identity_usuarios_tolerancia.py` — Tests identidad, usuarios, tolerancia, sync/server.
- `tests/test_monitoring.py` — Tests de andamiaje de observabilidad.
- `tests/e2e/` — Tests E2E de contrato de licencia y ciclo offline.
- `docs/evidencia/volumen-analisis.md` — Análisis de rendimiento de 50k boletos.
- `docs/MIGRACION-SPLIT.md` — Documentación de migración a arquitectura split (planeada).