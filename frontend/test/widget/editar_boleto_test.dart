import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:balansoft_ws/data/datasources/local/database_helper.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/data/repositories/weighing_repository.dart';
import 'package:balansoft_ws/domain/entities/boleto_edicion.dart';
import 'package:balansoft_ws/domain/entities/weighing.dart';
import 'package:balansoft_ws/domain/repositories/i_weighing_repository.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/screens/weighing/editar_boleto_dialog.dart';

/// Regresión del hito de edición de boletos (migración 024):
/// - la edición exige **justificación** de al menos 10 caracteres;
/// - no se puede editar un boleto anulado;
/// - sin cambios reales no se envía nada;
/// - el historial de ediciones se muestra y las ediciones quedan registradas.
class _FakeApi extends ApiClient {}

class _RepoEditable extends WeighingRepository {
  _RepoEditable({this.error})
      : super(
          apiClient: _FakeApi(),
          dbHelper: DatabaseHelper(),
          connectivity: Connectivity(),
        );

  final Object? error;
  Map<String, dynamic>? ultimoPayload;
  int llamadas = 0;
  List<BoletoEdicion> historial = const [];

  @override
  Future<List<BoletoEdicion>> getEdiciones(String boleto) async => historial;

  @override
  Future<Weighing> updateWeighing(String boleto, Map<String, dynamic> data) async {
    llamadas++;
    ultimoPayload = data;
    if (error != null) throw error!;
    return _boleto(estado: 'MODIFICADO', documento: data['documento'] as String?);
  }
}

Weighing _boleto({
  String estado = 'CERRADO',
  String? documento,
  String? observaciones,
  double? pesoNeto = 15000,
}) {
  final now = DateTime.utc(2026, 10, 14, 10, 0);
  return Weighing(
    boleto: '11111111-1111-1111-1111-111111111111',
    numeroBoleto: 'TA-00000001',
    idVehiculo: 'ABC123',
    productoNombre: 'MAÍZ',
    pesoEntradaVehiculo: 25000,
    pesoSalidaVehiculo: 10000,
    pesoNeto: pesoNeto,
    documento: documento,
    observaciones: observaciones,
    fechaHoraEntrada: now,
    fechaHoraSalida: now.add(const Duration(minutes: 30)),
    estadoBoleto: estado,
    createdAt: now,
    updatedAt: now,
  );
}

BoletoEdicion _edicion(int n, String just) => BoletoEdicion(
      idEdicion: 'e$n',
      boleto: '11111111-1111-1111-1111-111111111111',
      numeroBoleto: 'TA-00000001',
      usuarioNombre: 'Admin Uno',
      fechaEdicion: DateTime.utc(2026, 10, 14, 9, 30),
      justificacion: just,
      estadoAnterior: 'CERRADO',
      estadoNuevo: 'MODIFICADO',
      camposModificados: const {'documento': 'OLD -> NEW'},
      edicionNumero: n,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RepoEditable repo;

  Future<void> montar(WidgetTester tester, Weighing boleto,
      {Object? error, List<BoletoEdicion>? historial}) async {
    repo = _RepoEditable(error: error);
    if (historial != null) repo.historial = historial;
    await di.sl.reset();
    di.sl.registerLazySingleton<WeighingRepository>(() => repo);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => EditarBoletoDialog.mostrar(context, boleto),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra la justificación y el historial, y guarda con cambios',
      (tester) async {
    await montar(tester, _boleto(documento: 'OLD'), historial: [
      _edicion(1, 'Corrección de documento por error de tipeo'),
    ]);

    // Hay campo de justificación y el historial aparece.
    expect(find.text('Justificación (obligatoria)'), findsOneWidget);
    expect(find.text('Corrección de documento por error de tipeo'), findsOneWidget);
    expect(find.text('Edición 1'), findsOneWidget);

    // Sin justificación → error y no se llama al backend.
    await tester.enterText(find.byType(TextField).at(0), 'NEW');
    await tester.tap(find.text('Guardar edición'));
    await tester.pumpAndSettle();
    expect(repo.llamadas, 0);

    // Con justificación válida → se envía el payload completo.
    await tester.enterText(
      find.byType(TextField).last,
      'Corrijo el número de documento mal digitado',
    );
    await tester.tap(find.text('Guardar edición'));
    await tester.pumpAndSettle();
    expect(repo.llamadas, 1);
    expect(repo.ultimoPayload!['documento'], 'NEW');
    expect(
      repo.ultimoPayload!['justificacion'],
      'Corrijo el número de documento mal digitado',
    );
  });

  testWidgets('sin cambios reales no se envía la edición', (tester) async {
    await montar(tester, _boleto(documento: 'SAME'));
    await tester.enterText(
      find.byType(TextField).last,
      'Justifico una edición que no cambia nada',
    );
    await tester.tap(find.text('Guardar edición'));
    await tester.pumpAndSettle();
    expect(repo.llamadas, 0);
  });

  testWidgets('un boleto anulado no ofrece guardar', (tester) async {
    await montar(tester, _boleto(estado: 'ANULADO'));
    expect(find.text('Guardar edición'), findsNothing);
    expect(find.text('Un boleto anulado no se puede editar.'), findsOneWidget);
    expect(find.text('Cerrar'), findsOneWidget);
  });

  testWidgets('un 409 del backend (tope alcanzado) se muestra al usuario',
      (tester) async {
    await montar(
      tester,
      _boleto(documento: 'OLD'),
      error: Exception('Se alcanzó el máximo de ediciones permitidas '
          'para este boleto (2). Solicite al administrador de la cuenta.'),
    );
    await tester.enterText(find.byType(TextField).at(0), 'NEW');
    await tester.enterText(
      find.byType(TextField).last,
      'Edición que el backend rechaza por tope',
    );
    await tester.tap(find.text('Guardar edición'));
    await tester.pumpAndSettle();
    expect(repo.llamadas, 1);
    expect(
      find.textContaining('Se alcanzó el máximo de ediciones'),
      findsOneWidget,
    );
  });

  testWidgets('sin conexión no se edita y se avisa (no se salta la RB)',
      (tester) async {
    await montar(
      tester,
      _boleto(documento: 'OLD'),
      error: const EdicionRequiereConexionException(),
    );
    await tester.enterText(find.byType(TextField).at(0), 'NEW');
    await tester.enterText(
      find.byType(TextField).last,
      'Edición que requiere conexión con el servidor',
    );
    await tester.tap(find.text('Guardar edición'));
    await tester.pumpAndSettle();

    // El mensaje se traduce (clave i18n), no se filtra el texto de la excepción.
    expect(
      find.text('Editar un boleto requiere conexión con el servidor.'),
      findsOneWidget,
    );
    expect(find.textContaining('edit_ticket_needs_connection'), findsNothing);
  });
}
