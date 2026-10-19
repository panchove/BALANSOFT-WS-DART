/// Cliente de báscula que prefiere el HAL del backend y mantiene el socket
/// TCP directo emparejado en paralelo.
///
/// Verifica el enrutamiento sin abrir sockets reales (salvo el último test,
/// que usa un `ServerSocket` local) y que la API y el TCP no se alternen
/// cerrándose mutuamente.
library;

import 'dart:convert';
import 'dart:io';

import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/data/datasources/remote/scale_api_datasource.dart';
import 'package:balansoft_ws/data/services/scale_api_client.dart';
import 'package:balansoft_ws/data/services/scale_tcp_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeScaleDatasource extends ScaleApiDatasource {
  _FakeScaleDatasource(this._handler) : super(ApiClient());

  final Future<PesoEnVivo> Function(String balanzaId) _handler;

  @override
  Future<PesoEnVivo> readLive(String balanzaId) => _handler(balanzaId);
}

PesoEnVivo _peso(double? kg) => PesoEnVivo(
      pesoKg: kg,
      timestamp: DateTime.now(),
      origin: 'API-tcp',
    );

void main() {
  test('sin balanza seleccionada usa TCP directo', () async {
    final client = ScaleApiClient(
      datasource: _FakeScaleDatasource((_) async => _peso(10)),
    );
    client.configurarApi(balanzaId: null);

    await client.conectar();

    expect(client.usaApi, isFalse);
    client.dispose();
  });

  test('si el HAL no entrega peso, cae a TCP', () async {
    final client = ScaleApiClient(
      datasource: _FakeScaleDatasource((_) async => _peso(null)),
    );
    client.configurarApi(balanzaId: 'b1');

    await client.conectar();

    expect(client.usaApi, isFalse);
    expect(client.pesoActual, isNull);
    client.dispose();
  });

  test('con peso del HAL se mantiene en la API', () async {
    final client = ScaleApiClient(
      datasource: _FakeScaleDatasource((_) async => _peso(123.4)),
    );
    client.configurarApi(balanzaId: 'b1');

    await client.conectar();

    expect(client.usaApi, isTrue);
    expect(client.pesoActual, 123.4);
    client.dispose();
  });

  test('error de hardware del HAL cae a TCP', () async {
    final client = ScaleApiClient(
      datasource: _FakeScaleDatasource(
        (_) async => throw const ScaleNotConfiguredException(),
      ),
    );
    client.configurarApi(balanzaId: 'b1');

    await client.conectar();

    expect(client.usaApi, isFalse);
    client.dispose();
  });

  test('mantiene el socket TCP aunque la API entregue el peso', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final conexiones = <Socket>[];
    final sub = server.listen((socket) {
      conexiones.add(socket);
      socket.write(
        '${jsonEncode({'weight_kg': 50.0, 'status': 'stable'})}\n',
      );
    });

    final client = ScaleApiClient(
      datasource: _FakeScaleDatasource((_) async => _peso(123.4)),
    );
    client.configurarApi(balanzaId: 'b1');
    await client.conectar(InternetAddress.loopbackIPv4.address, server.port);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    // La API manda en pantalla, pero el emparejamiento TCP sigue vivo.
    expect(client.usaApi, isTrue);
    expect(client.pesoActual, 123.4);
    expect(conexiones, hasLength(1));

    client.dispose();
    await sub.cancel();
    await server.close();
  });
}
