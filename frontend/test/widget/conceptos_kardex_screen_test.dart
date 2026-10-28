import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/constants/api_constants.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/screens/inventario/conceptos_kardex_screen.dart';

/// Doble del `ApiClient` con catálogo de conceptos en memoria.
///
/// Permite verificar las reglas de la pantalla sin red: qué IDs se ofrecen al
/// crear, cómo se deriva el signo y qué pasa al borrar un concepto con
/// movimientos (409 → ofrecer desactivar).
class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.conceptos = const [], this.errorBorrar409 = false});

  final List<Map<String, dynamic>> conceptos;
  final bool errorBorrar409;

  final List<Map<String, dynamic>> creados = [];
  final List<Map<String, dynamic>> actualizados = [];
  final List<String> borrados = [];

  @override
  Future<Response> getList(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return Response(
      data: conceptos,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response> createItem(String path, Map<String, dynamic> body) async {
    creados.add(Map<String, dynamic>.from(body));
    return Response(data: body, requestOptions: RequestOptions(path: path));
  }

  @override
  Future<Response> updateItem(String path, Map<String, dynamic> body) async {
    actualizados.add(Map<String, dynamic>.from(body));
    return Response(data: body, requestOptions: RequestOptions(path: path));
  }

  @override
  Future<Response> deleteItem(String path) async {
    borrados.add(path);
    if (errorBorrar409) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
          statusCode: 409,
          data: {'detail': 'El concepto tiene movimientos de kardex'},
          requestOptions: RequestOptions(path: path),
        ),
      );
    }
    return Response(statusCode: 204, requestOptions: RequestOptions(path: path));
  }
}

Map<String, dynamic> _concepto(
  int id,
  String nombre, {
  required String signo,
  bool sistema = false,
  bool activo = true,
}) {
  return {
    'id_concepto': id,
    'nombre': nombre,
    'descripcion': null,
    'signo': signo,
    'es_sistema': sistema,
    'activo': activo,
    'aplica_a': 'AMBOS',
  };
}

Future<void> _pump(WidgetTester tester, _FakeApiClient fake) async {
  await di.sl.reset();
  di.sl.registerLazySingleton<ApiClient>(() => fake);
  await tester.pumpWidget(
    const MaterialApp(home: ConceptosKardexScreen()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('ConceptosKardexScreen', () {
    testWidgets('agrupa por rango y muestra el signo de cada concepto',
        (tester) async {
      final fake = _FakeApiClient(
        conceptos: [
          _concepto(0, 'Saldo inicial', signo: 'inicial', sistema: true),
          _concepto(5, 'Compra', signo: 'positivo'),
          _concepto(10, 'Ingreso por báscula', signo: 'positivo', sistema: true),
          _concepto(60, 'Despacho por báscula', signo: 'negativo', sistema: true),
          _concepto(55, 'Merma', signo: 'negativo'),
        ],
      );
      await _pump(tester, fake);

      expect(find.text('Rango 00'), findsOneWidget);
      expect(find.text('Rango 01-49'), findsOneWidget);
      expect(find.text('Rango 10'), findsOneWidget);
      expect(find.text('Rango 50-59'), findsOneWidget);
      expect(find.text('Rango 60'), findsOneWidget);
      expect(find.text('5 - Compra'), findsOneWidget);
      expect(find.text('55 - Merma'), findsOneWidget);
    });

    testWidgets('el combo de nuevo arranca en un ID libre (nunca reservado)',
        (tester) async {
      final fake = _FakeApiClient(
        conceptos: [
          _concepto(0, 'Saldo inicial', signo: 'inicial', sistema: true),
          _concepto(5, 'Compra', signo: 'positivo'),
          _concepto(10, 'Ingreso por báscula', signo: 'positivo', sistema: true),
          _concepto(60, 'Despacho por báscula', signo: 'negativo', sistema: true),
        ],
      );
      await _pump(tester, fake);

      await tester.tap(find.byKey(const Key('conceptos_kardex_nuevo')));
      await tester.pumpAndSettle();

      final dropdown = tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>),
      );
      final seleccionado = dropdown.initialValue;
      // El valor por defecto es el primer hueco libre y no es reservado.
      expect(seleccionado, isNotNull);
      expect(seleccionado, isNot(0));
      expect(seleccionado, isNot(5));
      expect(seleccionado, isNot(10));
      expect(seleccionado, isNot(60));
      // El signo mostrado acompaña al rango del ID elegido.
      expect(
        find.text(
          seleccionado! >= 50 ? 'Negativo (-)' : 'Positivo (+)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('un concepto del sistema oculta el botón de borrar',
        (tester) async {
      final fake = _FakeApiClient(
        conceptos: [
          _concepto(10, 'Ingreso por báscula', signo: 'positivo', sistema: true),
          _concepto(5, 'Compra', signo: 'positivo'),
        ],
      );
      await _pump(tester, fake);

      expect(find.text('ID y signo bloqueados (concepto del sistema)'),
          findsNothing);
      // El 10 no tiene delete; el 5 sí.
      expect(find.byKey(const Key('concepto_kardex_borrar_5')), findsOneWidget);
      expect(find.byKey(const Key('concepto_kardex_borrar_10')), findsNothing);
    });

    testWidgets('borrar con movimientos (409) ofrece desactivar',
        (tester) async {
      final fake = _FakeApiClient(
        conceptos: [_concepto(5, 'Compra', signo: 'positivo')],
        errorBorrar409: true,
      );
      await _pump(tester, fake);

      await tester.tap(find.byKey(const Key('concepto_kardex_borrar_5')));
      await tester.pumpAndSettle();

      expect(find.text('Concepto con movimientos'), findsOneWidget);
      await tester.tap(find.text('Desactivar'));
      await tester.pumpAndSettle();
      expect(fake.actualizados, isNotEmpty);
      expect(fake.actualizados.last['activo'], isFalse);
    });

    testWidgets('crear manda el signo coherente con el ID', (tester) async {
      final fake = _FakeApiClient(conceptos: [
        _concepto(0, 'Saldo inicial', signo: 'inicial', sistema: true),
        _concepto(10, 'Ingreso por báscula', signo: 'positivo', sistema: true),
        _concepto(60, 'Despacho por báscula', signo: 'negativo', sistema: true),
      ]);
      await _pump(tester, fake);

      await tester.tap(find.byKey(const Key('conceptos_kardex_nuevo')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField).first, 'Ajuste por inventario físico');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(fake.creados, hasLength(1));
      expect(fake.creados.first['nombre'], 'Ajuste por inventario físico');
      expect(
        fake.creados.first['signo'], anyOf('positivo', 'negativo', 'inicial'),
      );
    });
  });
}
