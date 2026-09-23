import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/security/device_info.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/mensaje_error.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../providers/bloc/license/license_bloc.dart';
import '../../../injection.dart' as di;

/// Administración de licencias (ADMIN): tier, vencimiento, uso y renovación.
class LicenseAdminScreen extends StatefulWidget {
  const LicenseAdminScreen({super.key});

  @override
  State<LicenseAdminScreen> createState() => _LicenseAdminScreenState();
}

class _LicenseAdminScreenState extends State<LicenseAdminScreen> {
  Map<String, dynamic>? _snapshot;
  bool _cargando = true;
  bool _renovando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarSnapshot();
  }

  Future<void> _cargarSnapshot() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data = await di.sl<ApiClient>().getLicenseSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo consultar la licencia: ${mensajeDeError(e)}';
      });
    }
  }

  Future<void> _renovar() async {
    setState(() => _renovando = true);
    try {
      final hwInfo = await DeviceInfo.getHardwareInfo();
      final keyCandidate = _snapshot?['licencia_key_masked'] as String?;
      final bool esMascara = keyCandidate == null ||
          keyCandidate.contains('...') ||
          keyCandidate.contains('•');
      await di.sl<ApiClient>().validateLicense({
        if (!esMascara) 'licencia_key': keyCandidate,
        'hardware_id': hwInfo.hardwareId,
        'mac_address': hwInfo.macAddress,
        'device_brand': hwInfo.brand,
        'device_model': hwInfo.model,
        'os_version': hwInfo.osVersion,
      });
      if (mounted) await _cargarSnapshot();
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Renovación fallida: ${mensajeDeError(e, fallback: 'No se pudo validar la licencia con el servidor.')}');
      }
    } finally {
      if (mounted) setState(() => _renovando = false);
    }
  }

  String _fmtFecha(String? iso) {
    if (iso == null) return 'Sin vencimiento';
    final d = DateTime.tryParse(iso);
    if (d == null) return 'Sin vencimiento';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// "Válida hasta el 22 sep 2027 (398 días restantes)".
  String _fmtVigencia(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return 'Sin vencimiento';
    final dias = d.difference(DateTime.now().toUtc()).inDays;
    if (dias < 0) return 'Vencida el ${_fmtFecha(iso)}';
    final meses = const [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return 'Válida hasta el ${d.day} ${meses[d.month - 1]} ${d.year} '
        '($dias ${dias == 1 ? 'día' : 'días'} restantes)';
  }

  String _limite(num? v) => v == null ? 'Ilimitado' : v.toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administración de Licencias')),
      body: RefreshIndicator(
        onRefresh: _cargarSnapshot,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SwsColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: SwsColors.danger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: SwsColors.danger, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_cargando && _snapshot == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_snapshot != null)
              _snapshotTile(context)
            else
              const _SinDatos(),
            const SizedBox(height: 12),
            BlocBuilder<LicenseBloc, LicenseState>(
              builder: (context, state) => _cacheCard(context, state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _snapshotTile(BuildContext context) {
    final s = _snapshot!;
    final tier = (s['tier'] as String?) ?? '—';
    final status = (s['status'] as String?) ?? '—';
    final valid = s['valid'] == true;
    final actuales = (s['registros_actuales'] as num?)?.toInt() ?? 0;
    final features = (s['features'] as Map<String, dynamic>?) ?? const {};
    final maxReg = features['max_registros'] as num?;
    final maxRegInt = maxReg?.toInt();
    final maxEquipos = _limite(features['max_equipos'] as num?);
    final maxUsuarios = _limite(features['max_usuarios'] as num?);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  valid ? Icons.verified_user : Icons.error_outline,
                  color: valid ? SwsColors.success : SwsColors.danger,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tier: $tier',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 18)),
                      Text(
                        status,
                        style: TextStyle(
                            color: valid
                                ? SwsColors.success
                                : SwsColors.danger,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _InfoRow('Vigencia', _fmtVigencia(s['expires_at'] as String?)),
            _InfoRow('Clave', (s['licencia_key_masked'] as String?) ?? '—'),
            _InfoRow('Máx. equipos', maxEquipos),
            _InfoRow('Máx. usuarios', maxUsuarios),
            const SizedBox(height: 8),
            if (maxRegInt != null) ...[
              LinearProgressIndicator(
                value: maxRegInt > 0 ? actuales / maxRegInt : 0,
                backgroundColor: SwsColors.gray200,
                color: SwsColors.primary,
              ),
              const SizedBox(height: 6),
              Text('$actuales / $maxRegInt registros (DEMO)',
                  style: const TextStyle(fontSize: 12)),
            ] else
              Text('Registros ilimitados (CENTRAL) · $actuales usados',
                  style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _renovando ? null : _renovar,
              icon: _renovando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('Renovar / Verificar licencia'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cacheCard(BuildContext context, LicenseState state) {
    final icono = state is LicenseValid
        ? (state.license.isValidAndActive
            ? Icons.check_circle_outline
            : Icons.warning_amber_outlined)
        : Icons.cloud_off_outlined;
    final color = state is LicenseValid
        ? (state.license.isValidAndActive
            ? SwsColors.success
            : SwsColors.warning)
        : SwsColors.gray400;
    final subtitulo = state is LicenseValid
        ? 'Tier ${state.license.tier ?? '—'} · ${state.license.status ?? '—'}'
        : 'Sin licencia cacheada localmente';

    return Card(
      child: ListTile(
        leading: Icon(icono, color: color),
        title: const Text('Caché local'),
        subtitle: Text(subtitulo, style: const TextStyle(fontSize: 12)),
        trailing: IconButton(
          tooltip: 'Limpiar caché',
          icon: const Icon(Icons.delete_outline),
          onPressed: () =>
              context.read<LicenseBloc>().add(ClearLicenseCacheEvent()),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: SwsColors.gray500, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

class _SinDatos extends StatelessWidget {
  const _SinDatos();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text('Sin información de licencia disponible'),
        ),
      ),
    );
  }
}