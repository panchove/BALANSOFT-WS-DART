import 'package:balansoft_ws/core/i18n/translations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTranslations', () {
    test('las claves nuevas de instalación existen en es/en/pt', () {
      const claves = [
        'setup_preferences_title',
        'setup_step_language',
        'setup_step_theme',
        'setup_mode_title',
        'initial_setup_title',
        'initial_setup_report_format',
        'initial_setup_reports_folder',
        'connection_unreachable',
        'ticket_confirm_print',
        'ticket_weight_reading',
        'reports_exported',
      ];
      for (final lang in ['es', 'en', 'pt']) {
        for (final clave in claves) {
          final valor = AppTranslations.tr(clave, langCode: lang);
          expect(valor, isNot(clave),
              reason: 'falta la clave "$clave" en $lang');
        }
      }
    });

    test('tr() sustituye los argumentos {0} en los tres idiomas', () {
      expect(
        AppTranslations.tr('ticket_confirm_print', args: ['2']),
        'Confirmar e Imprimir (2)',
      );
      expect(
        AppTranslations.tr('ticket_confirm_print',
            langCode: 'en', args: ['3']),
        'Confirm and Print (3)',
      );
      expect(
        AppTranslations.tr('ticket_confirm_print',
            langCode: 'pt', args: ['1']),
        'Confirmar e Imprimir (1)',
      );
      expect(
        AppTranslations.tr('ticket_cut_i', langCode: 'en', args: ['2']),
        'Cut 2',
      );
    });

    test('el texto en español cae como fallback', () {
      expect(AppTranslations.tr('Guardar', langCode: 'es'), 'Guardar');
      expect(AppTranslations.tr('Guardar', langCode: 'en'), 'Save');
    });

    test('los tres diccionarios tienen exactamente las mismas claves', () {
      final es = AppTranslations.keys(langCode: 'es');
      final en = AppTranslations.keys(langCode: 'en');
      final pt = AppTranslations.keys(langCode: 'pt');

      expect(es.length, greaterThan(400),
          reason: 'el diccionario es/en/pt debe estar completo');
      expect(en.difference(es), isEmpty,
          reason: 'claves solo en en: ${en.difference(es)}');
      expect(pt.difference(es), isEmpty,
          reason: 'claves solo en pt: ${pt.difference(es)}');
      expect(es.difference(en), isEmpty,
          reason: 'claves solo en es: ${es.difference(en)}');
      expect(es.difference(pt), isEmpty,
          reason: 'claves solo en es: ${es.difference(pt)}');
    });

    test('ninguna clave queda vacía en los tres idiomas', () {
      for (final lang in ['es', 'en', 'pt']) {
        for (final clave in AppTranslations.keys(langCode: lang)) {
          expect(AppTranslations.tr(clave, langCode: lang).trim(), isNotEmpty,
              reason: 'la clave "$clave" está vacía en $lang');
        }
      }
    });

    test('las claves del ajuste de tipografía están traducidas en es/en/pt',
        () {
      // REQ-FN-007 (5 familias) y REQ-FN-019 (paridad). Ninguna puede quedar
      // como la propia clave en pantalla: se vería "tipografia_familia_serif".
      const claves = [
        'tipografia_titulo',
        'tipografia_subtitulo',
        'tipografia_ui_familia',
        'tipografia_ui_familia_scope',
        'tipografia_ui_escala',
        'tipografia_familia_sistema',
        'tipografia_familia_sans_serif',
        'tipografia_familia_serif',
        'tipografia_familia_monospace',
        'tipografia_familia_roboto',
        'tipografia_vista_previa',
        'tipografia_ticket_guardado',
        'tipografia_ticket_error',
        'tipografia_ticket_error_lectura',
      ];
      for (final lang in ['es', 'en', 'pt']) {
        for (final clave in claves) {
          final valor = AppTranslations.tr(clave, langCode: lang);
          expect(valor, isNot(clave), reason: 'falta la clave "$clave" en $lang');
          expect(valor.trim(), isNotEmpty, reason: '"$clave" vacía en $lang');
        }
      }

      // La familia por defecto debe decirlo en los tres idiomas: es la que
      // distingue "Sistema" de las otras cuatro.
      expect(AppTranslations.tr('tipografia_familia_sistema'), contains('Sistema'));
      expect(
        AppTranslations.tr('tipografia_familia_sistema', langCode: 'en'),
        contains('System'),
      );
      expect(
        AppTranslations.tr('tipografia_familia_sistema', langCode: 'pt'),
        contains('Sistema'),
      );
      // "Monoespaçada" no es "Monospace": una traducción ausente disfrazada de
      // copia en español no se distinguiría de una traducción real.
      expect(
        AppTranslations.tr('tipografia_familia_monospace', langCode: 'pt'),
        isNot(equals(AppTranslations.tr('tipografia_familia_monospace'))),
      );
    });

    test('las claves del flujo de instalación y empresa están traducidas', () {
      const claves = [
        'setup_company_title',
        'setup_company_subtitle',
        'setup_company_finish',
        'setup_company_pending_hint',
        'initial_setup_step_company',
        'initial_setup_step_reports',
        'ticket_design_title',
        'works_offline',
        'system_integrity',
        'env_check_intro',
      ];
      for (final lang in ['es', 'en', 'pt']) {
        for (final clave in claves) {
          expect(AppTranslations.tr(clave, langCode: lang), isNot(clave),
              reason: 'falta la clave "$clave" en $lang');
        }
      }
    });
  });
}
