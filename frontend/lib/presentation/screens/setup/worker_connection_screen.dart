import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../providers/bloc/auth/auth_bloc.dart';
import 'setup_layout_wrapper.dart';

/// Instalación en modo TRABAJADOR LOCAL.
///
/// La máquina es un cliente delgado: no levanta WServer ni PostgreSQL, solo
/// apunta a la API de la estación que es titular de la cuenta. Aquí se coloca
/// la URL o IP de esa máquina y su puerto, se verifica la conexión y se pasa al
/// login con las credenciales que asignó el administrador de la cuenta.
class WorkerConnectionScreen extends StatefulWidget {
  final ApiClient Function(String baseUrl) clientFactory;

  const WorkerConnectionScreen({super.key, required this.clientFactory});

  @override
  State<WorkerConnectionScreen> createState() => _WorkerConnectionScreenState();
}

class _WorkerConnectionScreenState extends State<WorkerConnectionScreen> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _puertoCtrl;

  bool _verificando = false;
  bool _ok = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final base = AppConfig.apiBaseUrl ?? '';
    _hostCtrl = TextEditingController(text: _hostDe(base));
    _puertoCtrl = TextEditingController(text: _puertoDe(base));
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _puertoCtrl.dispose();
    super.dispose();
  }

  /// Separa `http://192.168.1.10:8000` en host y puerto para precargar los
  /// campos cuando el instalador vuelve atrás a corregirlos.
  static String _hostDe(String url) {
    var u = url.trim();
    if (u.isEmpty) return '';
    u = u.replaceFirst(RegExp(r'^https?://'), '');
    u = u.split('/').first;
    final partes = u.split(':');
    return partes.first;
  }

  static String _puertoDe(String url) {
    var u = url.trim().replaceFirst(RegExp(r'^https?://'), '').split('/').first;
    final partes = u.split(':');
    return partes.length > 1 ? partes[1] : '8000';
  }

  /// URL final: `http://<host>:<puerto>`. Si el instalador escribe la URL
  /// completa con esquema, se respeta tal cual.
  String get _url {
    final host = _hostCtrl.text.trim().replaceAll(RegExp(r'^https?://'), '');
    final limpio = host.split('/').first;
    if (limpio.isEmpty) return '';
    if (limpio.contains(':')) return 'http://$limpio';
    return 'http://$limpio:${_puertoCtrl.text.trim()}';
  }

  Future<void> _verificar() async {
    final url = _url;
    if (url.isEmpty) {
      setState(() => _error = 'worker_host_required'.tr());
      return;
    }
    final puerto = int.tryParse(_puertoCtrl.text.trim());
    if (puerto == null || puerto <= 0 || puerto > 65535) {
      setState(() => _error = 'worker_port_invalid'.tr());
      return;
    }

    setState(() {
      _verificando = true;
      _error = null;
      _ok = false;
    });

    bool ok = false;
    try {
      ok = await widget.clientFactory(url).health();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _verificando = false;
      _ok = ok;
      _error = ok ? null : 'worker_unreachable'.tr();
    });
  }

  Future<void> _continuar() async {
    final url = _url;
    await AppConfig.setApiBaseUrl(url);
    context.read<AuthBloc>().add(const CheckAuthStatusEvent());
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: SetupLayoutWrapper(
        onBack: () =>
            Navigator.of(context).pushReplacementNamed('/mode_selection'),
        children: [
          const Center(
            child: Icon(Icons.lan_outlined,
                size: 44, color: SwsColors.accentLight),
          ),
          const SizedBox(height: 20),
          Text(
            'worker_title'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: SwsColors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'worker_subtitle'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: SwsColors.white.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _hostCtrl,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(color: SwsColors.white),
                  decoration: InputDecoration(
                    labelText: 'worker_host'.tr(),
                    hintText: '192.168.1.10',
                    prefixIcon: const Icon(Icons.dns_outlined),
                    errorStyle: const TextStyle(color: SwsColors.danger),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _puertoCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: SwsColors.white),
                  decoration: InputDecoration(
                    labelText: 'worker_port'.tr(),
                    hintText: '8000',
                    errorStyle: const TextStyle(color: SwsColors.danger),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'worker_no_local_db'.tr(),
            style: TextStyle(
              fontSize: 12,
              color: SwsColors.white.withValues(alpha: 0.5),
              height: 1.4,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SwsColors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: SwsColors.danger.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: SwsColors.danger, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                          color: SwsColors.danger, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_ok) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: SwsColors.success, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'worker_connection_ok'.tr(),
                    style:
                        const TextStyle(color: SwsColors.success, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _verificando ? null : _verificar,
              icon: _verificando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: Text('worker_verify'.tr()),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _ok && !_verificando ? _continuar : null,
              icon: const Icon(Icons.login_rounded),
              label: Text('worker_go_login'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}
