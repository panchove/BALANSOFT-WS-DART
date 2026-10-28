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
  /// Historial de ediciones del boleto (justificación por edición, migración 024).
  static String weighingEdiciones(String boleto) =>
      '$apiPrefix/weighing/$boleto/ediciones';
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
  static const String seguridadRoles = '$apiPrefix/seguridad/roles';

  // Auditoría
  static const String auditoria = '$apiPrefix/auditoria';

  // Notificaciones (bandeja de la estación) y recordatorios
  static const String notificaciones = '$apiPrefix/notificaciones';
  static const String notificacionesResumen = '$apiPrefix/notificaciones/resumen';
  static const String notificacionesLeerTodas = '$apiPrefix/notificaciones/leer-todas';
  static const String notificacionesProbar = '$apiPrefix/notificaciones/probar';
  static String notificacionLeer(String id) =>
      '$apiPrefix/notificaciones/$id/leer';
  static String notificacionArchivar(String id) =>
      '$apiPrefix/notificaciones/$id/archivar';
  static const String recordatorios = '$apiPrefix/recordatorios';
  static String recordatorio(String id) => '$apiPrefix/recordatorios/$id';
  static String recordatorioProbar(String id) =>
      '$apiPrefix/recordatorios/$id/probar';

  // RB-12: sesiones/equipos de la cuenta (servidor central, token de servidor).
  static const String sesionesEquipo = '/api/v1/auth/sesiones';
  static String sesionEquipo(String id) => '/api/v1/auth/sesiones/$id';

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

  // Semáforos (actuador de salida del ciclo de pesaje)
  static const String semaforos = '$apiPrefix/semaforos';
  static String semaforo(String id) => '$apiPrefix/semaforos/$id';
  static const String semaforosDescubrir = '$apiPrefix/semaforos/descubrir';
  static String semaforoProbar(String id) => '$apiPrefix/semaforos/$id/probar';
  static String semaforoEstado(String id) => '$apiPrefix/semaforos/$id/estado';
  static String semaforoComando(String id) => '$apiPrefix/semaforos/$id/comando';
  static String semaforoAutomatico(String id) => '$apiPrefix/semaforos/$id/automatico';

  // Cámaras (captura de placa: snapshot IP o cámara local/USB)
  static const String camaras = '$apiPrefix/camaras';
  static const String camarasDescubrir = '$apiPrefix/camaras/descubrir';
  static String camara(String id) => '$apiPrefix/camaras/$id';
  static String camaraProbar(String id) => '$apiPrefix/camaras/$id/probar';
  static String camaraSnapshot(String id) => '$apiPrefix/camaras/$id/snapshot';
  static String camaraStream(String id) => '$apiPrefix/camaras/$id/stream';
  static String camaraCapturar(String id) => '$apiPrefix/camaras/$id/capturar';

  // Barreras de tránsito (actuador de salida: abrir/cerrar paso vehicular)
  static const String barreras = '$apiPrefix/barreras';
  static String barrera(String id) => '$apiPrefix/barreras/$id';
  static const String barrerasDescubrir = '$apiPrefix/barreras/descubrir';
  static String barreraProbar(String id) => '$apiPrefix/barreras/$id/probar';
  static String barreraEstado(String id) => '$apiPrefix/barreras/$id/estado';
  static String barreraComando(String id) => '$apiPrefix/barreras/$id/comando';

  // Indicadores (terminal de peso, separado de la báscula física)
  static const String indicadores = '$apiPrefix/indicadores';
  static String indicador(String id) => '$apiPrefix/indicadores/$id';
  static String indicadorEnlazar(String id, String balanzaId) =>
      '$apiPrefix/indicadores/$id/balanzas/$balanzaId/enlazar';

  // Conceptos de inventario (catálogo de motivos de kardex)
  static const String conceptosInventario = '$apiPrefix/conceptos_inventario';
  static String conceptoInventario(String id) =>
      '$apiPrefix/conceptos_inventario/$id';
  static const String conceptosKardex = '$apiPrefix/conceptos-kardex';
  static String conceptoKardex(String id) =>
      '$apiPrefix/conceptos-kardex/$id';
  static const String inventarioAjustes = '$apiPrefix/inventario/ajustes';
  static const String weighingResumen = '$apiPrefix/weighing/resumen';

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
  static const String reportExportPdf = '$apiPrefix/reports/export/pdf';
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

  // Llaves de activación de un solo uso (estaciones OPERADOR).
  static const String llavesActivacion = '$apiPrefix/activacion/llaves';

  // Sync de usuarios (cola local -> servidor central)
  static const String syncUsuariosPendientes = '$apiPrefix/sync/usuarios/pendientes';
  static const String syncUsuariosEntregados = '$apiPrefix/sync/usuarios/entregados';
  static const String syncUsersServer = '$apiPrefix/sync/users';

  // Backups de estación (REQ-NF-BKP-001/002/003; rol local)
  static const String backupsBase = '$apiPrefix/backups';
  static const String backupsAuto = '$apiPrefix/backups/auto';
  static String backupDownload(String archivo) =>
      '$apiPrefix/backups/$archivo/download';
  static String backupRestore(String archivo) =>
      '$apiPrefix/backups/$archivo/restore';

  // Dispositivos / Vinculación
  static const String dispositivosDescubrir = '$apiPrefix/dispositivos/descubrir';
  static const String vinculos = '$apiPrefix/vinculos';

  // Configuración
  static const String configPesoManual = '$apiPrefix/config/peso-manual';
}