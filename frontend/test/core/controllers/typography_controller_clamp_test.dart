import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:balansoft_ws/presentation/providers/text_scaler_provider.dart';
import 'package:balansoft_ws/core/controllers/typography_controller.dart';
import 'package:balansoft_ws/core/utils/clamped_text_scaler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TypographyController - clamp y rangos', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('selector UI permite valores entre 0.85 y 1.40', () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = TypographyController(prefs: prefs);
      await controller.load();

      await controller.setTextScale(0.85);
      expect(controller.textScale, closeTo(0.85, 1e-4));
      expect(controller.isValidScale(controller.textScale), isTrue);

      await controller.setTextScale(1.00);
      expect(controller.textScale, closeTo(1.00, 1e-4));
      expect(controller.isValidScale(controller.textScale), isTrue);

      await controller.setTextScale(1.40);
      expect(controller.textScale, closeTo(1.40, 1e-4));
      expect(controller.isValidScale(controller.textScale), isTrue);
    });

    test('clamp técnico protege fuera del rango UI [0.85,1.50] externo', () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = TypographyController(prefs: prefs);
      await controller.load();

      await controller.setTextScale(0.50);
      expect(controller.textScale, closeTo(0.85, 1e-4));

      await controller.setTextScale(2.00);
      expect(controller.textScale, closeTo(1.40, 1e-4));

      const scalerBelow = ClampedTextScaler(0.80, min: 0.85, max: 1.50);
      expect(scalerBelow.clampValue(0.80), closeTo(0.85, 1e-4));

      const scalerAbove = ClampedTextScaler(1.60, min: 0.85, max: 1.50);
      expect(scalerAbove.clampValue(1.60), closeTo(1.50, 1e-4));

      const scalerOk = ClampedTextScaler(1.40, min: 0.85, max: 1.50);
      expect(scalerOk.clampValue(1.40), closeTo(1.40, 1e-4));
    });

    test('persistencia y defaults correctos', () async {
      {
        final prefs = await SharedPreferences.getInstance();
        final controller = TypographyController(prefs: prefs);
        await controller.load();
        await controller.setTextScale(1.20);
        expect(controller.textScale, closeTo(1.20, 1e-4));
      }

      {
        final prefs = await SharedPreferences.getInstance();
        final controller = TypographyController(prefs: prefs);
        await controller.load();
        expect(controller.textScale, closeTo(1.20, 1e-4));
      }

      SharedPreferences.setMockInitialValues({});
      final prefsClean = await SharedPreferences.getInstance();
      final controllerClean = TypographyController(prefs: prefsClean);
      await controllerClean.load();
      expect(controllerClean.textScale, closeTo(1.00, 1e-4));
      expect(controllerClean.tipoFuenteTicket, equals('DejaVu'));
      expect(controllerClean.tamanoTicketPdf, equals('AUTOMATICO'));
    });
  });

  group('TypographyController - familia de UI (REQ-FN-007)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('ofrece las 5 familias y su fontFamily', () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = TypographyController(prefs: prefs);
      await controller.load();

      expect(TypographyController.familiasUi.length, 5);
      expect(TypographyController.familiasUi, [
        'SISTEMA',
        'SANS_SERIF',
        'SERIF',
        'MONOSPACE',
        'ROBOTO',
      ]);

      // Por defecto la familia del sistema: fontFamily null, que es lo que
      // hace Flutter para tomar la del sistema operativo.
      expect(controller.familiaUi, equals('SISTEMA'));
      expect(controller.familiaUiFontFamily, isNull);

      final esperadas = <String, String?>{
        'SISTEMA': null,
        'SANS_SERIF': 'sans-serif',
        'SERIF': 'serif',
        'MONOSPACE': 'monospace',
        'ROBOTO': 'Roboto',
      };
      for (final familia in TypographyController.familiasUi) {
        await controller.setFamiliaUi(familia);
        expect(
          controller.familiaUiFontFamily,
          equals(esperadas[familia]),
          reason: 'fontFamily inesperado para $familia',
        );
      }
    });

    test('la familia se persiste y se restaura al reabrir', () async {
      {
        final prefs = await SharedPreferences.getInstance();
        final controller = TypographyController(prefs: prefs);
        await controller.load();
        await controller.setFamiliaUi('SERIF');
        expect(controller.familiaUi, equals('SERIF'));
      }

      // Reapertura: nueva instancia del controlador sobre las mismas
      // preferencias, que es lo que hace la app al volver a abrir Ajustes.
      {
        final prefs = await SharedPreferences.getInstance();
        final controller = TypographyController(prefs: prefs);
        await controller.load();
        expect(controller.familiaUi, equals('SERIF'));
        expect(controller.familiaUiFontFamily, equals('serif'));
      }
    });

    test('una preferencia corrupta cae al default y no rompe el arranque',
        () async {
      for (final corrupto in ['Comic Sans', '', '   ', 'sans-serif']) {
        SharedPreferences.setMockInitialValues({'app.familiaUi': corrupto});
        final prefs = await SharedPreferences.getInstance();
        final controller = TypographyController(prefs: prefs);
        await controller.load();

        expect(controller.familiaUi, equals('SISTEMA'),
            reason: 'no cayó al default con "$corrupto"');
        expect(controller.familiaUiFontFamily, isNull);
      }
    });

    test('no persiste una familia desconocida', () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = TypographyController(prefs: prefs);
      await controller.load();

      await controller.setFamiliaUi('Papyrus');
      expect(controller.familiaUi, equals('SISTEMA'));
      expect(prefs.getString('app.familiaUi'), isNull);
    });

    test('un tamano de ticket corrupto cae a AUTOMATICO', () async {
      SharedPreferences.setMockInitialValues({
        'empresa.tamanoTicketPdf': 'ENORME',
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = TypographyController(prefs: prefs);
      await controller.load();

      expect(controller.tamanoTicketPdf, equals('AUTOMATICO'));
    });
  });

  group('TextScalerProvider', () {
    test('proporciona textScaler coherente con el controlador', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = TypographyController(prefs: prefs);
      await controller.load();
      await controller.setTextScale(1.15);

      final provider = TextScalerProvider(controller: controller);
      expect(provider.textScale, closeTo(1.15, 1e-4));
      expect(provider.textScaler, isA<ClampedTextScaler>());
    });
  });

  /// Regresión de T10b: `load()` no debe notificar cuando nada cambia.
  ///
  /// `load()` se llama desde el `initState` de dos sitios (la app y la pantalla
  /// de Ajustes → Tipografía). Con `notifyListeners()` incondicional, la
  /// segunda llamada —que no cambia ningún valor— marcaba como sucio el
  /// `ListenableBuilder` de `TipografiaScope` **durante el build**, y Flutter
  /// lanzaba «setState() or markNeedsBuild() called during build». Se veía como
  /// error en cada apertura de la pantalla de tipografía.
  group('TypographyController - load() sin ruido', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'app.textScaleFactor': 1.25,
        'app.familiaUi': 'MONOSPACE',
        'app.tipoFuenteTicket': 'DejaVu',
        'app.tamanoTicketPdf': 'MEDIANO',
      });
    });

    test('no notifica si los valores no cambian', () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = TypographyController(prefs: prefs);

      await controller.load(); // primera lectura: sí cambia, sí notifica
      var notificaciones = 0;
      controller.addListener(() => notificaciones++);

      await controller.load(); // segunda lectura: no cambia nada
      expect(notificaciones, 0,
          reason: 'una lectura que no cambia nada no debe notificar: el '
              'notificado se marca sucio durante el build');

      await controller.load();
      expect(notificaciones, 0);
    });

    test('sí notifica cuando un valor cambia de verdad', () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = TypographyController(prefs: prefs);
      await controller.load();

      await prefs.setDouble('app.textScaleFactor', 0.9);
      var notificaciones = 0;
      controller.addListener(() => notificaciones++);

      await controller.load();
      expect(notificaciones, 1);
      expect(controller.textScale, closeTo(0.9, 1e-9));
    });
  });
}
