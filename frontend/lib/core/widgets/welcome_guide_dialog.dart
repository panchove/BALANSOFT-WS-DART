import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/modal_manager.dart';
import '../i18n/translations.dart';
import 'keyboard_dialog_wrapper.dart';
import '../../injection.dart' as di;

/// Un paso del mini tutorial de bienvenida.
///
/// El texto se referencia por clave i18n (es/en/pt) para mantener la paridad
/// de `translations.dart`; [atajo] es un literal corto (p. ej. `F2` o `Ctrl+K`).
class GuideStep {
  final String tituloKey;
  final String textoKey;
  final String? atajo;

  const GuideStep({
    required this.tituloKey,
    required this.textoKey,
    this.atajo,
  });
}

/// Mini tutorial de bienvenida (stepper de una sola vez tras el onboarding).
///
/// Al finalizar o saltar devuelve `true` (el llamador decide si marca
/// `AppConfig.tutorialVisto`). Se reutiliza desde Ayuda y Soporte para verlo
/// las veces que haga falta.
class WelcomeGuideDialog extends StatefulWidget {
  final List<GuideStep> pasos;

  /// Pasos globales por defecto: navegación, acciones rápidas, atajos de
  /// pesaje, paleta de comandos, conexión y ayuda.
  static const pasosGlobales = <GuideStep>[
    GuideStep(
      tituloKey: 'tutorial_sidebar_title',
      textoKey: 'tutorial_sidebar_text',
      atajo: 'F10 · Ctrl+B',
    ),
    GuideStep(
      tituloKey: 'tutorial_dashboard_title',
      textoKey: 'tutorial_dashboard_text',
      atajo: 'Ctrl+1',
    ),
    GuideStep(
      tituloKey: 'tutorial_quick_actions_title',
      textoKey: 'tutorial_quick_actions_text',
      atajo: 'F2 · Ctrl+N',
    ),
    GuideStep(
      tituloKey: 'tutorial_weighing_title',
      textoKey: 'tutorial_weighing_text',
      atajo: 'F2–F6',
    ),
    GuideStep(
      tituloKey: 'tutorial_palette_title',
      textoKey: 'tutorial_palette_text',
      atajo: 'Ctrl+K',
    ),
    GuideStep(
      tituloKey: 'tutorial_connection_title',
      textoKey: 'tutorial_connection_text',
      atajo: 'Ctrl+L · Ctrl+Q',
    ),
    GuideStep(
      tituloKey: 'tutorial_help_title',
      textoKey: 'tutorial_help_text',
      atajo: 'Ayuda',
    ),
  ];

  const WelcomeGuideDialog({super.key, required this.pasos});

  @override
  State<WelcomeGuideDialog> createState() => _WelcomeGuideDialogState();
}

class _WelcomeGuideDialogState extends State<WelcomeGuideDialog> {
  final PageController _pages = PageController();
  int _paso = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _siguiente() {
    if (_paso >= widget.pasos.length - 1) {
      Navigator.of(context).pop(true);
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
    );
  }

  void _cerrar() {
    // Salida sin aceptar (ESC): no marca el tutorial como visto.
    Navigator.of(context).pop(false);
  }

  /// Botón «Saltar»: el usuario decide no verlo, pero es una acción
  /// deliberada, así que el tutorial queda dado por visto (no vuelve a
  /// aparecer en el próximo arranque).
  void _saltar() {
    Navigator.of(context).pop(true);
  }

  void _anterior() {
    if (_paso <= 0) return;
    _pages.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ultimo = _paso == widget.pasos.length - 1;

    final dialogContent = Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.school_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'tutorial_title'.tr(),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'tutorial_subtitle'.tr(),
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    AppTranslations.tr('tutorial_step',
                        args: ['${_paso + 1}', '${widget.pasos.length}']),
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: (_paso + 1) / widget.pasos.length,
                        minHeight: 4,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 190,
                child: PageView(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _paso = i),
                  children: [
                    for (final p in widget.pasos) _TarjetaPaso(paso: p),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton(
                    onPressed: _saltar,
                    child: Text('tutorial_skip'.tr()),
                  ),
                  const Spacer(),
                  if (_paso > 0) ...[
                    OutlinedButton(
                      onPressed: _anterior,
                      child: Text('tutorial_back'.tr()),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton(
                    key: const Key('guia_siguiente_btn'),
                    onPressed: _siguiente,
                    child: Text(
                      ultimo ? 'tutorial_finish'.tr() : 'tutorial_next'.tr(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return KeyboardDialogWrapper(
      onEnter: _siguiente,
      onEscape: _cerrar,
      child: dialogContent,
    );
  }
}

class _TarjetaPaso extends StatelessWidget {
  final GuideStep paso;

  const _TarjetaPaso({required this.paso});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final atajo = paso.atajo?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          paso.tituloKey.tr(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          paso.textoKey.tr(),
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        if (atajo != null && atajo.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.keyboard_command_key,
                    size: 14, color: scheme.onSecondaryContainer),
                const SizedBox(width: 6),
                Text(
                  '${'tutorial_shortcut'.tr()}: $atajo',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Abre el mini tutorial de bienvenida.
///
/// Si [marcarVisto] es true, persiste `AppConfig.tutorialVisto` cuando el
/// usuario finaliza o salta (no al cerrar de otra forma).
Future<bool?> mostrarGuiaRapida(
  BuildContext context, {
  bool marcarVisto = false,
}) {
  final modalManager = di.sl<ModalManager>();
  return modalManager.showModal<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const WelcomeGuideDialog(
      pasos: WelcomeGuideDialog.pasosGlobales,
    ),
  ).then((visto) {
    if (marcarVisto && visto == true) {
      AppConfig.setTutorialVisto();
    }
    return visto;
  });
}
