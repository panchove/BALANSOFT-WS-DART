// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import 'dart:convert';
import 'dart:io';

/// Representa una impresora descubierta en el sistema.
class DiscoveredPrinter {
  final String name;
  final String driver;
  final String connection; // USB, RED, SERIAL, PDF, VIRTUAL, OTRO
  final bool isDefault;
  final Map<String, dynamic> metadata;

  const DiscoveredPrinter({
    required this.name,
    required this.driver,
    required this.connection,
    this.isDefault = false,
    this.metadata = const {},
  });

  @override
  String toString() =>
      'DiscoveredPrinter(name: $name, connection: $connection, isDefault: $isDefault)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredPrinter &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          driver == other.driver &&
          connection == other.connection &&
          isDefault == other.isDefault;

  @override
  int get hashCode => Object.hash(name, driver, connection, isDefault);
}

/// Servicio para descubrir impresoras **reales** en el sistema (Windows/Linux).
///
/// Solo se listan impresoras físicas o de red instaladas en el equipo: las
/// impresoras virtuales (Microsoft Print to PDF, XPS, CUPS-PDF, OneNote…)
/// se descartan con [esImpresoraVirtual] para que la lista no muestre
/// "impresoras falsas" que no pueden imprimir un boleto en papel.
class PrinterDiscovery {
  PrinterDiscovery._();

  /// Escanea el sistema en busca de impresoras instaladas.
  ///
  /// En Windows usa WMI/CIM (`Win32_Printer`) vía PowerShell.
  /// En Linux usa CUPS (`lpstat -v`).
  /// Retorna lista vacía si no se pueden detectar o en otras plataformas.
  static Future<List<DiscoveredPrinter>> scan() async {
    List<DiscoveredPrinter> brutas;
    if (Platform.isWindows) {
      brutas = await _scanWindows();
    } else if (Platform.isLinux) {
      brutas = await _scanLinux();
    } else {
      return [];
    }
    return brutas
        .where((p) => !esImpresoraVirtual(p.name, puerto: p.metadata['port'] as String? ?? p.metadata['uri'] as String?))
        .toList();
  }

  /// ¿Es una impresora virtual (no física) que no debe aparecer en la lista?
  ///
  /// [puerto] es el puerto (Windows) o la URI CUPS (Linux) si se conoce.
  static bool esImpresoraVirtual(String nombre, {String? puerto}) {
    final n = nombre.toLowerCase();
    if (n.contains('print to pdf') ||
        n.contains('microsoft xps') ||
        n.contains('xps document writer') ||
        n.contains('onenote') ||
        n.contains('microsoft fax') ||
        n.contains('adobe pdf') ||
        n.contains('cups-pdf')) {
      return true;
    }
    if (puerto == null || puerto.isEmpty) return false;
    final p = puerto.toLowerCase();
    return p == 'nul:' ||
        p == 'file:' ||
        p.contains('cups-pdf') ||
        p.startsWith('file:') ||
        p.contains('pdf') && !p.contains('://');
  }

  /// Escanea impresoras en Windows usando CIM (PowerShell 5.1 y 7+) con
  /// fallback a `Get-WmiObject` (solo 5.1).
  static Future<List<DiscoveredPrinter>> _scanWindows() async {
    const comandos = [
      'Get-CimInstance Win32_Printer | Select-Object Name, DriverName, PortName, Default, Network | ConvertTo-Json -Depth 3 -Compress',
      'Get-WmiObject Win32_Printer | Select-Object Name, DriverName, PortName, Default, Network | ConvertTo-Json -Depth 3 -Compress',
    ];
    for (final comando in comandos) {
      try {
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          comando,
        ]).timeout(const Duration(seconds: 20));
        if (result.exitCode != 0) continue;
        final salida = result.stdout.toString().trim();
        if (salida.isEmpty) return [];
        return parseWindowsJson(salida);
      } catch (_) {
        // Timeout o PowerShell inaccesible → probar el siguiente comando.
      }
    }
    return [];
  }

  /// Convierte la salida de `ConvertTo-Json` en impresoras (pública para
  /// pruebas).
  ///
  /// `ConvertTo-Json` emite un objeto suelto `{…}` cuando hay UNA sola
  /// impresora y un arreglo `[{…}]` cuando hay varias: ambos casos se
  /// normalizan aquí.
  static List<DiscoveredPrinter> parseWindowsJson(String salida) {
    try {
      final dynamic decodificado = jsonDecode(salida);
      final List<dynamic> filas = decodificado is List
          ? decodificado
          : <dynamic>[decodificado];
      final impresoras = <DiscoveredPrinter>[];
      for (final p in filas) {
        if (p is! Map || p['Name'] == null) continue;
        impresoras.add(DiscoveredPrinter(
          name: p['Name'] as String,
          driver: (p['DriverName'] as String?) ?? 'Desconocido',
          connection: _detectConnectionTypeWindows(p['PortName'] as String?),
          isDefault: p['Default'] == true,
          metadata: {
            'port': p['PortName'],
            'network': p['Network'] == true,
          },
        ));
      }
      return impresoras;
    } catch (_) {
      return [];
    }
  }

  /// Escanea impresoras en Linux usando CUPS (`lpstat -v`).
  static Future<List<DiscoveredPrinter>> _scanLinux() async {
    try {
      final result = await Process.run('lpstat', ['-v']).timeout(
        const Duration(seconds: 10),
      );
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        return parseLpstat(result.stdout.toString());
      }
    } catch (_) {
      // lpstat ausente o CUPS no instalado → lista vacía.
    }
    return [];
  }

  /// Procesa la salida de `lpstat -v` (pública para pruebas).
  ///
  /// Formato: `device for NOMBRE: URI`, donde NOMBRE puede contener
  /// espacios (`device for HP LaserJet 1020: usb://…`).
  static List<DiscoveredPrinter> parseLpstat(String salida) {
    final impresoras = <DiscoveredPrinter>[];
    for (final linea in salida.split('\n')) {
      final i = linea.indexOf('device for ');
      if (i == -1) continue;
      final resto = linea.substring(i + 'device for '.length).trimRight();
      final j = resto.indexOf(': ');
      if (j <= 0) continue;
      final nombre = resto.substring(0, j).trim();
      final uri = resto.substring(j + 2).trim();
      if (nombre.isEmpty || uri.isEmpty) continue;
      impresoras.add(DiscoveredPrinter(
        name: nombre,
        driver: 'CUPS',
        connection: _detectConnectionTypeLinux(uri),
        metadata: {'uri': uri},
      ));
    }
    return impresoras;
  }

  /// Detecta el tipo de conexión en Windows basado en el puerto.
  static String _detectConnectionTypeWindows(String? port) {
    if (port == null) return 'DESCONOCIDO';
    final p = port.toLowerCase();
    if (p.contains('usb')) return 'USB';
    if (p.startsWith('com') || p.startsWith('lpt')) return 'SERIAL';
    if (p.startsWith('ip_') || p.startsWith('tcp') || p.contains('://')) {
      return 'RED';
    }
    if (p == 'file:' || p.contains('pdf') || p.contains('xps')) return 'PDF';
    if (p.startsWith('nul:')) return 'VIRTUAL';
    return 'OTRO';
  }

  /// Detecta el tipo de conexión en Linux basado en la URI de CUPS.
  static String _detectConnectionTypeLinux(String uri) {
    final u = uri.toLowerCase();
    if (u.startsWith('usb:')) return 'USB';
    if (u.startsWith('serial:') || u.startsWith('tty:')) return 'SERIAL';
    if (u.startsWith('socket:') ||
        u.startsWith('lpd:') ||
        u.startsWith('ipp:') ||
        u.startsWith('http:') ||
        u.startsWith('https:')) {
      return 'RED';
    }
    if (u.startsWith('file:') || u.contains('pdf') || u.contains('cups-pdf')) {
      return 'PDF';
    }
    if (u.startsWith('dnssd:') || u.startsWith('ipps:')) return 'RED';
    return 'OTRO';
  }

  /// Obtiene el nombre legible del tipo de conexión para UI.
  static String connectionTypeLabel(String type) {
    switch (type.toUpperCase()) {
      case 'USB':
        return 'USB';
      case 'SERIAL':
        return 'Serie (RS-232)';
      case 'RED':
        return 'Red (TCP/IP)';
      case 'PDF':
        return 'PDF / Virtual';
      case 'VIRTUAL':
        return 'Virtual';
      default:
        return type;
    }
  }
}
