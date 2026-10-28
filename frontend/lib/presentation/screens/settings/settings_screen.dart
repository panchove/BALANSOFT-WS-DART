import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../providers/bloc/sync/sync_bloc.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/wserver_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../injection.dart' as di;
import '../../../data/services/scale_api_client.dart';
import '../../../data/datasources/local/local_storage.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../domain/entities/catalogs.dart';
import 'license_admin_screen.dart';
import 'connections_screen.dart';
import 'usuarios_screen.dart';
import 'system_diagnostics_screen.dart';
import 'typography_settings_screen.dart';
import 'backups_screen.dart';
import '../../../core/utils/save_file_utils.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/i18n/translations.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeController themeController;
  final LocaleController? localeController;
  const SettingsScreen({
    super.key,
    required this.themeController,
    this.localeController,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  LocaleController? _localLocaleController;
  LocaleController get _localeController {
    if (widget.localeController != null) return widget.localeController!;
    if (di.sl.isRegistered<LocaleController>()) {
      return di.sl<LocaleController>();
    }
    return _localLocaleController ??= LocaleController();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings_title'.tr()),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(icon: const Icon(Icons.tune, size: 18), text: 'General'),
            Tab(icon: const Icon(Icons.scale_outlined, size: 18), text: 'Operación'),
            Tab(icon: const Icon(Icons.settings_suggest_outlined, size: 18), text: 'Sistema'),
            Tab(icon: const Icon(Icons.shield_outlined, size: 18), text: 'Seguridad'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _GeneralTab(
            themeController: widget.themeController,
            localeController: _localeController,
          ),
          const _OperacionTab(),
          const _SistemaTab(),
          const _SeguridadTab(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TAB 1 — General
// ═══════════════════════════════════════════════════════════════════════

class _GeneralTab extends StatelessWidget {
  final ThemeController themeController;
  final LocaleController localeController;

  const _GeneralTab({
    required this.themeController,
    required this.localeController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionCard(
          icon: Icons.account_balance_outlined,
          title: 'Cuenta y Empresa',
          children: [
            _AccountInfoTile(),
            _IdentidadTile(),
          ],
        ),
        _SectionCard(
          icon: Icons.palette_outlined,
          title: 'Apariencia e Idioma',
          children: [
            _ThemeSelector(themeController: themeController),
            const Divider(),
            _LanguageSelector(localeController: localeController),
          ],
        ),
        _SectionCard(
          icon: Icons.format_size_outlined,
          title: 'tipografia_titulo'.tr(),
          children: [
            ListTile(
              leading: const Icon(Icons.format_size_outlined),
              title: Text('tipografia_titulo'.tr()),
              subtitle: Text('tipografia_subtitulo'.tr()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const TypographySettingsScreen(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TAB 2 — Operación
// ═══════════════════════════════════════════════════════════════════════

class _OperacionTab extends StatefulWidget {
  const _OperacionTab();

  @override
  State<_OperacionTab> createState() => _OperacionTabState();
}

class _OperacionTabState extends State<_OperacionTab> {
  bool _pesoManualPermitido = true;
  bool _cargandoPesoManual = true;

  @override
  void initState() {
    super.initState();
    _cargarPesoManual();
  }

  Future<void> _cargarPesoManual() async {
    try {
      final permitido = await di.sl<ApiClient>().getPesoManualPermitido();
      if (mounted) setState(() {
        _pesoManualPermitido = permitido;
        _cargandoPesoManual = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoPesoManual = false);
    }
  }

  Future<void> _togglePesoManual(bool valor) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await di.sl<ApiClient>().setPesoManualPermitido(valor);
      if (!mounted) return;
      setState(() => _pesoManualPermitido = valor);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            valor
                ? 'Peso manual habilitado'
                : 'Peso manual deshabilitado',
          ),
          backgroundColor: SwsColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: $e'),
          backgroundColor: SwsColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          icon: Icons.keyboard_outlined,
          title: 'Peso Manual',
          children: [
            if (_cargandoPesoManual)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              SwitchListTile(
                secondary: const Icon(Icons.edit_note_outlined),
                title: const Text('Permitir peso manual'),
                subtitle: const Text(
                  'Cuando no haya báscula conectada, el operador podrá ingresar el peso a mano. '
                  'Desactivado: el formulario de pesaje bloqueará el guardado hasta que haya báscula.',
                ),
                value: _pesoManualPermitido,
                onChanged: _togglePesoManual,
              ),
          ],
        ),
        const _SectionCard(
          icon: Icons.scale_outlined,
          title: 'Básculas por defecto',
          children: [
            _BalanzasSelectorSection(),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TAB 3 — Sistema
// ═══════════════════════════════════════════════════════════════════════

class _SistemaTab extends StatelessWidget {
  const _SistemaTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionCard(
          icon: Icons.wifi_tethering_outlined,
          title: 'Conexiones',
          children: [_ConexionesTile(), _DiagnosticoTile()],
        ),
        const _SectionCard(
          icon: Icons.storage_outlined,
          title: 'Servidor Local (WServer)',
          children: [_WServerPanel()],
        ),
        _SectionCard(
          icon: Icons.sync_outlined,
          title: 'Sincronización',
          children: _syncChildren(context),
        ),
        const _SectionCard(
          icon: Icons.folder_open_outlined,
          title: 'Archivos',
          children: [_DirectorioTile()],
        ),
        if (AppConfig.esServidor)
          _SectionCard(
            icon: Icons.backup_outlined,
            title: 'backup_titulo'.tr(),
            children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: Text('backup_titulo'.tr()),
                subtitle: Text('backup_crear'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BackupsScreen()),
                ),
              ),
            ],
          ),
      ],
    );
  }

  static List<Widget> _syncChildren(BuildContext context) {
    final syncBloc = context.read<SyncBloc?>();
    final syncAuto = AppConfig.syncAutoEnabled;
    return [
      SwitchListTile(
        secondary: const Icon(Icons.sync_outlined),
        title: Text('sync_auto'.tr()),
        subtitle: Text('auto_sync_every'.tr(null, [
          AppConstants.syncIntervalMinutes.toString(),
        ])),
        value: syncAuto,
        dense: true,
        onChanged: (v) async {
          await AppConfig.setSyncAutoEnabled(v);
          syncBloc?.add(SetAutoSyncEnabledEvent(v));
        },
      ),
      ListTile(
        leading: const Icon(Icons.cloud_upload_outlined),
        title: Text('sync_now'.tr()),
        onTap: () {
          syncBloc?.add(SyncWeighingsEvent());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('syncing'.tr())),
          );
        },
      ),
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TAB 4 — Seguridad
// ═══════════════════════════════════════════════════════════════════════

class _SeguridadTab extends StatelessWidget {
  const _SeguridadTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _SectionCard(
          icon: Icons.card_membership_outlined,
          title: 'Licencia',
          children: [_LicenseTile()],
        ),
        _SectionCard(
          icon: Icons.group_outlined,
          title: 'Usuarios y Roles',
          children: [_UsuariosTile()],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Selector de básculas (reutilizable)
// ═══════════════════════════════════════════════════════════════════════

class _BalanzasSelectorSection extends StatefulWidget {
  const _BalanzasSelectorSection();

  @override
  State<_BalanzasSelectorSection> createState() =>
      _BalanzasSelectorSectionState();
}

class _BalanzasSelectorSectionState extends State<_BalanzasSelectorSection> {
  static const _scaleDefaultKey = 'scale_default_id';
  static const _scaleEntradaKey = 'scale_default_entrada_id';
  static const _scaleSalidaKey = 'scale_default_salida_id';

  List<Scale> _balanzas = const [];
  Scale? _balanzaDefault;
  Scale? _balanzaEntrada;
  Scale? _balanzaSalida;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final resp = await di.sl<ApiClient>().getList(ApiConstants.balanzas);
      final filas = (resp.data as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Scale.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _balanzas = filas;
        _balanzaDefault = _buscarPreferida(filas, _scaleDefaultKey);
        _balanzaEntrada = _buscarPreferida(filas, _scaleEntradaKey);
        _balanzaSalida = _buscarPreferida(filas, _scaleSalidaKey);
      });
    } catch (_) {
      if (mounted) setState(() => _balanzas = const []);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Scale? _buscarPreferida(List<Scale> filas, String clave) {
    final id = AppConfig.prefs.getString(clave) ??
        AppConfig.prefs.getString(_scaleDefaultKey);
    if (id == null || id.isEmpty) return null;
    final coincidencias = filas.where((b) => b.id == id);
    return coincidencias.isNotEmpty ? coincidencias.first : null;
  }

  Future<void> _onSeleccionada(
    Scale? b,
    String clave,
    void Function(Scale?) onEstado,
  ) async {
    setState(() => onEstado(b));
    if (b == null) {
      await AppConfig.prefs.remove(clave);
      return;
    }
    await AppConfig.prefs.setString(clave, b.id);
    if (b.ipAddress != null && b.ipAddress!.isNotEmpty) {
      di.sl<ScaleApiClient>().configurarFallbackTcp(
            b.ipAddress!,
            b.puertoTcp ?? 5555,
          );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Báscula por defecto: ${b.descripcion}'),
          backgroundColor: SwsColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _selector(
    String etiqueta,
    String ayuda,
    Scale? seleccionada,
    void Function(Scale?) onChanged,
  ) {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            ayuda,
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        InputDecorator(
          decoration: InputDecoration(
            labelText: etiqueta,
            prefixIcon: const Icon(Icons.scale_outlined),
            suffixIcon: IconButton(
              tooltip: 'Actualizar básculas',
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Scale?>(
              value: seleccionada,
              isExpanded: true,
              isDense: true,
              hint: Text('not_selected'.tr()),
              items: [
                DropdownMenuItem<Scale?>(
                  value: null,
                  child: Text('not_selected'.tr()),
                ),
                for (final b in _balanzas)
                  if (b.activo)
                    DropdownMenuItem<Scale?>(
                      value: b,
                      child: Text(
                        b.etiqueta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _selector(
          'Báscula por defecto en ENTRADAS',
          'default_scale_entry_hint'.tr(),
          _balanzaEntrada,
          (b) => _onSeleccionada(b, _scaleEntradaKey, (v) => _balanzaEntrada = v),
        ),
        const Divider(),
        _selector(
          'Báscula por defecto en SALIDAS',
          'default_scale_exit_hint'.tr(),
          _balanzaSalida,
          (b) => _onSeleccionada(b, _scaleSalidaKey, (v) => _balanzaSalida = v),
        ),
        const Divider(),
        _selector(
          'Báscula por defecto (global)',
          'default_scale_pick_full'.tr(),
          _balanzaDefault,
          (b) => _onSeleccionada(b, _scaleDefaultKey, (v) => _balanzaDefault = v),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Widgets reutilizables (los mismos que ya tenías)
// ═══════════════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: SwsColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Tiles ya existentes (copiados del archivo original sin cambios)
// ═══════════════════════════════════════════════════════════════════════

class _AccountInfoTile extends StatelessWidget {
  const _AccountInfoTile();
  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const SizedBox(
        width: 24,
        height: 24,
        child: Icon(Icons.person_outlined),
      ),
      title: Text('profile'.tr()),
      subtitle: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          if (state is AuthAuthenticated) {
            return Text('${state.user.nombre} — ${state.user.email}');
          }
          return Text('not_authenticated'.tr());
        },
      ),
    );
  }
}

class _IdentidadTile extends StatefulWidget {
  const _IdentidadTile();
  @override
  State<_IdentidadTile> createState() => _IdentidadTileState();
}

class _IdentidadTileState extends State<_IdentidadTile> {
  Map<String, dynamic>? _identidad;
  bool _sinIdentidad = false;

  @override
  void initState() {
    super.initState();
    _cargar(refresh: true);
  }

  Future<void> _cargar({bool refresh = false}) async {
    try {
      final id = await di.sl<ApiClient>().getIdentity(refresh: refresh);
      if (!mounted) return;
      setState(() {
        _identidad = id;
        _sinIdentidad = id == null;
      });
    } catch (_) {
      if (mounted) setState(() => _sinIdentidad = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _identidad;
    final String sub;
    if (id == null) {
      sub = _sinIdentidad
          ? 'Sin configurar — se registra en el primer login'
          : 'Cargando...';
    } else {
      sub = '${id['nombre_comercial'] ?? id['nombre_fiscal'] ?? '---'}'
          ' · ${id['licencia_tier'] ?? '---'}'
          '${id['modo_offline'] == true ? ' · sin conexión' : ''}';
    }
    return ListTile(
      dense: true,
      leading: const SizedBox(
        width: 24,
        height: 24,
        child: Icon(Icons.account_balance_outlined),
      ),
      title: Text('station_identity'.tr()),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      trailing: IconButton(
        icon: const Icon(Icons.refresh, size: 20),
        tooltip: 'Recargar',
        onPressed: () => _cargar(refresh: true),
      ),
    );
  }
}

class _UsuariosTile extends StatelessWidget {
  const _UsuariosTile();
  @override
  Widget build(BuildContext context) {
    final rol = context.select<AuthBloc, String?>((bloc) {
      final state = bloc.state;
      return state is AuthAuthenticated ? state.user.rol : null;
    });
    final esAdmin = rol == 'ADMIN';
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 24,
        height: 24,
        child: Icon(esAdmin ? Icons.group_outlined : Icons.lock_outline),
      ),
      title: Text('users_and_roles_hint'.tr()),
      subtitle: Text(
        esAdmin
            ? 'Crear, editar y desactivar operadores'
            : 'Solo visible para administradores',
      ),
      enabled: esAdmin,
      trailing: esAdmin ? const Icon(Icons.chevron_right) : null,
      onTap: esAdmin
          ? () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UsuariosScreen()),
              )
          : null,
    );
  }
}

class _LicenseTile extends StatelessWidget {
  const _LicenseTile();
  @override
  Widget build(BuildContext context) {
    final rol = context.select<AuthBloc, String?>((bloc) {
      final state = bloc.state;
      return state is AuthAuthenticated ? state.user.rol : null;
    });
    final esAdmin = rol == 'ADMIN';
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 24,
        height: 24,
        child: Icon(
          esAdmin ? Icons.card_membership_outlined : Icons.lock_outline,
        ),
      ),
      title: Text('license_admin'.tr()),
      subtitle: Text(
        esAdmin
            ? 'Tier, vencimiento y renovación'
            : 'Solo visible para administradores',
      ),
      enabled: esAdmin,
      trailing: esAdmin ? const Icon(Icons.chevron_right) : null,
      onTap: esAdmin
          ? () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LicenseAdminScreen()),
              )
          : null,
    );
  }
}

class _WServerPanel extends StatefulWidget {
  const _WServerPanel();
  @override
  State<_WServerPanel> createState() => _WServerPanelState();
}

class _WServerPanelState extends State<_WServerPanel> {
  bool? _online;
  bool _trabajando = false;
  bool _autostart = false;

  @override
  void initState() {
    super.initState();
    WServerManager.autostartActivo().then((v) {
      if (mounted) setState(() => _autostart = v);
    });
    _checarEstado();
  }

  Future<void> _checarEstado() async {
    setState(() => _trabajando = true);
    final online = await WServerManager.isOnline();
    if (!mounted) return;
    setState(() {
      _online = online;
      _trabajando = false;
    });
  }

  Future<void> _encender() async {
    setState(() => _trabajando = true);
    try {
      await WServerManager.ensureRunning();
    } catch (e) {
      if (!mounted) return;
      setState(() => _trabajando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo iniciar el WServer: $e'),
          backgroundColor: SwsColors.danger,
        ),
      );
      return;
    }
    await _checarEstado();
  }

  Future<void> _apagar() async {
    setState(() => _trabajando = true);
    await WServerManager.detener();
    await _checarEstado();
  }

  Future<void> _toggleAutostart(bool value) async {
    setState(() => _trabajando = true);
    final ok = await WServerManager.setAutostart(value);
    await AppConfig.setWServerAutostart(value);
    if (!mounted) return;
    setState(() {
      _trabajando = false;
      _autostart = ok && value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final base = AppConfig.apiBaseUrl?.trim().isNotEmpty == true
        ? AppConfig.apiBaseUrl!
        : AppConfig.defaultApiBaseUrl;
    final online = _online;

    final estadoColor = _trabajando
        ? SwsColors.warning
        : (online == true
            ? SwsColors.success
            : (online == false ? SwsColors.danger : SwsColors.gray500));

    final estadoTexto = _trabajando
        ? 'Verificando...'
        : (online == true
            ? 'Activo · $base'
            : (online == false
                ? 'Apagado · no responde en $base'
                : 'Comprobando conexión...'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.circle, size: 12, color: estadoColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  estadoTexto,
                  style: const TextStyle(fontSize: 12.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Comprobar de nuevo',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _checarEstado,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              if (online != true)
                FilledButton.icon(
                  onPressed: _trabajando ? null : _encender,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text('turn_on'.tr()),
                )
              else
                OutlinedButton.icon(
                  onPressed: _trabajando ? null : _apagar,
                  icon: const Icon(Icons.stop, size: 18),
                  label: Text('turn_off'.tr()),
                ),
            ],
          ),
        ),
        const Divider(height: 16),
        SwitchListTile(
          dense: true,
          secondary: const Icon(Icons.power_settings_new_outlined),
          title: Text('start_with_computer'.tr()),
          subtitle: Text(
            'autostart_desc'.tr(),
            style: const TextStyle(fontSize: 11.5),
          ),
          value: _autostart,
          onChanged: _trabajando ? null : _toggleAutostart,
        ),
      ],
    );
  }
}

class _ConexionesTile extends StatelessWidget {
  const _ConexionesTile();
  @override
  Widget build(BuildContext context) {
    final local = AppConfig.apiBaseUrl;
    final localPendiente = local == null || local.trim().isEmpty;
    return ListTile(
      dense: true,
      leading: const SizedBox(
        width: 24,
        height: 24,
        child: Icon(Icons.settings_ethernet),
      ),
      title: Text('local_connection'.tr()),
      subtitle: Text(
        'local_connection_desc'.tr(),
        style: const TextStyle(fontSize: 12),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: localPendiente
          ? const Icon(Icons.error_outline, color: SwsColors.warning)
          : const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ConnectionsScreen()),
      ),
    );
  }
}

class _DiagnosticoTile extends StatelessWidget {
  const _DiagnosticoTile();
  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const SizedBox(
        width: 24,
        height: 24,
        child: Icon(Icons.monitor_heart_outlined),
      ),
      title: Text('system_diagnostics'.tr()),
      subtitle: Text(
        'system_diagnostics_desc'.tr(),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SystemDiagnosticsScreen()),
      ),
    );
  }
}

class _DirectorioTile extends StatefulWidget {
  const _DirectorioTile();
  @override
  State<_DirectorioTile> createState() => _DirectorioTileState();
}

class _DirectorioTileState extends State<_DirectorioTile> {
  String? _ruta;
  bool _esPersonalizada = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final perfil = await di.sl<ApiClient>().getEmpresaPerfil();
      final personalizada = perfil['ruta_exportacion_reportes'] as String?;
      if (personalizada != null && personalizada.trim().isNotEmpty) {
        final rutaTrim = personalizada.trim();
        await SaveFileUtils.setRutaPersonalizada(rutaTrim);
        if (mounted) {
          setState(() {
            _ruta = rutaTrim;
            _esPersonalizada = true;
          });
        }
        return;
      }
    } catch (_) {}

    final base = await di.sl<LocalStorage>().getDescargasDir();
    if (mounted) {
      setState(() {
        _ruta = base;
        _esPersonalizada = false;
      });
    }
  }

  Future<void> _copiar() async {
    final ruta = _ruta;
    if (ruta == null) return;
    await Clipboard.setData(ClipboardData(text: ruta));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('path_copied'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final esAdmin = authState is AuthAuthenticated && authState.user.isAdmin;

    return ListTile(
      dense: true,
      leading: const SizedBox(
        width: 24,
        height: 24,
        child: Icon(Icons.folder_open_outlined),
      ),
      title: Text(
        _esPersonalizada
            ? 'Carpeta de reportes (Cuenta)'
            : 'Carpeta de reportes (Predeterminada)',
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _ruta ?? 'Obteniendo...',
            style: const TextStyle(fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (_esPersonalizada)
            Text(
              'set_by_admin'.tr(),
              style: TextStyle(
                  fontSize: 10.5,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.copy, size: 20),
        onPressed: _copiar,
        tooltip: 'Copiar ruta',
      ),
      onTap: esAdmin ? _copiar : _copiar,
    );
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
              dense: true,
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

class _LanguageSelector extends StatelessWidget {
  final LocaleController localeController;
  const _LanguageSelector({required this.localeController});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: localeController,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.language_outlined,
                    size: 18, color: SwsColors.accent),
                const SizedBox(width: 8),
                Text(
                  AppTranslations.of(
                      context, 'language_title', localeController),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
          RadioGroup<AppLanguage>(
            groupValue: localeController.language,
            onChanged: (v) {
              if (v != null) localeController.setLanguage(v);
            },
            child: Column(
              children: AppLanguage.values.map((lang) {
                return RadioListTile<AppLanguage>(
                  title: Text(_label(lang)),
                  value: lang,
                  dense: true,
                  activeColor: SwsColors.accent,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _label(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.system:
        return 'language_system'.tr();
      case AppLanguage.es:
        return 'language_es'.tr();
      case AppLanguage.en:
        return 'language_en'.tr();
      case AppLanguage.pt:
        return 'language_pt'.tr();
    }
  }
}