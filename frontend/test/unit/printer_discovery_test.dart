import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/services/printer_discovery.dart';

/// Pruebas de la detección de impresoras **reales**.
///
/// El contrato es que la lista jamás muestre impresoras virtuales
/// (PDF/XPS/OneNote…): esos casos deben filtrarse y las físicas conservar
/// su nombre, incluso con espacios.
void main() {
  group('esImpresoraVirtual', () {
    test('las impresoras virtuales de Windows se descartan', () {
      expect(PrinterDiscovery.esImpresoraVirtual('Microsoft Print to PDF'),
          isTrue);
      expect(PrinterDiscovery.esImpresoraVirtual('Microsoft XPS Document Writer'),
          isTrue);
      expect(
          PrinterDiscovery
              .esImpresoraVirtual('Microsoft XPS Document Writer v3'),
          isTrue);
      expect(PrinterDiscovery.esImpresoraVirtual('OneNote (Desktop)'), isTrue);
      expect(PrinterDiscovery.esImpresoraVirtual('Microsoft Fax'), isTrue);
      expect(PrinterDiscovery.esImpresoraVirtual('Adobe PDF'), isTrue);
      expect(PrinterDiscovery.esImpresoraVirtual('CUPS-PDF'), isTrue);
      expect(PrinterDiscovery.esImpresoraVirtual('Mi impresora (CUPS-PDF)'),
          isTrue);
    });

    test('las impresoras físicas y de red no se descartan', () {
      expect(PrinterDiscovery.esImpresoraVirtual('HP LaserJet Pro M404dn'),
          isFalse);
      expect(PrinterDiscovery.esImpresoraVirtual('EPSON LX-350'), isFalse);
      expect(PrinterDiscovery.esImpresoraVirtual('Brother QL-800'), isFalse);
      expect(PrinterDiscovery.esImpresoraVirtual('Samsung ML-2160'), isFalse);
      // Nombre con "PDF" pero puerto físico (driver del SO) no es virtual.
      expect(
          PrinterDiscovery.esImpresoraVirtual('PDF Creator HW', puerto: 'USB001'),
          isFalse);
    });

    test('el puerto decide cuando el nombre no es concluyente', () {
      expect(
          PrinterDiscovery.esImpresoraVirtual('Impresora 1', puerto: 'nul:'),
          isTrue);
      expect(
          PrinterDiscovery.esImpresoraVirtual('Impresora 1', puerto: 'FILE:'),
          isTrue);
      expect(PrinterDiscovery.esImpresoraVirtual('Impresora 1', puerto: 'file:'),
          isTrue);
      expect(
          PrinterDiscovery.esImpresoraVirtual('Impresora 1',
              puerto: 'cups-pdf:/out'),
          isTrue);
      expect(
          PrinterDiscovery.esImpresoraVirtual('Impresora 1',
              puerto: 'PORTPROMPT:'),
          isFalse);
      expect(
          PrinterDiscovery.esImpresoraVirtual('Impresora 1', puerto: 'LPT1:'),
          isFalse);
      expect(
          PrinterDiscovery.esImpresoraVirtual('Impresora 1', puerto: 'USB001'),
          isFalse);
      // Puerto vacío no debe descartar la impresora.
      expect(PrinterDiscovery.esImpresoraVirtual('Impresora 1', puerto: ''),
          isFalse);
    });

    test('mayúsculas y minúsculas no cambian el resultado', () {
      expect(
          PrinterDiscovery.esImpresoraVirtual('MICROSOFT PRINT TO PDF'), isTrue);
      expect(PrinterDiscovery.esImpresoraVirtual('hp laserjet', puerto: 'nul:'),
          isTrue);
      expect(PrinterDiscovery.esImpresoraVirtual('hp laserjet', puerto: 'usb001'),
          isFalse);
    });
  });

  group('parseLpstat', () {
    test('conserva los nombres con espacios (CUPS)', () {
      const salida = '''
device for HP LaserJet 1020: usb://HP/LaserJet_1020?serial=ABC123
device for EPSON LX-350: lpd://192.168.1.50/EPSON
device for Samsung ML-2160: usb://Samsung/ML-2160
''';
      final impresoras = PrinterDiscovery.parseLpstat(salida);

      expect(impresoras, hasLength(3));
      expect(impresoras[0].name, 'HP LaserJet 1020');
      expect(impresoras[1].name, 'EPSON LX-350');
      expect(impresoras[2].name, 'Samsung ML-2160');
      expect(
          impresoras.map((p) => p.connection).toList(),
          ['USB', 'RED', 'USB']);
      expect(impresoras[0].metadata['uri'],
          'usb://HP/LaserJet_1020?serial=ABC123');
    });

    test('ignora líneas que no son dispositivos', () {
      const salida = '''
device for Impresora Local: usb://X/Y
no default destination
device for : usb://Z
''';
      final impresoras = PrinterDiscovery.parseLpstat(salida);
      expect(impresoras, hasLength(1));
      expect(impresoras.single.name, 'Impresora Local');
    });

    test('acepta fin de línea CRLF y salida vacía', () {
      expect(PrinterDiscovery.parseLpstat(''), isEmpty);
      expect(
          PrinterDiscovery.parseLpstat(
              'device for HP: usb://HP/1\r\ndevice for EPSON: usb://E/2\r\n'),
          hasLength(2));
    });

    test('una impresora virtual de CUPS queda marcada como PDF', () {
      final impresoras = PrinterDiscovery.parseLpstat(
          'device for CUPS-PDF: cups-pdf:/tmp/out.pdf');
      expect(impresoras.single.connection, 'PDF');
      expect(
          PrinterDiscovery.esImpresoraVirtual(impresoras.single.name,
              puerto: impresoras.single.metadata['uri'] as String?),
          isTrue,
          reason: 'CUPS-PDF no debe llegar a la lista de impresoras reales');
    });
  });

  group('parseWindowsJson', () {
    test('UNA sola impresora viene como objeto suelto y se normaliza', () {
      const salida =
          '{"Name":"HP LaserJet Pro M404dn","DriverName":"HP Universal",'
          '"PortName":"USB001","Default":true,"Network":false}';
      final impresoras = PrinterDiscovery.parseWindowsJson(salida);

      expect(impresoras, hasLength(1),
          reason: 'ConvertTo-Json emite un objeto (no arreglo) con 1 impresora');
      expect(impresoras.single.name, 'HP LaserJet Pro M404dn');
      expect(impresoras.single.driver, 'HP Universal');
      expect(impresoras.single.connection, 'USB');
      expect(impresoras.single.isDefault, isTrue);
    });

    test('varias impresoras vienen como arreglo', () {
      const salida = '''
      [
        {"Name":"EPSON LX-350","DriverName":"Epson ESC/P","PortName":"LPT1:","Default":false,"Network":false},
        {"Name":"HP LaserJet","DriverName":"HP","PortName":"IP_192.168.1.50","Default":true,"Network":true},
        {"Name":"Microsoft Print to PDF","DriverName":"Microsoft","PortName":"PORTPROMPT:","Default":false,"Network":false}
      ]
      ''';
      final impresoras = PrinterDiscovery.parseWindowsJson(salida);

      expect(impresoras, hasLength(3));
      expect(impresoras[0].connection, 'SERIAL');
      expect(impresoras[1].connection, 'RED');
      expect(impresoras[1].isDefault, isTrue);
      expect(impresoras[2].name, 'Microsoft Print to PDF');
      expect(impresoras[2].isDefault, isFalse);

      // `scan()` debe dejar fuera la virtual del resultado anterior.
      final reales = impresoras
          .where((p) =>
              !PrinterDiscovery.esImpresoraVirtual(p.name,
                  puerto: p.metadata['port'] as String?))
          .toList();
      expect(reales.map((p) => p.name), ['EPSON LX-350', 'HP LaserJet']);
    });

    test('sin driver conserva la impresora con «Desconocido»', () {
      const salida = '{"Name":"Impresora Rara","PortName":"USB003"}';
      final impresoras = PrinterDiscovery.parseWindowsJson(salida);
      expect(impresoras.single.driver, 'Desconocido');
      expect(impresoras.single.connection, 'USB');
      expect(impresoras.single.isDefault, isFalse);
    });

    test('salida corrupta o sin Name no lanza', () {
      expect(PrinterDiscovery.parseWindowsJson(''), isEmpty);
      expect(PrinterDiscovery.parseWindowsJson('no es json {'), isEmpty);
      expect(PrinterDiscovery.parseWindowsJson('null'), isEmpty);
      expect(PrinterDiscovery.parseWindowsJson('[{"PortName":"USB001"}]'),
          isEmpty);
    });
  });

  group('connectionTypeLabel', () {
    test('etiqueta legible de cada tipo', () {
      expect(PrinterDiscovery.connectionTypeLabel('USB'), 'USB');
      expect(PrinterDiscovery.connectionTypeLabel('SERIAL'), 'Serie (RS-232)');
      expect(PrinterDiscovery.connectionTypeLabel('RED'), 'Red (TCP/IP)');
      expect(PrinterDiscovery.connectionTypeLabel('PDF'), 'PDF / Virtual');
      expect(PrinterDiscovery.connectionTypeLabel('VIRTUAL'), 'Virtual');
      expect(PrinterDiscovery.connectionTypeLabel('OTRO'), 'OTRO');
      expect(PrinterDiscovery.connectionTypeLabel('usb'), 'USB',
          reason: 'la etiqueta no depende de mayúsculas');
    });
  });
}
