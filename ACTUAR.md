# ¿Qué queda por hacer en BALANSOFT-WS?

**Fecha**: 2026-10-01
**Base**: `IMPLEMENTADO.md` v2.0
**Estado tras la ejecución `/update-all`**: **343 tests backend (310 rápidos + 33 E2E) + 158 frontend** en verde; `ruff`, `mypy` y `flutter analyze` limpios.

---

## 0. Resumen de lo ejecutado (2026-10-01)

Cerrados en esta tanda: **D1, D2, D3, D4, D5 (documentado), D6, H1, H2, H5, H7, H8, H10, H11** y **H14** (ya existía).

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
| H2 | Stub del LM firmante con Ed25519 + 33 tests E2E (contrato firmado, flujo de licencia y ciclo offline) + job `e2e` en CI | `backend/scripts/lm_stub.py`, `backend/tests/e2e/`, `.github/workflows/ci.yml` |
| — | **Bug real encontrado por el E2E**: `/sync/push` insertaba datetimes con offset en columnas naive (`DataError`, lote caído). Ahora normaliza a UTC naive | `backend/app/services/sync_service.py` |

**Sigue pendiente** (requiere entorno/cliente/infra): H3, H4, H6, H12, H15 y P1-P8. El E2E de Flutter (`integration_test/pesaje_flow_test.dart`) queda como fase 2 de H2: la parte backend ya corre en CI.

---

## Respuesta corta

El sistema está **funcionalmente completo**. No hay bugs bloqueantes. Lo que queda es:

| Categoría | Pendientes | Días |
|-----------|-----------|:----:|
| 🟢 **Deuda técnica** | 0 ítems (D1-D6 cerrados) | 0 |
| 🔴 **CI/CD + hardening** | 3 ítems (H3, H4, H6) | ~4 |
| 🟠 **Optimización + UX** | 2 ítems (H12, H15) | ~2 |
| 🟡 **Validación con cliente** | 8 ítems (P1-P8) | ~10 |
| **TOTAL** | **14 ítems** | **~17 días** |

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
| **H6** | Prometheus + Grafana + Alertmanager | `/metrics` existe pero nadie lo visualiza | ⏳ Infra |
| **H7** | Rotación de logs (logrotate) | Disco se llena en prod | ✅ Hecho |
| **H8** | Validación `APP_ENV=production` en `config.py` | Si `DEBUG_MODE=true` en prod, filtra tokens de reset | ✅ Hecho |

---

## 3. Optimización + UX (~5 días)

| # | Qué | Impacto | Estado |
|---|-----|---------|--------|
| **H10** | Compresión de fotos antes de subir | Almacenamiento crece rápido | ✅ Hecho (Pillow, 1600 px, JPEG q80) |
| **H11** | Paginación en `catalogo/sync` | Lento con catálogos grandes | ✅ Hecho (`limit`/`skip`/`catalogo`) |
| **H12** | Auditoría de lecturas sensibles (opcional) | Trazabilidad de consultas | ⏳ Opcional |
| **H14** | Documentación de API para integradores (Redoc) | Operadores no técnicos no saben usar la API | ✅ Ya existía |
| **H15** | Manual de operador (PDF/Markdown + screenshots) | Capacitación manual | ⏳ Producto final |

---

## 4. Validación con cliente (~10 días)

**Requiere hardware/dominio/cliente real**, no se puede hacer en dev.

| # | Qué | Requiere |
|---|-----|----------|
| **P1** | Probar con balanza física (Toledo/Rice Lake/Sartorius) | Hardware real |
| **P2** | Prueba de volumen (~50k boletos) | Semilla + entorno |
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
1. ~~H2b~~ → hecho. Siguiente disponible: H6 (Prometheus + Grafana) o H12
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