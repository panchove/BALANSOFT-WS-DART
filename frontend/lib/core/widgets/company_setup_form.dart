import 'package:flutter/material.dart';

import '../i18n/locale_controller.dart';
import '../i18n/translations.dart';
import '../theme/app_theme.dart';
import '../utils/save_file_utils.dart';
import '../widgets/photo_picker_field.dart';

/// Datos de empresa + preferencias de exportación.
///
/// Es la única fuente de verdad de la configuración inicial: la usan tanto la
/// instalación (antes del login, se guarda como borrador local) como el
/// wizard posterior al login (se envía a `PUT /api/v1/empresa`).
class CompanySetupData {
  final String nombreFiscal;
  final String nombreComercial;
  final String rifNit;
  final String direccion;
  final String telefono;
  final String email;
  final String idioma;
  final String formatoTicket;
  final String formatoReporte;
  final String rutaReportes;
  final List<PhotoCaptured> logo;
  final String? logoUrl;

  const CompanySetupData({
    this.nombreFiscal = '',
    this.nombreComercial = '',
    this.rifNit = '',
    this.direccion = '',
    this.telefono = '',
    this.email = '',
    this.idioma = 'es',
    this.formatoTicket = 'PDF',
    this.formatoReporte = 'EXCEL',
    this.rutaReportes = '',
    this.logo = const [],
    this.logoUrl,
  });

  /// Cuerpo para `PUT /api/v1/empresa` (nulos = "no cambiar").
  /// El backend solo admite `es|en|pt`; "system" (seguir al sistema) se
  /// resuelve al idioma activo de la estación antes de enviarse.
  String get idiomaApi => switch (idioma) {
        'en' => 'en',
        'pt' => 'pt',
        _ => 'es',
      };

  Map<String, dynamic> toApiBody() => {
        'nombre_fiscal': nombreFiscal.trim(),
        'nombre_comercial': _oNulo(nombreComercial),
        'rif_nit': _oNulo(rifNit),
        'direccion': _oNulo(direccion),
        'telefono': _oNulo(telefono),
        'email': _oNulo(email),
        'idioma': idiomaApi,
        'formato_ticket': formatoTicket,
        'formato_reporte': formatoReporte,
        'ruta_exportacion_reportes': _oNulo(rutaReportes),
        if (logo.isNotEmpty || logoUrl != null) 'logo_url': logoUrl,
      };

  static String? _oNulo(String v) => v.trim().isEmpty ? null : v.trim();
}

/// Formulario estándar de configuración de empresa (3 pasos).
///
/// - Paso 1: datos de la empresa y logo.
/// - Paso 2: formatos de exportación (boleto, reporte) e idioma.
/// - Paso 3: carpeta de reportes, validando que sea escribible.
class CompanySetupForm extends StatefulWidget {
  final CompanySetupData? initial;
  final LocaleController localeController;

  /// Etiqueta del botón final (`initial_setup_finish` o `setup_continue`).
  final String finalLabelKey;

  /// Se invoca con los datos cuando el usuario confirma el último paso.
  final Future<void> Function(CompanySetupData data) onSubmit;

  /// Se invoca al cambiar el idioma en el paso 2 (para aplicarlo en vivo).
  final Future<void> Function(String idioma)? onLanguageChanged;

  final bool mostrarOmitir;
  final VoidCallback? onOmitir;

  /// Bloquea razón social y RIF: cuando los datos vienen de la cuenta del
  /// servidor central son la identidad de la cuenta y no se editan aquí
  /// (se cambian desde el panel del proveedor).
  final bool initialLock;

  const CompanySetupForm({
    super.key,
    required this.localeController,
    required this.onSubmit,
    this.initial,
    this.finalLabelKey = 'initial_setup_finish',
    this.onLanguageChanged,
    this.mostrarOmitir = true,
    this.onOmitir,
    this.initialLock = false,
  });

  @override
  State<CompanySetupForm> createState() => CompanySetupFormState();
}

class CompanySetupFormState extends State<CompanySetupForm> {
  final _ctrl = <TextEditingController>[];
  final PageController _pages = PageController();

  int _paso = 0;
  bool _enviando = false;
  bool _rutaValida = true;
  bool _rutaVerificada = false;

  String _idioma = 'es';
  String _formatoTicket = 'PDF';
  String _formatoReporte = 'EXCEL';
  List<PhotoCaptured> _logo = const [];
  String? _logoUrl;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _idioma = i?.idioma ?? 'es';
    _formatoTicket = i?.formatoTicket ?? 'PDF';
    _formatoReporte = i?.formatoReporte ?? 'EXCEL';
    _logoUrl = i?.logoUrl;
    if (i != null) {
      _crear(0, i.nombreFiscal);
      _crear(1, i.nombreComercial);
      _crear(2, i.rifNit);
      _crear(3, i.direccion);
      _crear(4, i.telefono);
      _crear(5, i.email);
      _crear(6, i.rutaReportes);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl) {
      c.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  TextEditingController _crear(int indice, String valor) {
    while (_ctrl.length <= indice) {
      _ctrl.add(TextEditingController());
    }
    if (_ctrl[indice].text.isEmpty) _ctrl[indice].text = valor;
    return _ctrl[indice];
  }

  /// Datos actuales del formulario (para guardado manual o validación).
  CompanySetupData get data => CompanySetupData(
        nombreFiscal: _ctrl.isNotEmpty ? _ctrl[0].text : '',
        nombreComercial: _crear(1, '').text,
        rifNit: _crear(2, '').text,
        direccion: _crear(3, '').text,
        telefono: _crear(4, '').text,
        email: _crear(5, '').text,
        idioma: _idioma,
        formatoTicket: _formatoTicket,
        formatoReporte: _formatoReporte,
        rutaReportes: _crear(6, '').text,
        logo: _logo,
        logoUrl: _logoUrl,
      );

  Future<void> _aplicarIdiomaLocal() async {
    if (_idioma == 'system') return;
    await widget.localeController.setLanguage(switch (_idioma) {
      'en' => AppLanguage.en,
      'pt' => AppLanguage.pt,
      _ => AppLanguage.es,
    });
    await widget.onLanguageChanged?.call(_idioma);
  }

  Future<void> _verificarRuta() async {
    final ruta = _ctrl.length > 6 ? _ctrl[6].text.trim() : '';
    if (ruta.isEmpty) {
      setState(() {
        _rutaValida = true;
        _rutaVerificada = true;
      });
      return;
    }
    final ok = await SaveFileUtils.esRutaEscribible(ruta);
    if (!mounted) return;
    setState(() {
      _rutaValida = ok;
      _rutaVerificada = true;
    });
  }

  Future<void> _usarCarpetaPredeterminada() async {
    await SaveFileUtils.setRutaPersonalizada(null);
    if (!mounted) return;
    setState(() {
      if (_ctrl.length > 6) _ctrl[6].clear();
      _rutaValida = true;
      _rutaVerificada = true;
    });
  }

  Future<void> _siguiente() async {
    if (_paso == 1) await _aplicarIdiomaLocal();
    if (_paso == 0) await _verificarRuta();
    if (mounted) setState(() => _paso++);
  }

  Future<void> _finalizar() async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      await _verificarRuta();
      await _aplicarIdiomaLocal();
      await widget.onSubmit(data);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              _StepperHeader(paso: _paso),
              Expanded(
                child: PageView(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_pasoEmpresa(), _pasoFormatos(), _pasoReportes()],
                ),
              ),
            ],
          ),
        ),
        _barraInferior(),
      ],
    );
  }

  Widget _pasoEmpresa() {
    return _lista([
      Text(
        'initial_setup_step_company'.tr(),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: SwsColors.white,
        ),
      ),
      const SizedBox(height: 16),
      PhotoPickerField(
        label: 'initial_setup_company_logo'.tr(),
        fotos: _logo,
        onChanged: (f) => setState(() => _logo = f),
        maxFotos: 1,
      ),
      const SizedBox(height: 16),
      _texto(0, 'initial_setup_company_legal_name', Icons.badge_outlined,
          bloqueado: widget.initialLock),
      const SizedBox(height: 12),
      _texto(1, 'initial_setup_company_name', Icons.storefront_outlined),
      const SizedBox(height: 12),
      _texto(2, 'initial_setup_company_taxid', Icons.numbers_rounded,
          bloqueado: widget.initialLock),
      const SizedBox(height: 12),
      _texto(3, 'initial_setup_company_address', Icons.location_on_outlined),
      const SizedBox(height: 12),
      _texto(4, 'initial_setup_company_phone', Icons.phone_outlined),
      const SizedBox(height: 12),
      _texto(5, 'initial_setup_company_email', Icons.email_outlined),
    ]);
  }

  Widget _pasoFormatos() {
    return _lista([
      Text(
        'initial_setup_step_appearance'.tr(),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: SwsColors.white,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'setup_language_note'.tr(),
        style: TextStyle(
          fontSize: 12,
          color: SwsColors.white.withValues(alpha: 0.6),
        ),
      ),
      const SizedBox(height: 20),
      _selector(
        'initial_setup_ticket_format',
        Icons.confirmation_number_outlined,
        _formatoTicket,
        const ['PDF', 'TXT'],
        (v) => setState(() => _formatoTicket = v),
      ),
      const SizedBox(height: 16),
      _selector(
        'initial_setup_report_format',
        Icons.table_chart_outlined,
        _formatoReporte,
        const ['EXCEL', 'PDF'],
        (v) => setState(() => _formatoReporte = v),
      ),
      const SizedBox(height: 16),
      _selector(
        'setup_step_language',
        Icons.translate_rounded,
        _idioma,
        const ['es', 'en', 'pt', 'system'],
        (v) => setState(() => _idioma = v),
      ),
    ]);
  }

  Widget _pasoReportes() {
    return _lista([
      Text(
        'initial_setup_step_reports'.tr(),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: SwsColors.white,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'initial_setup_reports_folder_hint'.tr(),
        style: TextStyle(
          fontSize: 12,
          color: SwsColors.white.withValues(alpha: 0.6),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _crear(6, ''),
        style: const TextStyle(color: SwsColors.white),
        decoration: InputDecoration(
          labelText: 'initial_setup_reports_folder'.tr(),
          prefixIcon: const Icon(Icons.folder_open_rounded),
          suffixIcon: IconButton(
            tooltip: 'initial_setup_use_default_folder'.tr(),
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: _usarCarpetaPredeterminada,
          ),
        ),
        onChanged: (_) => setState(() {
          _rutaVerificada = false;
          _rutaValida = true;
        }),
      ),
      if (_rutaVerificada)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Icon(
                _rutaValida
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                size: 18,
                color: _rutaValida ? SwsColors.success : SwsColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _rutaValida
                      ? 'initial_setup_folder_ok'.tr()
                      : 'initial_setup_folder_not_writable'.tr(),
                  style: TextStyle(
                    fontSize: 12,
                    color: _rutaValida ? SwsColors.success : SwsColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _lista(List<Widget> hijos) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      children: hijos,
    );
  }

  Widget _texto(
    int indice,
    String etiqueta,
    IconData icono, {
    bool bloqueado = false,
  }) {
    return TextField(
      controller: _crear(indice, ''),
      readOnly: bloqueado,
      style: TextStyle(
        color: bloqueado ? Colors.white70 : SwsColors.white,
      ),
      decoration: InputDecoration(
        labelText: etiqueta.tr(),
        prefixIcon: Icon(icono),
        helperText: bloqueado ? 'company_field_from_server'.tr() : null,
        helperStyle:
            const TextStyle(fontSize: 11, color: SwsColors.accentLight),
      ),
    );
  }

  Widget _selector(
    String etiqueta,
    IconData icono,
    String valor,
    List<String> opciones,
    ValueChanged<String> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: valor,
      isExpanded: true,
      dropdownColor: SwsColors.darkCard,
      style: const TextStyle(color: SwsColors.white),
      decoration: InputDecoration(
        labelText: etiqueta.tr(),
        prefixIcon: Icon(icono),
      ),
      items: [
        for (final o in opciones)
          DropdownMenuItem(
            value: o,
            child: Text(
              o == 'system' ? 'language_system'.tr() : _etiquetaFormato(o),
              style: const TextStyle(color: SwsColors.white),
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  /// El backend solo admite EXCEL|PDF; la etiqueta es amigable.
  String _etiquetaFormato(String valor) {
    return switch (valor) {
      'EXCEL' => 'report_format_excel'.tr(),
      'TXT' => 'report_format_txt'.tr(),
      _ => valor,
    };
  }

  Widget _barraInferior() {
    final ultimo = _paso == 2;
    // `Wrap` en vez de `Row`: con traducciones largas (EN/PT) o pantallas
    // angostas los botones se reparten en dos líneas en lugar de desbordar.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        spacing: 8,
        children: [
          if (widget.mostrarOmitir && widget.onOmitir != null)
            TextButton(
              onPressed: _enviando ? null : widget.onOmitir,
              child: Text('initial_setup_skip'.tr()),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_paso > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    onPressed: _enviando ? null : () => setState(() => _paso--),
                    child: Text('btn_back'.tr()),
                  ),
                ),
              if (ultimo)
                FilledButton.icon(
                  onPressed: _enviando ? null : _finalizar,
                  icon: _enviando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(widget.finalLabelKey.tr()),
                )
              else
                FilledButton(
                  onPressed: _enviando ? null : _siguiente,
                  child: Text('setup_continue'.tr()),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperHeader extends StatelessWidget {
  final int paso;
  const _StepperHeader({required this.paso});

  static const titulos = [
    'initial_setup_step_company',
    'initial_setup_step_appearance',
    'initial_setup_step_reports',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulos[paso].tr(),
            style: const TextStyle(
              fontSize: 12,
              color: SwsColors.accentLight,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < titulos.length; i++) ...[
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= paso
                          ? SwsColors.accentLight
                          : SwsColors.surfaceGlassBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (i < titulos.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
