# Correspondencias y Consistencia entre Vistas — BALANSOFT-WS

**Norma:** ISO/IEC/IEEE 42010 - Requerimiento de correspondencias entre vistas

## 1. Propósito

Según ISO/IEC/IEEE 42010, la documentación de arquitectura debe incluir correspondencias entre vistas para garantizar la consistencia y coherencia del modelo arquitectónico. Este documento mapea cómo las diferentes vistas (lógica, despliegue, implementación) se relacionan y se refuerzan mutuamente.

## 2. Matriz de Correspondencias entre Viewpoints

| Par de Vistas | Tipo de Correspondencia | Descripción |
|---------------|------------------------|-------------|
| **Lógica ↔ Despliegue** | **Refinement** | Los componentes de la visión lógica (WeighingService, CatalogService, etc.) se despliegan en los entornos definidos (local WServer en `0.0.0.0:8000`, server en `0.0.0.0:8002`). Cada componente tiene una asignación única de entorno. |
| **Lógica ↔ Implementación** | **Realization** | Cada componente lógico se realiza en clases de código específicas: FastAPI Python services, Dart Flutter widgets, SQL migraciones. Por ejemplo: `WeighingService` (lógico) → `app/services/weighing_service.py` (implementación). |
| **Despliegue ↔ Implementación** | **Deployment** | Los archivos de despliegue (`WServer.spec`, `scripts/build_wserver.sh`) corresponden a los binarios reales que se ejecutan. Los endpoints FastAPI definidos en `main.py` se mapean a las rutas OpenAPI generadas. |
| **Lógica ↔ Seguridad** | **Constraint** | La preocupación de aislamiento multi-tenant (`id_empresa` en toda consulta) es una restricción transversal que afecta a todos los componentes lógicos y a su implementación en BD y API. |
| **Metrología ↔ Lógica** | **Derivation** | Las reglas metrológicas (inmutabilidad peso, control sobrecapacidad, timestamps UTC) se derivan de las preocupaciones ISO/IEC 17025 y se implementan en la lógica de negocio del servicio `WeighingService`. |
| **Offline-First ↔ Lógica** | **Dependency** | La capacidad de operar offline (SQFLite + sync_queue) es una preocupación de non-functional quality que influye en el diseño de la capa de persistencia y la lógica de sincronización. |
| **Usabilidad (i18n) ↔ Lógica** | **Extension** | La internacionalización (es/en/pt) se extiende a todas las capadas: mensajes de API, vistas Flutter, previsualización e impresión de tickets, reportes exportados. |

## 3. Consistencia entre Preocupaciones Clave

| Concern | Vistas Afectadas | Tipo de Consistencia |
|---------|-----------------|---------------------|
| **Aislamiento multi-tenant** | Lógica, Despliegue, Implementación, Seguridad | **Invariante**: `id_empresa` debe aparecer en TODO query, filtro, inserción, validación en todas las vistas |
| **Inmutabilidad del peso** | Lógica, Metrología, Implementación | **Restricción**: Los campos `peso_entrada_vehiculo`, `peso_salida_vehiculo`, etc. NUNCA se editan en boletos CERRADOS/MODIFICADOS |
| **Estados de bolete** | Lógica, Despliegue | **Consistente**: La máquina de estados PENDIENTE → CERRADO/MODIFICADO → ANULADO es la misma en todas las vistas |
| **Series numeracionales** | Lógica, Implementación | **Consistente**: `SELECT ... FOR UPDATE` nunca reutiliza números; DELETE con boletos → 409 |
| **Matriz de permisos** | Seguridad, Implementación | **Consistente**: 18 módulos × 3 roles (ADMIN/OPERADOR/AUDITOR), ADMIN forzado a `editar` en todo |
| **Validación licencias** | Seguridad, Despliegue | **Consistente**: Ed25519 firma asimétrica; llaves un solo uso BS-XXXX-XXXX-XXXX, 7 días máx. |
| **Latencias de rendimiento** | Despliegue, Implementación | **Objetivo**: p50 < 50 ms, p95 < 200 ms bajo concurrencia normal |
| **Paginación obligatoria** | Lógica, Implementación | **Regla**: Todos los endpoints de lista deben soportar `limit` y `skip`; prohibido N+1 queries |

## 4. Rastreabilidad de Decisiones (Rationale)

| Decisión Arquitectónica | Documento Origen | Vistas Afectadas | Justificación |
|-------------------------|-----------------|------------------|---------------|
| Arquitectura server/local dual | `constitution.md §5`, `ADR-002` | Lógica, Despliegue | Garantizar offline-first y multi-tenancy nativo |
| Routers condicionales por `APP_ROLE` | `constitution.md §6`, `ADR-001` | Lógica, Implementación | Un solo repositorio, dos roles, migrabilidad futura |
| Validación Ed25519 + HMAC-SHA256 | `constitution.md §7`, `ADR-003` | Seguridad, Lógica | Seguridad criptográfica fuerte, licencias originarias |
| Capa HAL multi-marca | `constitution.md §9`, `ADR-004` | Lógica, Implementación | Compatibilidad con hardware existente en campo |
| Offline-first con sync_queue | `constitution.md §8`, `ADR-005` | Lógica, Despliegue | Operación garantizada sin conexión, recuperación automática |
| Migraciones hand-made (sin Alembic) | `constitution.md §6` | Implementación | Control total, idempotencia, sin dependencias externas |
| Motor BD por prefijo DATABASE_URL | `constitution.md §10` | Implementación, Despliegue | Soporte PostgreSQL y SQL Server por convenio, no nuevas env vars |

## 5. Verificación de Consistencia

Para verificar que todas las correspondencias son consistentes:

1. **Revisar que `id_empresa` esté presente** en cada query SQL generada por cada endpoint
2. **Confirmar que los estados de bolete** sean consistentes entre la máquina de estados y los endpoints API
3. **Validar que los números de serie** nunca se reutilicen revisando migraciones y constraints `RESTRICT`
4. **Verificar la matriz de permisos** 18×3 en cada endpoint de catálogo y pesaje
5. **Comprobar los timeouts** de lectura serie (1.0s a 2.0s) en la implementación HAL
6. **Confirmar formato de timestamps** UTC ISO 8601 en todas las inserciones de `fecha_hora_entrada/salida`

## 6. Fallos Comunes en Correspondencias

| Fallo | Descripción | Impacto | Detector |
|-------|-------------|---------|----------|
| Fuga de `id_empresa` | Alguna query no incluye el filtro `id_empresa` | Exposición de datos entre empresas | Revisar logs `/metrics`, queries lentas |
| Estados de bolete inconsistentes | Transición no permitida en la máquina de estados | Lógica incorrecta, boletes en estado imposible | Tests automatizados TEST-003, TEST-004 |
| Número de serie reutilizado | `DELETE series_numeration` con boletos asociados no bloqueado | Violación de regla de negocio | Tests TEST-008, código 409 |
| Peso editable en boleto CERRADO | Endpoint permite modificar `peso_entrada_vehiculo` | Violación metrológica | Tests TEST-010, reglas ISO 17025 |
| Faltante `limit`/`skip` en endpoint | Endpoint de lista sin paginación | Problemas de performance, N+1 queries | Revisar `ruff check`, manuales de API |
| JWT sin validación Ed25519 | Licencia aceptada sin firma against LM | Seguridad comprometida | Tests de licencia, validación LM |

## 7. Mapeo a Documentos Relacionados

- **Visión Lógica** (`logical-view.md`): Descripción detallada de componentes e interfaces
- **Visión de Despliegue** (`deployment-view.md`): Entornos, configuración de despliegue
- **Visión de Implementación** (`implementation-view.md`): Módulos de código, clases, SQL
- **ADRs** (`architecture/adr/`): Decisiones arquitectónicas con rationale detallado
- **Constitución** (`constitution.md`): Principios rectores y restricciones
- **Stakeholders** (`stakeholders.md`): Partes interesadas y sus concerns
- **Matriz de Trazabilidad Global** (`../../traceability-matrix.md`): Cadena completa requisitos → diseño → tareas