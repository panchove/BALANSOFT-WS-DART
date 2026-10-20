---
name: sdd-spec-transform
description: Convertir el análisis del sistema legacy en una Especificación de Requisitos de Software (SRS) formal y estructurada bajo SDD y la norma ISO/IEC 29148.
---
# SDD Spec Transform Skill

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 29148 / ISO/IEC 25010
**Fuente:** Sistema BALANSOFT-WS (Legacy → SDD Transformation)
**Autor:** Legacy2SDD Translator

## Objetivo

Convertir el análisis extraído por el skill `legacy-ingest` en una **Especificación de Requisitos de Software (SRS)** formal y estructurada bajo el modelo SDD y la norma ISO/IEC 29148. Este skill toma las reglas de negocio, vacíos y restricciones detectadas en la fase de ingestión y las transforma en requisitos formales con priorización RFC 2119 y criterios de aceptación en formato Gherkin.

## Entrada Esperada

El skill requiere como entrada estructurada el output del skill `legacy-ingest`, específicamente:

1. **Matriz de Reglas de Negocio (RULE-XXX):** Lista de reglas de negocio extraídas del legado.
2. **Mapa de Vacíos (GAP-XXX):** Brechas de información identificadas.
3. **Mapa de Deuda Técnica (DT-XXX):** Riesgos y clasificaciones de criticidad.
4. **Contexto del Dominio:** Información sobre el sector, actores, transacciones críticas.

## Estructura del Output SDD

### 1. Propósito y Alcance del Sistema (Nuevo Modelo vs Legacy)

**Propósito SDD:**
> Sistema BALANSOFT-WS: Estación pesaje industrial multi-empresa con arquitectura cliente-servidor y base de datos dual (server/local). Decisión arquitectónica fundamental: separación de la base de datos en dos instancias (`balansoft_ws` servidor y `balansoft_ws_local` máquina del cliente).

**Diferencias Legado vs SDD:**
- **Legado:** Single database, sin separación de roles, lógica de negocio dispersa.
- **SDD:** Dos bases de datos, `APP_ROLE=server|local`, routers condicionales, multi-tenant obligatorio con `id_empresa` en toda consulta.

### 2. Requisitos Funcionales Extrapolados

Los requisitos se priorizan con niveles **RFC 2119** y se definen con criterios de aceptación en formato **Gherkin (Given/When/Then)**.

| ID Requisito | Prioridad RFC 2119 | Descripción | Criterio de Aceptación Gherkin |
|--------------|-------------------|-------------|--------------------------------|
| FR-SDD-001 | MUST | El sistema debe garantizar aislamiento multi-tenant mediante `id_empresa` en toda consulta. | **Given** un usuario autenticado con `id_empresa` definido, **When** se ejecuta cualquier consulta CRUD, **Then** el resultado debe filtrarse exclusiv por `id_empresa` y no exponer datos de otras empresas. |
| FR-SDD-002 | MUST | El peso capturado por la báscula nunca puede ser editado. | **Given** un boleto en estado CERRADO, **When** el usuario intenta modificar `peso_entrada_vehiculo`, **Then** el sistema debe rechazar la operación y registrar intento en auditoría. |
| FR-SDD-015 | MUST | Validación de tolerancia comercial en cierre de boleto. | **Given** un boleto con `PDV` calculado, **When** `PDV > tolerancia_producto`, **Then** emitir advertencia en auditoría y no bloquear cierre. |
| FR-SDD-010 | SHOULD | El sistema debe soportar modo offline con sincronización posterior. | **Given** un usuario sin conexión internet, **When** opera la app en modo offline, **Then** debe poder crear boletos PENDIENTE y sincronizarlos al recuperar conexión. |
| FR-SDD-005 | MAY | El sistema debe soportar generación de tickets en formatos PDF y TXT. | **Given** un boleto CERRADO, **When** el usuario solicita imprimir ticket, **Then** debe generar archivo coherente con la vista preview en Flutter (`TicketPreviewDialog`). |

### 3. Requisitos No Funcionales (Alineados a ISO/IEC 25010)

| ID Requisito | Descripción | Criterio de Medición |
|--------------|-------------|----------------------|
| **PF-001** | **Desempeño (Performance Efficiency):** Latencias de endpoints de pesaje y catálogos: p50 < 50 ms, p95 < 200 ms bajo concurrencia normal. | Medir con `wrk` o load tester bajo 100 concurrent users. |
| **SE-001** | **Seguridad (Security):** Confidencialidad: Aislamiento multi-tenant por `id_empresa` en el 100% de consultas. | Auditar `% de consultas que filtran por id_empresa`. |
| **RE-001** | **Reliability (Reliability):** Manejo de desconexiones abruptas en sockets TCP con timeout en `writer.wait_closed()` (timeout 2.0s). | Probar desconexión forzada durante operación activa. |
| **MA-001** | **Mantenibilidad (Maintainability):** Modularidad estricta: capa HAL desacoplada del parser de texto; servicios desacoplados de rutas FastAPI. | Medir acoplamiento (lack of cohesion in methods) por debajo de threshold. |
| **PO-001** | **Portabilidad (Portability):** WServer empaquetado en binario autocontenido (PyInstaller one-file). | Compilar WServer y verificar independencia de Python en máquina destino. |

### 4. Matriz de Trazabilidad (Legacy Requirement → SDD Spec ID)

| ID Legacy | Tipo | Descripción | ID SDD | Prioridad | Estado |
|-----------|------|-------------|--------|-----------|--------|
| RULE-001 | LOGIC | Peso báscula nunca se edita | FR-SDD-002 | MUST | Mapeado |
| RULE-015 | LOGIC | Bloqueo dual boleto PENDIENTE | FR-SDD-010 | MUST | Mapeado |
| GAP-001 | KNOWLEDGE | Hora de captura sin zona horaria definida | PF-001 (parcial) | MEDIUM | Pendiente definir |
| DT-010 | COMPLIANCE | ISO/IEC 17025 requiere inmutabilidad metrológica | SE-001 | CRITICAL | Mapeado |
| DT-005 | LOGIC | Regla "solo admin puede anular boleto CERRADO" | FR-SDD-015 | MUST | Mapeado |

## Buenas Prácticas

1. **Siempre priorizar con RFC 2119:** Usar MUST, SHOULD, MAY de manera consistente y documentar el porqué de cada nivel de prioridad.
2. **Formato Gherkin estricto:** Todo criterio de aceptación debe seguir `Given/When/Then` para ser consumible por frameworks de testing (Behave, Cucumber).
3. **Trazabilidad inversa:** Cada requisito SDD debe rastrearse hacia atrás al menos una regla legacy (`RULE-XXX`) o indicar claramente que es nuevo (`NEW-XXX`).
4. **Validación con stakeholders:** Revisar requisitos críticos (MUST) con el equipo de dominio antes de congelar la especificación.
5. **Consistencia con ISO/IEC 25010:** Cada requisito no funcional debe alinearse a al menos un atributo de calidad de la norma 25010.

## Limitaciones

1. Requiere input estructurado del skill `legacy-ingest`. No funciona con análisis libres o texto suelto.
2. La calidad del output depende directamente de la exhaustividad del análisis legacy.
3. Puede generar requisitos redundantes si el legacy tenía superposición de reglas no detectadas.

## Ejemplo de Uso

```bash
# Ejecutar skill con output del legacy-ingest
/sdd-spec-transform "output_del_legacy_ingest"

# Resultado esperado: Documento SRS formal con:
# - Propósito y alcance definidos
# - 10-15 requisitos funcionales con prioridad RFC 2119
# - 5-7 requisitos no funcionales ISO/IEC 25010
# - Matriz trazabilidad Legacy↔SDD
```
