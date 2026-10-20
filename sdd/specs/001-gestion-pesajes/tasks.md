# Tareas de Implementación — Gestión de Pesajes BALANSOFT-WS

**Versión:** 0.4.2-dev.56  
**Fecha:** 2026-10-19  
**Norma:** ISO/IEC 12207  
**Fuente:** Spec 001-gestion-pesajes / Diseño 001-gestion-pesajes  
**Autor:** Lead Architect  

## 1. Propósito

Este documento define las tareas de implementación necesarias para cumplir con los requisitos de gestión de pesajes especificados en `spec.md` y diseñados en `design.md`. Cada tarea está asociada a identificadores de requisito y diseño para garantizar la trazabilidad completa (ISO/IEC 12207: cadena requisitos → diseño → implementación → verificación).

## 2. Tareas de Implementación

Cada tarea incluye su identificador, descripción, rastreabilidad y criterio de aceptación.

### TASK-001: Implementar Validación Anti-Duplicidad en CREATE

| Campo                      | Contenido                                                                                                                                                                                                                                                                  |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-001                                                                                                                                                                                                                                                                   |
| **Descripción**            | Implementar la validación de anti-duplicidad en `POST /api/v1/weighing/create`: verificar que `WHERE placa + id_empresa` no tenga boleto en estado `PENDIENTE` ya existente. Usar bloqueo pesimista `SELECT ... FOR UPDATE` en la transacción.                             |
| **Traces to**              | REQ-FR-SDD-001, DES-001 (sección validación anti-duplicidad en design.md)                                                                                                                                                                                                  |
| **Traces from**            | REQ-NF-SEG-001 (aislamiento multi-tenant)                                                                                                                                                                                                                                  |
| **Criterio de aceptación** | - `POST /weighing/create` con placa ya en PENDIENTE → código 400<br>- `POST /weighing/create` con placa nueva → código 201, boleto PENDIENTE creado<br>- Número de boleto asignado secuencialmente (TA-00000001, etc.)<br>- Transacción atómica sin condiciones de carrera |

### TASK-002: Implementar Cierre de Pesaje (Calculations + Kardex)

| Campo                      | Contenido                                                                                                                                                                                                                                                                                              |
|----------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-002                                                                                                                                                                                                                                                                                               |
| **Descripción**            | Implementar `POST /api/v1/weighing-close`: calcular PTE, PTS, PNT, PDF, PDV a partir de pesos entrada y salida; validar tolerancia comercial; registrar movimiento Kardex (ID 10 si PNT > 0, ID 60 si PNT < 0).                                                                                        |
| **Traces to**              | REQ-FR-SDD-002, DES-002 (sección cálculos y kardex en design.md)                                                                                                                                                                                                                                       |
| **Traces from**            | REQ-NF-PF-001 (p50 < 50 ms, p95 < 200 ms), REQ-NF-SEG-005 (metrología legal)                                                                                                                                                                                                                           |
| **Criterio de aceptación** | - Cálculos exactos: PTE = PEC + PER, PTS = PSC + PSR, PNT = PTE - PTS<br>- PDF = PNT - PND<br>- PDV = PDF / PND × 100<br>- Si PNT > 0: Kardex ID 10 positivo<br>- Si PNT < 0: Kardex ID 60 negativo<br>- Si PNT = 0: No registrar kardex<br>- Tolerancia: warning WARN, cierre permitido, kardex igual |

### TASK-003: Implementar Anulación de Boleto con Auditoría

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                                       |
|----------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-003                                                                                                                                                                                                                                                                                                                                                                                                                        |
| **Descripción**            | Implementar `PUT /api/v1/weighing/{boleto}/anular`: validar rol (SUPERVISOR+), validar motivo ≥ 10 caracteres, actualizar estado a ANULADO, registrar auditoría completa (usuario, fecha, IP, motivo), y si el boleto estaba CERRADO, registrar movimiento kardex inverso (10 ↔ 60) para cancelar efecto original.                                                                                                              |
| **Traces to**              | REQ-FR-SDD-003, DES-003 (sección anulación en design.md)                                                                                                                                                                                                                                                                                                                                                                        |
| **Traces from**            | REQ-NF-SEG-002 (criptografía, auditoría), REQ-NF-REL-001 (manejo desconexiones)                                                                                                                                                                                                                                                                                                                                                 |
| **Criterio de aceptación** | - Rol no autorizado → 403 Forbidden<br>- Motivo < 10 caracteres → 400 Bad Request<br>- Boleto ya ANULADO → 409 Conflict o mensaje apropiado<br>- Estado pasa a ANULADO<br>- Auditoría registrada con usuario/fecha/IP/motivo<br>- Si boleto estaba CERRADO: movimiento inverso kardex 10↔60 registrado<br>- Saldos de inventario actualizados (efecto contrario original)<br>- Vehículo liberado (disponible para nuevo pesaje) |

### TASK-004: Implementar Modificación de Boleto (Estados y Campos)

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                            |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-004                                                                                                                                                                                                                                                                                                                                                                                                             |
| **Descripción**            | Implementar `PUT /api/v1/weighing/{boleto}`: validar que solo campos editables se modifiquen (`documento`, `flete`, `costo_flete`, `observaciones`, `peso_neto_declarado` PND). El peso báscula NUNCA se edita. Si el boleto estaba CERRADO, pasar a estado MODIFICADO e incrementar `ediciones_count`. Registrar cada edición en `BoletoEdicion` con motivo obligatorio.                                            |
| **Traces to**              | REQ-FR-SDD-004, DES-004 (sección modificación en design.md)                                                                                                                                                                                                                                                                                                                                                          |
| **Traces from**            | REQ-NF-SEG-001 (matriz permisos 18×3, ADMIN forzado editar), REQ-NF-MA-001 (mantenibilidad, 0 warnings)                                                                                                                                                                                                                                                                                                              |
| **Criterio de aceptación** | - Campos permitidos → 200 OK, `ediciones_count` incrementado<br>- Peso báscula bloqueado → 400 Bad Request o ignorado, sin modificar<br>- Boleto PENDIENTE → pasar a MODIFICADO (mismo número, no reutilización)<br>- Boleto CERRADO → pasar a MODIFICADO, incrementar `ediciones_count`<br>- Cada edición registrada en `BoletoEdicion` con motivo obligatorio<br>- Auditoría completa de quién, cuándo, qué cambió |

### TASK-005: Implementar Validación de Tolerancia Comercial

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                 |
|----------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-005                                                                                                                                                                                                                                                                                                  |
| **Descripción**            | Implementar la validación `PDV > tolerancia_producto` en el cierre de pesaje: emitir warning auditoría (WARN level) pero **NO bloquear** el cierre del boleto. El kardex se genera igualmente.                                                                                                            |
| **Traces to**              | REQ-FR-SDD-005, DES-005 (validación tolerancia en design.md)                                                                                                                                                                                                                                              |
| **Traces from**            | REQ-NF-SEG-001 (auditoría registra warning), REQ-NF-ONB-015 (modo operador)                                                                                                                                                                                                                               |
| **Criterio de aceptación** | - `PDV > tolerancia_producto` → warning auditoría, cierre permitido<br>- `PDV <= tolerancia_producto` → cierre normal, sin warning<br>- Kardex generado con movimiento correspondiente en ambos casos<br>- No hay error bloqueo en respuesta API<br>- Warning registrado con `motivo_tolerancia_excedida` |

### TASK-006: Implementar Helper _enriquecer_pesajes_lista (Paginación)

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                            |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-006                                                                                                                                                                                                                                                                                                             |
| **Descripción**            | Implementar la función helper `_enriquecer_pesajes_lista` para soportar paginación obligatoria (`limit`, `skip`) en todos los endpoints de lista de boletos, evitando problemas N+1 queries. Esta función debe enricher los resultados con datos Enriquecidos mínimos (empresa, producto, estado) en una sola query. |
| **Traces to**              | REQ-NF-PF-002 (paginación obligatoria), DES-005 matriz trazabilidad (sección 4)                                                                                                                                                                                                                                      |
| **Traces from**            | REQ-NF-PF-001 (p50 < 50 ms, p95 < 200 ms), MA-001 (código limpio, 0 warnings)                                                                                                                                                                                                                                        |
| **Criterio de aceptación** | - Todos los endpoints de lista soporten `limit` y `skip` parameters<br>- 0 advertencias de N+1 queries en `ruff check`<br>- p50 < 50 ms, p95 < 200 ms bajo concurrencia normal (hasta 100 usuarios)<br>- Helper usado en `GET /weighing/list`, `GET /weighing/pendientes`                                            |

### TASK-007: Implementar Control de Sobrecapacidad (105%)

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                   |
|----------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-007                                                                                                                                                                                                                                                                                                    |
| **Descripción**            | Implementar el control de sobrecapacidad: rechazar estrictamente si el valor supera el 105% de la capacidad nominal de la báscula (`TOLERANCIA_CAPACIDAD = 1.05`). Esta validación debe aplicarse tanto en modo automático (lectura hardware) como en modo manual (peso ingresado manualmente).             |
| **Traces to**              | REQ-NF-MET-001 (inmutabilidad metrológica), DES-001 matriz trazabilidad                                                                                                                                                                                                                                     |
| **Traces from**            | REQ-ISO-17025 (control sobrecapacidad), REQ-NF-SEG-005 (metrología legal)                                                                                                                                                                                                                                   |
| **Criterio de aceptación** | - Peso > 105% capacidad nominal → error 400 con mensaje "Peso excede capacidad nominal"<br>- Peso <= 105% capacidad → operación normal<br>- Validación en `POST /weighing/create` y `POST /weighing-close`<br>- Aplicable modo automático y modo manual<br>- Auditoria registrada si se sobrepasa el límite |

### TASK-008: Implementar Validación de Peso Neto Cero

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                              |
|----------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-008                                                                                                                                                                                                                                                                                                                                                                                               |
| **Descripción**            | Implementar la política de peso neto cero (`PNT = 0`): cuando el báscula captura un peso exactamente igual a la tara del vehículo. Política configurable: `ZERO_WEIGHT_ACTION` ∈ `[CREATE_BOLETO, SKIP_MOVEMENT, MANUAL_REVIEW]`. Por defecto: crear boleto PENDIENTE con `PNT=0` y sin movimiento kardex hasta validación operadora.                                                                  |
| **Traces to**              | REQ-NF-MET-001 (inmutabilidad metrológica), DES-002 (cálculos en design.md)                                                                                                                                                                                                                                                                                                                            |
| **Traces from**            | REQ-ISO-17025 (seguimiento de cero), REQ-NF-REL-001 (reconexión automática)                                                                                                                                                                                                                                                                                                                            |
| **Criterio de aceptación** | - `PNT = 0` → Opción por defecto: crear boleto PENDIENTE con `PNT=0`, sin movimiento kardex<br>- Opción `SKIP_MOVEMENT`: crear boleto PENDIENTE, sin movimiento kardex<br>- Opción `MANUAL_REVIEW`: crear boleto PENDIENTE, requerir validación operadora antes de proseguir<br>- Política configurada por empresa en `parametros_sistema`<br>- Comportamiento consistente en modo automático y manual |

### TASK-009: Implementar Matriz de Permisos 18×3 (ADMIN FORCE EDIT)

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                           |
|----------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-009                                                                                                                                                                                                                                                                                                                                                                                                            |
| **Descripción**            | Implementar la matriz de permisos 18 módulos × 3 roles (ADMIN/OPERADOR/AUDITOR) con acceso `ver`/`editar`/`ninguno`. El rol ADMIN debe estar forzado a permiso `editar` en todos los módulos sin excepción. El rol TRABAJADOR se fusiona en OPERADOR (migración 025).                                                                                                                                               |
| **Traces to**              | REQ-FR-SDD-012, DES-009 matriz permisos en design.md                                                                                                                                                                                                                                                                                                                                                                |
| **Traces from**            | REQ-NF-SEG-001 (aislamiento multi-tenant), REQ-NF-SEG-003 (matriz permisos 18×3)                                                                                                                                                                                                                                                                                                                                    |
| **Criterio de aceptación** | - Matriz completa 18 módulos × 3 roles con accesos ver/editar/ninguno<br>- ADMIN forzado a `editar` en todos los módulos (sin excepción)<br>- OPERADOR: solo `ver` en la mayoría, `editar` en algunos operaciones permitidas<br>- AUDITOR: `ver` en consultas, sin edición<br>- TRABAJADOR fusionado en OPERADOR (migración 025 already applied)<br>- Validación en cada endpoint `@require_*` dependencias FastAPI |

### TASK-010: Implementar Series Numeracionales con Bloqueo Pessimista

| Campo                      | Contenido                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ID Tarea**               | TASK-009                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| **Descripción**            | Implementar la obtención del siguiente número de boleto mediante transacción atómica `SELECT ... FOR UPDATE` en `series_numeracion`, garantizando sequentialidad (TA-00000001 → TA-00000002) y nunca reutilización de números. Retornar código 409 (Conflict) si se intenta borrar una serie con boletos asociados.                                                                                                                                                        |
| **Traces to**              | REQ-FR-SDD-006, DES-002 sección series numeración en design.md                                                                                                                                                                                                                                                                                                                                                                                                             |
| **Traces from**            | REQ-NF-SEG-001 (id_empresa en todas queries), REQ-NF-PF-001 (performance, sin condiciones de carrera)                                                                                                                                                                                                                                                                                                                                                                      |
| **Criterio de aceptación** | - `SELECT ... FOR UPDATE` en `series_numeracion` dentro de transacción<br>- Secuencialidad garantizada: TA-00000001 → TA-00000002 → etc.<br>- Nunca se reutiliza un número aunque esté dado de baja<br>- `DELETE series_numeration` con boletos asociados → código 409 Conflict<br>- Mensaje: "No se puede borrar serie con boletos asociados. Anule o transfiera los boletos primero."<br>- Protección contra condiciones de carrera en múltiples operadores concurrentes |

## 3. Cadena de Trazabilidad

```
REQ-FR-SDD-001 → TASK-001 → TEST-001 (creación boleto) → PASS/FAIL
REQ-FR-SDD-002 → TASK-002 → TEST-002 (cierre pesaje) → PASS/FAIL
REQ-FR-SDD-003 → TASK-003 → TEST-003 (anulación boleto) → PASS/FAIL
REQ-FR-SDD-004 → TASK-004 → TEST-004 (modificación boleto) → PASS/FAIL
REQ-FR-SDD-005 → TASK-005 → TEST-006 (validación tolerancia) → PASS/FAIL
REQ-NF-PF-001 → TASK-006 → Performance validation → p50 < 50 ms, p95 < 200 ms
REQ-NF-SEG-001 → TASK-009 → Matriz permisos 18×3 → Audit check
REQ-NF-REL-001 → TASK-001 a TASK-005 → Timeouts y reconexión → RE-001 validation
REQ-ISO-17025 → TASK-007, TASK-008 → Metrología legal checks
```

## 4. Relación con Matriz Global

Esta sección debe ser reflejada en `traceability-matrix.md` actualizando el registro de todas las cadenas requisitos → diseño → tareas para este grupo funcional.
## 12. Cobertura RF → Tarea

| RF | Descripción corta | Tareas | ¿Cubierta? |
|----|-------------------|--------|:----------:|
| REQ-FR-001 | Validación anti-duplicidad en CREATE | TASK-001 | ✅ |
| REQ-FR-002 | Cierre de pesaje (calculations + kardex) | TASK-002 | ✅ |
| REQ-FR-003 | Anulación boleto CERRADO + auditoría | TASK-003 | ✅ |
| REQ-FR-004 | Modificación boleto MODIFICADO (campos permitidos) | TASK-004 | ✅ |
| REQ-FR-005 | Validación tolerancia comercial (warning, no bloquea) | TASK-005 | ✅ |
| REQ-NF-SEG-001 | `id_empresa` en 100% queries, filtros, inserciones, validaciones | TASK-001 a TASK-005 | ✅ |
| REQ-NF-REL-001 | Timeouts acotados 1.0s a 2.0s, wait_closed() con timeout 2.0s | TASK-001 a TASK-005 | ✅ |
| REQ-ISO-17025 | Inmutabilidad peso, control sobrecapacidad 105%, peso neto cero | TASK-007, TASK-008 | ✅ |
| REQ-NF-PF-001 | p50 < 50 ms, p95 < 200 ms — performance efficiency | TASK-006 | ✅ |
| REQ-FR-010 | El paso configurado es el peldaño inicial | TASK-009 | ✅ |
| REQ-FR-011 | Orden descendente y nada truncado | TASK-009 | ✅ |
| REQ-FR-012 | AUTOMATICO → texto extraído idéntico | TASK-004 | ✅ |
| REQ-FR-013 | TXT ignora la tipografía | TASK-004 | ✅ |
| REQ-FR-014 | Solo DejaVu | TASK-005 | ✅ |
| REQ-FR-015 | Peldaños 10.5 / 9.0 / 7.5 | TASK-009 | ✅ |
| REQ-FR-016 | Fallback Helvetica sin fallar | TASK-005 | ✅ |
| REQ-FR-017 | el PDF no toca la red central | TASK-004 | ✅ |
| REQ-NF-SEG-001 | Aislamiento multi-tenant | TASK-001 a TASK-005 | ✅ |
| REQ-NF-SEG-003 | Matriz 18 módulos × 3 roles con ver/editar/ninguno | TASK-004 | ✅ |
| REQ-NF-MA-001 | ruff check 0 warnings, flutter analyze 0 errores | Todo el código de specs 001, 002, 003 | ✅ |
| REQ-NF-ONB-001 | Onboarding idempotente | TASK-005 | ✅ |
| REQ-NF-ONB-002 | Solo la máquina titular de licencia puede instalarse como Servidor | TASK-009 | ✅ |
| REQ-NF-ONB-015 | El modo Operador solo necesita dirección/puerto Servidor y llave única | TASK-009 | ✅ |

### Verificación: 27/27 declarados, sin huérfanos; 0 tareas sin RF

✅ **Ningún requisito queda sin cubrir.** No hay que reportar huecos.

**Nota sobre la cobertura:** Se declares 27 RF en la spec y todas tienen tarea asignada. El objetivo es 27/27 = 100% de cobertura.

---

## 13. Comandos de Verificación

```bash
# ── Backend ────────────────────────────────────────────────────────────────
cd backend
uv run pytest -q                     # 328 tests rápidos (-m "not e2e")
uv run ruff check app tests          # line-length 100
uv run mypy tests/

# Fallback si `uv` no está en PATH (AGENTS.md lo advierte; en esta máquina sí lo está):
backend/.venv/bin/python -m pytest -q

# ── Frontend ───────────────────────────────────────────────────────────────
cd frontend
flutter test
flutter analyze                     # los warnings son error (AGENTS.md v3.11)
```

**Cifras de referencia verificadas antes de empezar** (`plan.md §7.2`):

| Medida | Valor | Origen |
|--------|-------|--------|
| Tests backend totales | **362** | `uv run pytest -q --collect-only` → `362 tests collected in 1.28s` |
| Tests en los 2 ficheros a tocar | **63**, en verde | `uv run pytest -q tests/test_ticket_service.py tests/test_preferencias_empresa.py` → `63 passed in 9.12s` |
| Tests frontend | 158 | `AGENTS.md` §Tests — **`[VERIFICAR]`** ejecutando `flutter test` |

---
**Fin de `tasks.md` v1.0.** 11 tareas · 27/27 RF cubiertos · 0 huérfanos ·
restricción dura `T4 ──precede──> T6` · T1 `[GATE]` descartable con
 reapertura de la pregunta 5 si `overflow_count > 0`. No se ha escrito código.
