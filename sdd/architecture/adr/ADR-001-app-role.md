# ADR-001 - Routers Condicionales por APP_ROLE

**Estado:** Aprobado  
**Fecha:** 2026-10-19  
**Autor:** Lead Architect  
**Norma:** ISO/IEC/IEEE 42010

## Contexto

El proyecto BALANSOFT-WS requiere desplegar la misma base de código FastAPI en dos roles distintos:
- **`local`**: Estación operativa (boletos, catálogos, login offline)
- **`server`**: Central de cuenta/licencia/sync/panel

Inicialmente se consideró mantener dos repositorios separados, pero se decidió en favor de un solo repositorio por las siguientes razones:

- Un solo repo, un solo `main.py`, un solo `pytest`
- Migrable a paquetes separados cuando la organización lo requiera
- Menor overhead de mantenimiento y despliegue

## Decision

Implementar una sola base de código FastAPI con routers condicionales basados en la variable de entorno `APP_ROLE` en `.env`:

```python
# backend/app/main.py (resumen)
from app.core.config import settings

app = FastAPI()

# Routers comunes (siempre)
app.include_router(auth_router, prefix="/api/v1/auth")
app.include_router(health_router, prefix="/api/v1")

# Routers solo en modo server
if settings.app_role == "server":
    app.include_router(panel_router, prefix="/api/v1/panel")
    app.include_router(licencias_router, prefix="/api/v1/licencias")
    app.include_router(sync_server_router, prefix="/api/v1/sync")

# Routers solo en modo local
if settings.app_role == "local":
    app.include_router(weighing_router, prefix="/api/v1/weighing")
    app.include_router(catalogo_router, prefix="/api/v1/catalogo")
    app.include_router(flota_router, prefix="/api/v1/flota")
    app.include_router(inventario_router, prefix="/api/v1/inventario")
    app.include_router(directorio_router, prefix="/api/v1/directorio")
    app.include_router(reports_router, prefix="/api/v1/reports")
    app.include_router(kardex_router, prefix="/api/v1/kardex")
    app.include_router(sync_local_router, prefix="/api/v1/sync")
```

## Consecuencias

### Consecuencias Positivas

1. **Mantenimiento reducido**: Un solo repositorio, un solo punto de entrada
2. **Migrabilidad**: Fácil transición a paquetes separados cuando crezca el proyecto
3. **Consistencia**: Mismo código base, comportamiento diferente según rol
4. **Tests unificados**: Same `pytest` suite corria contra ambos roles

### Consecuencias Negativas

1. **Condición `if` en `main.py`**: Debe mantenerse consistente; riesgo de olvidar incluir un router en el rol incorrecto
2. **Complejidad de configuración**: Los desarrolladores deben recordar setear `APP_ROLE` correctamente en `.env`
3. **Documentación necesaria**: Es crucial documentar qué routers van en cada rol

### Mitigaciones

- **Checks en CI**: Pruebas automatizadas que verifican que `APP_ROLE=local` monta `API_ROUTERS` y `APP_ROLE=server` monta `SERVER_ROUTERS`
- **README documentación**: Documentar claramente qué routers van en cada rol (ver `constitution.md §5`)
- **Revisiones de código**: Requerir revisión en cualquier cambio de `main.py` que afecte los routers

## Relación con Otros Artefactos

- **Refinamiento por**: Visión Lógica (`architecture/views/logical-view.md`)
- **Restricción de**: Constitución (`constitution.md §6`)
- **Documentado en**: ADR-001-xxx.md (este archivo)
- **Trazado a**: `FR-SDD-010` (modo offline), `REQ-NF-ONB-010` (modo estación)