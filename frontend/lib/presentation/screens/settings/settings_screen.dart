import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/section_header.dart';
import '../../../injection.dart' as di;
import '../../../data/services/scale_api_client.dart';
import '../../../data/datasources/local/local_storage.dart';
import 'license_admin_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeController themeController;
  const SettingsScreen({super.key, required this.themeController});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _scaleHostCtrl = TextEditingController(text: '127.0.0.1');
  final _scalePortCtrl = TextEditingController(text: '5555');
  bool _scaleEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadScaleConfig();
  }

  Future<void> _loadScaleConfig() async {
    final config = await di.sl<LocalStorage>().getScaleConfig();
    if (!mounted) return;
    setState(() {
      _scaleHostCtrl.text = config.host;
      _scalePortCtrl.text = config.port.toString();
    });
  }

  @override
  void dispose() {
    _scaleHostCtrl.dispose();
    _scalePortCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveScaleConfig() async {
    final host = _scaleHostCtrl.text.trim();
    final port = int.tryParse(_scalePortCtrl.text) ?? 5555;
    await di.sl<LocalStorage>().setScaleConfig(host: host, port: port);
    di.sl<ScaleApiClient>().configurarFallbackTcp(host, port);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuración de báscula guardada'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        children: [
          const SectionHeader(title: 'Cuenta'),
          ListTile(
            leading: const Icon(Icons.person_outlined),
            title: const Text('Perfil'),
            subtitle: BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                if (state is AuthAuthenticated) {
                  return Text('${state.user.nombre} - ${state.user.email}');
                }
                return const Text('No autenticado');
              },
            ),
          ),
          const ListTile(
            leading: Icon(Icons.business_outlined),
            title: Text('Empresa'),
            subtitle: Text('Información de la empresa'),
          ),
          const Divider(),
          const SectionHeader(title: 'Báscula / Dispositivo'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text('Conexión a báscula'),
                  subtitle: const Text('Activar conexión a báscula BSDD / hardware'),
                  value: _scaleEnabled,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _scaleEnabled = v),
                ),
                if (_scaleEnabled) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _scaleHostCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Dirección IP',
                            hintText: '127.0.0.1',
                            prefixIcon: Icon(Icons.wifi_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _scalePortCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Puerto',
                            hintText: '5555',
                            prefixIcon: Icon(Icons.settings_ethernet),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _saveScaleConfig,
                      child: const Text('Guardar configuración'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          const Divider(),
          const SectionHeader(title: 'Licencia'),
          const _LicenciaTile(),
          const Divider(),
          const SectionHeader(title: 'Sincronización'),
          SwitchListTile(
            secondary: const Icon(Icons.sync_outlined),
            title: const Text('Sincronización automática'),
            subtitle: const Text('Sincronizar cada 5 minutos'),
            value: true,
            onChanged: (v) {},
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Sincronizar ahora'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sincronizando...')),
              );
            },
          ),
          const Divider(),
          const SectionHeader(title: 'Archivos'),
          const _DirectorioTile(),
          const Divider(),
          const SectionHeader(title: 'Apariencia'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Tema'),
            subtitle: Text(_temaLabel(widget.themeController.tema)),
          ),
          _ThemeSelector(themeController: widget.themeController),
          const Divider(),
          const SectionHeader(title: 'General'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Acerca de'),
            subtitle: Text('Balansoft-WS v1.0.0'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: SwsColors.danger),
            title: const Text('Cerrar Sesión', style: TextStyle(color: SwsColors.danger)),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Cerrar Sesión'),
                  content: const Text('¿Está seguro que desea cerrar sesión?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.read<AuthBloc>().add(LogoutEvent());
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      child: const Text('Cerrar', style: TextStyle(color: SwsColors.danger)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _temaLabel(TemaApp tema) {
    switch (tema) {
      case TemaApp.claro:
        return 'Claro';
      case TemaApp.oscuro:
        return 'Oscuro';
      case TemaApp.sistema:
        return 'Sistema';
    }
  }
}

class _ThemeSelector extends StatelessWidget {
  final ThemeController themeController;
  const _ThemeSelector({required this.themeController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => RadioGroup<TemaApp>(
        groupValue: themeController.tema,
        onChanged: (v) {
          if (v != null) themeController.setTema(v);
        },
        child: Column(
          children: TemaApp.values.map((tema) {
            return RadioListTile<TemaApp>(
              title: Text(_label(tema)),
              value: tema,
              activeColor: SwsColors.accent,
            );
          }).toList(),
        ),
      ),
    );
  }

  String _label(TemaApp tema) {
    switch (tema) {
      case TemaApp.claro:
        return 'Claro';
      case TemaApp.oscuro:
        return 'Oscuro';
      case TemaApp.sistema:
        return 'Sistema (automático)';
    }
  }
}

class _DirectorioTile extends StatefulWidget {
  const _DirectorioTile();

  @override
  State<_DirectorioTile> createState() => _DirectorioTileState();
}

class _DirectorioTileState extends State<_DirectorioTile> {
  String? _ruta;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final base = await di.sl<LocalStorage>().getDescargasDir();
    if (mounted) setState(() => _ruta = base);
  }

  Future<void> _copiar() async {
    final ruta = _ruta;
    if (ruta == null) return;
    await Clipboard.setData(ClipboardData(text: ruta));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ruta copiada al portapapeles')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder_open_outlined),
      title: const Text('Carpeta de guardado'),
      subtitle: Text(
        _ruta ?? 'Obteniendo...',
        style: const TextStyle(fontSize: 12),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.copy),
        onPressed: _copiar,
        tooltip: 'Copiar ruta',
      ),
      onTap: _copiar,
    );
  }
}

/// Acceso a la administración de licencias (solo ADMIN, REQ-NF-ARQ-007).
class _LicenciaTile extends StatelessWidget {
  const _LicenciaTile();

  @override
  Widget build(BuildContext context) {
    final rol = context.select<AuthBloc, String?>((bloc) {
      final state = bloc.state;
      return state is AuthAuthenticated ? state.user.rol : null;
    });
    final esAdmin = rol == 'ADMIN';
    return ListTile(
      leading: Icon(
        esAdmin ? Icons.card_membership_outlined : Icons.lock_outline,
      ),
      title: const Text('Administración de licencias'),
      subtitle: Text(
        esAdmin
            ? 'Tier, vencimiento y renovación'
            : 'Solo visible para administradores',
      ),
      enabled: esAdmin,
      onTap: esAdmin
          ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LicenseAdminScreen(),
                ),
              )
          : null,
    );
  }
}