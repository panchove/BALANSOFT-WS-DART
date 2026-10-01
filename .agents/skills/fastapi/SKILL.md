---
name: fastapi
description: Desarrollo del backend FastAPI de BALANSOFT-WS. Usar para endpoints, servicios, autenticación, autorización, sincronización, validación y lógica empresarial.
---

# BALANSOFT-WS FastAPI Skill

## Arquitectura

Preferir:

API Router
→ Service
→ Repository
→ Database

## Router

El router debe encargarse principalmente de:

- recibir request;
- validar schema;
- obtener contexto autenticado;
- llamar al service;
- devolver response.

No colocar lógica empresarial compleja en routers.

## Service

Los services contienen reglas de negocio.

Ejemplos:

- creación de pesaje;
- cierre de boleto;
- anulación;
- sincronización;
- reversión de Kardex;
- validación de licencia.

## Repository

Los repositories manejan persistencia.

No colocar reglas empresariales complejas en repositories.

## Seguridad

Nunca confiar en datos sensibles proporcionados directamente por Flutter.

Especialmente:

- id_empresa;
- user_id;
- roles;
- permisos;
- balances;
- estados de licencia.

## Tenant

El tenant efectivo debe proceder del contexto autenticado.

## Validación

Usar Pydantic para validar entrada y salida.

No confiar exclusivamente en validación del cliente.

## Transacciones

Operaciones críticas deben ser transaccionales.

Especialmente:

- cierre de pesaje;
- movimientos Kardex;
- anulaciones;
- sincronización;
- modificaciones de inventario.

## Idempotencia

Los endpoints de sincronización deben poder recibir una operación repetida sin duplicar información.

## Errores

Utilizar respuestas HTTP coherentes.

No exponer:

- stack traces;
- SQL;
- secretos;
- información interna.

## Cambios

Antes de crear un endpoint:

1. buscar endpoint existente;
2. revisar schemas;
3. revisar service;
4. revisar repository;
5. revisar migraciones;
6. revisar tests.