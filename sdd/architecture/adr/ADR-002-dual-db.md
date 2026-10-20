# ADR-002 - Arquitectura de Dos Bases de Datos (Server/Local)

**Estado:** Aprobado  
**Fecha:** 2026-10-19  
**Autor:** Lead Architect  
**Norma:** ISO/IEC/IEEE 42010, ISO/IEC 29148

## Contexto

El modelo original de BALANSOFT-WS tenía una única base de datos (`balansoft_ws`) con todas las tablas: cuentas, licencias, dispositivos, boletos, kardex, catálogos, etc. Esta arquitectura no garantizaba el aislamiento multi-tenant ni la operación offline-first, que son requisitos críticos para el nuevo modelo.

## Decision

Separar la base de datos en dos instancias independientes:

| Base de Datos        | Propiedad           | Responsabilidad Principal                                                      | Tecnología                        |
|----------------------|---------------------|--------------------------------------------------------------------------------|-----------------------------------|
| `balansoft_ws`       | Proveedor / Central | Cuentas, licencias, dispositivos, sincronización, panel del proveedor          | PostgreSQL 15+                    |
| `balansoft_ws_local` | Máquina del cliente | Usuarios locales, flota, inventario, boletos, kardex, auditoría, configuración | PostgreSQL 15+ o SQLite (offline) |

**Regla fundamental:** Una máquina local = una empresa = una cuenta. El `id_empresa` se resuelve del JWT del usuario autenticado.

## Consecuencias

### Consecuencias Positivas

1. **Aislamiento multi-tenant nativo**: `id_empresa` en toda consulta, filtro, inserción, validación. Ningún dato de una empresa está disponible para otra.
2. **Operación offline garantizada**: Capa SQLite local + cola de sync (`sync_queue`) permite operar sin internet. Gracia de 7 días (`OFFLINE_GRACE_DAYS=7`) tras expiración de licencia DEMO.
3. **Escalabilidad independiente**: La central no depende de que las estaciones estén conectadas. Scalability vertical independiente de cada BD.
4. **Seguridad mejorada**: Filtro obligatorio `id_empresa` previene fugas de datos entre empresas en todas las operaciones.

### Consecuencias Negativas

1. **Complejidad de sincronización**: Es necesario mantener la consistencia bidireccional entre `balansoft_ws` y `balansoft_ws_local`.
2. **Duplicación de catálogos**: Algunos catálogos (marcas, transportes, productos) existen en ambas BDs, requiriendo sincronización.
3. **Complexidad de desarrollo**: Los desarrolladores deben estar conscientes de cuál BD está operando según el `APP_ROLE`.
4. **Migración para clientes existentes**: Clientes con la arquitectura single-DB requieren script de migración.

### Mitigaciones

- **Sincronización bidireccional Fase 2** (roadmap): Implementar `sync/push` y `sync/pull` completos con resolución de conflictos (último timestamp gana).
- **Vistas/materialized views**: Para catálogos compartidos, usar vistas que reflejen datos del central en la local.
- **Script de migración**: `scripts/migrate_to_split.sql` para clientes que necesiten migrar de single-DB a split-DB.
- **Tests automatizados**: `tests/test_api_server.py` cubre 6 tests sobre modo server y local.
- **Identidad local**: Modelo `IdentidadLocal` (singleton `id=true`) + `GET/PUT /api/v1/identity` para administración best-effort.

## Relación con Otros Artefactos

- **Refinamiento por**: Visión Lógica (`architecture/views/logical-view.md`), Constitución (`constitution.md §5`)
- **Restricción de**: Constitución (`constitution.md §4`), Stakeholders (`stakeholders.md`)
- **Documentado en**: ADR-002-xxx.md (este archivo)
- **Trazado a**: `REQ-NF-SEG-001` (aislamiento multi-tenant), `REQ-NF-ONB-010` (modo estación), `REQ-NF-REL-001` (manejo desconexiones)