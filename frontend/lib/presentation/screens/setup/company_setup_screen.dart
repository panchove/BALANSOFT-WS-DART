import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/company_draft.dart';
import '../../../core/config/cuenta_activada.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/save_file_utils.dart';
import '../../../core/widgets/company_setup_form.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;
import 'setup_layout_wrapper.dart';

/// Paso 4 de la instalación en modo SERVIDOR: datos de la empresa.
///
/// Al llegar aquí la cuenta ya fue validada en el servidor central, así que el
/// formulario llega **precargado** con lo que el proveedor registró allí
/// (razón social, RIF, dirección, teléfono y correo). El operador solo completa
/// lo que falte: logo, formatos de exportación, carpeta de reportes e idioma.
///
/// Con la sesión abierta (validación de la cuenta) los datos se guardan
/// directo en la BD local con `PUT /api/v1/empresa` y el operador entra al
/// sistema sin volver a escribir su contraseña. Si por lo que sea no hay
/// sesión, se guarda el borrador y se aplica en el siguiente login
/// (docs/I18N_Y_ONBOARDING.md · REQ-NF-ONB-006).
class CompanySetupScreen extends StatefulWidget {
  final LocaleController localeController;

  const CompanySetupScreen({super.key, required this.localeController});

  @override
  State<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends State<CompanySetupScreen> {
  final GlobalKey<CompanySetupFormState> _formKey =
      GlobalKey<CompanySetupFormState>();

  CompanySetupData? _inicial;
  CuentaActivada? _cuenta;
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Prioriza los datos del servidor central y, si no hay cuenta activada,
  /// cae al borrador local (instalaciones en curso o reconexión).
  Future<void> _cargar() async {
    final cuenta = await CuentaActivada.leer();
    final draft = await CompanyDraft.leer();
    if (!mounted) return;
    setState(() {
      _cuenta = cuenta;
      _inicial = cuenta?.tieneDatos == true
          ? _desdeCuenta(cuenta!, draft?.data)
          : draft?.data;
      _cargando = false;
    });
  }

  /// Mezcla lo que vino del central con lo que el operador ya había escrito:
  /// los campos del central mandan (son la ficha de la cuenta), el resto
  /// conserva lo capturado.
  CompanySetupData _desdeCuenta(
    CuentaActivada cuenta,
    CompanySetupData? previo,
  ) {
    return CompanySetupData(
      nombreFiscal: cuenta.nombreFiscal,
      nombreComercial: cuenta.nombreComercial.isEmpty
          ? cuenta.nombreFiscal
          : cuenta.nombreComercial,
      rifNit: cuenta.rifNit,
      direccion: cuenta.direccion ?? previo?.direccion ?? '',
      telefono: cuenta.telefono ?? previo?.telefono ?? '',
      email: cuenta.email.isNotEmpty ? cuenta.email : previo?.email ?? '',
      idioma: previo?.idioma ?? widget.localeController.activeLanguageCode,
      formatoTicket: previo?.formatoTicket ?? 'PDF',
      formatoReporte: previo?.formatoReporte ?? 'EXCEL',
      rutaReportes: previo?.rutaReportes ?? '',
      logo: previo?.logo ?? const [],
      logoUrl: cuenta.logoUrl,
    );
  }

  Future<void> _guardar(CompanySetupData data) async {
    setState(() {
      _guardando = true;
      _error = null;
    });

    if (data.rutaReportes.trim().isNotEmpty) {
      await SaveFileUtils.setRutaPersonalizada(data.rutaReportes.trim());
    }

    // Con la cuenta ya validada hay token: se escribe directo en la BD local.
    if (AppConfig.licenciaVerificada) {
      try {
        final api = di.sl<ApiClient>();
        final body = data.toApiBody();
        final bytes = data.logo.isNotEmpty ? data.logo.first.bytes : null;
        if (bytes != null) {
          body['logo_url'] = await api.uploadPhotoFile(
            bytes,
            data.logo.first.nombre.isEmpty
                ? 'logo.png'
                : data.logo.first.nombre,
            carpeta: 'empresa',
          );
        }
        await api.updateEmpresaPerfil(body);
        await CompanyDraft.limpiar();
        await AppConfig.setEmpresaSetupCapturado();
        await AppConfig.setOnboardingCompletado();
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/dashboard');
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _guardando = false;
          _error = 'company_save_error'.tr();
        });
        return;
      }
    }

    // Sin sesión: se deja el borrador para aplicarlo en el login.
    await CompanyDraft.guardar(
      data,
      logoBytes: data.logo.isNotEmpty ? data.logo.first.bytes : null,
      logoNombre: data.logo.isNotEmpty ? data.logo.first.nombre : null,
    );
    await AppConfig.setEmpresaSetupCapturado();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    final desdeCentral = _cuenta?.tieneDatos == true;
    return SetupLayoutWrapper(
      // El formulario tiene `PageView` + `Expanded`: necesita alto acotado.
      fillHeight: true,
      children: [
        const Icon(
          Icons.storefront_outlined,
          size: 40,
          color: SwsColors.accentLight,
        ),
        const SizedBox(height: 14),
        Text(
          'setup_company_title'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: SwsColors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          desdeCentral
              ? 'setup_company_subtitle_central'.tr()
              : 'setup_company_subtitle'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: SwsColors.white.withValues(alpha: 0.60),
            height: 1.5,
          ),
        ),
        if (desdeCentral) ...[
          const SizedBox(height: 10),
          _PrefillBadge(cuenta: _cuenta!),
        ],
        if (_guardando) ...[
          const SizedBox(height: 10),
          const SizedBox(
            height: 14,
            width: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SwsColors.danger, fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : CompanySetupForm(
                  key: _formKey,
                  localeController: widget.localeController,
                  initial: _inicial,
                  initialLock: desdeCentral,
                  finalLabelKey: 'setup_company_finish',
                  onSubmit: _guardar,
                  mostrarOmitir: !AppConfig.licenciaVerificada,
                  onOmitir: () {
                    // Omitir deja el borrador pendiente: el wizard post-login
                    // lo mostrará al primer ADMIN para aplicarlo en la BD.
                    Navigator.of(context).pushReplacementNamed('/login');
                  },
                ),
        ),
      ],
    );
  }
}

/// Resumen de lo que ya trajo la cuenta del servidor central, para que el
/// operador vea de un vistazo qué NO tiene que volver a escribir.
class _PrefillBadge extends StatelessWidget {
  final CuentaActivada cuenta;

  const _PrefillBadge({required this.cuenta});

  @override
  Widget build(BuildContext context) {
    final licencia = cuenta.licenciaTier;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SwsColors.accentLight.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: SwsColors.accentLight.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_done_outlined,
              size: 18, color: SwsColors.accentLight),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'company_prefill_badge'.tr(),
              style:
                  const TextStyle(color: SwsColors.accentLight, fontSize: 12),
            ),
          ),
          if (licencia != null && licencia.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: SwsColors.accentLight.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                licencia,
                style: const TextStyle(
                  color: SwsColors.accentLight,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
