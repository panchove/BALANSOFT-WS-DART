import 'package:balansoft_ws/core/constants/api_constants.dart';
import 'package:balansoft_ws/core/constants/catalog_resources.dart';
import 'package:flutter_test/flutter_test.dart';

/// Catálogo CONCEPTOS DE INVENTARIO (motivos de kardex, migración 029).
///
/// Lock-in del recurso CRUD: si alguien cambia el `clave`/`idKey`/rutas, la
/// pantalla deja de leer el catálogo del backend y el selector del ajuste se
/// queda sin opciones.
void main() {
  group('CatalogResource conceptos_inventario', () {
    final recurso = AppCatalogos.conceptoInventarioResource;

    test('apunta a las rutas del backend', () {
      expect(recurso.clave, 'conceptos_inventario');
      expect(recurso.listaPath, ApiConstants.conceptosInventario);
      expect(recurso.itemPath('c1'), ApiConstants.conceptoInventario('c1'));
      expect(recurso.idKey, 'id_concepto');
    });

    test('titula por nombre y subtitula con código y tipo', () {
      expect(
        recurso.tituloFila({'nombre': 'Merma por derrame'}),
        'Merma por derrame',
      );
      expect(
        recurso.subtituloFila!({
          'codigo': 'MER-01',
          'tipo_movimiento': 'despacho',
        }),
        'MER-01 · Despacho',
      );
      expect(
        recurso.subtituloFila!({'activo': false}),
        'Inactivo',
      );
      expect(recurso.subtituloFila!({}), isNull);
    });

    test('el tipo de movimiento se limita a los valores de la BD', () {
      final campo = recurso.campos.firstWhere(
        (c) => c.key == 'tipo_movimiento',
      );
      expect(campo.opciones, ['ingreso', 'despacho', 'ajuste', 'ambos']);
      expect(campo.opcionLabels, ['Ingreso', 'Despacho', 'Ajuste', 'Ambos']);
    });

    test('el nombre es obligatorio', () {
      final campo = recurso.campos.firstWhere((c) => c.key == 'nombre');
      expect(campo.requerido, isTrue);
    });
  });
}
