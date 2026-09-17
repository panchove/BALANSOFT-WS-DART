import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
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
  String? _resultadoLocal;
  String? _resultadoServer;

  @override
  void initState() {
    super.initState();
    _serverCtrl = TextEditingController(text: AppConfig.serverApiUrl ?? '');
    _localCtrl = TextEditingController(text: AppConfig.apiBaseUrl ?? '');
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
          if (esSetup) const _SetupBanner(),
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
        ],
      ),
    );
  }

  Widget _buildCompact(BuildContext context, bool esSetup) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (esSetup) const _SetupBanner(),
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
  const _SetupBanner();

  @override
  Widget build(BuildContext context) {
    return const Card(
      color: SwsColors.blue100,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
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
      ),
    );
  }
}