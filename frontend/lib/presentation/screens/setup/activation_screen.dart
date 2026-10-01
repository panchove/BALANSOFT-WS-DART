import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/services/wserver_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/activacion_repository.dart';
import '../../providers/bloc/auth/auth_bloc.dart';
import 'setup_layout_wrapper.dart';

/// Paso 3 de la instalación en modo SERVIDOR.
///
/// El proveedor entrega el correo y la contraseña de la cuenta; aquí se
/// validan contra el servidor central, lo que además **verifica la licencia**
/// en esta máquina: si ya está activada en otro equipo titular, el central
/// responde 403 y la instalación no continúa como servidor.
class ActivationScreen extends StatefulWidget {
  final ActivacionRepository repository;

  const ActivationScreen({super.key, required this.repository});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _enviando = false;
  bool _verOculta = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _activar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _enviando = true;
      _error = null;
    });

    // La API de la estación puede haberse caído (el WServer es hijo de la app:
    // si se cerró la app, se quedó sin backend). En modo servidor se intenta
    // relanzar antes de culpar al servidor central.
    if (AppConfig.esServidor && !await WServerManager.isOnline()) {
      try {
        await WServerManager.ensureRunning();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _enviando = false;
          _error = 'La API de esta máquina no está disponible: $e';
        });
        return;
      }
    }

    final resultado = await widget.repository.activar(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );

    if (!mounted) return;
    if (!resultado.exito) {
      setState(() {
        _enviando = false;
        _error = resultado.error;
      });
      return;
    }

    // La sesión quedó abierta: se recarga el estado de autenticación (que
    // restaura la sesión recién guardada) y se va directo a completar los
    // datos de la empresa, precargados con los del servidor central.
    context.read<AuthBloc>().add(const CheckAuthStatusEvent());
    Navigator.of(context).pushReplacementNamed('/company_setup');
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
            child: Icon(
              Icons.verified_user_outlined,
              size: 44,
              color: SwsColors.accentLight,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'activation_title'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: SwsColors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'activation_subtitle'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: SwsColors.white.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('activacion_email_field'),
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  style: const TextStyle(color: SwsColors.white),
                  decoration: InputDecoration(
                    labelText: 'activation_email'.tr(),
                    hintText: 'admin@empresa.com',
                    prefixIcon: const Icon(Icons.mail_outline),
                    errorStyle: const TextStyle(color: SwsColors.danger),
                  ),
                  validator: (v) {
                    final valor = v?.trim() ?? '';
                    if (valor.isEmpty) return 'activation_required'.tr();
                    if (!valor.contains('@') || !valor.contains('.')) {
                      return 'activation_email_invalid'.tr();
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('activacion_password_field'),
                  controller: _passCtrl,
                  obscureText: _verOculta,
                  style: const TextStyle(color: SwsColors.white),
                  decoration: InputDecoration(
                    labelText: 'activation_password'.tr(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    errorStyle: const TextStyle(color: SwsColors.danger),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _verOculta ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white54,
                      ),
                      onPressed: () => setState(() => _verOculta = !_verOculta),
                      tooltip: 'btn_show_password'.tr(),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'activation_required'.tr()
                      : null,
                  onFieldSubmitted: (_) => _activar(),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
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
                  const Icon(
                    Icons.error_outline,
                    color: SwsColors.danger,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: SwsColors.danger,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              key: const Key('activacion_enviar_btn'),
              onPressed: _enviando ? null : _activar,
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_rounded),
              label: Text('activation_submit'.tr()),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'activation_help'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: SwsColors.white.withValues(alpha: 0.5),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
