import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/services/wserver_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/brand_text.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/auth/auth_bloc.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  // URL de proveedores oficiales del producto.
  static const String _proveedoresUrl = 'http://www.balansoft.com.ve/#proveedores';

  @override
  void initState() {
    super.initState();
    // El trabajador es cliente delgado: su API vive en la estación titular, así
    // que no debe levantar un WServer propio (docs/MANEJO_DB.md §13).
    if (AppConfig.esTrabajador) return;
    // Si ya hay una conexión local configurada, asegura que el WServer esté
    // levantado antes de intentar el login (p. ej. tras un reinicio del
    // equipo sin autostart activo). Best-effort: no bloquea la pantalla.
    if (AppConfig.localApiConfigured) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WServerManager.ensureRunning().catchError((_) => false);
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submitLogin() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<AuthBloc>().add(LoginEvent(
          email: _email.text.trim(),
          password: _password.text,
        ));
  }

  /// Abre el enlace de proveedores oficiales en el navegador externo.
  Future<void> _abrirProveedores() async {
    final uri = Uri.parse(_proveedoresUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('No se pudo abrir el enlace de proveedores')),
          backgroundColor: SwsColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: SwsColors.gradientEnd,
        body: BlocListener<AuthBloc, AuthState>(
          listener: (context, state) {
            if (state is AuthError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: SwsColors.danger,
                ),
              );
            } else if (state is AuthAuthenticated) {
              Navigator.pushReplacementNamed(context, '/dashboard');
            }
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              // Breakpoints:
              //   >= 900  → Desktop:  Row con imagen lateral + formulario
              //   >= 600  → Tablet:   banner superior + formulario debajo
              //   <  600  → Móvil:    formulario a pantalla completa (imagen como fondo tenue)
              if (w >= 900) return _buildDesktopLayout();
              if (w >= 600) return _buildTabletLayout();
              return _buildMobileLayout();
            },
          ),
        ),
      ),
    );
  }

  // ─── Desktop (>= 900) ──────────────────────────────────────────────────
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: SizedBox.expand(
            child: Image.asset(
              'assets/images/BLSWS-LOGO-LOGIN.jpeg',
              fit: BoxFit.cover,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandText(size: 64, withTagline: true),
                    const SizedBox(height: 36),
                    _buildLoginForm(),
                    const SizedBox(height: 24),
                    Text(
                      'works_offline'.tr(),
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    _buildProveedoresLink(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Tablet (600 <= w < 900) ───────────────────────────────────────────
  Widget _buildTabletLayout() {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Banner superior con la marca
                const BrandText(size: 48, withTagline: true),
                const SizedBox(height: 24),

                // Formulario en Card para separarlo del fondo
                Card(
                  elevation: 0,
                  color: Colors.white.withValues(alpha: 0.04),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 24),
                    child: _buildLoginForm(),
                  ),
                ),

                const SizedBox(height: 24),
                Text(
                  'works_offline'.tr(),
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 8),
                _buildProveedoresLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Móvil (< 600) ─────────────────────────────────────────────────────
  Widget _buildMobileLayout() {
    return SafeArea(
      child: Stack(
        children: [
          // Fondo con la imagen, muy tenue, para no perder la marca sin robar espacio.
          Positioned.fill(
            child: Opacity(
              opacity: 0.12,
              child: Image.asset(
                'assets/images/BLSWS-LOGO-LOGIN.jpeg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandText(size: 40, withTagline: true),
                    const SizedBox(height: 24),
                    Card(
                      elevation: 0,
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 22),
                        child: _buildLoginForm(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'works_offline'.tr(),
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    _buildProveedoresLink(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Enlace a proveedores oficiales ────────────────────────────────────
  Widget _buildProveedoresLink() {
    return TextButton.icon(
      onPressed: _abrirProveedores,
      style: TextButton.styleFrom(
        foregroundColor: SwsColors.accent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.storefront_outlined, size: 14),
      label: Text(
        context.tr('Proveedores oficiales'),
        style: const TextStyle(
          fontSize: 12,
          decoration: TextDecoration.underline,
          decorationColor: SwsColors.accent,
        ),
      ),
    );
  }

  // ─── Formulario (compartido por los 3 layouts) ─────────────────────────
  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildLanguageSelector(context),
            ],
          ),
          Text(
            context.tr('Iniciar Sesión'),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('Accede a tu estación de pesaje'),
            style: const TextStyle(color: Colors.white60, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // Campo Email
          TextFormField(
            key: const Key('email_field'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: Validators.email,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              labelText: context.tr('Correo Electrónico'),
              labelStyle: const TextStyle(color: Colors.white60),
              prefixIcon: const Icon(Icons.mail_outline, color: Colors.white60),
              enabledBorder: const UnderlineInputBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                borderSide: BorderSide(color: Colors.white30, width: 1.5),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                borderSide: BorderSide(color: SwsColors.accent, width: 2.0),
              ),
              border: const UnderlineInputBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Campo Contraseña
          TextFormField(
            key: const Key('password_field'),
            controller: _password,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitLogin(),
            validator: Validators.password,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              labelText: context.tr('Contraseña'),
              labelStyle: const TextStyle(color: Colors.white60),
              prefixIcon: const Icon(Icons.lock_outline, color: Colors.white60),
              enabledBorder: const UnderlineInputBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                borderSide: BorderSide(color: Colors.white30, width: 1.5),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                borderSide: BorderSide(color: SwsColors.accent, width: 2.0),
              ),
              border: const UnderlineInputBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white60,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // `Flexible`: con etiquetas largas los dos botones sumaban más
              // que el ancho de la tarjeta y el Row se desbordaba.
              Flexible(
                child: TextButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/connections'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                  ),
                  icon: const Icon(Icons.wifi_tethering, size: 15),
                  label: Text(
                    context.tr('Conexión local'),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Flexible(
                child: TextButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/forgot-password'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                  ),
                  child: Text(
                    context.tr('¿Olvidaste tu contraseña?'),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Botón Iniciar Sesión
          BlocBuilder<AuthBloc, AuthState>(
            builder: (context, state) {
              final loading = state is AuthLoading;
              return SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('login_button'),
                  onPressed: loading ? null : _submitLogin,
                  style: FilledButton.styleFrom(
                    backgroundColor: SwsColors.accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (loading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      else
                        const Icon(Icons.login),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          loading
                              ? context.tr('loading')
                              : context.tr('Iniciar Sesión'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector(BuildContext context) {
    if (!di.sl.isRegistered<LocaleController>()) return const SizedBox.shrink();
    final localeCtrl = di.sl<LocaleController>();
    // El código de idioma va FUERA del botón: dentro de `PopupMenuButton.icon`
    // el `Row` recibía el ancho mínimo del botón y se desbordaba (RenderFlex
    // overflow de 6-10 px, detectado por el E2E de Flutter).
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Icon(Icons.language, size: 16, color: Colors.white70),
        const SizedBox(width: 4),
        Text(
          localeCtrl.activeLanguageCode.toUpperCase(),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        PopupMenuButton<AppLanguage>(
          tooltip: context.tr('Idioma del Sistema'),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.arrow_drop_down,
              size: 18, color: Colors.white70),
          onSelected: (lang) => localeCtrl.setLanguage(lang),
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: AppLanguage.system,
              child: Text(
                  context.tr('Detectar idioma del dispositivo (automático)')),
            ),
            const PopupMenuItem(
              value: AppLanguage.es,
              child: Text('Español (ES)'),
            ),
            const PopupMenuItem(
              value: AppLanguage.en,
              child: Text('English (EN)'),
            ),
            const PopupMenuItem(
              value: AppLanguage.pt,
              child: Text('Português (PT)'),
            ),
          ],
        ),
      ],
    );
  }
}