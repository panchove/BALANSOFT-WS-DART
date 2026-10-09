import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/app_constants.dart';
import '../../data/datasources/remote/api_client.dart';
import '../../injection.dart' as di;

/// Respaldo automático por inactividad (REQ-NF-BKP-001).
///
/// Solo corre en estaciones **SERVIDOR** (el TRABAJADOR es cliente delgado y
/// no aloja los datos). Tras [AppConstants.backupAutoIdleMinutes] minutos sin
/// interacción (puntero, teclado o navegación) dispara
/// `POST /api/v1/backups/auto`.
///
/// Los fallos de red son silenciosos a propósito: el kiosco no debe molestar
/// al operador; el reintento ocurre en el siguiente tick.
class AutoBackupService {
  AutoBackupService({ApiClient? apiClient}) : _apiClient = apiClient;

  /// Instancia global usada por la app (HomeShell).
  static final AutoBackupService instance = AutoBackupService._();

  // Constructor privado para la singleton: usa el cliente del contenedor DI.
  AutoBackupService._() : _apiClient = null;

  final ApiClient? _apiClient;

  ApiClient get _api => _apiClient ?? di.sl<ApiClient>();

  /// Última interacción registrada del operador.
  @visibleForTesting
  DateTime ultimaActividad = DateTime.now();

  Timer? _timer;
  bool _enProgreso = false;
  bool _iniciado = false;

  /// Solo la estación que aloja la BD respalda (rol del instalador).
  bool get habilitado => AppConfig.esServidor;

  /// Registra actividad del operador (reset del contador de inactividad).
  void registrarActividad() {
    ultimaActividad = DateTime.now();
  }

  /// Arranca el vigilante periódico. No hace nada fuera de modo SERVIDOR.
  void iniciar({Duration? intervalo}) {
    if (!habilitado || _iniciado) return;
    _iniciado = true;
    _timer = Timer.periodic(
      intervalo ?? const Duration(minutes: 1),
      (_) => verificarBackup(),
    );
  }

  /// Detiene el vigilante (logout / cierre de sesión).
  void detener() {
    _timer?.cancel();
    _timer = null;
    _iniciado = false;
  }

  /// Comprueba si corresponde disparar el respaldo y, si es el caso, lo
  /// ejecuta. Público para tests; devuelve `true` solo si se creó un respaldo.
  @visibleForTesting
  Future<bool> verificarBackup() async {
    if (!habilitado || _enProgreso) return false;
    final inactividad = DateTime.now().difference(ultimaActividad);
    if (inactividad <
        const Duration(minutes: AppConstants.backupAutoIdleMinutes)) {
      return false;
    }
    _enProgreso = true;
    try {
      await _api.crearBackupAuto();
      return true;
    } catch (_) {
      // Sin red o servidor ocupado: se reintenta en el siguiente tick.
      return false;
    } finally {
      _enProgreso = false;
    }
  }
}