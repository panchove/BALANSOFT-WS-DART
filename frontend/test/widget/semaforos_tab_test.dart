import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/screens/dispositivos/semaforos_tab.dart';

/// Doble del `ApiClient` que sirve semáforos registrados y sus comandos.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.semaforos = const []});

  final List<Map<String, dynamic>> semaforos;
  final List<Map<String, dynamic>> comandos = [];
  final List<Map<String, dynamic>> llamadas = [];

  @override
  Future<Response> getList(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    llamadas.add(Map<String, dynamic>.from(queryParameters ?? const {}));
    final data = path.endsWith('/semaforos') ? semaforos : const <Map<String, dynamic>>[];
    return Response(
      data: data,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Map<String, dynamic>> probarSemaforo(String semaforoId) async => {
        'semaforo': 'S1',
        'conectado': true,
        'protocolo': 'http',
        'estado': {'fase': 'EXTERNO'},
        'detalle': 'Conexión correcta',
      };

  @override
  Future<Map<String, dynamic>> estadoSemaforo(String semaforoId) async => {
        'semaforo': 'S1',
        'conectado': true,
        'automatico': false,
        'fase': 'PESANDO',
        'luces': {
          'rojo': 'on',
          'amarillo': 'off',
          'verde': 'off',
          'zumbador': false,
        },
      };

  @override
  Future<Map<String, dynamic>> comandoSemaforo(
    String semaforoId,
    Map<String, dynamic> comando,
  ) async {
    comandos.add({'id': semaforoId, ...comando});
    return {'aplicado': true, 'comando': comando};
  }

  @override
  Future<Map<String, dynamic>> setSemaforoAutomatico(
    String semaforoId,
    bool activo,
  ) async =>
      {
        'id_semaforo': semaforoId,
        'descripcion': 'Semáforo entrada',
        'control_automatico': activo,
      };
}

Map<String, dynamic> _semaforoJson({
  String id = 'uuid-s1',
  String descripcion = 'Semáforo entrada',
  String protocolo = 'http',
  String ipAddress = '127.0.0.1',
  int puertoTcp = 8080,
  String? puertoCom,
}) =>
    {
      'id_semaforo': id,
      'descripcion': descripcion,
      'protocolo': protocolo,
      'ip_address': ipAddress,
      'puerto_tcp': puertoTcp,
      'puerto_com': puertoCom,
      'id_balanza': 'uuid-b1',
      'control_automatico': true,
      'umbral_cero_kg': 5.0,
      'is_simulado': true,
      'activo': true,
    };

Future<void> _pumpTab(WidgetTester tester, _FakeApiClient fake) async {
  await di.sl.reset();
  di.sl.registerLazySingleton<ApiClient>(() => fake);
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: SemaforosConfigTab(esAdmin: true),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('lista los semáforos registrados y muestra su configuración',
      (tester) async {
    await _pumpTab(tester, _FakeApiClient(semaforos: [_semaforoJson()]));

    expect(find.text('Semáforo entrada'), findsOneWidget);
    expect(find.textContaining('HTTP 127.0.0.1:8080'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la lista vacía muestra el estado sin semáforos',
      (tester) async {
    await _pumpTab(tester, _FakeApiClient(semaforos: const []));

    expect(find.textContaining('Sin semáforos configurados'), findsOneWidget);
  });

  testWidgets('el campo de búsqueda filtra localmente', (tester) async {
    final fake = _FakeApiClient(
      semaforos: [
        _semaforoJson(id: 's1', descripcion: 'Semáforo Entrada'),
        _semaforoJson(id: 's2', descripcion: 'Semáforo Salida'),
      ],
    );
    await _pumpTab(tester, fake);

    expect(find.text('Semáforo Entrada'), findsOneWidget);
    expect(find.text('Semáforo Salida'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Salida');
    await tester.pumpAndSettle();

    expect(find.text('Semáforo Salida'), findsOneWidget);
    expect(find.text('Semáforo Entrada'), findsNothing);
  });

  testWidgets('tocar una tarjeta abre el detalle del semáforo',
      (tester) async {
    await _pumpTab(tester, _FakeApiClient(semaforos: [_semaforoJson()]));

    await tester.tap(find.text('Semáforo entrada'));
    await tester.pumpAndSettle();

    // Comprueba que el bottom sheet se abre con los datos del semáforo
    expect(find.text('Semáforo entrada'), findsWidgets);
    expect(find.byType(SwitchListTile), findsWidgets);
  });
}
