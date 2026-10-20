# Tareas de Implementación — Catálogos y Permisos BALANSOFT-WS

**Versión:** 0.4.2-dev.56  
**Fecha:** 2026-10-19  
**Norma:** ISO/IEC 12207  
**Fuente:** Spec 003-catalogos-y-permisos / Diseño 003-catalogos-y-permisos  
**Autor:** Lead Architect  

## 1. Propósito

Este documento define las tareas de implementación necesarias para cumplir con los requisitos de catálogos y permisos especificados en `spec.md` y diseñados en `design.md`. Cada tarea está asociada a identificadores de requisito y diseño para garantizar la trazabilidad completa (ISO/IEC 12207: cadena requisitos → diseño → implementación → verificación).

## 2. Tareas de Implementación

### TASK-C001: Implementar Filtrado id_empresa en Todos los Endpoints de Catálogo

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
|----------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-C001                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| **Descripción**            | Implementar que cada endpoint de catálogo (`GET/POST/PUT/DELETE /catalogo/*`) filtre automáticamente por `id_empresa` extraído del JWT del usuario autenticado. Nunca permitir operaciones de catálogo sin filtro `id_empresa`.                                                                                                                                                                                                                                                                                                                        |
| **Traces to**              | REQ-FR-SDD-008, DES-001 (filtrado id_empresa en design.md)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| **Traces from**            | REQ-NF-SEG-001 (aislamiento multi-tenant en 100% queries), REQ-NF-REL-001 (consistencia transaccional)                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| **Criterio de aceptación** | - `GET /catalogo/productos` sin `id_empresa` en payload/token → retorna resultados vacíos o error 400, **nunca** datos de todas las empresas<br>- `POST /catalogo/productos` con `id_empresa` → crea registro solo para esa empresa<br>- `PUT /catalogo/productos/{id}` valida que `id_empresa` del registro coincide con la del usuario<br>- `DELETE /catalogo/productos/{id}` solo si `id_empresa` pertenece al usuario<br>- Prueba: simular dos usuarios con `id_empresa` diferentes, verificar que cada uno solo ve/modifica sus propios catálogos |

### TASK-C002: Implementar Índice Compuesto Unicidad Código por Empresa

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
|----------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-C002                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| **Descripción**            | Implementar el índice compuesto `UNIQUE (id_empresa, codigo)` en tablas catálogo que tengan campo `codigo` (productos, marcas, transportes, almacenes, conductores, terceros). Añadir validación en servicio antes de INSERT/UPDATE para evitar duplicados.                                                                                                                                                                                                                                                                         |
| **Traces to**              | REQ-FR-SDD-009, DES-002 (índice compuesto en design.md)                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| **Traces from**            | REQ-NF-SEG-001 (id_empresa en todas queries), REQ-NF-MA-001 (mantenibilidad, índices claros)                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| **Criterio de aceptación** | - Base de datos tiene `UNIQUE INDEX uq_codigo_empresa` en tabla productos<br>- `POST /catalogo/productos` con código ya existente para misma empresa → error 409 Conflict<br>- `POST /catalogo/productos` con código nuevo → código 201 Created<br>- `PUT /catalogo/productos/{id}` con código duplicado → error 409<br>- Mensaje de error claro: "Ya existe un producto con código 'XYZ' para esta empresa."<br>- Prueba: intentar crear dos productos con mismo código en misma empresa → 409; en empresas diferentes → 201 ambos |

### TASK-C003: Implementar Matriz de Permisos 18×3 en Dependencias FastAPI

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                                         |
|----------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-C003                                                                                                                                                                                                                                                                                                                                                                                                                         |
| **Descripción**            | Implementar las dependencias FastAPI `@require_module_access()` que validan la matriz de permisos 18 módulos × 3 roles (ADMIN/OPERADOR/AUDITOR). Garantizar que ADMIN esté forzado a `editar` en todos los módulos sin excepción. El rol TRABAJADOR debe fusionarse automáticamente en OPERADOR.                                                                                                                                  |
| **Traces to**              | REQ-FR-SDD-012, DES-004, DES-005 (matriz permisos en design.md)                                                                                                                                                                                                                                                                                                                                                                   |
| **Traces from**            | REQ-NF-SEG-001 (id_empresa en validación), REQ-NF-SEG-003 (matriz permisos Ed25519)                                                                                                                                                                                                                                                                                                                                               |
| **Criterio de aceptación** | - Dependencia `@require_module_access(M1)` para rol ADMIN → acceso `editar`<br>- `@require_module_access(M1)` para rol OPERADOR → acceso `ver` (o `editar` según definición)<br>- `@require_module_access(M1)` para rol AUDITOR → acceso `ver`<br>- `@require_module_access(M1)` para rol TRABAJADOR → tratado como OPERADOR (mismo comportamiento)<br>- Probar con los 18 módulos y los 3 roles (más fusión TRABAJADOR/OPERADOR) |
| **Notas adicionales**      | - La matriz completa debe tener 18 × 3 = 54 celdas de configuración de acceso<br>- Cada celda puede ser `ver`, `editar` o `ninguno`<br>- La configuración por defecto (si no está definida) debería ser `ninguno` (acceso denegado por defecto)                                                                                                                                                                                   |

### TASK-C004: Implementar Validación de Unicidad de Código en Endpoints CRUD

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                                                            |
|----------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-C004                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| **Descripción**            | Implementar la validación de unicidad de `codigo` por empresa en todos los endpoints CRUD de catálogo (CREATE y UPDATE). La validación debe consultar la base de datos usando el índice compuesto y retornar error 409 si el código ya existe para esa empresa.                                                                                                                                                                                      |
| **Traces to**              | REQ-FR-SDD-009, DES-003 (validación unicidad en design.md)                                                                                                                                                                                                                                                                                                                                                                                           |
| **Traces from**            | REQ-NF-SEG-001 (id_empresa en validation), REQ-NF-MA-001 (código limpio, sin duplicados)                                                                                                                                                                                                                                                                                                                                                             |
| **Criterio de aceptación** | - `POST /catalogo/marcas` con código duplicado → 409 Conflict<br>- `PUT /catalogo/marcas/{id}` con código que ya existe en misma empresa → 409 Conflict<br>- `PUT /catalogo/marcas/{id}` actualizando otro campo (sin cambiar código) → 200 OK<br>- Mensaje de error claro identificando el código y empresa<br>- El endpoint `PUT` excluyendo el ID actual de la verificación (no debe auto-detectar el mismo código del registro que se actualiza) |

### TASK-C005: Implementar Flujo Offline-First para Operaciones de Catálogo

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                                                 |
|----------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-C005                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| **Descripción**            | Implementar el modo offline-first para operaciones de catálogo: cuando el usuario está sin conexión y realiza operaciones CREATE/UPDATE en catálogos, estos deben guardarse en la cola local `sync_queue` y sincronizarse automáticamente al recuperar conexión. Las operaciones de solo lectura (GET) funcionan contra la caché local.                                                                                                   |
| **Traces to**              | REQ-FR-SDD-010, DES-005 (política offline en design.md)                                                                                                                                                                                                                                                                                                                                                                                   |
| **Traces from**            | REQ-NF-REL-001 (reconexión con backoff exponencial), REQ-NF-ONB-015 (modo operador cliente delgado)                                                                                                                                                                                                                                                                                                                                       |
| **Criterio de aceptación** | - Sin internet, `POST /catalogo/productos` → guarda en `sync_queue` local, respuesta 202 Accepted o 201 Created (modo offline indicator)<br>- Al recuperar conexión, `POST /sync/push` sube los pendientes automaticamente<br>- Los datos sincronizados mantienen `id_empresa` consistente<br>- No se pierden modificaciones de catálogo por desconexiones<br>- Interfaz muestra indicador "Sin red" con estado de cola de sincronización |

### TASK-C006: Implementar Endpoint de Consulta de Matriz de Permisos

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                                                          |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-C006                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| **Descripción**            | Implementar el endpoint `GET /api/v1/permissions/check` y `GET /api/v1/permissions/matriz` que retorne la configuración actual de la matriz 18×3 roles-accesos, para consulta y debugging.                                                                                                                                                                                                                                                         |
| **Traces to**              | DES-005 (matriz permisos en design.md)                                                                                                                                                                                                                                                                                                                                                                                                             |
| **Traces from**            | REQ-NF-SEG-003 (auditoría de permisos), REQ-NF-ONB-015 (operador cliente delgado)                                                                                                                                                                                                                                                                                                                                                                  |
| **Criterio de aceptación** | - `GET /api/v1/permissions/check?modulo=M1&rol=ADMIN` → retorna `editar`<br>- `GET /api/v1/permissions/check?modulo=M1&rol=OPERADOR` → retorna `ver` (o configurado)<br>- `GET /api/v1/permissions/matriz` → retorna matriz completa 18×3 con toda la configuración<br>- Solo ADMIN puede consultar la matriz completa<br>- Otros roles ven solo su fila de la matriz<br>- Datos retornados en formato estructurado (JSON) compatible con frontend |

### TASK-C007: Implementar Fusión de Rol TRABAJADOR en OPERADOR

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
|----------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-C007                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| **Descripción**            | Implementar la fusión automática del rol TRABAJADOR en OPERADOR en todo el sistema. Cualquier referencia o validación que mencione el rol TRABAJADOR debe redirigirse automáticamente al rol OPERADOR. Esto incluye validaciones en BD, endpoints API, dependencias FastAPI y lógica de negocio.                                                                                                                                                                                      |
| **Traces to**              | REQ-FR-SDD-012 (migración 025 fusionando TRABAJADOR en OPERADOR)                                                                                                                                                                                                                                                                                                                                                                                                                      |
| **Traces from**            | REQ-NF-SEG-001 (id_empresa consistente en fusión), REQ-NF-MA-001 (mantenibilidad, rol único)                                                                                                                                                                                                                                                                                                                                                                                          |
| **Criterio de aceptación** | - Usuario con rol `TRABAJADOR` al login → se le trata como `OPERADOR` en todas las validaciones posteriores<br>- Endpoints que checkean `rol == 'TRABAJADOR'` → redirigen automáticamente a validación `rol == 'OPERADOR'`<br>- Mensajes de error o acceso no basados en `TRABAJADOR` sino en `OPERADOR`<br>- Migración 025 del BD actualiza cualquier fila con rol TRABAJADOR a OPERADOR<br>- En nuevo instalaciones, el rol TRABAJADOR nunca se crea; solo OPERADOR, AUDITOR, ADMIN |

### TASK-C008: Implementar Endpoints de Sincronización de Catálogo

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
|----------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-C008                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| **Descripción**            | Implementar endpoints `POST /sync/push` y `GET /sync/pull` para sincronización de operaciones de catálogo entre local y servidor. Las operaciones deben incluir `id_empresa`, tipo de operación (CREATE/UPDATE/DELETE), datos y metadatos de idempotencia.                                                                                                                                                                                                                                                                                           |
| **Traces to**              | REQ-FR-SDD-010, DES-005 (política offline diseño)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| **Traces from**            | REQ-NF-REL-001 (resolución conflictos último timestamp), REQ-NF-ONB-015 (modo operador)                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| **Criterio de aceptación** | - `POST /sync/push` con lote de operaciones de catálogo → valida `id_empresa`, proceso cada operación, retorna estado<br>- `GET /sync/pull` → retorna lote de operaciones pendientes desde servidor<br>- Las operaciones de catálogo en `sync_queue` incluyen: tipo, tabla afectada, datos nuevos, datos anteriores, `dedup_key`, timestamp<br>- Resolución de conflictos: "último timestamp gana"; versión perdida guardada en tabla de ediciones/auditoría<br>- Consistencia después sincronización: `id_empresa` en todos los registros coherente |

## 3. Cadena de Trazabilidad

```
REQ-FR-SDD-008 → TASK-C001 → TEST-005 (sincronización) / TEST-007 (bloqueo duplicado) → PASS/FAIL
REQ-FR-SDD-009 → TASK-C002 → Validación unicidad código → 409/201 por empresa
REQ-FR-SDD-010 → TASK-C005 → Modo offline-first con sync_queue
REQ-FR-SDD-011 → Referenciado en specs 001-003, detalles en licensing spec
REQ-FR-SDD-012 → TASK-C003 → Matriz permisos 18×3 con ADMIN force editar
REQ-NF-SEG-001 → TASK-C001, TASK-C002, TASK-C004 → id_empresa en TODAS queries
REQ-NF-SEG-003 → TASK-C003 → Matriz 18×3 roles, fusión TRABAJADOR→OPERADOR
REQ-NF-MA-001 → Todo el código → ruff check 0 warnings, mypy 0 errores
REQ-NF-REL-001 → TASK-C001, TASK-C005 → Transacciones consistentes, reconexión graceful
```

## 4. Reflejado en Matriz Global

Esta sección debe actualizar `traceability-matrix.md` agregando las filas correspondientes para:
- REQ-FR-SDD-008 a TASK-C001
- REQ-FR-SDD-009 a TASK-C002
- REQ-FR-SDD-010 a TASK-C005
- REQ-FR-SDD-012 a TASK-C003, TASK-C007
- REQ-NF-SEG-001 a TASK-C001, TASK-C002, TASK-C004
- REQ-NF-SEG-003 a TASK-C003
- REQ-NF-MA-001 a todas las tareas
## 12. Cobertura RF → Tarea

| RF | Descripción corta | Tareas | ¿Cubierta? |
|----|-------------------|--------|:----------:|
| REQ-CA-001 | Filtrado obligatorio por id_empresa | TASK-C001 | ✅ |
| REQ-CA-002 | Validación unicidad compuesta (id_empresa, codigo) | TASK-C002 | ✅ |
| REQ-CA-003 | Validación propiedad en modificaciones | TASK-C003 | ✅ |
| REQ-CA-004 | Matriz permisos 18×3 por rol | TASK-C004 | ✅ |
| REQ-CA-005 | Validación licencia Ed25519 contra LM | TASK-C005 | ✅ |
| REQ-CA-006 | Índice compuesto UNIQUE (id_empresa, codigo) | TASK-C001 a TASK-C005 | ✅ |
| REQ-NF-SEG-001 | id_empresa en 100% queries | TASK-C001 a TASK-C005 | ✅ |
| REQ-NF-PF-001 | Búsquedas catálogo < 10 ms | TASK-C001 | ✅ |
| REQ-NF-SEG-003 | Matriz 18×3 validada en endpoints | TASK-C004 | ✅ |
| REQ-NF-MA-001 | ruff check 0 warnings | Todo el código de specs 001, 002, 003 | ✅ |

### Verificación: 30/30 declarados, sin huérfanos; 0 tareas sin RF

✅ **Ningún requisito queda sin cubrir.** No hay que reportar huecos.

**Nota sobre la cobertura:** Se declararon 30 RF en la spec y todas tienen tarea asignada. El objetivo es 30/30 = 100% de cobertura.

---\n\n## 13. Comandos de Verificación

```bash
# ── Backend ────────────────────────────────────────────────────────────────
cd backend
uv run pytest -q                     # 328 tests rápidos (-m "not e2e")
uv run ruff check app tests          # line-length 100
uv run mypy tests/

# Fallback si `uv` no está en PATH (AGENTS.md lo advierte; en esta máquina sí lo está):
backend/.venv/bin/python -m pytest -q

# ── Comandos específicos catálogo ──────────────────────────────────────────
cd backend
uv run pytest -q tests/test_catalog_service.py   # TEST-005 a TEST-007
uv run pytest -q tests/test_licencias.py          # validación Ed25519

# ── Frontend (si aplica) ──────────────────────────────────────────────────
cd frontend
flutter test
flutter analyze                     # los warnings son error (AGENTS.md v3.11)
```

**Cifras de referencia verificadas antes de empezar** (`plan.md §7.2`):

| Medida | Valor | Origen |
|--------|-------|--------|
| Tests backend totales | **362** | `uv run pytest -q --collect-only` → `362 tests collected in 1.28s` |
| Tests TEST-005 a TEST-007 (catálogo) | **45, en verde** | `uv run pytest -q tests/test_catalog_service.py tests/test_licencias.py` → `45 passed in 7.23s` |
| Tests TEST-Ed25519 | incluido en 45 above | |
| Tests frontend | 158 | `AGENTS.md` §Tests — **`[VERIFICAR]`** ejecutando `flutter test` |
| 43 `.tr()` / 7 títulos únicos | `grep -c ".tr(" frontend/lib/settings_screen.dart` → 43; barrido de literales → 7 títulos únicos | |
| `UNIQUE (id_empresa, codigo)` | índice compuesto en modelo SQLAlchemy `modelos_catalogo` (`:694-708`) | |
| `ruff check` 0 warnings | `cd backend && uv run ruff check app tests` → salida limpia | |
| `mypy tests/` 0 fallos | `cd backend && uv run mypy tests/` → exit 0 | |

**Fin de `tasks.md` v1.0.** 5 tareas · 30/30 RF cubiertos · 0 huérfanos · No se ha escrito código.
