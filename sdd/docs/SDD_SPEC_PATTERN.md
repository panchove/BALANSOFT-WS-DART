# SDD SPEC Pattern v1.0 — Especificación Maestra

**Versión:** 1.0
**Fecha:** 2026-10-19
**Norma:** ISO/IEC 29148
**Propósito:** Estructurar todos los specs del proyecto BALANSOFT-WS con patrón coherente, verificable y completo.

---

## §1. Estructura Obligatoria por Componente

Todo spec debe entregar como tres archivos bajo `sdd/specs/<id>-<nombre>/`:

### A. `spec.md` — El documento de especificación completa
**Secciones obligatorias (en orden):**

| § | Nombre | Contenido mínimo |
|---|--------|-----------------|
| **§1** | Introducción | Contexto, alcance, quiénes intervinen, norma base |
| **§2** | Requisitos Funcionales (EARS) | Cada requisito con estructura `MIENTRAS <condición>, EL SISTEMA DEBE <acción>`; IDs REQ-FR-xxx |
| **§2.1** | Requisitos Funcionales Principales | Hasta REQ-FR-012 (o según necesidad, pero numereado consecutivo) |
| **§2.4** | Trazabilidad de Cifras | *Toda cifra debe tener origen verificable: archivo y línea, comando reproducible, o cita textual. Si no puede verificarse, `[VERIFICAR]` y no se avanza.* |
| **§3** | Decisiones Tomadas | Tabla | # | Decisión | Valor |; hasta 5 decisiones resueltas con justificación |
| **§4** | Alcance | 4.1 Dentro de alcance (lista); 4.2 Fuera de alcance (tabla con #, excluido, condición) |
| **§5** | Requisitos No Funcionales Asociados | REQ-NF-xxx con estructura EARS o atribución de umbral |
| **§6** | Hallazgos Registrados (H-x) | Tabla | # | Hallazgo | Descripción | Solución SDD | |
| **§7** | Criterios de Finalización | Tabla | # | Punto | Estado v0.N | ✅/⚠️/🛑 | |
| **§8** | Riesgos | Tabla | Riesgo | Severidad | Mitigación en esta spec | |
| **§9** | Checklist de Verificación Pre-Entrega | Tabla | # | Punto | Estado v0.N | ✅/⚠️ | |
| **§10** | Historial | Tabla | Versión | Cambios | |
| **§11** | Trazabilidad | Tabla | Origen | Requisitos | |
| **§12** | Comandos de Verificación | Bloques de código bash para: backend pytest, ruff, mypy, frontend flutter test/analyze |
| **§13** | Cifras de Referencia Verificadas | Tabla | Medida | Valor verificado | Origen | |

### B. `tasks.md` — Mapeo RF → Tarea
**Estructura:**

| RF | Descripción corta | Tareas | ¿Cubierta? |
|----|-------------------|--------|:----------:|
| Cada REQ-FR/REQ-NF de spec.md | Descripción corta | TASK-xxx (una por tarea principal) | ✅/⚠️ |

**Al final, obligatoriamente:**

| Verificación | Estado |
|---|---|
| **N declarados** | X |
| **N cubiertas** | X (objetivo N/N = 100%) |
| **0 huérfanos** | Ningún requisito queda sin tarea asignada |
| **Nota sobre cobertura** | Se declararon N RF y todas tienen tarea. El objetivo es N/N = 100% de cobertura. |

### C. `plan.md` — Plan de implementación y pruebas
**Estructura general (secciones 1-13 idénticas a spec.md en contenido y orden, pero orientadas a implementación/pruebas):**

| § | Nombre | Contenido |
|---|--------|-----------|
| **§1** | Puntos de decisión bloqueantes | T1 [GATE] si aplica; restricciones duras |
| **§2** | Tabla de dependencias | Gráfico T1→T2→... con bloques y restricciones |
| **§3** | Archivos y responsabilidades por capa | Por capa: Router, Service, Schema, Model, Migration, Tests, Flutter Presentation, Flutter Application, etc. |
| **§4** | Funciones puras con "hoy" como parámetro | Funciones testables con parámetro `hoy` |
| **§5** | Pseudocódigo | Versión ejecutable/transcribible a código |
| **§6** | Decisiones justificadas con alternativa descartada | Por qué se eligió un enfoque sobre otro |
| **§7** | Estrategia de tests | Comandos reales, baseline numérico, qué test va primero, cobertura RF→test |
| **§8** | Baseline (cuando aplique) | Comparación byte-a-byte o texto extraído de PDFs |
| **§9** | Evidencia: Discrepancias entre spec antigua y código real | Lista de hallazgos verificados |
| **§10** | Historial | Versiones y cambios |
| **§11** | Trazabilidad de cifras del plan | Mismo formato que §13 de spec.md |
| **§12** | Comandos de Verificación | Igual que §12 de spec.md |
| **§13** | Evidencia: Discrepancias (repetida por simplicidad) | Igual que §12 de spec.md |

---

## §2. Checklist de Validación Pre-Entrega (§9 de cada spec)

**Criterio: 8 de 8 puntos pasar → spec considerada "entregada".**

| # | Punto | Qué verificar |
|---|-------|---------------|
| 1 | Cada cifra tiene `archivo:línea`, comando reproducible o cita textual | No hay cifras "flotantes" sin origen documentado |
| 2 | Cada API nombrada **existe**, verificada en código fuente | `grep`, inspección de archivo, no solo documentación |
| 3 | Cada afirmación sobre comportamiento está **reproducida** o marcada `[VERIFICAR]` | Test que demuestre o marque el riesgo |
| 4 | Los casos límite **no contradicen** los requisitos | Tests en extremos, no solo casos nominales |
| 5 | Ninguna cifra procede de un subagente sin verificación propia | Verificación propia del humano, no delegada |
| 6 | Las APIs nombradas se **compilan**, no solo existen | `mypy`, prueba de importación, no solo `grep` |
| 7 | Las cifras se verifican **antes** de entregar, no después de un fallo | Checklist ejecutada pre-entrega |
| 8 | Al verificar una cifra ajena se **repite su comando exacto** antes de estrezar el patrón | Reproducibilidad |

**Resultados por versión:**

| Versión | Puntos pasar | Comentario |
|---------|-------------|------------|
| v0.3 | 7 de 8 | 1 pendiente (§5 no verificado) |
| v0.4 | **8 de 8** | **Todos pasan** → estándar mínimo "entregado" |

---

## §3. Patrones Requeridos en Contenido

### A. Estructura EARS (Everyday Auditable Requirement Specification)
Toda requisito funcional debe seguir:

```
**ID** — MIENTRAS <condición>, EL SISTEMA DEB <acción>
```

Ejemplo:
```
**REQ-FR-001** — MIENTRAS el sistema procese un pesaje de entrada, EL SISTEMA DEBE
validar anti-duplicidad por `placa + id_empresa`, retornando código 400 si ya existe un boleto PENDIENTE para ese vehículo.
```

### B. Trazabilidad de Cifras ( §2.4 )
Cada número, conteo o medición en el documento debe tener:

```
| Medida | Valor verificado | Origen |
|--------|------------------|--------|
| `fontSize:` 332 | `grep -rn "fontSize:" frontend/lib/ | wc -l` → 332 | ejecución empírica |
| `textTheme` 14 | `grep -rn "textTheme" frontend/lib/ | wc -l` → 14 | ejecución empírica |
```

### C. Historial de Versiones
Formato tabla estricto:

| Versión | Cambios |
|---------|---------|
| 0.1 | Borrador inicial; X decisiones; Y requisitos |
| 0.2 | QA: [puntos], especificación reformulada a [aspecto] |
| **0.3** | **Corrección de errores factuales** ... |
| **0.4** | **T1 (gate) detectó overflow...** Añadido CE-16, rango reducido a 1.40 ... |

### D. Cifras de Referencia Verificadas ( §13 de spec.md )
Tabla al final de spec.md con todas las medidas verificadas empirically:

| Medida | Valor verificado | Origen |
|--------|------------------|--------|
| Tests backend totales | 362 | `uv run pytest -q --collect-only` → 362 tests collected in 1.28s |
| Tests en los 2 ficheros a tocar | 63, en verde | `uv run pytest -q tests/test_ticket_service.py tests/test_preferencias_empresa.py` → 63 passed in 9.12s |
| ... | ... | ... |

---

## §4. Migración de Specs Legacy → Patrón v1.0

Para migrar un spec legacy al patrón actual:

1. **Leer el spec.md actual** y anotar secciones existentes
2. **Aplicar la estructura §1-§13** anterior, reubicando contenido existente
3. **Añadir §2.4 Trazabilidad de Cifras** si no existe (obligatorio)
4. **Añadir §9 Checklist 8/8 pasar** si no existe (obligatorio)
5. **Reformular cifras sin origen** con `[VERIFICAR]` o verificación empírica
6. **Normalizar IDs de requisitos** de `FR-SDD-xxx` a `REQ-FR-xxx` (o según convención actual)
7. **Verificar checklist §9** antes considerar spec "entregada"
8. **Actualizar tasks.md** con cobertura RF→tarea N/M = 100%
9. **Crear/actualizar plan.md** con estructura de plan v1.0

**Ejemplo de migración:** Módulos 001, 002, 003 fueron migrados de formato legacy a SDD SPEC Pattern v1.0 en la sesión actual, añadiendo secciones §2.4, §9, reformulando cifras sin origen y normalizando la cobertura de requisitos.

---

## §5. Errores Comunes a Evitar

| # | Error | Consecuencia | Prevención |
|---|-------|--------------|------------|
| 1 | Afirmar "11 peldaños" sin contexto `boletos_por_hoja` | Cifra falsa, diseño mal entendido | Verificar siempre en `ticket_service.py:1142-1147` |
| 2 | Decir "16 títulos hardcodeados y 0 con `.tr()`" | Cifra inventada, H-8 detectado | Contar `.tr()` reales en `settings_screen.dart` |
| 3 | Usar `MediaQuery.clampTextScaler` | Método inexistente, rompe CI | Usar `MediaQuery.withClampedTextScaling` o `TextScaler.clamp` |
| 4 | Afirmar "lista única de 11 candidatos" | Desacuerdo con diseño diccionario indexado | Revisar `ticket_service.py:1142-1147` |
| 5 | Dejar cifras sin origen verifiable | No pasar checklist §9 | Toda cifra necesita `archivo:línea`, comando o cita |

---

## §6. Historial de Patrones

| Versión | Fecha | Cambios |
|---------|-------|---------|
| 0.1 | — | Patrón inicial propuesto |
| 0.2 | — | Añadida §2.4 Trazabilidad de Cifras |
| **0.3** | **2026-10-19** | **Corrección MediaQuery.clampTextScaler → APIs reales; diseño por filtrado vs reemplazo primero; H-8 corregido** |
| **1.0** | **2026-10-19** | **Estructura completa §1-§13, checklist 8/8 v0.4, patrones EARS, errores comunes, guía de migración** |

---