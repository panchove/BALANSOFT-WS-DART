import '../../core/utils/num_parser.dart';

class Marca {
  final String id;
  final String nombre;
  final String? logoUrl;

  const Marca({
    required this.id,
    required this.nombre,
    this.logoUrl,
  });

  factory Marca.fromJson(Map<String, dynamic> json) => Marca(
        id: '${json['id_marca']}',
        nombre: json['nombre'],
        logoUrl: json['logo_url'],
      );

  Map<String, dynamic> toJson() => {
        'id_marca': id,
        'nombre': nombre,
        'logo_url': logoUrl,
      };

  @override
  String toString() => nombre;
}

class ModeloCamion {
  final String id;
  final String? marcaId;
  final String nombre;
  final double? capacidadCargaTon;
  final String? fotoReferencialUrl;
  final int? ejes;

  const ModeloCamion({
    required this.id,
    this.marcaId,
    required this.nombre,
    this.capacidadCargaTon,
    this.fotoReferencialUrl,
    this.ejes,
  });

  factory ModeloCamion.fromJson(Map<String, dynamic> json) => ModeloCamion(
        id: '${json['id_modelo_camion']}',
        marcaId: json['marca_id'] != null ? '${json['marca_id']}' : null,
        nombre: json['nombre'],
        capacidadCargaTon:
            NumParser.toDoubleOrNull(json['capacidad_carga_ton']),
        fotoReferencialUrl: json['foto_referencial_url'],
        ejes: json['ejes'],
      );

  Map<String, dynamic> toJson() => {
        'id_modelo_camion': id,
        'marca_id': marcaId,
        'nombre': nombre,
        'capacidad_carga_ton': capacidadCargaTon,
        'foto_referencial_url': fotoReferencialUrl,
        'ejes': ejes,
      };

  @override
  String toString() => nombre;
}

class Camion {
  final String id;
  final String placa;
  final String? modeloId;
  final String? transporteId;
  final String? color;
  final String? fotoRealUrl;
  final double? taraHabitual;
  final bool activo;

  const Camion({
    required this.id,
    required this.placa,
    this.modeloId,
    this.transporteId,
    this.color,
    this.fotoRealUrl,
    this.taraHabitual,
    this.activo = true,
  });

  factory Camion.fromJson(Map<String, dynamic> json) => Camion(
        id: '${json['id']}',
        placa: json['placa'],
        modeloId: json['modelo_id'] != null ? '${json['modelo_id']}' : null,
        transporteId:
            json['transporte_id'] != null ? '${json['transporte_id']}' : null,
        color: json['color'],
        fotoRealUrl: json['foto_real_url'],
        taraHabitual: NumParser.toDoubleOrNull(json['tara_habitual']),
        activo: json['activo'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'placa': placa,
        'modelo_id': modeloId,
        'transporte_id': transporteId,
        'color': color,
        'foto_real_url': fotoRealUrl,
        'tara_habitual': taraHabitual,
        'activo': activo,
      };

  @override
  String toString() => '$placa${color != null ? ' - $color' : ''}';
}

class Trailer {
  final String id;
  final String placa;
  final String? tipo;
  final double? taraHabitual;
  final String? fotoUrl;
  final bool activo;

  const Trailer({
    required this.id,
    required this.placa,
    this.tipo,
    this.taraHabitual,
    this.fotoUrl,
    this.activo = true,
  });

  factory Trailer.fromJson(Map<String, dynamic> json) => Trailer(
        id: '${json['id_remolque']}',
        placa: json['placa'],
        tipo: json['tipo_remolque'],
        taraHabitual: NumParser.toDoubleOrNull(json['tara_habitual']),
        fotoUrl: json['foto_url'],
        activo: json['activo'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id_remolque': id,
        'placa': placa,
        'tipo_remolque': tipo,
        'tara_habitual': taraHabitual,
        'foto_url': fotoUrl,
        'activo': activo,
      };

  @override
  String toString() =>
      '$placa${tipo != null ? ' ($tipo)' : ''}${taraHabitual != null ? ' - Tara ${taraHabitual}kg' : ''}';
}

class Transport {
  final String id;
  final String? codigo;
  final String razonSocial;
  final String? identificacionFiscal;
  final String? telefono;
  final String? contacto;
  final bool activo;

  const Transport({
    required this.id,
    this.codigo,
    required this.razonSocial,
    this.identificacionFiscal,
    this.telefono,
    this.contacto,
    this.activo = true,
  });

  factory Transport.fromJson(Map<String, dynamic> json) => Transport(
        id: '${json['id_transporte']}',
        codigo: json['codigo'],
        razonSocial: json['razon_social'],
        identificacionFiscal: json['identificacion_fiscal'],
        telefono: json['telefono'],
        contacto: json['contacto'],
        activo: json['activo'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id_transporte': id,
        'codigo': codigo,
        'razon_social': razonSocial,
        'identificacion_fiscal': identificacionFiscal,
        'telefono': telefono,
        'contacto': contacto,
        'activo': activo,
      };

  String get etiqueta => codigo != null ? '$codigo - $razonSocial' : razonSocial;

  @override
  String toString() => etiqueta;
}

class Driver {
  final String cedulaDni;
  final String nombreCompleto;
  final String? telefono;
  final String? licenciaConducir;
  final String? fotoUrl;
  final bool activo;

  const Driver({
    required this.cedulaDni,
    required this.nombreCompleto,
    this.telefono,
    this.licenciaConducir,
    this.fotoUrl,
    this.activo = true,
  });

  factory Driver.fromJson(Map<String, dynamic> json) => Driver(
        cedulaDni: '${json['cedula_dni']}',
        nombreCompleto: json['nombre_completo'],
        telefono: json['telefono'],
        licenciaConducir: json['licencia_conducir'],
        fotoUrl: json['foto_url'],
        activo: json['activo'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'cedula_dni': cedulaDni,
        'nombre_completo': nombreCompleto,
        'telefono': telefono,
        'licencia_conducir': licenciaConducir,
        'foto_url': fotoUrl,
        'activo': activo,
      };

  @override
  String toString() => '$nombreCompleto ($cedulaDni)';
}

class Product {
  final String id;
  final String? codigo;
  final String nombre;
  final String? descripcion;
  final double? densidadEstandar;
  final String unidadMedida;
  final bool activo;
  final bool esKardex;
  final double? tolerancia;
  final double? pesoUnidad;

  const Product({
    required this.id,
    this.codigo,
    required this.nombre,
    this.descripcion,
    this.densidadEstandar,
    this.unidadMedida = 'TON',
    this.activo = true,
    this.esKardex = false,
    this.tolerancia,
    this.pesoUnidad,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: '${json['id_producto']}',
        codigo: json['codigo'],
        nombre: json['nombre'],
        descripcion: json['descripcion'],
        densidadEstandar: NumParser.toDoubleOrNull(json['densidad_estandar']),
        unidadMedida: json['unidad_medida'] ?? 'TON',
        activo: json['activo'] ?? true,
        esKardex: json['es_kardex'] ?? false,
        tolerancia: NumParser.toDoubleOrNull(json['tolerancia']),
        pesoUnidad: NumParser.toDoubleOrNull(json['peso_unidad']),
      );

  Map<String, dynamic> toJson() => {
        'id_producto': id,
        'codigo': codigo,
        'nombre': nombre,
        'descripcion': descripcion,
        'densidad_estandar': densidadEstandar,
        'unidad_medida': unidadMedida,
        'activo': activo,
        'es_kardex': esKardex,
        'tolerancia': tolerancia,
        'peso_unidad': pesoUnidad,
      };

  String get etiqueta => codigo != null ? '$codigo - $nombre' : nombre;
  double? get densidadTonelada =>
      densidadEstandar != null ? densidadEstandar! / 1000 : null;

  @override
  String toString() => etiqueta;
}

class Warehouse {
  final String id;
  final String? codigo;
  final String nombre;
  final String? ubicacion;
  final double? capacidadMaxTon;
  final double stockActualTon;
  final bool activo;

  const Warehouse({
    required this.id,
    this.codigo,
    required this.nombre,
    this.ubicacion,
    this.capacidadMaxTon,
    this.stockActualTon = 0,
    this.activo = true,
  });

  factory Warehouse.fromJson(Map<String, dynamic> json) => Warehouse(
        id: '${json['id_almacen']}',
        codigo: json['codigo'],
        nombre: json['nombre'],
        ubicacion: json['ubicacion'],
        capacidadMaxTon: NumParser.toDoubleOrNull(json['capacidad_max_ton']),
        stockActualTon: NumParser.toDouble(json['stock_actual_ton']),
        activo: json['activo'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id_almacen': id,
        'codigo': codigo,
        'nombre': nombre,
        'ubicacion': ubicacion,
        'capacidad_max_ton': capacidadMaxTon,
        'stock_actual_ton': stockActualTon,
        'activo': activo,
      };

  String get etiqueta => codigo != null ? '$codigo - $nombre' : nombre;

  @override
  String toString() => etiqueta;
}

class Scale {
  final String id;
  final String descripcion;
  final String? codigo;
  final String? marca;
  final String? modelo;
  final double? capacidadMax;
  final double? division;
  final bool activo;
  final bool isSimulada;
  final String? puertoCom;
  final String? ipAddress;
  final int? puertoTcp;
  final String protocolo;

  const Scale({
    required this.id,
    required this.descripcion,
    this.codigo,
    this.marca,
    this.modelo,
    this.capacidadMax,
    this.division,
    this.activo = true,
    this.isSimulada = false,
    this.puertoCom,
    this.ipAddress,
    this.puertoTcp,
    this.protocolo = 'tcp',
  });

  factory Scale.fromJson(Map<String, dynamic> json) => Scale(
        id: '${json['id_balanza']}',
        descripcion: json['descripcion'],
        codigo: json['codigo'],
        marca: json['marca'],
        modelo: json['modelo'],
        capacidadMax: NumParser.toDoubleOrNull(json['capacidad_max']),
        division: NumParser.toDoubleOrNull(json['division']),
        activo: json['activo'] ?? true,
        isSimulada: json['is_simulada'] ?? false,
        puertoCom: json['puerto_com'],
        ipAddress: json['ip_address'],
        puertoTcp: (json['puerto_tcp'] as num?)?.toInt(),
        protocolo: json['protocolo'] ?? 'tcp',
      );

  Map<String, dynamic> toJson() => {
        'id_balanza': id,
        'descripcion': descripcion,
        'codigo': codigo,
        'marca': marca,
        'modelo': modelo,
        'capacidad_max': capacidadMax,
        'division': division,
        'activo': activo,
        'is_simulada': isSimulada,
        'puerto_com': puertoCom,
        'ip_address': ipAddress,
        'puerto_tcp': puertoTcp,
        'protocolo': protocolo,
      };

  String get etiqueta => codigo != null ? '$codigo - $descripcion' : descripcion;

  /// Ej.: `TCP 192.168.0.50:5555` o `SERIAL /dev/ttyUSB0`.
  String get configuracionHardware {
    if (protocolo == 'serial') {
      return puertoCom != null && puertoCom!.isNotEmpty
          ? 'SERIAL $puertoCom'
          : 'SERIAL sin puerto';
    }
    if (ipAddress != null && ipAddress!.isNotEmpty) {
      return 'TCP $ipAddress:${puertoTcp ?? 5555}';
    }
    return 'Sin configuración';
  }

  bool get tieneHardware =>
      (puertoCom != null && puertoCom!.isNotEmpty) ||
      (ipAddress != null && ipAddress!.isNotEmpty);

  @override
  String toString() => etiqueta;
}

/// Resultado de la prueba de conexión de una balanza (`/balanzas/{id}/probar`).
class PruebaConexion {
  final String balanza;
  final bool conectado;
  final String? hardware;
  final String? protocolo;
  final double? pesoKg;
  final bool estable;
  final String? detalle;

  const PruebaConexion({
    required this.balanza,
    required this.conectado,
    this.hardware,
    this.protocolo,
    this.pesoKg,
    this.estable = false,
    this.detalle,
  });

  factory PruebaConexion.fromJson(Map<String, dynamic> json) => PruebaConexion(
        balanza: json['balanza'] ?? '',
        conectado: json['conectado'] ?? false,
        hardware: json['hardware'],
        protocolo: json['protocolo'],
        pesoKg: (json['peso_kg'] as num?)?.toDouble(),
        estable: json['estable'] ?? false,
        detalle: json['detalle'],
      );
}

class ThirdParty {
  final String id;
  final String? codigo;
  final String tipo;
  final String razonSocial;
  final String? identificacionFiscal;
  final String? direccion;
  final String? telefono;
  final String? email;
  final bool activo;

  const ThirdParty({
    required this.id,
    this.codigo,
    required this.tipo,
    required this.razonSocial,
    this.identificacionFiscal,
    this.direccion,
    this.telefono,
    this.email,
    this.activo = true,
  });

  bool matchesType(String? tipoFiltro) {
    if (tipoFiltro == null || tipoFiltro.isEmpty) return true;
    if (tipo == tipoFiltro) return true;
    if (tipo == 'AMBOS') return true;
    return false;
  }

  factory ThirdParty.fromJson(Map<String, dynamic> json) => ThirdParty(
        id: '${json['id_tercero']}',
        codigo: json['codigo'],
        tipo: json['tipo'],
        razonSocial: json['razon_social'],
        identificacionFiscal: json['identificacion_fiscal'],
        direccion: json['direccion'],
        telefono: json['telefono'],
        email: json['email'],
        activo: json['activo'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id_tercero': id,
        'codigo': codigo,
        'tipo': tipo,
        'razon_social': razonSocial,
        'identificacion_fiscal': identificacionFiscal,
        'direccion': direccion,
        'telefono': telefono,
        'email': email,
        'activo': activo,
      };

  String get etiqueta {
    final partes = <String>[razonSocial];
    if (codigo != null && codigo!.isNotEmpty) partes.add(codigo!);
    if (identificacionFiscal != null &&
        identificacionFiscal!.isNotEmpty) {
      partes.add(identificacionFiscal!);
    }
    return partes.join(' - ');
  }

  @override
  String toString() => etiqueta;
}

class CatalogData {
  final List<Camion> camiones;
  final List<Trailer> trailers;
  final List<Marca> marcas;
  final List<ModeloCamion> modelosCamion;
  final List<Transport> transports;
  final List<Driver> drivers;
  final List<Product> products;
  final List<Warehouse> warehouses;
  final List<Scale> scales;
  final List<ThirdParty> thirdParties;

  const CatalogData({
    this.camiones = const [],
    this.trailers = const [],
    this.marcas = const [],
    this.modelosCamion = const [],
    this.transports = const [],
    this.drivers = const [],
    this.products = const [],
    this.warehouses = const [],
    this.scales = const [],
    this.thirdParties = const [],
  });

  static const empty = CatalogData();

  bool get isEmpty =>
      camiones.isEmpty &&
      trailers.isEmpty &&
      marcas.isEmpty &&
      modelosCamion.isEmpty &&
      transports.isEmpty &&
      drivers.isEmpty &&
      products.isEmpty &&
      warehouses.isEmpty &&
      scales.isEmpty &&
      thirdParties.isEmpty;

  List<Camion> get camionesActivos => camiones.where((c) => c.activo).toList();

  List<Trailer> get trailersActivos =>
      trailers.where((t) => t.activo).toList();

  List<ThirdParty> tercerosPorTipo(String? tipo) =>
      thirdParties.where((t) => t.matchesType(tipo)).toList();

  Marca? marcaById(String id) {
    for (final m in marcas) {
      if (m.id == id) return m;
    }
    return null;
  }

  List<ModeloCamion> modelosByMarca(String? marcaId) =>
      modelosCamion.where((m) => m.marcaId == marcaId).toList();

  Camion? camionByPlaca(String placa) {
    for (final c in camiones) {
      if (c.placa.toUpperCase() == placa.toUpperCase()) return c;
    }
    return null;
  }

  Driver? driverByCedula(String cedula) {
    for (final d in drivers) {
      if (d.cedulaDni == cedula) return d;
    }
    return null;
  }
}