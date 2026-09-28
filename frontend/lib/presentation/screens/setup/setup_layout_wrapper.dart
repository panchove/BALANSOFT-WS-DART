import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_text.dart';

class SetupLayoutWrapper extends StatelessWidget {
  final List<Widget> children;
  final VoidCallback? onBack;

  /// Cuando es `true` el contenido recibe la **altura disponible** del
  /// viewport en vez de vivir dentro de un `SingleChildScrollView`.
  ///
  /// Necesario para los pasos que usan `Expanded` (p. ej. el formulario de
  /// empresa, cuyos pasos van en un `PageView`): dentro de un scroll vertical
  /// la altura es infinita y un hijo con `flex` revienta el layout.
  final bool fillHeight;

  const SetupLayoutWrapper({
    super.key,
    required this.children,
    this.onBack,
    this.fillHeight = false,
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
    final contenido = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          // Con `fillHeight` la columna ocupa el alto disponible para que los
          // hijos con `Expanded` repartan el espacio sobrante.
          mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
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
            SizedBox(height: fillHeight ? 24 : 48),
            ...children,
          ],
        ),
      ),
    );

    if (fillHeight) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        child: contenido,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: contenido,
    );
  }
}