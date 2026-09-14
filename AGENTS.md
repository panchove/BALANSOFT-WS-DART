# AGENTS.md — BALANSOFT-WS

Sistema de estación de pesaje industrial para camiones (multi-empresa, API REST FastAPI + frontend Flutter cliente-servidor).

| Atributo          | Valor                                 |
|-------------------|---------------------------------------|
| **Documento**     | AGENTS.md                              |
| **Versión**       | 2.0                                    |
| **Fecha**         | 2026-09-08                             |
| **Estado**        | Vigente                                |
| **Autor**         | Equipo BALANSOFT                       |
| **Norma**         | ISO/IEC/IEEE 42010 + 29148             |
| **Fuente**        | `docs/PRD.md` (autoridad)              |

---

## 1. Propósito y alcance

Este archivo establece las **reglas inquebrantables** que cualquier agente (humano o IA) debe respetar al trabajar en este repositorio. Resume el stack canónico, el contexto del directorio y los requisitos no funcionales que aplican siempre.

---

## 2. Idioma y fuente de verdad

- **Idioma oficial del repo: español.** Documentación, comentarios y comunicación en español.
- **`docs/PRD.md` es la fuente de verdad.** `docs/ARCH.md`, `docs/MODEL.md` y `docs/UI-UX.md` derivan de él; ante cualquier conflicto entre docs de negocio, manda el PRD. `docs/MODEL.md` define el formato operativo de pantalla y cálculos.
- ⚠️ `docs/DOCUMENTACION-BALANSOFT-WS.md` es un documento de referencia paralelo (**no autoritativo**): contiene especificaciones históricas/simplificadas que pueden diferir del PRD. No alinear el sistema contra él.

---

## 3. Estado real de este directorio

- El repositorio **tiene código en dos subcarpetas** y documentación:
  - `backend/` — API FastAPI (Python 3.12+) con `uv`, `pytest`, `ruff`, `mypy`. Tests: 112/112 verdes (incluye 8 tests HAL, 6 de dispositivos, 7 de reportes avanzados, 1 snapshot de licencia, 11 de rate limiting y 8 de monitoreo).
  - `frontend/` — App Flutter (Dart), BLoC, offline-first con `sqflite`.
  - `docs/` — PRD.md (autoridad), ARCH.md, MODEL.md, UI-UX.md.
  - `backend/schema.sql` + `backend/migrations/*.sql` — esquema e historia de BD.
  - `backend/scripts/` — `setup_db.sh` (instalar/actualizar BD), `seed_data.py`, `seed_simulacion.py`, `generate_signing_keys.py`, `start_api.sh`, `backup.sh`, `verify.sh`, `install_cliente.sh`.
  - `backend/deploy/balansoft-ws.service` — unidad systemd de producción.
- No es repo git (carpeta compartida de VM). Comandos canónicos:

| Comando | Lugar |
|---------|-------|
| `uv sync` | `backend/` |
| `uv run pytest -q` | `backend/` |
| `uv run ruff check app tests` | `backend/` |
| `uv run mypy tests/` | `backend/` |
| `flutter test` | `frontend/` |
| `flutter analyze` | `frontend/` |
| `uvicorn app.main:app --port 8000` | `backend/` |

---

## 4. Stack canónico (PRD §1–2 alineado a la implementación real)

| Capa | Tecnología |
|------|------------|
| Backend | Python 3.12+ / **FastAPI** (async), Pydantic v2, SQLAlchemy 2.0 async (asyncpg) |
| Base de datos | **PostgreSQL 15+** (producción); SQLite en desarrollo NO se usa: la BD de tests es PostgreSQL real (`balansoft_ws_test`) |
| Esquema / Migraciones | `schema.sql` (esquema final idempotente) + `migrations/*.sql` hacia adelante (sin Alembic) |
| Auth | **JWT** (python-jose, HS256) access+refresh; passwords con **BCrypt** (passlib) |
| Tenancy | Multi-**empresa**: toda entidad lleva `id_empresa` (UUID) FK a `empresas`; se resuelve del JWT (`get_current_empresa`) |
| Licencias | Cliente HTTP contra **BALANSOFT-LM** (SGLB): edición Ed25519 anti-fake-server, caché, tiers DEMO/MONOPUESTA/CENTRAL |
| PDF / Excel | ReportLab (tickets PDF, marca de agua ANULADO) / openpyxl (exportación) |
| Frontend | **Flutter** (Dart) — web/desktop/mobile, BLoC, offline-first con cola de sincronización |
| Sync offline | `sqflite` local + cola `pendiente/sincronizado` + endpoints `/api/v1/sync/*` |
| Deploy | Servidor Linux con systemd (`balansoft-ws.service`) + `scripts/setup_db.sh`; operaciones: `backup.sh`, `verify.sh`, `install_cliente.sh` |
| Seguridad / Ops | Rate limiting propio (`app/core/rate_limit.py`, cachetools, IP+email, límites por env) + monitoreo (`app/core/monitoring.py`, prometheus-client, endpoint `GET /metrics`) + CORS restringido por env |
| Hardware | ✅ HAL de balanza en backend (`app/core/scale_hal.py`: SerialScaleHAL/TcpScaleHAL + factory); endpoint `GET /weighing/scale/{id}/live` para lectura de peso en vivo (REQ-NF-ARQ-004, B7). Frontend: `ScaleApiClient` (API-first con fallback TCP) + `ScaleMonitorWidget` con `balanzaId`/descripción. El peso también se recibe vía TCP directo desde el simulador BSDD (`ScaleTcpClient`). |

Notas:

- **Sí hay API REST y JWT** (la UI Flutter consume `/api/v1/*`). Cualquier referencia a "sin API, sin JWT, ClaimsPrincipal, EJ* (EF6)" en docs es vestigio del histórico .NET/WinForms y **debe reinterpretarse** como FastAPI/JWT.
- **Histórico de migraciones de stack**: el proyecto migró Java/Spring+Vaaadin → PyQt6/FastAPI → .NET/WinForms (docs) → **FastAPI + Flutter (implementación vigente)**. Vestigios como `.env` con `JWT_SECRET`/`SERVER_PORT`/`SPRING_PROFILES_ACTIVE` se interpretan como `SECRET_KEY`/`API_PORT`/sin perfil simulado. No reintroducir frameworks no-FastAPI/no-Flutter.
- Los estados del boleto son **4**: `PENDIENTE`, `CERRADO`, `MODIFICADO`, `ANULADO` (MODEL.md); `COMPLETADO`/`ABIERTO`/`AUTOMATICO` son legacy y se normalizan en `WeighingService.normalizar_estado`.

---

## 5. Configuración local (`.env`)

- Variables vigentes (ver `backend/.env.example`): `DATABASE_URL`, `DATABASE_URL_SYNC`, `API_HOST`, `API_PORT=8000`, `SECRET_KEY`, `ALGORITHM`, `ACCESS_TOKEN_EXPIRE_MINUTES`, `REFRESH_TOKEN_EXPIRE_DAYS`, `CORS_ORIGINS`, `LICENSE_API_URL`, `LICENSE_ADMIN_URL`, `LICENSE_PUBLIC_KEY` (Ed25519, una línea), `LICENSE_PRODUCT_CODE`, `APP_ENV`, `DEBUG_MODE`, límites de licencia (`DEMO_MAX_RECORDS`, etc.), `LOG_*`, `SYNC_*`, `RATE_LIMIT_*` (enabled/login/register/password/window/trust_proxy), `METRICS_ENABLED`, `BACKUP_DIR`, `BACKUP_RETENTION_DAYS`.
- No existe `SERVER_PORT=7000` ni perfil simulado de hardware en la implementación actual.
- Contiene credenciales de desarrollo reales (`.env` local). Rotar en producción; `SECRET_KEY` debe ser aleatoria (≥32 bytes).

---

## 6. Requisitos no funcionales invariables (romper estas = bug)

Cada requisito tiene un **identificador trazable** (`REQ-NF-<área>-NNN`) que se reutiliza en ARCH.md y UI-UX.md para mantener la trazabilidad ISO/IEC/IEEE 29148. Las verificaciones reflejan la implementación real (FastAPI/Flutter).

| ID              | Título                                          | Prioridad | Verificación |
|-----------------|-------------------------------------------------|-----------|--------------|
| REQ-NF-ARQ-001  | Multi-empresa obligatorio (toda entidad con `id_empresa`)  | M | Tests de aislamiento por empresa |
| REQ-NF-ARQ-002  | Máquina de estados del boleto `PENDIENTE → CERRADO/MODIFICADO → ANULADO` | M | Tests unitarios de `WeighingService` (anular/no reutilizar número) |
| REQ-NF-ARQ-003  | Kardex: peso neto = entrada − salida (>0 INGRESO/ID 10, <0 DESPACHO/ID 60, =0 sin movimiento) | M | Tests de `_registrar_kardex` + inverso al anular CERRADO (10↔60) |
| REQ-NF-ARQ-004  | Estabilidad de pesada 3 s + validación de unidades KG/LBS | M | (Implementación futura vía estación/hardware) |
| REQ-NF-ARQ-005  | Modo MANUAL al fallar balanza (peso manual + fotos opcionales, solo ADMIN/SUPERVISOR) | M | Tests de endpoints con `_PERMISOS_PESO_MANUAL` |
| REQ-NF-ARQ-006  | Unidades: KG base interna; conversión 1 kg = 2.20462 lbs | M | Constantes de conversión en frontend/back (sin servicio dedicado) |
| REQ-NF-ARQ-007  | Roles ADMIN > SUPERVISOR > OPERADOR con matriz de permisos | M | Tests de autorización en endpoints (peso manual/anulación restringidos) |
| REQ-NF-ARQ-008  | Esquema DB vive en `schema.sql` + migraciones SQL versionadas | M | Inspección de `backend/schema.sql` + `backend/migrations/` |
| REQ-NF-ARQ-009  | Campos JSON en `JSONB` (PostgreSQL) para auditoría/logs | M | Tests de auditoría/logs |
| REQ-NF-ARQ-010  | Timestamps persistidos en UTC | M | Revisión de código + tests (`datetime.now(UTC)`) |
| REQ-NF-ARQ-011  | Fechas de DTOs/entidades sin sufijo `Utc` pero almacenadas en UTC | M | Convención de código |
| REQ-NF-ARQ-012  | Conversión a TZ local **solo** en capa de presentación (Flutter) | M | Revisión arquitectónica |
| REQ-NF-SEG-001  | Auditoría completa de boletos (usuario, IP, timestamp UTC, cambios) | M | Inspección de tabla `auditoria` + `AuditMiddleware` |
| REQ-NF-SEG-002  | Passwords con BCrypt | M | Inspección de `app/core/security.py` |
| REQ-NF-SEG-003  | Sesión con JWT (usuario, rol, `id_empresa`) | M | Inspección de `security.py` + `dependencies.py` |
| REQ-NF-OPE-001  | Modo kiosk: pantalla completa, sin bordes | M | Smoke test en app Flutter |
| REQ-NF-OPE-002  | Tema claro/oscuro persistente | M | `ThemeController` (SharedPreferences por dispositivo) |

> Cualquier desviación de estos requisitos requiere actualizar primero el PRD.md (fuente de verdad), propagando a ARCH.md y UI-UX.md.

---

## 7. Convenciones de documentación

- Los docs usan diagramas Mermaid de forma intensiva; validar sintaxis al editarlos (preview de VS Code o `mmdc`).
- Al cambiar requisitos, rutas/screens o roles: actualizar primero `docs/PRD.md` y luego derivar en `ARCH.md` y `UI-UX.md`.
- **Cabecera editorial** de cada MD: `Versión`, `Fecha`, `Estado`, `Autor`, `Norma` (ISO/IEC/IEEE 42010 + 29148), `Fuente`.
- **Identificadores trazables**: `REQ-FN-NNN` (requisitos funcionales), `REQ-NF-<área>-NNN` (no funcionales), `AR-NNN` (decisiones de arquitectura), `INT-NNN` (interfaces), `UX-NNN` (requisitos de UI).
- Los comandos de build/test citados en los docs (`uv run pytest`, `flutter test`) se ejecutan en `backend/` y `frontend/` respectivamente.

---

## 8. Historial de cambios

| Versión | Fecha       | Cambios                                                                       |
|---------|-------------|-------------------------------------------------------------------------------|
| 2.0     | 2026-09-08  | Re-alineación al stack real de implementación: FastAPI + PostgreSQL + Flutter (+ JWT, kardex numérico 10/60, inverso al anular, multi-empresa `id_empresa`). Reemplaza reinvención .NET/WinForms anterior. |
| 1.1     | 2026-08-20  | Cabecera editorial ISO/IEC/IEEE 42010+29148; tabla de requisitos trazables (REQ-NF-*). |
| 1.0     | 2026-08-20  | Versión inicial.                                                              |