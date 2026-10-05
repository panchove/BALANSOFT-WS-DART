// HARNESS DE T10B — spec 001, `tasks.md §11`.
//
// Recorre las pantallas reales de la estación para los casos 1, 2 y 4 de T10b y
// devuelve un dato medido, no una impresión:
//
//   * el **factor de texto realmente efectivo** en cada pantalla, leído del
//     `MediaQuery` que la app tiene montado;
//   * el **tema efectivo** (claro/oscuro) que resolvió el `MaterialApp`;
//   * los eventos `RenderFlex overflowed` capturados por pantalla;
//   * las etiquetas del ajuste de tipografía que se ven en cada idioma.
//
// Por qué un harness aparte y no reutilizar `t1_overflow_spike_test.dart`: aquel
// es el spike descartable de T1 (`tasks.md §1`, "no se commitea") y además fija
// el factor en una constante que se cierra sobre ella. Aquí el factor, el tema
// y el idioma son **parámetros**, y el factor se mide en vez de repetir lo que
// se inyectó.
//
// ⚠️ Lo que T1 imprimía como "textScaler efectivo" era el valor **inyectado**
// (`platformDispatcher.textScaleFactor`), que no es lo mismo que el efectivo:
// el efectivo es el producto del factor del sistema con el del operador,
// acotado por el clamp de REQ-FN-002b. Con el factor del operador persistido en
// 1.35, un factor externo de 1.40 se ve en pantalla a **1.60**. Por eso este
// harness lee el factor del árbol montado en vez de repetir la inyección.

import 'package:balansoft_ws/core/config/app_config.dart';
import 'package:balansoft_ws/core/controllers/typography_controller.dart';
import 'package:balansoft_ws/core/i18n/locale_controller.dart';
import 'package:balansoft_ws/core/i18n/translations.dart';
import 'package:balansoft_ws/core/theme/theme_controller.dart';
import 'package:balansoft_ws/domain/usecases/auth_usecases.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/main.dart' as app;
import 'package:balansoft_ws/presentation/screens/settings/typography_settings_screen.dart';
import 'package:balansoft_ws/presentation/widgets/tipografia_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

/// Las 4 pantallas críticas de REQ-FN-008. Sus claves son las que usan
/// `home_shell.dart` y `weighing_list_screen.dart`.
const List<String> pantallasCriticas = [
  'panel_principal',
  'ajustes',
  'formulario_pesaje',
  'detalle_boleto',
];

/// Un caso de T10b.
class CasoT10b {
  const CasoT10b({
    required this.numero,
    required this.titulo,
    required this.factor,
    required this.tema,
    this.familia = 'SISTEMA',
    this.idiomas = const <AppLanguage>[],
    this.etiquetasPorIdioma = const <AppLanguage, List<String>>{},
  });

  /// Número del caso de la tabla de `tasks.md §11`.
  final int numero;
  final String titulo;

  /// Factor del **selector** del operador, el rango de REQ-FN-002.
  final double factor;

  /// Tema elegido, por la misma vía que usa el operador (Ajustes → Apariencia).
  final TemaApp tema;

  /// Familia de UI con la que arranca el caso (REQ-FN-006). Es un valor de
  /// `TypographyController.familiasUi`, no un `fontFamily`: el caso 5 arranca en
  /// `SERIF` para comprobar que una familia que el sistema puede no tener
  ///installed cae a la del sistema sin error ni diálogo.
  final String familia;

  /// Idiomas en los que, además, hay que comprobar las etiquetas del ajuste.
  /// El primero es el inicial.
  final List<AppLanguage> idiomas;

  /// Etiquetas del ajuste de tipografía que tienen que verse en cada idioma
  /// (REQ-FN-019).
  final Map<AppLanguage, List<String>> etiquetasPorIdioma;

  String nombreIdioma(AppLanguage l) => l.name;
}

/// Lo que un caso midió.
class InformeT10b {
  InformeT10b(this.caso);

  final CasoT10b caso;

  /// Una línea por evento `RenderFlex overflowed`: `pantalla :: mensaje`.
  final List<String> overflowos = <String>[];

  /// Pantalla → alcanzada de verdad. "No vi overflow" no es "no lo vi".
  final Map<String, bool> pantallas = <String, bool>{};

  /// Pantalla → factor de texto efectivo medido en ella.
  final Map<String, double> factores = <String, double>{};

  /// Pantalla → tema efectivo que resolvió el `MaterialApp`.
  final Map<String, Brightness> temas = <String, Brightness>{};

  /// Idioma → etiquetas del ajuste que se leyeron en pantalla.
  final Map<String, List<String>> etiquetas = <String, List<String>>{};

  /// Hitos del recorrido que no se pudieron cumplir (pantalla no alcanzada,
  /// etiqueta que no apareció…). Se listan aparte del veredicto.
  final List<String> fallos = <String>[];

  String pantallaActual = 'arranque';


  /// Las 4 pantallas de REQ-FN-008 se alcanzaron y ninguna tuvo desborde.
  bool get pantallasOk =>
      pantallasCriticas.every((p) => pantallas[p] == true) &&
      overflowos.isEmpty;

  List<String> get pantallasNoAlcanzadas =>
      [for (final p in pantallasCriticas) if (pantallas[p] != true) p];

  void volcar() {
    debugPrint('=== T10B REPORTE ===');
    debugPrint('caso: ${caso.numero} — ${caso.titulo}');
    debugPrint('factor_del_selector: ${caso.factor}');
    debugPrint('factor_externo_del_so: '
        '${TestWidgetsFlutterBinding.instance.platformDispatcher.textScaleFactor}');
    debugPrint('tema_pedido: ${caso.tema.name}');
    debugPrint('familia_pedida: ${caso.familia}');
    for (final p in pantallas.keys) {
      debugPrint('pantalla $p: alcanzada=${pantallas[p]} '
          'factor_efectivo=${factores[p]} tema=${temas[p]?.name}');
    }
    debugPrint('pantallas_alcanzadas: '
        '${[for (final p in pantallas.keys) if (pantallas[p] == true) p].join(", ")}');
    debugPrint('pantallas_no_alcanzadas: ${pantallasNoAlcanzadas.join(", ")}');
    for (final e in etiquetas.entries) {
      debugPrint('etiquetas[${e.key}]: ${e.value.join(" | ")}');
    }
    debugPrint('overflow_count: ${overflowos.length}');
    for (final o in overflowos) {
      debugPrint('OVERFLOW :: $o');
    }
    for (final f in fallos) {
      debugPrint('FALLO :: $f');
    }
    debugPrint('=== FIN T10B ===');
  }
}

/// Factor de texto **efectivo** en la pantalla montada.
///
/// Se lee del `MediaQuery` que hay en pantalla, que es el que usa cada `Text`
/// para decidir su tamaño final. No se lee el valor inyectado: son distintos
/// (ver la cabecera del fichero).
double factorEfectivo(WidgetTester tester) {
  final andamio = find.byType(TipografiaScope);
  expect(andamio, findsOneWidget,
      reason: 'sin TipografiaScope el ajuste de REQ-FN-002 no se aplicaría');
  final elemento = tester.element(find.byType(Scaffold).first);
  return MediaQuery.textScalerOf(elemento).scale(16) / 16;
}

/// Tema efectivo (el que resolvió el `MaterialApp`, no el pedido).
Brightness temaEfectivo(WidgetTester tester) {
  return Theme.of(tester.element(find.byType(Scaffold).first)).brightness;
}

/// Deja las preferencias en memoria con el factor y el tema del caso.
///
/// **Por qué en memoria y no escribiendo en disco:** el factor del operador y el
/// tema son preferencias *de este equipo*
/// (`~/.local/share/com.balansoft.balansoft_ws/shared_preferences.json`). Un E2E
/// que las escribiera alteraría el estado de una estación instalada en la misma
/// máquina, que es justo lo que `pesaje_flow_test.dart` evita en modo seed.
/// `setMockInitialValues` cambia el almacén por uno en memoria conservando el
/// resto de claves, así que ni se pisa nada ni se depende de lo que hubiera.
void _preferenciasEnMemoria(
    {required double factor, required TemaApp tema, required String familia}) {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'app.textScaleFactor': factor,
    'app.familiaUi': familia,
    'balansoft.tema': tema.index,
    'balansoft.idioma': 'es',
  });
}

/// Prepara el proceso: almacén de sqflite, contenedor de dependencias y
/// controladores globales. **Una sola vez**, como en `pesaje_flow_test.dart`:
/// `di.init()` registra singletons en GetIt y llamarlo dos veces lanza
/// «ApiClient is already registered».
Future<void> iniciarProceso() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  await AppConfig.init();
  // Modo seed, igual que `pesaje_flow_test.dart`: campos estáticos directos,
  // sin escribir en las preferencias reales.
  AppConfig.setupPreferenciasCompletado = true;
  AppConfig.modoEstacion = 'SERVIDOR';
  AppConfig.licenciaVerificada = true;
  AppConfig.esTitularLicencia = true;
  AppConfig.empresaSetupCapturado = true;
  AppConfig.onboardingCompletado = true;
  AppConfig.offline = false;
  AppConfig.wserverAutostart = false;

  await app.themeController.load();
  await di.init();
  app.localeController = di.sl<LocaleController>();
  await app.localeController.load();
  AppTranslations.setController(app.localeController);
}

/// Reconstruye **solo** el `TypographyController` contra el `SharedPreferences`
/// del caso.
///
/// ⚠️ Es el único punto donde el harness se sale de la app. El motivo es
/// concreto y no es una comodidad: `AppConfig.init()` sustituye el
/// `SharedPreferences` del proceso en cada caso (las preferencias del caso se
/// siembran en memoria), pero `TypographyController` es un singleton *lazy* que
/// **captura `AppConfig.prefs` en el momento de construirse**. Con el
/// contenedor intacto, el caso 2 leería el almacén del caso 1 y mediría el
/// factor equivocado — o sea, un `overflow_count: 0` del caso 2 sería el del
/// caso 1. Ya pasó: el primer intento de este harness reportaba 1.40 en el caso
/// de factor 0.85.
///
/// El resto de controladores no lo necesitan: `LocaleController` y
/// `ThemeController` vuelven a pedir `SharedPreferences.getInstance()` en cada
/// `load()`.
Future<void> _reconstruirTipografia() async {
  await di.sl.unregister<TypographyController>();
  di.sl.registerLazySingleton<TypographyController>(
    () => TypographyController(prefs: AppConfig.prefs),
  );
}

/// Aplica el caso y monta la estación, con sesión limpia.
Future<void> montarEstacion(
  WidgetTester tester,
  CasoT10b caso, {
  String baseUrl = 'http://localhost:8000',
  String email = 'admin@balansoft.demo',
  String pass = 'demo1234',
}) async {
  // El orden importa: preferencias del caso → `AppConfig.init()` (que fija el
  // `SharedPreferences` del proceso) → contenedor de dependencias (que lo
  // captura). Al revés, el caso mediría el factor del caso anterior.
  _preferenciasEnMemoria(
      factor: caso.factor, tema: caso.tema, familia: caso.familia);

  // El factor del SO se fija en 1.0 para que el único factor en juego sea el del
  // selector: si no, el factor efectivo sería el producto de los dos y el caso
  // no mediría lo que dice medir.
  tester.platformDispatcher.textScaleFactorTestValue = 1.0;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await AppConfig.init();
  AppConfig.setupPreferenciasCompletado = true;
  AppConfig.modoEstacion = 'SERVIDOR';
  AppConfig.licenciaVerificada = true;
  AppConfig.esTitularLicencia = true;
  AppConfig.empresaSetupCapturado = true;
  AppConfig.onboardingCompletado = true;
  AppConfig.apiBaseUrl = baseUrl;
  AppConfig.offline = false;
  AppConfig.wserverAutostart = false;
  AppConfig.serverApiUrl = null;

  await _reconstruirTipografia();

  // Los controladores leen del almacén en memoria: el factor y el tema del caso
  // entran por la misma vía que usaría el operador, no por una constante.
  await app.themeController.load();
  await app.themeController.setTema(caso.tema);
  await app.localeController.load();
  await app.localeController.setLanguage(
    caso.idiomas.isEmpty ? AppLanguage.es : caso.idiomas.first,
  );

  // El ajuste de tipografía se lee aquí y no solo en el `initState` de la app:
  // así el valor del caso está en el controlador **antes** de que se monte nada,
  // y el primer frame ya se ve con él. Si no se leyera, arrancaría en 1.00 y el
  // caso no mediría el factor que dice medir.
  await di.sl<TypographyController>().load();

  await di.sl<LogoutUseCase>().execute();
  AppConfig.serverApiUrl = null;

  await windowManager.setSize(const Size(1400, 860));
  tester.view.physicalSize = const Size(1400, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const app.BalansoftApp());
  await asentar(tester, duracion: const Duration(seconds: 40));

  // Sesión limpia: sin esto el arranque puede restaurar el token de una corrida
  // anterior y saltar el login.
  expect(find.byKey(const Key('email_field')), findsOneWidget,
      reason: 'la estación debe abrir en /login con el factor '
          '${caso.factor} y el tema ${caso.tema.name}');
  await tester.enterText(find.byKey(const Key('email_field')), email);
  await tester.enterText(find.byKey(const Key('password_field')), pass);
  await tocar(tester, find.byKey(const Key('login_button')));
}

// ═══════════════════════════════════════════════════════════════════════════
// Utilidades de recorrido (mismas que el spike de T1: `pumpAndSettle` con la
// red real se queda corto, así que se acota por paso)
// ═══════════════════════════════════════════════════════════════════════════

const Duration _paso = Duration(milliseconds: 100);
const Duration _maxPaso = Duration(minutes: 2);

/// Deja asentar la pantalla: pump hasta que no haya frames programados y, si
/// queda un spinner, espera a que termine la petición en vuelo.
Future<void> asentar(WidgetTester tester,
    {Duration duracion = const Duration(seconds: 25)}) async {
  final limite = DateTime.now().add(duracion);
  while (DateTime.now().isBefore(limite)) {
    await tester.pump(const Duration(milliseconds: 120));
    if (!tester.binding.hasScheduledFrame) return;
  }
  await tester.pumpAndSettle(_paso, EnginePhase.sendSemanticsUpdate, _maxPaso);
  for (var i = 0;
      i < 80 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      i++) {
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle(_paso, EnginePhase.sendSemanticsUpdate, _maxPaso);
  }
}

/// Toca un widget llevándolo antes al centro de la vista: las listas tienen
/// scroll y el destino puede quedar fuera del viewport.
Future<void> tocar(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    debugPrint('[T10B] no se encontró ${finder.toString()}');
    return;
  }
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 150));
  await tester.tap(finder.first);
  await asentar(tester);
}

/// Espera a que aparezca algo. `false` = no apareció (se registra aparte: una
/// pantalla no alcanzada no se puede certificar).
Future<bool> esperar(WidgetTester tester, Finder finder,
    {String? porque, Duration duracion = const Duration(seconds: 45)}) async {
  final limite = DateTime.now().add(duracion);
  while (DateTime.now().isBefore(limite)) {
    await tester.pump(const Duration(milliseconds: 120));
    if (finder.evaluate().isNotEmpty) return true;
  }
  debugPrint('[T10B] no apareció ${porque ?? finder.toString()}');
  return false;
}

/// Vuelca lo visible: en un fallo de recorrido la única pista es la UI.
void volcar(WidgetTester tester, String paso) {
  final textos = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .take(30)
      .toList();
  debugPrint('[T10B $paso] $textos');
}

/// Registra una pantalla con lo que se midió en ella.
void registrar(WidgetTester tester, InformeT10b inf, String pantalla,
    {required bool alcanzada, String? porque}) {
  inf.pantallaActual = pantalla;
  inf.pantallas[pantalla] = alcanzada;
  if (!alcanzada) {
    inf.fallos.add('no se alcanzó $pantalla${porque == null ? '' : ' ($porque)'}');
    return;
  }
  inf.factores[pantalla] = factorEfectivo(tester);
  inf.temas[pantalla] = temaEfectivo(tester);
}

// ═══════════════════════════════════════════════════════════════════════════
// Recorridos
// ═══════════════════════════════════════════════════════════════════════════

/// Abre un módulo del menú lateral, desplegando su grupo si hace falta.
Future<bool> irAModulo(WidgetTester tester, String modulo) async {
  if (find.byKey(Key('menu_$modulo')).evaluate().isEmpty) {
    for (final grupo in ['REPORTES', 'MANTENIMIENTO', 'PRINCIPAL']) {
      if (find.byKey(Key('menu_grupo_$grupo')).evaluate().isNotEmpty) {
        await tocar(tester, find.byKey(Key('menu_grupo_$grupo')));
        if (find.byKey(Key('menu_$modulo')).evaluate().isNotEmpty) break;
      }
    }
  }
  if (!await esperar(tester, find.byKey(Key('menu_$modulo')),
      porque: 'la entrada de menú $modulo')) {
    return false;
  }
  await tocar(tester, find.byKey(Key('menu_$modulo')));
  return true;
}

/// Panel principal.
Future<void> irAPanel(WidgetTester tester, InformeT10b inf) async {
  final ok = await irAModulo(tester, 'inicio');
  registrar(tester, inf, 'panel_principal',
      alcanzada: ok, porque: 'el menú lateral del dashboard');
}

/// Pantalla de Ajustes.
Future<bool> irAAjustes(WidgetTester tester, InformeT10b inf,
    {bool registrarPantalla = true}) async {
  final ok = await irAModulo(tester, 'configuracion');
  if (registrarPantalla) {
    registrar(tester, inf, 'ajustes',
        alcanzada: ok, porque: 'Ajustes en el menú lateral');
  }
  return ok;
}

/// Vuelve atrás con el botón de la `AppBar`.
Future<void> volverAtras(WidgetTester tester) async {
  if (find.byType(BackButton).evaluate().isNotEmpty) {
    await tocar(tester, find.byType(BackButton));
  }
}

/// Abre el formulario de pesaje (sin guardar nada) y lo mide.
Future<bool> abrirFormulario(WidgetTester tester, InformeT10b inf) async {
  if (!await irAModulo(tester, 'entradas')) return false;
  if (!await esperar(tester, find.byKey(const Key('nuevo_pesaje_btn')),
      porque: 'el botón de nuevo pesaje')) {
    return false;
  }
  await tocar(tester, find.byKey(const Key('nuevo_pesaje_btn')));
  if (!await esperar(tester, find.byKey(const Key('placa_field')),
      porque: 'el formulario de pesaje')) {
    return false;
  }
  registrar(tester, inf, 'formulario_pesaje', alcanzada: true);
  return true;
}

/// Crea un boleto completo (entrada + salida) y abre su detalle.
///
/// El detalle exige un boleto **cerrado**: un boleto recién creado queda
/// PENDIENTE y aparece en ENTRADAS; al cerrarlo pasa a SALIDAS
/// (`weighing_list_screen.dart` se abre con `estadoInicial: 'CERRADO'` desde
/// `home_shell.dart`). Por eso se buscan las filas en los dos listados: mirar
/// solo uno fue el defecto que dejó `detalle_boleto` sin medir en T1.
Future<String?> abrirDetalleDeBoletoNuevo(
    WidgetTester tester,
    InformeT10b inf) async {
  if (!await abrirFormulario(tester, inf)) return null;
  final placa = 'T10B-${DateTime.now().millisecondsSinceEpoch % 100000}';

  await tester.enterText(find.byKey(const Key('placa_field')), placa);
  await asentar(tester);
  await tester.enterText(find.byKey(const Key('peso_entrada_field')), '15000');
  await asentar(tester);
  // Sin báscula en la empresa semilla: «Capturar peso» fija el tecleo manual.
  await tocar(tester, find.byKey(const Key('capturar_peso_button')));
  await tocar(tester, find.byKey(const Key('guardar_toolbar_button')));
  if (await esperar(tester, find.byKey(const Key('dialogo_confirmar_guardado_btn')),
      porque: 'la confirmación de guardado')) {
    await tocar(tester, find.byKey(const Key('dialogo_confirmar_guardado_btn')));
    if (await esperar(tester, find.byKey(const Key('dialogo_nuevo_peso_btn')),
        porque: 'la pregunta de impresión')) {
      await tocar(tester, find.byKey(const Key('dialogo_nuevo_peso_btn')));
    }
  }
  await asentar(tester);

  // Cierre (salida) del mismo boleto.
  await tocar(tester, find.byKey(const Key('salida_toolbar_button')));
  final pendiente = find.byKey(Key('boleto_pendiente_$placa'));
  if (await esperar(tester, pendiente,
      porque: 'el boleto $placa pendiente de salida',
      duracion: const Duration(seconds: 25))) {
    await tocar(tester,
        find.descendant(of: pendiente, matching: find.byType(FilledButton)));
    if (find.byKey(const Key('peso_salida_field')).evaluate().isNotEmpty) {
      await tester.enterText(find.byKey(const Key('peso_salida_field')), '13800');
      await asentar(tester);
      await tocar(tester, find.byKey(const Key('guardar_toolbar_button')));
      if (await esperar(tester, find.byKey(const Key('dialogo_confirmar_guardado_btn')),
          duracion: const Duration(seconds: 20))) {
        await tocar(tester, find.byKey(const Key('dialogo_confirmar_guardado_btn')));
        if (await esperar(tester, find.byKey(const Key('dialogo_nuevo_peso_btn')),
            duracion: const Duration(seconds: 20))) {
          await tocar(tester, find.byKey(const Key('dialogo_nuevo_peso_btn')));
        }
      }
    }
  }
  await asentar(tester);
  await tocar(tester, find.byKey(const Key('salir_toolbar_button')));
  await asentar(tester);

  if (!await _abrirFilaDelBoleto(tester, placa)) {
    registrar(tester, inf, 'detalle_boleto',
        alcanzada: false, porque: 'no apareció la fila del boleto $placa');
    return placa;
  }
  registrar(tester, inf, 'detalle_boleto', alcanzada: true);
  return placa;
}

/// Busca el boleto cerrado en ENTRADAS, en SALIDAS y, si hace falta,
/// reingresando al módulo: la lista puede quedar desactualizada al volver del
/// formulario.
Future<bool> _abrirFilaDelBoleto(WidgetTester tester, String placa) async {
  final fila = find.byKey(Key('boleto_fila_$placa'));
  if (await esperar(tester, fila,
      porque: 'la fila de $placa en ENTRADAS', duracion: const Duration(seconds: 10))) {
    await tocar(tester, fila);
    return true;
  }
  await tocar(tester, find.byKey(const Key('menu_salidas')));
  if (await esperar(tester, fila,
      porque: 'la fila de $placa en SALIDAS', duracion: const Duration(seconds: 20))) {
    await tocar(tester, fila);
    return true;
  }
  volcar(tester, 'historial sin la fila de $placa');
  if (find.byKey(const Key('menu_entradas')).evaluate().isEmpty) {
    await tocar(tester, find.byKey(const Key('menu_grupo_REPORTES')));
  }
  if (find.byKey(const Key('menu_entradas')).evaluate().isNotEmpty) {
    await tocar(tester, find.byKey(const Key('menu_entradas')));
    if (await esperar(tester, fila,
        porque: 'la fila de $placa tras reingresar a Entradas',
        duracion: const Duration(seconds: 25))) {
      await tocar(tester, fila);
      return true;
    }
  }
  return false;
}

/// Cambia el idioma por la vía real del operador (Ajustes → Apariencia e
/// Idioma) y comprueba las etiquetas del ajuste de tipografía en el nuevo.
///
/// La etiqueta del selector es traducida, así que se busca con el idioma
/// **vigente**: al cambiar a inglés, el botón de portugués se llama
/// «Portuguese (PT)».
Future<void> comprobarIdioma(WidgetTester tester, InformeT10b inf,
    {required AppLanguage destino}) async {
  if (!await irAAjustes(tester, inf)) return;
  final vigente = app.localeController.activeLanguageCode;
  final boton = AppTranslations.tr('language_${destino.name}', langCode: vigente);
  if (find.text(boton).evaluate().isEmpty) {
    volcar(tester, 'Ajustes sin el selector de idioma ($boton)');
    inf.fallos.add('no se encontró el selector de idioma $boton');
    return;
  }
  await tocar(tester, find.text(boton));
  await asentar(tester, duracion: const Duration(seconds: 10));
  if (app.localeController.activeLanguageCode != destino.name) {
    inf.fallos.add('el idioma no cambió a ${destino.name}');
    return;
  }
  registrar(tester, inf, 'ajustes_${destino.name}', alcanzada: true);
  await comprobarEtiquetasTipografia(tester, inf, destino);
}

/// Abre el ajuste de tipografía desde Ajustes y comprueba sus etiquetas en el
/// idioma vigente.
Future<void> comprobarEtiquetasTipografia(WidgetTester tester, InformeT10b inf,
    AppLanguage idioma) async {
  final titulo = AppTranslations.tr('tipografia_titulo',
      langCode: app.localeController.activeLanguageCode);
  final entrada = find.widgetWithText(ListTile, titulo);
  if (entrada.evaluate().isEmpty) {
    volcar(tester, 'Ajustes sin la entrada de tipografía ($titulo)');
    inf.fallos.add('no se encontró la entrada «$titulo» en Ajustes');
    return;
  }
  await tocar(tester, entrada);
  if (!await esperar(tester, find.byType(TypographySettingsScreen),
      porque: 'la pantalla de tipografía')) {
    inf.fallos.add('no se abrió la pantalla de tipografía');
    return;
  }
  await asentar(tester, duracion: const Duration(seconds: 8));

  // Todas las etiquetas que se piden para este idioma, leyéndolas de verdad de
  // la pantalla (con scroll, porque la lista no cabe entera).
  final vistas = <String>[];
  for (final etiqueta in inf.caso.etiquetasPorIdioma[idioma] ?? const <String>[]) {
    if (await _aparecerTexto(tester, etiqueta)) {
      vistas.add(etiqueta);
    } else {
      inf.fallos.add('no apareció la etiqueta «$etiqueta» en ${idioma.name}');
    }
  }
  inf.etiquetas[idioma.name] = vistas;
  registrar(tester, inf, 'ajustes_tipografia_${idioma.name}', alcanzada: true);

  await volverAtras(tester);
}

/// Busca un texto en la pantalla desplazando la lista, como haría el operador.
Future<bool> _aparecerTexto(WidgetTester tester, String texto) async {
  if (find.text(texto).evaluate().isNotEmpty) return true;
  // `dragUntilVisible` y no un bucle de `drag`: el bucle arrastraba el primer
  // `Scrollable` aunque ya estuviera al final, y a factor 1.40 las dos últimas
  // etiquetas («Fuente del ticket PDF» y «DejaVu») nunca se llegaban a
  // construir. Con `dragUntilVisible` además se sabe si la lista se acabó.
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) return false;

  // **Todos** los scrollables, no solo el primero: el árbol de la estación tiene
  // más de uno (el lateral del shell, la propia pantalla), y arrastrar el
  // equivocado no mueve nada. Con el primero, a factor 1.40 las dos últimas
  // etiquetas nunca llegaban a construirse y el caso fallaba por culpa del
  // arnés, no de la app.
  for (final scrollable in scrollables.evaluate()) {
    try {
      await tester.dragUntilVisible(
        find.text(texto),
        find.byElementPredicate((e) => e == scrollable),
        const Offset(0, -240),
        maxIteration: 60,
      );
      await asentar(tester, duracion: const Duration(seconds: 2));
      if (find.text(texto).evaluate().isNotEmpty) return true;
    } on Object catch (e) {
      debugPrint('[T10B] «$texto»: este scrollable no sirve '
          '(${e.runtimeType})');
    }
  }
  volcar(tester, 'sin la etiqueta «$texto»');
  return false;
}

/// Captura los `RenderFlex overflowed` del caso y delega el resto de errores en
/// el manejador original: tragarse cualquier otra excepción dejaría pasar un
/// fallo real.
void capturarOverflows(InformeT10b inf) {
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final texto = details.exceptionAsString();
    if (texto.contains('overflowed')) {
      // La cadena del nodo de diagnóstico es lo que identifica la fila que
      // desborda. Con solo el mensaje («60 pixels on the right») no se puede
      // localizar, y la regla es no tocar ningún layout sin saber cuál es.
      final nodo = details.context;
      final cadena = nodo == null
          ? 'contexto:null'
          : nodo.toStringDeep().trim().split('\n').take(8).join(' ');
      inf.overflowos.add('${inf.pantallaActual} :: $texto :: $cadena');
    } else {
      originalOnError?.call(details);
    }
  };
  addTearDown(() => FlutterError.onError = originalOnError);
}
