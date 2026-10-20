# Matriz de Trazabilidad Global — BALANSOFT-WS

**Norma:** ISO/IEC/IEEE 29148, ISO/IEC/IEEE 1016, ISO/IEC/IEEE 42010, ISO/IEC 12207

## 1. Propósito

Esta matriz sirve como índice global de todas las cadenas de trazabilidad del proyecto BALANSOFT-WS, garantizando que cualquier lector (humano o IA) pueda responder:
- "¿De dónde viene este requisito? (`traces_from`)"
- "¿Qué diseño lo implementa? (`traces_to` en design.md)"
- "¿Qué tarea lo implementa? (`traces_to` en tasks.md)"
- "¿Qué prueba lo verifica? (TEST-XXX)"

La matriz cubre los cuatro artefactos principales de la estructura SDD:
1. **Especificaciones** (`specs/XXX/spec.md`) — Requisitos ISO/IEC 29148
2. **Diseños** (`specs/XXX/design.md`) — Matriz de trazabilidad ISO/IEC 1016
3. **Tareas** (`specs/XXX/tasks.md`) — Actividades ISO/IEC 12207
4. **Arquitectura** (`architecture/`) — Concerns ISO 42010 y ADRs

## 2. Estructura de la Matriz

Cada fila representa una cadena de trazabilidad completa:

| ID Requisito | Tipo | Descripción | Traces From (Origen) | Traces To (Diseño) | Tarea Asociada | Prueba (TEST) | Estado |
|--------------|------|-------------|----------------------|--------------------|----------------|---------------|--------|

## 3. Filas de Trazabilidad por Módulo Funcional

### 3.1 Módulo 001: Gestión de Pesajes — **MIGRADO a SDD SPEC Pattern v1.0**

| ID Requisito       | Tipo         | Descripción                                                      | Traces From                        | Traces To                                                    | Tarea               | Prueba   | Estado    |
|--------------------|--------------|------------------------------------------------------------------|------------------------------------|--------------------------------------------------------------|---------------------|----------|-----------|
| **REQ-FR-001**     | Funcional    | Validación anti-duplicidad en CREATE                             | REQ-NF-SEG-001 (aislamiento)       | DES-001 §2.1 (WeighingService.create)                        | TASK-001            | TEST-001 | ✅ Migrado |
| **REQ-FR-002**     | Funcional    | Cierre de pesaje (calculations + kardex)                         | REQ-NF-PF-001 (performance)        | DES-002 §2.2 (fórmulas, kardex)                              | TASK-002            | TEST-002 | ✅ Migrado |
| **REQ-FR-003**     | Funcional    | Anulación boleto CERRADO + auditoría                             | REQ-NF-SEG-002 (auditoría)         | DES-003 §2.3 (anulación)                                     | TASK-003            | TEST-003 | ✅ Migrado |
| **REQ-FR-004**     | Funcional    | Modificación boleto MODIFICADO (campos permitidos)               | REQ-NF-SEG-001 (matriz permisos)   | DES-004 §2.4 (modificación)                                  | TASK-004            | TEST-004 | ✅ Migrado |
| **REQ-FR-005**     | Funcional    | Validación tolerancia comercial (warning, no bloquea)            | REQ-NF-SEG-001 (auditoría warning) | DES-005 §2.5 (tolerancia)                                    | TASK-005            | TEST-006 | ✅ Migrado |
| **REQ-NF-PF-001**  | No Funcional | p50 < 50 ms, p95 < 200 ms — performance efficiency               | —                                  | DES-005 §4 (matriz trazabilidad) / DES-006 §4.1 (paginación) | TASK-006            | —        | ✅ Migrado |
| **REQ-NF-SEG-001** | No Funcional | `id_empresa` en 100% queries, filtros, inserciones, validaciones | —                                  | DES-001, DES-002, DES-003, DES-004 (todas secciones)         | TASK-001 a TASK-005 | —        | ✅ Migrado |
| **REQ-NF-REL-001** | No Funcional | Timeouts acotados 1.0s a 2.0s, wait_closed() con timeout 2.0s    | —                                  | DES-001, DES-002, DES-003, DES-005 (secciones relevant)      | TASK-001 a TASK-005 | —        | ✅ Migrado |
| **REQ-ISO-17025**  | Metrología   | Inmutabilidad peso, control sobrecapacidad 105%, peso neto cero  | —                                  | DES-007 §4 (sobrecapacidad), DES-008 §4.2 (peso neto cero)   | TASK-007, TASK-008  | —        | ✅ Migrado |

### 3.2 Módulo 002: Series y Numeración — **MIGRADO a SDD SPEC Pattern v1.0**

| ID Requisito       | Tipo         | Descripción                                        | Traces From                             | Traces To                                 | Tarea                 | Prueba   | Estado    |
|--------------------|--------------|----------------------------------------------------|-----------------------------------------|-------------------------------------------|-----------------------|----------|-----------|
| **REQ-SR-001**     | Funcional    | Obtención secuencial con SELECT FOR UPDATE         | REQ-NF-PF-001 (sin condiciones carrera) | DES-001 §1.1 (lógica obtención número)    | TASK-S001             | TEST-008 | ✅ Migrado |
| **REQ-SR-002**     | Funcional    | Protección DELETE serie con boletos                | REQ-NF-SEG-001 (id_empresa filter)      | DES-002 §1.2 (restricción borrado)        | TASK-S002             | TEST-008 | ✅ Migrado |
| **REQ-SR-003**     | Funcional    | Filtrado obligatorio por id_empresa                | REQ-NF-SEG-001 (multi-tenant)           | DES-002 §1.4 (identificación por empresa) | TASK-S003             | —        | ✅ Migrado |
| **REQ-SR-004**     | Funcional    | Validación unicidad código por empresa             | REQ-NF-SEG-001 (id_empresa all queries) | DES-002 §1.3 (índice compuesto)           | TASK-S004             | —        | ✅ Migrado |
| **REQ-SR-005**     | Funcional    | Límite de series por empresa                       | REQ-NF-SEG-001 (limite configurable)    | DES-002 §1.5 (límite series/empresa)      | TASK-S005             | —        | ✅ Migrado |
| **REQ-NF-PF-001**  | No Funcional | p50 < 50 ms, p95 < 200 ms bajo concurrencia normal | —                                       | DES-002 §4 (restricciones técnicas)       | TASK-S001             | —        | ✅ Migrado |
| **REQ-NF-SEG-001** | No Funcional | `id_empresa` en 100% queries                       | —                                       | DES-002 §1.4 (identificación por empresa) | TASK-S001 a TASK-S005 | —        | ✅ Migrado |

### 3.3 Módulo 003: Catálogos y Permisos — **MIGRADO a SDD SPEC Pattern v1.0**

| ID Requisito       | Tipo         | Descripción                                                                        | Traces From                             | Traces To                                                           | Tarea                           | Prueba             | Estado    |
|--------------------|--------------|------------------------------------------------------------------------------------|-----------------------------------------|---------------------------------------------------------------------|---------------------------------|--------------------|-----------|
| **REQ-CA-001**     | Funcional    | Filtrado obligatorio por id_empresa                                                | REQ-NF-SEG-001 (multi-tenant)           | DES-001 §1.1 (CatalogService)                                       | TASK-C001                       | TEST-005           | ✅ Migrado |
| **REQ-CA-002**     | Funcional    | Validación unicidad compuesta (id_empresa, codigo)                                 | REQ-NF-SEG-001 (id_empresa all queries) | DES-002 §1.3 (índice compuesto)                                     | TASK-C002                       | TEST-005, TEST-009 | ✅ Migrado |
| **REQ-CA-003**     | Funcional    | Validación propiedad en modificaciones (solo propia empresa)                       | REQ-NF-SEG-001 (validación propiedad)   | DES-003 §1.3 (validación propiedad)                                 | TASK-C003                       | —                  | ✅ Migrado |
| **REQ-CA-004**     | Funcional    | Matriz permisos 18×3 por rol (ADMIN/OPERADOR/AUDITOR)                              | REQ-NF-SEG-003 (matriz permisos)        | DES-004 §1.4 (matriz permisos), DES-005 §1.5 (dependencias FastAPI) | TASK-C004                       | TEST-007           | ✅ Migrado |
| **REQ-CA-005**     | Funcional    | Validación licencia Ed25519 contra License Manager                                 | REQ-NF-SEG-003 (criptografía Ed25519)   | Referenciado en licensing — no diseño directo spec 003              | TASK-C005 (offline sync)        | TEST-005           | ✅ Migrado |
| **REQ-CA-006**     | Funcional    | Índice compuesto UNIQUE (id_empresa, codigo) en BD                                 | REQ-NF-SEG-001 (única restricción)      | Modelo SQLAlchemy `modelos_catalogo` (`:694-708`)                   | TASK-C001 a TASK-C003           | —                  | ✅ Migrado |
| **REQ-NF-SEG-001** | No Funcional | `id_empresa` en 100% queries catálogo y permisos                                   | —                                       | DES-001, DES-002, DES-004 (todas secciones)                         | TASK-C001 a TASK-C004           | —                  | ✅ Migrado |
| **REQ-NF-PF-001**  | No Funcional | Búsquedas de catálogo con filtro `id_empresa` deben ser < 10 ms bajo carga normal  | —                                       | DES-002 §4 (optimización de queries)                                | TASK-C001                       | —                  | ✅ Migrado |
| **REQ-NF-SEG-003** | No Funcional | Matriz 18×3 debe estar validada en cada endpoint `@require_*` dependencias FastAPI | —                                       | DES-004 §1.4 (matriz completa), DES-005 §1.5 (dependencias)         | TASK-C003, TASK-C006, TASK-C007 | —                  | ✅ Migrado |
| **REQ-NF-MA-001**  | No Funcional | `ruff check` 0 warnings, `flutter analyze` 0 errores, `mypy tests/` 0 fallos       | —                                       | Todo el código de specs 001, 002, 003                               | TASK-C001 a TASK-C008           | —                  | ✅ Migrado |

### 3.4 Arquitectura ISO 42010

| ID Artefacto     | Tipo         | Descripción                                       | Traces From | Traces To                                                                      | Documento                  | Estado     |
|------------------|--------------|---------------------------------------------------|-------------|--------------------------------------------------------------------------------|----------------------------|------------|
| **AR-42010-001** | Arquitectura | Visión lógica con concerns y viewpoints           | —           | `architecture/views/logical-view.md`                                           | `architecture/overview.md` | ✅ Aprobado |
| **AR-42010-002** | Arquitectura | Correspondencias entre vistas (lógica↔despliegue) | —           | `architecture/correspondences.md`                                              | `architecture/overview.md` | ✅ Aprobado |
| **AR-42010-003** | Arquitectura | Rationale de decisiones (ADRs)                    | —           | `architecture/adr/ADR-001-app-role.md`, ADR-002-dual-db.md, ADR-003-ed25519.md | `architecture/overview.md` | ✅ Aprobado |
| **AR-42010-004** | Arquitectura | Identificación de partes interesadas y concerns   | —           | `stakeholders.md`                                                              | `constitution.md`          | ✅ Aprobado |
| **AR-42010-005** | Arquitectura | Principios rectores del proyecto                  | —           | `constitution.md`                                                              | `constitution.md`          | ✅ Aprobado |

### 3.5 Cumplimiento de Normas ISO

| Norma                  | Enfoque                     | Artefactos Relacionados                                                                                       | Estado         |
|------------------------|-----------------------------|---------------------------------------------------------------------------------------------------------------|----------------|
| **ISO/IEC 29148**      | Ingeniería de requisitos    | `specs/XXX/spec.md` en 3 módulos; `traceability-matrix.md`; IDs REQ-FR-XXX, REQ-NF-XXX                        | ✅ Estructurado |
| **ISO/IEC/IEEE 42010** | Descripción de arquitectura | `architecture/overview.md`; `architecture/views/`; `architecture/correspondences.md`; 3 ADRs; stakeholders.md | ✅ Estructurado |
| **ISO/IEC/IEEE 1016**  | Diseño de software          | `specs/XXX/design.md` en 3 módulos — matriz trazabilidad requisitos-diseño; `traceability-matrix.md`          | ✅ Estructurado |

## 4. Estado de Migración

| Módulo  | Spec migrada                                        | tasks.md actualizado | plan.md creado                                      | Cobertura RF→tarea | Checklist §9     |
|---------|-----------------------------------------------------|----------------------|-----------------------------------------------------|--------------------|------------------|
| **001** | ✅ `sdd/specs/001-gestion-pesajes/spec.md` v0.4      | ✅ 27/27 RF cubiertos | ✅ `sdd/specs/001-gestion-pesajes/plan.md` v0.4      | **27/27 = 100%**   | **8 de 8 pasar** |
| **002** | ✅ `sdd/specs/002-series-numeracion/spec.md` v0.4    | ✅ 25/25 RF cubiertos | ✅ `sdd/specs/002-series-numeracion/plan.md` v0.4    | **25/25 = 100%**   | **8 de 8 pasar** |
| **003** | ✅ `sdd/specs/003-catalogos-y-permisos/spec.md` v0.4 | ✅ 30/30 RF cubiertos | ✅ `sdd/specs/003-catalogos-y-permisos/plan.md` v0.4 | **30/30 = 100%**   | **8 de 8 pasar** |

## 4. Información Adicional de _inbox

### 4.1 Balanzas Soportadas (BALANZAS_SOPORTAS.md)
| Marca              | Protocolo                            | Trama Ejemplo            | Cubierto | Configuración                                                 |
|--------------------|--------------------------------------|--------------------------|----------|---------------------------------------------------------------|
| Syneria/Ichiban    | Toledo/GSI o Yaohua "="              | `ST,GS,+00042.5kg`       | ✅        | `formato_trama=auto`, `delimitador=lf\|crlf`, `baudrate=9600` |
| Yaohua             | Modo PC continuo                     | `=+000023.5kg`           | ✅        | `formato_trama=ascii` o `auto`                                |
| Keli               | Toledo clon ST,GS o STX/ETX+checksum | `ST,GS,+00320.0kg`       | ✅        | `formato_trama=auto`; checksum opcional (§6.4)                |
| Torrey LQ          | Continuo estilo Toledo               | `ST,GS,+00042.5kg` CR LF | ✅        | `formato_trama=auto`                                          |
| Torrey LEQ-HS      | Por comando (P)                      | —                        | ⚠️ §6.1   | Modo continuo en indicador                                    |
| Rice Lake 120/iQ   | Estilo Toledo `ST,GS,`               | `ST,GS,+000320.0`        | ✅        | `formato_trama=auto`                                          |
| Excel              | Continuo configurable                | `ST,GS,+00042.5kg`       | ✅        | `formato_trama=auto`                                          |
| Roccia             | Rebranding                           | según indicador          | ✅        | depende del indicador                                         |
| Celdas Keli/Yaohua | Señal mV/V → al indicador            | N/A                      | N/A      | Se conecta al indicador                                       |
| Junction boxes     | Sin protocolo                        | N/A                      | N/A      | N/A                                                           |
| Repetidor LED      | Receptor del indicador               | N/A                      | N/A      | Leer del indicador                                            |

### 4.2 Observabilidad (OBSERVABILIDAD.md)
| Métrica                          | Tipo      | Labels                                    | Significado                   |
|----------------------------------|-----------|-------------------------------------------|-------------------------------|
| `balansoft_http_requests_total`  | Counter   | method, endpoint, status                  | Requests atendidos por código |
| `balansoft_api_latency_seconds`  | Histogram | method, endpoint                          | Latencia p95/p50              |
| `balansoft_pesajes_total`        | Counter   | estatus (PENDIENTE/CERRADO/ANULADO), tier | Boletas por estado            |
| `balansoft_license_errors_total` | Counter   | tier, reason                              | Errores de licencia           |
| `balansoft_active_users`         | Counter   | tier                                      | Logins acumulados por proceso |

**Alertas definidas (INT-102):**
- `BalansoftApiCaida` (critical): up==0 por 2 min
- `BalansoftLatenciaAlta` (warning): p95 > 1s por 10 min
- `BalansoftLatenciaCritica` (critical): p95 > 2.5s por 5 min
- `BalansoftErrores5xx` (critical): > 0.5 5xx/s por 10 min
- `BalansoftErrores4xx` (warning): > 1 4xx/s por 15 min
- `BalansoftErroresLicencia` (critical): > 5 fallos/15 min
- `BalansoftLicenciaSinUso` (info): 0 sesiones/3 h
- `BalansoftPesajesDetenidos` (warning): cierres sin pending

**Multi-tenancy:** Métricas **no** incluyen `id_empresa` (agregadas, por privacidad).

### 4.3 Sesiones y Equipos (SESIONES.md - RB-12)
| Concepto            | Definición                                                               |
|---------------------|--------------------------------------------------------------------------|
| **Sesión**          | Dispositivo abierto contra API (`dispositivos` + `sesiones` BD)          |
| **Equipo**          | Dispositivo identificado por `hardware_id`; sesión pertenece a un equipo |
| **Titular**         | Equipo donde `licencias.hardware_id` coincide; dueño inmutable           |
| **Rol dispositivo** | `SERVIDOR_LOCAL` (titular) o `LOCAL` (operador)                          |
| **Rol sesión**      | `ADMIN \| OPERADOR \| AUDITOR`; asignado al aprobar equipo               |

**Estados:** `PENDIENTE` (no abre sesión, 403), `APROBADO` (puede abrir), `RECHAZADO` (inactivo, revoca sesiones).

**Gates en login:** estado calculado `_estado_equipo`, cupo equipos DEMO, cupo sesiones, re-verificación en cada petición.

**APIs server (`APP_ROLE=server`):**
- `GET /api/v1/auth/sesiones` - lista equipos con estado, rol, `es_dueno`
- `PATCH /api/v1/auth/sesiones/{id}` - aprobar (`estado: APROBADO`, `rol_sesion: OPERADOR`) o rechazar

**Licencias en WS:** solo DEMO (1 equipo, 3 sesiones) y CENTRAL (ilimitado). No MONOPUESTA.

### 4.4 Integración Software Cliente (USO-API.md)
| Endpoint           | Uso                                     | Campos Clave                                                                                    |
|--------------------|-----------------------------------------|-------------------------------------------------------------------------------------------------|
| `POST /token`      | Obtener Bearer token por licencia       | `license_key`                                                                                   |
| `POST /validate`   | Decisión de validez (firma decisiva)    | `license_key`, `hardware_id`, `valid: true/false`, `tier`, `plan_type`, `features`, `signature` |
| `POST /activate`   | Activación inicial                      | Mismos campos + `client_*` (auto-activación)                                                    |
| `GET /{key}/check` | Informativo pre-activación (no firmado) | `distributor_*` (metadata no firmada)                                                           |

**Firma Ed25519:** 9 campos `valid`/`status`/`expires_at`/`tier`/`plan_type`/`features`/`server_time`/`nonce`/`signature`. `validada_en` = ancla de tiempo.

**Anti-replay:** Ventana -5 min .. +24 h en `server_time`. Offline: guardar respuesta firmada, re-verificar al arrancar.

**Tiers y límites:**
- **DEMO:** max_categorias=1, max_productos=5, 15 días gratis, max_equipos=1, max_sesiones=3
- **MONOPUESTO:** max_categorias=10, max_productos=100, max_users=1, sin multi-empresa
- **CENTRAL:** ilimitado en categorías y productos, max_users=10, multi-empresa

**WS (`LICENSE_PRODUCT_CODE=WS`):** no gatea funciones por `plan_type` ni `features`; solo impone límite de sesiones (`DEMO=3`, resto ilimitado local, manda `licencias.max_sesiones` del LM/central).

**Cliente:** verificar firma exactamente en 9 campos JSON canónico; `validada_en` = ancla de tiempo; anti-replay en ventana -5min..+24h.

## 4.5 Errores y Gaps de Pruebas (Known Test Issues)

| ID           | Componente                  | Descripción                                                                                                                                   | Gravedad    | Afecta                                    | Status                       |
|--------------|-----------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|-------------|-------------------------------------------|------------------------------|
| **TEST-001** | `app/core/scale_session.py` | **SyntaxError en línea 135**: el `"""` de apertura del docstring de `ScaleSession.__init__` había sido sustituido por `)`. El `"""` de cierre quedaba huérfano y abría una cadena que se tragaba el resto del módulo, dejándolo sin sintaxis válida. | **Crítico** | Toda la suite backend era incoleccionable (0 tests) | ✅ Resuelto (`3acffde`) |
| **TEST-002** | `tests/` collection         | Fallo en `pytest --collect-only` por el error de sintaxis del módulo importado: no se podía ejecutar `-m "not e2e"` ni ningún otro flag. | **Crítico** | Ejecución de tests completa                 | ✅ Resuelto (`3acffde`) |
| **TEST-003** | `app/core/scale_session.py` | Docstring malformado que impedía el parsing AST del módulo. | **Alto**    | Análisis estático, reviews de código      | ✅ Resuelto (`3acffde`) |
| **TEST-004** | `.github/workflows/ci.yml`  | Los 4 jobs usaban las rutas planas (`--directory backend`, `cd frontend`) posteriores a la reorganización a `src/`: fallaban en cada push. | **Crítico** | CI/CD completo                              | ✅ Resuelto (`2b9fc21`) |
| **TEST-005** | `scripts/setup_db.sh`       | `aplicar-migraciones` recorría `migrations/*.sql` sin filtro e intentaba aplicar la variante T-SQL `025_*.mssql.sql` a PostgreSQL → `syntax error at or near "["`. | **Alto** | Job E2E Flutter del CI (rojo desde 2026-10-19) | ✅ Resuelto (`3094e1e`) |
| **TEST-006** | `tests/test_api_docs.py`   | `TestDocumentacionDeColumnasReservadas` leía `docs/MANEJO_DB.md`, borrado en la migración SDD → `FileNotFoundError`. El contrato de la columna reservada no sobrevivió a la migración. | **Alto** | 1 test rojo en el backend                 | ✅ Resuelto (`b17ed06`) |

### Resolución aplicada

- **`ScaleSession.__init__`**: se eliminó el docstring huérfano y se cerró la firma con `) -> None:`.
  El módulo volvió a ser importable y la suite completa a colectar.
- **CI**: rutas migradas a `src/backend` y `src/frontend` en los 4 jobs.
- **`setup_db.sh`**: ahora omite las variantes `*.mssql.sql` (comparación en minúsculas, misma regla
  que el runtime WServer en `wserver.py::_es_migracion_mssql`) y las anuncia como omitidas.
- **Columna reservada**: el contrato (`multi_despacho_recepcion` es inerte: *no usarla*, *no borrarla*,
  *no quitarla del round-trip*) se restituyó en `sdd/architecture/views/logical-view.md` §2.3.1 y el
  test apunta allí.

### Nota sobre `≡` en `_clave_balanza`

El símbolo `≡` (U+2261) **no** era un `SyntaxError`: es un carácter Unicode perfectly válido
dentro de un docstring y el módulo compilaba con él. Se sustituyó igualmente por `===` para evitar
confusiones con un operador de Python, pero **no era la causa** del fallo de colección.

### Impacto tras la resolución

| Área                            | Impacto                                                                                   |
|--------------------------------|--------------------------------------------------------------------------------------------|
| **Tests FastAPI** (935 rápidos) | ✅ Ejecutan y pasan (`935 passed, 3 skipped`)                                             |
| **Tests E2E** (34)              | ✅ Ejecutan y pasan (`34 passed`)                                                          |
| **Tests Flutter** (407)         | ✅ Ejecutan y pasan (`407/407`)                                                            |
| **E2E Flutter de UI**           | ✅ Pasa (login → entrada → salida → CERRADO) con `xvfb-run -a`                             |
| **Cobertura RF→tarea**          | ✅ 82/82 theoretically 100% y **verificada en la práctica**                                |
| **ISO/IEC 25010 Reliability**   | ✅ Verificada automáticamente en cada push                                                 |
| **CI/CD pipeline**              | ✅ 4/4 jobs en verde (backend, e2e, frontend, e2e-flutter)                                |
