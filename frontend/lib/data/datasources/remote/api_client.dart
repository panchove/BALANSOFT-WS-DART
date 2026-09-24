import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/api_constants.dart';

class ApiClient {
  final Dio _dio;
  String _baseUrl;
  String? _serverToken;
  Future<String?> Function()? _refreshTokenHandler;
  bool _refrescando = false;

  String get baseUrl => _baseUrl;

  ApiClient({String? baseUrl, Dio? dio})
      : _baseUrl = baseUrl ?? AppConfig.apiBaseUrl ?? 'http://localhost:8000',
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            )) {
    _setupInterceptor();
  }

  /// Cambia la URL base de la API local en caliente (Ajustes > Conexiones).
  /// Las repositorios comparten esta misma instancia, así el cambio aplica a
  /// todas las llamadas sin reiniciar la app.
  void setBaseUrl(String url) {
    _baseUrl = url.replaceAll(RegExp(r'/$'), '');
  }

  void onUnauthorized(Future<String?> Function() handler) {
    _refreshTokenHandler = handler;
  }

  void _setupInterceptor() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          // No reintentar refresh sobre el propio endpoint de refresh ni en
          // cascada: evita bucles infinitos cuando el refresh token es
          // inválido (p.ej. tras reinstalar/vaciar la BD del backend).
          final esEndpointRefresh =
              error.requestOptions.path.contains('refresh-token');
          if (error.response?.statusCode != 401 ||
              _refreshTokenHandler == null ||
              _refrescando ||
              esEndpointRefresh) {
            return handler.next(error);
          }
          _refrescando = true;
          try {
            final newToken = await _refreshTokenHandler!();
            if (newToken != null && newToken.isNotEmpty) {
              setToken(newToken);
              final opts = error.requestOptions;
              opts.headers['Authorization'] = 'Bearer $newToken';
              try {
                final response = await _dio.fetch(opts);
                return handler.resolve(response);
              } catch (_) {}
            }
          } finally {
            _refrescando = false;
          }
          return handler.next(error);
        },
      ),
    );
  }

  void setToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  void clearToken() {
    _dio.options.headers.remove('Authorization');
  }

  /// Token de la sesión contra el servidor central (credencial global).
  /// Cuando está presente se usa para las llamadas server-bound en lugar
  /// del token local de la estación.
  void setServerToken(String? token) {
    _serverToken = (token == null || token.isEmpty) ? null : token;
  }

  String _serverBase([String? serverUrl]) {
    final url = (serverUrl ?? AppConfig.serverApiUrl)
            ?.replaceAll(RegExp(r'/$'), '') ??
        '';
    return url;
  }

  /// Login contra el servidor central: obtiene la credencial global de la
  /// cuenta (necesaria para `/api/v1/sync/*`, `/api/v1/licencias`, etc.).
  Future<Response> serverLogin({
    required String email,
    required String password,
    required String hardwareId,
    String? serverUrl,
    String? deviceBrand,
    String? deviceModel,
    String? osVersion,
    String? macAddress,
    String? nombreEquipo,
    String? sistemaOperativo,
    String? versionApp,
  }) async {
    final url = _serverBase(serverUrl);
    if (url.isEmpty) {
      throw StateError('Servidor central no configurado');
    }
    return _dio.post(
      '$url/api/v1/auth/login',
      data: {
        'email': email,
        'password': password,
        'hardware_id': hardwareId,
        'device_brand': deviceBrand,
        'device_model': deviceModel,
        'os_version': osVersion,
        'mac_address': macAddress,
        'nombre_equipo': nombreEquipo,
        'sistema_operativo': sistemaOperativo,
        'version_app': versionApp,
      },
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
  }

  Future<bool> health() async {
    try {
      final response = await _dio.get('$_baseUrl${ApiConstants.health}');
      return response.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  Future<Response> login(Map<String, dynamic> body) async {
    final response = await _dio.post('$_baseUrl/api/v1/auth/login', data: body);
    return response;
  }

  /// Login OFFLINE: valida credenciales locales sin consultar el LM.
  /// Se usa como respaldo cuando el login estándar falla por red o el LM está caído.
  Future<Response> loginLocal(Map<String, dynamic> body) async {
    final response =
        await _dio.post('$_baseUrl${ApiConstants.loginLocal}', data: body);
    return response;
  }

  /// Login CENTRAL-first contra el backend LOCAL (`/api/v1/auth/login-central`).
  /// El backend valida la cuenta en el servidor central (DB del panel) y, si
  /// existe, hace espejo local (empresa + admin) para poder operar offline.
  Future<Response> loginCentral(Map<String, dynamic> body) async {
    final response =
        await _dio.post('$_baseUrl/api/v1/auth/login-central', data: body);
    return response;
  }

  /// Comprueba si el servidor central (cuenta/licencia) responde.
  Future<bool> serverHealth({String? serverUrl}) async {
    final url = (serverUrl ?? AppConfig.serverApiUrl)
            ?.replaceAll(RegExp(r'/$'), '') ??
        AppConfig.apiBaseUrl;
    try {
      final response = await _dio.get('$url${ApiConstants.health}',
          options: Options(receiveTimeout: const Duration(seconds: 5)));
      return response.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  /// Consulta el estado del entorno de la API local (verificación de
  /// instalación). Devuelve el mapa completo del endpoint /environment.
  Future<Map<String, dynamic>?> environment({String? baseUrl}) async {
    final base = (baseUrl ?? _baseUrl).replaceAll(RegExp(r'/$'), '');
    try {
      final response = await _dio.get(
        '$base/api/v1/environment',
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } on DioException {
      // Entorno no accesible (p. ej. WServer aún arrancando): se reporta abajo como null.
    }
    return null;
  }

  Future<Response> register(Map<String, dynamic> body) async {
    final response = await _dio.post('$_baseUrl/api/v1/auth/register', data: body);
    return response;
  }

  Future<Response> logout() async {
    final response = await _dio.post('$_baseUrl/api/v1/auth/logout');
    return response;
  }

  Future<Response> refreshToken(String refreshToken) async {
    final response = await _dio.post(
      '$_baseUrl${ApiConstants.refreshToken}',
      data: {'refresh_token': refreshToken},
    );
    return response;
  }

  Future<Response> forgotPassword(String email) async {
    final response = await _dio.post(
      '$_baseUrl${ApiConstants.forgotPassword}',
      data: {'email': email},
    );
    return response;
  }

  Future<Response> resetPassword(String token, String newPassword) async {
    final response = await _dio.post(
      '$_baseUrl${ApiConstants.resetPassword}',
      data: {'token': token, 'new_password': newPassword},
    );
    return response;
  }

  Future<Response> validateLicense(Map<String, dynamic> body) async {
    final response = await _dio.post(
      '$_baseUrl${ApiConstants.validateLicense}',
      data: body,
    );
    return response;
  }

  /// Snapshot de la licencia de la empresa autenticada (admin).
  Future<Map<String, dynamic>> getLicenseSnapshot() async {
    final response = await _dio.get('$_baseUrl${ApiConstants.licenseSnapshot}');
    return response.data as Map<String, dynamic>;
  }

  /// Identidad de la estación local (GET /api/v1/identity).
  /// Lanza 404 si la cuenta aún no se ha configurado tras un login.
  Future<Map<String, dynamic>?> getIdentity({bool refresh = false}) async {
    final response = await _dio.get(
      '$_baseUrl${ApiConstants.identity}',
      queryParameters: refresh ? {'refresh': 'true'} : null,
    );
    return (response.data as Map<String, dynamic>?)?.cast<String, dynamic>();
  }

  /// Persiste la identidad de la estación local (PUT /api/v1/identity, solo ADMIN).
  Future<void> saveIdentity(Map<String, dynamic> body) async {
    await _dio.put('$_baseUrl${ApiConstants.identity}', data: body);
  }

  /// Información unificada de la estación: cuenta espejo del servidor +
  /// licencia validada en vivo contra el LM (GET /api/v1/config/account).
  Future<Map<String, dynamic>> getAccountInfo() async {
    final response = await _dio.get('$_baseUrl${ApiConstants.configAccount}');
    return response.data as Map<String, dynamic>;
  }

  /// Perfil de la empresa local (datos de contacto + logo).
  Future<Map<String, dynamic>> getEmpresaPerfil() async {
    final response =
        await _dio.get('$_baseUrl${ApiConstants.empresaPerfil}');
    return response.data as Map<String, dynamic>;
  }

  /// Actualiza el perfil de la empresa local (solo ADMIN).
  Future<Map<String, dynamic>> updateEmpresaPerfil(
    Map<String, dynamic> body,
  ) async {
    final response =
        await _dio.put('$_baseUrl${ApiConstants.empresaPerfil}', data: body);
    return response.data as Map<String, dynamic>;
  }

  /// Usuarios de la estación (ADMIN/AUDITOR).
  Future<List<dynamic>> listUsuarios() async {
    final response = await _dio.get('$_baseUrl${ApiConstants.usuarios}');
    return (response.data as List<dynamic>?) ?? const [];
  }

  /// Crea un usuario local (ADMIN) y lo encola para sincronizar al servidor.
  Future<Map<String, dynamic>> createUsuario(Map<String, dynamic> body) async {
    final response = await _dio.post('$_baseUrl${ApiConstants.usuarios}', data: body);
    return response.data as Map<String, dynamic>;
  }

  /// Actualiza un usuario local (ADMIN) y lo encola para sincronizar.
  Future<Map<String, dynamic>> updateUsuario(
    String id,
    Map<String, dynamic> body,
  ) async {
    final response = await _dio.put('$_baseUrl${ApiConstants.usuario(id)}', data: body);
    return response.data as Map<String, dynamic>;
  }

  /// Lista de usuarios sincronizados pendientes de enviar al servidor central.
  Future<List<dynamic>> usuariosPendientes() async {
    final response =
        await _dio.get('$_baseUrl${ApiConstants.syncUsuariosPendientes}');
    return (response.data?['pendientes'] as List<dynamic>?) ?? const [];
  }

  /// Marca los usuarios entregados al servidor como sincronizados.
  Future<void> marcarUsuariosEntregados(List<String> ids) async {
    await _dio.post(
      '$_baseUrl${ApiConstants.syncUsuariosEntregados}',
      data: {'ids': ids},
    );
  }

  /// Empuja los usuarios locales pendientes al servidor central (best-effort).
  /// Usa el token de la credencial global (`serverLogin`) si está disponible;
  /// si no, el interceptor no podrá autenticar y la cola queda intacta.
  Future<void> pushUsuariosServer(
    List<Map<String, dynamic>> items, {
    String? serverUrl,
  }) async {
    final url = _serverBase(serverUrl);
    if (url.isEmpty) return;
    final token = _serverToken;
    if (token == null) return;
    await _dio.post(
      '$url${ApiConstants.syncUsersServer}',
      data: {'items': items},
      options: Options(
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
  }

  Future<Response> createWeighing(Map<String, dynamic> body) async {
    final response = await _dio.post('$_baseUrl${ApiConstants.weighingCreate}', data: body);
    return response;
  }

  Future<Response> closeWeighing(
      String boleto, Map<String, dynamic> body) async {
    final response = await _dio.post(
      '$_baseUrl${ApiConstants.weighingClose(boleto)}',
      data: body,
    );
    return response;
  }

  Future<Response> getWeighingByBoleto(String boleto) async {
    final response = await _dio.get(
        '$_baseUrl${ApiConstants.weighingByBoleto(boleto)}');
    return response;
  }

  Future<Response> listWeighings({Map<String, dynamic>? params}) async {
    final response = await _dio.get(
      '$_baseUrl${ApiConstants.weighingList}',
      queryParameters: params,
    );
    return response;
  }

  Future<Response> listPendientes() async {
    final response =
        await _dio.get('$_baseUrl${ApiConstants.weighingPendientes}');
    return response;
  }

  Future<Response> anularWeighing(String boleto, String motivo) async {
    final response = await _dio.put(
      '$_baseUrl${ApiConstants.weighingAnular(boleto)}',
      data: {'motivo': motivo},
    );
    return response;
  }

  Future<Response> getTicketPdf(
    String boleto, {
    int boletos_por_hoja = 1,
    String tamano_papel = 'Letter',
    String orientacion = 'portrait',
    bool mostrar_encabezado = true,
    bool mostrar_detalles = true,
  }) async {
    final response = await _dio.get(
      '$_baseUrl${ApiConstants.weighingPdf(boleto)}',
      queryParameters: {
        'boletos_por_hoja': boletos_por_hoja,
        'tamano_papel': tamano_papel,
        'orientacion': orientacion,
        'mostrar_encabezado': mostrar_encabezado,
        'mostrar_detalles': mostrar_detalles,
      },
      options: Options(responseType: ResponseType.bytes),
    );
    return response;
  }

  Future<Response> getTicketTxt(String boleto) async {
    final response = await _dio.get(
      '$_baseUrl${ApiConstants.weighingTxt(boleto)}',
      options: Options(responseType: ResponseType.bytes),
    );
    return response;
  }

  // ── Series de numeración (CRUD; el campo de trabajo elige cuál usar) ──
  Future<Response> listSeries() async {
    return _dio.get('$_baseUrl${ApiConstants.seriesBase}');
  }

  Future<Response> createSeries(Map<String, dynamic> body) async {
    return _dio.post('$_baseUrl${ApiConstants.seriesCreate}', data: body);
  }

  Future<Response> updateSeries(
      String idSerie, Map<String, dynamic> body) async {
    return _dio.put(
        '$_baseUrl${ApiConstants.seriesUpdate(idSerie)}', data: body);
  }

  Future<Response> marcarSerieActiva(String idSerie) async {
    return _dio.put(
        '$_baseUrl${ApiConstants.seriesActiva(idSerie)}');
  }

  Future<Response> deleteSeries(String idSerie) async {
    return _dio.delete('$_baseUrl${ApiConstants.seriesDelete(idSerie)}');
  }

  Future<Response> updateWeighing(
      String boleto, Map<String, dynamic> body) async {
    final response = await _dio.put(
      '$_baseUrl${ApiConstants.weighingUpdate(boleto)}',
      data: body,
    );
    return response;
  }

  Future<Response> getCatalogSync() async {
    final response =
        await _dio.get('$_baseUrl${ApiConstants.catalogsSync}');
    return response;
  }

  /// Matriz de accesos (Seguridad y Accesos): `{modulos: [{clave, titulo, accesos}]}`.
  Future<Response> getMatrizSeguridad() async {
    return _dio.get('$_baseUrl${ApiConstants.seguridadMatriz}');
  }

  /// Actualiza el acceso de un (rol, módulo). Devuelve el módulo actualizado.
  Future<Response> putMatrizSeguridad(
    String rol,
    String modulo,
    String acceso,
  ) async {
    return _dio.put(
      '$_baseUrl${ApiConstants.seguridadMatriz}',
      data: {'rol': rol, 'modulo': modulo, 'acceso': acceso},
    );
  }

  /// Lee el peso en vivo de una balanza vía el HAL del backend (B7).
  /// Devuelve el payload crudo `{peso_kg, estable, balanza, hardware, timestamp}`.
  Future<Map<String, dynamic>> readLiveWeight(String balanzaId) async {
    final response =
        await _dio.get('$_baseUrl${ApiConstants.scaleLive(balanzaId)}');
    return response.data as Map<String, dynamic>;
  }

  /// Prueba la conexión de hardware de una balanza.
  /// Devuelve `{balanza, conectado, hardware, protocolo, peso_kg, estable, detalle}`.
  Future<Map<String, dynamic>> probarBalanza(String balanzaId) async {
    final response =
        await _dio.post('$_baseUrl${ApiConstants.balanzaProbar(balanzaId)}');
    return response.data as Map<String, dynamic>;
  }

  Future<Response> getDailyReport(String fecha) async {
    final response = await _dio.get(
      '$_baseUrl${ApiConstants.reportDaily}',
      queryParameters: {'fecha': fecha},
    );
    return response;
  }

Future<Response> getMonthlyReport(int year, int month) async {
    return _dio.get(
      '$_baseUrl${ApiConstants.reportMonthly}',
      queryParameters: {'year': year, 'month': month},
    );
  }

  /// Ranking de transportistas (cerrados/sin anular) en el rango dado.
  Future<Response> getTransportistaReport(
      String desde, String hasta) async {
    return _dio.get(
      '$_baseUrl${ApiConstants.advancedReportTransportista}',
      queryParameters: {'fecha_desde': desde, 'fecha_hasta': hasta},
    );
  }

  /// Volumen por tercero (cliente/proveedor) en el rango.
  Future<Response> getTerceroReport(
      String desde, String hasta, {String? tipo}) async {
    return _dio.get(
      '$_baseUrl${ApiConstants.advancedReportTercero}',
      queryParameters: {
        'fecha_desde': desde,
        'fecha_hasta': hasta,
        if (tipo != null) 'tipo_tercero': tipo,
      },
    );
  }

  /// Distribución de pesos netos por rango de tonelaje.
  Future<Response> getPesoRangoReport(
      String desde, String hasta) async {
    return _dio.get(
      '$_baseUrl${ApiConstants.advancedReportPesoRango}',
      queryParameters: {'fecha_desde': desde, 'fecha_hasta': hasta},
    );
  }

  /// Comparativo mensual actual vs. mes anterior.
  Future<Response> getComparativoReport(int year, int month) async {
    return _dio.get(
      '$_baseUrl${ApiConstants.advancedReportComparativo}',
      queryParameters: {'year': year, 'month': month},
    );
  }

  Future<Response> kardexSaldo(Map<String, dynamic> params) async {
    final response = await _dio.get(
      '$_baseUrl${ApiConstants.kardexSaldo}',
      queryParameters: params,
    );
    return response;
  }

  Future<Response> kardexDetalle(Map<String, dynamic> params) async {
    final response = await _dio.get(
      '$_baseUrl${ApiConstants.kardexDetalle}',
      queryParameters: params,
    );
    return response;
  }

  Future<Response> kardexExportExcel(Map<String, dynamic> params) async {
    final response = await _dio.get(
      '$_baseUrl${ApiConstants.kardexExportExcel}',
      queryParameters: params,
      options: Options(responseType: ResponseType.bytes),
    );
    return response;
  }

  Future<Response> kardexExportPdf(Map<String, dynamic> params) async {
    final response = await _dio.get(
      '$_baseUrl${ApiConstants.kardexExportPdf}',
      queryParameters: params,
      options: Options(responseType: ResponseType.bytes),
    );
    return response;
  }

  Future<Response> exportExcel(Map<String, dynamic> params) async {
    final response = await _dio.get(
      '$_baseUrl${ApiConstants.reportExportExcel}',
      queryParameters: params,
      options: Options(responseType: ResponseType.bytes),
    );
    return response;
  }

  Future<Response> getList(String path) async {
    final response = await _dio.get('$_baseUrl$path');
    return response;
  }

  /// Escanea las básculas conectadas/disponibles (TCP + serial).
  Future<List<Map<String, dynamic>>> descubrirBalanzas() async {
    final response =
        await _dio.get('$_baseUrl${ApiConstants.balanzasDescubrir}');
    return (response.data as List? ?? []).whereType<Map<String, dynamic>>().toList();
  }

  Future<Response> getItem(String path) async {
    final response = await _dio.get('$_baseUrl$path');
    return response;
  }

  Future<Response> createItem(String path, Map<String, dynamic> body) async {
    final response = await _dio.post('$_baseUrl$path', data: body);
    return response;
  }

  Future<Response> updateItem(String path, Map<String, dynamic> body) async {
    final response = await _dio.put('$_baseUrl$path', data: body);
    return response;
  }

  Future<Response> deleteItem(String path) async {
    final response = await _dio.delete('$_baseUrl$path');
    return response;
  }

  Future<Response> listImages(String boleto) async {
    final response = await _dio.get(
      '$_baseUrl/api/v1/weighing/$boleto/imagenes',
    );
    return response;
  }

  Future<Response> uploadImage(
      String boleto, List<int> imageBytes, String fileName,
      {String tipo = 'vehiculo'}) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(imageBytes, filename: fileName),
      'tipo': tipo,
    });
    final response = await _dio.post(
      '$_baseUrl/api/v1/weighing/$boleto/imagenes/archivo',
      data: formData,
    );
    return response;
  }

  /// Sube una foto genérica (catálogos: camión/remolque/conductor) y
  /// devuelve la URL relativa (ej. `/media/camiones/abc.jpg`).
  Future<String> uploadPhotoFile(List<int> imageBytes, String fileName,
      {String? carpeta}) async {
    final formData = FormData.fromMap({
      if (carpeta != null && carpeta.isNotEmpty) 'carpeta': carpeta,
      'file': MultipartFile.fromBytes(imageBytes, filename: fileName),
    });
    final response = await _dio.post(
      '$_baseUrl/api/v1/files/upload',
      data: formData,
    );
    return '${response.data['url']}';
  }


  /// Registra un ajuste manual de inventario (movimiento de kardex).
  ///
  /// [idMovimiento]: 10 = INGRESO, 60 = DESPACHO.
  /// [valorKg]: peso ajustado en kilogramos (positivo).
  /// [documento]: justificación obligatoria.
  Future<Response> crearAjusteInventario({
    required int idMovimiento,
    required String idProducto,
    required String idAlmacen,
    required double valorKg,
    required String documento,
  }) async {
    final response = await _dio.post(
      '$_baseUrl/api/v1/inventario/ajustes',
      data: {
        'id_movimiento': idMovimiento,
        'id_producto': idProducto,
        'id_almacen': idAlmacen,
        'valor_kg': valorKg,
        'documento': documento,
      },
    );
    return response;
  }

  /// Resuelve una URL relativa del servidor (`/media/...`) a una URL completa
  /// apuntando a la API actual.
  String mediaUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    return '$base$url';
  }
}
