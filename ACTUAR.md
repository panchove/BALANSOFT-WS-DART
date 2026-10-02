# ¿Qué queda por hacer en BALANSOFT-WS?

**Fecha**: 2026-10-01
**Base**: `IMPLEMENTADO.md` v2.0
**Estado tras la ejecución `/update-all`**: **343 tests backend (310 rápidos + 33 E2E) + 158 frontend** en verde; `ruff`, `mypy` y `flutter analyze` limpios.

---

## 0. Resumen de lo ejecutado (2026-10-01)

Cerrados en esta tanda: **D1, D2, D3, D4, D5 (documentado), D6, H1, H2, H5, H7, H8, H10, H11** y **H14** (Redoc corregido: venía deshabilitado en instalaciones; ahora activo y documentado) y **B-doc** (`multi_despacho_recepcion` documentada como reservada/inerte).

| Ítem | Qué se hizo | Dónde |
|------|-------------|-------|
| D1 | `dbVersion` 1 → 5 | `frontend/lib/core/constants/app_constants.dart` |
| D2 | `productCode` `BWS` → `WS` | `frontend/lib/core/config/license_config.dart` |
| D3 | Switch y "Sincronizar ahora" cableados al `SyncBloc` real (con `BlocListener` de resultado) | `settings_screen.dart`, `sync_bloc.dart`, `app_config.dart` |
| D4 | `GET /api/v1/auditoria` (usuario/email, IP, entidad, detalle, UTC) + pestaña "Registro" en la UI | `backend/app/api/v1/endpoints/auditoria.py`, `frontend/.../auditoria_screen.dart` |
| D5 | Limitación multi-worker documentada (Redis sigue pendiente) | `backend/app/core/rate_limit.py` |
| D6 | 22 → 24 tablas locales | `docs/MANEJO_DB.md` |
| H1 | CI con GitHub Actions: backend (ruff + mypy + pytest con PostgreSQL) y frontend (analyze + test) | `.github/workflows/ci.yml` |
| H5 | Logging estructurado JSON + rotación por tamaño | `backend/app/core/logging_config.py`, `app/main.py` |
| H7 | Configuración de logrotate | `backend/deploy/balansoft-ws.logrotate` |
| H8 | Fail-fast si `APP_ENV=production` con `DEBUG_MODE=true` o `SECRET_KEY` por defecto | `backend/app/core/config.py` |
| H10 | Compresión/redimensión de imágenes (1600 px, JPEG q80, EXIF) antes de guardarlas | `backend/app/core/image_compress.py`, `archivos.py` |
| H11 | Paginación y filtro por catálogo en `/catalogo/sync` (`limit`, `skip`, `catalogo`, `totales`, `truncado`) | `catalog_service.py`, `endpoints/catalogo.py` |
| H2 | Stub del LM firmante con Ed25519 + 34 tests E2E (contrato firmado, flujo de licencia y ciclo offline) + job `e2e` en CI | `backend/scripts/lm_stub.py`, `backend/tests/e2e/`, `.github/workflows/ci.yml` |
| H6 | Andamiaje de observabilidad sobre las métricas que ya existían: Prometheus (scrape), 8 reglas de alerta, Alertmanager y dashboard Grafana provisionado (7 paneles) | `backend/deploy/observability/`, `docs/OBSERVABILIDAD.md`, `backend/tests/test_monitoring.py` |
| — | **Bug real encontrado por el E2E**: `/sync/push` insertaba datetimes con offset en columnas naive (`DataError`, lote caído). Ahora normaliza a UTC naive | `backend/app/services/sync_service.py` |

**Sigue pendiente**: H3 (timer de backup del LM), H4 (certificados), H12 (auditoría de lecturas sensibles), H15 (manual de operador) y P1, P3-P8. **P2 está cerrada** (prueba de volumen de 50k boletos). De H6 queda solo la parte de infraestructura que no se puede cerrar desde el repo (canal de notificación, retención y TLS).

---

## Respuesta corta

El sistema está **funcionalmente completo**. No hay bugs bloqueantes. Lo que queda es:

| Categoría | Pendientes | Días |
|-----------|-----------|:----:|
| 🟢 **Deuda técnica** | 0 ítems (D1-D6 cerrados) | 0 |
| 🔴 **CI/CD + hardening** | 2 ítems (H3, H4) | ~3 |
| 🟠 **Optimización + UX** | 2 ítems (H12, H15) | ~2 |
| 🟡 **Validación con cliente** | 8 ítems (P1-P8) | ~10 |
| **TOTAL** | **13 ítems** | **~16 días** |

---

## 1. Deuda técnica (~4 días) — ✅ CERRADA

Estos son **inconsistencias detectadas en el código** que no rompen nada hoy pero pueden causar bugs sutiles.

| # | Qué | Dónde | Fix | Estado |
|---|-----|-------|-----|--------|
| **D1** | `AppConstants.dbVersion = 1` pero la BD real es `version: 5` | `frontend/lib/core/constants/app_constants.dart` vs `database_helper.dart` | Unificar a 5 | ✅ Hecho |
| **D2** | Frontend usa `productCode = 'BWS'`, backend usa `LICENSE_PRODUCT_CODE=WS` | `frontend/lib/core/config/license_config.dart` vs `backend/.env` | Unificar a `WS` | ✅ Hecho |
| **D3** | Ajustes → Sincronización: switch "cada 5 min" no funciona, "Sincronizar ahora" solo muestra snackbar | `frontend/lib/presentation/screens/settings/` | Conectar al `SyncBloc` real | ✅ Hecho |
| **D4** | UI de Auditoría solo muestra estado de pesajes, no la tabla `auditoria` completa | `frontend/lib/presentation/screens/auditoria/` | Agregar volcado de `auditoria` (usuario/IP/timestamp) | ✅ Hecho |
| **D5** | Rate limiting no se comparte entre los 4 workers de uvicorn | `backend/app/core/rate_limit.py` | Redis o documentar limitación | ✅ Documentado (Redis sigue pendiente) |
| **D6** | `docs/MANEJO_DB.md` dice 22 tablas locales, el esquema real tiene 24 | `docs/MANEJO_DB.md` | Actualizar a 24 | ✅ Hecho |

**Por qué primero**: son fixes rápidos (0.5-1 día cada uno) y evitan bugs difíciles de diagnosticar.

---

## 2. CI/CD + Hardening (~6 días)

Sin esto, **no puedes desplegar en producción seria**.

| # | Qué | Por qué | Estado |
|---|-----|---------|--------|
| **H1** | CI con GitHub Actions (pytest + flutter test + analyze) | Sin verificación automática en PRs | ✅ Hecho (`.github/workflows/ci.yml`) |
| **H2** | E2E en CI (backend sembrado + Flutter integration_test) | Los E2E existen pero no corren automáticamente | ✅ Hecho (stub LM Ed25519 + 34 tests E2E + job `e2e`) |
| **H2b** | E2E de Flutter en CI (`integration_test/`) | El flujo de UI no se prueba automáticamente | ✅ Hecho (`pesaje_flow_test.dart` + `e2e_flutter.sh` + job `e2e-flutter` con xvfb) |
| **H3** | Backup automático del LM (pg_dump + timer) | Pérdida de licencias/cuentas = desastre | ⏳ Infra |
| **H4** | Firma de código WServer (Windows/macOS) | Windows Defender puede bloquear el `.exe` | ⏳ Certificados |
| **H5** | Logging estructurado JSON + rotación | Difícil diagnosticar en producción | ✅ Hecho |
| **H6** | Prometheus + Grafana + Alertmanager | `/metrics` existe pero nadie lo visualiza | ✅ Andamiaje hecho (`backend/deploy/observability/`, dashboard, 8 alertas, `docs/OBSERVABILIDAD.md`). Pendiente de infra: canal de notificación, retención, TLS |
| **H7** | Rotación de logs (logrotate) | Disco se llena en prod | ✅ Hecho |
| **H8** | Validación `APP_ENV=production` en `config.py` | Si `DEBUG_MODE=true` en prod, filtra tokens de reset | ✅ Hecho |

---

## 3. Optimización + UX (~5 días)

| # | Qué | Impacto | Estado |
|---|-----|---------|--------|
| **H10** | Compresión de fotos antes de subir | Almacenamiento crece rápido | ✅ Hecho (Pillow, 1600 px, JPEG q80) |
| **H11** | Paginación en `catalogo/sync` | Lento con catálogos grandes | ✅ Hecho (`limit`/`skip`/`catalogo`) |
| **H12** | Auditoría de lecturas sensibles (opcional) | Trazabilidad de consultas | ⏳ Opcional |
| **H14** | Documentación de API para integradores (Redoc) | Operadores no técnicos no saben usar la API | ✅ Corregido (venía `false` en la plantilla → 404 en toda estación) |
| **H15** | Manual de operador (PDF/Markdown + screenshots) | Capacitación manual | ⏳ Producto final |

---

## 3.b Pruebas de volumen (P2) — ✅ CERRADA 2026-10-02

`seed_volumen.py` genera 50 000 boletos coherentes en `balansoft_ws_volumen`
(10 invariantes verificados) y `benchmark_volumen.py` mide 11 endpoints con
p50/p95/p99.

**Encontró un bug real de producción**: `/weighing/list` y `/weighing/pendientes`
enriquecían **fila por fila** (`_enriquecer_pesaje_ticket`, hasta 10 consultas por
registro → ~1 000 idas y vueltas por página de 100). Con 50k boletos ambos
endpoints rondaban los 450 ms p50. No era un problema de índices: el SQL era de
0,6 ms y el `COUNT` de 4,7 ms. Resuelto con `_enriquecer_pesajes_lista` (7
consultas por página, constante): **450 ms → 20 ms** y **462 ms → 13 ms**.

11/11 escenarios dentro de umbral. Backend 354 en verde (320 + 34 E2E), con 3
tests de regresión que fallan si alguien reintroduce el N+1. Análisis y evidencia:
`docs/evidencia/volumen-analisis.md`.

**P2b resultó falsado**: `multi_despacho_recepcion` es una columna inerte (0 apariciones en cualquier consulta). Marcar 10k boletos con el flag no movió los tiempos, así que la degradación temida no puede ocurrir: la feature no está implementada. **B-doc cerrado**: la columna queda como reservada en `MANEJO_DB.md` §6.3, sin tocar esquema ni sync (el round-trip se conserva a propósito: son 35 bytes/boleto y quitarlo arriesga perder un `true` existente).

**H14 corregido**: `.env.plantilla` traía `API_DOCS_ENABLED=false`, así que toda estación instalada daba 404 en `/docs` y `/redoc` mientras `/openapi.json` exponía las 82 rutas igual. Ahora la documentación va activa y la exposición se documenta como decisión consciente.

P2c (`benchmark_concurrencia.py`) sí midió el costo real de JWT + TCP contra un servidor de 1 worker como el de la estación: **~20 ms** de sobrecoste, y `/weighing/list` alcanza los 200 ms p95 con **10 operadores concurrentes**, con techo de ~40-45 req/s y sin 5xx hasta 50.

**No se creó la migración 021 de índices**: la hipótesis del plan inicial (falta
un índice compuesto por `id_empresa`) no se confirmó. Con un tenant no hay
colisión que filtrar y añadir índices solo encarece las escrituras de pesajes.

---

## 4. Validación con cliente (~10 días)

**Requiere hardware/dominio/cliente real**, no se puede hacer en dev.

| # | Qué | Requiere |
|---|-----|----------|
| **P1** | Probar con balanza física (Toledo/Rice Lake/Sartorius) | Hardware real |
| **P3** | HTTPS/TLS con nginx | Dominio + certificado |
| **P4** | Manuales de usuario con capturas | Producto final |
| **P5** | Proceso de soporte formal (SLA, escalación) | Proceso |
| **P6** | CI/CD completo | Pipeline |
| **P7** | Automatización de backups del LM | Infra |
| **P8** | Regenerar WServer + bundles Flutter/APK | Build |

---

## 5. ¿Qué NO queda por hacer?

Estas cosas **ya están hechas** (no las toques):

- ✅ Pesaje completo (4 estados, cálculos, kardex 10/60)
- ✅ Captura guiada cabina→remolque
- ✅ Conversión de unidades
- ✅ Tabla de tolerancia
- ✅ Búsqueda rápida con copia
- ✅ Protección de datos sin guardar
- ✅ HAL de balanza (serial/TCP)
- ✅ Peso en vivo
- ✅ Descubrimiento de dispositivos
- ✅ i18n es/en/pt (621 claves)
- ✅ Tickets PDF + TXT con presets
- ✅ Panel del proveedor
- ✅ Seguridad por categorías (matriz rol × módulo)
- ✅ Series de numeración
- ✅ Identidad local
- ✅ Asistente de instalación (SERVIDOR/TRABAJADOR)
- ✅ WServer (PyInstaller)
- ✅ Reportes avanzados (transportista, tercero, rango, comparativo)
- ✅ Ajustes de inventario
- ✅ Auditoría (backend + volcado en UI con usuario/IP/timestamp)
- ✅ Rate limiting (básico, documentado su límite por worker)
- ✅ Prometheus (`/metrics`)
- ✅ Compresión de imágenes (H10) y paginación de catálogos (H11)
- ✅ Logging JSON rotado (H5/H7) y validación de entorno prod (H8)
- ✅ CI en GitHub Actions (H1)
- ✅ 343 tests backend (310 rápidos + 33 E2E con stub del LM) + 158 frontend

---

## 6. Mi recomendación

**Orden sugerido** (tras la tanda del 2026-10-01):

```
1. ~~H2b~~ → hecho. 2. ~~H6~~ → hecho. 3. ~~P2~~ → hecho. Siguiente disponible: **H12** (auditoría de lecturas sensibles)
2. H3 (backups del LM)             → 1 día  → protege cuentas/licencias
3. H6 (Grafana) + H4 (firma)      → 2 días → producción seria
4. H15 (manual) + H12             → 2 días → operación y trazabilidad
5. Validación cliente (P1-P8)     → 10 días → requiere entorno real
```

**Si tienes un cliente esperando**: salta directo a P1-P3 (hardware, volumen, TLS) y deja H12/H15 para después.

**Si es producto interno**: H2b ya está cerrado; el ciclo de calidad en UI queda cubierto por el job `e2e-flutter`.

---

## 7. Preguntas para decidir

1. **¿Hay un cliente real esperando** o es producto en desarrollo?
2. **¿Tienes dominio + servidor** para TLS y despliegue real?
3. **¿Hay hardware de balanza** disponible para pruebas?
4. **¿Se puede montar un stub del LM** (servicio que firme licencias) para CI?

Si me dices cuál es tu prioridad, te genero el código concreto para esas tareas.