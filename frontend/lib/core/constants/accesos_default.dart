import 'package:flutter/material.dart';

/// Matriz de Seguridad y Accesos por defecto (espejo de
/// `backend/app/core/seguridad_matrix.py`). El backend es autoridad: si hay una
/// sobrescritura perseguida, el repositorio la usa; aquí vive el fallback para
/// modo offline / primera carga.
///
/// Acceso: `ver` | `editar` | `ninguno`.
class AccesosDefault {
  static const List<String> roles = ['ADMIN', 'OPERADOR', 'AUDITOR', 'TRABAJADOR'];

  /// Clave de módulo → (título).
  static const Map<String, String> modulos = {
    'inicio': 'Inicio',
    'terceros': 'Terceros',
    'usuarios': 'Usuarios del Sistema',
    'camiones': 'Camiones / Vehículos',
    'conductores': 'Conductores',
    'transportes': 'Empresas de Transporte',
    'categorias': 'Categorías',
    'productos': 'Productos',
    'almacenes': 'Almacenes',
    'kardex': 'Kardex',
    'entradas': 'Ingresos (Entradas)',
    'salidas': 'Despachos (Salidas)',
    'reportes': 'Inventario (Stock Físico)',
    'dispositivos': 'Dispositivos de Campo',
    'seguridad': 'Seguridad y Accesos',
    'documentos_empresa': 'Empresa y Documentos',
    'configuracion': 'Configuración General',
  };

  /// Icono por módulo (para la tabla de accesos).
  static IconData iconoDe(String modulo) {
    return switch (modulo) {
      'inicio' => Icons.dashboard_outlined,
      'terceros' => Icons.people_outline,
      'usuarios' => Icons.admin_panel_settings_outlined,
      'camiones' => Icons.directions_car_outlined,
      'conductores' => Icons.badge_outlined,
      'transportes' => Icons.fire_truck_outlined,
      'categorias' => Icons.category_outlined,
      'productos' => Icons.inventory_2_outlined,
      'almacenes' => Icons.warehouse_outlined,
      'kardex' => Icons.table_rows_outlined,
      'entradas' => Icons.arrow_downward_outlined,
      'salidas' => Icons.arrow_upward_outlined,
      'reportes' => Icons.inventory_outlined,
      'dispositivos' => Icons.sensors_outlined,
      'seguridad' => Icons.lock_outline,
      'documentos_empresa' => Icons.business_outlined,
      'configuracion' => Icons.settings_outlined,
      _ => Icons.circle_outlined,
    };
  }

  /// Ruta del módulo en el sidebar (último nodo hoja visible = índice).
  static int indiceDe(String modulo) {
    return switch (modulo) {
      'inicio' => 0,
      'terceros' => 1,
      'usuarios' => 2,
      'camiones' => 3,
      'conductores' => 4,
      'transportes' => 5,
      'categorias' => 6,
      'productos' => 7,
      'almacenes' => 8,
      'kardex' => 9,
      'entradas' => 10,
      'salidas' => 11,
      'reportes' => 12,
      'dispositivos' => 13,
      'seguridad' => 14,
      'documentos_empresa' => 15,
      'configuracion' => 16,
      _ => -1,
    };
  }

  /// Matriz por defecto: rol → módulo → acceso.
  static const Map<String, Map<String, String>> _matriz = {
    'ADMIN': {
      'inicio': 'editar', 'terceros': 'editar', 'usuarios': 'editar',
      'camiones': 'editar', 'conductores': 'editar', 'transportes': 'editar',
      'categorias': 'editar', 'productos': 'editar', 'almacenes': 'editar',
      'kardex': 'editar', 'entradas': 'editar', 'salidas': 'editar',
      'reportes': 'editar', 'dispositivos': 'editar', 'seguridad': 'editar',
      'documentos_empresa': 'editar', 'configuracion': 'editar',
    },
    'OPERADOR': {
      'inicio': 'editar', 'terceros': 'editar', 'usuarios': 'ninguno',
      'camiones': 'editar', 'conductores': 'editar', 'transportes': 'editar',
      'categorias': 'editar', 'productos': 'editar', 'almacenes': 'editar',
      'kardex': 'ver', 'entradas': 'editar', 'salidas': 'editar',
      'reportes': 'editar', 'dispositivos': 'ninguno', 'seguridad': 'ninguno',
      'documentos_empresa': 'ninguno', 'configuracion': 'ninguno',
    },
    'AUDITOR': {
      'inicio': 'editar', 'terceros': 'ver', 'usuarios': 'ver',
      'camiones': 'ver', 'conductores': 'ver', 'transportes': 'ver',
      'categorias': 'ver', 'productos': 'ver', 'almacenes': 'ver',
      'kardex': 'ver', 'entradas': 'ver', 'salidas': 'ver',
      'reportes': 'editar', 'dispositivos': 'ninguno', 'seguridad': 'ninguno',
      'documentos_empresa': 'ver', 'configuracion': 'ninguno',
    },
    'TRABAJADOR': {
      'inicio': 'ver', 'terceros': 'ninguno', 'usuarios': 'ninguno',
      'camiones': 'ninguno', 'conductores': 'ninguno', 'transportes': 'ninguno',
      'categorias': 'ninguno', 'productos': 'ninguno', 'almacenes': 'ninguno',
      'kardex': 'ninguno', 'entradas': 'ninguno', 'salidas': 'ninguno',
      'reportes': 'ninguno', 'dispositivos': 'ninguno', 'seguridad': 'ninguno',
      'documentos_empresa': 'ninguno', 'configuracion': 'ninguno',
    },
  };

  /// Acceso por defecto de `rol` al `modulo`. Si el módulo no existe en la
  /// clave (usuario heredado sin set), devuelve `ninguno` para no exponerlo.
  static String acceso(String rol, String modulo) {
    return _matriz[rol]?[modulo] ?? 'ninguno';
  }

  /// Roles que pueden ver el módulo (acceso distinto de `ninguno`).
  static Set<String> rolesQueVen(String modulo) {
    return roles
        .where((r) => acceso(r, modulo) != 'ninguno')
        .toSet();
  }
}