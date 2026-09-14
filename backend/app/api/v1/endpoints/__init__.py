"""Agregador de routers de la API v1."""

from app.api.v1.endpoints import (
    archivos,
    auth,
    catalogo,
    directorio,
    exports,
    flota,
    inventario,
    pesajes,
    reports,
    sync,
)

API_ROUTERS = [
    archivos.router,
    auth.router,
    catalogo.router,
    flota.router,
    inventario.router,
    directorio.router,
    pesajes.router,
    sync.router,
    reports.router,
    exports.router,
]