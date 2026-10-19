import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/controllers/typography_controller.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/auth/auth_bloc.dart';

/// Ajustes de tipografía de la estación.
///
/// Los dos ajustes que-conviven aquí tienen alcances distintos (spec 001 §3) y
/// no se deben confundir:
///
/// - **Familia y tamaño de la interfaz**: preferencia **de este dispositivo**
///   (`SharedPreferences`), igual que el tema. No va al backend.
/// - **Paso del tamaño del ticket PDF**: ajuste **de la empresa**
///   (`PUT`/`GET /api/v1/empresa`). Por eso solo lo ve y lo cambia el rol
///   ADMIN; para los demás el `PUT` responde 403.
///
/// La **fuente** del PDF no es seleccionable (REQ-FN-014: la BD solo admite
/// `DejaVu`); se informa como texto, nunca como un control que no hace nada.
class TypographySettingsScreen extends StatefulWidget {
  const TypographySettingsScreen({super.key});

  @override
  State<TypographySettingsScreen> createState() =>
      _TypographySettingsScreenState();
}

class _TypographySettingsScreenState extends State<TypographySettingsScreen> {
  late TypographyController _controller;

  /// Solo si el contenedor de dependencias no tiene el controlador (por ejemplo
  /// en pruebas aisladas). En la app real siempre es el singleton, que es el
  /// que escucha `main.dart` para aplicar el ajuste a toda la aplicación
  /// (REQ-FN-004). Mismo patrón que el `LocaleController` de `settings_screen`.
  TypographyController? _controllerLocal;

  bool _loading = true;
  bool _saving = false;

  /// El selector del ticket es un ajuste de la empresa, así que se limita a
  /// ADMIN. Se resuelve en `build` con el mismo patrón que el resto de Ajustes
  /// (`settings_screen.dart`, tile de Licencia).
  bool _esAdmin = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _controller = di.sl.isRegistered<TypographyController>()
        ? di.sl<TypographyController>()
        : _controllerLocal ??=
            TypographyController(prefs: await SharedPreferences.getInstance());
    await _controller.load();
    if (!mounted) return;
    setState(() => _loading = false);
    // La empresa es la autoridad del tamaño del ticket, así que la lectura va
    // después del primer frame: ahí el `AuthBloc` ya está resuelto y usar el
    // contexto es seguro.
    WidgetsBinding.instance.addPostFrameCallback((_) => _leerTamanoTicket());
  }

  // ── Rol ──────────────────────────────────────────────────────────────────

  String? _rolActual() {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated ? state.user.rol : null;
  }

  // ── Ticket (ajuste de la empresa) ─────────────────────────────────────────

  /// Normaliza lo que devuelve `GET /empresa`: solo se acepta un valor del
  /// `Literal` del backend, cualquier otra cosa se ignora.
  String? _tamanoTicketDesde(Map<String, dynamic> perfil) {
    final valor = perfil['tamano_ticket_pdf'];
    if (valor is! String) return null;
    return TypographyController.esTamanoTicketValido(valor) ? valor : null;
  }

  /// Refleja el tamaño configurado en la empresa. Un fallo de red no es motivo
  /// para esconder nada: se avisa y se conserva el valor de este dispositivo.
  Future<void> _leerTamanoTicket() async {
    if (!mounted) return;
    if (_rolActual() != 'ADMIN') return;
    try {
      final perfil = await di.sl<ApiClient>().getEmpresaPerfil();
      final remoto = _tamanoTicketDesde(perfil);
      if (remoto == null || remoto == _controller.tamanoTicketPdf) return;
      await _controller.setTamanoTicketPdf(remoto);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Tipografía: no se pudo leer el tamaño del ticket: $e');
      if (!mounted) return;
      _avisar('tipografia_ticket_error_lectura'.tr(), SwsColors.danger);
    }
  }

  /// Guarda el tamaño del ticket en la empresa (`PUT /api/v1/empresa`) y lo
  /// vuelve a leer (`GET /api/v1/empresa`): la empresa es la autoridad del PDF,
  /// así que lo que se muestra es lo que quedó guardado, no lo que se pidió.
  Future<bool> _guardarTamanoTicketEnEmpresa({String? mensajeOk}) async {
    // Solo ADMIN: el `PUT` responde 403 para cualquier otro rol.
    if (!_esAdmin) return false;
    if (mounted) setState(() => _saving = true);
    try {
      await di.sl<ApiClient>().updateEmpresaPerfil({
        'tamano_ticket_pdf': _controller.tamanoTicketPdf,
      });
      final perfil = await di.sl<ApiClient>().getEmpresaPerfil();
      final remoto = _tamanoTicketDesde(perfil);
      if (remoto != null && remoto != _controller.tamanoTicketPdf) {
        await _controller.setTamanoTicketPdf(remoto);
      }
      if (mounted) setState(() {});
      _avisar(
        mensajeOk ?? 'tipografia_ticket_guardado'.tr(),
        SwsColors.success,
      );
      return true;
    } catch (e) {
      // Modo offline-first: el valor local se conserva (el operador no pierde
      // lo que eligió) pero el aviso dice que los boletos siguen con el tamaño
      // anterior, porque hasta que se guarde en la empresa el PDF no cambia.
      debugPrint('Tipografía: no se pudo guardar el tamaño del ticket: $e');
      _avisar('tipografia_ticket_error'.tr(), SwsColors.danger);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Acciones ─────────────────────────────────────────────────────────────

  Future<void> _resetDefaults() async {
    await _controller.setTextScale(1.00);
    await _controller.setFamiliaUi(TypographyController.familiaUiPorDefecto);
    await _controller.setTipoFuenteTicket(TypographyController.fuenteTicket);
    await _controller.setTamanoTicketPdf(
      TypographyController.tamanoTicketPorDefecto,
    );
    if (_esAdmin) {
      await _guardarTamanoTicketEnEmpresa(
        mensajeOk: 'tipografia_restaurados'.tr(),
      );
      return;
    }
    if (mounted) setState(() {});
    _avisar('tipografia_restaurados'.tr(), SwsColors.success);
  }

  void _avisar(String mensaje, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(mensaje), backgroundColor: color),
      );
  }

  // ── Etiquetas ────────────────────────────────────────────────────────────

  /// Traducción de las 5 familias de REQ-FN-007. Un `default` explícito: si se
  /// añadiera una familia sin su clave, se muestra la del sistema en vez de
  /// dejar la clave en pantalla.
  String _etiquetaFamilia(String familia) {
    switch (familia) {
      case 'SANS_SERIF':
        return 'tipografia_familia_sans_serif'.tr();
      case 'SERIF':
        return 'tipografia_familia_serif'.tr();
      case 'MONOSPACE':
        return 'tipografia_familia_monospace'.tr();
      case 'ROBOTO':
        return 'tipografia_familia_roboto'.tr();
      case 'SISTEMA':
      default:
        return 'tipografia_familia_sistema'.tr();
    }
  }

  // ── Pantalla ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rol = context.select<AuthBloc, String?>((bloc) {
      final state = bloc.state;
      return state is AuthAuthenticated ? state.user.rol : null;
    });
    _esAdmin = rol == 'ADMIN';

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final tema = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('tipografia_titulo'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _cardFamilia(tema),
          const SizedBox(height: 16),
          _cardEscala(tema),
          const SizedBox(height: 16),
          // Ajuste de la empresa: fuera del alcance de los demás roles.
          if (_esAdmin) ...[
            _cardTamanoTicket(tema),
            const SizedBox(height: 16),
          ],
          _cardFuenteTicket(tema),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: _saving ? null : _resetDefaults,
            child: Text('tipografia_restablecer'.tr()),
          ),
        ],
      ),
    );
  }

  /// Familia de letra de la interfaz (REQ-FN-007). Preferencia del dispositivo.
  Widget _cardFamilia(ThemeData tema) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'tipografia_ui_familia'.tr(),
                style: tema.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'tipografia_ui_familia_scope'.tr(),
                style: tema.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _controller.familiaUi,
                onChanged: (v) {
                  if (v == null || v == _controller.familiaUi) return;
                  // El controlador actualiza el valor de forma síncrona, así que
                  // el redibujado es inmediato y la escritura en preferencias va
                  // por detrás: esperar aquí retrasaría el gesto una escritura
                  // a disco por cada paso del control.
                  unawaited(_controller.setFamiliaUi(v));
                  setState(() {});
                },
                child: Column(
                  children: TypographyController.familiasUi
                      .map(
                        (familia) => RadioListTile<String>(
                          value: familia,
                          title: Text(_etiquetaFamilia(familia)),
                          dense: true,
                          activeColor: SwsColors.accent,
                        ),
                      )
                      .toList(),
                ),
              ),
              const Divider(),
              Text(
                'tipografia_vista_previa'.tr(),
                style: tema.textTheme.bodySmall,
              ),
              Text(
                'AaBbCc 0123456789',
                // Si la familia no está instalada en el sistema, Flutter cae a
                // la fuente por defecto sin fallar ni avisar (REQ-FN-006).
                style: tema.textTheme.titleLarge?.copyWith(
                  fontFamily: _controller.familiaUiFontFamily,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tamaño del texto de la interfaz: factor 0.85–1.40, aplica sin reiniciar.
  Widget _cardEscala(ThemeData tema) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'tipografia_ui_escala'.tr(),
                style: tema.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('0.85'),
                  Expanded(
                    child: Slider(
                      value: _controller.textScale,
                      min: 0.85,
                      max: 1.40,
                      divisions: 11,
                      label: _controller.textScale.toStringAsFixed(2),
                      onChanged: (v) {
                        unawaited(_controller.setTextScale(v));
                        setState(() {});
                      },
                    ),
                  ),
                  const Text('1.40'),
                ],
              ),
              Text(
                'tipografia_actual'.tr().replaceFirst(
                      '{}',
                      _controller.textScale.toStringAsFixed(2),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Paso del tamaño del ticket PDF: ajuste de la empresa (solo ADMIN).
  Widget _cardTamanoTicket(ThemeData tema) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'tipografia_ticket_tamano'.tr(),
              style: tema.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment<String>(
                  value: 'AUTOMATICO',
                  label: Text('tipografia_ticket_automatico'.tr()),
                ),
                ButtonSegment<String>(
                  value: 'GRANDE',
                  label: Text('tipografia_ticket_grande'.tr()),
                ),
                ButtonSegment<String>(
                  value: 'MEDIANO',
                  label: Text('tipografia_ticket_mediano'.tr()),
                ),
                ButtonSegment<String>(
                  value: 'PEQUENO',
                  label: Text('tipografia_ticket_pequeno'.tr()),
                ),
              ],
              selected: <String>{_controller.tamanoTicketPdf},
              onSelectionChanged: _saving
                  ? null
                  : (selection) async {
                      final v = selection.isNotEmpty
                          ? selection.first
                          : TypographyController.tamanoTicketPorDefecto;
                      await _controller.setTamanoTicketPdf(v);
                      await _guardarTamanoTicketEnEmpresa();
                    },
              multiSelectionEnabled: false,
            ),
          ],
        ),
      ),
    );
  }

  /// REQ-FN-014: la fuente del PDF no es seleccionable, solo DejaVu. Se informa
  /// como texto y no como control: un botón o un desplegable que no cambia
  /// nada hace que el operador busque un ajuste que no existe.
  Widget _cardFuenteTicket(ThemeData tema) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'tipografia_ticket_fuente'.tr(),
              style: tema.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'tipografia_fuente_fija'.tr(),
              style: tema.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
