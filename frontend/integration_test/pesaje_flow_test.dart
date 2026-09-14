import 'package:balansoft_ws/core/config/app_config.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Prueba end-to-end (requiere backend corriendo en
/// `http://localhost:8000` con datos sembrados por `scripts/seed_data.py`).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Flujo completo: Login → Nuevo pesaje (entrada)',
      (tester) async {
    await AppConfig.init();
    await app.themeController.load();
    await di.init();

    await tester.pumpWidget(const app.BalansoftApp());
    await tester.pumpAndSettle();

    // 1. Login con el admin sembrado por seed_data.py
    expect(find.byKey(const Key('email_field')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('email_field')), 'admin@balansoft.demo');
    await tester.enterText(
        find.byKey(const Key('password_field')), 'demo1234');
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 2. Ir a la pantalla de pesajes
    expect(find.byKey(const Key('new_weighing_fab')), findsOneWidget);
    await tester.tap(find.byKey(const Key('new_weighing_fab')));
    await tester.pumpAndSettle();

    // 3. Llenar la entrada del boleto
    expect(find.byKey(const Key('placa_field')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('placa_field')), 'EZE-2026');
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('peso_entrada_field')), '15000');
    await tester.pumpAndSettle();

    // 4. Guardar entrada
    final guardar = find.byKey(const Key('guardar_entrada_button'));
    expect(guardar, findsOneWidget);
    await tester.tap(guardar, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Tras guardar se vuelve al historial (el guardado completo depende de
    // que los catálogos estén sincronizados en la BD local).
    expect(
      find.byKey(const Key('new_weighing_fab')),
      findsWidgets,
    );
  });
}