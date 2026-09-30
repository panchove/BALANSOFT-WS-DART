/// Diagnóstico del sistema para una estación ya instalada.
///
/// A diferencia de `EnvironmentCheckScreen` (wizard de instalación, que revisa
/// el SO: servicio de PostgreSQL, drivers, puertos y permisos), esta pantalla
/// solo consulta el estado del sistema en producción: API local, base de
/// datos, licencia, sincronización y versión. Todo es de solo lectura.
library;

import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/mensaje_error.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;

enum _Estado { cargando, ok, aviso, error }

class _Item {
  _Item(this.id, this.titulo, this.detalle, this.estado);

  final String id;
  final String titulo;
  String detalle;
  _Estado estado;
}

class SystemDiagnosticsScreen extends StatefulWidget {
  const SystemDiagnosticsScreen({super.key});

  @override
  State<SystemDiagnosticsScreen> createState() =>
      _SystemDiagnosticsScreenState();
}

class _SystemDiagnosticsScreenState extends State<SystemDiagnosticsScreen> {
  late final List<_Item> _items = [
    _Item('api', 'diag_api'.tr(), '', _Estado.cargando),
    _Item('db', 'diag_db'.tr(), '', _Estado.cargando),
    _Item('licencia', 'diag_license'.tr(), '', _Estado.cargando),
    _Item('sync', 'diag_sync'.tr(), '', _Estado.cargando),
    _Item('version', 'diag_version'.tr(), '', _Estado.cargando),
  ];

  bool _verificando = false;
  DateTime? _verificado;

  int get _fallos => _items.where((i) => i.estado == _Estado.error).length;
  int get _avisos => _items.where((i) => i.estado == _Estado.aviso).length;

  @override
  void initState() {
    super.initState();
    _verificar();
  }

  void _actualizar(String id, _Estado estado, String detalle) {
    setState(() {
      final i = _items.firstWhere((x) => x.id == id);
      i.estado = estado;
      i.detalle = detalle;
    });
  }

  Future<void> _verificar() async {
    if (_verificando) return;
    setState(() {
      _verificando = true;
      for (final i in _items) {
        i.estado = _Estado.cargando;
        i.detalle = '';
      }
    });

    final api = di.sl<ApiClient>();
    await Future.wait([
      _verificarApi(api),
      _verificarEntorno(api),
      _verificarLicencia(api),
      _verificarSync(api),
    ]);

    if (!mounted) return;
    setState(() {
      _verificando = false;
      _verificado = DateTime.now();
    });
  }

  /// API local: responde /health en la URL configurada para esta estación.
  Future<void> _verificarApi(ApiClient api) async {
    final base = AppConfig.apiBaseUrl ?? '';
    try {
      final ok = await api.health();
      if (!mounted) return;
      _actualizar(
        'api',
        ok ? _Estado.ok : _Estado.error,
        ok ? base : '${'diag_api_unreachable'.tr()} $base',
      );
    } catch (e) {
      if (!mounted) return;
      _actualizar('api', _Estado.error,
          mensajeDeError(e, fallback: 'diag_api_unreachable'.tr()));
    }
  }

  /// Base de datos y versión: una sola llamada a /environment.
  Future<void> _verificarEntorno(ApiClient api) async {
    final env = await api.environment();
    if (!mounted) return;
    if (env == null) {
      _actualizar('db', _Estado.error, 'diag_db_unreachable'.tr());
      _actualizar('version', _Estado.aviso, 'diag_unavailable'.tr());
      return;
    }
    final pg = (env['postgres'] as Map?)?.cast<String, dynamic>() ?? const {};
    final conectado = pg['conectado'] == true;
    final esquema = pg['esquema_listo'] == true;
    final bd = (pg['bd'] ?? '').toString();
    final tablas = pg['n_tablas'];

    _actualizar(
      'db',
      conectado && esquema ? _Estado.ok : _Estado.error,
      conectado && esquema
          ? [
              bd,
              if (tablas != null)
                AppTranslations.tr('diag_tables', args: ['$tablas'])
            ].join(' · ')
          : 'diag_db_incomplete'.tr(),
    );

    final apiVer = ((env['api'] as Map?)?['version'] ?? '').toString();
    final rol = ((env['sistema'] as Map?)?['app_role'] ?? '').toString();
    _actualizar(
      'version',
      _Estado.ok,
      [
        '${AppConfig.appName} ${AppConfig.appVersion}',
        if (apiVer.isNotEmpty) 'API $apiVer',
        if (rol.isNotEmpty) rol.toUpperCase(),
      ].join(' · '),
    );
  }

  /// Licencia de la cuenta (solo disponible para el administrador).
  Future<void> _verificarLicencia(ApiClient api) async {
    try {
      final data = await api.getLicenseSnapshot();
      if (!mounted) return;
      final valido = data['valid'] == true;
      final tier = (data['tier'] ?? '').toString();
      final estado = (data['status'] ?? '').toString();
      final expira = (data['expires_at'] ?? '').toString();
      final detalle = [
        if (tier.isNotEmpty) tier,
        if (estado.isNotEmpty) estado,
        if (valido && expira.isNotEmpty)
          AppTranslations.tr('diag_expires', args: [_fecha(expira)]),
      ].join(' · ');
      _actualizar(
        'licencia',
        valido ? _Estado.ok : _Estado.error,
        detalle.isEmpty
            ? (data['message'] ?? 'diag_unavailable'.tr()).toString()
            : detalle,
      );
    } catch (e) {
      if (!mounted) return;
      // 401/403: el usuario no es admin; no es un fallo del sistema.
      final msg = mensajeDeError(e, fallback: 'diag_unavailable'.tr());
      _actualizar('licencia', _Estado.aviso, msg);
    }
  }

  /// Pendientes de sincronizar contra el servidor titular.
  Future<void> _verificarSync(ApiClient api) async {
    final data = await api.syncStatus();
    if (!mounted) return;
    if (data == null) {
      _actualizar('sync', _Estado.aviso, 'diag_sync_offline'.tr());
      return;
    }
    final pendientes = data['pendientes'];
    final ultima = (data['ultima_sync'] ?? '').toString();
    _actualizar(
      'sync',
      _Estado.ok,
      AppTranslations.tr('diag_sync_detail', args: [
        '${pendientes ?? 0}',
        ultima.isEmpty ? 'diag_never'.tr() : _fecha(ultima),
      ]),
    );
  }

  String _fecha(String iso) {
    if (iso.isEmpty) return '-';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)}/${d.year} ${dos(d.hour)}:${dos(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('system_diagnostics'.tr()),
        actions: [
          IconButton(
            onPressed: _verificando ? null : _verificar,
            icon: _verificando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'verify_again'.tr(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _verificar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _resumen(tema),
            const SizedBox(height: 16),
            for (final i in _items) ...[
              _tarjeta(i, tema),
              const SizedBox(height: 10),
            ],
            if (_verificado != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  AppTranslations.tr(
                    'diag_checked_at',
                    args: [_fecha(_verificado!.toIso8601String())],
                  ),
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 11, color: tema.colorScheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _resumen(ThemeData tema) {
    final (IconData icono, Color color, String msg) =
        switch ((_fallos, _avisos)) {
      (0, 0) => (
          Icons.verified_outlined,
          SwsColors.success,
          'diag_all_ok'.tr()
        ),
      (0, _) => (
          Icons.info_outline,
          SwsColors.warning,
          AppTranslations.tr('diag_warnings', args: ['$_avisos'])
        ),
      _ => (
          Icons.report_problem_outlined,
          SwsColors.danger,
          AppTranslations.tr('diag_problems', args: ['$_fallos'])
        ),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icono, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(_Item item, ThemeData tema) {
    final (IconData icono, Color color) = switch (item.estado) {
      _Estado.cargando => (Icons.hourglass_top, SwsColors.gray400),
      _Estado.ok => (Icons.check_circle, SwsColors.success),
      _Estado.aviso => (Icons.info_outline, SwsColors.warning),
      _Estado.error => (Icons.cancel, SwsColors.danger),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 24,
                height: 24,
                child: Icon(icono, color: color, size: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.titulo,
                    style: tema.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.detalle.isEmpty ? 'diag_checking'.tr() : item.detalle,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: item.estado == _Estado.error
                          ? SwsColors.danger
                          : tema.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
