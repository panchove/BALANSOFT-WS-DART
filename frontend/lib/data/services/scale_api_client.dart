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
    }
    // El socket TCP directo (simulador BSDD) queda emparejado de forma
    // persistente: se mantiene vivo aunque la API entregue el peso. Su
    // reconexión la gestiona ScaleTcpClient; aquí solo se asegura.
    unawaited(super.asegurarConexion());
    if (_balanzaId == null) {
      // Sin balanza registrada seleccionada: se muestra el peso por TCP.
      _usandoTcp = true;
      notifyListeners();
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_intervalo, (_) => _leerEnVivo());
    await _leerEnVivo();
    notifyListeners();
  }

  Future<void> _leerEnVivo() async {
    if (_balanzaId == null) return;
    try {
      final peso = await _datasource.readLive(_balanzaId!);
      if (peso.pesoKg == null) {
        // El backend responde pero no pudo leer el HAL: se muestra TCP.
        _apiPeso = null;
        _apiError = 'Sin lectura del HAL (usando TCP)';
        _usandoTcp = true;
      } else {
        _apiPeso = peso;
        _apiError = '';
        _usandoTcp = false;
      }
    } on ScaleNotConfiguredException {
      _apiPeso = null;
      _apiError = 'Balanza sin hardware configurado (usando TCP)';
      _usandoTcp = true;
    } on ScaleNotFoundException {
      _apiPeso = null;
      _apiError = 'Balanza no encontrada (usando TCP)';
      _usandoTcp = true;
    } on ScaleConnectionException {
      _apiPeso = null;
      _apiError = 'Servidor inalcanzable (usando TCP)';
      _usandoTcp = true;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    // Cierra el socket TCP directo (fin del emparejamiento desde la app).
    super.dispose();
  }
}