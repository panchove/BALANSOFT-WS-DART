import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/api_constants.dart';

class ApiClient {
  final Dio _dio;
  final String _baseUrl;
  Future<String?> Function()? _refreshTokenHandler;

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

  void onUnauthorized(Future<String?> Function() handler) {
    _refreshTokenHandler = handler;
  }

  void _setupInterceptor() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 && _refreshTokenHandler != null) {
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

  Future<Response> getTicketPdf(String boleto) async {
    final response = await _dio.get(
      '$_baseUrl${ApiConstants.weighingPdf(boleto)}',
      options: Options(responseType: ResponseType.bytes),
    );
    return response;
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
