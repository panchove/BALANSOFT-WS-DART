---
name: sdd-test-plan
description: Crear una suite de pruebas basada en la nueva especificación para garantizar equivalencia funcional con el sistema legacy (evitando regresiones).
---
# SDD Test Plan Skill

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 25010 / ISO/IEC 12207
**Fuente:** Sistema BALANSOFT-WS (Test Plan SDD)
**Autor:** Legacy2SDD Translator

## Objetivo

Crear una suite de pruebas basada en la nueva especificación SDD para garantizar equivalencia funcional con el sistema legacy, evitando regresiones durante la migración o transformación del sistema. Este skill toma la arquitectura definida en `sdd-arch-rebuild` y el comportamiento legado del `legacy-ingest` para generar una suite de pruebas completa.

## Entrada Esperada

El skill requiere como input estructurado:

1. **Output del skill `sdd-arch-rebuild`:**
   - Diagramas Mermaid (componentes, secuencia, flujo de datos)
   - Modelo de datos normalizado con entidades y relaciones
   - Contratos de interfaz (OpenAPI 3.0 endpoints)
   - Registro de decisiones arquitectónicas (ADRs)

2. **Output del skill `legacy-ingest`:**
   - Matriz de reglas de negocio (RULE-XXX)
   - Mapas de vacíos (GAP-XXX)
   - Comportamientos críticos y edge cases detectados en el legado

## Output Estructurado

### 1. Casos de Prueba Functional-Equivalence (Legacy vs SDD)

Los casos de prueba están diseñados para validar que el nuevo sistema SDD preserve el comportamiento del sistema legacy en escenarios críticos.

| ID Prueba | Descripción | Comportamiento Legacy | Comportamiento SDD | Equivalencia Esperada |
|-----------|-------------|----------------------|--------------------|-----------------------|
| **TEST-001** | **Creación de boleto entrada** | `POST /weighing/create` con placa vehiculo, valida anti-duplicidad (código 400 si boleto PENDIENTE existe). | `POST /api/v1/weighing/create` mismo comportamiento con `id_empresa` filter. | **PASS** Si ambos rechazan boleto duplicado con código 400. |
| **TEST-002** | **Cierre de pesaje** | `POST /weighing-close` calcula PTE-PTS-PNT-PDF-PDV, valida tolerancia, registra kardex ID 10/60. | `POST /api/v1/weighing-close` mismo cálculo con validación tolerancia y movimiento kardex. | **PASS** Si cálculos matemáticos idénticos y movimiento kardex correcto. |
| **TEST-003** | **Anulación de boleto CERRADO** | `PUT /weighing/{boleto}/anular` requiere `motivo_anulacion` (≥10 chars), pasa estado ANULADO, registra auditoría, movimiento inverso kardex. | `PUT /api/v1/weighing/{boleto}/anular` mismo flujo con auditoría y movimiento inverso. | **PASS** Si estado ANULADO, auditoría registrada y kardex inverso idéntico. |
| **TEST-004** | **Modificación de boleto MODIFICADO** | En estado MODIFICADO, solo campos `documento`, `flete`, `costo_flete`, `observaciones`, `peso_neto_declarado` (PND) son editables. Peso báscula NUNCA se edita. | `PUT /api/v1/weighing/{boleto}` mismo filtrado de campos permitidos, bloqueo peso báscula. | **PASS** Si solo campos permitidos aceptados y peso báscula bloqueado. |
| **TEST-005** | **Sincronización local→servidor** | `POST /sync/push` envía lotes de boletos, usuarios, catálogos. El servidor procesa y marca `pendiente=False`. | `POST /api/v1/sync/push` mismo flujo con procesamiento y marcado en BD. | **PASS** Si lotes procesados y `sync_queue` limpiado correctamente. |
| **TEST-006** | **Validación tolerancia comercial** | `PDV > tolerancia_producto` emite warning auditoría, NO bloquea cierre. | `PDV > tolerancia_producto` warning auditoría, no bloquea cierre en SDD. | **PASS** Si comportamiento idéntico (advertencia pero cierre permitido). |
| **TEST-007** | **Bloqueo boleto PENDIENTE duplicado** | Un camión/placa no puede tener dos boletos PENDIENTE simultáneamente (código 400). | Mismo bloqueo en SDD con `id_empresa` filter en consulta. | **PASS** Si ambos retornan 400 ante duplicidad. |
| **TEST-008** | **Numeración de series** | `series_numeracion` con `FOR UPDATE` evita carreras, número nunca se reutiliza. | Mismo comportamiento con transacción transaccional en SDD. | **PASS** Si números asignados son secuenciales y nunca se reutilizan. |
| **TEST-009** | **Modo offline** | Sin internet, JWT válido opera contra API local. JWT expirado permite login local con `usuarios.password_hash`. | Mismo flujo con `auth-login-local` y caché `identidad_local`. | **PASS** Si offline/online comportamiento idéntico. |
| **TEST-010** | **ISO/IEC 17025 - Inmutabilidad metrológica** | Peso capturado no puede ser alterado ni suavizado. | En SDD: `es_peso_manual=True` si viene de hardware, bloqueo edición contrario. | **PASS** Si comportamiento metrológico idéntico preservado. |

### 2. Escenarios de Validación ISO/IEC 25010

Estos escenarios validan atributos de calidad no funcionales definidos en la norma 25010:

| ID Escenario | Atributo ISO/IEC 25010 | Descripción | Caso de Prueba Asociado | Éxito Esperado |
|--------------|----------------|-------------|------------------------|----------------|
| **PF-01** | **Performance Efficiency** | Latencias p50 < 50 ms, p95 < 200 ms bajo concurrencia normal. | TEST-001 a TEST-010 | p50 ≤ 50ms, p95 ≤ 200ms |
| **SE-01** | **Security** | Aislamiento multi-tenant por `id_empresa` en 100% consultas. | TEST-001, TEST-007 | Sin fugas de `id_empresa` en logs/métricas. |
| **RE-01** | **Reliability** | Manejo desconexiones sockets TCP con `wait_closed()` timeout 2.0s. | TEST-009 (offline) | Sin cuelgue proceso ante desconexión. |
| **MA-01** | **Maintainability** | Código sin warnings (ruff/flake8) y modularidad estricta. | Estructura de carpetas, imports. | 0 warnings ruff/flake8. |
| **PO-01** | **Portability** | WServer binario one-file independiente de Python instalado. | Compilación WServer en máquina limpia. | Binario funcional sin Python. |

### 3. Fixtures / Datasets de Prueba con Casos Límite (Edge Cases)

#### a) Datos de Entrada Normalizados

| Fixture | Descripción | Datos de Entrada | Resultado Esperado |
|---------|-------------|------------------|--------------------|
| **FXT-001** | **Boleto entrada completo** | `peso_entrada_vehiculo=3540.50`, `peso_entrada_remolque=0`, `placa ABC-123`, `conductor='12345678Z'` | Booleto PENDIENTE creado con `numero_boleto` asignado. |
| **FXT-002** | **Boleto con remolque** | `peso_entrada_vehiculo=3540.50`, `peso_entrada_remolque=1200.25`, `placa ABC-123`, `remolque=True` | Booleto PENDIENTE con PER calculado y `multi_despacho_recepcion=False`. |
| **FXT-003** | **Boleto anulación** | Boleto CERRADO con `motivo_anulacion='Fallo en guía SUNAGRO'` (≥10 chars). | Estado ANULADO, movimiento inverso kardex, auditoría registrada. |
| **FXT-004** | **Boleto tolerancia exceeded** | `PDV = 8.5%`, `tolerancia_producto = 5%`. | Advertencia auditoría, cierre permitido, kardex generado. |
| **FXT-005** | **Modo offline usuario** | Sin internet, JWT expirado, credenciales locales válidas. | Login `auth-login-local` exitoso, JWT local emitido (7 días grace). |
| **FXT-006** | **Series numeración extremo** | Serie con `siguiente=999999`, emisión nueva. | Nuevo número `TA-00000001` asignado, `siguiente=2` actualizado. |
| **FXT-007** | **Kardex movimiento 60 (despacho)** | Boleto con `PNT < 0` (salida). | Movimiento kardex ID 60, signo negativo, `stock_actual_ton` decrementado. |
| **FXT-008** | **Kardex movimiento 10 (ingreso)** | Boleto con `PNT > 0` (entrada). | Movimiento kardex ID 10, signo positivo, `stock_actual_ton` incrementado. |

#### b) Casos Límite (Edge Cases) Detectados en Legacy

| Edge Case | Descripción | Comportamiento Legacy | Validación SDD Requerida |
|-----------|-------------|----------------------|------------------------|
| **EC-001** | **Hora sin zona horaria** | `fecha_hora_entrada` sin `Z` o `UTC` definido. | SDD debe normalizar a `timestamp with time zone` o `UTC datetime`. |
| **EC-002** | **Peso neto cero** | `PNT = 0` (bruto = tara). | Movimiento kardex ID 10 o 60 según tipo, o sin movimiento si reglas definen "sin movimiento". |
| **EC-003** | **Borrar serie con boletos** | Intentar `DELETE series_numeracion` con boletos asociados. | Debe retornarse código 409 Conflict, borrado prohibido hasta anular/transferir boletos. |
| **EC-004** | **Login con hardware_id ajeno** | Tercer equipo intenta activar cuenta ajena. | Debe retornarse `403 Forbidden` o `404 Not Found`, sin permitir activación. |
| **EC-005** | **Sincronización conflicto** | Mismo boleto modificado en local y servidor simultáneamente. | Skill sync debe resolver con "último timestamp gana", registrar versión anterior en `boletos_ediciones`. |
| **EC-006** | **Licencia DEMO expiración** | Licencia `DEMO` expira tras 30 días. | Sistema debe pasar a modo readonly o solicitar licencia comercial. |
| **EC-007** | **Borrar empresa con datos** | `DELETE empresa` con boletos/usuarios asociados. | Debe retornarse 409 o bloqueo con mensaje "tiene datos asociados, anule primero". |

### 4. Ejecución de Pruebas

#### a) Configuración de Entorno

```bash
# Instalar dependencias de test
cd /home/panchove/Projects/I+D-SYSTEM/BALANSOFT-WS-DART
uv sync --extra test  # si tests requieren extras

# O configurar entorno manual
pip install pytest pytest-asyncio httpx pytest-mock
```

#### b) Ejecutar Suite de Pruebas

```bash
# Ejecutar todas las pruebas de functional equivalence
pytest tests/ -k "TEST-" -v

# Ejecutar pruebas de atributos ISO/IEC 25010
pytest tests/ -k "PF-01 or SE-01 or RE-01" -v

# Ejecutar pruebas específicas
pytest tests/test_legacy_equivalence.py::TEST-001 -v
```

#### c) Reportes de Resultados

```bash
# Generar reporte HTML
pytest tests/ -v --html=report/test_suite.html

# Generar reporte JUnit para CI
pytest tests/ -v --junit-xml=report/results.xml

# Fallar build ante failures críticos
pytest tests/ -v --fail-on-skips --fail-on-errors
```

## Buenas Prácticas

1. **Siempre incluir edge cases:** Los casos límite (EC-001 a EC-007) deben estar cubiertos en la suite de pruebas, ya que son típicos de sistemas legacy transformados.
2. **Siempre validar ISO/IEC 25010:** Los escenarios de calidad (PF-01 a PO-01) deben ejecutarse en la pipeline de CI/CD, no solo en desarrollo local.
3. **Siempre versionar fixtures:** Los datasets de prueba (FXT-001 a FXT-008) deben versionarse junto con la especificación para mantener consistencia a través de iteraciones.
4. **Siempre fall build ante CRITICAL failures:** Failures en escenarios SE-01 (Security) o DT-XXX (Compliance) deben fallar la construcción CI/CD automáticamente.
5. **Siempre documentar pasos para reproducir:** Cada caso de prueba debe tener descripción clara de pasos pre-condiciones y pasos de validación post-ejecución.

## Limitaciones

1. Requiere input estructurado de ambos skills anteriores (`sdd-arch-rebuild` + `legacy-ingest`). No funciona con especificaciones parciales.
2. La cobertura de pruebas depende de la exhaustividad del análisis legacy. Legacy con documentación muy fragmentada reduzca la precisión de edge cases.
3. Algunas validaciones ISO/IEC 25010 requieren entorno de ejecución real y no pueden probarse completamente en modo solo-architectural.

## Ejemplo de Uso

```bash
# Ejecutar skill generando plan de pruebas completo
/sdd-test-plan "output_del_sdd_arch_rebuild" "output_del_legacy_ingest"

# Resultado esperado: Documento de plan de pruebas con:
# - 10+ TEST-XXX casos de functional equivalence
# - 5+ escenarios validación ISO/IEC 25010
# - 8+ fixtures/datasets FXT-XXX con edge cases
# - Pasos de ejecución y reportes configurables
```
