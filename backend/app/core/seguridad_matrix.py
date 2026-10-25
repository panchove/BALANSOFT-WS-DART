"""Matriz de seguridad por defecto: módulos de la estación × roles.

Fuente: docs/ARCH.md ("Seguridad y Accesos") y decisión del equipo.
Roles locales: ADMIN, OPERADOR, AUDITOR (CHECK de balansoft-ws-local.sql).
Acceso: ``ver`` | ``editar`` | ``ninguno``.

Cuando no existe un registro en ``permisos_acceso`` para un (rol, módulo),
se usa el valor de esta matriz. La pantalla "Seguridad y Accesos" permite a
ADMIN sobrescribirla por empresa (la sobrescritura se persiste en la tabla).
"""

from __future__ import annotations

# Claves alineadas con el índice de `_pages`/`_claveAIndice` del home_shell.
MODULOS: dict[str, str] = {
    "inicio": "Inicio",
    "terceros": "Terceros",
    "clientes": "Clientes",
    "proveedores": "Proveedores",
    "usuarios": "Usuarios del Sistema",
    "camiones": "Camiones / Vehículos",
    "conductores": "Conductores",
    "transportes": "Empresas de Transporte",
    "categorias": "Categorías",
    "productos": "Productos",
    "almacenes": "Almacenes",
    "kardex": "Kardex",
    "entradas": "Ingresos (Entradas)",
    "salidas": "Despachos (Salidas)",
    "ingresos": "Ingresos",
    "despachos": "Despachos",
    "reportes": "Reportes Generales",
    "dispositivos": "Dispositivos de Campo",
    "seguridad": "Seguridad y Accesos",
    "documentos_empresa": "Empresa y Documentos",
    "diseno_ticket": "Diseño de Ticket",
    "configuracion": "Configuración General",
    "ajustes_inventario": "Ajustes de Inventario",
    "auditoria": "Auditoría del Sistema",
    "conceptos_inventario": "Conceptos de Inventario",
    "roles": "Roles",
    "reportes_diarios": "Reportes Diarios",
    "reportes_mensuales": "Reportes Mensuales",
    "reportes_personalizado": "Reporte Personalizado",
}

ROLES_LOCALES: tuple[str, ...] = ("ADMIN", "OPERADOR", "AUDITOR")

ACCESOS_VALIDOS: tuple[str, ...] = ("ver", "editar", "ninguno")

# Matriz por defecto: rol -> módulo -> acceso.
MATRIZ_DEFECTO: dict[str, dict[str, str]] = {
    "ADMIN": {m: "editar" for m in MODULOS},
    "OPERADOR": {
        "inicio": "editar",
        "terceros": "editar",
        "clientes": "editar",
        "proveedores": "editar",
        "usuarios": "ninguno",
        "camiones": "editar",
        "conductores": "editar",
        "transportes": "editar",
        "categorias": "editar",
        "productos": "editar",
        "almacenes": "editar",
        "kardex": "ver",
        "entradas": "editar",
        "salidas": "editar",
        "ingresos": "ver",
        "despachos": "ver",
        "reportes": "editar",
        "dispositivos": "ninguno",
        "seguridad": "ninguno",
        "documentos_empresa": "ninguno",
        "diseno_ticket": "editar",
        "configuracion": "ninguno",
        "ajustes_inventario": "editar",
        "auditoria": "ninguno",
        "conceptos_inventario": "editar",
        "roles": "ninguno",
        "reportes_diarios": "editar",
        "reportes_mensuales": "editar",
        "reportes_personalizado": "editar",
    },
    "AUDITOR": {
        "inicio": "editar",
        "terceros": "ver",
        "clientes": "ver",
        "proveedores": "ver",
        "usuarios": "ver",
        "camiones": "ver",
        "conductores": "ver",
        "transportes": "ver",
        "categorias": "ver",
        "productos": "ver",
        "almacenes": "ver",
        "kardex": "ver",
        "entradas": "ver",
        "salidas": "ver",
        "ingresos": "ver",
        "despachos": "ver",
        "reportes": "editar",
        "dispositivos": "ninguno",
        "seguridad": "ninguno",
        "documentos_empresa": "ver",
        "diseno_ticket": "ver",
        "configuracion": "ninguno",
        "ajustes_inventario": "ninguno",
        "auditoria": "ver",
        "conceptos_inventario": "ver",
        "roles": "ver",
        "reportes_diarios": "editar",
        "reportes_mensuales": "editar",
        "reportes_personalizado": "editar",
    },
}
