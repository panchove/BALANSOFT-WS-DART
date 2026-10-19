import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balansoft_ws/core/controllers/typography_controller.dart';
import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:balansoft_ws/presentation/widgets/tipografia_scope.dart';

/// Texto con `fontSize:` fijo, **sin** `MediaQuery` ni envoltura tipográfica: es
/// el caso real de los 322 `fontSize:` del código, que el ajuste tiene que
/// escalar sin tocar ninguno.
class _TextoFijo extends StatelessWidget {
  const _TextoFijo();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Pesaje',
      style: TextStyle(fontSize: 16),
    );
  }
}

/// Ancho que el texto ya escalado ocupa en pantalla. Se mide en vez de leer el
/// `TextStyle`, porque lo que importa es lo que se ve en la estación.
///
/// Se mide el **ancho** y no el alto porque el alto redondea a píxeles enteros
/// (a 1.0 mide 23 px, a 0.85 mide 19 y a 1.40 mide 32) y perdería precisión en
/// el factor; el ancho escala de forma proporcional.
double anchoRenderizado(WidgetTester tester) {
  return tester.getSize(find.text('Pesaje')).width;
}

/// Factor real de escalado del texto fijo, relativo al ancho sin ajustar.
double factorRenderizado(double anchoBase, double ancho) => ancho / anchoBase;

/// Tolerancia de las medidas de render: son décimas de píxel y la fuente de
/// respaldo puede variar entre plataformas.
const _tolerancia = 0.02;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TypographyController controlador;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    controlador = TypographyController(
      prefs: await SharedPreferences.getInstance(),
    );
    await controlador.load();
  });

  /// Factor de escalado "del sistema operativo", como el que fija la
  /// accesibilidad del SO. Va por `textScaleFactorTestValue` y no con un
  /// `MediaQuery` externo porque `MaterialApp` **crea su propio** `MediaQuery`
  /// desde la vista: uno colocado por fuera se descarta.
  void factorExterno(WidgetTester tester, double factor) {
    tester.platformDispatcher.textScaleFactorTestValue = factor;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// Monta el `TipografiaScope` **sin** ningún otro que reconstruya: si el
  /// ajuste se aplica a un `Text` ya montado, es porque el propio scope escucha
  /// al controlador. Por eso aquí no hay ningún `AnimatedBuilder` alrededor, que
  /// es justamente lo que hay que demostrar.
  Future<void> montar(WidgetTester tester, {double externo = 1.0}) async {
    factorExterno(tester, externo);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(
          familia: controlador.familiaUiFontFamily,
          factorIconos: controlador.textScale,
        ),
        builder: (context, hijo) => TipografiaScope(
          controlador: controlador,
          child: hijo!,
        ),
        home: const Scaffold(body: _TextoFijo()),
      ),
    );
    await tester.pump();
  }

  /// Monta la composición completa de `main.dart`, incluido el `AnimatedBuilder`
  /// que escucha al controlador. Hace falta solo para el caso de la **familia**,
  /// que va en el `ThemeData` y por tanto la reconstruye quien contiene el
  /// `MaterialApp` (`main.dart`, en su `Listenable.merge`); el factor va en el
  /// `MediaQuery` y lo reconstruye el `TipografiaScope`.
  Future<void> montarComoMain(WidgetTester tester, {double externo = 1.0}) async {
    factorExterno(tester, externo);
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: controlador,
        builder: (context, _) => MaterialApp(
          theme: buildLightTheme(
            familia: controlador.familiaUiFontFamily,
            factorIconos: controlador.textScale,
          ),
          builder: (context, hijo) => TipografiaScope(
            controlador: controlador,
            child: hijo!,
          ),
          home: const Scaffold(body: _TextoFijo()),
        ),
      ),
    );
    await tester.pump();
  }

  /// Ancho del texto con el ajuste por defecto (factor 1.0): la referencia para
  /// comparar, medida en el mismo árbol y con la misma fuente.
  ///
  /// Ojo con el orden: [montar] fija el factor externo **antes** de `pumpWidget`,
  /// y por eso el ancho base hay que medirlo en un árbol ya montado. Cambiar
  /// `textScaleFactorTestValue` con la app montada no relanza el layout del
  /// `RenderParagraph` en el binding de pruebas (sí lo hace en un dispositivo,
  /// donde llega por el canal de accesibilidad), así que los casos de factor
  /// externo se comprueban sobre el escalador que el árbol recibe, que es lo
  /// que decide el tamaño final.
  Future<double> anchoBase(WidgetTester tester) async {
    await montar(tester);
    return anchoRenderizado(tester);
  }

  /// Factor con el que el texto se painted realmente, leído del `MediaQuery`
  /// que el árbol tiene montado. Es la misma ruta que usa `Text` para decidir
  /// el tamaño final de cada `fontSize:`.
  double factorEfectivo(WidgetTester tester) {
    final escala16 = MediaQuery.textScalerOf(
      tester.element(find.byType(_TextoFijo)),
    ).scale(16);
    return escala16 / 16;
  }

  group('REQ-FN-002 — el factor escala los fontSize fijos en pantalla', () {
    testWidgets('con factor 1.0 el texto se ve igual que hoy (no-regresión)',
        (tester) async {
      final base = await anchoBase(tester);
      expect(factorRenderizado(base, anchoRenderizado(tester)),
          closeTo(1.0, _tolerancia));
    });

    testWidgets('con factor 1.40 el texto fijo crece un 40%', (tester) async {
      final base = await anchoBase(tester);
      await controlador.setTextScale(1.40);
      await montar(tester);
      expect(factorRenderizado(base, anchoRenderizado(tester)),
          closeTo(1.40, _tolerancia));
    });

    testWidgets('con factor 0.85 el texto fijo se encoge un 15%', (tester) async {
      final base = await anchoBase(tester);
      await controlador.setTextScale(0.85);
      await montar(tester);
      expect(factorRenderizado(base, anchoRenderizado(tester)),
          closeTo(0.85, _tolerancia));
    });

    testWidgets('el texto escala en los dos extremos del selector',
        (tester) async {
      final base = await anchoBase(tester);
      for (final factor in [0.85, 1.0, 1.15, 1.40]) {
        await controlador.setTextScale(factor);
        await montar(tester);
        expect(factorRenderizado(base, anchoRenderizado(tester)),
            closeTo(factor, _tolerancia),
            reason: 'con factor $factor');
      }
    });

    testWidgets('con factor externo 2.0 el texto no llega a duplicarse '
        '(REQ-FN-002b)', (tester) async {
      // El SO con accesibilidad al doble: el clamp técnico lo deja en 1.60, y
      // el texto se pinta un 60% más grande, no un 100%.
      await montar(tester, externo: 2.0);
      expect(factorEfectivo(tester), closeTo(1.60, _tolerancia));
      expect(anchoRenderizado(tester), lessThan(193.5));
    });

    testWidgets('lo externo y lo del operador se componen sin recortarse',
        (tester) async {
      // Externo 2.0 acotado a 1.60 y operador a 1.40: el factor efectivo se
      // queda en el techo de 1.60 en vez de llegar a 2.24.
      await controlador.setTextScale(1.40);
      await montar(tester, externo: 2.0);
      expect(factorEfectivo(tester), closeTo(1.60, _tolerancia));
    });

    testWidgets('el texto nunca se sale de [0.85, 1.60] pase lo que pase',
        (tester) async {
      for (final externo in [0.1, 1.0, 5.0]) {
        for (final factor in [0.85, 1.40]) {
          await controlador.setTextScale(factor);
          await montar(tester, externo: externo);
          final real = factorEfectivo(tester);
          expect(real, greaterThanOrEqualTo(0.85 - _tolerancia),
              reason: 'externo $externo, operador $factor');
          expect(real, lessThanOrEqualTo(1.60 + _tolerancia),
              reason: 'externo $externo, operador $factor');
        }
      }
    });
  });

  group('REQ-FN-004 — el ajuste se aplica sin reiniciar', () {
    testWidgets('cambiar el factor con la app ya montada redibuja la pantalla',
        (tester) async {
      await montar(tester);
      final base = anchoRenderizado(tester);
      expect(factorRenderizado(base, anchoRenderizado(tester)),
          closeTo(1.0, _tolerancia));

      // Sin volver a montar nada: el controlador notifica y `TipografiaScope`
      // reconstruye el `MediaQuery`.
      await controlador.setTextScale(1.40);
      await tester.pump();

      expect(factorRenderizado(base, anchoRenderizado(tester)),
          closeTo(1.40, _tolerancia));
      expect(find.byType(_TextoFijo), findsOneWidget);
    });

    testWidgets('cambiar la familia con la app ya montada repinta el texto',
        (tester) async {
      await montarComoMain(tester);

      await controlador.setFamiliaUi('MONOSPACE');
      // `MaterialApp` envuelve el tema en un `AnimatedTheme`, así que el
      // cambio de familia se interpola: hay que dejar correr la animación.
      await tester.pumpAndSettle();

      // El `Text` fija su propio `fontSize` y no su familia, así que lo que
      // manda es la del tema: se comprueba en el `TextTheme` que hereda la app.
      final estilo = tester.widget<Text>(find.text('Pesaje')).style!;
      expect(estilo.fontFamily, isNull);
      expect(
        Theme.of(tester.element(find.text('Pesaje')))
            .textTheme
            .bodyMedium
            ?.fontFamily,
        equals('monospace'),
      );
    });

    testWidgets('varios cambios seguidos se acumulan sin reiniciar',
        (tester) async {
      await montar(tester);
      final base = anchoRenderizado(tester);

      for (final factor in [1.10, 1.25, 0.90, 1.40]) {
        await controlador.setTextScale(factor);
        await tester.pump();
        expect(factorRenderizado(base, anchoRenderizado(tester)),
            closeTo(factor, _tolerancia),
            reason: 'tras poner $factor');
      }
    });
  });

  group('REQ-FN-005 — el ajuste persistido se restituye al arrancar', () {
    testWidgets('al cargar el controlador se aplica lo que había guardado',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'app.textScaleFactor': 1.40,
        'app.familiaUi': 'SERIF',
      });
      final prefs = await SharedPreferences.getInstance();
      final restaurado = TypographyController(prefs: prefs);
      await restaurado.load();

      expect(restaurado.textScale, closeTo(1.40, 1e-9));
      expect(restaurado.familiaUiFontFamily, equals('serif'));

      // Y una instancia nueva de la app arranca ya con el ajuste puesto, sin
      // esperar a que el operador abra Ajustes.
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: MaterialApp(
            theme: buildLightTheme(
              familia: restaurado.familiaUiFontFamily,
              factorIconos: restaurado.textScale,
            ),
            builder: (context, hijo) => TipografiaScope(
              controlador: restaurado,
              child: hijo!,
            ),
            home: const Scaffold(body: _TextoFijo()),
          ),
        ),
      );
      await tester.pump();

      // 16 px × 1.40: el `Text` sin ajuste mide ~97,5 px de ancho, con el
      // ajuste puesto mide 1.40 veces.
      expect(anchoRenderizado(tester) / 97.5, closeTo(1.40, _tolerancia));
    });

    testWidgets('una preferencia corrupta no rompe el arranque',
        (tester) async {
      // Un factor y una familia escritos a mano, o restaurados de un backup de
      // otra versión, no pueden dejar la pantalla sin pintar (REQ-FN-006).
      SharedPreferences.setMockInitialValues({
        'app.textScaleFactor': 99.0,
        'app.familiaUi': 'FAMILIA_INVENTADA',
      });
      final prefs = await SharedPreferences.getInstance();
      final restaurado = TypographyController(prefs: prefs);
      await restaurado.load();

      expect(restaurado.textScale, closeTo(TypographyController.maxUiScale, 1e-9));
      expect(restaurado.familiaUi, TypographyController.familiaUiPorDefecto);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: MaterialApp(
            theme: buildLightTheme(
              familia: restaurado.familiaUiFontFamily,
              factorIconos: restaurado.textScale,
            ),
            builder: (context, hijo) => TipografiaScope(
              controlador: restaurado,
              child: hijo!,
            ),
            home: const Scaffold(body: _TextoFijo()),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(_TextoFijo), findsOneWidget);
    });
  });

  group('REQ-FN-006 — familia no instalada', () {
    testWidgets('una familia que no existe en el sistema no lanza ni falta',
        (tester) async {
      // El nombre se aplica tal cual al tema: si la fuente no está, el motor cae
      // a la siguiente de su lista. Lo que exige el requisito es que no haya
      // excepción, aviso ni texto invisible.
      SharedPreferences.setMockInitialValues({'app.familiaUi': 'MONOSPACE'});
      final prefs = await SharedPreferences.getInstance();
      final c = TypographyController(prefs: prefs);
      await c.load();
      // Se fuerza un nombre inexistente por la vía del tema, que es la que
      // recibe el nombre crudo.
      final tema = buildLightTheme(familia: 'FuenteQueNoExiste_0000');

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: MaterialApp(
            theme: tema,
            builder: (context, hijo) => TipografiaScope(
              controlador: c,
              child: hijo!,
            ),
            home: const Scaffold(body: _TextoFijo()),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(_TextoFijo), findsOneWidget);
      expect(anchoRenderizado(tester), greaterThan(0));
    });
  });

  group('REQ-FN-003 — los iconos heredan el factor', () {
    testWidgets('un Icon sin size explícito toma el del tema escalado',
        (tester) async {
      await controlador.setTextScale(1.40);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(factorIconos: controlador.textScale),
          home: const Scaffold(
            body: Center(child: Icon(Icons.save)),
          ),
        ),
      );
      await tester.pump();

      final icono = tester.widget<Icon>(find.byType(Icon));
      expect(icono.size, isNull, reason: 'no fija tamaño: lo hereda del tema');

      // 20 px base × 1.40 = 28 px.
      expect(tester.getSize(find.byType(Icon)).width, closeTo(28, 0.01));
    });

    testWidgets('con factor 1.0 el icono se ve como hoy', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: const Scaffold(body: Center(child: Icon(Icons.save))),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(Icon)).width, closeTo(20, 0.01));
    });
  });
}