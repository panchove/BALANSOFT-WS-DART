class ApiConstants {
  static const String apiPrefix = '/api/v1';

  // Health
  static const String health = '$apiPrefix/health';

  // Auth
  static const String login = '$apiPrefix/auth/login';
  static const String loginLocal = '$apiPrefix/auth/login-local';
  static const String register = '$apiPrefix/auth/register';
  static const String validateLicense = '$apiPrefix/auth/validate-license';
  static const String licenseSnapshot = '$apiPrefix/auth/license';
  static const String refreshToken = '$apiPrefix/auth/refresh-token';
  static const String logout = '$apiPrefix/auth/logout';
  static const String forgotPassword = '$apiPrefix/auth/forgot-password';
  static const String resetPassword = '$apiPrefix/auth/reset-password';

  // Weighing
  static const String weighingCreate = '$apiPrefix/weighing/create';
  static String weighingClose(String boleto) => '$apiPrefix/weighing/close/$boleto';
  static const String weighingList = '$apiPrefix/weighing/list';
  static String weighingByBoleto(String boleto) => '$apiPrefix/weighing/boleto/$boleto';
  static String weighingUpdate(String boleto) => '$apiPrefix/weighing/$boleto';
  static String weighingAnular(String boleto) => '$apiPrefix/weighing/$boleto/anular';
  static const String weighingPendientes = '$apiPrefix/weighing/pendientes';
  static String weighingPdf(String boleto) => '$apiPrefix/weighing/$boleto/pdf';
  static String weighingTxt(String boleto) => '$apiPrefix/weighing/$boleto/txt';
  static String scaleLive(String balanzaId) => '$apiPrefix/weighing/scale/$balanzaId/live';
  static const String seriesBase = '$apiPrefix/empresa/series';
  static const String seriesCreate = '$apiPrefix/empresa/series';
  static String seriesUpdate(String idSerie) =>
      '$apiPrefix/empresa/series/$idSerie';
  static String seriesActiva(String idSerie) =>
      '$apiPrefix/empresa/series/$idSerie/activa';
  static String seriesDelete(String idSerie) =>
      '$apiPrefix/empresa/series/$idSerie';

  // Catalogos (sync combinado)
  static const String catalogsSync = '$apiPrefix/catalogo/sync';

  // Seguridad y Accesos
  static const String seguridadMatriz = '$apiPrefix/seguridad/matriz';

  // Flota
  static const String camiones = '$apiPrefix/camiones';
  static String camion(String id) => '$apiPrefix/camiones/$id';
  static const String camionesBuscar = '$apiPrefix/camiones/buscar';
  static const String remolques = '$apiPrefix/remolques';
  static String remolque(String id) => '$apiPrefix/remolques/$id';

  // Inventario
  static const String productos = '$apiPrefix/productos';
  static String producto(String id) => '$apiPrefix/productos/$id';
  static const String categorias = '$apiPrefix/categorias';
  static String categoria(String id) => '$apiPrefix/categorias/$id';
  static const String almacenes = '$apiPrefix/almacenes';
  static String almacen(String id) => '$apiPrefix/almacenes/$id';
  static const String balanzas = '$apiPrefix/balanzas';
  static String balanza(String id) => '$apiPrefix/balanzas/$id';
  static String balanzaProbar(String id) => '$apiPrefix/balanzas/$id/probar';
  static const String balanzasDescubrir = '$apiPrefix/balanzas/descubrir';

  // Directorio
  static const String transportes = '$apiPrefix/transportes';
  static String transporte(String id) => '$apiPrefix/transportes/$id';
  static const String conductores = '$apiPrefix/conductores';
  static String conductor(String cedulaDni) => '$apiPrefix/conductores/$cedulaDni';
  static const String terceros = '$apiPrefix/terceros';
  static String tercero(String id) => '$apiPrefix/terceros/$id';

  // Sync
  static const String syncPush = '$apiPrefix/sync/push';
  static const String syncPull = '$apiPrefix/sync/pull';
  static const String syncStatus = '$apiPrefix/sync/status';

  // Reports
  static const String reportDaily = '$apiPrefix/reports/daily';
  static const String reportMonthly = '$apiPrefix/reports/monthly';
  static String reportVehicle(String id) => '$apiPrefix/reports/vehicle/$id';
  static const String reportExportExcel = '$apiPrefix/reports/export/excel';
  static const String kardexSaldo = '$apiPrefix/reports/kardex/saldo';
  static const String kardexDetalle = '$apiPrefix/reports/kardex/detalle';
  static const String kardexExportExcel = '$apiPrefix/reports/export/kardex/excel';
  static const String kardexExportPdf = '$apiPrefix/reports/export/kardex/pdf';

  // Reports avanzados
  static const String advancedReportTransportista = '$apiPrefix/reports/transportista';
  static const String advancedReportTercero = '$apiPrefix/reports/tercero';
  static const String advancedReportPesoRango = '$apiPrefix/reports/peso-rango';
  static const String advancedReportComparativo = '$apiPrefix/reports/comparativo-mensual';

  // Identidad local (cuenta espejo / APP_ROLE=local)
  static const String identity = '$apiPrefix/identity';

  // Configuración unificada de la estación (cuenta + licencia en vivo)
  static const String configAccount = '$apiPrefix/config/account';

  // Perfil de la empresa (datos de contacto + logo)
  static const String empresaPerfil = '$apiPrefix/empresa';

  // Usuarios locales (gestión admin)
  static const String usuarios = '$apiPrefix/usuarios';
  static String usuario(String id) => '$apiPrefix/usuarios/$id';

  // Sync de usuarios (cola local -> servidor central)
  static const String syncUsuariosPendientes = '$apiPrefix/sync/usuarios/pendientes';
  static const String syncUsuariosEntregados = '$apiPrefix/sync/usuarios/entregados';
  static const String syncUsersServer = '$apiPrefix/sync/users';
}