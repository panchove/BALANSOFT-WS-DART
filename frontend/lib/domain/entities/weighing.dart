import '../../core/utils/num_parser.dart';

class Weighing {
  final String boleto;
  final String? idVehiculo;
  final bool remolque;
  final String? idRemolque;
  final String? idTransporte;
  final String? idConductor;
  final String? idProducto;
  final String? idAlmacen;
  final String? idBalanza;
  final String? tipoTercero;
  final String? idTercero;
  final bool multiDespachoRecepcion;
  final DateTime fechaHoraEntrada;
  final double pesoEntradaVehiculo;
  final double? pesoEntradaRemolque;
  final DateTime? fechaHoraSalida;
  final double? pesoSalidaVehiculo;
  final double? pesoSalidaRemolque;
  final double? pesoBruto;
  final double? pesoTara;
  final double? pesoNeto;
  final double? pesoNetoDeclarado;
  final double? pesoDiferencia;
  final double? porcentajeDesviacion;
  final double? diferenciaPeso;
  final double? porcentajeDiferencia;
  final double? densidad;
  final double? litros;
  final double? unidades;
  final String? documento;
  final String? flete;
  final double? costoFlete;
  final String? observaciones;
  final String? numeroBoleto;
  final String? motivoAnulacion;
  final String estadoBoleto;
  final bool sincronizado;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Weighing({
    required this.boleto,
    this.idVehiculo,
    this.remolque = false,
    this.idRemolque,
    this.idTransporte,
    this.idConductor,
    this.idProducto,
    this.idAlmacen,
    this.idBalanza,
    this.tipoTercero,
    this.idTercero,
    this.multiDespachoRecepcion = false,
    required this.fechaHoraEntrada,
    required this.pesoEntradaVehiculo,
    this.pesoEntradaRemolque,
    this.fechaHoraSalida,
    this.pesoSalidaVehiculo,
    this.pesoSalidaRemolque,
    this.pesoBruto,
    this.pesoTara,
    this.pesoNeto,
    this.pesoNetoDeclarado,
    this.pesoDiferencia,
    this.porcentajeDesviacion,
    this.diferenciaPeso,
    this.porcentajeDiferencia,
    this.densidad,
    this.litros,
    this.unidades,
    this.documento,
    this.flete,
    this.costoFlete,
    this.observaciones,
    this.numeroBoleto,
    this.motivoAnulacion,
    this.estadoBoleto = 'PENDIENTE',
    this.sincronizado = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isOpen =>
      estadoBoleto == 'PENDIENTE' || estadoBoleto == 'MODIFICADO';
  bool get isClosed => estadoBoleto == 'CERRADO';
  bool get isAnulado => estadoBoleto == 'ANULADO';
  bool get isPendingSync => !sincronizado;

  double get pesoTotalEntrada =>
      pesoEntradaVehiculo + (pesoEntradaRemolque ?? 0);
  double? get pesoTotalSalida =>
      pesoSalidaVehiculo != null
          ? pesoSalidaVehiculo! + (pesoSalidaRemolque ?? 0)
          : null;

  factory Weighing.fromJson(Map<String, dynamic> json) => Weighing(
        boleto: json['boleto'],
        idVehiculo: json['id_vehiculo'],
        remolque: json['remolque'] ?? false,
        idRemolque: json['id_remolque'],
        idTransporte: json['id_transporte'],
        idConductor: json['id_conductor'],
        idProducto: json['id_producto'],
        idAlmacen: json['id_almacen'],
        idBalanza: json['id_balanza'],
        tipoTercero: json['tipo_tercero'],
        idTercero: json['id_tercero'],
        multiDespachoRecepcion: json['multi_despacho_recepcion'] ?? false,
        fechaHoraEntrada: DateTime.parse(json['fecha_hora_entrada']),
        pesoEntradaVehiculo: NumParser.toDouble(json['peso_entrada_vehiculo']),
        pesoEntradaRemolque: NumParser.toDoubleOrNull(json['peso_entrada_remolque']),
        fechaHoraSalida: json['fecha_hora_salida'] != null
            ? DateTime.parse(json['fecha_hora_salida'])
            : null,
        pesoSalidaVehiculo: NumParser.toDoubleOrNull(json['peso_salida_vehiculo']),
        pesoSalidaRemolque: NumParser.toDoubleOrNull(json['peso_salida_remolque']),
        pesoBruto: NumParser.toDoubleOrNull(json['peso_bruto']),
        pesoTara: NumParser.toDoubleOrNull(json['peso_tara']),
        pesoNeto: NumParser.toDoubleOrNull(json['peso_neto']),
        pesoNetoDeclarado: NumParser.toDoubleOrNull(json['peso_neto_declarado']),
        pesoDiferencia: NumParser.toDoubleOrNull(json['peso_diferencia']),
        porcentajeDesviacion: NumParser.toDoubleOrNull(json['porcentaje_desviacion']),
        diferenciaPeso: NumParser.toDoubleOrNull(json['diferencia_peso']),
        porcentajeDiferencia:
            NumParser.toDoubleOrNull(json['porcentaje_diferencia']),
        densidad: NumParser.toDoubleOrNull(json['densidad']),
        litros: NumParser.toDoubleOrNull(json['litros']),
        unidades: NumParser.toDoubleOrNull(json['unidades']),
        documento: json['documento'],
        flete: json['flete'],
        costoFlete: NumParser.toDoubleOrNull(json['costo_flete']),
        observaciones: json['observaciones'],
        numeroBoleto: json['numero_boleto'],
        motivoAnulacion: json['motivo_anulacion'],
        estadoBoleto: json['estado_boleto'] ?? 'PENDIENTE',
        sincronizado: json['sincronizado'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
        updatedAt: DateTime.parse(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'boleto': boleto,
        'id_vehiculo': idVehiculo,
        'remolque': remolque,
        'id_remolque': idRemolque,
        'id_transporte': idTransporte,
        'id_conductor': idConductor,
        'id_producto': idProducto,
        'id_almacen': idAlmacen,
        'id_balanza': idBalanza,
        'tipo_tercero': tipoTercero,
        'id_tercero': idTercero,
        'multi_despacho_recepcion': multiDespachoRecepcion,
        'fecha_hora_entrada': fechaHoraEntrada.toIso8601String(),
        'peso_entrada_vehiculo': pesoEntradaVehiculo,
        'peso_entrada_remolque': pesoEntradaRemolque,
        'fecha_hora_salida': fechaHoraSalida?.toIso8601String(),
        'peso_salida_vehiculo': pesoSalidaVehiculo,
        'peso_salida_remolque': pesoSalidaRemolque,
        'peso_bruto': pesoBruto,
        'peso_tara': pesoTara,
        'peso_neto': pesoNeto,
        'peso_neto_declarado': pesoNetoDeclarado,
        'peso_diferencia': pesoDiferencia,
        'porcentaje_desviacion': porcentajeDesviacion,
        'diferencia_peso': diferenciaPeso,
        'porcentaje_diferencia': porcentajeDiferencia,
        'densidad': densidad,
        'litros': litros,
        'unidades': unidades,
        'documento': documento,
        'flete': flete,
        'costo_flete': costoFlete,
        'observaciones': observaciones,
        'numero_boleto': numeroBoleto,
        'motivo_anulacion': motivoAnulacion,
        'estado_boleto': estadoBoleto,
        'sincronizado': sincronizado,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  Weighing copyWith({
    String? boleto,
    String? idVehiculo,
    bool? remolque,
    String? idRemolque,
    String? idTransporte,
    String? idConductor,
    String? idProducto,
    String? idAlmacen,
    String? idBalanza,
    String? tipoTercero,
    String? idTercero,
    bool? multiDespachoRecepcion,
    DateTime? fechaHoraEntrada,
    double? pesoEntradaVehiculo,
    double? pesoEntradaRemolque,
    DateTime? fechaHoraSalida,
    double? pesoSalidaVehiculo,
    double? pesoSalidaRemolque,
    double? pesoBruto,
    double? pesoTara,
    double? pesoNeto,
    double? pesoNetoDeclarado,
    double? pesoDiferencia,
    double? porcentajeDesviacion,
    double? diferenciaPeso,
    double? porcentajeDiferencia,
    double? densidad,
    double? litros,
    double? unidades,
    String? documento,
    String? flete,
    double? costoFlete,
    String? observaciones,
    String? numeroBoleto,
    String? motivoAnulacion,
    String? estadoBoleto,
    bool? sincronizado,
  }) =>
      Weighing(
        boleto: boleto ?? this.boleto,
        idVehiculo: idVehiculo ?? this.idVehiculo,
        remolque: remolque ?? this.remolque,
        idRemolque: idRemolque ?? this.idRemolque,
        idTransporte: idTransporte ?? this.idTransporte,
        idConductor: idConductor ?? this.idConductor,
        idProducto: idProducto ?? this.idProducto,
        idAlmacen: idAlmacen ?? this.idAlmacen,
        idBalanza: idBalanza ?? this.idBalanza,
        tipoTercero: tipoTercero ?? this.tipoTercero,
        idTercero: idTercero ?? this.idTercero,
        multiDespachoRecepcion:
            multiDespachoRecepcion ?? this.multiDespachoRecepcion,
        fechaHoraEntrada: fechaHoraEntrada ?? this.fechaHoraEntrada,
        pesoEntradaVehiculo: pesoEntradaVehiculo ?? this.pesoEntradaVehiculo,
        pesoEntradaRemolque: pesoEntradaRemolque ?? this.pesoEntradaRemolque,
        fechaHoraSalida: fechaHoraSalida ?? this.fechaHoraSalida,
        pesoSalidaVehiculo: pesoSalidaVehiculo ?? this.pesoSalidaVehiculo,
        pesoSalidaRemolque: pesoSalidaRemolque ?? this.pesoSalidaRemolque,
        pesoBruto: pesoBruto ?? this.pesoBruto,
        pesoTara: pesoTara ?? this.pesoTara,
        pesoNeto: pesoNeto ?? this.pesoNeto,
        pesoNetoDeclarado: pesoNetoDeclarado ?? this.pesoNetoDeclarado,
        pesoDiferencia: pesoDiferencia ?? this.pesoDiferencia,
        porcentajeDesviacion:
            porcentajeDesviacion ?? this.porcentajeDesviacion,
        diferenciaPeso: diferenciaPeso ?? this.diferenciaPeso,
        porcentajeDiferencia:
            porcentajeDiferencia ?? this.porcentajeDiferencia,
        densidad: densidad ?? this.densidad,
        litros: litros ?? this.litros,
        unidades: unidades ?? this.unidades,
        documento: documento ?? this.documento,
        flete: flete ?? this.flete,
        costoFlete: costoFlete ?? this.costoFlete,
        observaciones: observaciones ?? this.observaciones,
        numeroBoleto: numeroBoleto ?? this.numeroBoleto,
        motivoAnulacion: motivoAnulacion ?? this.motivoAnulacion,
        estadoBoleto: estadoBoleto ?? this.estadoBoleto,
        sincronizado: sincronizado ?? this.sincronizado,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
