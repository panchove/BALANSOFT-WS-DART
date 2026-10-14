class PrinterPreset {
  final String nombreImpresora;
  final String tipoImpresora; // POS_80, POS_58, SISTEMA_PDF, MATRIZ_PUNTO
  final String tamanoPapel; // 80mm, 58mm, HalfLetter, Letter, A4, Custom
  final String orientacion; // portrait, landscape
  final String formatoPredeterminado; // PDF, TXT
  final int copias; // cantidad de tickets a imprimir (1..N)
  final double altoBoletoMm; // 0 = Auto / proporcional
  final bool mostrarEncabezado;
  final bool mostrarDetalles;
  final bool mostrarQr; // solo afecta al PDF: el preview no dibuja QR
  final double margenMm;
  final double? anchoCustomMm;
  final double? altoCustomMm;
  final String tipoTicket; // simple, avanzado

  const PrinterPreset({
    this.nombreImpresora = 'Impresora Térmica POS-80',
    this.tipoImpresora = 'POS_80',
    this.tamanoPapel = '80mm',
    this.orientacion = 'portrait',
    this.formatoPredeterminado = 'PDF',
    this.copias = 1,
    this.altoBoletoMm = 0.0,
    this.mostrarEncabezado = true,
    this.mostrarDetalles = true,
    this.mostrarQr = true,
    this.margenMm = 5.0,
    this.anchoCustomMm,
    this.altoCustomMm,
    this.tipoTicket = 'simple',
  });

  Map<String, dynamic> toJson() => {
        'nombreImpresora': nombreImpresora,
        'tipoImpresora': tipoImpresora,
        'tamanoPapel': tamanoPapel,
        'orientacion': orientacion,
        'formatoPredeterminado': formatoPredeterminado,
        'copias': copias,
        'altoBoletoMm': altoBoletoMm,
        'mostrarEncabezado': mostrarEncabezado,
        'mostrarDetalles': mostrarDetalles,
        'mostrarQr': mostrarQr,
        'margenMm': margenMm,
        'anchoCustomMm': anchoCustomMm,
        'altoCustomMm': altoCustomMm,
        'tipoTicket': tipoTicket,
      };

  factory PrinterPreset.fromJson(Map<String, dynamic> json) => PrinterPreset(
        nombreImpresora: json['nombreImpresora'] as String? ?? 'Impresora Térmica POS-80',
        tipoImpresora: json['tipoImpresora'] as String? ?? 'POS_80',
        tamanoPapel: json['tamanoPapel'] as String? ?? '80mm',
        orientacion: json['orientacion'] as String? ?? 'portrait',
        formatoPredeterminado: json['formatoPredeterminado'] as String? ?? 'PDF',
        copias: json['copias'] as int? ?? 1,
        altoBoletoMm: (json['altoBoletoMm'] as num?)?.toDouble() ?? 0.0,
        mostrarEncabezado: json['mostrarEncabezado'] as bool? ?? true,
        mostrarDetalles: json['mostrarDetalles'] as bool? ?? true,
        mostrarQr: json['mostrarQr'] as bool? ?? true,
        margenMm: (json['margenMm'] as num?)?.toDouble() ?? 5.0,
        anchoCustomMm: (json['anchoCustomMm'] as num?)?.toDouble(),
        altoCustomMm: (json['altoCustomMm'] as num?)?.toDouble(),
      );

  PrinterPreset copyWith({
    String? nombreImpresora,
    String? tipoImpresora,
    String? tamanoPapel,
    String? orientacion,
    String? formatoPredeterminado,
    int? copias,
    double? altoBoletoMm,
    bool? mostrarEncabezado,
    bool? mostrarDetalles,
    bool? mostrarQr,
    double? margenMm,
    double? anchoCustomMm,
    double? altoCustomMm,
    String? tipoTicket,
  }) {
    return PrinterPreset(
      nombreImpresora: nombreImpresora ?? this.nombreImpresora,
      tipoImpresora: tipoImpresora ?? this.tipoImpresora,
      tamanoPapel: tamanoPapel ?? this.tamanoPapel,
      orientacion: orientacion ?? this.orientacion,
      formatoPredeterminado: formatoPredeterminado ?? this.formatoPredeterminado,
      copias: copias ?? this.copias,
      altoBoletoMm: altoBoletoMm ?? this.altoBoletoMm,
      mostrarEncabezado: mostrarEncabezado ?? this.mostrarEncabezado,
      mostrarDetalles: mostrarDetalles ?? this.mostrarDetalles,
      mostrarQr: mostrarQr ?? this.mostrarQr,
      margenMm: margenMm ?? this.margenMm,
      anchoCustomMm: anchoCustomMm ?? this.anchoCustomMm,
      altoCustomMm: altoCustomMm ?? this.altoCustomMm,
      tipoTicket: tipoTicket ?? this.tipoTicket,
    );
  }
}
