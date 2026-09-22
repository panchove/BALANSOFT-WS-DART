"""Matriz de seguridad por defecto: módulos de la estación × roles.

Fuente: docs/ARCH.md ("Seguridad y Accesos") y decisión del equipo.
Roles locales: ADMIN, OPERADOR, AUDITOR, TRABAJADOR (CHECK de balansoft-ws-local.sql).
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
    "reportes": "Inventario (Stock Físico)",
    "dispositivos": "Dispositivos de Campo",
    "seguridad": "Seguridad y Accesos",
    "documentos_empresa": "Empresa y Documentos",
    "configuracion": "Configuración General",
}

ROLES_LOCALES: tuple[str, ...] = ("ADMIN", "OPERADOR", "AUDITOR", "TRABAJADOR")

ACCESOS_VALIDOS: tuple[str, ...] = ("ver", "editar", "ninguno")

# Matriz por defecto: rol -> módulo -> acceso.
MATRIZ_DEFECTO: dict[str, dict[str, str]] = {
    "ADMIN": {m: "editar" for m in MODULOS},
    "OPERADOR": {
        "inicio": "editar",
        "terceros": "editar",
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
        "reportes": "editar",
        "dispositivos": "ninguno",
        "seguridad": "ninguno",
        "documentos_empresa": "ninguno",
        "configuracion": "ninguno",
    },
    "AUDITOR": {
        "inicio": "editar",
        "terceros": "ver",
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
        "reportes": "editar",
        "dispositivos": "ninguno",
        "seguridad": "ninguno",
        "documentos_empresa": "ver",
        "configuracion": "ninguno",
    },
    "TRABAJADOR": {
        "inicio": "ver",
        "terceros": "ninguno",
        "usuarios": "ninguno",
        "camiones": "ninguno",
        "conductores": "ninguno",
        "transportes": "ninguno",
        "categorias": "ninguno",
        "productos": "ninguno",
        "almacenes": "ninguno",
        "kardex": "ninguno",
        "entradas": "ninguno",
        "salidas": "ninguno",
        "reportes": "ninguno",
        "dispositivos": "ninguno",
        "seguridad": "ninguno",
        "documentos_empresa": "ninguno",
        "configuracion": "ninguno",
    },
}
