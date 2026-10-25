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

    test('lee el indicador enlazado (migración 028)', () {
      final s = Scale.fromJson({
        'id_balanza': 'uuid-b4',
        'descripcion': 'Báscula 4',
        'id_indicador': 'uuid-i1',
      });
      expect(s.idIndicador, 'uuid-i1');
      expect(s.toJson()['id_indicador'], 'uuid-i1');

      final sinIndicador = Scale.fromJson({
        'id_balanza': 'uuid-b5',
        'descripcion': 'Báscula 5',
        'id_indicador': null,
      });
      expect(sinIndicador.idIndicador, isNull);
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

  group('Semaforo (dispositivos)', () {
    test('fromJson parsea canal HTTP y vínculo con la báscula', () {
      final s = Semaforo.fromJson({
        'id_semaforo': 'uuid-s1',
        'descripcion': 'Semáforo entrada',
        'protocolo': 'http',
        'ip_address': '127.0.0.1',
        'puerto_tcp': 8080,
        'id_balanza': 'uuid-b1',
        'control_automatico': true,
        'umbral_cero_kg': '5.0000',
        'is_simulado': true,
      });
      expect(s.id, 'uuid-s1');
      expect(s.ipAddress, '127.0.0.1');
      expect(s.puertoTcp, 8080);
      expect(s.idBalanza, 'uuid-b1');
      expect(s.controlAutomatico, isTrue);
      expect(s.umbralCeroKg, 5.0);
      expect(s.isSimulado, isTrue);
      expect(s.configuracionHardware, 'HTTP 127.0.0.1:8080');
    });

    test('fromJson serial sin puerto no rompe', () {
      final s = Semaforo.fromJson({
        'id_semaforo': 'uuid-s2',
        'descripcion': 'Semáforo serial',
        'protocolo': 'serial',
      });
      expect(s.puertoCom, isNull);
      expect(s.tieneHardware, isFalse);
      expect(s.configuracionHardware, 'SERIAL sin puerto');
      expect(s.controlAutomatico, isFalse);
    });

    test('toJson round-trip conserva el control automático', () {
      final s = Semaforo.fromJson({
        'id_semaforo': 'uuid-s3',
        'descripcion': 'Semáforo 3',
        'puerto_com': '/dev/bsdd_semaforo_acm',
        'protocolo': 'serial',
        'control_automatico': true,
        'umbral_cero_kg': 7.5,
      });
      final mapa = s.toJson();
      expect(mapa['puerto_com'], '/dev/bsdd_semaforo_acm');
      expect(mapa['control_automatico'], isTrue);
      expect(mapa['umbral_cero_kg'], 7.5);
      expect(s.configuracionHardware, 'SERIAL /dev/bsdd_semaforo_acm');
    });
  });

  group('PruebaSemaforo / EstadoSemaforo', () {
    test('PruebaSemaforo parsea el estado publicado por el equipo', () {
      final p = PruebaSemaforo.fromJson({
        'semaforo': 'S1',
        'conectado': true,
        'protocolo': 'http',
        'estado': {'fase': 'EXTERNO', 'zumbador': false},
        'detalle': 'Conexión correcta',
      });
      expect(p.conectado, isTrue);
      expect(p.estado?['fase'], 'EXTERNO');
    });

    test('EstadoSemaforo parsea fase y luces decididas por la app', () {
      final e = EstadoSemaforo.fromJson({
        'semaforo': 'S1',
        'conectado': true,
        'automatico': true,
        'fase': 'PESANDO',
        'luces': {
          'rojo': 'on',
          'amarillo': 'off',
          'verde': 'off',
          'zumbador': false,
        },
        'detalle': null,
      });
      expect(e.automatico, isTrue);
      expect(e.fase, 'PESANDO');
      expect(e.luces?['rojo'], 'on');
      expect(e.luces?['amarillo'], 'off');
    });

    test('EstadoSemaforo tolera luces y estado ausentes', () {
      final e = EstadoSemaforo.fromJson({
        'semaforo': 'S1',
        'conectado': false,
      });
      expect(e.luces, isNull);
      expect(e.estado, isNull);
      expect(e.fase, isNull);
    });
  });

  group('Camara (dispositivos)', () {
    test('parsea la configuración y no expone la contraseña', () {
      final c = Camara.fromJson({
        'id_camara': 'uuid-c1',
        'descripcion': 'Cámara entrada',
        'codigo': 'CAM-01',
        'url_snapshot': 'http://192.168.1.50/snapshot.cgi',
        'usuario': 'admin',
        'ubicacion': 'entrada',
        'is_simulada': true,
        'activo': true,
        'password_configurada': true,
      });
      expect(c.id, 'uuid-c1');
      expect(c.descripcion, 'Cámara entrada');
      expect(c.etiqueta, 'CAM-01 - Cámara entrada');
      expect(c.urlSnapshot, 'http://192.168.1.50/snapshot.cgi');
      expect(c.ubicacionLegible, 'Entrada');
      // El backend nunca devuelve la contraseña: solo si está configurada.
      expect(c.passwordConfigurada, isTrue);
      expect(c.toJson().containsKey('password'), isFalse);
    });

    test('campos ausentes toman los valores por defecto', () {
      final c = Camara.fromJson({
        'id_camara': 'uuid-c2',
        'descripcion': 'Sin código',
        'url_snapshot': 'http://10.0.0.9/snap',
      });
      expect(c.codigo, isNull);
      expect(c.etiqueta, 'Sin código');
      expect(c.ubicacion, 'ambos');
      expect(c.ubicacionLegible, 'Entrada y salida');
      expect(c.activo, isTrue);
      expect(c.passwordConfigurada, isFalse);
      // Sin `origen` la cámara es de red (compatibilidad con lo ya guardado).
      expect(c.origen, 'ip');
      expect(c.esLocal, isFalse);
      expect(c.dispositivo, isNull);
    });

    test('parsea una cámara local (USB/integrada)', () {
      final c = Camara.fromJson({
        'id_camara': 'uuid-c3',
        'descripcion': 'Webcam USB',
        'origen': 'local',
        'dispositivo': '/dev/video2',
        'url_snapshot': '',
        'ubicacion': 'ambos',
      });
      expect(c.origen, 'local');
      expect(c.esLocal, isTrue);
      expect(c.dispositivo, '/dev/video2');
      expect(c.urlSnapshot, isEmpty);
      // El origen viaja al backend al guardar.
      expect(c.toJson()['origen'], 'local');
      expect(c.toJson()['dispositivo'], '/dev/video2');
    });
  });

  group('CamaraDescubierta (escaneo)', () {
    test('parsea una cámara local detectada en el equipo', () {
      final d = CamaraDescubierta.fromJson({
        'descripcion': 'Integrated_Webcam_HD',
        'origen': 'local',
        'dispositivo': '/dev/video0',
        'url_snapshot': '',
        'ubicacion': 'ambos',
        'detalle': 'Cámara conectada a este equipo',
      });
      expect(d.esLocal, isTrue);
      expect(d.dispositivo, '/dev/video0');
      expect(d.detalle, isNotEmpty);
    });

    test('una cámara IP descubierta conserva su URL', () {
      final d = CamaraDescubierta.fromJson({
        'descripcion': 'IP registrada',
        'origen': 'ip',
        'url_snapshot': 'http://10.0.0.9/snap.jpg',
      });
      expect(d.esLocal, isFalse);
      expect(d.urlSnapshot, 'http://10.0.0.9/snap.jpg');
      expect(d.isSimulada, isFalse);
      expect(d.ubicacion, 'ambos');
    });

    test('el cuerpo de auto-registro lleva origen y dispositivo', () {
      final d = CamaraDescubierta.fromJson({
        'descripcion': 'Webcam USB',
        'origen': 'local',
        'dispositivo': '/dev/video2',
      });
      final body = d.toCamaraCreateBody();
      expect(body['origen'], 'local');
      expect(body['dispositivo'], '/dev/video2');
      expect(body['descripcion'], 'Webcam USB');
      expect(body['activo'], isTrue);
    });
  });

  group('PruebaCamara', () {
    test('parsea el resultado de la prueba de conexión', () {
      final p = PruebaCamara.fromJson({
        'camara': 'Cámara entrada',
        'conectado': true,
        'detalle': null,
        'ancho': 1920,
        'alto': 1080,
        'tamano_kb': 240.5,
      });
      expect(p.conectado, isTrue);
      expect(p.ancho, 1920);
      expect(p.alto, 1080);
      expect(p.tamanoKb, 240.5);
    });

    test('tolera una respuesta sin imagen', () {
      final p = PruebaCamara.fromJson({
        'camara': 'Cámara salida',
        'conectado': false,
        'detalle': 'La cámara no devolvió una imagen válida',
      });
      expect(p.conectado, isFalse);
      expect(p.ancho, isNull);
      expect(p.detalle, isNotEmpty);
    });
  });

  group('Indicador (dispositivos)', () {
    test('parsea el terminal y su configuración de comunicación', () {
      final i = Indicador.fromJson({
        'id_indicador': 'uuid-i1',
        'descripcion': 'Indicador entrada',
        'codigo': 'IND-01',
        'marca': 'Transcell',
        'modelo': 'TI500E',
        'protocolo': 'serial',
        'puerto_com': '/dev/ttyUSB0',
        'formato_trama': 'ascii',
        'baudrate': 19200,
        'delimitador': 'crlf',
        'balanzas_enlazadas': 1,
      });
      expect(i.id, 'uuid-i1');
      expect(i.etiqueta, 'IND-01 - Indicador entrada');
      expect(i.marca, 'Transcell');
      expect(i.modelo, 'TI500E');
      expect(i.configuracionHardware, 'SERIAL /dev/ttyUSB0');
      expect(i.baudrate, 19200);
      expect(i.delimitador, 'crlf');
      expect(i.balanzasEnlazadas, 1);
    });

    test('campos ausentes toman los valores por defecto', () {
      final i = Indicador.fromJson({
        'id_indicador': 'uuid-i2',
        'descripcion': 'Sin código',
      });
      expect(i.codigo, isNull);
      expect(i.etiqueta, 'Sin código');
      expect(i.protocolo, 'tcp');
      expect(i.formatoTrama, 'auto');
      expect(i.baudrate, 9600);
      expect(i.activo, isTrue);
      expect(i.balanzasEnlazadas, 0);
      expect(i.configuracionHardware, 'Sin configuración');
    });

    test('toJson round-trip conserva la configuración', () {
      final i = Indicador.fromJson({
        'id_indicador': 'uuid-i3',
        'descripcion': 'Indicador TCP',
        'ip_address': '10.0.0.9',
        'puerto_tcp': 5555,
        'protocolo': 'tcp',
      });
      final mapa = i.toJson();
      expect(mapa['ip_address'], '10.0.0.9');
      expect(mapa['puerto_tcp'], 5555);
      expect(mapa['protocolo'], 'tcp');
      // El id y el contador de básculas los gobierna el backend.
      expect(mapa.containsKey('id_indicador'), isFalse);
      expect(mapa.containsKey('balanzas_enlazadas'), isFalse);
    });
  });
}