---
name: postgresql
description: PostgreSQL y diseño de base de datos para BALANSOFT-WS. Usar para tablas, relaciones, índices, constraints, transacciones y migraciones.
---

# BALANSOFT-WS PostgreSQL Skill

## Principio

PostgreSQL es la fuente de verdad del backend.

## Integridad

Preferir restricciones de base de datos cuando protejan reglas fundamentales.

Usar:

- PRIMARY KEY
- FOREIGN KEY
- UNIQUE
- CHECK
- NOT NULL
- índices

cuando corresponda.

## Multi-Tenant

Las entidades pertenecientes a una empresa deben conservar:

id_empresa UUID

Las consultas tenant-scoped deben filtrar correctamente.

## UUID

Preferir UUID para entidades distribuidas/offline cuando el sistema ya utilice UUID.

## Fechas

Conservar timestamps consistentes.

Preferir timestamps con timezone cuando corresponda.

## Transacciones

Usar transacciones para operaciones que modifiquen múltiples registros relacionados.

Ejemplo:

boleto
+
movimiento Kardex
+
auditoría

deben mantener consistencia.

## Kardex

Nunca eliminar movimientos históricos solamente para representar una anulación.

Preferir movimientos compensatorios/reversiones.

## Índices

Crear índices basados en patrones reales de consulta.

Especialmente para:

- id_empresa;
- created_at;
- updated_at;
- synchronization state;
- operation_id;
- foreign keys.

No crear índices indiscriminadamente.

## Migraciones

Toda modificación estructural debe tener migración.

Nunca asumir que modificar el modelo Python modifica PostgreSQL automáticamente.

## Seguridad

Nunca guardar:

- contraseñas en texto plano;
- tokens completos;
- claves privadas Ed25519.

## Antes de modificar

Revisar:

- modelos;
- migrations;
- foreign keys;
- queries;
- índices;
- tests.