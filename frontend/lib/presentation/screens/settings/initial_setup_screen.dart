import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/save_file_utils.dart';
import '../../../core/widgets/company_setup_form.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;

/// Configuración inicial posterior al login.
///
/// Usa el mismo formulario estandarizado que la instalación
/// (`CompanySetupForm`); se muestra solo cuando el primer `ADMIN` entra sin
/// borrador previo (p. ej. estación instalada antes de este flujo) y también
/// se puede reabrir desde Ajustes → Empresa y Documentos
/// (docs/I18N_Y_ONBOARDING.md · REQ-NF-ONB-002).
class InitialSetupScreen extends StatefulWidget {
  final LocaleController localeController;
  final OnboardingFinish? onFinish;

  const InitialSetupScreen({
    super.key,
    required this.localeController,
    this.onFinish,
  });

  @override
  State<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends State<InitialSetupScreen> {
  CompanySetupData? _inicial;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final perfil = await di.sl<ApiClient>().getEmpresaPerfil();
      if (!mounted) return;
      setState(() {
        _inicial = CompanySetupData(
          nombreFiscal: '${perfil['nombre_fiscal'] ?? ''}',
          nombreComercial: '${perfil['nombre_comercial'] ?? ''}',
          rifNit: '${perfil['rif_nit'] ?? ''}',
          direccion: '${perfil['direccion'] ?? ''}',
          telefono: '${perfil['telefono'] ?? ''}',
          email: '${perfil['email'] ?? ''}',
          idioma: '${perfil['idioma'] ?? 'es'}',
          formatoTicket: '${perfil['formato_ticket'] ?? 'PDF'}',
          formatoReporte: '${perfil['formato_reporte'] ?? 'EXCEL'}',
          rutaReportes: '${perfil['ruta_exportacion_reportes'] ?? ''}',
          logoUrl: perfil['logo_url'] as String?,
        );
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _guardar(CompanySetupData data) async {
    final api = di.sl<ApiClient>();
    final cuerpo = data.toApiBody();
    if (data.logo.isNotEmpty) {
      cuerpo['logo_url'] = await api.uploadPhotoFile(
        data.logo.first.bytes,
        data.logo.first.nombre,
        carpeta: 'empresa',
      );
    }
    await api.updateEmpresaPerfil(cuerpo);
    final ruta = data.rutaReportes.trim();
    await SaveFileUtils.setRutaPersonalizada(ruta.isEmpty ? null : ruta);
    await AppConfig.setOnboardingCompletado();
    if (!mounted) return;
    _mensaje('initial_setup_saved'.tr(), SwsColors.success);
    widget.onFinish?.call();
  }

  void _mensaje(String texto, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('initial_setup_title'.tr()),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : CompanySetupForm(
                localeController: widget.localeController,
                initial: _inicial,
                onSubmit: (data) async {
                  try {
                    await _guardar(data);
                  } catch (e) {
                    if (!mounted) return;
                    _mensaje('${'initial_setup_error'.tr()}$e', SwsColors.danger);
                  }
                },
                onOmitir: () async {
                  await AppConfig.setOnboardingCompletado();
                  if (mounted) widget.onFinish?.call();
                },
              ),
      ),
    );
  }
}

typedef OnboardingFinish = void Function();
