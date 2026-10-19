import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/services/dialog_keyboard.dart';
import 'package:balansoft_ws/core/widgets/keyboard_dialog_wrapper.dart';
import 'package:balansoft_ws/presentation/widgets/atajo_nuevo.dart';

/// Arnés que replica el portón de `HomeShell._onKey`:
///
/// ```dart
/// if (ModalManager.hasOpenModals || DialogKeyboard.hayModalAbierto()) {
///   return DialogKeyboard.manejarTeclaEnModal(event);
/// }
/// … navegación/atajos del shell …
/// ```
///
/// Devolver `true` aquí corta la navegación del propio shell, pero **NO**
/// a los demás handlers del binding (Flutter los invoca a todos, sin corte
/// temprano). Por eso el CRUD real envuelve su pantalla en [AtajoNuevo],
/// que se autoprotege: ese es el componente que se prueba de verdad abajo.
class _Control {
  /// Resultado del portón para la última tecla pulsada (null = sin pulsar).
  bool? portonConsumio;

  /// Veces que el atajo `Ctrl+=` del CRUD disparó `onNuevo`.
  int nuevo = 0;

  /// Diálogos abiertos por [AtajoNuevo] (debe ser 0 con un modal puesto).
  int dialogosApilados = 0;
}

class _Arnes extends StatefulWidget {
  const _Arnes({required this.control});

  final _Control control;

  @override
  State<_Arnes> createState() => _ArnesState();
}

class _ArnesState extends State<_Arnes> {
  @override
  void initState() {
    super.initState();
    ServicesBinding.instance.keyboard.addHandler(_porton);
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_porton);
    super.dispose();
  }

  bool _porton(KeyEvent e) {
    // Igual que `HomeShell._onKey`: solo teclas pulsadas.
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    if (DialogKeyboard.hayModalAbierto()) {
      final consumio = DialogKeyboard.manejarTeclaEnModal(e);
      widget.control.portonConsumio = consumio;
      return consumio;
    }
    widget.control.portonConsumio = false;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: _Interior(control: widget.control));
  }
}

/// Interior del arnés: queda DEBAJO de [MaterialApp], así los diálogos que
/// abre `AtajoNuevo` tienen Localizations/Navigator.
class _Interior extends StatelessWidget {
  const _Interior({required this.control});

  final _Control control;

  @override
  Widget build(BuildContext context) {
    void nuevo() {
      control.nuevo++;
      control.dialogosApilados++;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Dialogo del CRUD'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Ok'),
            ),
          ],
        ),
      );
    }

    return AtajoNuevo(
      onNuevo: nuevo,
      child: const _PaginaFondo(),
    );
  }
}

class _PaginaFondo extends StatelessWidget {
  const _PaginaFondo();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('fondo'),
            TextButton(
              key: const Key('abrir_simple'),
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  title: const Text('Confirmar'),
                  content: const TextField(key: Key('campo_texto')),
                  actions: [
                    TextButton(
                      key: const Key('cancelar_simple'),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      key: const Key('aceptar_simple'),
                      onPressed: () => Navigator.of(ctx).pop('ok'),
                      child: const Text('Aceptar'),
                    ),
                  ],
                ),
              ),
              child: const Text('abrir simple'),
            ),
            TextButton(
              key: const Key('abrir_tres'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Tres opciones'),
                  actions: [
                    TextButton(
                      key: const Key('uno'),
                      onPressed: () => Navigator.of(ctx).pop('uno'),
                      child: const Text('Uno'),
                    ),
                    TextButton(
                      key: const Key('dos'),
                      onPressed: () => Navigator.of(ctx).pop('dos'),
                      child: const Text('Dos'),
                    ),
                    TextButton(
                      key: const Key('tres'),
                      onPressed: () => Navigator.of(ctx).pop('tres'),
                      child: const Text('Tres'),
                    ),
                  ],
                ),
              ),
              child: const Text('abrir tres'),
            ),
            TextButton(
              key: const Key('abrir_wrapper'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => KeyboardDialogWrapper(
                  onEnter: () {
                    wrapperEnter++;
                    Navigator.of(ctx).pop('enter');
                  },
                  onEscape: () {
                    wrapperEscape++;
                    Navigator.of(ctx).pop();
                  },
                  child: AlertDialog(
                    title: const Text('Wrapper'),
                    actions: [
                      FilledButton(
                        key: const Key('aceptar_wrapper'),
                        onPressed: () => Navigator.of(ctx).pop('ok'),
                        child: const Text('Aceptar'),
                      ),
                    ],
                  ),
                ),
              ),
              child: const Text('abrir wrapper'),
            ),
            DropdownButtonFormField<String>(
              key: const Key('desplegable'),
              initialValue: 'a',
              items: const [
                DropdownMenuItem(value: 'a', child: Text('Opcion A')),
                DropdownMenuItem(value: 'b', child: Text('Opcion B')),
              ],
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
  }
}

/// Contadores del diálogo con [KeyboardDialogWrapper].
int wrapperEnter = 0;
int wrapperEscape = 0;

void main() {
  late _Control control;

  Future<void> montar(WidgetTester tester) async {
    control = _Control();
    wrapperEnter = 0;
    wrapperEscape = 0;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_Arnes(control: control));
    await tester.pumpAndSettle();
  }

  Future<void> abrir(WidgetTester tester, String clave) async {
    await tester.tap(find.byKey(Key(clave)));
    await tester.pumpAndSettle();
    expect(DialogKeyboard.hayModalAbierto(), isTrue,
        reason: 'la ruta con el foco debe ser un PopupRoute');
  }

  group('Bloqueo de atajos con modal abierto', () {
    testWidgets('sin modal el atajo del CRUD sí se dispara', (tester) async {
      await montar(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(control.nuevo, 1);
      expect(control.portonConsumio, isFalse);
      expect(find.text('Dialogo del CRUD'), findsOneWidget);
    });

    testWidgets('con diálogo abierto el atajo NO apila otro diálogo',
        (tester) async {
      await montar(tester);
      await abrir(tester, 'abrir_simple');
      expect(control.nuevo, 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(control.nuevo, 0,
          reason: 'Ctrl+= no debe abrir un CRUD encima del diálogo');
      expect(find.text('Dialogo del CRUD'), findsNothing);
      expect(find.text('Confirmar'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'jamás debe haber dos diálogos apilados');
    });

    testWidgets('la tecla de función se consume en el portón', (tester) async {
      await montar(tester);
      await abrir(tester, 'abrir_simple');

      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();

      expect(control.portonConsumio, isTrue,
          reason:
              'el portón corta ANTES de la navegación del shell (F5 = Reportes)');
      expect(control.nuevo, 0);
      expect(find.text('Confirmar'), findsOneWidget,
          reason: 'el diálogo sigue donde estaba');
    });

    testWidgets('Ctrl+letra de navegación también queda bloqueada',
        (tester) async {
      await montar(tester);
      await abrir(tester, 'abrir_simple');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(control.portonConsumio, isTrue);
      expect(find.text('Confirmar'), findsOneWidget,
          reason: 'Ctrl+H no debe sacar de la pantalla con el modal abierto');
    });

    testWidgets('al cerrar el modal el atajo vuelve a operar', (tester) async {
      await montar(tester);
      await abrir(tester, 'abrir_simple');
      await tester.tap(find.byKey(const Key('cancelar_simple')));
      await tester.pumpAndSettle();
      expect(DialogKeyboard.hayModalAbierto(), isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(control.nuevo, 1, reason: 'sin modal el atajo vuelve a funcionar');
      expect(find.text('Dialogo del CRUD'), findsOneWidget);
    });

    testWidgets('la escritura de texto pasa por alto el portón',
        (tester) async {
      await montar(tester);
      await abrir(tester, 'abrir_simple');
      await tester.enterText(find.byKey(const Key('campo_texto')), 'abc');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(control.portonConsumio, isFalse,
          reason: 'las letras no son atajos: se dejan al diálogo');
      expect(control.nuevo, 0);
      expect(find.text('abc'), findsOneWidget);
      expect(find.text('Confirmar'), findsOneWidget);
    });
  });

  group('ENTER', () {
    testWidgets('activa el botón primario (Filled) del diálogo',
        (tester) async {
      await montar(tester);
      await abrir(tester, 'abrir_simple');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(control.portonConsumio, isTrue);
      expect(find.text('Confirmar'), findsNothing,
          reason: 'ENTER debió aceptar y cerrar el diálogo');
    });

    testWidgets('no hace nada con más de dos botones de texto (a ciegas)',
        (tester) async {
      await montar(tester);
      await abrir(tester, 'abrir_tres');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(control.portonConsumio, isFalse);
      expect(find.text('Tres opciones'), findsOneWidget,
          reason: 'con 3 botones no se decide: ENTER no debe pulsar a ciegas');
    });

    testWidgets('cede cuando el diálogo gestiona ENTER con el wrapper',
        (tester) async {
      await montar(tester);
      await abrir(tester, 'abrir_wrapper');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(wrapperEnter, 1,
          reason: 'la acción debe dispararse UNA sola vez (el wrapper)');
      expect(control.portonConsumio, isFalse,
          reason: 'el portón cede: ya la gestiona el wrapper');
      expect(find.text('Wrapper'), findsNothing);
    });

    testWidgets('el foco en un campo de texto no dispara la acción',
        (tester) async {
      await montar(tester);
      await abrir(tester, 'abrir_simple');

      await tester.enterText(find.byKey(const Key('campo_texto')), 'abc');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(control.portonConsumio, isFalse,
          reason: 'ENTER es del campo de texto, no del diálogo');
      expect(find.text('Confirmar'), findsOneWidget,
          reason: 'ENTER en un TextField no debe aceptar el diálogo');
      expect(find.text('abc'), findsOneWidget);
    });
  });

  group('ESC', () {
    testWidgets('cierra aunque barrierDismissible sea false (resultado null)',
        (tester) async {
      await montar(tester);
      await abrir(tester, 'abrir_simple');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(control.portonConsumio, isTrue);
      expect(find.text('Confirmar'), findsNothing);
      expect(DialogKeyboard.hayModalAbierto(), isFalse);
    });

    testWidgets('cede cuando el diálogo gestiona ESC con el wrapper',
        (tester) async {
      await montar(tester);
      await abrir(tester, 'abrir_wrapper');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(wrapperEscape, 1, reason: 'una sola vez');
      expect(control.portonConsumio, isFalse,
          reason: 'el portón cede porque lo gestiona el wrapper');
      expect(find.text('Wrapper'), findsNothing);
    });

    testWidgets('no fuerza el cierre de un popup que no es diálogo',
        (tester) async {
      await montar(tester);
      // 'Opcion A' está en el propio botón; el menú añade una copia más.
      expect(find.text('Opcion A'), findsOneWidget);

      await tester.tap(find.byKey(const Key('desplegable')));
      await tester.pumpAndSettle();
      expect(find.text('Opcion A'), findsNWidgets(2),
          reason: 'el menú desplegado añade la copia del ítem');
      expect(DialogKeyboard.hayModalAbierto(), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(control.portonConsumio, isFalse,
          reason: 'el desplegable NO es DialogRoute: el portón cede');
      expect(find.text('Opcion A'), findsOneWidget,
          reason: 'lo cierra su propia ruta nativa, el portón no la mata');
      expect(control.nuevo, 0);
    });
  });

  group('Detección de modal', () {
    testWidgets('sin modal la ruta con foco no es PopupRoute', (tester) async {
      await montar(tester);
      expect(DialogKeyboard.hayModalAbierto(), isFalse);
      expect(control.portonConsumio, isNull);
    });

    testWidgets('detecta el diálogo montado en el Navigator raíz',
        (tester) async {
      await montar(tester);
      await abrir(tester, 'abrir_simple');
      expect(DialogKeyboard.hayModalAbierto(), isTrue);

      await tester.tap(find.byKey(const Key('cancelar_simple')));
      await tester.pumpAndSettle();
      expect(DialogKeyboard.hayModalAbierto(), isFalse);
    });
  });
}
