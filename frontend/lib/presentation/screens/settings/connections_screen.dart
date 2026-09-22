import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/wserver_manager.dart';
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
  late final TextEditingController _serverCtrl;
  late final TextEditingController _localCtrl;
  bool _probandoLocal = false;
  bool _probandoServer = false;
  bool _wserverOnline = false;
  bool _verificandoInicio = false;
  String? _resultadoLocal;
  String? _resultadoServer;

  @override
  void initState() {
    super.initState();
    _serverCtrl = TextEditingController(text: AppConfig.serverApiUrl ?? '');
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
    _serverCtrl.dispose();
    _localCtrl.dispose();
    super.dispose();
  }

  String get _localUrl => _localCtrl.text.trim().replaceAll(RegExp(r'/$'), '');
  String get _serverUrl => _serverCtrl.text.trim().replaceAll(RegExp(r'/$'), '');

  Future<void> _probarServidor() async {
    setState(() {
      _probandoServer = true;
      _resultadoServer = null;
    });
    final ok = await di.sl<ApiClient>().serverHealth(serverUrl: _serverUrl);
    if (!mounted) return;
    setState(() {
      _probandoServer = false;
      _resultadoServer =
          ok ? 'Servidor central accesible ✓' : 'No se pudo conectar al servidor central';
    });
  }

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
          ? 'Indica primero la URL de la API local'
          : (ok ? 'API local accesible ✓' : 'No se pudo conectar a la API local');
    });
  }

  Future<void> _guardar() async {
    final localOk = _localUrl.isNotEmpty;
    await AppConfig.setServerApiUrl(_serverUrl.isNotEmpty ? _serverUrl : AppConfig.defaultServerApiUrl);
    if (localOk) {
      await AppConfig.setApiBaseUrl(_localUrl);
      di.sl<ApiClient>().setBaseUrl(_localUrl);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          localOk ? 'Conexiones guardadas' : 'Guardado: falta configurar la API local',
        ),
        backgroundColor: localOk ? SwsColors.success : SwsColors.warning,
      ),
    );

    if (widget.setupMode && localOk && mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  Future<void> _reiniciarInstalacion() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reiniciar instalación'),
        content: const Text(
          'Se borrará la URL de la API local configurada y la app volverá al '
          'modo instalación (verificación de entorno). '
          '¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await AppConfig.quitarApiBaseUrl();
    di.sl<ApiClient>().setBaseUrl(AppConfig.defaultApiBaseUrl);
    WServerManager.reset();

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/setup',
      (route) => false,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _serverCard(context)),
              const SizedBox(width: 16),
              Expanded(child: _localCard(context)),
            ],
          ),
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
            Center(
              child: TextButton.icon(
                onPressed: _reiniciarInstalacion,
                icon: const Icon(Icons.settings_backup_restore, size: 18),
                label: const Text('Volver al inicio de instalación'),
              ),
            ),
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
        _serverCard(context),
        const SizedBox(height: 12),
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
          TextButton.icon(
            onPressed: _reiniciarInstalacion,
            icon: const Icon(Icons.settings_backup_restore, size: 18),
            label: const Text('Volver al inicio de instalación'),
          ),
        ],
      ],
    );
  }

  Widget _serverCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_outlined, color: SwsColors.accent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Servidor central (cuenta y licencia)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Siempre disponible: se usa para validar la cuenta y la licencia.',
              style: TextStyle(fontSize: 12, color: SwsColors.gray500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serverCtrl,
              decoration: const InputDecoration(
                labelText: 'URL del servidor central',
                hintText: 'http://localhost:8002',
                prefixIcon: Icon(Icons.cloud_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _probandoServer ? null : _probarServidor,
                icon: _probandoServer
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.network_check, size: 18),
                label: const Text('Probar'),
              ),
            ),
            if (_resultadoServer != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _resultadoServer!,
                  style: TextStyle(
                    fontSize: 12,
                    color: (_resultadoServer?.contains('✓') ?? false)
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

  Widget _localCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.dns_outlined, color: SwsColors.accent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'API local (estación)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
                label: const Text('Probar'),
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
      estado = const Row(
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Comprobando WServer local…', style: TextStyle(fontSize: 12)),
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
            const Row(
              children: [
                Icon(Icons.settings_remote_outlined, color: SwsColors.accent),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Primera configuración: indica la URL de la API local de '
                    'esta estación. El servidor central ya viene predefinido.',
                    style: TextStyle(fontSize: 13),
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