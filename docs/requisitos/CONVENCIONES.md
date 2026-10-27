# Convenciones para la Matriz de Trazabilidad — BALANSOFT-WS

**Versión:** 1.0  
**Fecha:** 2026-10-26  
**Estado:** Vigente

---

## 1. Definiciones y Criterios de Clasificación

### 1.1 Requisito Funcional (RF)
**Qué es:** Describe **qué debe hacer el sistema** — una función, comportamiento, flujo o capacidad observable por un actor (usuario, sistema externo, dispositivo).

**Criterios de inclusión:**
- Se expresa como: "El sistema debe permitir…", "El sistema debe calcular…", "El sistema debe mostrar…"
- Tiene un actor y un resultado observable.
- Se valida con un test de integración, E2E o de aceptación.
- Aparece en endpoints, servicios, pantallas, BLoCs, flujos de instalación.

**Ejemplos:**
- RF: "El sistema debe permitir registrar una entrada de pesaje con peso capturado de báscula"
- RF: "El sistema debe generar el número de boleto secuencial por serie (ej. TA-00000001)"
- RF: "El sistema debe emitir una llave de activación de un solo uso (formato BS-XXXX-XXXX-XXXX)"

### 1.2 Requisito No Funcional (RNF)
**Qué es:** Describe **cómo debe comportarse el sistema** — atributos de calidad, restricciones técnicas, estándares.

**Criterios de inclusión:**
- No es una función observable directa, sino una propiedad del sistema.
- Se valida con tests de performance, seguridad, carga, o análisis estático.
- Aparece en configuración, middleware, arquitectura, políticas.

**Subtipos y ejemplos:**
| Subtipo           | Ejemplo                                                                    |
|-------------------|----------------------------------------------------------------------------|
| Seguridad         | "Toda query debe filtrar por `id_empresa` (multi-tenancy estricto)"        |
| Performance       | "Latencia p50 < 50ms, p95 < 200ms en endpoints de pesaje"                  |
| Disponibilidad    | "Offline-first: pesaje e impresión funcionan sin red"                      |
| Observabilidad    | "Métricas Prometheus sin `id_empresa` (cardinalidad acotada)"              |
| Mantenibilidad    | "Código sin warnings: `ruff check app tests` y `flutter analyze` en verde" |
| Interoperabilidad | "Protocolos básicos: Toledo/GSI, Rice Lake, MT-SICS, Yaohua, Torrey, Keli" |
| Usabilidad        | "i18n es/en/pt con 621 claves por idioma, paridad verificada por test"     |
| Portabilidad      | "WServer empaquetado como binario PyInstaller one-file"                    |

### 1.3 Regla de Negocio (RB)
**Qué es:** Una **restricción invariante** que el sistema debe hacer cumplir — cálculo, validación, estado, transición, integridad.

**Criterios de inclusión:**
- Es una verdad del dominio que **no cambia por configuración** (o cambia solo por migración).
- Se expresa como: "Si X entonces Y", "X nunca debe ser Y", "X debe ser único por empresa".
- Se valida con tests unitarios puros (sin BD, sin red).
- Aparece en: CHECK constraints, validadores Pydantic, `@validates` SQLAlchemy, lógica pura en servicios, enums, FSM de estados.

**Ejemplos:**
- RB: "Boleto solo puede estar en estados: PENDIENTE → CERRADO/MODIFICADO → ANULADO"
- RB: "Kardex ID 10 = INGRESO (+), ID 60 = DESPACHO (-); anular CERRADO genera movimiento inverso"
- RB: "Peso capturado de báscula **nunca** se edita; manual = `es_peso_manual=True` + auditoría"
- RB: "Serie numeración: contador transaccional con `FOR UPDATE`; DELETE serie usada = 409"
- RB: "Límite sesiones: DEMO = 3; resto = `licencias.max_sesiones` del LM (fuente única: `limite_sesiones_por_tier()`)"
- RB: "Llave activación: SHA-256 en BD, un solo uso por usuario, 7 días default, máx 90"

---

## 2. Nomenclatura de IDs

### 2.1 Formato
```
REQ-FN-<DOMINIO>-<NNN>   # Requisito Funcional
REQ-NF-<ÁREA>-<NNN>      # Requisito No Funcional
RB-<DOMINIO>-<NNN>       # Regla de Negocio
```

### 2.2 Dominios Funcionales (para RF y RB)
| Código        | Dominio                    | Descripción                                              |
|---------------|----------------------------|----------------------------------------------------------|
| AUTH          | Autenticación/Autorización | Login, JWT, roles, permisos, matriz de seguridad         |
| WEIGHING      | Pesaje                     | Entrada/salida, boletos, estados, captura peso, ticket   |
| CATALOG       | Catálogos                  | Terceros, productos, almacenes, transportes, vehículos   |
| KARDEX        | Kardex/Inventario          | Movimientos 10/60, ajustes, conceptos, contra-asientos   |
| SYNC          | Sincronización             | Push/pull offline-first, idempotencia, cola, conflictos  |
| LICENSE       | Licencia                   | Validación Ed25519, LM, snapshot, features, tiers        |
| SESSIONS      | Sesiones                   | Límite por tier, contador, bloqueo, expiración           |
| SEMAFORO      | Semáforo                   | Torre 3 luces, decisión backend, vigilante, HAL          |
| DEVICES       | Dispositivos               | Básculas, indicadores, semáforos, cámaras, impresoras    |
| REPORTS       | Reportes                   | Diarios, mensuales, personalizados, Excel, PDF           |
| AUDIT         | Auditoría                  | Tabla completa, filtros, roles ADMIN/AUDITOR             |
| I18N          | Internacionalización       | es/en/pt, claves, plurales, fechas, números              |
| OBSERVABILITY | Observabilidad             | Métricas, logs, alertas, tracing                         |
| INSTALLER     | Instalador                 | Pasos, rol, llave activación, config.json                |
| WSERVER       | WServer Runtime            | Bootstrap, BD, migraciones, .env, API local              |
| PRINTING      | Impresión                  | Térmica ESC/POS, matricial ESC/P, PDF ReportLab, spooler |

### 2.3 Áreas No Funcionales (para RNF)
| Código  | Área                                                        |
|---------|-------------------------------------------------------------|
| SEC     | Seguridad (auth, crypto, multi-tenancy, rate-limit)         |
| PERF    | Rendimiento (latencia, throughput, concurrencia)            |
| AVAIL   | Disponibilidad (offline-first, timeouts, retries)           |
| OBS     | Observabilidad (métricas, logs, alertas)                    |
| MAINT   | Mantenibilidad (lint, types, tests, modularidad)            |
| PORT    | Portabilidad (binario, multiplataforma, drivers opcionales) |
| USAB    | Usabilidad (i18n, a11y, atajos, responsive)                 |
| INTEROP | Interoperabilidad (protocolos, APIs, formatos)              |

### 2.4 Numeración
- Secuencial dentro del dominio/área: 001, 002, 003…
- Reservar rangos por submódulo si es grande (ej. WEIGHING 001–050, KARDEX 051–100).

---

## 3. Distinción: Requisito vs. Detalle de Implementación

| Requisito (SÍ incluir)                                                  | Detalle de Implementación (NO incluir)                           |
|-------------------------------------------------------------------------|------------------------------------------------------------------|
| "El sistema debe validar que la llave de activación no haya sido usada" | "La tabla `llaves_activacion` tiene columna `consumida BOOLEAN`" |
| "El peso capturado no se puede editar"                                  | "Campo `peso_entrada_vehiculo` es NUMERIC(10,2)"                 |
| "Latencia p95 < 200ms en `/weighing/list`"                              | "Usa `_enriquecer_pesajes_lista` con 7 consultas por página"     |
| "Ticket térmico 58mm y 80mm con tabla 5 columnas"                       | "`_tamano_tabla_pesos()` calcula 6.3pt / 4.5pt"                  |
| "Multi-tenancy estricto en toda query"                                  | "Helper `CatalogService.list_filtrado(..., id_empresa)`"         |

**Regla práctica:** Si al cambiar la tecnología (ej. PostgreSQL → SQL Server, Flutter → React) el enunciado **sigue siendo válido**, es un requisito. Si cambia, es detalle de implementación.

---

## 4. Estados de Trazabilidad

| Estado                          | Significado                                                   | Cuándo usar                                                                                         |
|---------------------------------|---------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| **IMPLEMENTADO**                | Código + tests + (idealmente) doc                             | Evidencia en código y tests pasando                                                                 |
| **PARCIAL**                     | Código existe pero incompleto o con gaps conocidos            | Falta cobertura de casos, hay TODOs, o tests en rojo                                                |
| **DOCUMENTADO-NO-IMPLEMENTADO** | Solo en docs (MANEJO_DB, TERMINOS, PLANES-PAGOS, specs, etc.) | No hay código ni tests que lo soporten                                                              |
| **IMPLEMENTADO-NO-DOCUMENTADO** | Solo en código/tests                                          | No aparece en ninguna doc vigente                                                                   |
| **LEGACY-NO-MIGRADO**           | Solo en docs/DOCUMENTACION VIEJA/                             | Requisito del legacy que no existe en código actual; producto debe decidir si recuperar o descartar |

---

## 5. Fuentes de Evidencia (Jerarquía de Confianza)

1. **Código fuente + tests en verde** (`.py`, `.dart`, `.sql`) — **fuente de verdad** (lo que el sistema HACE)
2. **docs/specs/** — Contratos formales de requisitos con IDs propios (ej. REQ-FN-001 de spec 001)
3. **docs/*.md raíz** — Documentación vigente (MANEJO_DB.md, NAV.md, MODELO_ESTANDAR.md, SEMAFORO.md, BALANZAS_SOPORTADAS.md, OBSERVABILIDAD.md, USO-API.md, SESIONES.md, PLANES-PAGOS.md, I18N_Y_ONBOARDING.md, AGENTS.md, ACTUAR.md, constitution.md)
4. **docs/evidencia/** — Mediciones empíricas (RNF de rendimiento: p50, p95, req/s, umbrales)
5. **TERMINOS_CONDICIONES.md** — Contrato comercial; puede describir restricciones no enforceadas técnicamente
6. **docs/DOCUMENTACION VIEJA/** — **NO AUTORITATIVO**; solo para detectar requisitos perdidos

**Regla de conflicto:** Si hay contradicción entre (1) y (2-5), **el código gana para describir el estado actual**, pero el requisito documentado NO se descarta: se registra como CONTRADICCIÓN para que producto decida.

---

## 6. Manejo de Contradicciones

Cuando doc ≠ código:
1. Registrar en `CONTRADICCIONES.md` con:
   - ID del requisito afectado
   - Qué dice la doc (cita exacta + archivo:línea)
   - Qué hace el código (cita exacta + archivo:línea)
   - Jerarquía aplicada (código gana para estado actual)
   - Resolución propuesta / decisión pendiente
2. Marcar el requisito en la matriz con `Estado = IMPLEMENTADO` + `Notas = "Contradicción con <doc> §X.Y — ver CONTRADICCIONES.md"`

---

## 7. Plantilla de Fila de Matriz

```markdown
| ID               | ID original (spec)    | Tipo | Dominio  | Descripción                                     | Criterio de aceptación                        | Fuente (código)                                                                         | Fuente (doc)              | Estado       | Notas |
|------------------|-----------------------|------|----------|-------------------------------------------------|-----------------------------------------------|-----------------------------------------------------------------------------------------|---------------------------|--------------|-------|
| REQ-FN-WEIGH-001 | REQ-FN-001 (spec 001) | RF   | WEIGHING | Registrar entrada de pesaje con peso de báscula | `test_weighing.py::test_entrada_peso_bascula` | `app/api/v1/endpoints/pesajes.py:45`, `app/services/weighing_service.py:create_entrada` | MANEJO_DB.md §6, spec 001 | IMPLEMENTADO |       |
```

---

## 8. Reportes de Consolidación (Fase 10)

Al final, generar 4 reportes:

1. **RFs sin test** — Riesgo de regresión. Buscar RFs donde no hay test asociado en la matriz.
2. **RFs documentados pero no implementados** — Deuda de producto. Estado = DOCUMENTADO-NO-IMPLEMENTADO.
3. **RFs implementados pero no documentados** — Deuda de documentación. Estado = IMPLEMENTADO-NO-DOCUMENTADO.
4. **Contradicciones doc vs. código** — Desde `CONTRADICCIONES.md`.

---

## 9. Checklist de Calidad por Fase

Antes de pasar a la siguiente fase, verificar:
- [ ] Todos los archivos de la fase han sido escaneados (grep/read)
- [ ] No hay requisitos duplicados (mismo ID o misma descripción)
- [ ] Cada requisito tiene al menos una fuente de código/test/spec/evidencia
- [ ] Los IDs siguen la nomenclatura
- [ ] Los estados son correctos según evidencia
- [ ] Las contradicciones detectadas están registradas
- [ ] Los IDs originales de specs se conservan en la columna "ID original (spec)"