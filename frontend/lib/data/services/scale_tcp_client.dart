import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class PesoEnVivo {
  final double? pesoKg;
  final String? unidad;
  final String estado;
  final DateTime timestamp;
  final String origin;

  const PesoEnVivo({
    this.pesoKg,
    this.unidad,
    this.estado = 'desconocido',
    required this.timestamp,
    this.origin = 'TCP',
  });

  factory PesoEnVivo.fromJson(Map<String, dynamic> json) {
    return PesoEnVivo(
      pesoKg: (json['weight_kg'] as num?)?.toDouble(),
      unidad: json['unit'] as String?,
      estado: (json['status'] as String?) ?? 'desconocido',
      timestamp: DateTime.now(),
      origin: (json['type'] as String?) ?? 'TCP',
    );
  }

  bool get estable => estado == 'stable';
}

class ScaleTcpClient extends ChangeNotifier {
  Socket? _socket;
  StreamSubscription<Uint8List>? _sub;
  String? _host;
  int _port = 5555;
  bool _conectando = false;
  String _error = '';
  PesoEnVivo? _ultimoPeso;
  int _reintentos = 0;
  Timer? _reconnectTimer;
  Timer? _timeoutTimer;

  static const String _protocoloPeticion =
      '{"action":"get_state"}\n';

  String get host => _host ?? '127.0.0.1';
  int get port => _port;
  bool get conectado => _socket != null;
  bool get conectando => _conectando;
  String get error => _error;
  PesoEnVivo? get ultimoPeso => _ultimoPeso;
  double? get pesoActual => _ultimoPeso?.pesoKg;

  void configurar(String host, [int port = 5555]) {
    final cambioHost = host != _host;
    final cambioPuerto = port != _port;
    _host = host;
    _port = port;
    if (cambioHost || cambioPuerto) {
      _conectar();
    }
  }

  Future<void> conectar([String? host, int port = 5555]) async {
    if (host != null) _host = host;
    _port = port;
    await _conectar();
  }

  Future<void> _conectar() async {
    await _desconectar(notificar: false);
    if (_host == null || _host!.isEmpty) return;
    _conectando = true;
    _error = '';
    notifyListeners();
    try {
      _iniciarTimeout();
      final socket = await Socket.connect(_host!, _port,
          timeout: const Duration(seconds: 5));
      _cancelarTimeout();
      _socket = socket;
      _conectando = false;
      _reintentos = 0;
      _ultimoPeso = null;
      socket.write(_protocoloPeticion);
      _sub = socket.listen(
        _onDatos,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      notifyListeners();
    } catch (e) {
      _cancelarTimeout();
      _conectando = false;
      _error = 'No se pudo conectar a $_host:$_port ($e)';
      notifyListeners();
    }
  }

  void _iniciarTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 7), () {
      if (_conectando && _socket == null) {
        _error = 'Tiempo de conexión agotado';
        _conectando = false;
        notifyListeners();
      }
    });
  }

  void _cancelarTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  void _onDatos(Uint8List datos) {
    final texto = utf8.decode(datos, allowMalformed: true);
    for (final linea in texto.split('\n')) {
      final trim = linea.trim();
      if (trim.isEmpty) continue;
      try {
        final json = jsonDecode(trim) as Map<String, dynamic>;
        _ultimoPeso = PesoEnVivo.fromJson(json);
        notifyListeners();
      } catch (_) {
        // Línea no JSON, ignorar.
      }
    }
  }

  void _onError(Object error) {
    _error = 'Error de conexión: $error';
    _ultimoPeso = null;
    _socket = null;
    notifyListeners();
    _programarReintento();
  }

  void _onDone() {
    _socket = null;
    if (_host != null && _host!.isNotEmpty) {
      _error = 'Conexión perdida';
    }
    notifyListeners();
    _programarReintento();
  }

  void _programarReintento() {
    if (_reintentos >= 3) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: 3 * (_reintentos + 1)), () {
      _reintentos++;
      _conectar();
    });
  }

  Future<void> _desconectar({bool notificar = true}) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _sub?.cancel();
    _sub = null;
    _socket?.destroy();
    _socket = null;
    if (notificar) notifyListeners();
  }

  @override
  void dispose() {
    _desconectar(notificar: false);
    _cancelarTimeout();
    super.dispose();
  }
}