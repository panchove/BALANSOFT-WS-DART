import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/api_constants.dart';
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
import '../../../core/utils/save_file_utils.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeController themeController;
  const SettingsScreen({super.key, required this.themeController});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _scaleDefaultKey = 'scale_default_id';

  List<Scale> _balanzas = const [];
  Scale? _balanzaDefault;
  bool _cargandoBalanzas = true;

  @override
  void initState() {
    super.initState();
    _loadBalanzas();
  }

  Future<void> _loadBalanzas() async {
    setState(() => _cargandoBalanzas = true);
    try {
      final resp = await di.sl<ApiClient>().getList(ApiConstants.balanzas);
      final filas = (resp.data as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Scale.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _balanzas = filas;
        final prevId = AppConfig.prefs.getString(_scaleDefaultKey);
        if (prevId != null && prevId.isNotEmpty) {
          final coincidencias = filas.where((b) => b.id == prevId);
          _balanzaDefault =
              coincidencias.isNotEmpty ? coincidencias.first : null;
        } else {
          _balanzaDefault = null;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _balanzas = const []);
    } finally {
      if (mounted) setState(() => _cargandoBalanzas = false);
    }
  }

  /// Al cambiar la báscula por defecto: persiste el id y refresca el
  /// `ScaleApiClient` con los datos de hardware de esa báscula.
  Future<void> _onBalanzaSeleccionada(Scale? b) async {
    setState(() => _balanzaDefault = b);
    if (b == null) {
      await AppConfig.prefs.remove(_scaleDefaultKey);
      return;
    }
    await AppConfig.prefs.setString(_scaleDefaultKey, b.id);
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadBalanzas();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadBalanzas();
          if (mounted) setState(() {});
        },
        child: isWide ? _buildWideLayout(context) : _buildCompactLayout(context),
      ),
    );
  }

  // ── Layouts ─────────────────────────────────────────────────────────────

  Widget _buildCompactLayout(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        const _AccountHeader(),
        const SizedBox(height: 8),
        ..._sections(context),
      ],
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    // Columna izquierda: identidad / cuenta / licencia / apariencia.
    // Columna derecha: configuración operativa.
    final izquierda = <Widget>[
      const _SectionCard(
        icon: Icons.account_balance_outlined,
        title: 'Cuenta y Empresa',
        children: [
          _AccountInfoTile(),
          _IdentidadTile(),
          _UsuariosTile(),
        ],
      ),
      const _SectionCard(
        icon: Icons.card_membership_outlined,
        title: 'Licencia',
        children: [_LicenseTile()],
      ),
      _SectionCard(
        icon: Icons.palette_outlined,
        title: 'Apariencia',
        children: [
          _ThemeSelector(themeController: widget.themeController),
        ],
      ),
    ];
    final derecha = <Widget>[
      _SectionCard(
        icon: Icons.straighten_outlined,
        title: 'Báscula del Sistema',
        children: [_buildBalanzasSelector()],
      ),
const _SectionCard(
        icon: Icons.wifi_tethering_outlined,
        title: 'Conexiones',
        children: [_ConexionesTile()],
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
      _cierreSesion(context),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AccountHeader(),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(children: izquierda)),
              const SizedBox(width: 16),
              Expanded(child: Column(children: derecha)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Secciones (móvil) ───────────────────────────────────────────────────

  List<Widget> _sections(BuildContext context) {
    return [
      const _SectionCard(
        icon: Icons.account_balance_outlined,
        title: 'Cuenta y Empresa',
        children: [
          _AccountInfoTile(),
          _IdentidadTile(),
          _UsuariosTile(),
        ],
      ),
      const _SectionCard(
        icon: Icons.card_membership_outlined,
        title: 'Licencia',
        children: [_LicenseTile()],
      ),
      _SectionCard(
        icon: Icons.straighten_outlined,
        title: 'Báscula del Sistema',
        children: [_buildBalanzasSelector()],
      ),
      const _SectionCard(
        icon: Icons.wifi_tethering_outlined,
        title: 'Conexiones',
        children: [_ConexionesTile()],
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
      _SectionCard(
        icon: Icons.palette_outlined,
        title: 'Apariencia',
        children: [
          _ThemeSelector(themeController: widget.themeController),
        ],
      ),
      const SizedBox(height: 8),
      _cierreSesion(context),
    ];
  }

  List<Widget> _syncChildren(BuildContext context) {
    return [
      SwitchListTile(
        secondary: const Icon(Icons.sync_outlined),
        title: const Text('Sincronización automática'),
        subtitle: const Text('Cada 5 minutos'),
        value: true,
        dense: true,
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
    ];
  }

  // ── Báscula por defecto (solo select) ───────────────────────────────────

  Widget _buildBalanzasSelector() {
    if (_cargandoBalanzas) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Selecciona la báscula que el sistema usará por defecto para '
            'todos los pesajes.',
            style: TextStyle(fontSize: 12.5, color: SwsColors.gray600),
          ),
        ),
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Báscula por defecto',
            prefixIcon: const Icon(Icons.scale_outlined),
            suffixIcon: IconButton(
              tooltip: 'Actualizar básculas',
              onPressed: _loadBalanzas,
              icon: const Icon(Icons.refresh),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Scale?>(
              value: _balanzaDefault,
              isExpanded: true,
              isDense: true,
              hint: const Text('— Sin seleccionar —'),
              items: _dropdownItems(),
              onChanged: _onBalanzaSeleccionada,
            ),
          ),
        ),
        if (_balanzas.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'No hay básculas registradas. Añádelas desde '
              'Dispositivos → Añadir báscula.',
              style: TextStyle(fontSize: 12, color: SwsColors.gray500),
            ),
          ),
      ],
    );
  }

  List<DropdownMenuItem<Scale?>> _dropdownItems() {
    if (_balanzas.isEmpty) {
      return const [
        DropdownMenuItem<Scale?>(
          value: null,
          enabled: false,
          child: Text('Sin básculas disponibles'),
        ),
      ];
    }
    return [
      const DropdownMenuItem<Scale?>(
        value: null,
        child: Text('— Sin seleccionar —'),
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
    ];
  }

  // ── Cierre de sesión ────────────────────────────────────────────────────

  Widget _cierreSesion(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: const Icon(Icons.logout, color: SwsColors.danger),
        title: const Text(
          'Cerrar Sesión',
          style: TextStyle(color: SwsColors.danger),
        ),
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
                    context.read<AuthBloc>().add(const LogoutEvent());
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                  child: const Text(
                    'Cerrar',
                    style: TextStyle(color: SwsColors.danger),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

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
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

class _AccountHeader extends StatefulWidget {
  const _AccountHeader();

  @override
  State<_AccountHeader> createState() => _AccountHeaderState();
}

class _AccountHeaderState extends State<_AccountHeader> {
  Map<String, dynamic>? _account;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await di.sl<ApiClient>().getAccountInfo();
      if (!mounted) return;
      setState(() {
        _account = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;
    final nombre = (_account?['nombre_comercial'] as String?)
        ?? (_account?['nombre_fiscal'] as String?)
        ?? 'Estación';
    final rif = _account?['rif_nit'] as String? ?? '---';

    return Card(
      margin: EdgeInsets.symmetric(horizontal: isWide ? 0 : 12, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              SwsColors.primary,
              SwsColors.primary.withValues(alpha: 0.85),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _loading && _account == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final apilado = constraints.maxWidth < 260;
                    if (apilado) {
                      return _headerApilado(nombre, rif);
                    }
                    return _headerFila(nombre, rif);
                  },
                ),
        ),
      ),
    );
  }

  Widget _headerApilado(String nombre, String rif) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white24,
              child: Icon(Icons.business, color: Colors.white, size: 26),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh, color: Colors.white70, size: 22),
              onPressed: _load,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _headerTextos(nombre, rif),
        const SizedBox(height: 12),
        _badges(),
        if (_error != null) _errorText(),
      ],
    );
  }

  Widget _headerFila(String nombre, String rif) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white24,
              child: Icon(Icons.business, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(child: _headerTextos(nombre, rif)),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh, color: Colors.white70, size: 22),
              onPressed: _load,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _badges(),
        if (_error != null) _errorText(),
      ],
    );
  }

  Widget _headerTextos(String nombre, String rif) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          nombre,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          'RIF: $rif',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _badges() {
    final tier = (_account?['licencia_tier'] as String?) ?? '---';
    final status = (_account?['licencia_status'] as String?) ?? '---';
    final valid = _account?['licencia_valida'] == true;
    final expires = _account?['licencia_expira'] as String?;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _BadgeChip(
          label: tier,
          icon: Icons.workspace_premium,
          color: Colors.amber,
          dark: true,
        ),
        _BadgeChip(
          label: status,
          icon: valid ? Icons.verified : Icons.error_outline,
          color: valid ? SwsColors.success : SwsColors.danger,
          dark: true,
        ),
        if (expires != null)
          _BadgeChip(
            label: _fmtDate(expires),
            icon: Icons.calendar_today,
            color: Colors.white70,
            dark: true,
          ),
      ],
    );
  }

  Widget _errorText() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        _error!,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }

  String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '---';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

class _BadgeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool dark;

  const _BadgeChip({
    required this.label,
    required this.icon,
    required this.color,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.15)
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: dark ? Colors.white : color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: dark ? Colors.white : color,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
      title: const Text('Perfil'),
      subtitle: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          if (state is AuthAuthenticated) {
            return Text('${state.user.nombre} — ${state.user.email}');
          }
          return const Text('No autenticado');
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
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final id = await di.sl<ApiClient>().getIdentity();
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
      title: const Text('Identidad de la estación'),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      trailing: IconButton(
        icon: const Icon(Icons.refresh, size: 20),
        tooltip: 'Recargar',
        onPressed: _cargar,
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
      title: const Text('Usuarios y roles'),
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
      title: const Text('Administración de licencias'),
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
      title: const Text('Servidores'),
      subtitle: Text(
        localPendiente
            ? 'API local sin configurar · Central: ${AppConfig.serverApiUrl}'
            : 'Local: $local · Central: ${AppConfig.serverApiUrl}',
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
        const SnackBar(content: Text('Ruta copiada al portapapeles')),
      );
    }
  }

  Future<void> _editarRuta(bool esAdmin) async {
    if (!esAdmin || _guardando) return;
    final ctrl = TextEditingController(text: _esPersonalizada ? _ruta : '');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ruta de exportación de reportes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esta carpeta se utilizará para almacenar las exportaciones de Excel, PDF y Kardex en todas las sesiones y estaciones de esta cuenta.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Ruta absoluta de la carpeta',
                hintText: 'Ej. /var/reportes o C:\\ReportesBalansoft',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.folder_open_outlined),
              ),
            ),
          ],
        ),
        actions: [
          if (_esPersonalizada)
            TextButton(
              onPressed: () {
                ctrl.text = '';
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Restablecer por defecto'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    final nuevaRuta = ctrl.text.trim();
    setState(() => _guardando = true);
    try {
      final valorAEnviar = nuevaRuta.isEmpty ? null : nuevaRuta;
      await di.sl<ApiClient>().updateEmpresaPerfil({
        'ruta_exportacion_reportes': valorAEnviar,
      });
      await SaveFileUtils.setRutaPersonalizada(valorAEnviar);
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            valorAEnviar != null
                ? 'Ruta de exportación actualizada para toda la cuenta'
                : 'Ruta de exportación restablecida a descargas predeterminadas',
          ),
          backgroundColor: SwsColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la ruta: $e'),
          backgroundColor: SwsColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
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
            const Text(
              'Configurada por el administrador para todas las sesiones',
              style: TextStyle(fontSize: 10.5, color: SwsColors.primary, fontWeight: FontWeight.w600),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (esAdmin)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _editarRuta(esAdmin),
              tooltip: 'Configurar ruta para toda la empresa',
            ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: _copiar,
            tooltip: 'Copiar ruta',
          ),
        ],
      ),
      onTap: esAdmin ? () => _editarRuta(esAdmin) : _copiar,
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