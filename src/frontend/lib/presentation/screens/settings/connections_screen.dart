import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;

/// Pantalla de conexiones: servidor central (siempre presente) y API local
/// (se configura en este punto si aún no está configurada).
class ConnectionsScreen extends StatefulWidget {
  /// true cuando se abre como configuración inicial (primera ejecución).
  final bool setupMode;
  const ConnectionsScreen({super.key, this.setupMode = false});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  late final TextEditingController _localCtrl;
  bool _probandoLocal = false;
  bool _wserverOnline = false;
  bool _verificandoInicio = false;
  String? _resultadoLocal;

  @override
  void initState() {
    super.initState();
    _localCtrl = TextEditingController(
      text: AppConfig.apiBaseUrl ??
          (widget.setupMode ? AppConfig.defaultApiBaseUrl : ''),
    );
    if (widget.setupMode) {
      // Al abrir el modo instalación se comprueba automáticamente si el
      // WServer (API local) ya está levantado y listo para probar/editar.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        setState(() => _verificandoInicio = true);
        await _probarLocal();
        if (mounted) setState(() => _verificandoInicio = false);
      });
    }
  }

  @override
  void dispose() {
    _localCtrl.dispose();
    super.dispose();
  }

  String get _localUrl => _localCtrl.text.trim().replaceAll(RegExp(r'/$'), '');

  Future<void> _probarLocal() async {
    setState(() {
      _probandoLocal = true;
      _resultadoLocal = null;
    });
    bool ok = false;
    try {
      ok = await ApiClient(baseUrl: _localUrl).health();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _probandoLocal = false;
      final accesible = _localUrl.isNotEmpty && ok;
      _wserverOnline = accesible;
      _resultadoLocal = _localUrl.isEmpty
          ? 'connection_hint_url_first'.tr()
          : (ok
              ? 'connection_local_ok'.tr()
              : 'connection_unreachable'.tr());
    });
  }

  Future<void> _guardar() async {
    if (_localUrl.isEmpty) {
      _avisar('connection_hint_url_first', SwsColors.warning);
      return;
    }
    // La URL solo se persiste si el WServer responde: una URL escrita a mano
    // pero inaccesible dejaría la estación sin API local.
    setState(() {
      _probandoLocal = true;
      _resultadoLocal = null;
    });
    bool ok = false;
    try {
      ok = await ApiClient(baseUrl: _localUrl).health();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _probandoLocal = false;
      _wserverOnline = ok;
    });
    if (!ok) {
      _avisar('connection_unreachable', SwsColors.danger);
      return;
    }

    await AppConfig.setApiBaseUrl(_localUrl);
    di.sl<ApiClient>().setBaseUrl(_localUrl);
    _avisar('connections_saved', SwsColors.success);
  }

  void _avisar(String clave, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(clave.tr()),
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final esSetup = widget.setupMode;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;

    return Scaffold(
      appBar: AppBar(title: Text(esSetup ? 'Configurar conexiones' : 'Conexiones')),
      body: isWide ? _buildWide(context, esSetup) : _buildCompact(context, esSetup),
    );
  }

  Widget _buildWide(BuildContext context, bool esSetup) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (esSetup) _SetupBanner(
            wserverOnline: _wserverOnline,
            verificando: _verificandoInicio,
          ),
          const SizedBox(height: 16),
          _localCard(context),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 320,
              height: 48,
              child: FilledButton.icon(
                onPressed: _guardar,
                icon: const Icon(Icons.save_outlined),
                label: Text(esSetup ? 'Guardar y continuar' : 'Guardar conexiones'),
              ),
            ),
          ),
          if (!esSetup) ...[
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildCompact(BuildContext context, bool esSetup) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (esSetup) _SetupBanner(
          wserverOnline: _wserverOnline,
          verificando: _verificandoInicio,
        ),
        const SizedBox(height: 8),
        _localCard(context),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _guardar,
            icon: const Icon(Icons.save_outlined),
            label: Text(esSetup ? 'Guardar y continuar' : 'Guardar conexiones'),
          ),
        ),
        if (!esSetup) ...[
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _localCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dns_outlined, color: SwsColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'local_api_station'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _localUrl.isEmpty
                  ? 'Aún no configurada: se configura aquí al ejecutarse por primera vez.'
                  : 'Se usará para la operación diaria (boletos, catálogos, reportes).',
              style: const TextStyle(fontSize: 12, color: SwsColors.gray500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _localCtrl,
              decoration: const InputDecoration(
                labelText: 'URL de la API local',
                hintText: 'http://localhost:8000',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _probandoLocal ? null : _probarLocal,
                icon: _probandoLocal
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering, size: 18),
                label: Text('test'.tr()),
              ),
            ),
            if (_resultadoLocal != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _resultadoLocal!,
                  style: TextStyle(
                    fontSize: 12,
                    color: (_resultadoLocal?.contains('✓') ?? false)
                        ? SwsColors.success
                        : SwsColors.danger,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SetupBanner extends StatelessWidget {
  const _SetupBanner({this.wserverOnline = false, this.verificando = false});

  /// ¿La API local (WServer) está accesible?
  final bool wserverOnline;

  /// ¿Se está comprobando el estado del WServer al abrir?
  final bool verificando;

  @override
  Widget build(BuildContext context) {
    final Widget estado;
    if (verificando) {
      estado = Row(
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text('checking_wserver'.tr(), style: const TextStyle(fontSize: 12)),
        ],
      );
    } else {
      estado = Row(
        children: [
          Icon(
            wserverOnline ? Icons.check_circle : Icons.error_outline,
            size: 16,
            color: wserverOnline ? SwsColors.success : SwsColors.warning,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              wserverOnline
                  ? 'WServer local activo: la API responde y la conexión es editable.'
                  : 'WServer local no detectado: indica la URL de una API local '
                      'alcanzable (o arranca el servicio WServer).',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      );
    }

    return Card(
      color: SwsColors.blue100,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings_remote_outlined, color: SwsColors.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'first_config_hint'.tr(),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            estado,
          ],
        ),
      ),
    );
  }
}