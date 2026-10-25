import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/screens/dispositivos/indicadores_tab.dart';

/// Doble del `ApiClient` que sirve indicadores y básculas registradas.
/// Ninguna prueba abre un socket.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.indicadores = const [], this.balanzas = const []});

  final List<Map<String, dynamic>> indicadores;
  final List<Map<String, dynamic>> balanzas;
  final List<Map<String, dynamic>> llamadas = [];

  @override
  Future<Response> getList(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    llamadas.add(Map<String, dynamic>.from(queryParameters ?? const {}));
    final data = path.endsWith('/indicadores') ? indicadores : balanzas;
    return Response(
      data: data,
      requestOptions: RequestOptions(path: path),
    );
  }
}

Map<String, dynamic> _indicadorJson({
  String id = 'uuid-i1',
  String descripcion = 'Indicador entrada',
  bool activo = true,
  bool isSimulado = false,
  String? puertoCom,
  String protocolo = 'tcp',
  String? ipAddress = '192.168.1.50',
  int? puertoTcp = 5555,
}) =>
    {
      'id_indicador': id,
      'descripcion': descripcion,
      'marca': 'Transcell',
      'modelo': 'TI500E',
      'activo': activo,
      'is_simulado': isSimulado,
      'protocolo': protocolo,
      'puerto_com': puertoCom,
      'ip_address': ipAddress,
      'puerto_tcp': puertoTcp,
      'formato_trama': 'auto',
      'baudrate': 9600,
      'delimitador': null,
      'balanzas_enlazadas': 0,
    };

Map<String, dynamic> _balanzaJson({
  String id = 'uuid-b1',
  String descripcion = 'Báscula 1',
  String? idIndicador,
}) =>
    {
      'id_balanza': id,
      'descripcion': descripcion,
      'protocolo': 'tcp',
      'id_indicador': idIndicador,
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

    expect(find.text('Indicador entrada'), findsOneWidget);
    expect(find.text('TCP 192.168.1.50:5555'), findsOneWidget);
    // Sin báscula enlazada.
    expect(find.text('Sin báscula enlazada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('muestra la báscula enlazada al indicador', (tester) async {
    await _pumpTab(
      tester,
      _FakeApiClient(
        indicadores: [_indicadorJson()],
        balanzas: [_balanzaJson(idIndicador: 'uuid-i1')],
      ),
    );

    expect(find.text('Báscula: Báscula 1'), findsOneWidget);
  });

  testWidgets('la lista vacía invita a registrar un indicador', (tester) async {
    await _pumpTab(tester, _FakeApiClient());

    expect(
      find.text('No hay indicadores registrados.\n'
          'Registre el terminal de peso (marca y modelo) y enlácelo a su báscula.'),
      findsOneWidget,
    );
  });

  testWidgets('el botón "Nuevo indicador" abre el formulario de alta',
      (tester) async {
    await _pumpTab(tester, _FakeApiClient());

    await tester.tap(find.byKey(const Key('indicadores_nuevo_vacio')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Nuevo indicador'), findsWidgets);
    expect(find.text('Descripción'), findsOneWidget);
    expect(find.text('Guardar indicador'), findsOneWidget);
  });

  testWidgets('un indicador inactivo se marca OFF', (tester) async {
    await _pumpTab(
      tester,
      _FakeApiClient(
        indicadores: [_indicadorJson(activo: false, isSimulado: false)],
      ),
    );

    expect(find.text('OFF'), findsOneWidget);
    expect(find.text('SIM'), findsNothing);
  });

  testWidgets('la vista trae su barra de filtros', (tester) async {
    await _pumpTab(tester, _FakeApiClient(indicadores: [_indicadorJson()]));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Todos'), findsNWidgets(3));
  });

  testWidgets('el texto de búsqueda viaja a la API como query parameter',
      (tester) async {
    final fake = _FakeApiClient(indicadores: [_indicadorJson()]);
    await _pumpTab(tester, fake);

    await tester.enterText(find.byType(TextField), 'Transcell');
    await tester.pump(const Duration(milliseconds: 400));

    final conTexto = fake.llamadas.lastWhere(
      (q) => (q['q'] as String?)?.isNotEmpty ?? false,
      orElse: () => const {},
    );
    expect(conTexto['q'], 'Transcell');
  });

  testWidgets('el filtro de canal viaja como protocolo', (tester) async {
    final fake = _FakeApiClient(indicadores: [_indicadorJson()]);
    await _pumpTab(tester, fake);

    await tester.tap(find.text('TCP'));
    await tester.pump(const Duration(milliseconds: 400));

    final conFiltro = fake.llamadas.lastWhere(
      (q) => q['protocolo'] == 'tcp',
      orElse: () => const {},
    );
    expect(conFiltro['protocolo'], 'tcp');
  });
}
