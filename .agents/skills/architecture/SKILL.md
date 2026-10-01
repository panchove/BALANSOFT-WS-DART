---
name: architecture
description: Arquitectura y diseño técnico de BALANSOFT-WS. Usar para cambios estructurales, nuevos módulos, decisiones de diseño, separación de responsabilidades y coordinación entre Flutter, FastAPI, PostgreSQL y sincronización offline.
---

# BALANSOFT-WS Architecture Skill

## Objetivo

Mantener una arquitectura modular, mantenible y escalable para BALANSOFT-WS.

Stack principal:

- Flutter / Dart
- FastAPI / Python
- PostgreSQL
- SQLite / sqflite
- REST API
- JWT
- Offline-first
- Synchronization Engine
- Ed25519

## Reglas

Antes de modificar arquitectura:

1. Inspeccionar el código existente.
2. Buscar implementaciones similares.
3. Identificar dependencias entre módulos.
4. Evitar duplicación.
5. Mantener compatibilidad con las capas existentes.
6. Aplicar el cambio mínimo necesario.

## Flutter

Preferir:

presentation
→ application
→ domain
→ data
→ infrastructure

No colocar lógica empresarial compleja dentro de widgets.

Los widgets deben encargarse principalmente de:

- presentación
- interacción
- navegación
- estado visual

## Backend

Preferir:

router
→ service
→ repository
→ database

Los routers no deben contener lógica empresarial compleja.

## Base de datos

PostgreSQL es la fuente de verdad del servidor.

SQLite es almacenamiento operativo local para Flutter.

Nunca asumir que SQLite y PostgreSQL son idénticos.

## Comunicación

Flutter NO debe acceder directamente a PostgreSQL.

La comunicación debe pasar por la API.

## Nuevos módulos

Antes de crear un módulo:

- comprobar si ya existe;
- comprobar si puede extenderse;
- comprobar si existe una abstracción equivalente.

No crear clases duplicadas.

## Cambios críticos

Los cambios que afecten:

- pesajes
- Kardex
- sincronización
- autenticación
- multi-tenancy
- licencias

deben analizarse transversalmente antes de implementarse.

## Resultado esperado

Toda decisión arquitectónica debe favorecer:

1. integridad
2. seguridad
3. mantenibilidad
4. testabilidad
5. offline-first
6. rendimiento