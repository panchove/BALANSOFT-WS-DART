---
name: offline-sync
description: Motor de sincronización offline-first de BALANSOFT-WS. Usar para colas de eventos locales, resolución de conflictos, idempotencia y reconciliación entre la estación de pesaje y el servidor central.
---

# BALANSOFT-WS Offline-First & Sync Skill

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 42001 / ISO/IEC 25010
**Fuente:** Sistema BALANSOFT-WS
**Autor:** Lead Architect


## Principios Fundamentales

1. **Operación Continua Offline**: La estación de pesaje debe ser capaz de emitir boletos, registrar camiones y operar sin conexión a Internet o al servidor central.
2. **Cola de Sincronización Local**: Toda mutación en offline se encola en SQLite / base local con estado `PENDIENTE` e identificador único idempotente (UUIDv4).
3. **Idempotencia**: Todas las peticiones de sincronización enviadas al servidor deben usar claves de deduplicación / idempotencia para tolerar reintentos en redes inestables sin duplicar boletos ni asientos de Kardex.

## Flujo de Reconciliación

```
[Estación Local] -> Captura Pesaje -> Persiste Localmente (CERRADO) -> Cola Sync
                                                                          |
                                                                          v (Cuando hay red)
[Servidor Central] <- Procesa con dedup_key <- Envía Lote Sync
       |
       +--> Éxito: Servidor responde 200 OK -> Local marca evento como SINCRONIZADO
       +--> Conflicto: Se resuelve según la regla Last-Write-Wins para catálogos y append-only inmutable para boletos de pesaje
```

## Invariantes de Seguridad y Negocio en Sincronización

- **Boletos Inmutables**: Los boletos cerrados no se sobreescriben en el servidor; su sincronización es de tipo append-only.
- **Series Transaccionales**: El correlativo de numeración de serie se asigna localmente bajo el rango reservado de la estación para evitar colisiones de numeración con otras estaciones.
- **Auditoría de Eventos**: Cada paquete de sincronización registra timestamp UTC (ISO 8601), usuario responsable y versión de esquema.