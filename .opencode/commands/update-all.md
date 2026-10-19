---
description: Analiza TODO.md y AGENTS.md, verifica el estado actual del proyecto y ejecuta únicamente las tareas pendientes.
---

# Update All Command

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 42001 / ISO/IEC 25010
**Fuente:** Sistema BALANSOFT-WS
**Autor:** Lead Architect


Cuando el usuario ejecute `/update-all`, sigue estrictamente este flujo de trabajo:

## 1. Lectura de Fuentes
Lee detenidamente el contenido de los siguientes archivos en la raíz del proyecto:
- `TODO.md`
- `AGENTS.md`

## 2. Verificación y Comparación (Auditoría previa)
Antes de realizar cualquier modificación, analiza el estado actual del código y del proyecto para verificar qué elementos de la lista ya han sido cumplidos o implementados:
- Inspecciona los archivos, clases, funciones, componentes o configuraciones del sistema relevantes.
- Compara lo que se solicita en `TODO.md` y `AGENTS.md` contra la implementación real en el código base.
- Identifica y descarta las tareas que **ya estén completamente resueltas o integradas**.

## 2.5. Repaso Cruzado PRD.md ↔ TODO.md (Validación Ligera)
Extrae los elementos críticos de `PRD.md` (roles de negocio, reglas obligatorias, fórmulas principales) y verifica su menciones en `TODO.md`:
- **Roles**: Busca `ADMIN`, `AUDITOR`, `OPERADOR` en `PRD.md` y verifica si `TODO.md` los tiene como referencia en sus ítems de permisos o arquitectura.
- **Reglas críticas**: Revisa si `PRD.md` tiene reglas "no hacer" (ej. "no borrar columna X", "siempre incluir `id_empresa`") y si `TODO.md` las tiene registradas como pendientes o recordatorios.
- **Fórmulas/álgoritmos**: Si `PRD.md` define fórmulas clave (ej. fórmulas de peso, tolerancias), verifica si `TODO.md` las tiene documentadas o como tarea de validación.
- **Resultado**: Reporta si hay coincidencias, brechas (PRD.md menciona algo que TODO.md ignora) o divergencias. Esto es **solo informativo**; no bloquea la ejecución de tareas.

## 3. Reporte de Diagnóstico
Presenta un resumen breve en la consola clasificando los ítems:
- **Cumplidos:** Tareas que ya están implementadas (no se modifican).
- **Pendientes:** Tareas que faltan por realizar o requieren ajustes.

## 4. Ejecución
Procede a implementar o actualizar **únicamente** los ítems identificados como **Pendientes**, asegurando no duplicar trabajo ni romper lo que ya está funcional.