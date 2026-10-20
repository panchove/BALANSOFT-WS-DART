"""Agregador de routers de la API v1.

``API_ROUTERS``: estación local (APP_ROLE=local) — operación normal.
``SERVER_ROUTERS``: servidor central (APP_ROLE=server) — cuenta, licencia,
credenciales globales, panel del proveedor y recepción de sync.

Versión: 0.4.2-dev.56
Fecha: 2026-10-19
Estado: Vigente
Norma: ISO/IEC 25010 / ISO/IEC 27001
Fuente: Sistema BALANSOFT-WS
Autor: Lead Architect
"""

from app.api.v1.endpoints import (
    activacion,
    archivos,
    auditoria,
    auth,
    backups,
    catalogo,
    config,
    directorio,
    empresa,
    entorno,
    exports,
    flota,
    identity,
    inventario,
    notificaciones,
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
    auditoria.router,
    auth.router,
    backups.router,
    catalogo.router,
    config.router,
    empresa.router,
    entorno.router,
    flota.router,
    inventario.router,
    directorio.router,
    pesajes.router,
    sync.router,
    activacion.router,
    reports.router,
    exports.router,
    identity.router,
    usuarios.router,
    seguridad.router,
    series.router,
    notificaciones.router,
    notificaciones.router_recordatorios,
]

SERVER_ROUTERS = [
    servidor.router,
    entorno.router,
]
