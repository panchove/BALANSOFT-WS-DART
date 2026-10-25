import 'package:flutter/material.dart';

/// Matriz de Seguridad y Accesos por defecto (espejo de
/// `backend/app/core/seguridad_matrix.py`). El backend es autoridad: si hay una
/// sobrescritura perseguida, el repositorio la usa; aquí vive el fallback para
/// modo offline / primera carga.
///
/// Acceso: `ver` | `editar` | `ninguno`.
class AccesosDefault {
  static const List<String> roles = ['ADMIN', 'OPERADOR', 'AUDITOR'];

  /// Clave de módulo → (título).
  static const Map<String, String> modulos = {
    'inicio': 'Inicio',
    'terceros': 'Terceros',
    'clientes': 'Clientes',
    'proveedores': 'Proveedores',
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
    'ingresos': 'Ingresos',
    'despachos': 'Despachos',
    'reportes': 'Reportes Generales',
    'dispositivos': 'Dispositivos de Campo',
    'dispositivos_basculas': 'Básculas',
    'dispositivos_indicadores': 'Indicadores',
    'dispositivos_semaforos': 'Semáforos',
    'dispositivos_barreras': 'Barreras de tránsito',
    'dispositivos_camaras': 'Cámaras',
    'dispositivos_impresoras': 'Impresoras',
    'seguridad': 'Seguridad y Accesos',
    'documentos_empresa': 'Empresa y Documentos',
    'diseno_ticket': 'Diseño de Ticket',
    'configuracion': 'Configuración General',
    'ajustes_inventario': 'Ajustes de Inventario',
    'auditoria': 'Auditoría del Sistema',
    'conceptos_inventario': 'Conceptos de Inventario',
    'roles': 'Roles',
    'reportes_diarios': 'Reportes Diarios',
    'reportes_mensuales': 'Reportes Mensuales',
    'reportes_personalizado': 'Reporte Personalizado',
  };

  /// Icono por módulo (para la tabla de accesos).
  static IconData iconoDe(String modulo) {
    return switch (modulo) {
      'inicio' => Icons.dashboard_outlined,
      'terceros' => Icons.people_outline,
      'clientes' => Icons.handshake_outlined,
      'proveedores' => Icons.local_shipping_outlined,
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
      'ingresos' => Icons.arrow_downward_outlined,
      'despachos' => Icons.arrow_upward_outlined,
      'reportes' => Icons.analytics_outlined,
      'dispositivos' => Icons.sensors_outlined,
      'dispositivos_basculas' => Icons.scale_outlined,
      'dispositivos_indicadores' => Icons.straighten_outlined,
      'dispositivos_semaforos' => Icons.traffic_outlined,
      'dispositivos_barreras' => Icons.door_sliding,
      'dispositivos_camaras' => Icons.photo_camera_outlined,
      'dispositivos_impresoras' => Icons.print_outlined,
      'seguridad' => Icons.lock_outline,
      'documentos_empresa' => Icons.business_outlined,
      'diseno_ticket' => Icons.receipt_long_outlined,
      'configuracion' => Icons.settings_outlined,
      'ajustes_inventario' => Icons.tune,
      'auditoria' => Icons.fact_check_outlined,
      'conceptos_inventario' => Icons.rule_folder_outlined,
      'roles' => Icons.badge_outlined,
      'reportes_diarios' => Icons.today_outlined,
      'reportes_mensuales' => Icons.calendar_month_outlined,
      'reportes_personalizado' => Icons.date_range_outlined,
      _ => Icons.circle_outlined,
    };
  }

  /// Ruta del módulo en el sidebar (último nodo hoja visible = índice).
  static int indiceDe(String modulo) {
    return switch (modulo) {
      'inicio' => 0,
      'terceros' => 1,
      'clientes' => 18,
      'proveedores' => 19,
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
      'dispositivos_basculas' => 13,
      'dispositivos_indicadores' => 27,
      'dispositivos_semaforos' => 28,
      'dispositivos_barreras' => 31,
      'dispositivos_camaras' => 29,
      'dispositivos_impresoras' => 30,
      'seguridad' => 14,
      'documentos_empresa' => 15,
      'configuracion' => 16,
      'diseno_ticket' => 17,
      'ingresos' => 20,
      'despachos' => 21,
      'conceptos_inventario' => 22,
      'roles' => 23,
      'reportes_diarios' => 24,
      'reportes_mensuales' => 25,
      'reportes_personalizado' => 26,
      _ => -1,
    };
  }

  /// Matriz por defecto: rol → módulo → acceso.
  static const Map<String, Map<String, String>> _matriz = {
    'ADMIN': {
      'inicio': 'editar', 'terceros': 'editar', 'usuarios': 'editar',
      'clientes': 'editar', 'proveedores': 'editar',
      'camiones': 'editar', 'conductores': 'editar', 'transportes': 'editar',
      'categorias': 'editar', 'productos': 'editar', 'almacenes': 'editar',
      'kardex': 'editar', 'entradas': 'editar', 'salidas': 'editar',
      'ingresos': 'editar', 'despachos': 'editar',
      'reportes': 'editar', 'dispositivos': 'editar', 'seguridad': 'editar',
      'dispositivos_basculas': 'editar', 'dispositivos_indicadores': 'editar',
      'dispositivos_semaforos': 'editar', 'dispositivos_barreras': 'editar', 'dispositivos_camaras': 'editar',
      'dispositivos_impresoras': 'editar',
      'documentos_empresa': 'editar', 'diseno_ticket': 'editar',
      'configuracion': 'editar', 'ajustes_inventario': 'editar',
      'auditoria': 'editar', 'conceptos_inventario': 'editar',
      'roles': 'editar',
      'reportes_diarios': 'editar', 'reportes_mensuales': 'editar',
      'reportes_personalizado': 'editar',
    },
    'OPERADOR': {
      'inicio': 'editar', 'terceros': 'editar', 'usuarios': 'ninguno',
      'clientes': 'editar', 'proveedores': 'editar',
      'camiones': 'editar', 'conductores': 'editar', 'transportes': 'editar',
      'categorias': 'editar', 'productos': 'editar', 'almacenes': 'editar',
      'kardex': 'ver', 'entradas': 'editar', 'salidas': 'editar',
      'ingresos': 'ver', 'despachos': 'ver',
      'reportes': 'editar', 'dispositivos': 'ninguno', 'seguridad': 'ninguno',
      'dispositivos_basculas': 'ninguno', 'dispositivos_indicadores': 'ninguno',
      'dispositivos_semaforos': 'ninguno', 'dispositivos_barreras': 'ver', 'dispositivos_camaras': 'ninguno',
      'dispositivos_impresoras': 'ninguno',
      'documentos_empresa': 'ninguno', 'diseno_ticket': 'editar',
      'configuracion': 'ninguno', 'ajustes_inventario': 'editar',
      'auditoria': 'ninguno', 'conceptos_inventario': 'editar',
      'roles': 'ninguno',
      'reportes_diarios': 'editar', 'reportes_mensuales': 'editar',
      'reportes_personalizado': 'editar',
    },
    'AUDITOR': {
      'inicio': 'editar', 'terceros': 'ver', 'usuarios': 'ver',
      'clientes': 'ver', 'proveedores': 'ver',
      'camiones': 'ver', 'conductores': 'ver', 'transportes': 'ver',
      'categorias': 'ver', 'productos': 'ver', 'almacenes': 'ver',
      'kardex': 'ver', 'entradas': 'ver', 'salidas': 'ver',
      'ingresos': 'ver', 'despachos': 'ver',
      'reportes': 'editar', 'dispositivos': 'ninguno', 'seguridad': 'ninguno',
      'dispositivos_basculas': 'ninguno', 'dispositivos_indicadores': 'ninguno',
      'dispositivos_semaforos': 'ninguno', 'dispositivos_barreras': 'ver', 'dispositivos_camaras': 'ninguno',
      'dispositivos_impresoras': 'ninguno',
      'documentos_empresa': 'ver', 'diseno_ticket': 'ver',
      'configuracion': 'ninguno', 'ajustes_inventario': 'ninguno',
      'auditoria': 'ver', 'conceptos_inventario': 'ver',
      'roles': 'ver',
      'reportes_diarios': 'editar', 'reportes_mensuales': 'editar',
      'reportes_personalizado': 'editar',
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