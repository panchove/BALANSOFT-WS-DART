import '../../domain/entities/notification.dart';
import '../datasources/remote/api_client.dart';

/// Repositorio del centro de notificaciones y recordatorios.
///
/// Autoridad: el backend de la estación (`/api/v1/notificaciones` y
/// `/api/v1/recordatorios`). Las notificaciones **no** se cachean: son avisos
/// generados por el programador del WServer y su valor es estar al día; si la
/// red falla, la campana simplemente no actualiza su contador.
class NotificationRepository {
  final ApiClient _apiClient;

  NotificationRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<AppNotification>> listar({
    String? estado,
    String? tipo,
    bool soloNoLeidas = false,
    int skip = 0,
    int limit = 50,
  }) async {
    final filas = await _apiClient.listNotificaciones(
      estado: estado,
      tipo: tipo,
      soloNoLeidas: soloNoLeidas,
      skip: skip,
      limit: limit,
    );
    return filas.map(AppNotification.fromJson).toList();
  }

  Future<NotificationSummary> resumen() async {
    return NotificationSummary.fromJson(await _apiClient.resumenNotificaciones());
  }

  Future<AppNotification> marcarLeida(String id) async {
    return AppNotification.fromJson(await _apiClient.marcarNotificacionLeida(id));
  }

  Future<AppNotification> archivar(String id) async {
    return AppNotification.fromJson(await _apiClient.archivarNotificacion(id));
  }

  Future<int> marcarTodasLeidas() => _apiClient.marcarTodasLeidas();

  /// Genera un aviso de prueba (solo ADMIN): valida el canal nativo del SO.
  Future<AppNotification> probar() async {
    return AppNotification.fromJson(await _apiClient.probarNotificacion());
  }

  // ── Recordatorios (solo ADMIN) ──────────────────────────────────────────

  Future<List<Reminder>> listarRecordatorios({bool incluirInactivos = true}) async {
    final filas =
        await _apiClient.listRecordatorios(incluirInactivos: incluirInactivos);
    return filas.map(Reminder.fromJson).toList();
  }

  Future<Reminder> crearRecordatorio({
    required String titulo,
    String? mensaje,
    required DateTime programadaPara,
    String recurrencia = 'none',
  }) async {
    final json = await _apiClient.crearRecordatorio({
      'titulo': titulo,
      'mensaje': mensaje,
      'programada_para': programadaPara.toUtc().toIso8601String(),
      'recurrencia': recurrencia,
    });
    return Reminder.fromJson(json);
  }

  Future<Reminder> actualizar(
    String id, {
    String? titulo,
    String? mensaje,
    DateTime? programadaPara,
    String? recurrencia,
    bool? activo,
  }) async {
    return Reminder.fromJson(
      await _apiClient.actualizarRecordatorio(id, {
        if (titulo != null) 'titulo': titulo,
        if (mensaje != null) 'mensaje': mensaje,
        if (programadaPara != null)
          'programada_para': programadaPara.toUtc().toIso8601String(),
        if (recurrencia != null) 'recurrencia': recurrencia,
        if (activo != null) 'activo': activo,
      }),
    );
  }

  Future<void> eliminar(String id) => _apiClient.eliminarRecordatorio(id);

  /// Dispara el recordatorio ahora sin alterar su programación (solo ADMIN).
  Future<AppNotification> probarRecordatorio(String id) async {
    return AppNotification.fromJson(await _apiClient.probarRecordatorio(id));
  }
}
