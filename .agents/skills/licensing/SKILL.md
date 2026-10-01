---
name: licensing
description: Sistema de licencias Ed25519 para BALANSOFT-WS. Usar para validación criptográfica, estaciones autorizadas, expiración y funcionalidades licenciadas.
---

# BALANSOFT-WS Licensing Skill

## Objetivo

Validar criptográficamente que una estación posee una licencia válida.

## Criptografía

El sistema utiliza Ed25519.

La aplicación cliente puede verificar firmas mediante una clave pública.

La clave privada de firma NUNCA debe estar dentro de Flutter.

## License Payload

Una licencia puede contener información equivalente a:

- license_id;
- id_empresa;
- station_id;
- issued_at;
- expires_at;
- features;
- version;
- metadata.

No modificar el formato existente sin compatibilidad/migración.

## Validación

La validación debe comprobar:

1. estructura;
2. firma;
3. identidad;
4. empresa;
5. estación;
6. expiración;
7. funcionalidades;
8. integridad del payload.

## Fecha

No confiar exclusivamente en una fecha manipulable por el cliente.

Cuando el diseño del sistema lo requiera, utilizar información del servidor o mecanismo equivalente.

## Revocación

Si existe infraestructura de revocación, la aplicación debe respetar su estado.

## Seguridad

Nunca:

- incluir private key en Flutter;
- hardcodear secretos;
- aceptar una licencia solo porque el JSON tiene formato válido;
- desactivar validación desde una flag fácilmente modificable.

## Offline

Si BALANSOFT-WS debe funcionar offline, la licencia debe contener la información mínima necesaria para validación local.

## Backend

El servidor debe realizar su propia validación.

Nunca asumir que una validación realizada por Flutter es suficiente.

## Testing

Probar:

- licencia válida;
- firma inválida;
- licencia modificada;
- estación incorrecta;
- empresa incorrecta;
- licencia expirada;
- feature no autorizada.