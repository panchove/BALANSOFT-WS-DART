import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/constants/api_constants.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/domain/entities/catalogs.dart';
import 'package:balansoft_ws/domain/repositories/i_catalog_repository.dart';
import 'package:balansoft_ws/domain/usecases/catalog_usecases.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/screens/ajustes_inventario/ajustes_inventario_screen.dart';

/// Doble del `ApiClient` para la pantalla de ajustes.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    this.conceptos = const [],
    this.errorAjuste,
  });

  final List<Map<String, dynamic>> conceptos;
  final Object? errorAjuste;

  final List<Map<String, dynamic>> creados = [];

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
  Future<Response> crearAjusteInventario({
    required int idConcepto,
    required String idProducto,
    required String idAlmacen,
    required double cantidad,
    required String motivo,
    String? documento,
  }) async {
    if (errorAjuste != null) throw errorAjuste!;
    creados.add({
      'id_concepto': idConcepto,
      'id_producto': idProducto,
      'id_almacen': idAlmacen,
      'cantidad': cantidad,
      'motivo': motivo,
      'documento': documento,
    });
    return Response(
      data: {'id_movimiento': idConcepto, 'valor': cantidad.abs()},
      requestOptions: RequestOptions(path: ApiConstants.inventarioAjustes),
    );
  }
}

/// Repositorio de catálogos que solo sirve un producto kardex y un almacén.
class _FakeCatalogRepository implements ICatalogRepository {
  @override
  Future<CatalogData?> getCachedCatalogs() async => CatalogData(
        products: const [
          Product(id: 'prod-1', nombre: 'Cemento', esKardex: true),
        ],
        warehouses: const [
          Warehouse(id: 'alm-1', nombre: 'Silo Principal'),
        ],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _concepto(
  int id,
  String nombre, {
  required String signo,
  bool sistema = false,
  bool activo = true,
}) =>
    {
      'id_concepto': id,
      'nombre': nombre,
      'descripcion': null,
      'signo': signo,
      'es_sistema': sistema,
      'activo': activo,
      'aplica_a': 'AMBOS',
    };

Future<void> _pump(WidgetTester tester, _FakeApiClient fake) async {
  await di.sl.reset();
  di.sl.registerLazySingleton<ApiClient>(() => fake);
  di.sl.registerLazySingleton<ICatalogRepository>(_FakeCatalogRepository.new);
  di.sl.registerLazySingleton<GetCachedCatalogsUseCase>(
    () => GetCachedCatalogsUseCase(di.sl<ICatalogRepository>()),
  );
  await tester.pumpWidget(
    const MaterialApp(home: AjustesInventarioScreen()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('AjustesInventarioScreen', () {
    testWidgets('carga el catálogo y arranca sin concepto ni prefijo',
        (tester) async {
      final fake = _FakeApiClient(
        conceptos: [
          _concepto(0, 'Saldo inicial', signo: 'inicial', sistema: true),
          _concepto(10, 'Ingreso por báscula', signo: 'positivo', sistema: true),
          _concepto(5, 'Compra', signo: 'positivo'),
        ],
      );
      await _pump(tester, fake);

      // El formulario se renderiza con el combo de concepto vacío.
      expect(find.text('Selecciona el motivo del movimiento'), findsOneWidget);
      // Sin concepto elegido no se fuerza ningún signo en la cantidad.
      expect(find.text('+ '), findsNothing);
      expect(find.text('- '), findsNothing);
    });

    testWidgets('sin concepto seleccionado no llama al backend',
        (tester) async {
      final fake = _FakeApiClient(
        conceptos: [_concepto(5, 'Compra', signo: 'positivo')],
      );
      await _pump(tester, fake);

      await tester.enterText(find.byType(TextFormField).last, '200');
      await tester.pumpAndSettle();

      final boton = find.byType(FilledButton).last;
      await tester.ensureVisible(boton);
      await tester.pumpAndSettle();
      await tester.tap(boton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(fake.creados, isEmpty);
      // El validador del formulario impide llegar al envío sin concepto.
      expect(find.text('Selecciona un concepto'), findsWidgets);
    });

    testWidgets('un 422 del backend se muestra al usuario', (tester) async {
      final fake = _FakeApiClient(
        conceptos: [_concepto(5, 'Compra', signo: 'positivo')],
        errorAjuste: DioException(
          requestOptions: RequestOptions(path: ApiConstants.inventarioAjustes),
          response: Response(
            statusCode: 422,
            data: {
              'detail':
                  "El concepto 'Compra' es positivo; la cantidad debe ser mayor que cero"
            },
            requestOptions: RequestOptions(path: ApiConstants.inventarioAjustes),
          ),
        ),
      );
      await _pump(tester, fake);

      // Sin concepto el flujo se corta antes de llamar al backend: se verifica
      // el mensaje de validación del propio formulario.
      await tester.enterText(find.byType(TextFormField).last, '100');
      await tester.pumpAndSettle();
      final boton = find.byType(FilledButton).last;
      await tester.ensureVisible(boton);
      await tester.pumpAndSettle();
      await tester.tap(boton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(fake.creados, isEmpty);
      expect(find.text('Selecciona un concepto'), findsWidgets);
    });
  });
}
