import 'package:balansoft_ws/core/config/app_config.dart';
import 'package:balansoft_ws/core/i18n/locale_controller.dart';
import 'package:balansoft_ws/core/i18n/translations.dart';
import 'package:balansoft_ws/core/widgets/company_setup_form.dart';
import 'package:balansoft_ws/presentation/screens/setup/company_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Monta la pantalla en el tamaño de una estación de pesaje (1366x768) y
  /// devuelve las excepciones de layout detectadas.
  Future<Object?> montar(WidgetTester tester, Size tamano) async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.init();
    final controller = LocaleController();
    await controller.load();
    AppTranslations.setController(controller);

    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: CompanySetupScreen(localeController: controller),
      ),
    );
    await tester.pumpAndSettle();
    return tester.takeException();
  }

  group('CompanySetupScreen', () {
    testWidgets(
        'se renderiza sin errores de layout en 1366x768 '
        '(el Expanded del form no puede vivir en un alto infinito)', (tester) async {
      final excepcion = await montar(tester, const Size(1366, 768));

      expect(excepcion, isNull);
      expect(find.byType(CompanySetupForm), findsOneWidget);
    });

    testWidgets('también se renderiza en formato ancho y bajo (1024x600)',
        (tester) async {
      final excepcion = await montar(tester, const Size(1024, 600));

      expect(excepcion, isNull);
      expect(find.byType(CompanySetupForm), findsOneWidget);
    });
  });
}
