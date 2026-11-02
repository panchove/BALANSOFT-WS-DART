import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/screens/dispositivos/camaras_tab.dart';

/// Doble del `ApiClient` que sirve cámaras registradas.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.camaras = const []});

  final List<Map<String, dynamic>> camaras;
  final List<Map<String, dynamic>> llamadas = [];

  @override
  Future<Response> getList(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    llamadas.add(Map<String, dynamic>.from(queryParameters ?? const {}));
    return Response(
      data: camaras,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Map<String, dynamic>> probarCamara(String camaraId) async => {
        'id_camara': camaraId,
        'conectado': true,
        'bytes': 1024,
        'mime': 'image/jpeg',
      };
}

Map<String, dynamic> _camaraJson({
  String id = 'uuid-c1',
  String descripcion = 'Cámara entrada',
  String origen = 'ip',
  String urlSnapshot = 'http://192.168.1.50/snapshot.cgi',
  String? dispositivo,
  String ubicacion = 'ambos',
  bool activo = true,
  bool isSimulada = false,
}) =>
    {
      'id_camara': id,
      'descripcion': descripcion,
      'codigo': null,
      'origen': origen,
      'url_snapshot': urlSnapshot,
      'dispositivo': dispositivo,
      'ubicacion': ubicacion,
      'activo': activo,
      'is_simulada': isSimulada,
      'usuario': null,
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

void main() {
  testWidgets('lista las cámaras registradas y muestra la ubicación',
      (tester) async {
    await _pumpTab(tester, _FakeApiClient(camaras: [_camaraJson()]));

    expect(find.text('Cámara entrada'), findsOneWidget);
    expect(find.textContaining('http://192.168.1.50/snapshot.cgi'), findsOneWidget);
    expect(find.textContaining('Entrada y salida'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la lista vacía muestra el estado sin cámaras', (tester) async {
    await _pumpTab(tester, _FakeApiClient(camaras: const []));

    expect(find.textContaining('Sin cámaras configuradas'), findsOneWidget);
  });

  testWidgets('cámara USB local muestra origen USB / Local', (tester) async {
    final camaraLocal = _camaraJson(
      id: 'c-local',
      descripcion: 'Webcam Local',
      origen: 'local',
      dispositivo: '/dev/video0',
      urlSnapshot: '',
    );
    await _pumpTab(tester, _FakeApiClient(camaras: [camaraLocal]));

    expect(find.text('Webcam Local'), findsOneWidget);
    expect(find.textContaining('USB / Local'), findsOneWidget);
  });

  testWidgets('el campo de búsqueda filtra localmente', (tester) async {
    final fake = _FakeApiClient(
      camaras: [
        _camaraJson(id: 'c1', descripcion: 'Cámara Frontal Entrada'),
        _camaraJson(id: 'c2', descripcion: 'Cámara Trasera Salida'),
      ],
    );
    await _pumpTab(tester, fake);

    expect(find.text('Cámara Frontal Entrada'), findsOneWidget);
    expect(find.text('Cámara Trasera Salida'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Trasera');
    await tester.pumpAndSettle();

    expect(find.text('Cámara Trasera Salida'), findsOneWidget);
    expect(find.text('Cámara Frontal Entrada'), findsNothing);
  });

  testWidgets('tocar una tarjeta abre el detalle de la cámara',
      (tester) async {
    await _pumpTab(tester, _FakeApiClient(camaras: [_camaraJson()]));

    await tester.tap(find.text('Cámara entrada'));
    await tester.pumpAndSettle();

    expect(find.text('Cámara entrada'), findsWidgets);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
  });
}
