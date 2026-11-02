import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/screens/dispositivos/indicadores_tab.dart';

/// Doble del `ApiClient` que sirve indicadores registrados.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.indicadores = const []});

  final List<Map<String, dynamic>> indicadores;
  final List<Map<String, dynamic>> llamadas = [];

  @override
  Future<Response> getList(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    llamadas.add(Map<String, dynamic>.from(queryParameters ?? const {}));
    return Response(
      data: indicadores,
      requestOptions: RequestOptions(path: path),
    );
  }
}

Map<String, dynamic> _indicadorJson({
  String id = 'uuid-i1',
  String descripcion = 'Indicador entrada',
  String marca = 'Transcell',
  String modelo = 'TI500E',
  bool activo = true,
  bool isSimulado = false,
  String? puertoCom,
  String protocolo = 'tcp',
  String? ipAddress = '192.168.1.50',
  int? puertoTcp = 5555,
  int balanzasEnlazadas = 0,
}) =>
    {
      'id_indicador': id,
      'descripcion': descripcion,
      'marca': marca,
      'modelo': modelo,
      'activo': activo,
      'is_simulado': isSimulado,
      'protocolo': protocolo,
      'puerto_com': puertoCom,
      'ip_address': ipAddress,
      'puerto_tcp': puertoTcp,
      'formato_trama': 'auto',
      'baudrate': 9600,
      'delimitador': null,
      'balanzas_enlazadas': balanzasEnlazadas,
    };

Future<void> _pumpTab(WidgetTester tester, _FakeApiClient fake) async {
  await di.sl.reset();
  di.sl.registerLazySingleton<ApiClient>(() => fake);
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: IndicadoresConfigTab(esAdmin: true),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('lista los indicadores y su configuración', (tester) async {
    await _pumpTab(tester, _FakeApiClient(indicadores: [_indicadorJson()]));

    expect(find.textContaining('Transcell TI500E'), findsOneWidget);
    expect(find.textContaining('TCP 192.168.1.50:5555'), findsOneWidget);
    expect(find.textContaining('Sin vincular'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('muestra la vinculación cuando está enlazado a básculas',
      (tester) async {
    await _pumpTab(
      tester,
      _FakeApiClient(
        indicadores: [_indicadorJson(balanzasEnlazadas: 2)],
      ),
    );

    expect(find.textContaining('Vinculado a 2 báscula(s)'), findsOneWidget);
  });

  testWidgets('la lista vacía muestra el estado sin indicadores',
      (tester) async {
    await _pumpTab(tester, _FakeApiClient(indicadores: const []));

    expect(find.textContaining('Sin indicadores configurados'), findsOneWidget);
  });

  testWidgets('el botón crear abre el formulario de alta', (tester) async {
    await _pumpTab(tester, _FakeApiClient());

    final botonCrear = find.widgetWithText(OutlinedButton, 'Crear Indicador');
    expect(botonCrear, findsOneWidget);
    await tester.tap(botonCrear);
    await tester.pumpAndSettle();

    expect(find.text('Crear Indicador'), findsWidgets);
    expect(find.text('Descripción *'), findsOneWidget);
    expect(find.text('Marca'), findsOneWidget);
  });

  testWidgets('el campo de búsqueda filtra localmente por texto',
      (tester) async {
    final fake = _FakeApiClient(
      indicadores: [
        _indicadorJson(id: '1', marca: 'Transcell', modelo: 'TI500E'),
        _indicadorJson(id: '2', marca: 'Cardinal', modelo: '225', descripcion: 'Cardinal 225'),
      ],
    );
    await _pumpTab(tester, fake);

    expect(find.textContaining('Transcell TI500E'), findsOneWidget);
    expect(find.textContaining('Cardinal 225'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Cardinal');
    await tester.pumpAndSettle();

    expect(find.textContaining('Cardinal 225'), findsOneWidget);
    expect(find.textContaining('Transcell TI500E'), findsNothing);
  });

  testWidgets('tocar una tarjeta abre el detalle del indicador',
      (tester) async {
    await _pumpTab(tester, _FakeApiClient(indicadores: [_indicadorJson()]));

    await tester.tap(find.textContaining('Transcell TI500E'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sin vincular a ninguna báscula'), findsOneWidget);
  });
}
