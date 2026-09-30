import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/config/app_config.dart';
import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/screens/settings/system_diagnostics_screen.dart';

/// Estación sana: todos los chequeos en OK.
class _FakeApiOk extends ApiClient {
  @override
  Future<bool> health() async => true;

  @override
  Future<Map<String, dynamic>?> environment({String? baseUrl}) async => {
        'estado': 'ok',
        'sistema': {'app_role': 'local', 'hostname': 'ESTACION-01'},
        'api': {'version': '1.2.8'},
        'postgres': {
          'conectado': true,
          'esquema_listo': true,
          'n_tablas': 22,
          'bd': 'balansoft_ws_local',
        },
      };

  @override
  Future<Map<String, dynamic>> getLicenseSnapshot() async => {
        'valid': true,
        'status': 'ACTIVA',
        'tier': 'CENTRAL PRO',
        'expires_at': '2026-12-31T23:59:59',
      };

  @override
  Future<Map<String, dynamic>?> syncStatus() async => {
        'pendientes': 0,
        'ultima_sync': '2026-09-29T14:30:00',
      };
}

/// Estación con WServer caído: debe señalar el problema, no romper la pantalla.
class _FakeApiCaido extends ApiClient {
  @override
  Future<bool> health() async => false;

  @override
  Future<Map<String, dynamic>?> environment({String? baseUrl}) async => null;

  @override
  Future<Map<String, dynamic>> getLicenseSnapshot() async {
    throw Exception('401');
  }

  @override
  Future<Map<String, dynamic>?> syncStatus() async => null;
}

/// `di.sl.reset()` es asíncrono: hay que awaited para que su continuación no
/// se ejecute dentro del FakeAsync de testWidgets y borre lo registrado después.
Future<void> _registrar(ApiClient client) async {
  await di.sl.reset();
  di.sl.registerSingleton<ApiClient>(client);
}

Widget _app() => MaterialApp(
    theme: buildLightTheme(), home: const SystemDiagnosticsScreen());

void main() {
  setUp(() {
    AppConfig.apiBaseUrl = 'http://localhost:8000';
  });

  testWidgets('diagnóstico muestra los cinco chequeos y el resumen correcto',
      (tester) async {
    await _registrar(_FakeApiOk());
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    for (final titulo in [
      'API local',
      'Base de datos',
      'Licencia',
      'Sincronización',
      'Versión',
    ]) {
      expect(find.text(titulo), findsOneWidget,
          reason: 'falta la tarjeta $titulo');
    }

    expect(find.textContaining('balansoft_ws_local'), findsOneWidget);
    expect(find.textContaining('22 tablas'), findsOneWidget);
    expect(find.textContaining('CENTRAL PRO'), findsOneWidget);
    expect(find.textContaining('0 pendientes'), findsOneWidget);
    expect(find.textContaining(AppConfig.appVersion), findsOneWidget);
    expect(find.textContaining('Todo en orden'), findsOneWidget);
  });

  testWidgets('diagnóstico con API caída reporta el problema sin desbordar',
      (tester) async {
    await _registrar(_FakeApiCaido());
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.textContaining('Se detectaron'), findsOneWidget);
    expect(find.textContaining('Sin respuesta en'), findsOneWidget);
    expect(
      find.text('No se pudo consultar el estado de la base de datos.'),
      findsOneWidget,
    );
    expect(
        find.textContaining('Servidor central no disponible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
