import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:balansoft_ws/frontend/lib/core/utils/arranque_estacion.dart';

void main() {
  group('destinoSegunEstadoEstacion', () {
    test('sin empresa y arrancando en el login manda al asistente', () {
      expect(
        destinoSegunEstadoEstacion(configurada: false, rutaActual: rutaLogin),
        rutaSetup,
      );
    });

    test('sin empresa pero ya en el asistente no navega', () {
      expect(
        destinoSegunEstadoEstacion(configurada: false, rutaActual: rutaSetup),
        isNull,
      );
    });

    test('con empresa y arrancando en el login no navega', () {
      expect(
        destinoSegunEstadoEstacion(configurada: true, rutaActual: rutaLogin),
        isNull,
      );
    });

    test('con empresa pero en el asistente se le lleva al login', () {
      // El asistente respondería 409 al crear el ADMIN: no tiene salida.
      expect(
        destinoSegunEstadoEstacion(configurada: true, rutaActual: rutaSetup),
        rutaLogin,
      );
    });

    test('estado desconocido no mueve al usuario de donde está', () {
      expect(
        destinoSegunEstadoEstacion(configurada: null, rutaActual: rutaLogin),
        isNull,
      );
      expect(
        destinoSegunEstadoEstacion(configurada: null, rutaActual: rutaSetup),
        isNull,
      );
    });

    test('las rutas del contrato coinciden con las de MaterialApp', () {
      // Si alguien renombra las rutas del router, este test lo delata.
      expect(rutaLogin, '/login');
      expect(rutaSetup, '/setup');
    });
  });
}