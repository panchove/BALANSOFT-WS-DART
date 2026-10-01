---
name: security
description: Seguridad de BALANSOFT-WS. Usar para JWT, autorización, secretos, tenant isolation, validación de entrada, auditoría y protección de datos.
---

# BALANSOFT-WS Security Skill

## Principio

Nunca confiar en el cliente.

Flutter es un cliente no confiable.

FastAPI es responsable de aplicar las reglas de seguridad.

## Autenticación

Validar:

- token;
- firma;
- expiración;
- usuario;
- sesión cuando corresponda.

## Autorización

Autenticación != autorización.

Después de autenticar se debe comprobar si el usuario puede realizar la operación.

## Tenant

El tenant efectivo debe derivarse del contexto autenticado.

## Input

Validar toda entrada recibida desde:

- Flutter;
- API;
- sincronización;
- dispositivos;
- archivos.

## SQL

Nunca construir consultas SQL inseguras mediante concatenación de datos no confiables.

Usar ORM/query parameters según el stack existente.

## Secrets

Nunca almacenar en Git:

- passwords;
- JWT secrets;
- API keys;
- private keys;
- production credentials.

## Logs

Nunca registrar:

- contraseñas;
- tokens completos;
- claves privadas;
- secretos.

## Errores

No revelar internals innecesarios.

Evitar devolver:

- SQL;
- stack traces;
- filesystem paths;
- secretos.

## Licencias

La validación de licencia debe ser independiente de controles puramente visuales del cliente.

## Auditoría

Registrar acciones sensibles cuando corresponda:

- login;
- cambios de permisos;
- anulaciones;
- cambios de configuración;
- licencias;
- operaciones administrativas.

## Testing

Probar:

- token inválido;
- token expirado;
- usuario sin permisos;
- cross-tenant;
- input inválido;
- replay/idempotencia.