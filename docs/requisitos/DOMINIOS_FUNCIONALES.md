# Dominios Funcionales Detectados — BALANSOFT-WS

Fecha: 2026-10-26  
Fuente: Análisis de estructura de código, AGENTS.md, MANEJO_DB.md, NAV.md, MODELO_ESTANDAR.md

---

## 16 Dominios Funcionales Identificados

| Código            | Dominio                      | Descripción                                                                                                           | Módulos/Carpetas Clave                                                                                                                                                   |
|-------------------|------------------------------|-----------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **AUTH**          | Autenticación y Autorización | Login local/central, JWT, roles, matriz de permisos 18×3, refresh token, reset password                               | `app/api/v1/endpoints/auth.py`, `app/core/seguridad_matrix.py`, `app/core/security.py`, `frontend/lib/bloc/auth_bloc.dart`                                               |
| **WEIGHING**      | Pesaje (Core)                | Entrada/salida, boletos (PENDIENTE→CERRADO/MODIFICADO→ANULADO), captura peso báscula/manual, ticket, serie numeración | `app/api/v1/endpoints/pesajes.py`, `app/services/weighing_service.py`, `app/services/ticket_service.py`, `frontend/lib/presentation/screens/weighing/`                   |
| **CATALOG**       | Catálogos Maestros           | Terceros, productos, almacenes, transportes, vehículos, remolques, conductores, conceptos inventario                  | `app/api/v1/endpoints/catalogos.py`, `app/models/__init__.py` (Tercero, Producto, Almacen, etc.), `frontend/lib/presentation/screens/catalogos/`                         |
| **KARDEX**        | Kardex e Inventario          | Movimientos ID 10 (INGRESO +) / 60 (DESPACHO -), ajustes, conceptos, contra-asientos al anular                        | `app/services/kardex_service.py`, `app/models/__init__.py` (Kardex), `app/api/v1/endpoints/kardex.py`                                                                    |
| **SYNC**          | Sincronización Offline-First | Push/pull, cola idempotente, conflicto resolution, sync_logs, estado sincronización                                   | `app/services/sync_service.py`, `app/api/v1/endpoints/sync.py`, `frontend/lib/data/repositories/sync_repository.dart`                                                    |
| **LICENSE**       | Licencia y License Manager   | Validación Ed25519, LM (token, validate, activate, check), snapshot `/auth/license`, tiers, features                  | `app/services/license_client.py`, `app/api/v1/endpoints/auth.py` (license), `app/core/license_client.py`, `backend/scripts/lm_stub.py`                                   |
| **SESSIONS**      | Gestión de Sesiones          | Límite por tier (DEMO=3, resto=LM), contador, bloqueo, expiración, `limite_sesiones_por_tier()`                       | `app/services/llave_activacion_service.py`, `app/api/v1/endpoints/auth.py`, `frontend/lib/bloc/session_bloc.dart`                                                        |
| **SEMAFORO**      | Semáforo de Pesaje           | Torre 3 luces + zumbador, decisión backend (función pura), vigilante 0.5s, HAL HTTP/Serial                            | `app/core/semaforo_hal.py`, `app/services/semaforo_service.py`, `app/api/v1/endpoints/semaforos.py`, `frontend/lib/presentation/screens/dispositivos/semaforos_tab.dart` |
| **DEVICES**       | Dispositivos de Campo        | Básculas, Indicadores, Semáforos, Cámaras, Impresoras — vistas independientes con filtros propios                     | `app/api/v1/endpoints/balanzas.py`, `indicadores.py`, `semaforos.py`, `camaras.py`, `frontend/lib/presentation/screens/dispositivos/`                                    |
| **REPORTS**       | Reportes y Exportación       | Diarios, mensuales, personalizados, Excel, PDF, presets de rango, `_enriquecer_pesajes_lista`                         | `app/services/report_service.py`, `app/api/v1/endpoints/reports.py`, `frontend/lib/presentation/screens/reports/`                                                        |
| **AUDIT**         | Auditoría                    | Tabla `auditoria` completa, filtros entidad/acción/fecha, roles ADMIN/AUDITOR, UI pestañas                            | `app/api/v1/endpoints/auditoria.py`, `app/models/__init__.py` (Auditoria), `frontend/lib/presentation/screens/auditoria/`                                                |
| **I18N**          | Internacionalización         | es/en/pt, 621 claves/idioma, backend `?idioma=`/`Accept-Language`, Flutter `translations.dart`                        | `app/core/i18n.py`, `frontend/lib/core/i18n/translations.dart`, `frontend/test/unit/i18n_test.dart`                                                                      |
| **OBSERVABILITY** | Observabilidad               | Prometheus metrics, Grafana dashboards, Alertmanager, logging rotado, rate limiting                                   | `app/core/monitoring.py`, `app/core/logging_config.py`, `app/core/rate_limit.py`, `backend/deploy/observability/`                                                        |
| **INSTALLER**     | Instalador y Onboarding      | Pasos 1–9, rol SERVIDOR/OPERADOR, llave activación paso 1c, `config.json`, WServer bootstrap                          | `BALANSOFT-INSTALLER/gui/steps/*.py`, `frontend/lib/core/config/station_config.dart`, `backend/wserver.py`                                                               |
| **WSERVER**       | WServer Runtime Local        | PyInstaller one-file, BD local, migraciones, `.env` desde plantilla, API 0.0.0.0:8000                                 | `backend/wserver.py`, `backend/WServer.spec`, `scripts/build_wserver.sh`, `frontend/lib/core/services/wserver_manager.dart`                                              |
| **PRINTING**      | Impresión de Tickets         | Térmica ESC/POS (80/58mm), Matricial ESC/P (LX-350/FX-890 formulario continuo), PDF ReportLab, spooler                | `app/services/ticket_service.py`, `app/api/v1/endpoints/exports.py`, `printer-specialist` skill, `frontend/lib/presentation/widgets/ticket_preview_dialog.dart`          |

---

## Sub-dominios / Módulos Transversales

| Código            | Nombre                                | Afecta a                               |
|-------------------|---------------------------------------|----------------------------------------|
| **MULTI_TENANCY** | Aislamiento multi-tenant estricto     | TODOS (query filter `id_empresa`)      |
| **OFFLINE_FIRST** | Arquitectura offline-first            | WEIGHING, CATALOG, SYNC, PRINTING      |
| **IMMUTABILITY**  | Inmutabilidad peso capturado          | WEIGHING, KARDEX, AUDIT                |
| **METROLOGY**     | Metrología legal (OIML R 76-1)        | WEIGHING, DEVICES (básculas), PRINTING |
| **HARDWARE_IO**   | I/O hardware (serial, TCP, Bluetooth) | DEVICES, SEMAFORO, PRINTING            |

---

## Mapeo a Documentación Vigente

| Doc                       | Dominios que cubre                                                                                        |
|---------------------------|-----------------------------------------------------------------------------------------------------------|
| `MANEJO_DB.md`            | ARQUITECTURA, AUTH, WEIGHING, CATALOG, KARDEX, SYNC, LICENSE, SESSIONS, INSTALLER, WSERVER, MULTI_TENANCY |
| `NAV.md`                  | UI navigation → todas las pantallas por dominio                                                           |
| `MODELO_ESTANDAR.md`      | WEIGHING, CATALOG, KARDEX, REPORTS, RB invariables                                                        |
| `SEMAFORO.md`             | SEMAFORO (ciclo, integración, API, HAL)                                                                   |
| `DISPOSITIVOS.md`         | DEVICES (básculas, indicadores, semáforos, cámaras, impresoras)                                           |
| `BALANZAS_SOPORTADAS.md`  | DEVICES (protocolos, marcas, configuración)                                                               |
| `I18N_Y_ONBOARDING.md`    | I18N, INSTALLER                                                                                           |
| `OBSERVABILIDAD.md`       | OBSERVABILITY                                                                                             |
| `USO-API.md`              | API contracts para AUTH, WEIGHING, CATALOG, SYNC, LICENSE, REPORTS, AUDIT                                 |
| `SESIONES.md`             | SESSIONS, LICENSE                                                                                         |
| `PLANES-PAGOS.md`         | LICENSE (tiers, features) — **CONTRADICCIÓN conocida**                                                    |
| `TERMINOS_CONDICIONES.md` | LICENSE (Básico/Premium gatea) — **CONTRADICCIÓN conocida**                                               |
| `AGENTS.md`               | Resumen operativo de todos                                                                                |
| `ACTUAR.md`               | Plan de acción / backlog                                                                                  |
| `CHANGELOG.md`            | Historial de cambios por versión                                                                          |

---

## Próximos Pasos (Fases 1–10)

1. **FASE 1**: Esquema BD (`balansoft-ws-local.sql`, `balansoft-ws-server.sql`, `migrations/`)
2. **FASE 2**: Modelos ORM (`app/models/`, `models_server.py`)
3. **FASE 3**: Esquemas Pydantic (`app/schemas/`)
4. **FASE 4**: Endpoints (`app/api/v1/endpoints/`)
5. **FASE 5**: Servicios (`app/services/`)
6. **FASE 6**: Core (`app/core/`)
7. **FASE 7**: Tests (`backend/tests/`, `frontend/test/`)
8. **FASE 8**: Frontend Flutter (`frontend/lib/`)
9. **FASE 9**: Instalador + WServer (`wserver.py`, `BALANSOFT-INSTALLER/`)
10. **FASE 10**: Consolidación + Matriz final + Reportes