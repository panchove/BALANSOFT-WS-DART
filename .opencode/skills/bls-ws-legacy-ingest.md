---
name: legacy-ingest
description: Auditar y descomponer documentación obsoleta o fragmentada identificando lógica de negocio oculta, incoherencias y vacíos de información.
---
# Legacy Ingest Skill

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 29148 / ISO/IEC 25010
**Fuente:** Sistema BALANSOFT-WS (Legacy Analysis)
**Autor:** Legacy2SDD Translator

## Objetivo

Auditar y descomponer documentación obsoleta, código legado, esquemas de base de datos antiguos o cualquier artefacto de documentación fragmentada para extraer reglas de negocio implícitas, identificar incoherencias y señalar vacíos de información que deben ser cubiertos en la nueva especificación SDD.

## Ámbito de Análisis

El skill está diseñado para procesar los siguientes tipos de entradas legacy:

1. **Documentación Técnica:** Manuales de usuario obsoletos, documentos de diseño arquitectónico desactualizados, diagramas de flujo sin mantener.
2. **Código Fuente Legacy:** Stored Procedures legacy, clases monolíticas, implementaciones spaghetti, código sin tests.
3. **Esquemas de Base de Datos:** Diagramas E-R antiguos, migraciones sin documentar, scripts de creación de BD sin versionar.
4. **Comentarios de Código:** Javadoc/Docstrings antiguos, comentarios que describen lógica de negocio crítica.

## Proceso de Ingestión

### Paso 1: Reconocimiento de Artefactos
- Listado de todos los archivos/documentos procesados con metadatos (líneas, tipo, fecha última modificación).
- Identificación de formatos mezclados (.md, .docx, .sql, .pdf).

### Paso 2: Extracción de Reglas de Negocio
- Patrones de negocio recurrentes identificados como `RULE-XXX`.
- Lógica de flujo crítica: cálculos, validaciones, estados de transición.
- Mapeo de entidades a sus atributos y restricciones.

### Paso 3: Detección de Ambigüedades y Vacíos (Gaps)
- Comportamientos no documentados o contradictorios.
- `GAP-XXX: [descripción] + [impacto en SDD]`.
- Ejemplos típicos:
  - Validación de campos omitidos en formularios legacy.
  - Estados de transición no documentados (ej. PENDIENTE → MODIFICADO → ANULADO).
  - Reglas de negocio implícitas (ej. "el peso de báscula nunca se edita").

### Paso 4: Mapa de Deuda Técnica y Riesgos
- Clasificación por criticidad: `CRITICAL`/`HIGH`/`MEDIUM`/`LOW`.
- Clasificación por tipo: `ARCHITECTURAL`/`LOGIC`/`KNOWLEDGE`/`COMPLIANCE`.
- Ejemplos:
  - `CRITICAL/ARCHITECTURAL`: Falta de multi-tenant en 40% de consultas.
  - `HIGH/LOGIC`: Lógica de kardex con movimiento inverso en anulación no documentada.
  - `MEDIUM/KNOWLEDGE`: Regla de negocio "solo admin puede anular boleto CERRADO" implícita en código.

## Output Estructurado (ISO/IEC 29148 compliant)

El skill retorna un documento estructurado con:

1. **Resumen de Artefactos Analizados:**
   - Total de archivos procesados.
   - Rangos de líneas/characters por archivo.
   - Fechas de creación/última modificación.

2. **Matriz de Reglas de Negocio Extraídas:**
   | ID Regla | Descripción                   | Origen           | Criticidad | Comentario                |
   |----------|-------------------------------|------------------|------------|---------------------------|
   | RULE-001 | Peso báscula nunca se edita   | CODE/legacy.py   | CRITICAL   | Validado en ISO/IEC 17025 |
   | RULE-015 | Bloqueo dual boleto PENDIENTE | CODE/migrations/ | HIGH       | Reglas anti-duplicidad    |

3. **Ambigüedades y Puntos Ciegos (Gaps):**
   | ID Gap  | Descripción                                | Impacto SDD                   | Prioridad |
   |---------|--------------------------------------------|-------------------------------|-----------|
   | GAP-001 | Hora de captura sin zona horaria definida  | Requerir timestamp UTC en SDD | HIGH      |
   | GAP-015 | Tolerancia comercial no definida en legacy | Definir porcentaje en SDD     | MEDIUM    |

4. **Mapa de Deuda Técnica y Riesgos Detectados:**
   | ID Deuda | Tipo       | Descripción                                      | Recomendación SDD             | Criticidad |
   |----------|------------|--------------------------------------------------|-------------------------------|------------|
   | DT-001   | KNOWLEDGE  | "Modo offline > 30 días bloquea operaciones"     | Documentar en SDD specs       | MEDIUM     |
   | DT-010   | COMPLIANCE | ISO/IEC 17025 requiere inmutabilidad metrológica | Validar en sdd-spec-transform | CRITICAL   |

## Buenas Prácticas

1. **Siempre documentar la fuente:** Anotar siempre el archivo/origen de cada regla extraída.
2. **Validar con dueños del sistema:** Confirmar reglas de negocio con personal técnico original cuando sea posible.
3. **Fotografiar el "conocimiento tácito":** Capturar reglas que solo residen en la memoria de operadores veteranos.
4. **Clasificar por criticidad:** Usar siempre la misma escala de criticidad para consistencia con otros skills del flujo SDD.

## Limitaciones

1. No puede inferir reglas que estén completamente ausentes del documentation legacy.
2. Dependiente de la calidad del documento original: documentación muy fragmentada reduce la precisión del análisis.
3. No cubre lógica ejecutada en runtime que no esté documentada en ningúnder archivo estático.

## Ejemplo de Uso

```bash
# Ejecutar skill sobre archivo legacy
/legacy-ingest /ruta/archivo/legacy_stored_procedure.sql

# Resultado esperado: Matriz RULE-XXX, GAP-XXX, DT-XXX estructurada
```
