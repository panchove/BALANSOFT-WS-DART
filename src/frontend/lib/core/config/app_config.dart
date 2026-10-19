import 'package:shared_preferences/shared_preferences.dart';

import 'station_config.dart';

/// Estado global de configuración de la app (cliente Flutter).
///
/// Lo que decide el INSTALADOR (rol + URL de la API) vive en `config.json` y
/// se lee vía [StationConfig]; aquí queda proyectado en [rol] y [apiBaseUrl]
/// para el resto de la app. Nada de esto autoriza: tenant, licencia y
/// permisos los decide el backend (multi-tenancy, docs/MANEJO_DB.md §13).
class AppConfig {
  static const String appName = 'Balansoft-WS';
  static const String appVersion = '0.4.2-dev.56';
  static const int appBuild = 56;

  /// Título de la ventana nativa de escritorio.
  ///
  /// `MaterialApp.title` **no** la cambia en Linux/Windows: es el runner nativo
  /// el que fija el título al crear la ventana, así que lo re-aplica
  /// `window_manager` en `main()` (ver `OsNotifications` para el otro caso en
  /// que Windows muestra un nombre: el emisor de los avisos).
  static const String windowTitle =
      'BALANSOFT WS - ESTACIÓN DE PESAJE INDUSTRIAL';

  static const String defaultServerApiUrl = 'https://ws.balansoft.com.ve';
  static const String defaultApiBaseUrl = 'http://localhost:8000';

  /// URL de la API a la que apunta la estación (override o sistema del
  /// instalador, o migración del legado). Proyección en memoria.
  static String? apiBaseUrl;

  static String? serverApiUrl;
  static String? licenseApiUrl;
  static String? publicKey;
  static bool offline = false;

  /// El WServer arranca con el sistema (silencioso) en lugar de esperar a que
  /// la app lo lance. Activado por defecto: una estación recién instalada no
  /// puede depender de que alguien abra la app para que haya API. Quien
  /// desactive el conmutador de Ajustes baja este flag, y entonces el WServer
  /// solo vive mientras la app esté abierta.
  static bool wserverAutostart = true;

  /// Sincronización automática por timer (Ajustes → Sincronización).
  static bool syncAutoEnabled = true;

  // ── Configuración de estación (config.json del instalador) ───────────────
  /// Rol funcional decidido por el instalador (`SERVIDOR` o `OPERADOR`).
  /// `null` = sin config válida (la app no debe operar).
  static StationRole? rol;

  /// Error de provisión si `config.json` faltaba o era inválido: la app no
  /// debe arrancar con rol nulo (contrato BALANSOFT-INSTALLER).
  static StationConfigError? configError;

  /// El wizard post-login ya no tiene nada pendiente que aplicar
  /// (primer ADMIN captura los datos de empresa con InitialSetupScreen).
  static bool onboardingCompletado = false;

  /// El mini tutorial de bienvenida ya se mostró (se marca al finalizarlo o
  /// saltarlo). Se repite manualmente desde Ayuda y Soporte.
  static bool tutorialVisto = false;

  /// El aviso de bienvenida del SO ya se emitió (una sola vez por estación,
  /// al primer inicio de sesión de la app).
  static bool bienvenidaNotificada = false;

  static late SharedPreferences _prefs;

  /// true después de `init()`: en producción `_prefs` siempre está lista, pero
  /// en tests de widget (donde no se puede llamar `init()` por el FakeAsync)
  /// `setTutorialVisto` guarda solo en memoria.
  static bool _prefsLista = false;

  /// Hay config de instalador cargada (rol + URL válida): sin esto la app
  /// no opera (error duro en `main()`).
  static bool get instalacionValida =>
      rol != null &&
      apiBaseUrl != null &&
      apiBaseUrl!.trim().isNotEmpty;

  /// La URL de la API LOCAL ya está configurada.
  static bool get localApiConfigured =>
      apiBaseUrl != null && apiBaseUrl!.trim().isNotEmpty;

  /// Cliente delgado: no levanta WServer ni base de datos propia.
  static bool get esOperador => rol == StationRole.operador;

  /// Servidor local: la estación aloja la API y los datos de la empresa.
  static bool get esServidor => rol == StationRole.servidor;

  static Future<void> init({bool migrarLegado = false}) async {
    _prefs = await SharedPreferences.getInstance();
    _prefsLista = true;
    // El servidor central SIEMPRE está presente (nube: cuenta y licencia).
    serverApiUrl = defaultServerApiUrl;
    licenseApiUrl = _prefs.getString('license_api_url') ?? 'http://localhost:8080';
    publicKey = _prefs.getString('public_key');
    offline = _prefs.getBool('offline') ?? false;
    wserverAutostart = _prefs.getBool('wserver_autostart') ?? true;
    syncAutoEnabled = _prefs.getBool('sync_auto_enabled') ?? true;
    onboardingCompletado = _prefs.getBool('onboarding_completado') ?? false;
    tutorialVisto = _prefs.getBool('tutorial_visto') ?? false;
    bienvenidaNotificada = _prefs.getBool('bienvenida_notificada') ?? false;

    // Config de estación: archivo del instalador (override → sistema) o, en
    // el arranque real, migración única del legado. Sin archivo ni legado,
    // se deja `rol` nulo y se expone el error (no se debe operar).
    rol = null;
    configError = null;
    apiBaseUrl = null;
    try {
      final cfg = await StationConfigLoader.cargar(migrarLegado: migrarLegado);
      apiBaseUrl = cfg.apiBaseUrl;
      rol = cfg.rol;
    } on StationConfigError catch (e) {
      configError = e;
    }
  }

  static SharedPreferences get prefs => _prefs;

  /// URL de la API local: se edita en "Conexiones". Persiste en el override
  /// de usuario del `config.json` conservando el rol de la estación.
  static Future<void> setApiBaseUrl(String url) async {
    await StationConfigWriter.actualizarApiBaseUrl(url);
    apiBaseUrl = url;
  }

  /// URL del servidor central (cuenta y licencia). Siempre disponible.
  static Future<void> setServerApiUrl(String url) async {
    serverApiUrl = url;
    await _prefs.setString('server_api_url', url);
  }

  /// Marca el estado offline de la estación (sesión con login-local).
  static Future<void> setOffline(bool value) async {
    offline = value;
    await _prefs.setBool('offline', value);
  }

  /// ¿Arrancar el WServer automáticamente al encender el equipo?
  static Future<void> setWServerAutostart(bool value) async {
    wserverAutostart = value;
    await _prefs.setBool('wserver_autostart', value);
  }

  /// Activa o desactiva la sincronización automática por timer.
  static Future<void> setSyncAutoEnabled(bool value) async {
    syncAutoEnabled = value;
    await _prefs.setBool('sync_auto_enabled', value);
  }

  /// Marca el onboarding como cerrado: no se vuelve a mostrar el wizard
  /// post-login del primer ADMIN.
  static Future<void> setOnboardingCompletado([bool value = true]) async {
    onboardingCompletado = value;
    await _prefs.setBool('onboarding_completado', value);
  }

  /// Marca el mini tutorial de bienvenida como visto: no se vuelve a ofrecer
  /// automáticamente (sigue disponible en Ayuda y Soporte). En producción
  /// persiste en prefs (siempre inicializadas tras `init()`); sin prefs guarda
  /// solo en memoria (caso de tests de widget, donde no se llama `init()`).
  static Future<void> setTutorialVisto([bool value = true]) async {
    tutorialVisto = value;
    if (_prefsLista) {
      await _prefs.setBool('tutorial_visto', value);
    }
  }

  /// Marca el aviso de bienvenida del SO como emitido (una sola vez).
  /// En producción persiste en prefs; sin prefs guarda solo en memoria (tests
  /// de widget, donde no se llama `init()` — misma regla que
  /// [setTutorialVisto]).
  static Future<void> setBienvenidaNotificada([bool value = true]) async {
    bienvenidaNotificada = value;
    if (_prefsLista) {
      await _prefs.setBool('bienvenida_notificada', value);
    }
  }
}
