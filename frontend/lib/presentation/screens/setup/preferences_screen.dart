import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import 'setup_layout_wrapper.dart';

/// Paso 1 de la instalación: idioma y tema de la app.
///
/// Se muestra antes de necesitar la API local, de modo que toda la
/// instalación (entorno, conexiones, login) quede en el idioma elegido
/// (docs/I18N_Y_ONBOARDING.md · REQ-NF-ONB-001).
class SetupPreferencesScreen extends StatelessWidget {
  final LocaleController localeController;
  final ThemeController themeController;

  const SetupPreferencesScreen({
    super.key,
    required this.localeController,
    required this.themeController,
  });

  @override
  Widget build(BuildContext context) {
    return SetupLayoutWrapper(
      children: [
        const Icon(
          Icons.translate_rounded,
          size: 44,
          color: SwsColors.accentLight,
        ),
        const SizedBox(height: 20),
        Text(
          'setup_preferences_title'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: SwsColors.white,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'setup_preferences_subtitle'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: SwsColors.white.withValues(alpha: 0.60),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        _SectionTitle('setup_step_language'.tr()),
        const SizedBox(height: 10),
        _LanguageOptions(controller: localeController),
        const SizedBox(height: 26),
        _SectionTitle('setup_step_theme'.tr()),
        const SizedBox(height: 10),
        _ThemeOptions(controller: themeController),
        const SizedBox(height: 34),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            key: const Key('setup_continuar_btn'),
            onPressed: () async {
              await AppConfig.setSetupPreferenciasCompletado();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/mode_selection');
              }
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(
              'setup_continue'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: SwsColors.accentLight,
              foregroundColor: SwsColors.gradientEnd,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'setup_language_note'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: SwsColors.white.withValues(alpha: 0.50),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: SwsColors.accentLight,
      ),
    );
  }
}

class _LanguageOptions extends StatelessWidget {
  final LocaleController controller;
  const _LanguageOptions({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        children: [
          for (final lang in AppLanguage.values)
            _OptionTile(
              selected: controller.language == lang,
              icon: switch (lang) {
                AppLanguage.system => Icons.devices_rounded,
                AppLanguage.es => Icons.flag_outlined,
                AppLanguage.en => Icons.translate_rounded,
                AppLanguage.pt => Icons.language_rounded,
              },
              title: _languageLabel(lang),
              onTap: () => controller.setLanguage(lang),
            ),
        ],
      ),
    );
  }

  String _languageLabel(AppLanguage lang) {
    return switch (lang) {
      AppLanguage.system => 'language_system'.tr(),
      AppLanguage.es => 'language_es'.tr(),
      AppLanguage.en => 'language_en'.tr(),
      AppLanguage.pt => 'language_pt'.tr(),
    };
  }
}

class _ThemeOptions extends StatelessWidget {
  final ThemeController controller;
  const _ThemeOptions({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Row(
        children: [
          for (final tema in TemaApp.values) ...[
            Expanded(
              child: _OptionTile(
                dense: true,
                selected: controller.tema == tema,
                icon: switch (tema) {
                  TemaApp.sistema => Icons.brightness_auto_rounded,
                  TemaApp.claro => Icons.light_mode_rounded,
                  TemaApp.oscuro => Icons.dark_mode_rounded,
                },
                title: _themeLabel(tema),
                onTap: () => controller.setTema(tema),
              ),
            ),
            if (tema != TemaApp.values.last) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  String _themeLabel(TemaApp tema) {
    return switch (tema) {
      TemaApp.sistema => 'theme_system'.tr(),
      TemaApp.claro => 'theme_light'.tr(),
      TemaApp.oscuro => 'theme_dark'.tr(),
    };
  }
}

class _OptionTile extends StatelessWidget {
  final bool selected;
  final bool dense;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _OptionTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: dense ? 12 : 14,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? SwsColors.accentLight.withValues(alpha: 0.16)
                  : SwsColors.surfaceGlass,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? SwsColors.accentLight
                    : SwsColors.surfaceGlassBorder,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: dense ? 20 : 24, color: SwsColors.accentLight),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: dense ? 13 : 15,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      color: SwsColors.white,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: SwsColors.accentLight,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
