# Changelog — BALANSOFT-WS

Este proyecto **no es un repositorio Git** (carpeta compartida de VM), por lo que no
se aplican tags; la versión se documenta exclusivamente en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

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