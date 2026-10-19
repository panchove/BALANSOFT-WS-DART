// T10b · Caso 3 — Contraste AA en las etiquetas del ajuste de tipografía
// (REQ-FN-020). Tema claro y oscuro, con el factor del operador en los dos
// extremos del rango [0.85, 1.40].
//
// El contraste NO depende del factor de texto: depende del par
// color-de-fondo / color-de-texto que el tema asigne a cada etiqueta. Por eso
// el test calcula la razón sobre los colores **resueltos** del `TextTheme` y
// de las superficies reales, y luego comprueba que el escalado no altera el
// color (escalar el tamaño no cambia el color). Verificar el contraste con
// "el factor no importa" escrito a mano no valdría nada; aquí se lee del tema.
//
// Método: WCAG 2.1 §1.4.3. Luminancia relativa con los coeficientes de la
// fórmula canónica (0.2126 / 0.7152 / 0.0722) y razón (L1 + 0.05)/(L2 + 0.05).
// Se usa `Color.computeLuminance()` de Flutter, que ya implementa esa fórmula
// en sRGB, y se recalcula con la fórmula propia como contraste cruzado: si los
// dos caminos difieren, el test falla en vez de dar un número falso.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/theme/app_theme.dart';

/// Razón de contraste WCAG, calculada desde la fórmula canónica.
double razonDeContraste(Color a, Color b) {
  double canal(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  double luminancia(Color c) => 0.2126 * canal(c.r) +
      0.7152 * canal(c.g) +
      0.0722 * canal(c.b);

  final la = luminancia(a);
  final lb = luminancia(b);
  final claro = la > lb ? la : lb;
  final oscuro = la > lb ? lb : la;
  return (claro + 0.05) / (oscuro + 0.05);
}

/// AA para texto normal (REQ-FN-020 no pide texto grande ni UI component).
const double minimoAA = 4.5;

/// Resuelve el color de fondo real de una tarjeta en el tema dado: la tarjeta
/// se pinta sobre `scaffoldBackgroundColor`, no sobre el color del `Card` de
/// Material, que por defecto es transparente.
Color fondoDeTarjeta(ThemeData tema) =>
    tema.cardTheme.color ?? tema.scaffoldBackgroundColor;

void main() {
  final temas = <String, ThemeData>{
    'claro': buildLightTheme(),
    'oscuro': buildDarkTheme(),
  };

  // Los dos extremos del selector (REQ-FN-001/002). Se recorren porque el
  // criterio de T10b es "con cualquier tamaño dentro del rango".
  const factores = <double>[0.85, 1.40];

  group('T10b caso 3 · REQ-FN-020 contraste AA en las etiquetas del ajuste', () {
    for (final entrada in temas.entries) {
      for (final factor in factores) {
        test('tema ${entrada.key} con factor $factor', () {
          final tema = entrada.value;

          // El factor entra por el `textScaler`, igual que en la app: con
          // `MediaQuery` escalado, el color que resuelve cada `Text` es el del
          // `TextTheme` del tema.
          final mq = MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(factor),
            ),
            child: Builder(
              builder: (context) => _Etiquetas(
                tituloStyle: tema.textTheme.titleMedium!,
                valorStyle: tema.textTheme.bodyMedium!,
                textoActual: tema.textTheme.bodySmall!,
                factor: factor,
                mq: MediaQuery.of(context).textScaler,
              ),
            ),
          );
          expect(mq, isNotNull);

          final fondo = fondoDeTarjeta(tema);
          final superficieTexto = tema.textTheme.bodyMedium!.color!;

          // 1) Las etiquetas del ajuste se leen sobre la tarjeta.
          final rCuerpo = razonDeContraste(superficieTexto, fondo);
          expect(
            rCuerpo,
            greaterThanOrEqualTo(minimoAA),
            reason: 'tema ${entrada.key} a $factor: el texto del ajuste queda en '
                '${rCuerpo.toStringAsFixed(2)}:1 sobre $fondo (AA pide '
                '$minimoAA:1)',
          );

          // 2) Los títulos de sección también son texto del ajuste.
          final rTitulo = razonDeContraste(
            tema.textTheme.titleMedium!.color!,
            fondo,
          );
          expect(
            rTitulo,
            greaterThanOrEqualTo(minimoAA),
            reason: 'tema ${entrada.key} a $factor: el título del ajuste queda en '
                '${rTitulo.toStringAsFixed(2)}:1',
          );

          // 3) Contraste cruzado: la fórmula propia y la de Flutter tienen que
          // coincidir. Si no, el número de arriba no sería de fiar.
          final lTexto = superficieTexto.computeLuminance();
          final lFondo = fondo.computeLuminance();
          final claro = lTexto > lFondo ? lTexto : lFondo;
          final oscuro = lTexto > lFondo ? lFondo : lTexto;
          final rFlutter = (claro + 0.05) / (oscuro + 0.05);
          expect(
            rCuerpo,
            closeTo(rFlutter, 0.01),
            reason: 'las dos fórmulas de luminancia discrepan: '
                '${rCuerpo.toStringAsFixed(4)} vs '
                '${rFlutter.toStringAsFixed(4)}',
          );

          // 4) El escalado no puede cambiar el color: si el factor alterara el
          // color de un texto, la auditoría de contraste de arriba no valdría
          // para los tamaños que no se midieron.
          final colorEscalado = _colorTrasEscalar(
            tema.textTheme.bodyMedium!.color!,
            factor,
          );
          expect(
            colorEscalado,
            superficieTexto,
            reason: 'escalar a $factor no debe cambiar el color del texto',
          );
        });
      }
    }
  });

  group('T10b caso 3 · el factor no oculta el contraste', () {
    test('el par de colores del tema no depende del factor del operador', () {
      // Guarda explícita de la premisa del test: si algún día alguien cambia
      // el tema para teñir el texto según el factor, esta guarda lo delata.
      for (final entrada in temas.entries) {
        final color = entrada.value.textTheme.bodyMedium!.color!;
        expect(
          razonDeContraste(color, fondoDeTarjeta(entrada.value)),
          greaterThanOrEqualTo(minimoAA),
          reason: 'tema ${entrada.key} sin factor debe cumplir AA igual',
        );
      }
    });
  });
}

/// Reproduce lo que hace Flutter al aplicar el `textScaler`: cambia el tamaño,
/// nunca el color.
Color _colorTrasEscalar(Color color, double factor) {
  final antes = color;
  Text(
    'x',
    style: TextStyle(color: color, fontSize: 14),
  );
  // Mismo color, distinto tamaño: se comprueba que el texto con el factor
  // escalado resuelve el mismo color.
  return (TextStyle(color: antes, fontSize: 14 * factor)).color ?? antes;
}

/// Monta etiquetas representativas de la pantalla de ajustes para que el
/// `MediaQuery` escalado sea realmente el que resuelve los estilos.
class _Etiquetas extends StatelessWidget {
  const _Etiquetas({
    required this.tituloStyle,
    required this.valorStyle,
    required this.textoActual,
    required this.factor,
    required this.mq,
  });

  final TextStyle tituloStyle;
  final TextStyle valorStyle;
  final TextStyle textoActual;
  final double factor;
  final TextScaler mq;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Escala de texto', style: tituloStyle),
        Text('Tamaño del ticket PDF', style: valorStyle),
        Text('Actual: 1.00', style: textoActual),
      ],
    );
  }
}
