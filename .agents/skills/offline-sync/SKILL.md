---
name: offline-sync
description: Motor Offline-First y sincronización Flutter ↔ FastAPI/PostgreSQL de BALANSOFT-WS. Usar para colas, reintentos, idempotencia, conflictos y sincronización incremental.
---

# BALANSOFT-WS Offline Sync Skill

## Objetivo

Permitir que BALANSOFT-WS continúe funcionando cuando no existe conexión.

## Principio

LOCAL FIRST.

Una operación crítica no debe depender de Internet para ser registrada localmente.

## Flujo

Operación:

Flutter
→ SQLite
→ Sync Queue
→ API
→ PostgreSQL

## Estados

Una operación puede utilizar estados equivalentes a:

pending
processing
synced
failed
retry

No modificar nombres existentes sin revisar compatibilidad.

## Idempotencia

Cada operación debe tener un identificador único.

Ejemplo:

operation_id UUID

Si la misma operación llega dos veces:

NO crear dos registros.

## Reintentos

Los errores temporales deben poder reintentarse.

Preferir backoff progresivo.

No realizar loops infinitos agresivos.

## Errores permanentes

Una operación inválida debe quedar registrada como fallo y proporcionar información suficiente para diagnóstico.

## Sincronización

La sincronización debe soportar:

- conexión perdida;
- reconexión;
- timeout;
- respuesta duplicada;
- servidor temporalmente indisponible;
- operación ya procesada.

## Conflictos

No sobrescribir silenciosamente información crítica.

Los conflictos deben tener una estrategia determinista.

## Pesajes

Un pesaje local debe conservar:

- UUID;
- empresa;
- estación;
- timestamp;
- valores;
- operador;
- estado;
- operation_id;
- estado de sincronización.

## Seguridad

Nunca confiar en que los datos locales son autorizados.

El servidor debe validar nuevamente las reglas críticas.

## Backend

El endpoint de sincronización debe ser idempotente.

## Testing

Probar obligatoriamente:

- duplicados;
- retry;
- pérdida de red;
- sincronización parcial;
- conflicto;
- operación ya sincronizada.