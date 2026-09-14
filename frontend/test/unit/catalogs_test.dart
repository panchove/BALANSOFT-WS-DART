import 'package:flutter_test/flutter_test.dart';
import 'package:balansoft_ws/domain/entities/catalogs.dart';

void main() {
  group('Product.fromJson', () {
    test('parsea densidad como string decimal', () {
      final p = Product.fromJson({
        'id_producto': 'p1',
        'codigo': 'CEM',
        'nombre': 'Cemento',
        'densidad_estandar': '1.6000',
        'unidad_medida': 'TON',
        'activo': true,
        'es_kardex': false,
        'tolerancia': '0.0500',
        'peso_unidad': '42.5000',
      });
      expect(p.densidadEstandar, 1.6);
      expect(p.tolerancia, 0.05);
      expect(p.pesoUnidad, 42.5);
      expect(p.densidadTonelada, 0.0016);
    });

    test('etiqueta usa codigo', () {
      final p = Product.fromJson({'id_producto': 'p1', 'codigo': 'CEM', 'nombre': 'Cemento'});
      expect(p.etiqueta, 'CEM - Cemento');
    });

    test('densidad nula no rompe densidadTonelada', () {
      final p = Product.fromJson({'id_producto': 'p1', 'nombre': 'X'});
      expect(p.densidadEstandar, isNull);
      expect(p.densidadTonelada, isNull);
    });
  });

  group('Marca.fromJson', () {
    test('parsea id como string', () {
      final m = Marca.fromJson({'id_marca': 'uuid-1', 'nombre': 'Kenworth'});
      expect(m.id, 'uuid-1');
      expect(m.nombre, 'Kenworth');
    });
  });

  group('Warehouse.fromJson', () {
    test('parsea stock y capacidad como string', () {
      final w = Warehouse.fromJson({
        'id_almacen': 'a1',
        'codigo': 'PA',
        'nombre': 'Planta A',
        'capacidad_max_ton': '100.00',
        'stock_actual_ton': '25.50',
      });
      expect(w.capacidadMaxTon, 100.0);
      expect(w.stockActualTon, 25.5);
    });
  });

  group('Scale (dispositivos)', () {
    test('fromJson parsea campos de hardware', () {
      final s = Scale.fromJson({
        'id_balanza': 'uuid-b1',
        'descripcion': 'Báscula 1',
        'ip_address': '192.168.0.50',
        'puerto_tcp': 5555,
        'protocolo': 'tcp',
        'activo': true,
      });
      expect(s.ipAddress, '192.168.0.50');
      expect(s.puertoTcp, 5555);
      expect(s.protocolo, 'tcp');
      expect(s.tieneHardware, isTrue);
      expect(s.configuracionHardware, 'TCP 192.168.0.50:5555');
    });

    test('fromJson serial sin hardware no rompe', () {
      final s = Scale.fromJson({
        'id_balanza': 'uuid-b2',
        'descripcion': 'Báscula 2',
        'protocolo': 'serial',
      });
      expect(s.puertoCom, isNull);
      expect(s.tieneHardware, isFalse);
      expect(s.configuracionHardware, 'SERIAL sin puerto');
    });

    test('toJson round-trip conserva hardware', () {
      final s = Scale.fromJson({
        'id_balanza': 'uuid-b3',
        'descripcion': 'Báscula 3',
        'puerto_com': '/dev/ttyUSB0',
        'protocolo': 'serial',
      });
      final mapa = s.toJson();
      expect(mapa['puerto_com'], '/dev/ttyUSB0');
      expect(mapa['protocolo'], 'serial');
    });
  });

  group('PruebaConexion.fromJson', () {
    test('parsea resultado exitoso', () {
      final p = PruebaConexion.fromJson({
        'balanza': 'B1',
        'conectado': true,
        'hardware': 'tcp',
        'protocolo': 'tcp',
        'peso_kg': 12345.5,
        'estable': true,
      });
      expect(p.conectado, isTrue);
      expect(p.pesoKg, 12345.5);
      expect(p.estable, isTrue);
      expect(p.hardware, 'tcp');
    });

    test('parsea desconectado', () {
      final p = PruebaConexion.fromJson({
        'balanza': 'B1',
        'conectado': false,
        'detalle': 'sin lectura',
      });
      expect(p.conectado, isFalse);
      expect(p.detalle, 'sin lectura');
    });
  });
}