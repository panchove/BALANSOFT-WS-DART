---
name: testing
description: Estrategia de pruebas para BALANSOFT-WS. Usar para unit tests, integration tests, sincronización, multi-tenant, Kardex, pesaje, licencias y regresiones.
---

# BALANSOFT-WS Testing Skill

## Objetivo

Evitar regresiones y proteger reglas críticas del sistema.

## Antes de cambiar

Buscar tests existentes relacionados.

No crear duplicados innecesarios.

## Flutter

Probar:

- domain;
- repositories;
- servicios;
- estado;
- sincronización;
- UI crítica.

## FastAPI

Probar:

- endpoints;
- services;
- autorización;
- tenant isolation;
- errores;
- transacciones.

## Database

Probar:

- constraints;
- relaciones;
- migraciones;
- operaciones transaccionales.

## Offline Sync

Debe probar:

- operación offline;
- cola;
- retry;
- duplicado;
- idempotencia;
- conflicto;
- recuperación de red.

## Weighing

Probar:

- lectura;
- tara;
- bruto;
- neto;
- estabilidad;
- cierre;
- anulación.

## Kardex

Probar:

- entrada;
- salida;
- reversión;
- doble reversión;
- rollback.

## Multi-Tenant

Debe existir prueba de aislamiento:

tenant A no puede acceder a tenant B.

## Licensing

Probar firmas:

- válidas;
- inválidas;
- payload modificado;
- expiradas;
- estación incorrecta.

## Regresión

Después de modificar una función crítica:

1. ejecutar tests específicos;
2. ejecutar tests relacionados;
3. ejecutar suite general cuando sea razonable.

## No ocultar errores

No modificar tests simplemente para hacerlos pasar.

Si cambia el comportamiento esperado, documentar la razón.