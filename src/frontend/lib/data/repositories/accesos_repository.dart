import '../../core/constants/accesos_default.dart';
import '../datasources/local/local_storage.dart';
import '../datasources/remote/api_client.dart';

/// Repositorio de la matriz de Seguridad y Accesos.
///
/// Autoridad: el backend (`GET/PUT /api/v1/seguridad/matriz`). Si la red no
/// está disponible o aún no se cargó, [acceso] cae a [AccesosDefault] y la
/// app sigue funcionando offline. Tras cada carga/guardado se cachea en
/// [LocalStorage] para arrancar rápido y coherente en sesiones siguientes.
class AccesosRepository {
  final ApiClient _apiClient;
  final LocalStorage _localStorage;

  /// Módulo → rol → acceso (`ver`|`editar`|`ninguno`). Solo las claves con
  /// sobrescritura de la empresa; el resto usa [AccesosDefault].
  Map<String, Map<String, String>> _sobrescrituras = const {};
  bool _cargado = false;

  AccesosRepository({
    required ApiClient apiClient,
    required LocalStorage localStorage,
  })  : _apiClient = apiClient,
        _localStorage = localStorage;

  Future<void> cargar() async {
    try {
      final res = await _apiClient.getMatrizSeguridad();
      final modulos = res.data['modulos'] as List<dynamic>;
      final map = <String, Map<String, String>>{};
      for (final m in modulos) {
        final accesos =
            (m as Map<String, dynamic>)['accesos'] as Map<String, dynamic>;
        map[m['clave'] as String] =
            accesos.map((rol, a) => MapEntry(rol, a.toString()));
      }
      _sobrescrituras = map;
      _cargado = true;
      await _localStorage.cacheMatrizAccesos(map);
    } catch (_) {
      final cached = await _localStorage.getCachedMatrizAccesos();
      if (cached != null) {
        _sobrescrituras = cached;
        _cargado = true;
      }
    }
  }

  bool get cargado => _cargado;

  /// Acceso efectivo de `rol` al `modulo` (sobrescritura o default).
  String acceso(String rol, String modulo) {
    return _sobrescrituras[modulo]?[rol] ?? AccesosDefault.acceso(rol, modulo);
  }

  bool puedeVer(String rol, String modulo) => acceso(rol, modulo) != 'ninguno';

  bool puedeEditar(String rol, String modulo) => acceso(rol, modulo) == 'editar';

  /// Sobrescribe en backend y refresca en memoria/cache en caliente.
  Future<bool> actualizar(String rol, String modulo, String acceso) async {
    try {
      final res = await _apiClient.putMatrizSeguridad(rol, modulo, acceso);
      final data = res.data as Map<String, dynamic>;
      final accesos =
          (data['accesos'] as Map<String, dynamic>).map(
            (r, a) => MapEntry(r, a.toString()),
          );
      final map = Map<String, Map<String, String>>.from(_sobrescrituras);
      map[modulo] = {for (final e in accesos.entries) e.key: e.value};
      _sobrescrituras = map;
      _cargado = true;
      await _localStorage.cacheMatrizAccesos(map);
      return true;
    } catch (_) {
      return false;
    }
  }
}