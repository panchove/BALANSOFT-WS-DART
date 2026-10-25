import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/screens/dispositivos/camaras_tab.dart';

/// Doble del `ApiClient` que sirve cámaras registradas y una prueba de
/// conexión. Ninguna prueba abre un socket: el snapshot se simula.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.camaras = const [], this.descubiertas = const []});

  final List<Map<String, dynamic>> camaras;
  final List<Map<String, dynamic>> descubiertas;
  final List<Map<String, dynamic>> llamadas = [];
  final List<Map<String, dynamic>> creadas = [];

  @override
  Future<Response> getList(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    llamadas.add(Map<String, dynamic>.from(queryParameters ?? const {}));
    final data = path.endsWith('/camaras')
        ? camaras
        : const <Map<String, dynamic>>[];
    return Response(
      data: data,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> descubrirCamaras({
    bool incluirLocales = true,
    bool incluirRegistradas = true,
  }) async =>
      descubiertas;

  @override
  Future<Response> createItem(String path, Map<String, dynamic> body) async {
    creadas.add(Map<String, dynamic>.from(body));
    return Response(data: body, requestOptions: RequestOptions(path: path));
  }

  @override
  Future<Map<String, dynamic>> probarCamara(String camaraId) async => {
        'camara': 'Cámara entrada',
        'conectado': true,
        'detalle': null,
        'ancho': 1920,
        'alto': 1080,
        'tamano_kb': 240.5,
      };
}

Map<String, dynamic> _camaraJson() => {
      'id_camara': 'uuid-c1',
      'descripcion': 'Cámara entrada',
      'url_snapshot': 'http://192.168.1.50/snapshot.cgi',
      'usuario': 'admin',
      'ubicacion': 'ambos',
      'origen': 'ip',
      'dispositivo': null,
      'is_simulada': true,
      'activo': true,
      'password_configurada': true,
    };

Map<String, dynamic> _camaraLocalJson() => {
      'id_camara': 'uuid-c2',
      'descripcion': 'Webcam USB',
      'url_snapshot': '',
      'origen': 'local',
      'dispositivo': '/dev/video0',
      'ubicacion': 'ambos',
      'is_simulada': false,
      'activo': true,
      'password_configurada': false,
    };

Future<void> _pumpTab(WidgetTester tester, _FakeApiClient fake) async {
  await di.sl.reset();
  di.sl.registerLazySingleton<ApiClient>(() => fake);
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: CamarasConfigTab(esAdmin: true),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Desmonta la pestaña para cancelar el `Timer.periodic` de refresco.
Future<void> _desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump();
}

void main() {
  testWidgets('lista las cámaras registradas y muestra la ubicación',
      (tester) async {
    await _pumpTab(tester, _FakeApiClient(camaras: [_camaraJson()]));

    expect(find.text('Cámara entrada'), findsOneWidget);
    expect(find.text('http://192.168.1.50/snapshot.cgi'), findsOneWidget);
    expect(find.text('SIM'), findsOneWidget);
    expect(find.text('AMB'), findsOneWidget);
    expect(find.text('Conectada'), findsWidgets);
    expect(tester.takeException(), isNull);

    await _desmontar(tester);
  });

  testWidgets('la lista vacía invita a detectar o agregar una cámara',
      (tester) async {
    await _pumpTab(tester, _FakeApiClient());

    expect(
      find.textContaining('No hay cámaras registradas.'),
      findsOneWidget,
    );

    await _desmontar(tester);
  });

  testWidgets('el botón "Nueva cámara" abre el formulario de alta',
      (tester) async {
    await _pumpTab(tester, _FakeApiClient());

    await tester.tap(find.byKey(const Key('camaras_nueva_vacio')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // El formulario exige una URL de snapshot.
    expect(find.text('URL del snapshot'), findsOneWidget);
    expect(find.text('Probar conexión'), findsOneWidget);

    await _desmontar(tester);
  });

  testWidgets('una cámara inactiva se marca OFF', (tester) async {
    final json = _camaraJson()
      ..['activo'] = false
      ..['is_simulada'] = false
      ..['ubicacion'] = 'entrada';
    await _pumpTab(tester, _FakeApiClient(camaras: [json]));

    expect(find.text('OFF'), findsOneWidget);
    expect(find.text('ENT'), findsOneWidget);

    await _desmontar(tester);
  });

  testWidgets('la vista trae su barra de filtros', (tester) async {
    await _pumpTab(tester, _FakeApiClient(camaras: [_camaraJson()]));

    // Barra de búsqueda + chips de estado/tipo/simulación/ubicación.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Todas'), findsNWidgets(4));

    await _desmontar(tester);
  });

  testWidgets('el filtro de tipo viaja como origen', (tester) async {
    final fake = _FakeApiClient(camaras: [_camaraJson(), _camaraLocalJson()]);
    await _pumpTab(tester, fake);

    await tester.tap(find.text('Local/USB'));
    await tester.pump(const Duration(milliseconds: 400));

    final conFiltro = fake.llamadas.lastWhere(
      (q) => q['origen'] == 'local',
      orElse: () => const {},
    );
    expect(conFiltro['origen'], 'local');

    await _desmontar(tester);
  });

  testWidgets('una cámara local muestra el badge LOCAL y su dispositivo',
      (tester) async {
    await _pumpTab(
        tester, _FakeApiClient(camaras: [_camaraLocalJson()]));

    expect(find.text('Webcam USB'), findsOneWidget);
    // El badge LOCAL vive dentro de la tarjeta (el chip del filtro dice
    // «Local/USB», que no colisiona con el badge).
    expect(
      find.descendant(of: find.byType(Card), matching: find.text('LOCAL')),
      findsOneWidget,
    );
    expect(find.text('/dev/video0'), findsOneWidget);

    await _desmontar(tester);
  });

  testWidgets('una cámara IP muestra el badge IP y su URL', (tester) async {
    await _pumpTab(tester, _FakeApiClient(camaras: [_camaraJson()]));

    expect(
      find.descendant(of: find.byType(Card), matching: find.text('IP')),
      findsOneWidget,
    );
    expect(find.text('http://192.168.1.50/snapshot.cgi'), findsOneWidget);

    await _desmontar(tester);
  });

  testWidgets('Detectar auto-registra las cámaras locales nuevas',
      (tester) async {
    final fake = _FakeApiClient(descubiertas: [
      {
        'descripcion': 'Integrated_Webcam_HD',
        'origen': 'local',
        'dispositivo': '/dev/video0',
        'url_snapshot': '',
      },
    ]);
    await _pumpTab(tester, fake);

    await tester.tap(find.byKey(const Key('camaras_detectar_vacio')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(fake.creadas, hasLength(1));
    expect(fake.creadas.first['origen'], 'local');
    expect(fake.creadas.first['dispositivo'], '/dev/video0');

    await _desmontar(tester);
  });

  testWidgets('Detectar no re-registra una local ya presente', (tester) async {
    final fake = _FakeApiClient(
      camaras: [_camaraLocalJson()],
      descubiertas: [
        {
          'descripcion': 'Webcam USB',
          'origen': 'local',
          'dispositivo': '/dev/video0',
          'url_snapshot': '',
        },
      ],
    );
    await _pumpTab(tester, fake);

    await tester.tap(find.byKey(const Key('camaras_detectar_vacio')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(fake.creadas, isEmpty);

    await _desmontar(tester);
  });

  testWidgets('el texto de búsqueda viaja a la API como query parameter',
      (tester) async {
    final fake = _FakeApiClient(camaras: [_camaraJson()]);
    await _pumpTab(tester, fake);

    await tester.enterText(find.byType(TextField), 'entrada');
    await tester.pump(const Duration(milliseconds: 400));

    final conTexto = fake.llamadas.lastWhere(
      (q) => (q['q'] as String?)?.isNotEmpty ?? false,
      orElse: () => const {},
    );
    expect(conTexto['q'], 'entrada');

    await _desmontar(tester);
  });

  testWidgets('el filtro de simulación viaja como is_simulada', (tester) async {
    final fake = _FakeApiClient(camaras: [_camaraJson()]);
    await _pumpTab(tester, fake);

    // "Simuladas" es la 2.ª opción del grupo Origen.
    await tester.tap(find.text('Simuladas'));
    await tester.pump(const Duration(milliseconds: 400));

    final conFiltro = fake.llamadas.lastWhere(
      (q) => q['is_simulada'] == true,
      orElse: () => const {},
    );
    expect(conFiltro['is_simulada'], isTrue);

    await _desmontar(tester);
  });

  testWidgets(
      'el formulario de alta incluye campos para marca, modelo y fabricante',
      (tester) async {
    await _pumpTab(tester, _FakeApiClient());

    await tester.tap(find.byKey(const Key('camaras_nueva_vacio')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Marca'), findsOneWidget);
    expect(find.text('Modelo'), findsOneWidget);
    expect(find.text('Marca / Fabricante (opcional)'), findsOneWidget);
    expect(find.text('emparejar_y_guardar'), findsNothing); // Se evalúa con tr()
    expect(find.text('Emparejar y guardar'), findsOneWidget);

    await _desmontar(tester);
  });

  testWidgets('una cámara con marca y modelo la muestra en la tarjeta',
      (tester) async {
    final json = _camaraJson()
      ..['marca'] = 'Logitech'
      ..['modelo'] = 'C920';
    await _pumpTab(tester, _FakeApiClient(camaras: [json]));

    expect(find.textContaining('Logitech · C920'), findsOneWidget);
    expect(find.textContaining('Uso: Entrada y salida'), findsOneWidget);

    await _desmontar(tester);
  });
}

