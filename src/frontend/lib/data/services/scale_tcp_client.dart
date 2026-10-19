import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'scale_frame_parser.dart';

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
  Timer? _peticionTimer;
  bool _recibioDatos = false;
  String _buffer = '';

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

  /// Asegura la conexión usando el host/puerto **ya configurados**.
  ///
  /// A diferencia de [conectar] (que sobreescribe el puerto por defecto),
  /// esto preserva la configuración actual y permite mantener un socket
  /// persistente sin resetear el emparejamiento. Es idempotente: si ya hay
  /// conexión (o está en curso) no hace nada.
  Future<void> asegurarConexion() async {
    if (_socket != null || _conectando) return;
    await _conectar();
  }

  Future<void> _conectar() async {
    // Guard de reentrada: evita abrir dos sockets si `configurar` dispara una
    // conexión y el llamador invoca `asegurarConexion` acto seguido.
    if (_conectando) return;
    _conectando = true;
    await _desconectar(notificar: false);
    if (_host == null || _host!.isEmpty) {
      _conectando = false;
      return;
    }
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
      _buffer = '';
      _recibioDatos = false;
      // Contra un indicador real (ASCII) NO se escribe nada; solo si en una
      // ventana corta no llegó ningún frame (simulador BSDD bajo demanda) se
      // pide el estado por JSON.
      _peticionTimer?.cancel();
      _peticionTimer = Timer(const Duration(milliseconds: 1200), () {
        if (!_recibioDatos && _socket != null) {
          _socket!.write(_protocoloPeticion);
        }
      });
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
    _recibioDatos = true;
    _peticionTimer?.cancel();
    _peticionTimer = null;
    _buffer += utf8.decode(datos, allowMalformed: true);
    final partes = _buffer.split(RegExp(r'[\r\n]+'));
    _buffer = partes.removeLast();
    // Un flujo sin delimitadores no debe crecer sin límite.
    if (_buffer.length > 4096) {
      _buffer = _buffer.substring(_buffer.length - 1024);
    }
    for (final parte in partes) {
      final trim = parte.trim();
      if (trim.isEmpty) continue;
      final peso = _parsearLinea(trim);
      if (peso != null) {
        _ultimoPeso = peso;
        notifyListeners();
      }
    }
  }

  /// Interpreta una línea del equipo: JSON (simulador BSDD) o ASCII real.
  ///
  /// Una báscula real (Toledo/GSI, Rice Lake, etc.) emite tramas ASCII como
  /// `ST,GS,+00320.00kg`; el simulador BSDD emite `{"weight_kg":...}`. Se
  /// intenta JSON primero y, si no, el parser ASCII multi-marca.
  PesoEnVivo? _parsearLinea(String linea) {
    try {
      final json = jsonDecode(linea);
      if (json is Map<String, dynamic> && json['weight_kg'] != null) {
        return PesoEnVivo.fromJson(json);
      }
    } on FormatException {
      // No es JSON: sigue el parser ASCII.
    }
    final parseado = parseWeightFrame(linea);
    if (parseado.peso == null) return null;
    return PesoEnVivo(
      pesoKg: parseado.peso,
      estado: parseado.estado ?? 'stable',
      timestamp: DateTime.now(),
      origin: 'TCP',
    );
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
    _peticionTimer?.cancel();
    _peticionTimer = null;
    await _sub?.cancel();
    _sub = null;
    _socket?.destroy();
    _socket = null;
    _buffer = '';
    _recibioDatos = false;
    if (notificar) notifyListeners();
  }

  @override
  void dispose() {
    _desconectar(notificar: false);
    _cancelarTimeout();
    super.dispose();
  }
}