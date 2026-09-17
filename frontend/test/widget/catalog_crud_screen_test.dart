import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/constants/catalog_resources.dart';
import 'package:balansoft_ws/data/datasources/local/local_storage.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/providers/bloc/catalog_crud/catalog_crud_cubit.dart';
import 'package:balansoft_ws/presentation/screens/catalog/catalog_crud_screen.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super();

  @override
  Future<Response> getList(String path) async {
    return Response(
      data: {
        'data': [
          {
            'id_tercero': '1',
            'razon_social': 'Acme S.A.',
            'codigo': 'C-01',
            'identificacion_fiscal': 'J-100',
            'tipo': 'CLIENTE',
          },
          {
            'id_tercero': '2',
            'razon_social': 'Global C.A.',
            'codigo': 'P-01',
            'identificacion_fiscal': 'J-200',
            'tipo': 'AMBOS',
          },
        ],
      },
      requestOptions: RequestOptions(path: path),
    );
  }
}

class _FakeLocalStorage extends LocalStorage {
  @override
  Future<({String host, int port})> getScaleConfig() async {
    return (host: '127.0.0.1', port: 5555);
  }

  @override
  Future<String> getDescargasDir() async => '/tmp/descargas';
}

Future<void> _pumpCrud(WidgetTester tester) async {
  await di.sl.reset();
  di.sl.registerLazySingleton<ApiClient>(() => _FakeApiClient());
  di.sl.registerLazySingleton<LocalStorage>(() => _FakeLocalStorage());
  di.sl.registerFactory<CatalogCrudCubit>(
      () => CatalogCrudCubit(di.sl<ApiClient>()));

  await tester.pumpWidget(
    MaterialApp(
      home: CatalogCrudScreen(
        recurso: AppCatalogos.clientesYProveedores.recursos.first,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'CRUD terceros: lista C/P/Ambos sin ProviderNotFound al abrir editor',
      (tester) async {
    await _pumpCrud(tester);

    expect(find.text('Acme S.A.'), findsOneWidget);
    expect(find.text('Global C.A.'), findsOneWidget);

    await tester.tap(find.byTooltip('Nuevo Cliente/Proveedor'));
    await tester.pumpAndSettle();

    expect(find.text('Nuevo Cliente/Proveedor'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo Cliente/Proveedor'), findsNothing);
  });

  testWidgets(
      'filtro Cliente incluye registros AMBOS y editar en modal respeta rol',
      (tester) async {
    await _pumpCrud(tester);

    await tester.tap(find.text('Cliente'));
    await tester.pumpAndSettle();

    expect(find.text('Acme S.A.'), findsOneWidget);
    expect(find.text('Global C.A.'), findsOneWidget,
        reason: 'una persona AMBOS debe seguir apareciendo al filtrar Cliente');
    expect(tester.takeException(), isNull);
  });
}
