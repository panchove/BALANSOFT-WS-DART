import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_text.dart';

class SetupLayoutWrapper extends StatelessWidget {
  final List<Widget> children;
  final VoidCallback? onBack;

  const SetupLayoutWrapper({
    super.key,
    required this.children,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Fondo azul oscuro → iconos de status bar claros siempre.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        // ✅ FONDO AZUL FORZADO — no depende del tema global.
        // Antes: Theme.of(context).scaffoldBackgroundColor (blanco en modo claro).
        backgroundColor: SwsColors.gradientEnd,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            // Desktop: imagen lateral + contenido
            if (w >= 900) return _buildDesktopLayout();
            // Tablet/Mobile: contenido centrado
            return _buildMobileLayout();
          },
        ),
      ),
    );
  }

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
          child: _buildContentArea(),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return SafeArea(
      child: Center(
        child: _buildContentArea(),
      ),
    );
  }

  Widget _buildContentArea() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (onBack != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    // ✅ Icono blanco para que se vea sobre el azul
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: onBack,
                    tooltip: 'Volver',
                  ),
                ),
              if (onBack != null) const SizedBox(height: 16),
              const Center(
                child: BrandText(size: 48, withTagline: true),
              ),
              const SizedBox(height: 48),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}