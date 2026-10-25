import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/screens/dispositivos/semaforos_tab.dart';

/// Doble del `ApiClient` que sirve semáforos registrados, un estado simulado
/// y registra los comandos manuales enviados. Ninguna prueba abre un socket.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.semaforos = const []});

  final List<Map<String, dynamic>> semaforos;
  final List<Map<String, dynamic>> comandos = [];
  final List<Map<String, dynamic>> llamadas = [];
  int descubrirLlamadas = 0;

  @override
  Future<Response> getList(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    llamadas.add(Map<String, dynamic>.from(queryParameters ?? const {}));
    final data = path.endsWith('/semaforos')
        ? semaforos
        : const <Map<String, dynamic>>[];
    return Response(
      data: data,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> descubrirSemaforos({
    bool incluirSimulados = true,
  }) async {
    descubrirLlamadas++;
    return const <Map<String, dynamic>>[];
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

Map<String, dynamic> _semaforoJson() => {
      'id_semaforo': 'uuid-s1',
      'descripcion': 'Semáforo entrada',
      'protocolo': 'http',
      'ip_address': '127.0.0.1',
      'puerto_tcp': 8080,
      'id_balanza': 'uuid-b1',
      'control_automatico': true,
      'umbral_cero_kg': 5.0,
      'is_simulado': true,
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
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista los semáforos registrados y muestra el estado',
      (tester) async {
    await _pumpTab(tester, _FakeApiClient(semaforos: [_semaforoJson()]));

    expect(find.text('Semáforo entrada'), findsOneWidget);
    expect(find.text('HTTP 127.0.0.1:8080'), findsOneWidget);
    expect(find.text('SIMULADA'), findsOneWidget);
    expect(find.text('AUTO'), findsOneWidget);
    // Tras probar, el semáforo queda conectado.
    expect(find.text('Conectado'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la lista vacía invita a detectar', (tester) async {
    await _pumpTab(tester, _FakeApiClient());

    expect(
      find.text('No hay semáforos registrados.\n'
          'Presione "Detectar" para buscarlos automáticamente.'),
      findsOneWidget,
    );
  });

  testWidgets('detectar sin resultados avisa y llama al descubrimiento',
      (tester) async {
    final fake = _FakeApiClient();
    await _pumpTab(tester, fake);

    await tester.tap(find.byKey(const Key('semaforos_detectar_vacio')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fake.descubrirLlamadas, greaterThanOrEqualTo(1));
    expect(find.text('No se detectaron semáforos conectados'), findsOneWidget);

    // Dejar cerrar el snackbar para no terminar con temporizadores vivos.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('el detalle muestra la fase/luces y envía comandos manuales',
      (tester) async {
    final fake = _FakeApiClient(semaforos: [_semaforoJson()]);
    await _pumpTab(tester, fake);

    await tester.tap(find.text('Semáforo entrada'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // La app decide la fase; el semáforo solo obedece.
    expect(find.text('Fase: PESANDO'), findsOneWidget);
    expect(find.text('Prueba manual'), findsOneWidget);

    final botonVerde = find.widgetWithText(OutlinedButton, 'Verde');
    await tester.scrollUntilVisible(
      botonVerde,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    await tester.tap(botonVerde);
    await tester.pump();
    await tester.pump();

    expect(fake.comandos, isNotEmpty);
    expect(fake.comandos.last['id'], 'uuid-s1');
    expect(fake.comandos.last['color'], 'verde');
    expect(fake.comandos.last['action'], 'on');

    // Cerrar el modal para cancelar el refresco periódico del sheet.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('la vista trae su barra de filtros', (tester) async {
    await _pumpTab(tester, _FakeApiClient(semaforos: [_semaforoJson()]));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Todos'), findsNWidgets(4));
  });

  testWidgets('el texto de búsqueda viaja a la API como query parameter',
      (tester) async {
    final fake = _FakeApiClient(semaforos: [_semaforoJson()]);
    await _pumpTab(tester, fake);

    await tester.enterText(find.byType(TextField), 'semáforo');
    await tester.pump(const Duration(milliseconds: 400));

    final conTexto = fake.llamadas.lastWhere(
      (q) => (q['q'] as String?)?.isNotEmpty ?? false,
      orElse: () => const {},
    );
    expect(conTexto['q'], 'semáforo');
  });

  testWidgets('el filtro de control viaja como control_automatico',
      (tester) async {
    final fake = _FakeApiClient(semaforos: [_semaforoJson()]);
    await _pumpTab(tester, fake);

    await tester.tap(find.text('Automático'));
    await tester.pump(const Duration(milliseconds: 400));

    final conFiltro = fake.llamadas.lastWhere(
      (q) => q['control_automatico'] == true,
      orElse: () => const {},
    );
    expect(conFiltro['control_automatico'], isTrue);
  });
}
