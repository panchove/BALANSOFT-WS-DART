import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Wordmark de marca `baLnsoft` + sufijo `WS` (Estación de Pesaje), al mismo
/// estilo que BALANSOFT-SG.
class BrandText extends StatelessWidget {
  const BrandText({super.key, this.size, this.withTagline = false});

  final double? size;
  final bool withTagline;

  @override
  Widget build(BuildContext context) {
    final baseSize = size ?? 34;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'baLnsoft',
                style: TextStyle(
                  fontFamily: 'BalansoftBrand',
                  fontWeight: FontWeight.w400,
                  color: SwsColors.accent,
                  fontSize: baseSize,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                'WS',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: SwsColors.accentLight,
                  fontSize: baseSize * 0.5,
                  letterSpacing: 2,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
        if (withTagline)
          const Text(
            'Estación de Pesaje',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 6,
              color: SwsColors.gray500,
              fontWeight: FontWeight.w300,
            ),
          ),
      ],
    );
  }
}
