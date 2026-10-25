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
  /// Formato de la trama en el cable: `auto` | `json` | `ascii` (migración 022).
  final String formatoTrama;
  /// Velocidad serial (solo aplica a `serial`).
  final int baudrate;
  /// Separador de trama: `lf` | `cr` | `crlf` | `stx_etx` (NULL = `lf`).
  final String? delimitador;

  /// Indicador (terminal de peso) asignado, o `null` si aún no se ha enlazado
  /// (migración 028: la báscula física y el indicador son entidades separadas).
  final String? idIndicador;

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
    this.formatoTrama = 'auto',
    this.baudrate = 9600,
    this.delimitador,
    this.idIndicador,
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
        formatoTrama: (json['formato_trama'] as String?) ?? 'auto',
        baudrate: (json['baudrate'] as num?)?.toInt() ?? 9600,
        delimitador: json['delimitador'] as String?,
        idIndicador: json['id_indicador'] == null
            ? null
            : '${json['id_indicador']}',
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
        'formato_trama': formatoTrama,
        'baudrate': baudrate,
        'delimitador': delimitador,
        'id_indicador': idIndicador,
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

/// Semáforo de pesaje (dispositivo actuador de salida, `docs/SEMAFORO.md`).
///
/// Un semáforo **no mide: obedece**. La app decide el LED a partir del peso en
/// vivo de la báscula vinculada (`id_balanza`) y del estado del boleto; el
/// `SemaforoController` del backend mantiene viva esa decisión. Desde esta
/// entidad solo se configura el canal (HTTP/REST o USB serie), se vincula la
/// báscula, se activa el control automático y se prueban luces manualmente.
class Semaforo {
  final String id;
  final String descripcion;
  final String? codigo;
  final bool activo;
  final bool isSimulado;
  final String protocolo;
  final String? ipAddress;
  final int? puertoTcp;
  final String? puertoCom;
  final int baudrate;
  final String? idBalanza;
  final bool controlAutomatico;
  final double? umbralCeroKg;

  const Semaforo({
    required this.id,
    required this.descripcion,
    this.codigo,
    this.activo = true,
    this.isSimulado = false,
    this.protocolo = 'http',
    this.ipAddress,
    this.puertoTcp,
    this.puertoCom,
    this.baudrate = 9600,
    this.idBalanza,
    this.controlAutomatico = false,
    this.umbralCeroKg,
  });

  factory Semaforo.fromJson(Map<String, dynamic> json) => Semaforo(
        id: '${json['id_semaforo']}',
        descripcion: json['descripcion'] ?? '',
        codigo: json['codigo'],
        activo: json['activo'] ?? true,
        isSimulado: json['is_simulado'] ?? false,
        protocolo: json['protocolo'] ?? 'http',
        ipAddress: json['ip_address'],
        puertoTcp: (json['puerto_tcp'] as num?)?.toInt(),
        puertoCom: json['puerto_com'],
        baudrate: (json['baudrate'] as num?)?.toInt() ?? 9600,
        idBalanza: json['id_balanza'] != null ? '${json['id_balanza']}' : null,
        controlAutomatico: json['control_automatico'] ?? false,
        umbralCeroKg: NumParser.toDoubleOrNull(json['umbral_cero_kg']),
      );

  Map<String, dynamic> toJson() => {
        'id_semaforo': id,
        'descripcion': descripcion,
        'codigo': codigo,
        'activo': activo,
        'is_simulado': isSimulado,
        'protocolo': protocolo,
        'ip_address': ipAddress,
        'puerto_tcp': puertoTcp,
        'puerto_com': puertoCom,
        'baudrate': baudrate,
        'id_balanza': idBalanza,
        'control_automatico': controlAutomatico,
        'umbral_cero_kg': umbralCeroKg,
      };

  String get etiqueta => codigo != null ? '$codigo - $descripcion' : descripcion;

  /// Ej.: `HTTP 127.0.0.1:8080` o `SERIAL /dev/bsdd_semaforo_acm`.
  String get configuracionHardware {
    if (protocolo == 'serial') {
      return puertoCom != null && puertoCom!.isNotEmpty
          ? 'SERIAL $puertoCom'
          : 'SERIAL sin puerto';
    }
    if (ipAddress != null && ipAddress!.isNotEmpty) {
      return 'HTTP $ipAddress:${puertoTcp ?? 8080}';
    }
    return 'Sin configuración';
  }

  bool get tieneHardware =>
      (puertoCom != null && puertoCom!.isNotEmpty) ||
      (ipAddress != null && ipAddress!.isNotEmpty);

  @override
  String toString() => etiqueta;
}

/// Resultado de la prueba de conexión de un semáforo (`/semaforos/{id}/probar`).
class PruebaSemaforo {
  final String semaforo;
  final bool conectado;
  final String? protocolo;
  final Map<String, dynamic>? estado;
  final String? detalle;

  const PruebaSemaforo({
    required this.semaforo,
    required this.conectado,
    this.protocolo,
    this.estado,
    this.detalle,
  });

  factory PruebaSemaforo.fromJson(Map<String, dynamic> json) => PruebaSemaforo(
        semaforo: json['semaforo'] ?? '',
        conectado: json['conectado'] ?? false,
        protocolo: json['protocolo'],
        estado: json['estado'] is Map
            ? Map<String, dynamic>.from(json['estado'] as Map)
            : null,
        detalle: json['detalle'],
      );
}

/// Estado de un semáforo (`/semaforos/{id}/estado`): lo que publica el equipo
/// más la fase/luces que decide la app.
class EstadoSemaforo {
  final String semaforo;
  final bool conectado;
  final bool automatico;
  final Map<String, dynamic>? estado;
  final String? fase;
  final Map<String, dynamic>? luces;
  final String? detalle;

  const EstadoSemaforo({
    required this.semaforo,
    required this.conectado,
    this.automatico = false,
    this.estado,
    this.fase,
    this.luces,
    this.detalle,
  });

  factory EstadoSemaforo.fromJson(Map<String, dynamic> json) => EstadoSemaforo(
        semaforo: json['semaforo'] ?? '',
        conectado: json['conectado'] ?? false,
        automatico: json['automatico'] ?? false,
        estado: json['estado'] is Map
            ? Map<String, dynamic>.from(json['estado'] as Map)
            : null,
        fase: json['fase'],
        luces: json['luces'] is Map
            ? Map<String, dynamic>.from(json['luces'] as Map)
            : null,
        detalle: json['detalle'],
      );
}

/// Cámara de captura de placa (snapshot HTTP/JPEG).
///
/// Dispositivo gemelo de [Scale]/[Semaforo]: **no** decide nada, solo entrega
/// la imagen. `ubicacion` indica en qué momento se la usa (entrada/salida/ambos)
/// y las fotos de placa se piden **una sola vez por boleto**.
class Camara {
  final String id;
  final String descripcion;
  final String? codigo;
  final String? marca;
  final String? modelo;
  final String? fabricante;
  final String? porDonde;
  final bool activo;
  final bool isSimulada;
  /// `ip` (snapshot por red) o `local` (USB/integrada del equipo).
  final String origen;
  final String urlSnapshot;
  /// Ruta/nombre del dispositivo para [origen] `local` (ej. `/dev/video0`).
  final String? dispositivo;
  final String? usuario;
  final String ubicacion;
  final bool passwordConfigurada;

  const Camara({
    required this.id,
    required this.descripcion,
    this.codigo,
    this.marca,
    this.modelo,
    this.fabricante,
    this.porDonde,
    this.activo = true,
    this.isSimulada = false,
    this.origen = 'ip',
    required this.urlSnapshot,
    this.dispositivo,
    this.usuario,
    this.ubicacion = 'ambos',
    this.passwordConfigurada = false,
  });

  factory Camara.fromJson(Map<String, dynamic> json) => Camara(
        id: '${json['id_camara']}',
        descripcion: json['descripcion'] ?? '',
        codigo: json['codigo'],
        marca: json['marca'],
        modelo: json['modelo'],
        fabricante: json['fabricante'],
        porDonde: json['por_donde'],
        activo: json['activo'] ?? true,
        isSimulada: json['is_simulada'] ?? false,
        origen: json['origen'] ?? 'ip',
        urlSnapshot: json['url_snapshot'] ?? '',
        dispositivo: json['dispositivo'],
        usuario: json['usuario'],
        ubicacion: json['ubicacion'] ?? 'ambos',
        passwordConfigurada: json['password_configurada'] ?? false,
      );

  Map<String, dynamic> toJson() => {
        'descripcion': descripcion,
        'codigo': codigo,
        'marca': marca,
        'modelo': modelo,
        'fabricante': fabricante,
        'activo': activo,
        'is_simulada': isSimulada,
        'origen': origen,
        'url_snapshot': urlSnapshot,
        'dispositivo': dispositivo,
        'usuario': usuario,
        'ubicacion': ubicacion,
      };

  String get etiqueta => codigo != null ? '$codigo - $descripcion' : descripcion;

  /// True si es una cámara USB/integrada del equipo.
  bool get esLocal => origen == 'local';

  /// Vía de detección legible (ej. "USB (/dev/video0)" o "Red IP").
  String get porDondeLegible {
    if (porDonde != null && porDonde!.isNotEmpty) return porDonde!;
    if (esLocal) {
      return (dispositivo != null && dispositivo!.isNotEmpty)
          ? 'USB ($dispositivo)'
          : 'USB / Local';
    }
    return urlSnapshot.isNotEmpty ? 'Red IP ($urlSnapshot)' : 'Red IP';
  }

  /// Marca o fabricante legible para la interfaz.
  String get marcaFabricanteLegible {
    final m = (marca ?? '').trim();
    final f = (fabricante ?? '').trim();
    if (m.isNotEmpty && f.isNotEmpty && m != f) return '$m ($f)';
    if (m.isNotEmpty) return m;
    if (f.isNotEmpty) return f;
    return 'Genérica';
  }

  /// `entrada`, `salida` o `ambos` — en qué momento se usa la cámara.
  String get ubicacionLegible => switch (ubicacion) {
        'entrada' => 'Entrada',
        'salida' => 'Salida',
        _ => 'Entrada y salida',
      };

  @override
  String toString() => etiqueta;
}

/// Cámara detectada por el escaneo (`GET /camaras/descubrir`).
///
/// Es un candidato **sin persistir**: la UI deduplica y registra los nuevos.
class CamaraDescubierta {
  final String descripcion;
  final String origen;
  final String urlSnapshot;
  final String? dispositivo;
  final String? marca;
  final String? modelo;
  final String? fabricante;
  final String? porDonde;
  final String ubicacion;
  final bool isSimulada;
  final String? detalle;

  const CamaraDescubierta({
    required this.descripcion,
    this.origen = 'ip',
    this.urlSnapshot = '',
    this.dispositivo,
    this.marca,
    this.modelo,
    this.fabricante,
    this.porDonde,
    this.ubicacion = 'ambos',
    this.isSimulada = false,
    this.detalle,
  });

  factory CamaraDescubierta.fromJson(Map<String, dynamic> json) => CamaraDescubierta(
        descripcion: json['descripcion'] ?? '',
        origen: json['origen'] ?? 'ip',
        urlSnapshot: json['url_snapshot'] ?? '',
        dispositivo: json['dispositivo'],
        marca: json['marca'],
        modelo: json['modelo'],
        fabricante: json['fabricante'],
        porDonde: json['por_donde'],
        ubicacion: json['ubicacion'] ?? 'ambos',
        isSimulada: json['is_simulada'] ?? false,
        detalle: json['detalle'],
      );

  bool get esLocal => origen == 'local';

  String get porDondeLegible {
    if (porDonde != null && porDonde!.isNotEmpty) return porDonde!;
    if (esLocal) {
      return (dispositivo != null && dispositivo!.isNotEmpty)
          ? 'USB ($dispositivo)'
          : 'USB / Local';
    }
    return urlSnapshot.isNotEmpty ? 'Red IP ($urlSnapshot)' : 'Red IP';
  }

  String get marcaFabricanteLegible {
    final m = (marca ?? '').trim();
    final f = (fabricante ?? '').trim();
    if (m.isNotEmpty && f.isNotEmpty && m != f) return '$m ($f)';
    if (m.isNotEmpty) return m;
    if (f.isNotEmpty) return f;
    return 'Genérica';
  }

  /// Cuerpo para `POST /camaras` al auto-registrar una cámara descubierta.
  Map<String, dynamic> toCamaraCreateBody({String? ubicacionElegida, bool? activo}) => {
        'descripcion': descripcion,
        'origen': origen,
        'url_snapshot': urlSnapshot,
        'dispositivo': dispositivo,
        'marca': marca,
        'modelo': modelo,
        'fabricante': fabricante,
        'ubicacion': ubicacionElegida ?? ubicacion,
        'is_simulada': isSimulada,
        'activo': activo ?? true,
      };
}

/// Resultado de la prueba de conexión de una cámara (`/camaras/{id}/probar`).
class PruebaCamara {
  final String camara;
  final bool conectado;
  final String? detalle;
  final int? ancho;
  final int? alto;
  final double? tamanoKb;

  const PruebaCamara({
    required this.camara,
    required this.conectado,
    this.detalle,
    this.ancho,
    this.alto,
    this.tamanoKb,
  });

  factory PruebaCamara.fromJson(Map<String, dynamic> json) => PruebaCamara(
        camara: json['camara'] ?? '',
        conectado: json['conectado'] ?? false,
        detalle: json['detalle'],
        ancho: (json['ancho'] as num?)?.toInt(),
        alto: (json['alto'] as num?)?.toInt(),
        tamanoKb: NumParser.toDoubleOrNull(json['tamano_kb']),
      );
}

/// Indicador (terminal) de peso, separado de la báscula física.
///
/// El terminal que muestra y transmite el peso (BKG LP7510, CAS C12001A,
/// Transcell TI500E, AND AD431, Cardinal UMC555, Toledo T4321, …) es una
/// entidad propia desde la migración 028: la configuración de comunicación
/// (protocolo, puerto/ip, formato de trama, baudrate y delimitador) son
/// propiedades del *terminal*, no de la plataforma de pesaje. El ADMIN decide
/// qué indicador va con qué báscula desde [Scale.idIndicador].
class Indicador {
  final String id;
  final String descripcion;
  final String? codigo;
  final String? marca;
  final String? modelo;
  final bool activo;
  final bool isSimulado;
  final String protocolo;
  final String? puertoCom;
  final String? ipAddress;
  final int? puertoTcp;
  /// Formato de la trama en el cable: `auto` | `json` | `ascii`.
  final String formatoTrama;
  /// Velocidad serial (solo aplica a `serial`).
  final int baudrate;
  /// Separador de trama: `lf` | `cr` | `crlf` | `stx_etx` (NULL = `lf`).
  final String? delimitador;
  /// Cuántas básculas físicas lo tienen enlazado (lo calcula el backend).
  final int balanzasEnlazadas;

  const Indicador({
    required this.id,
    required this.descripcion,
    this.codigo,
    this.marca,
    this.modelo,
    this.activo = true,
    this.isSimulado = false,
    this.protocolo = 'tcp',
    this.puertoCom,
    this.ipAddress,
    this.puertoTcp,
    this.formatoTrama = 'auto',
    this.baudrate = 9600,
    this.delimitador,
    this.balanzasEnlazadas = 0,
  });

  factory Indicador.fromJson(Map<String, dynamic> json) => Indicador(
        id: '${json['id_indicador']}',
        descripcion: json['descripcion'] ?? '',
        codigo: json['codigo'],
        marca: json['marca'],
        modelo: json['modelo'],
        activo: json['activo'] ?? true,
        isSimulado: json['is_simulado'] ?? false,
        protocolo: json['protocolo'] ?? 'tcp',
        puertoCom: json['puerto_com'],
        ipAddress: json['ip_address'],
        puertoTcp: (json['puerto_tcp'] as num?)?.toInt(),
        formatoTrama: (json['formato_trama'] as String?) ?? 'auto',
        baudrate: (json['baudrate'] as num?)?.toInt() ?? 9600,
        delimitador: json['delimitador'] as String?,
        balanzasEnlazadas: (json['balanzas_enlazadas'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'descripcion': descripcion,
        'codigo': codigo,
        'marca': marca,
        'modelo': modelo,
        'activo': activo,
        'is_simulado': isSimulado,
        'protocolo': protocolo,
        'puerto_com': puertoCom,
        'ip_address': ipAddress,
        'puerto_tcp': puertoTcp,
        'formato_trama': formatoTrama,
        'baudrate': baudrate,
        'delimitador': delimitador,
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

/// Barrera de tránsito (actuador de salida: abrir/cerrar paso vehicular).
///
/// Dispositivo gemelo de [Semaforo]: **no mide nada**, solo recibe órdenes
/// de abrir o cerrar el brazo. `ubicacion` indica si controla la entrada,
/// la salida o ambos accesos. `control_automatico` deja que la app decida
/// cuándo abrir (ej. al cerrar un boleto CERRADO) o cerrar (ej. tras paso
/// de vehículo).
class Barrera {
  final String id;
  final String descripcion;
  final String? codigo;
  final bool activo;
  final bool isSimulado;
  final String protocolo; // 'http' | 'serial'
  final String? ipAddress;
  final int? puertoTcp;
  final String? puertoCom;
  final int baudrate;
  final String? ubicacion; // 'entrada' | 'salida' | 'ambos'
  final bool controlAutomatico;
  final int tiempoEsperaSegundos; // segundos que permanece abierta

  const Barrera({
    required this.id,
    required this.descripcion,
    this.codigo,
    this.activo = true,
    this.isSimulado = false,
    this.protocolo = 'http',
    this.ipAddress,
    this.puertoTcp,
    this.puertoCom,
    this.baudrate = 9600,
    this.ubicacion = 'ambos',
    this.controlAutomatico = false,
    this.tiempoEsperaSegundos = 5,
  });

  factory Barrera.fromJson(Map<String, dynamic> json) => Barrera(
        id: '${json['id_barrera']}',
        descripcion: json['descripcion'] ?? '',
        codigo: json['codigo'],
        activo: json['activo'] ?? true,
        isSimulado: json['is_simulado'] ?? false,
        protocolo: json['protocolo'] ?? 'http',
        ipAddress: json['ip_address'],
        puertoTcp: (json['puerto_tcp'] as num?)?.toInt(),
        puertoCom: json['puerto_com'],
        baudrate: (json['baudrate'] as num?)?.toInt() ?? 9600,
        ubicacion: json['ubicacion'] ?? 'ambos',
        controlAutomatico: json['control_automatico'] ?? false,
        tiempoEsperaSegundos: (json['tiempo_espera_segundos'] as num?)?.toInt() ?? 5,
      );

  Map<String, dynamic> toJson() => {
        'descripcion': descripcion,
        'codigo': codigo,
        'activo': activo,
        'is_simulado': isSimulado,
        'protocolo': protocolo,
        'ip_address': ipAddress,
        'puerto_tcp': puertoTcp,
        'puerto_com': puertoCom,
        'baudrate': baudrate,
        'ubicacion': ubicacion,
        'control_automatico': controlAutomatico,
        'tiempo_espera_segundos': tiempoEsperaSegundos,
      };

  String get etiqueta => codigo != null ? '$codigo - $descripcion' : descripcion;

  /// Ej.: `HTTP 127.0.0.1:8082` o `SERIAL /dev/ttyUSB1`.
  String get configuracionHardware {
    if (protocolo == 'serial') {
      return puertoCom != null && puertoCom!.isNotEmpty
          ? 'SERIAL $puertoCom'
          : 'SERIAL sin puerto';
    }
    if (ipAddress != null && ipAddress!.isNotEmpty) {
      return 'HTTP $ipAddress:${puertoTcp ?? 8082}';
    }
    return 'Sin configuración';
  }

  bool get tieneHardware =>
      (puertoCom != null && puertoCom!.isNotEmpty) ||
      (ipAddress != null && ipAddress!.isNotEmpty);

  /// `entrada`, `salida` o `ambos`.
  String get ubicacionLegible => switch (ubicacion) {
        'entrada' => 'Entrada',
        'salida' => 'Salida',
        _ => 'Entrada y salida',
      };

  @override
  String toString() => etiqueta;
}

/// Resultado de la prueba de conexión de una barrera (`/barreras/{id}/probar`).
class PruebaBarrera {
  final String barrera;
  final bool conectado;
  final String? protocolo;
  final Map<String, dynamic>? estado;
  final String? detalle;

  const PruebaBarrera({
    required this.barrera,
    required this.conectado,
    this.protocolo,
    this.estado,
    this.detalle,
  });

  factory PruebaBarrera.fromJson(Map<String, dynamic> json) => PruebaBarrera(
        barrera: json['barrera'] ?? '',
        conectado: json['conectado'] ?? false,
        protocolo: json['protocolo'],
        estado: json['estado'] is Map
            ? Map<String, dynamic>.from(json['estado'] as Map)
            : null,
        detalle: json['detalle'],
      );
}

/// Estado de una barrera (`/barreras/{id}/estado`).
class EstadoBarrera {
  final String barrera;
  final bool conectado;
  final bool automatico;
  final String? estado; // 'abierta' | 'cerrada' | 'abriendo' | 'cerrando' | 'error'
  final Map<String, dynamic>? detalle;

  const EstadoBarrera({
    required this.barrera,
    required this.conectado,
    this.automatico = false,
    this.estado,
    this.detalle,
  });

  factory EstadoBarrera.fromJson(Map<String, dynamic> json) => EstadoBarrera(
        barrera: json['barrera'] ?? '',
        conectado: json['conectado'] ?? false,
        automatico: json['automatico'] ?? false,
        estado: json['estado'],
        detalle: json['detalle'] is Map
            ? Map<String, dynamic>.from(json['detalle'] as Map)
            : null,
      );

  /// True si la barrera permite paso (abierta o abriendo).
  bool get permitePaso => estado == 'abierta' || estado == 'abriendo';
}

/// Barrera detectada por el escaneo (`GET /barreras/descubrir`).
class BarreraDescubierta {
  final String descripcion;
  final String origen; // 'ip' | 'serial'
  final String? ipAddress;
  final int? puertoTcp;
  final String? puertoCom;
  final String? marca;
  final String? modelo;
  final String? detalle;
  final bool isSimulado;

  const BarreraDescubierta({
    required this.descripcion,
    this.origen = 'ip',
    this.ipAddress,
    this.puertoTcp,
    this.puertoCom,
    this.marca,
    this.modelo,
    this.detalle,
    this.isSimulado = false,
  });

  factory BarreraDescubierta.fromJson(Map<String, dynamic> json) => BarreraDescubierta(
        descripcion: json['descripcion'] ?? '',
        origen: json['origen'] ?? 'ip',
        ipAddress: json['ip_address'],
        puertoTcp: (json['puerto_tcp'] as num?)?.toInt(),
        puertoCom: json['puerto_com'],
        marca: json['marca'],
        modelo: json['modelo'],
        detalle: json['detalle'],
        isSimulado: json['is_simulado'] ?? false,
      );

  String get configuracionLegible {
    if (origen == 'serial') {
      return 'SERIAL ${puertoCom ?? 'sin puerto'}';
    }
    return 'HTTP ${ipAddress ?? 'sin IP'}:${puertoTcp ?? 8082}';
  }

  /// Cuerpo para `POST /barreras` al auto-registrar una barrera descubierta.
  Map<String, dynamic> toBarreraCreateBody({String? ubicacionElegida, bool? activo}) => {
        'descripcion': descripcion,
        'protocolo': origen,
        'ip_address': ipAddress,
        'puerto_tcp': puertoTcp,
        'puerto_com': puertoCom,
        'ubicacion': ubicacionElegida ?? 'ambos',
        'is_simulado': isSimulado,
        'activo': activo ?? true,
        'baudrate': 9600,
      };
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