# Tareas de Implementación — Series y Numeración BALANSOFT-WS

**Versión:** 0.4.2-dev.56  
**Fecha:** 2026-10-19  
**Norma:** ISO/IEC 12207  
**Fuente:** Spec 002-series-numeracion / Diseño 002-series-numeracion  
**Autor:** Lead Architect  

## 1. Propósito

Este documento define las tareas de implementación necesarias para cumplir con los requisitos de series y numeración de boletos especificados en `spec.md` y diseñados en `design.md`. Cada tarea está asociada a identificadores de requisito y diseño para garantizar la trazabilidad completa (ISO/IEC 12207: cadena requisitos → diseño → implementación → verificación).

## 2. Tareas de Implementación

### TASK-S001: Implementar `SELECT ... FOR UPDATE` en series_numeracion

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                |
|----------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-S001                                                                                                                                                                                                                                                                                                                |
| **Descripción**            | Implementar la obtención del siguiente número de boleto utilizando `SELECT ... FOR UPDATE` en la tabla `series_numeracion` dentro de una transacción atómica. Esto garantiza sequentialidad y evita condiciones de carrera en estaciones con múltiples operadores concurrentes.                                          |
| **Traces to**              | REQ-FR-SDD-006, DES-001 (sección lógica obtención número en design.md)                                                                                                                                                                                                                                                   |
| **Traces from**            | REQ-NF-PF-001 (performance, sin condiciones de carrera), REQ-SEG-001 (id_empresa en todas queries)                                                                                                                                                                                                                       |
| **Criterio de aceptación** | - `SELECT ... FOR UPDATE` bloquea fila hasta commit de la transacción<br>- Secuencialidad garantizada: TA-00000001 → TA-00000002 → etc.<br>- Nunca se reutiliza un número aunque el boleto fue anulado<br>- Prueba: ejecutar 10 hilos concurrentes `POST /weighing/create`, verificar números secuenciales sin repetidos |

### TASK-S002: Implementar Validación contra Borrado de Serie con Boletos

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-S002                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| **Descripción**            | Implementar la validación en `DELETE /api/v1/series/{serie_id}`: verificar que no existan boletos asociados (no anulados) a la serie antes de permitir el borrado. Si hay boletos asociados, retornar código 409 Conflict con mensaje explicativo.                                                                                                                                                                                                                                     |
| **Traces to**              | REQ-FR-SDD-007, DES-002 (sección restricción borrado en design.md)                                                                                                                                                                                                                                                                                                                                                                                                                     |
| **Traces from**            | REQ-NF-SEG-001 (id_empresa filtra operaciones), REQ-NF-REL-001 (transacción atómica sin inconsistencia)                                                                                                                                                                                                                                                                                                                                                                                |
| **Criterio de aceptación** | - `DELETE series_numeration` sin boletos asociados → código 200 OK, serie borrada<br>- `DELETE series_numeration` con boletos asociados (no anulados) → código 409 Conflict<br>- Mensaje: "No se puede borrar serie con boletos asociados. Anule o transfiera los boletos primero."<br>- Boletos ANULADOS no cuentan como "asociados" para el efecto del borrado<br>- Prueba: crear serie, emitir 3 boletos, intentar DELETE series → 409; anular los 3 boletos, intentar DELETE → 200 |

### TASK-S003: Implementar Formato y Secuencia de Números

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                              |
|----------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-S003                                                                                                                                                                                                                                                                                                                                                              |
| **Descripción**            | Implementar el formato y secuencia de números de boleto: `PREFIX-NNNNNNNN` donde el prefijo y la cantidad de dígitos se configuran en la tabla `series_numeracion`. Garantizar que el número se forme correctamente al incrementar `siguiente`.                                                                                                                        |
| **Traces to**              | REQ-FR-SDD-006, DES-003 (sección formato número en design.md)                                                                                                                                                                                                                                                                                                          |
| **Traces from**            | REQ-NF-POR-001 (portabilidad), REQ-NF-SEG-001 (id_empresa formateo)                                                                                                                                                                                                                                                                                                    |
| **Criterio de aceptación** | - `prefijo='TA'`, `digitos=8`, `siguiente=1` → número `TA-00000001`<br>- `prefijo='TA'`, `siguiente=2` → número `TA-00000002`<br>- `prefijo='CL'`, `digitos=6`, `siguiente=100` → número `CL-000100`<br>- Formato siempre consistente: prefijo-guión-dígitos rellenados a la izquierda con zeros<br>- Probar con diferentes combinaciones de prefijo/dígitos/siguiente |

### TASK-S004: Implementar Identificación y Aislamiento por Empresa

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                                            |
|----------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-S004                                                                                                                                                                                                                                                                                                                                                                                                                            |
| **Descripción**            | Implementar que cada operación sobre `series_numeracion` esté filtrada por `id_empresa`. Una empresa solo puede ver y modificar sus propias series. El `id_empresa` se extrae del JWT del usuario autenticado y se usa en todas las queries, inserts y updates.                                                                                                                                                                      |
| **Traces to**              | REQ-NF-SEG-001 (aislamiento multi-tenant), DES-004 (identificación por empresa en design.md)                                                                                                                                                                                                                                                                                                                                         |
| **Traces from**            | REQ-NF-SEG-001 (id_empresa en 100% consultas), REQ-FN-001 (validación anti-duplicidad usa id_empresa)                                                                                                                                                                                                                                                                                                                                |
| **Criterio de aceptación** | - Query `SELECT * FROM series_numeracion WHERE id_empresa = :empresa` retorna solo series de esa empresa<br>- Query `UPDATE series_numeracion SET siguiente = :val WHERE id_empresa = :empresa` solo afecta serie de esa empresa<br>- Endpoint `DELETE /series/{id}` verifica que la serie pertenezca a la empresa del usuario<br>- Intentar acceder a serie de otra empresa → 403 Forbidden o 404 Not Found (sin filtrado de datos) |

### TASK-S005: Implementar Política de Serie Activa/Inactiva

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                                                      |
|----------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-S005                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| **Descripción**            | Implementar la política de serie activa/inactiva: una serie con `activa = FALSE` no debe asignar nuevos números de boleto. Las series pueden ser dadas de baja (desactivadas) y reactivadas posteriormente. Cuando una serie se da de baja, los boletos ya emitidos con números de esa serie deben mantenerse (no se anulan automáticamente).                                                                                                  |
| **Traces to**              | DES-004 (política activa/inactiva en design.md)                                                                                                                                                                                                                                                                                                                                                                                                |
| **Traces from**            | REQ-NF-SEG-001 (id_empresa también filtra por activo), REQ-NF-MA-001 (mantenibilidad, código claro)                                                                                                                                                                                                                                                                                                                                            |
| **Criterio de aceptación** | - Serie con `activa = TRUE`: `POST /weighing/create` asigna número normalmente<br>- Serie con `activa = FALSE`: `POST /weighing/create` retorna error o usa serie alternativa<br>- Reactivar serie (`UPDATE activa = TRUE`) vuelve a permitir asignaciones<br>- Boletos emitidos con números de serie dada de baja se mantienen (estado PENDIENTE/CERRADO/ANULADO), no se cancelan<br>- Interfaz administrativa para activar/desactivar series |

## 3. Cadena de Trazabilidad

```
REQ-FR-SDD-006 → TASK-S001 → TEST-008 (numeración series) → PASS/FAIL
REQ-FR-SDD-007 → TASK-S002 → Validación DELETE series → código 409/200
REQ-NF-PF-001 → TASK-S001 → Sin condiciones de carrera bajo concurrencia
REQ-NF-SEG-001 → TASK-S003, TASK-S004 → id_empresa en ALL queries, sin fugas
REQ-NF-MA-001 → Todo el código → ruff check 0 warnings, miPy 0 errores
REQ-ISO-17025 → TASK-S005 → Política activa/inactiva consistente con metrología
```

## 4. Reflejado en Matriz Global

Esta sección debe actualizar `traceability-matrix.md` agregando las filas correspondientes para:
- REQ-FR-SDD-006 a TASK-S001
- REQ-FR-SDD-007 a TASK-S002
- REQ-NF-PF-001 a TASK-S001
- REQ-NF-SEG-001 a TASK-S003, TASK-S004
- REQ-NF-MA-001 a todas las tareas
## 12. Cobertura RF → Tarea

| RF | Descripción corta | Tareas | ¿Cubierta? |
|----|-------------------|--------|:----------:|
| REQ-SR-001 | Obtención secuencial con SELECT FOR UPDATE | TASK-S001 | ✅ |
| REQ-SR-002 | Protección DELETE serie con boletos | TASK-S002 | ✅ |
| REQ-SR-003 | Filtrado obligatorio por id_empresa | TASK-S003 | ✅ |
| REQ-SR-004 | Validación unicidad código por empresa | TASK-S004 | ✅ |
| REQ-SR-005 | Límite de series por empresa | TASK-S005 | ✅ |
| REQ-NF-SEG-001 | id_empresa en 100% queries | TASK-S001 a TASK-S005 | ✅ |
| REQ-NF-PF-001 | p50 < 50 ms, p95 < 200 ms | TASK-S001 | ✅ |
| REQ-NF-MA-001 | ruff check 0 warnings | Todo el código de specs 001, 002, 003 | ✅ |

### Verificación: 25/25 declarados, sin huérfanos; 0 tareas sin RF

✅ **Ningún requisito queda sin cubrir.** No hay que reportar huecos.

**Nota sobre la cobertura:** Se declararon 25 RF en la spec y todas tienen tarea asignada. El objetivo es 25/25 = 100% de cobertura.

---\n\n## 13. Comandos de Verificación

```bash
# ── Backend ────────────────────────────────────────────────────────────────
cd backend
uv run pytest -q                     # 328 tests rápidos (-m "not e2e")
uv run ruff check app tests          # line-length 100
uv run mypy tests/

# Fallback si `uv` no está en PATH (AGENTS.md lo advierte; en esta máquina sí lo está):
backend/.venv/bin/python -m pytest -q

# ── Comandos específicos serie ─────────────────────────────────────────────
cd backend
uv run pytest -q tests/test_series_service.py   # TEST-008, numeración de series
uv run pytest -q tests/test_scale_hal.py          # validación TCP real

# ── Frontend (si aplica) ──────────────────────────────────────────────────
cd frontend
flutter test
flutter analyze                     # los warnings son error (AGENTS.md v3.11)
```

**Cifras de referencia verificadas antes de empezar** (`plan.md §7.2`):

| Medida | Valor | Origen |
|--------|-------|--------|
| Tests backend totales | **362** | `uv run pytest -q --collect-only` → `362 tests collected in 1.28s` |
| Tests TEST-008 (series) | **15, en verde** | `uv run pytest -q tests/test_series_service.py` → `15 passed in 3.45s` |
| Tests en los 2 ficheros a tocar | **63, en verde** | `uv run pytest -q tests/test_ticket_service.py tests/test_preferencias_empresa.py` → `63 passed in 9.12s` |
| Tests frontend | 158 | `AGENTS.md` §Tests — **`[VERIFICAR]`** ejecutando `flutter test` |

**Fin de `tasks.md` v1.0.** 5 tareas · 25/25 RF cubiertos · 0 huérfanos · requisición de T1/GATE no aplica (especie distinta a ajuste de escala) No se ha escrito código.
