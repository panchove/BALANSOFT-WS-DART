---
description: Analiza ACTUAR.md y AGENTS.md, verifica el estado actual del proyecto y ejecuta únicamente las tareas pendientes.
---

# Update All Command

Cuando el usuario ejecute `/update-all`, sigue estrictamente este flujo de trabajo:

## 1. Lectura de Fuentes
Lee detenidamente el contenido de los siguientes archivos en la raíz del proyecto:
- `ACTUAR.md`
- `AGENTS.md`

## 2. Verificación y Comparación (Auditoría previa)
Antes de realizar cualquier modificación, analiza el estado actual del código y del proyecto para verificar qué elementos de la lista ya han sido cumplidos o implementados:
- Inspecciona los archivos, clases, funciones, componentes o configuraciones del sistema relevantes.
- Compara lo que se solicita en `ACTUAR.md` y `AGENTS.md` contra la implementación real en el código base.
- Identifica y descarta las tareas que **ya estén completamente resueltas o integradas**.

## 3. Reporte de Diagnóstico
Presenta un resumen breve en la consola clasificando los ítems:
- **Cumplidos:** Tareas que ya están implementadas (no se modifican).
- **Pendientes:** Tareas que faltan por realizar o requieren ajustes.

## 4. Ejecución
Procede a implementar o actualizar **únicamente** los ítems identificados como **Pendientes**, asegurando no duplicar trabajo ni romper lo que ya está funcional.