/// Entidades del módulo de Kardex (PRD §9.6).
library;

class KardexMovimiento {
  final String idKardex;
  final String fecha;
  final int idMovimiento;
  final String idProducto;
  final String? nombreProducto;
  final String? codigoProducto;
  final String idAlmacen;
  final String? documento;
  final String? boleto;
  final String? numeroBoleto;
  final double valor;
  final double stock;

  const KardexMovimiento({
    required this.idKardex,
    required this.fecha,
    required this.idMovimiento,
    required this.idProducto,
    this.nombreProducto,
    this.codigoProducto,
    required this.idAlmacen,
    this.documento,
    this.boleto,
    this.numeroBoleto,
    required this.valor,
    required this.stock,
  });

  factory KardexMovimiento.fromJson(Map<String, dynamic> json) =>
      KardexMovimiento(
        idKardex: '${json['id_kardex']}',
        fecha: json['fecha'] as String? ?? '',
        idMovimiento: (json['id_movimiento'] as num?)?.toInt() ?? 0,
        idProducto: json['id_producto'] as String? ?? 'SIN_PRODUCTO',
        nombreProducto: json['nombre_producto'] as String?,
        codigoProducto: json['codigo_producto'] as String?,
        idAlmacen: json['id_almacen'] as String? ?? 'SIN_ALMACEN',
        documento: json['documento'] as String?,
        boleto: json['boleto'] as String?,
        numeroBoleto: json['numero_boleto'] as String?,
        valor: (json['valor'] as num?)?.toDouble() ?? 0,
        stock: (json['stock'] as num?)?.toDouble() ?? 0,
      );

  bool get esIngreso => idMovimiento < 50;
  String get etiquetaMovimiento =>
      esIngreso ? '$idMovimiento INGRESO BASC' : '$idMovimiento DESPACHO BASC';
  String get etiquetaProducto =>
      nombreProducto ?? (codigoProducto != null ? 'Prod. $codigoProducto' : 'Producto');
}

class KardexDetalle {
  final String fechaDesde;
  final String fechaHasta;
  final double saldoInicial;
  final double saldoActual;
  final List<KardexMovimiento> movimientos;

  const KardexDetalle({
    required this.fechaDesde,
    required this.fechaHasta,
    required this.saldoInicial,
    required this.saldoActual,
    this.movimientos = const [],
  });

  factory KardexDetalle.fromJson(Map<String, dynamic> json) => KardexDetalle(
        fechaDesde: json['fecha_desde'] as String? ?? '',
        fechaHasta: json['fecha_hasta'] as String? ?? '',
        saldoInicial: (json['saldo_inicial'] as num?)?.toDouble() ?? 0,
        saldoActual: (json['saldo_actual'] as num?)?.toDouble() ?? 0,
        movimientos: (json['movimientos'] as List? ?? [])
            .map((e) => KardexMovimiento.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}