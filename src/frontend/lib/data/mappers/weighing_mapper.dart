import '../../core/utils/num_parser.dart';
import '../../domain/entities/weighing.dart';

class WeighingMapper {
  static Map<String, dynamic> toMap(Weighing weighing) {
    return weighing.toJson();
  }

  static Weighing fromMap(Map<String, dynamic> map) {
    return Weighing.fromJson(map);
  }

  static Weighing fromLocalDb(Map<String, dynamic> map) {
    return Weighing(
      boleto: map['boleto'],
      idVehiculo: map['id_vehiculo'],
      remolque: map['remolque'] == 1,
      idTransporte: map['id_transporte'],
      idConductor: map['id_conductor'],
      idProducto: map['id_producto'],
      idAlmacen: map['id_almacen'],
      idBalanza: map['id_balanza'],
      tipoTercero: map['tipo_tercero'],
      idTercero: map['id_tercero'],
      multiDespachoRecepcion: map['multi_despacho_recepcion'] == 1,
      fechaHoraEntrada: DateTime.parse(map['fecha_hora_entrada']),
      pesoEntradaVehiculo: NumParser.toDouble(map['peso_entrada_vehiculo']),
      pesoEntradaRemolque: NumParser.toDoubleOrNull(map['peso_entrada_remolque']),
      fechaHoraSalida: map['fecha_hora_salida'] != null
          ? DateTime.parse(map['fecha_hora_salida'])
          : null,
      pesoSalidaVehiculo: NumParser.toDoubleOrNull(map['peso_salida_vehiculo']),
      pesoSalidaRemolque: NumParser.toDoubleOrNull(map['peso_salida_remolque']),
      pesoBruto: NumParser.toDoubleOrNull(map['peso_bruto']),
      pesoTara: NumParser.toDoubleOrNull(map['peso_tara']),
      pesoNeto: NumParser.toDoubleOrNull(map['peso_neto']),
      pesoNetoDeclarado: NumParser.toDoubleOrNull(map['peso_neto_declarado']),
      pesoDiferencia: NumParser.toDoubleOrNull(map['peso_diferencia']),
      porcentajeDesviacion: NumParser.toDoubleOrNull(map['porcentaje_desviacion']),
      diferenciaPeso: NumParser.toDoubleOrNull(map['diferencia_peso']),
      porcentajeDiferencia: NumParser.toDoubleOrNull(map['porcentaje_diferencia']),
      densidad: NumParser.toDoubleOrNull(map['densidad']),
      litros: NumParser.toDoubleOrNull(map['litros']),
      unidades: NumParser.toDoubleOrNull(map['unidades']),
      documento: map['documento'],
      flete: map['flete'],
      observaciones: map['observaciones'],
      numeroBoleto: map['numero_boleto'],
      motivoAnulacion: map['motivo_anulacion'],
      estadoBoleto: map['estado_boleto'] ?? 'PENDIENTE',
      sincronizado: map['sincronizado'] == 1,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  static Map<String, dynamic> toLocalDb(Weighing weighing) {
    return {
      'boleto': weighing.boleto,
      'id_vehiculo': weighing.idVehiculo,
      'remolque': weighing.remolque ? 1 : 0,
      'id_transporte': weighing.idTransporte,
      'id_conductor': weighing.idConductor,
      'id_producto': weighing.idProducto,
      'id_almacen': weighing.idAlmacen,
      'id_balanza': weighing.idBalanza,
      'tipo_tercero': weighing.tipoTercero,
      'id_tercero': weighing.idTercero,
      'multi_despacho_recepcion': weighing.multiDespachoRecepcion ? 1 : 0,
      'fecha_hora_entrada': weighing.fechaHoraEntrada.toIso8601String(),
      'peso_entrada_vehiculo': weighing.pesoEntradaVehiculo,
      'peso_entrada_remolque': weighing.pesoEntradaRemolque,
      'fecha_hora_salida': weighing.fechaHoraSalida?.toIso8601String(),
      'peso_salida_vehiculo': weighing.pesoSalidaVehiculo,
      'peso_salida_remolque': weighing.pesoSalidaRemolque,
      'peso_bruto': weighing.pesoBruto,
      'peso_tara': weighing.pesoTara,
      'peso_neto': weighing.pesoNeto,
      'peso_neto_declarado': weighing.pesoNetoDeclarado,
      'peso_diferencia': weighing.pesoDiferencia,
      'porcentaje_desviacion': weighing.porcentajeDesviacion,
      'diferencia_peso': weighing.diferenciaPeso,
      'porcentaje_diferencia': weighing.porcentajeDiferencia,
      'densidad': weighing.densidad,
      'litros': weighing.litros,
      'unidades': weighing.unidades,
      'flete': weighing.flete,
      'documento': weighing.documento,
      'observaciones': weighing.observaciones,
      'numero_boleto': weighing.numeroBoleto,
      'motivo_anulacion': weighing.motivoAnulacion,
      'estado_boleto': weighing.estadoBoleto,
      'sincronizado': weighing.sincronizado ? 1 : 0,
      'created_at': weighing.createdAt.toIso8601String(),
      'updated_at': weighing.updatedAt.toIso8601String(),
    };
  }
}
