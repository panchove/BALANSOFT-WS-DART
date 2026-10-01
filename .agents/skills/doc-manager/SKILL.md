---
name: doc-manager
description: Crea, actualiza y mantiene la documentación técnica, de código y de arquitectura del proyecto BALANSOFT-WS-DART. Úsala cuando el usuario pida documentar funciones, actualizar archivos README, documentar endpoints, cambios de versión (CHANGELOG) o diagramas.
---

# Documentation Manager Skill

## Descripción
Esta skill proporciona estándares y flujos de trabajo para redactar, actualizar y mantener al día toda la documentación técnica del sistema (Dart, APIs, bases de datos y arquitectura).

## Cuándo usar esta skill
- Al agregar nuevas funcionalidades, modelos o endpoints que requieran actualizar la documentación existente.
- Al generar comentarios de código estructurados (Dartdoc) para clases, funciones y componentes.
- Al redactar o actualizar archivos `README.md`, `CHANGELOG.md` o manuales técnicos del proyecto.
- Al revisar que los cambios en el código reflejen con precisión la arquitectura documentada.

## Estándares de Documentación

### 1. Documentación en Código (Dartdoc)
- Usa triple barra `///` para documentar clases, métodos públicos y propiedades.
- Incluye `@param` o descripciones de argumentos y valor de retorno (`[Returns]`).
- Ejemplo:
  ```dart
  /// Calcula el peso neto restando la tara del peso bruto.
  ///
  /// Retorna un [double] con el valor del peso neto en kilogramos.
  /// Lanza un [ArgumentError] si la tara es mayor al peso bruto.
  double calculateNetWeight(double gross, double tare) { ... }