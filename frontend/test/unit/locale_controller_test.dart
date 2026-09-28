import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:balansoft_ws/core/i18n/locale_controller.dart';
import 'package:balansoft_ws/core/i18n/translations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocaleController Unit Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Por defecto idioma es system y locale resuelve el idioma del dispositivo', () async {
      final controller = LocaleController();
      await controller.load();

      expect(controller.language, AppLanguage.system);
      expect(controller.locale, isNotNull);
      expect(controller.locale.languageCode, controller.activeLanguageCode);
    });

    test('Cambio a Español (ES) actualiza locale y persiste', () async {
      final controller = LocaleController();
      await controller.load();

      await controller.setLanguage(AppLanguage.es);
      expect(controller.language, AppLanguage.es);
      expect(controller.locale, const Locale('es'));
      expect(controller.activeLanguageCode, 'es');

      // Nuevo controller carga el valor persistido
      final controller2 = LocaleController();
      await controller2.load();
      expect(controller2.language, AppLanguage.es);
      expect(controller2.locale, const Locale('es'));
    });

    test('Cambio a Inglés (EN) y Portugués (PT)', () async {
      final controller = LocaleController();
      await controller.load();

      await controller.setLanguage(AppLanguage.en);
      expect(controller.language, AppLanguage.en);
      expect(controller.locale, const Locale('en'));
      expect(controller.activeLanguageCode, 'en');

      await controller.setLanguage(AppLanguage.pt);
      expect(controller.language, AppLanguage.pt);
      expect(controller.locale, const Locale('pt'));
      expect(controller.activeLanguageCode, 'pt');
    });

    test('AppTranslations devuelve textos correctos en ES, EN y PT', () {
      expect(AppTranslations.tr('status_online', langCode: 'es'), 'Online');
      expect(AppTranslations.tr('status_offline', langCode: 'es'), 'Offline');
      expect(AppTranslations.tr('status_no_network', langCode: 'es'), 'Sin red');

      expect(AppTranslations.tr('status_no_network', langCode: 'en'), 'Offline mode');
      expect(AppTranslations.tr('language_title', langCode: 'en'), 'System Language');

      expect(AppTranslations.tr('status_no_network', langCode: 'pt'), 'Sem rede');
      expect(AppTranslations.tr('language_title', langCode: 'pt'), 'Idioma do Sistema');

      // Claves de menú
      expect(AppTranslations.tr('menu_inicio', langCode: 'es'), 'Inicio');
      expect(AppTranslations.tr('menu_inicio', langCode: 'en'), 'Home / Weighing');
      expect(AppTranslations.tr('menu_inicio', langCode: 'pt'), 'Início / Pesagem');

      expect(AppTranslations.tr('menu_reportes', langCode: 'es'), 'REPORTES');
      expect(AppTranslations.tr('menu_reportes', langCode: 'en'), 'REPORTS');
      expect(AppTranslations.tr('menu_reportes', langCode: 'pt'), 'RELATÓRIOS');

      expect(AppTranslations.tr('export_excel', langCode: 'es'), 'Exportar a Excel');
      expect(AppTranslations.tr('export_excel', langCode: 'en'), 'Export to Excel');
      expect(AppTranslations.tr('export_excel', langCode: 'pt'), 'Exportar para Excel');
    });
  });
}

