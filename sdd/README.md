# SDD - Spec-Driven Development Documentation

## Overview

This directory contains the Spec-Driven Development (SDD) artifacts for the BALANSOFT-WS industrial weighing system, structured in accordance with ISO/IEC/IEEE standards:

- **ISO/IEC/IEEE 29148** - Software Requirements Engineering
- **ISO/IEC/IEEE 42010** - Architecture Description
- **ISO/IEC/IEEE 1016** - Software Design Description
- **ISO/IEC/IEEE 12207** - Software Life Cycle Processes

## Structure

```
sdd/
├── README.md                  # Este archivo - descripción general y mapa de normas ISO
├── constitution.md            # Principios rectores del proyecto
├── stakeholders.md            # Partes interesadas y sus preocupaciones
├── architecture/              # Documentación de arquitectura (ISO 42010)
│   ├── overview.md
│   ├── views/                 # Una vista por viewpoint
│   │   └── logical-view.md
│   ├── correspondences.md     # Correspondencias entre vistas
│   └── adr/                   # Registros de decisiones arquitectónicas
│       └── ADR-001-xxx.md
├── specs/                     # Especificaciones de funcionalidades (fuente única de verdad)
│   ├── 001-gestion-pesajes/   # Gestión de pesajes (FR-SDD-001 a FR-SDD-005)
│   │   ├── spec.md
│   │   ├── design.md
│   │   └── tasks.md
│   ├── 002-series-numeracion/ # Series y numeración (FR-SDD-006 a FR-SDD-007)
│   │   ├── spec.md
│   │   ├── design.md
│   │   └── tasks.md
│   └── 003-catalogos-y-permisos/ # Catálogos y permisos (FR-SDD-008 a FR-SDD-012)
│       ├── spec.md
│       ├── design.md
│       └── tasks.md
└── traceability-matrix.md     # Matriz de trazabilidad global (requisitos → diseño → tareas)
```

## Normas ISO Aplicadas

| Norma | Enfoque | Reflejado en |
|-------|---------|--------------|
| **ISO/IEC/IEEE 29148** | Ingeniería de requisitos | Identificadores `REQ-xxx`, requisitos verificables, trazas a stakeholders |
| **ISO/IEC/IEEE 42010** | Descripción de arquitectura | Partes interesadas, concerns, viewpoints, correspondencias, rationale |
| **ISO/IEC/IEEE 1016** | Diseño de software | Matriz de trazabilidad de requisitos, descomposición, interfaces |
| **ISO/IEC/IEEE 12207** | Ciclo de vida software | Tareas mapeadas a actividades, cadena completa de trazabilidad |

## Uso

- **Lectores humanos**: Consulte `README.md` → `constitution.md` → `stakeholders.md` para contexto
- **Lectores IA**: Todos los archivos contienen metadatos `id`, `traces_to`, `traces_from` para auto-resolución
- **Actualizaciones**: Cuando se añada un nuevo requisito, cree `spec.md` → `design.md` → `tasks.md` y actualice `traceability-matrix.md`

## Migración de Documentos Legacy

Los documentos originales en `docs/sdd/` han sido analizados y clasificados en esta nueva estructura. El contenido importante ha sido preservado y reorganizado según los estándares ISO. Cualquier elemento no clasificado ha sido movido a `sdd/_inbox/` para revisión.