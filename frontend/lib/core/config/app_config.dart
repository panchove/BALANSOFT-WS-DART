import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String appName = 'Balansoft-WS';
  static const String appVersion = '1.0.0';

  static const String defaultServerApiUrl = 'https://ws.balansoft.com.ve';
  static const String defaultApiBaseUrl = 'http://localhost:8000';

  static String? apiBaseUrl;
  static String? serverApiUrl;
  static String? licenseApiUrl;
  static String? publicKey;
  static bool offline = false;
  static bool wserverAutostart = false;

  /// Sincronización automática por timer (Ajustes → Sincronización).
  static bool syncAutoEnabled = true;

  // ── Onboarding de primera instalación (docs/I18N_Y_ONBOARDING.md) ──────────
  /// El usuario ya eligió idioma y tema (paso 1 del modo instalación).
  static bool setupPreferenciasCompletado = false;

  /// Rol que la estación va a tomar en la instalación (docs/MANEJO_DB.md §13).
  ///
  /// - `SERVIDOR`: la máquina es la titular de la licencia; levanta su WServer
  ///   y su PostgreSQL, y guarda aquí los datos operativos.
  /// - `TRABAJADOR`: cliente delgado; solo apunta a la API del servidor de la
  ///   cuenta (IP/puerto) y no crea base de datos local.
  static String? modoEstacion;

  /// El proveedor validó la cuenta en el servidor central y la licencia está
  /// activa en ESTA máquina (paso 3 del modo servidor).
  static bool licenciaVerificada = false;

  /// Este equipo es el titular de la licencia (`SERVIDOR_LOCAL` en el central).
  static bool esTitularLicencia = false;

  /// Los datos de empresa se capturaron y quedaron guardados en la BD local
  /// (paso 4 del modo servidor).
  static bool empresaSetupCapturado = false;

  /// El wizard post-login ya no tiene nada pendiente que aplicar.
  static bool onboardingCompletado = false;

  static late SharedPreferences _prefs;

  /// La URL de la API LOCAL (estación) aún no se ha configurado.
  static bool get localApiConfigured =>
      apiBaseUrl != null && apiBaseUrl!.trim().isNotEmpty;

  /// Cliente delgado: no levanta WServer ni base de datos propia.
  static bool get esTrabajador => modoEstacion == 'TRABAJADOR';

  /// Servidor local: la estación aloja la API y los datos de la empresa.
  static bool get esServidor => modoEstacion == 'SERVIDOR';

  /// La instalación se considera cerrada cuando se configuraron las
  /// preferencias, se eligió el modo y cada modo completó sus pasos:
  /// el trabajador tiene apuntada la API del servidor; el servidor validó la
  /// licencia y guardó los datos de empresa (REQ-NF-ONB-006).
  static bool get instalacionCompletada {
    if (!setupPreferenciasCompletado) return false;
    if (esTrabajador) return localApiConfigured;
    if (esServidor) return licenciaVerificada && empresaSetupCapturado;
    return false;
  }

  /// El borrador de empresa está guardado pero aún no llegó a la BD local.
  static bool get empresaConfigPendiente =>
      empresaSetupCapturado && !onboardingCompletado;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // El servidor central SIEMPRE está presente (default); la API local queda
    // sin valor hasta que se configure en la primera ejecución.
    apiBaseUrl = _prefs.getString('api_base_url');
    // El servidor central (nube: cuenta y licencia) está definido de fábrica
    // y NO es configurable por el usuario ni se lee de preferencias locales.
    serverApiUrl = defaultServerApiUrl;
    licenseApiUrl = _prefs.getString('license_api_url') ?? 'http://localhost:8080';
    publicKey = _prefs.getString('public_key');
    offline = _prefs.getBool('offline') ?? false;
    wserverAutostart = _prefs.getBool('wserver_autostart') ?? false;
    syncAutoEnabled = _prefs.getBool('sync_auto_enabled') ?? true;
    setupPreferenciasCompletado =
        _prefs.getBool('setup_preferencias_completado') ?? false;
    modoEstacion = _prefs.getString('modo_estacion');
    licenciaVerificada = _prefs.getBool('licencia_verificada') ?? false;
    esTitularLicencia = _prefs.getBool('es_titular_licencia') ?? false;
    empresaSetupCapturado =
        _prefs.getBool('empresa_setup_capturado') ?? false;
    onboardingCompletado = _prefs.getBool('onboarding_completado') ?? false;
  }

  static SharedPreferences get prefs => _prefs;

  /// URL de la API local (estación): se configura en "Conexiones" si no existe.
  static Future<void> setApiBaseUrl(String url) async {
    apiBaseUrl = url;
    await _prefs.setString('api_base_url', url);
  }

  /// Borra la URL local configurada: devuelve la app al modo instalación
  /// (verificación de entorno + pantalla de conexiones).
  static Future<void> quitarApiBaseUrl() async {
    apiBaseUrl = null;
    await _prefs.remove('api_base_url');
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

  /// Marca que el paso 1 de instalación (idioma y tema) ya se completó.
  static Future<void> setSetupPreferenciasCompletado() async {
    setupPreferenciasCompletado = true;
    await _prefs.setBool('setup_preferencias_completado', true);
  }

  /// Guarda el rol que toma la estación: `SERVIDOR` o `TRABAJADOR`.
  static Future<void> setModoEstacion(String modo) async {
    modoEstacion = modo;
    await _prefs.setString('modo_estacion', modo);
  }

  /// Marca (o desmarca) que la cuenta quedó validada en el servidor central y
  /// si esta máquina es la titular de la licencia.
  static Future<void> setLicenciaVerificada({
    required bool verificada,
    required bool titular,
  }) async {
    licenciaVerificada = verificada;
    esTitularLicencia = titular;
    await _prefs.setBool('licencia_verificada', verificada);
    await _prefs.setBool('es_titular_licencia', titular);
  }

  /// Marca que los datos de empresa ya quedaron guardados en la BD local
  /// (paso 4 del modo servidor).
  static Future<void> setEmpresaSetupCapturado() async {
    empresaSetupCapturado = true;
    await _prefs.setBool('empresa_setup_capturado', true);
  }

  /// Marca el onboarding como cerrado: no se vuelve a mostrar el wizard.
  static Future<void> setOnboardingCompletado([bool value = true]) async {
    onboardingCompletado = value;
    await _prefs.setBool('onboarding_completado', value);
  }
}
