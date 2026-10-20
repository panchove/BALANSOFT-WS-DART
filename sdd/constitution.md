# Constitución del Proyecto BALANSOFT-WS

## Principios Rectores

### 1. Trazabilidad Completa
Todo requisito, decisión de diseño y tarea de implementación debe ser rastreable a su origen y destino:
- Cada artefacto contiene identificadores `id`, `traces_to`, `traces_from`
- La matriz de trazabilidad global (`traceability-matrix.md`) mantiene el resumen completo
- Cadena completa: requisitos → diseño → implementación → verificación

### 2. Aislamiento Multi-Tenant Obligatorio
- Todo dato, consulta, filtro, inserción o validación debe incluir `id_empresa`
- Ninguna métrica pública, log o endpoint debe exponer `id_empresa` o datos sensibles
- El aislamiento es responsabilidad de todas las capas (backend, frontend, BD)

### 3. Inmutabilidad del Peso Capturado
- El peso leído de la báscula NUNCA se edita ni sobrescribe
- Pesajes manuales requieren `es_manual=True` y autorización de roles ADMIN/SUPERVISOR
- Los campos de peso reflejan la verdad física en el momento exacto

### 4. Ciclo de Vida del Boleto
- Únicos estados válidos: `PENDIENTE → CERRADO/MODIFICADO → ANULADO`
- Anti-duplicidad: un camión/placa no puede tener dos boletos PENDIENTE simultáneamente
- Modificación posterior al cierre pasa a estado `MODIFICADO` e incrementa `ediciones_count`

### 5. Series de Numeración y Concurrencia
- Números secuenciales derivados de `series_numeracion` con bloqueo pesimista `SELECT ... FOR UPDATE`
- Un número emitido nunca se reasigna ni reutiliza
- No se permite borrar una serie con boletos asociados (código 409)

### 6. Composición de Roles
- Roles definidos: `ADMIN`, `OPERADOR`, `AUDITOR` (el `TRABAJADOR` se fusionó en `OPERADOR`)
- ADMIN forzado a permiso `editar` en todos los módulos
- Matriz 18 módulos × 3 roles con acceso `ver`/`editar`/`ninguno`

### 7. Licencias Ed25519
- Validación de licinas mediante firmas asimétricas Ed25519
- Llaves de activación un solo uso (`BS-XXXX-XXXX-XXXX`, SHA-256, 7 días máx.)
- Estación no gatea por `features`/`plan_type`, solo tope local de sesiones (`DEMO` = 3)

### 8. Ofline-First
- Capa local SQLite + cola de sincronización (`sync_queue`) para operar sin internet
- Gracia de 7 días (`OFFLINE_GRACE_DAYS=7`) tras expiración de licencia DEMO
- Recuperación automática con backoff exponencial ante cortes de red

### 9. Metrología Legal
- Inmutabilidad metrológica: el software no permite alteración falseada de pesos
- Trazabilidad de medición: `id_balanza`, timestamp UTC, estado `stable`/`unstable`, modo captura
- Control de sobrecapacidad: rechazo si > 105% de capacidad nominal (`TOLERANCIA_CAPACIDAD = 1.05`)
- Seguimiento de cero: prohibido boletos con peso neto nulo o negativo

### 10. Codificación y Formatos
- Unicode / UTF-8 como codificación predeterminada
- ISO/IEC 8859-1 (Latin-1) / CP850 en spooling binario para impresoras térmicas y matriciales
- ISO/IEC 15417: códigos de barras Code 128
- ISO/IEC 18004: especificación para códigos QR

## Convenciones de Metadatos

Todos los archivos Markdown deben incluir un bloque de metadatos al inicio, después del título principal:

```markdown
**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Norma:** ISO/IEC 29148
**Fuente:** Sistema BALANSOFT-WS
**Autor:** Lead Architect
```

### Campos de Trazabilidad Requeridos

| Campo                 | Descripción                                  | Ejemplo                          |
|-----------------------|----------------------------------------------|----------------------------------|
| `id`                  | Identificador único del artefacto            | `REQ-001`, `DES-001`, `TASK-001` |
| `traces_to`           | A dónde apunta este artefacto (dependencias) | `REQ-001 → DES-001`              |
| `traces_from`         | De dónde proviene este artefacto (origen)    | `FR-SDD-001 → REQ-001`           |
| `verification_method` | Método de verificación asociado              | `suite de pruebas TEST-001`      |

## Estructura de Identificadores

```
REQ-xxx   -- Requisitos (ISO/IEC 29148)
DES-xxx   -- Diseño / Componentes (ISO/IEC 1016)
TASK-xxx  -- Tareas de implementación (ISO/IEC 12207)
ADR-xxx   -- Decisiones Arquitectónicas (ISO/IEC 42010)
```

## Normas ISO/IEC/IEEE Referenciadas

- **ISO/IEC/IEEE 29148**: Ingeniería de requisitos de software
- **ISO/IEC/IEEE 42010**: Descripción de arquitectura de sistemas y software
- **ISO/IEC/IEEE 1016**: Descripción de diseño de software
- **ISO/IEC/IEEE 12207**: Modelos de procesos del ciclo de vida del software
- **ISO/IEC 25010**: Calidad del producto de software (SQuaRE)
- **ISO/IEC 17025**: Requisitos para laboratorios de ensayo y calibración
- **OIML R 76-1**: Metrología legal para básculas no automáticas