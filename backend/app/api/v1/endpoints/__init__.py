"""Agregador de routers de la API v1.

``API_ROUTERS``: estación local (APP_ROLE=local) — operación normal.
``SERVER_ROUTERS``: servidor central (APP_ROLE=server) — cuenta, licencia,
credenciales globales, panel del proveedor y recepción de sync.
"""

from app.api.v1.endpoints import (
    archivos,
    auth,
    catalogo,
    config,
    directorio,
    empresa,
    entorno,
    exports,
    flota,
    identity,
    inventario,
    pesajes,
    reports,
    seguridad,
    series,
    servidor,
    sync,
    usuarios,
)

API_ROUTERS = [
    archivos.router,
    auth.router,
    catalogo.router,
    config.router,
    empresa.router,
    entorno.router,
    flota.router,
    inventario.router,
    directorio.router,
    pesajes.router,
    sync.router,
    reports.router,
    exports.router,
    identity.router,
    usuarios.router,
    seguridad.router,
    series.router,
]

SERVER_ROUTERS = [
    servidor.router,
    entorno.router,
]
