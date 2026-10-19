/// Entidades del módulo de Reportes (REQ-FN-REP-*).
library;

/// Filtros comunes para los reportes del sistema.
class ReporteFiltro {
  final DateTime? fechaDesde;
  final DateTime? fechaHasta;
  final String? idProducto;
  final String? idAlmacen;
  final String? idVehiculo;
  final String? tipoTercero;

  const ReporteFiltro({
    this.fechaDesde,
    this.fechaHasta,
    this.idProducto,
    this.idAlmacen,
    this.idVehiculo,
    this.tipoTercero,
  });

  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{};
    if (fechaDesde != null) params['fecha_desde'] = _iso(fechaDesde!);
    if (fechaHasta != null) params['fecha_hasta'] = _iso(fechaHasta!);
    if (idProducto != null && idProducto!.isNotEmpty) params['id_producto'] = idProducto;
    if (idAlmacen != null && idAlmacen!.isNotEmpty) params['id_almacen'] = idAlmacen;
    if (idVehiculo != null && idVehiculo!.isNotEmpty) params['vehicle_id'] = idVehiculo;
    if (tipoTercero != null && tipoTercero!.isNotEmpty) params['tipo_tercero'] = tipoTercero;
    return params;
  }

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T00:00:00';
}

/// Resumen de totales para mostrar en un reporte.
class ReporteResumen {
  final int totalBoletos;
  final double totalPesoKg;
  final double totalPesoNeto;
  final String? periodo;

  const ReporteResumen({
    required this.totalBoletos,
    required this.totalPesoKg,
    required this.totalPesoNeto,
    this.periodo,
  });

  factory ReporteResumen.fromJson(Map<String, dynamic> json) => ReporteResumen(
        totalBoletos: (json['total_boletos'] as num?)?.toInt() ?? 0,
        totalPesoKg: (json['total_peso_kg'] as num?)?.toDouble() ?? 0,
        totalPesoNeto: (json['total_peso_neto'] as num?)?.toDouble() ?? 0,
        periodo: json['periodo'] as String?,
      );

  /// Peso total en toneladas (1 t = 1000 kg).
  double get totalPesoTon => totalPesoKg / 1000;
  double get totalPesoNetoTon => totalPesoNeto / 1000;
}

/// Fila de un reporte de transportista o tercero.
class ReporteFilaEntidad {
  final String id;
  final String nombre;
  final int boletos;
  final double pesoKg;
  final double pesoNeto;

  const ReporteFilaEntidad({
    required this.id,
    required this.nombre,
    required this.boletos,
    required this.pesoKg,
    required this.pesoNeto,
  });

  factory ReporteFilaEntidad.fromJson(Map<String, dynamic> json) =>
      ReporteFilaEntidad(
        id: '${json['id'] ?? ''}',
        nombre: json['nombre'] as String? ?? json['razon_social'] as String? ?? '—',
        boletos: (json['boletos'] as num?)?.toInt() ?? 0,
        pesoKg: (json['peso_kg'] as num?)?.toDouble() ?? 0,
        pesoNeto: (json['peso_neto'] as num?)?.toDouble() ?? 0,
      );
}
