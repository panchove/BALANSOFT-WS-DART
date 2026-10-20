// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 17025 / OIML R 76-1 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

/// Entidades del módulo de Kardex (PRD §9.6).
library;

/// Registro individual de movimiento en el libro de inventario/Kardex de pesaje.
///
/// Refleja la variación de masa neta asociada a un boleto de pesaje:
/// - Movimientos < 50: Ingresos de materia prima o producto (10: Ingreso Báscula).
/// - Movimientos >= 50: Despachos de producto terminado (60: Despacho Báscula).
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

  /// Crea una instancia inmutable de un movimiento de Kardex.
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

  /// Construye un [KardexMovimiento] desde un mapa JSON retornado por el backend.
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

  /// Determina si el movimiento corresponde a un ingreso a planta (`idMovimiento < 50`).
  bool get esIngreso => idMovimiento < 50;

  /// Etiqueta descriptiva del tipo de movimiento.
  String get etiquetaMovimiento =>
      esIngreso ? '$idMovimiento INGRESO BASC' : '$idMovimiento DESPACHO BASC';

  /// Etiqueta formateada del producto asociado.
  String get etiquetaProducto =>
      nombreProducto ?? (codigoProducto != null ? 'Prod. $codigoProducto' : 'Producto');
}

/// Detalle consolidado de movimientos y saldos de Kardex para un rango temporal.
class KardexDetalle {
  final String fechaDesde;
  final String fechaHasta;
  final double saldoInicial;
  final double saldoActual;
  final List<KardexMovimiento> movimientos;

  /// Crea una instancia inmutable de [KardexDetalle].
  const KardexDetalle({
    required this.fechaDesde,
    required this.fechaHasta,
    required this.saldoInicial,
    required this.saldoActual,
    this.movimientos = const [],
  });

  /// Construye un [KardexDetalle] a partir del payload JSON del balance de masa.
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