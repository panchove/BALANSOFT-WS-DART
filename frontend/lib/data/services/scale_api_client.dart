import 'dart:async';

import '../datasources/remote/scale_api_datasource.dart';
import 'scale_tcp_client.dart';

/// Cliente de báscula que **prefiere el HAL del backend** (`/weighing/scale/
/// {id}/live`) con polling periódico, y cae a TCP directo (simulador BSDD)
/// cuando:
/// - no hay balanza seleccionada (`balanzaId` nulo/vacío);
/// - el backend logra autenticarse pero dice que la balanza no tiene hardware;
/// - el backend está inalcanzable (red/offline).
class ScaleApiClient extends ScaleTcpClient {
  ScaleApiClient({required ScaleApiDatasource datasource})
      : _datasource = datasource;

  final ScaleApiDatasource _datasource;
  String? _balanzaId;
  String _descripcion = '';
  Timer? _pollTimer;
  bool _usandoTcp = false;
  PesoEnVivo? _apiPeso;
  String _apiError = '';

  static const Duration _intervalo = Duration(seconds: 2);

  String? get balanzaId => _balanzaId;
  bool get usaApi => !_usandoTcp;

  /// Define la balanza a leer vía API (HAL). Sin id → se usa TCP directo.
  void configurarApi({String? balanzaId, String descripcion = ''}) {
    _balanzaId =
        (balanzaId == null || balanzaId.isEmpty) ? null : balanzaId;
    _descripcion = descripcion;
  }

  /// Configura el destino TCP que actúa como respaldo offline.
  void configurarFallbackTcp(String host, [int port = 5555]) {
    super.configurar(host, port);
  }

  @override
  String get host =>
      _descripcion.isNotEmpty ? _descripcion : super.host;

  @override
  bool get conectado => _usandoTcp ? super.conectado : _apiPeso != null;

  @override
  bool get conectando =>
      _usandoTcp ? super.conectando : _pollTimer != null;

  @override
  String get error => _usandoTcp ? super.error : _apiError;

  @override
  PesoEnVivo? get ultimoPeso => _usandoTcp ? super.ultimoPeso : _apiPeso;

  @override
  double? get pesoActual =>
      _usandoTcp ? super.pesoActual : _apiPeso?.pesoKg;

  @override
  Future<void> conectar([String? host, int port = 5555]) async {
    if (host != null) {
      configurarFallbackTcp(host, port);
      _usandoTcp = true;
    }
    if (_balanzaId == null && _usandoTcp) {
      await super.conectar();
      notifyListeners();
      return;
    }
    _usandoTcp = false;
    _apiError = '';
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_intervalo, (_) => _leerEnVivo());
    await _leerEnVivo();
    notifyListeners();
  }

  Future<void> _leerEnVivo() async {
    if (_balanzaId == null) return;
    try {
      final peso = await _datasource.readLive(_balanzaId!);
      _apiPeso = peso;
      _apiError = '';
      _volverATcp(false);
    } on ScaleNotConfiguredException {
      _apiPeso = null;
      _apiError = 'Balanza sin hardware configurado (usando TCP)';
      _volverATcp(true);
    } on ScaleNotFoundException {
      _apiPeso = null;
      _apiError = 'Balanza no encontrada';
    } on ScaleConnectionException {
      _apiPeso = null;
      _apiError = 'Servidor inalcanzable (usando TCP)';
      _volverATcp(true);
    }
    notifyListeners();
  }

  void _volverATcp(bool activar) {
    if (_usandoTcp == activar) return;
    _usandoTcp = activar;
    if (activar) {
      unawaited(super.conectar());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    super.dispose();
  }
}