---
name: mssql
description: Arquitectura y soporte de Microsoft SQL Server en BALANSOFT-WS. Usar para detección de motor por prefijo de DATABASE_URL, modo degradado de Fase 1, caché de esquema (TTL 60s), drivers ODBC y suites de pruebas MSSQL.
---

# BALANSOFT-WS Microsoft SQL Server (MSSQL) Skill

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 42001 / ISO/IEC 25010
**Fuente:** Sistema BALANSOFT-WS
**Autor:** Lead Architect


## 1. Principio y Contrato Arquitectónico (Fase 1)

Ubicación del núcleo: `src/backend/app/core/db_engine.py`  
Referencia documental: `docs/MANEJO_DB.md §11.5`

- **Detección Única por Prefijo**: El motor se decide **exclusivamente** por el prefijo de `DATABASE_URL` (sin variables de entorno adicionales):
  - `postgresql+asyncpg://` → PostgreSQL (Modo estándar de producción).
  - `mssql+aioodbc://` → Microsoft SQL Server (Fase 1: Modo degradado).
- **Derivación Sync Automática**: Si `DATABASE_URL_SYNC` no está definida o es incoherente, se deriva en memoria automáticamente (`mssql+pyodbc://`).
- **Validación `_coherencia_motores`**: Garantiza que el par async/sync pertenezca a la misma familia de motores (`postgresql` o `sqlserver`).

---

## 2. Modo Degradado y Respuestas 503

En Fase 1, el WServer arranca contra SQL Server sin aplicar DDL de esquema (el DDL formal se aplica en Fase 2):

| Condición                 | Código de Respuesta       | Payload / Código de Error                                                                                                                              |
|:--------------------------|:--------------------------|:-------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Esquema no aplicado**   | `503 Service Unavailable` | `{"codigo": "esquema_mssql_pendiente", "mensaje": "El esquema de SQL Server se aplicará en Fase 2; el WServer funciona en modo degradado sin datos."}` |
| **Sin conexión a la BD**  | `503 Service Unavailable` | `{"codigo": "sqlserver_sin_conexion", "mensaje": "No se pudo conectar a SQL Server. Verifica la base de datos y la URL DATABASE_URL."}`                |
| **Falta de Drivers ODBC** | `503 Service Unavailable` | `{"codigo": "sqlserver_sin_drivers", "mensaje": "Faltan drivers ODBC..."}` (El WServer sigue vivo sin abortar)                                         |

*Nota Crítica:* La ruta de PostgreSQL no captura estos errores; cualquier excepción en PostgreSQL se propaga produciendo el `500 Internal Server Error` habitual.

---

## 3. Caché de Estado de Esquema (TTL 60s)

Para no saturar el servidor SQL Server con consultas de verificación de tablas:
- **`_estado`**: `"pendiente"` (con expiración a los 60 segundos) o `"aplicado"` (pegajoso mientras no expire).
- **`marcar_estado_esquema(estado)`**: Siembra la caché en memoria.
- **`reiniciar_estado_esquema()`**: Reinicia la caché al estado inicial y resetea la bandera de drivers faltantes.

---

## 4. Instalación de Drivers y Dependencias

Para entornos con soporte de SQL Server:
```bash
# Sincronizar el grupo extra de sqlserver con uv
cd src/backend && uv sync --extra sqlserver
```
Requiere a nivel de sistema operativo:
- Linux: `unixodbc-dev` y Microsoft ODBC Driver for SQL Server (msodbcsql17 o msodbcsql18).
- Librerías Python involucradas: `aioodbc` (async) y `pyodbc` (sync).

---

## 5. Ejecución de Pruebas MSSQL (T8)

Las 3 pruebas de integración de SQL Server (N1 esquema/idempotencia/paridad + N2 flujo funcional de serie, monthly y peso_rango) se ejecutan mediante:

```bash
cd src/backend
MSSQL_TEST_URL_SYNC="mssql+pyodbc://sa:Password123@localhost:1433/balansoft_test?driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes" \
uv run pytest -m mssql
```

*Nota:* Si `MSSQL_TEST_URL_SYNC` no está configurada, los tests marcados con `@pytest.mark.mssql` se omiten automáticamente (`skipped`) sin fallar la suite general de backend.