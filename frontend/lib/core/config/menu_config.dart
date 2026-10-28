import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../constants/accesos_default.dart';

// ─── Catálogo de iconos (nombre → IconData) ────────────────────────────
//
// El `menu.json` no puede llevar `IconData`, así que nombra los iconos como
// `dashboard_outlined`. Nombre desconocido ⇒ icono de respaldo (no truena).

class MenuIconos {
  MenuIconos._();

    static const Map<String, IconData> mapa = {
    // ── Navegación / general ──
    'dashboard': Icons.dashboard,
    'dashboard_outlined': Icons.dashboard_outlined,
    'home': Icons.home,
    'home_outlined': Icons.home_outlined,
    'menu': Icons.menu,
    'apps': Icons.apps,
    'grid_view': Icons.grid_view,
    'widgets_outlined': Icons.widgets_outlined,

    // ── Operación / Gestión ──
    'smart_toy': Icons.smart_toy,
    'smart_toy_outlined': Icons.smart_toy_outlined,
    'edit_note': Icons.edit_note,
    'edit': Icons.edit,
    'edit_outlined': Icons.edit_outlined,
    'note_add_outlined': Icons.note_add_outlined,
    'create_new_folder_outlined': Icons.create_new_folder_outlined,
    'point_of_sale_outlined': Icons.point_of_sale_outlined,
    'tune': Icons.tune,
    'tune_outlined': Icons.tune,
    'build': Icons.build,
    'build_outlined': Icons.build_outlined,
    'engineering_outlined': Icons.engineering_outlined,
    'settings_backup_restore_outlined': Icons.settings_backup_restore_outlined,

    // ── Terceros / gente ──
    'people': Icons.people,
    'people_outline': Icons.people_outline,
    'handshake': Icons.handshake,
    'handshake_outlined': Icons.handshake_outlined,
    'person': Icons.person,
    'person_outline': Icons.person_outline,
    'person_add_outlined': Icons.person_add_outlined,
    'groups_outlined': Icons.groups_outlined,
    'group': Icons.group,
    'group_outlined': Icons.group_outlined,
    'badge': Icons.badge,
    'badge_outlined': Icons.badge_outlined,

    // ── Flota ──
    'local_shipping': Icons.local_shipping,
    'local_shipping_outlined': Icons.local_shipping_outlined,
    'directions_car': Icons.directions_car,
    'directions_car_outlined': Icons.directions_car_outlined,
    'directions_bus_outlined': Icons.directions_bus_outlined,
    'fire_truck': Icons.fire_truck,
    'fire_truck_outlined': Icons.fire_truck_outlined,
    'flight_outlined': Icons.flight_outlined,

    // ── Inventario ──
    'warehouse': Icons.warehouse,
    'warehouse_outlined': Icons.warehouse_outlined,
    'rule_folder': Icons.rule_folder,
    'rule_folder_outlined': Icons.rule_folder_outlined,
    'inventory': Icons.inventory,
    'inventory_2': Icons.inventory_2,
    'inventory_2_outlined': Icons.inventory_2_outlined,
    'category': Icons.category,
    'category_outlined': Icons.category_outlined,
    'storefront': Icons.storefront,
    'storefront_outlined': Icons.storefront_outlined,
    'move_to_inbox': Icons.move_to_inbox,
    'move_to_inbox_outlined': Icons.move_to_inbox_outlined,
    'outbox': Icons.outbox,
    'outbox_outlined': Icons.outbox_outlined,
    'filter_alt_outlined': Icons.filter_alt_outlined,
    'table_rows': Icons.table_rows,
    'table_rows_outlined': Icons.table_rows_outlined,
    'list_alt': Icons.list_alt,
    'list_alt_outlined': Icons.list_alt_outlined,

    // ── Reportes ──
    'bar_chart': Icons.bar_chart,
    'bar_chart_outlined': Icons.bar_chart_outlined,
    'pie_chart_outline': Icons.pie_chart_outline,
    'show_chart_outlined': Icons.show_chart_outlined,
    'assessment_outlined': Icons.assessment_outlined,
    'analytics': Icons.analytics,
    'analytics_outlined': Icons.analytics_outlined,
    'trending_up_outlined': Icons.trending_up_outlined,
    'trending_down_outlined': Icons.trending_down_outlined,
    'timeline_outlined': Icons.timeline_outlined,
    'today': Icons.today,
    'today_outlined': Icons.today_outlined,
    'calendar_month': Icons.calendar_month,
    'calendar_month_outlined': Icons.calendar_month_outlined,
    'date_range': Icons.date_range,
    'date_range_outlined': Icons.date_range_outlined,
    'arrow_downward': Icons.arrow_downward,
    'arrow_downward_outlined': Icons.arrow_downward_outlined,
    'arrow_upward': Icons.arrow_upward,
    'arrow_upward_outlined': Icons.arrow_upward_outlined,
    'swap_vert_outlined': Icons.swap_vert_outlined,
    'fact_check': Icons.fact_check,
    'fact_check_outlined': Icons.fact_check_outlined,
    'checklist_outlined': Icons.checklist_outlined,
    'task_alt_outlined': Icons.task_alt_outlined,

    // ── Seguridad / mantenimiento ──
    'settings': Icons.settings,
    'settings_outlined': Icons.settings_outlined,
    'admin_panel_settings': Icons.admin_panel_settings,
    'admin_panel_settings_outlined': Icons.admin_panel_settings_outlined,
    'lock': Icons.lock,
    'lock_outline': Icons.lock_outline,
    'lock_outlined': Icons.lock_outlined,
    'lock_open_outlined': Icons.lock_open_outlined,
    'key_outlined': Icons.key_outlined,
    'vpn_key_outlined': Icons.vpn_key_outlined,
    'security_outlined': Icons.security_outlined,
    'shield_outlined': Icons.shield_outlined,
    'verified_user': Icons.verified_user,
    'verified_user_outlined': Icons.verified_user_outlined,

    // ── Dispositivos / hardware ──
    'sensors': Icons.sensors,
    'sensors_outlined': Icons.sensors_outlined,
    'usb_outlined': Icons.usb_outlined,
    'wifi_outlined': Icons.wifi_outlined,
    'lan_outlined': Icons.lan_outlined,
    'bluetooth_outlined': Icons.bluetooth_outlined,
    'print_outlined': Icons.print_outlined,
    'print': Icons.print,
    'traffic': Icons.traffic,
    'traffic_outlined': Icons.traffic_outlined,
    'photo_camera': Icons.photo_camera,
    'photo_camera_outlined': Icons.photo_camera_outlined,
    'camera_alt': Icons.camera_alt,
    'camera_alt_outlined': Icons.camera_alt_outlined,
    'videocam_outlined': Icons.videocam_outlined,
    'scale': Icons.scale,
    'scale_outlined': Icons.scale_outlined,
    'speed_outlined': Icons.speed_outlined,
    'straighten': Icons.straighten,
    'straighten_outlined': Icons.straighten_outlined,
    'door_sliding': Icons.door_sliding,
    'door_sliding_outlined': Icons.door_sliding_outlined,
    'memory_outlined': Icons.memory_outlined,
    'developer_board_outlined': Icons.developer_board_outlined,
    'dns_outlined': Icons.dns_outlined,
    'router_outlined': Icons.router_outlined,
    'monitor_outlined': Icons.monitor_outlined,
    'desktop_windows_outlined': Icons.desktop_windows_outlined,
    'laptop_mac_outlined': Icons.laptop_mac_outlined,
    'phone_iphone_outlined': Icons.phone_iphone_outlined,
    'tablet_outlined': Icons.tablet_outlined,
    'battery_full_outlined': Icons.battery_full_outlined,
    'power_settings_new_outlined': Icons.power_settings_new_outlined,

    // ── Empresa / documentos ──
    'business': Icons.business,
    'business_outlined': Icons.business_outlined,
    'apartment_outlined': Icons.apartment_outlined,
    'receipt_long': Icons.receipt_long,
    'receipt_long_outlined': Icons.receipt_long_outlined,
    'receipt_outlined': Icons.receipt_outlined,
    'description_outlined': Icons.description_outlined,
    'article_outlined': Icons.article_outlined,
    'folder_outlined': Icons.folder_outlined,
    'file_copy_outlined': Icons.file_copy_outlined,
    'credit_card_outlined': Icons.credit_card_outlined,
    'payments_outlined': Icons.payments_outlined,
    'attach_money_outlined': Icons.attach_money_outlined,
    'request_quote_outlined': Icons.request_quote_outlined,

    // ── Ayuda / comunicación ──
    'help': Icons.help,
    'help_outline': Icons.help_outline,
    'info': Icons.info,
    'info_outline': Icons.info_outline,
    'info_outlined': Icons.info_outlined,
    'contact_support_outlined': Icons.contact_support_outlined,
    'support_agent': Icons.support_agent,
    'support_agent_outlined': Icons.support_agent_outlined,
    'chat_outlined': Icons.chat_outlined,
    'forum_outlined': Icons.forum_outlined,
    'mail_outlined': Icons.mail_outlined,
    'call_outlined': Icons.call_outlined,
    'campaign_outlined': Icons.campaign_outlined,
    'notifications_none': Icons.notifications_none,
    'notifications_active_outlined': Icons.notifications_active_outlined,
    'menu_book': Icons.menu_book,
    'menu_book_outlined': Icons.menu_book_outlined,
    'public': Icons.public,
    'public_outlined': Icons.public_outlined,
    'play_circle': Icons.play_circle,
    'play_circle_outline': Icons.play_circle_outline,
    'school': Icons.school,
    'school_outlined': Icons.school_outlined,

    // ── Tiempo / sistema ──
    'schedule_outlined': Icons.schedule_outlined,
    'history_outlined': Icons.history_outlined,
    'event_outlined': Icons.event_outlined,
    'timer_outlined': Icons.timer_outlined,
    'storage_outlined': Icons.storage_outlined,

    // ── Diversos útiles ──
    'star_outline': Icons.star_outline,
    'favorite_border': Icons.favorite_border,
    'bookmark_border': Icons.bookmark_border,
    'flag_outlined': Icons.flag_outlined,
    'label_outlined': Icons.label_outlined,
    'search_outlined': Icons.search_outlined,
    'filter_list_outlined': Icons.filter_list_outlined,
    'refresh_outlined': Icons.refresh_outlined,
    'sync_outlined': Icons.sync_outlined,
    'cloud_outlined': Icons.cloud_outlined,
    'cloud_done_outlined': Icons.cloud_done_outlined,
    'cloud_upload_outlined': Icons.cloud_upload_outlined,
    'cloud_download_outlined': Icons.cloud_download_outlined,
    'download_outlined': Icons.download_outlined,
    'upload_outlined': Icons.upload_outlined,
    'share_outlined': Icons.share_outlined,
    'link_outlined': Icons.link_outlined,
    'logout_outlined': Icons.logout_outlined,
    'login_outlined': Icons.login_outlined,
    'exit_to_app_outlined': Icons.exit_to_app_outlined,
    'open_in_new_outlined': Icons.open_in_new_outlined,
    'add_circle_outline': Icons.add_circle_outline,
    'remove_circle_outline': Icons.remove_circle_outline,
    'delete': Icons.delete,
    'delete_outline': Icons.delete_outline,
    'check_circle_outline': Icons.check_circle_outline,
    'error_outline': Icons.error_outline,
    'warning_amber_outlined': Icons.warning_amber_outlined,
  };

  static const IconData _respaldo = Icons.circle_outlined;

  /// Resuelve un nombre del JSON. Devuelve [_respaldo] si no existe, para que
  /// un `menu.json` mal escrito degrade el icono y nunca tire la pantalla.
  static IconData desde(String? nombre) {
    if (nombre == null) return _respaldo;
    return mapa[nombre] ?? _respaldo;
  }

  /// Nombre canónico de un icono (para serializar el árbol a JSON).
  static String? nombreDe(IconData? icono) {
    if (icono == null) return null;
    for (final e in mapa.entries) {
      if (e.value == icono) return e.key;
    }
    return null;
  }

  static List<String> get nombres {
    final l = mapa.keys.toList()..sort();
    return l;
  }
}

// ─── Ubicación del menu.json ───────────────────────────────────────────

/// Mismo contrato de rutas que `StationConfigPaths` (`config.json`):
///
/// - Override de usuario (prioritario): `~/.config/balansoftws/menu.json`
/// - Sistema (opcional): `/etc/balansoftws/menu.json` (Linux),
///   `%ProgramData%\BalansoftWS\menu.json` (Windows).
///
/// Si en ninguna parte existe, la app **siembra** el `menu.json` con el árbol
/// por defecto en el override, para que siempre haya un archivo que editar.
class MenuConfigPaths {
  static String get _home {
    final h = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (h != null && h.isNotEmpty) return h;
    return Directory.current.path;
  }

  /// Inyectable para tests: redirige las rutas reales a un directorio
  /// temporal sin tocar la máquina del desarrollador.
  @visibleForTesting
  static String? pruebasOverrideDir;

  @visibleForTesting
  static String? pruebasSistemaDir;

  static String get overrideDir =>
      pruebasOverrideDir ?? '$_home/.config/balansoftws';

  static String get sistemaDir {
    if (pruebasSistemaDir != null) return pruebasSistemaDir!;
    if (Platform.isWindows) {
      final pd = Platform.environment['ProgramData'];
      if (pd != null && pd.isNotEmpty) return '$pd\\BalansoftWS';
      return 'C:\\ProgramData\\BalansoftWS';
    }
    return '/etc/balansoftws';
  }

  static String get overridePath => '$overrideDir${Platform.pathSeparator}menu.json';

  static String get sistemaPath => '$sistemaDir${Platform.pathSeparator}menu.json';
}

// ─── Modelo de datos ───────────────────────────────────────────────────

class MenuNode {
  final String label;
  final IconData? icon;
  final IconData? activeIcon;
  final String? clave;
  final int? index;
  final List<MenuNode>? children;

  /// Comando de acción para hojas que **no** son páginas del shell (p. ej.
  /// `go:diagnostico`). Si está presente, el shell ejecuta el comando en vez
  /// de cambiar de índice.
  final String? accion;

  /// Etiqueta del atajo mostrado a la derecha (p. ej. `Ctrl + ,`).
  final String? shortcut;

  /// Roles con acceso al módulo (matriz por defecto). Si es `null`, el nodo
  /// (grupo/encabezado) no filtra por rol y depende de sus hijos.
  final Set<String>? rolesPermitidos;
  final bool isSectionHeader;
  final bool isSubItem;

  /// Línea separadora entre opciones (`{"tipo": "separador"}` en el JSON).
  /// No es una hoja: no navega, no filtra y no entra en el bottom bar.
  final bool esSeparador;

  /// Clave i18n explícita (`"i18n": "menu_inicio"`). Si viene, manda sobre el
  /// mapa label→clave; permite etiquetas personalizadas sin reescribir i18n.
  final String? claveI18n;

  const MenuNode({
    required this.label,
    this.icon,
    this.activeIcon,
    this.clave,
    this.index,
    this.children,
    this.accion,
    this.shortcut,
    this.rolesPermitidos,
    this.isSectionHeader = false,
    this.isSubItem = false,
    this.esSeparador = false,
    this.claveI18n,
  });

  /// Fábrica del separador.
  const MenuNode.separador()
      : label = '',
        icon = null,
        activeIcon = null,
        clave = null,
        index = null,
        children = null,
        accion = null,
        shortcut = null,
        rolesPermitidos = null,
        isSectionHeader = false,
        isSubItem = false,
        esSeparador = true,
        claveI18n = null;

  bool get isLeaf => !esSeparador && children == null && !isSectionHeader;

  /// Hoja que abre una pantalla del shell (tiene índice) vs. hoja-acción.
  bool get isPage => isLeaf && accion == null;

  /// Grupo desplegable (hijos y no es encabezado de sección).
  bool get isGrupo => !esSeparador && !isSectionHeader && children != null;

  MenuNode copyWith({bool? isSubItem, List<MenuNode>? children}) {
    return MenuNode(
      label: label,
      icon: icon,
      activeIcon: activeIcon,
      clave: clave,
      index: index,
      children: children ?? this.children,
      accion: accion,
      shortcut: shortcut,
      rolesPermitidos: rolesPermitidos,
      isSectionHeader: isSectionHeader,
      isSubItem: isSubItem ?? this.isSubItem,
      esSeparador: esSeparador,
      claveI18n: claveI18n,
    );
  }
}

// ─── Carga del menú desde menu.json ────────────────────────────────────

/// Menú lateral **data-driven**.
///
/// El árbol por defecto vive en [MenuConfig.arbolPorDefecto] (const) y se
/// sirve mientras no haya `menu.json`. Al arrancar, [MenuConfig.cargar()]
/// (llamado desde `main.dart`) lee el JSON y, si no existe, **siembra** el
/// archivo con el árbol por defecto para dejarlo listo para editar.
///
/// Todo error de lectura/parsing degrada al árbol por defecto: un `menu.json`
/// mal escrito nunca impide arrancar la estación.
class MenuConfig {
  MenuConfig._();

  /// Errores del último `cargar()` (clave desconocida, JSON inválido, …).
  /// Solo diagnóstico: la app sigue con el árbol por defecto.
  static List<String> errores = const [];

  static String? _ultimaRuta;

  /// Ruta del `menu.json` efectivamente leído (o la que se sembró).
  static String? get ruta => _ultimaRuta;

  /// Árbol por defecto (estructura pedida por el cliente). Fuente de verdad
  /// del archivo que se siembra en `menu.json`.
  ///
  /// **Nota de alcance**: solo se incluyen opciones con pantalla real en la
  /// estación (Fase 1 del menú). CÁMARAS, INDICADORES, CONCEPTOS DE INVENTARIO,
  /// REPORTES por filtro y MANUALES se añadirán al árbol cuando exista su
  /// módulo (Fases 2–4); se pueden pre-cargar editando `menu.json` a mano.
  static const List<MenuNode> arbolPorDefecto = [
    MenuNode(
      label: 'INICIO',
      isSectionHeader: true,
      children: [
        MenuNode(
          label: 'Inicio',
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard,
          clave: 'inicio',
          index: 0,
          shortcut: 'Ctrl+1',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
      ],
    ),
    MenuNode(
      label: 'CATÁLOGOS',
      isSectionHeader: true,
      children: [
        MenuNode(
          label: 'Clientes',
          icon: Icons.handshake_outlined,
          activeIcon: Icons.handshake,
          clave: 'clientes',
          index: 18,
          shortcut: 'Alt+C',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Proveedores',
          icon: Icons.storefront_outlined,
          activeIcon: Icons.storefront,
          clave: 'proveedores',
          index: 19,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode.separador(),
        MenuNode(
          label: 'Transportes',
          icon: Icons.fire_truck_outlined,
          activeIcon: Icons.fire_truck,
          clave: 'transportes',
          index: 5,
          shortcut: 'Ctrl+⇧+T',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Conductores',
          icon: Icons.badge_outlined,
          activeIcon: Icons.badge,
          clave: 'conductores',
          index: 4,
          shortcut: 'F8',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Camiones / Vehículos',
          icon: Icons.directions_car_outlined,
          activeIcon: Icons.directions_car,
          clave: 'camiones',
          index: 3,
          shortcut: 'Alt+F',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode.separador(),
        MenuNode(
          label: 'Categorías',
          icon: Icons.category_outlined,
          activeIcon: Icons.category,
          clave: 'categorias',
          index: 6,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Productos',
          icon: Icons.inventory_2_outlined,
          activeIcon: Icons.inventory_2,
          clave: 'productos',
          index: 7,
          shortcut: 'Alt+P',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode.separador(),
        MenuNode(
          label: 'Almacenes',
          icon: Icons.warehouse_outlined,
          activeIcon: Icons.warehouse,
          clave: 'almacenes',
          index: 8,
          shortcut: 'Alt+A',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode.separador(),
        MenuNode(
          label: 'Conceptos Kardex',
          icon: Icons.rule_folder_outlined,
          activeIcon: Icons.rule_folder,
          clave: 'conceptos_inventario',
          index: 29,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
      ],
    ),
    MenuNode(
      label: 'GESTIÓN',
      isSectionHeader: true,
      children: [
        MenuNode(
          label: 'Peso Manual',
          icon: Icons.edit_note,
          activeIcon: Icons.edit_note,
          accion: 'go:pesaje_manual',
          shortcut: 'F2',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Peso Automático',
          icon: Icons.smart_toy_outlined,
          activeIcon: Icons.smart_toy,
          accion: 'go:pesaje_automatico',
          shortcut: 'F1',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode.separador(),
        MenuNode(
          label: 'Inventario',
          icon: Icons.tune,
          activeIcon: Icons.tune,
          accion: 'go:ajustes',
          shortcut: 'Ctrl+A',
          rolesPermitidos: {'ADMIN', 'OPERADOR'},
        ),
      ],
    ),
    MenuNode(
      label: 'CONSULTAR',
      isSectionHeader: true,
      children: [
        MenuNode(
          label: 'Entradas',
          icon: Icons.arrow_downward_outlined,
          activeIcon: Icons.arrow_downward,
          clave: 'entradas',
          index: 10,
          shortcut: 'Ctrl+2',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Salidas',
          icon: Icons.arrow_upward_outlined,
          activeIcon: Icons.arrow_upward,
          clave: 'salidas',
          index: 11,
          shortcut: 'Ctrl+3',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode.separador(),
        MenuNode(
          label: 'Ingresos',
          icon: Icons.move_to_inbox_outlined,
          activeIcon: Icons.move_to_inbox,
          clave: 'ingresos',
          index: 21,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Despachos',
          icon: Icons.outbox_outlined,
          activeIcon: Icons.outbox,
          clave: 'despachos',
          index: 22,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode.separador(),
        MenuNode(
          label: 'Auditoría del Sistema',
          icon: Icons.fact_check_outlined,
          activeIcon: Icons.fact_check,
          accion: 'go:auditoria',
          rolesPermitidos: {'ADMIN', 'AUDITOR'},
        ),
      ],
    ),
    MenuNode(
      label: 'REPORTES',
      isSectionHeader: true,
      children: [
        MenuNode(
          label: 'Reportes Generales',
          icon: Icons.analytics_outlined,
          activeIcon: Icons.analytics,
          clave: 'reportes',
          index: 12,
          shortcut: 'Ctrl+4',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode.separador(),
        MenuNode(
          label: 'Diarios',
          icon: Icons.today_outlined,
          activeIcon: Icons.today,
          clave: 'reportes_diarios',
          index: 24,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Mensuales',
          icon: Icons.calendar_month_outlined,
          activeIcon: Icons.calendar_month,
          clave: 'reportes_mensuales',
          index: 25,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Personalizado',
          icon: Icons.date_range_outlined,
          activeIcon: Icons.date_range,
          clave: 'reportes_personalizado',
          index: 26,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Kardex',
          icon: Icons.table_rows_outlined,
          activeIcon: Icons.table_rows,
          clave: 'kardex',
          index: 9,
          shortcut: 'Alt+K',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
      ],
    ),
    MenuNode(
      label: 'MANTENIMIENTO',
      isSectionHeader: true,
      children: [
        MenuNode(
          label: 'Empresa y Documentos',
          icon: Icons.business_outlined,
          activeIcon: Icons.business,
          clave: 'documentos_empresa',
          index: 15,
          rolesPermitidos: {'ADMIN', 'AUDITOR'},
        ),
        MenuNode.separador(),
        MenuNode(
          label: 'Usuarios del Sistema',
          icon: Icons.admin_panel_settings_outlined,
          activeIcon: Icons.admin_panel_settings,
          clave: 'usuarios',
          index: 2,
          shortcut: 'Alt+U',
          rolesPermitidos: {'ADMIN', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Roles',
          icon: Icons.badge_outlined,
          activeIcon: Icons.badge,
          clave: 'roles',
          index: 20,
          rolesPermitidos: {'ADMIN', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Seguridad y Accesos',
          icon: Icons.lock_outline,
          activeIcon: Icons.lock,
          clave: 'seguridad',
          index: 14,
          shortcut: 'Alt+S',
          rolesPermitidos: {'ADMIN'},
        ),
        MenuNode.separador(),
        MenuNode(
          label: 'Semáforos',
          icon: Icons.traffic_outlined,
          activeIcon: Icons.traffic,
          clave: 'dispositivos_semaforos',
          index: 28,
          rolesPermitidos: {'ADMIN'},
        ),
        MenuNode(
          label: 'Barreras de tránsito',
          icon: Icons.door_sliding,
          activeIcon: Icons.door_sliding,
          clave: 'dispositivos_barreras',
          index: 31,
          rolesPermitidos: {'ADMIN'},
        ),
        MenuNode(
          label: 'Cámaras',
          icon: Icons.photo_camera_outlined,
          activeIcon: Icons.photo_camera,
          clave: 'dispositivos_camaras',
          index: 29,
          rolesPermitidos: {'ADMIN'},
        ),
        MenuNode(
          label: 'Impresoras',
          icon: Icons.print_outlined,
          activeIcon: Icons.print,
          clave: 'dispositivos_impresoras',
          index: 30,
          rolesPermitidos: {'ADMIN'},
        ),
        MenuNode(
          label: 'Básculas',
          icon: Icons.scale_outlined,
          activeIcon: Icons.scale,
          clave: 'dispositivos_basculas',
          index: 13,
          shortcut: 'Alt+D',
          rolesPermitidos: {'ADMIN'},
        ),
        MenuNode(
          label: 'Indicadores',
          icon: Icons.straighten_outlined,
          activeIcon: Icons.straighten,
          clave: 'dispositivos_indicadores',
          index: 27,
          rolesPermitidos: {'ADMIN'},
        ),
        MenuNode.separador(),
        MenuNode(
          label: 'Diseño de Ticket',
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long,
          clave: 'diseno_ticket',
          index: 17,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Configuración',
          icon: Icons.settings_outlined,
          activeIcon: Icons.settings,
          clave: 'configuracion',
          index: 16,
          shortcut: 'Ctrl+,',
          rolesPermitidos: {'ADMIN'},
        ),
      ],
    ),
    MenuNode(
      label: 'AYUDA',
      isSectionHeader: true,
      children: [
        MenuNode(
          label: 'Ayuda y Soporte',
          icon: Icons.help_outline,
          activeIcon: Icons.help,
          accion: 'go:ayuda',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode.separador(),
        MenuNode(
          label: 'Manuales',
          icon: Icons.menu_book_outlined,
          activeIcon: Icons.menu_book,
          accion: 'go:ayuda_manuales',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Página Web',
          icon: Icons.public_outlined,
          activeIcon: Icons.public,
          accion: 'go:ayuda_pagina',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Versión',
          icon: Icons.info_outline,
          activeIcon: Icons.info,
          accion: 'go:ayuda_version',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Tutorial',
          icon: Icons.school_outlined,
          activeIcon: Icons.school,
          accion: 'go:ayuda_tutorial',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
      ],
    ),
  ];

  /// Árbol efectivo (el JSON si hubo `menu.json`; si no, el por defecto).
  static List<MenuNode> _arbol = arbolPorDefecto;

  static List<MenuNode> get arbol => _arbol;

  /// ¿Se intentó leer el JSON? (para tests/diagnóstico).
  static bool cargado = false;

  /// Destinos válidos de `"clave"` en el JSON → pantalla del shell.
  ///
  /// Es una lista **informativa** (el mensaje de error la muestra); quien
  /// valida de verdad es [AccesosDefault.indiceDe]. Debe mantenerse alineada
  /// con `_pages` de HomeShell o el diagnóstico engaña al usuario, como pasó
  /// con `terceros` repetido en Clientes y Proveedores: `clientes` (18) y
  /// `proveedores` (19) existen y segmentan la misma tabla `terceros`;
  /// `ingresos` (20) y `despachos` (21) son el kardex filtrado por movimiento.
  static const List<String> clavesDisponibles = [
    'inicio',
    'terceros',
    'clientes',
    'proveedores',
    'usuarios',
    'camiones',
    'conductores',
    'transportes',
    'categorias',
    'productos',
    'almacenes',
    'kardex',
    'entradas',
    'salidas',
    'ingresos',
    'despachos',
    'reportes',
    'dispositivos',
    'dispositivos_basculas',
    'dispositivos_indicadores',
    'dispositivos_semaforos',
    'dispositivos_barreras',
    'dispositivos_camaras',
    'dispositivos_impresoras',
    'seguridad',
    'documentos_empresa',
    'configuracion',
    'diseno_ticket',
    'conceptos_inventario',
    'roles',
    'reportes_diarios',
    'reportes_mensuales',
    'reportes_personalizado',
  ];

  /// Destinos válidos de `"accion"` en el JSON → comando `go:*` del shell.
  static const List<String> accionesDisponibles = [
    'go:pesaje_automatico',
    'go:pesaje_manual',
    'go:ajustes',
    'go:auditoria',
    'go:sesiones',
    'go:diagnostico',
    'go:licencia',
    'go:conexiones',
    'go:ayuda',
  ];

  /// Lee `menu.json` (override → sistema). Si no existe, siembra el árbol
  /// por defecto en el override. Cualquier error deja el árbol por defecto.
  static Future<void> cargar() async {
    errores = <String>[];
    cargado = true;

    final rutas = [MenuConfigPaths.overridePath, MenuConfigPaths.sistemaPath];
    for (final ruta in rutas) {
      final f = File(ruta);
      try {
        if (!await f.exists()) continue;
        _ultimaRuta = ruta;
        final crudo = await f.readAsString();
        final raiz = jsonDecode(crudo);
        final items = raiz is Map ? raiz['menu'] : raiz;
        if (items is! List || items.isEmpty) {
          errores.add('$ruta: falta la lista "menu"; se usa el menú por defecto');
          _arbol = arbolPorDefecto;
          return;
        }
        final parsed = desdeJson(items);
        if (parsed.isEmpty) {
          errores.add('$ruta: ninguna opción válida; se usa el menú por defecto');
          _arbol = arbolPorDefecto;
          return;
        }
        _arbol = limpiarSeparadores(parsed);
        return;
      } catch (e) {
        errores.add('$ruta: $e');
        _arbol = arbolPorDefecto;
        return;
      }
    }

    // Sin archivo: siembro el por defecto para que el usuario tenga algo que
    // editar (best effort: si no se puede escribir, el menú sigue funcionando).
    _ultimaRuta = MenuConfigPaths.overridePath;
    _arbol = arbolPorDefecto;
    await sembrarPorDefecto();
  }

  /// Vuelve a leer el `menu.json` (p. ej. tras un botón de recarga).
  static Future<void> recargar() => cargar();

  /// Escribe el árbol por defecto como JSON (para que exista algo editable).
  static Future<void> sembrarPorDefecto() async {
    try {
      await Directory(MenuConfigPaths.overrideDir).create(recursive: true);
      await File(MenuConfigPaths.overridePath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(aJson(arbolPorDefecto)),
        flush: true,
      );
    } catch (e) {
      errores.add('no se pudo escribir ${MenuConfigPaths.overridePath}: $e');
    }
  }

  /// Ignora el JSON y vuelve al árbol de fábrica (también borra el archivo).
  static Future<void> restaurarDefecto({bool borrarArchivo = true}) async {
    _arbol = arbolPorDefecto;
    errores = <String>[];
    if (borrarArchivo) {
      try {
        final f = File(MenuConfigPaths.overridePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Fija el árbol efectivo directamente (solo tests: evita E/IO y aísla el
  /// estado global entre casos). Production usa [cargar].
  @visibleForTesting
  static void inyectarParaPruebas(List<MenuNode> arbol) {
    _arbol = arbol;
    cargado = true;
  }

  // ── Parsing ───────────────────────────────────────────────────────────

  /// Convierte la lista `"menu"` del JSON en nodos. Descarta lo inválido y
  /// acumula el motivo en [errores] (nunca lanza).
  static List<MenuNode> desdeJson(List<dynamic> items) {
    final out = <MenuNode>[];
    for (final it in items) {
      final n = _nodo(it);
      if (n != null) out.add(n);
    }
    _avisarClavesDuplicadas(out);
    return out;
  }

  /// Detecta `clave` repetidas entre hermanos (un `menu.json` editado a mano
  /// puede tener Clientes y Proveedores sobre `terceros`). No invalida el
  /// menú —el sidebar desambigua las claves de widget— pero deja el aviso en
  /// [errores] para que el usuario lo corrija.
  static void _avisarClavesDuplicadas(List<MenuNode> nodos) {
    final vistas = <String, int>{};
    for (final n in nodos) {
      final clave = n.clave;
      if (clave != null) {
        vistas[clave] = (vistas[clave] ?? 0) + 1;
      }
    }
    for (final e in vistas.entries) {
      if (e.value > 1) {
        _error(
            'la clave "${e.key}" se repite ${e.value} veces en el mismo nivel; '
            'las opciones se mostrarán igual, pero revise "clave" en menu.json');
      }
    }
    for (final n in nodos) {
      final hijos = n.children;
      if (hijos != null && hijos.isNotEmpty) {
        _avisarClavesDuplicadas(hijos);
      }
    }
  }

  static MenuNode? _nodo(dynamic raw) {
    if (raw is! Map) {
      _error('elemento que no es un objeto: $raw');
      return null;
    }
    final m = Map<String, dynamic>.from(raw);
    final tipoCrudo = m['tipo'];
    final tipo =
        (tipoCrudo is String ? tipoCrudo : '').trim().toLowerCase();

    switch (tipo) {
      case 'separador':
        return const MenuNode.separador();

      case 'seccion':
        return _contenedor(m, seccion: true);

      case 'grupo':
        return _contenedor(m, seccion: false);

      case 'opcion':
      case 'hoja':
        return _opcion(m);

      case '':
        _error('nodo sin "tipo" (seccion|grupo|opcion|separador): $m');
        return null;

      default:
        _error('"tipo" desconocido "$tipo": $m');
        return null;
    }
  }

  static MenuNode? _contenedor(Map<String, dynamic> m, {required bool seccion}) {
    final label = (_texto(m['label']) ?? '').trim();
    if (label.isEmpty) {
      _error('${seccion ? 'seccion' : 'grupo'} sin "label"');
      return null;
    }
    final hijosCrudos = m['hijos'];
    final hijos = hijosCrudos is List ? desdeJson(hijosCrudos) : <MenuNode>[];
    if (hijos.isEmpty) {
      _error('"$label" no tiene hijos válidos');
      return null;
    }
    final icono = _texto(m['icono'])?.trim();
    return MenuNode(
      label: label,
      claveI18n: _texto(m['i18n']),
      // Sin "icono" ⇒ null (el encabezado/grupo va sin icono, como siempre).
      icon: (icono == null || icono.isEmpty) ? null : MenuIconos.desde(icono),
      children: limpiarSeparadores(hijos),
      isSectionHeader: seccion,
      rolesPermitidos: _roles(m['roles']),
    );
  }

  static MenuNode? _opcion(Map<String, dynamic> m) {
    final label = (_texto(m['label']) ?? '').trim();
    if (label.isEmpty) {
      _error('opcion sin "label"');
      return null;
    }

    final accionCruda = (_texto(m['accion']) ?? '').trim();
    final accion = accionCruda.startsWith('go:') ? accionCruda : null;
    if (accionCruda.isNotEmpty && accion == null) {
      _error('"$label": la acción debe empezar por "go:" (recibido "$accionCruda")');
    }

    final claveCruda = (_texto(m['clave']) ?? '').trim();
    String? clave;
    int? idx;
    if (claveCruda.isNotEmpty) {
      final i = AccesosDefault.indiceDe(claveCruda);
      if (i >= 0) {
        clave = claveCruda;
        idx = i;
      } else {
        _error(
            '"$label": clave desconocida "$claveCruda". Válidas: ${clavesDisponibles.join(', ')}');
      }
    }

    if (clave == null && accion == null) {
      _error('"$label": necesita "clave" o "accion"');
      return null;
    }

    final icono = MenuIconos.desde(_texto(m['icono']));
    // `icono_activo` solo viaja si difiere de `icono` (menos bytes en el JSON);
    // al leer, ausente ⇒ ídem `icono`, que es como el árbol por defecto.
    final actCrudo = m['icono_activo'];
    final iconoActivo = actCrudo is String && actCrudo.trim().isNotEmpty
        ? MenuIconos.desde(actCrudo)
        : icono;

    return MenuNode(
      label: label,
      claveI18n: _texto(m['i18n']),
      icon: icono,
      activeIcon: iconoActivo,
      clave: clave,
      index: idx,
      accion: accion,
      shortcut: _texto(m['atajo']),
      rolesPermitidos: _roles(m['roles']),
    );
  }

  /// Texto tolerante: si el usuario escribe un número u objeto donde se
  /// esperaba string, devuelve `null` en vez de lanzar (el campo se omite
  /// y el resto del menú sigue vivo).
  static String? _texto(dynamic v) => v is String ? v : null;

  static Set<String>? _roles(dynamic raw) {
    if (raw is! List || raw.isEmpty) return null;
    final out = <String>{};
    for (final r in raw) {
      if (r is String && r.trim().isNotEmpty) out.add(r.trim().toUpperCase());
    }
    return out.isEmpty ? null : out;
  }

  static void _error(String msg) {
    errores = [...errores, msg];
  }

  /// Quita separadores al inicio, al final o consecutivos (para que una poda
  /// por rol no deje líneas sueltas o dobles).
  static List<MenuNode> limpiarSeparadores(List<MenuNode> nodos) {
    final out = <MenuNode>[];
    for (final n in nodos) {
      if (n.esSeparador) {
        if (out.isEmpty || out.last.esSeparador) continue;
        out.add(n);
        continue;
      }
      out.add(n);
    }
    while (out.isNotEmpty && out.last.esSeparador) {
      out.removeLast();
    }
    return out;
  }

  // ── Serialización (árbol → JSON) ──────────────────────────────────────

  /// Documento `menu.json` completo a partir de un árbol.
  static Map<String, dynamic> aJson(List<MenuNode> arbol) => {
        'version': 1,
        '_LEEME':
            'Menú lateral. Edita y reinicia la app. tipos: seccion | grupo | '
            'opcion | separador. Opciones: label, i18n, icono, icono_activo, '
            'atajo, roles, hijos. Destinos: "clave" (${clavesDisponibles.join('|')}) '
            'o "accion" (${accionesDisponibles.join('|')}). Iconos: '
            '${MenuIconos.nombres.take(40).join(', ')}… (ver docs/NAV.md).',
        'menu': arbol.map(_nodoJson).toList(),
      };

  static Map<String, dynamic> _nodoJson(MenuNode n) {
    if (n.esSeparador) return {'tipo': 'separador'};

    final m = <String, dynamic>{
      'tipo': n.isSectionHeader ? 'seccion' : (n.children != null ? 'grupo' : 'opcion'),
      'label': n.label,
    };
    if (n.claveI18n != null) m['i18n'] = n.claveI18n;
    final icono = MenuIconos.nombreDe(n.icon);
    if (icono != null) m['icono'] = icono;
    final activo = MenuIconos.nombreDe(n.activeIcon);
    if (activo != null && activo != icono) m['icono_activo'] = activo;
    if (n.clave != null) m['clave'] = n.clave;
    if (n.accion != null) m['accion'] = n.accion;
    if (n.shortcut != null) m['atajo'] = n.shortcut;
    if (n.rolesPermitidos != null && n.rolesPermitidos!.isNotEmpty) {
      m['roles'] = n.rolesPermitidos!.toList()..sort();
    }
    if (n.children != null && n.children!.isNotEmpty) {
      m['hijos'] = n.children!.map(_nodoJson).toList();
    }
    return m;
  }
}
