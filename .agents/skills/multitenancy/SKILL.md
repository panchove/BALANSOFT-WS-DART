---
name: multitenancy
description: Aislamiento multi-tenant de BALANSOFT-WS mediante id_empresa, JWT, autorización y consultas seguras.
---

# BALANSOFT-WS Multi-Tenant Skill

## Objetivo

Garantizar aislamiento absoluto entre empresas.

## Tenant

La empresa efectiva debe derivarse del contexto autenticado.

No confiar en:

id_empresa enviado por Flutter.

## JWT

El contexto autenticado puede proporcionar información necesaria para determinar:

- usuario;
- empresa;
- roles;
- permisos.

Validar siempre el token en backend.

## Consultas

Toda consulta sobre datos tenant-scoped debe aplicar aislamiento.

Ejemplo conceptual:

WHERE id_empresa = current_tenant

## Crear recursos

El backend debe asignar el tenant autorizado.

No permitir que el cliente fuerce otro tenant.

## Modificar recursos

Antes de modificar:

1. localizar recurso;
2. comprobar tenant;
3. comprobar autorización;
4. ejecutar modificación.

## Eliminar

Las eliminaciones deben validar tenant y permisos.

Para información histórica crítica, preferir soft-delete/anulación cuando corresponda al dominio.

## Cross-Tenant

Un usuario de empresa A nunca debe poder:

- leer empresa B;
- modificar empresa B;
- eliminar empresa B;
- sincronizar datos de empresa B.

## Testing

Debe existir al menos una prueba explícita que demuestre:

Empresa A ≠ Empresa B.

Intentos de acceso cruzado deben fallar.

## Auditoría

Registrar acciones sensibles con contexto de empresa.