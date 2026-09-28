# Changelog — BALANSOFT-WS

Este proyecto **no es un repositorio Git** (carpeta compartida de VM), por lo que no
se aplican tags; la versión se documenta exclusivamente en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

---

## [v1.2.0] — 2026-09-28

> Onboarding de instalación en dos modos (Servidor / Trabajador) y corrección del
> modelo de cuenta/dispositivos. Verificado: backend `248/248` ✓, `ruff` ✓,
> frontend `117/117` ✓, `flutter analyze` ✓, `flutter build linux --release` ✓.

### Añadido

- **Instalación en dos modos**
  - Flujo `SERVIDOR`: preferencias → modo → entorno → BD local → activación contra
    el central → empresa **precargada** (RIF y razón social de solo lectura) →
    dashboard con la sesión ya abierta, sin volver a pedir credenciales.
  - Flujo `TRABAJADOR` (cliente delgado): preferencias → modo → host/puerto +
    `/health` → login contra la API del servidor titular. No crea BD ni WServer.
  - `POST /api/v1/auth/login-central` acepta `modo_solicitado`; un equipo que no
    es titular y pide `SERVIDOR` recibe `403` indicando cuál equipo **sí** lo es.
- **Panel del proveedor**
  - `POST /api/v1/panel/cuentas/{id_cuenta}/titular` → reata la licencia a un
    equipo registrado y recalcula los roles (`SERVIDOR_LOCAL` / `LOCAL`), para
    corregir cuentas mal configuradas sin editar la base a mano.
  - El detalle de cuenta devuelve `dispositivos[]` y `hardware_titular`; la UI
    lista los equipos con el botón **"Designar titular"**.
- `i18n` es/en/pt para los textos de modo, activación, empresa precargada y
  trabajador (`docs/I18N_Y_ONBOARDING.md` v1.2, REQ-NF-ONB-010..015).

### Corregido

- **Titular de la licencia**: el rol del dispositivo se decidía por el orden de
  inserción de la fila y solo se asignaba al crearla, así que una cuenta podía
  quedar con el equipo equivocado como `SERVIDOR_LOCAL` y la instalación en
  modo Servidor se bloqueaba con `403`. Ahora la fuente de verdad es
  `licencias.hardware_id` (la misma que ata el `ADMIN`) y el rol se recalcula en
  cada login: no puede haber dos `SERVIDOR_LOCAL` y las cuentas mal aprobadas se
  autocorrigen (`docs/MANEJO_DB.md` §13).
- **Licencia virgen (`AVAILABLE`)**: el estado `AVAILABLE` del LM se guardaba tal
  cual en `licencias.licencia_status` y el central lo leía como licencia
  rechazada (`_licencia_activa` exigía `ACTIVA`), así que una licencia sin
  usar bloqueaba la instalación en modo Servidor y el panel mostraba
  "rechazada o inactiva (estatus AVAILABLE)". Ahora `AVAILABLE` = **virgen**: la
  cuenta queda `ACTIVA` y el primer equipo que valida se amarra a la licencia
  como titular único (`SERVIDOR_LOCAL`), que es lo que el panel muestra como
  "Disponible".
- El mensaje de error de activación ya no oculta el `detail` del central ni
  confunde "API local caída" con "el central rechazó la cuenta" (502 con causa).
- `scripts/reset_total.sh`: el borrado del keyring ya no falla por entradas
  fantasma de GNOME Keyring, y una compilación fallida no borra el bundle previo.

### Seguridad

- Rotar la contraseña de cualquier cuenta compartida por chat: las credenciales
  de los diagnósticos quedan expuestas en el historial.

---

## [v1.1.0] — 2026-09-11

> Iteración de cierre según `ACTUAR.md` (B1–B6 y M1–M4). Frontend verificado:
> `flutter test` (52/52) ✓, `flutter analyze` ✓ y `flutter build linux --release` ✓.
> Pendiente de entorno con PostgreSQL: `uv run pytest -q` (backend) y smoke test.

### Añadido

- **Seguridad**
  - Tokens JWT migrados a `flutter_secure_storage` (B1, T1.1) con migración
    one-shot desde `SharedPreferences`.
  - Endpoint `forgot-password` + `reset-password` en backend y pantallas
    `ForgotPasswordScreen` / `ResetPasswordScreen` (B3, T1.3).
- **Cumplimiento**
  - Tabla `auditoria` con escrituras reales en pesajes y catálogos
    (create/update/delete) — `audit_service.py` (B5, T2.2).
  - Consumo de `max_sync_retries` y `SYNC_INTERVAL_MINUTES`: columna `fallido`
    e `intentos_sync`, `pushWeighing`, reintentos y sección de pesajes fallidos
    en el dashboard (B6, T2.3).
  - Modo kiosk fullscreen (B4, T2.1).
- **Cierre (Fase 3)**
  - Health check `GET /api/v1/health` + badge de estado del backend en el
    dashboard con re-check cada 30 s (M1, T3.1).
  - UI de exportación a Excel en la pantalla de reportes (M3, T3.3).
  - UI Kardex completa con filtros, movimientos con saldo acumulado y
    exportación PDF/Excel (M4, T3.4): backend `kardex/detalle` +
    `reports/export/kardex/{excel,pdf}`.

### Cambiado

- `signature_verifier.dart` eliminado (B2, T1.2).
- `database_helper` a versión 4 (columna `fallido`), `weighing_repository`
  respeta `maxSyncRetries` y marca pesajes fallidos.
- `SyncBloc` con timer periódico configurable y verificación de salud del
  backend; `ApiClient` admite inyección de `Dio` y nuevos métodos de kardex.
- `DOCUMENTACION-BALANSOFT-WS.md` movida a `docs/legacy/` con header
  "NO AUTORITATIVO" (M2, T3.2).

### Corregido

- Comparación de conectividad en `WeighingRepository._isConnected` (operaba
  sobre `List<ConnectivityResult>` con `!=`).

### Pendientes futuros

- B7 · HAL de balanza (peso por API; integración futura vía estación).
- B8 · Estabilidad de pesada 3 s y conversión KG/LBS activas.

---

## [v1.0.0] — 2026-09-08

### Añadido

- Backend FastAPI multi-empresa: auth JWT (BCrypt), catálogos (flota/inventario/
  directorio), pesaje con reglas MODEL (estados, cálculos, kardex 10/60),
  sincronización offline, reportes, exportación a Excel, tickets PDF,
  auditoría en `logs_sistema` e integración de licencias Ed25519.
- Frontend Flutter (BLoC, offline-first con `sqflite`): login/registro,
  dashboard, pesaje, catálogos, reportes, tema persistente.