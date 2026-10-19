import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/presentation/screens/settings/backups_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi extends ApiClient {
  final List<Map<String, dynamic>> respaldos;
  int restauraciones = 0;

  _FakeApi({this.respaldos = const []});

  @override
  Future<List<Map<String, dynamic>>> listarBackups() async => respaldos;

  @override
  Future<Map<String, dynamic>> crearBackupAuto() async =>
      const {'archivo': 'backup_manual.json.gz'};

  @override
  Future<Map<String, dynamic>> restaurarBackup(
    String archivo, {
    bool confirmar = false,
  }) async {
    restauraciones++;
    return const {'archivo': '', 'restaurados': {}, 'advertencia': ''};
  }
}

const _respaldoDemo = {
  'archivo': 'backup_abc.json.gz',
  'creado_en': '2026-10-09T12:00:00+00:00',
  'motivo': 'auto',
  'tamano_bytes': 4096,
  'id_empresa': '00000000-0000-0000-0000-000000000001',
  'empresa_nombre': 'Demo SA',
  'empresa_rif': 'J-12345678-9',
  'conteos': {'boletos_pesaje': 7},
  'version': 1,
};

void main() {
  testWidgets('estado vacío muestra mensaje y botón de crear', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: BackupsScreen(apiClient: _FakeApi())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Respaldos'), findsOneWidget); // AppBar
    expect(find.text('No hay respaldos todavía'), findsOneWidget);
    expect(find.text('Crear respaldo ahora'), findsOneWidget);
  });

  testWidgets('lista los respaldos y permite restaurar con confirmación',
      (tester) async {
    final api = _FakeApi(respaldos: [_respaldoDemo]);
    await tester.pumpWidget(MaterialApp(home: BackupsScreen(apiClient: api)));
    await tester.pumpAndSettle();

    expect(find.text('backup_abc.json.gz'), findsOneWidget);
    expect(find.textContaining('Boletos: 7'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.restore_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Restaurar respaldo'), findsOneWidget);

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(api.restauraciones, 1);
  });

  testWidgets('cancelar la restauración no ejecuta nada', (tester) async {
    final api = _FakeApi(respaldos: [_respaldoDemo]);
    await tester.pumpWidget(MaterialApp(home: BackupsScreen(apiClient: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.restore_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(api.restauraciones, 0);
  });
}