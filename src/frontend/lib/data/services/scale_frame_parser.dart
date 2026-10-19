import 'dart:convert';

/// Parser de tramas de básculas industriales reales (multi-marca) para el
/// cliente TCP directo de Flutter.
///
/// Es el gemelo Dart de `backend/app/core/scale_parser.py`: extrae el peso de
/// una línea ASCII emitida por indicadores reales (Toledo/GSI
/// `ST,GS,+00320.00kg`, Rice Lake/iQ `01+000320.0`, MT-SICS `S S 320.00 kg`) y
/// clasifica su estabilidad. Se usa como respaldo del HAL del backend cuando la
/// app habla TCP directo con el equipo.
///
/// Principio anti-falso-positivo: un número desnudo (`1234567890`, la dirección
/// `01`, un checksum) **no** es un peso; un token solo es candidato si trae
/// signo, decimal, unidad o venía precedido de un token de signo suelto. Ante
/// ambigüedad se rechaza la trama: mejor `null` que fijar un peso equivocado.
class PesoParseado {
  /// Peso en kg, o `null` si la trama no contenía un peso válido.
  final double? peso;

  /// `stable` | `unstable` | `overload` | `null`.
  final String? estado;

  /// Motivo del rechazo (`vacio`, `checksum`, `sobrecarga`, `sin_numero`,
  /// `ambiguo`, `sobre_capacidad`, `precision`) o `null` cuando [peso] es válido.
  final String? motivo;

  const PesoParseado(this.peso, this.estado, this.motivo);

  bool get ok => peso != null;

  @override
  String toString() => 'PesoParseado(peso: $peso, estado: $estado, motivo: $motivo)';
}

const int _maxDecimales = 3;
const double _toleranciaCapacidad = 1.05;

final RegExp _reUnidadFinal =
    RegExp(r'(KGS|KG|LBS|LB|TONS|TON|G|T)$', caseSensitive: false);
final RegExp _reNum = RegExp(r'^[+-]?\d+(?:\.\d+)?$');
final RegExp _reNumEmbebido = RegExp(r'[+-]\s*\d+(?:\.\d+)?');
final RegExp _reSignoEspacio = RegExp(r'([+-])\s+');
final RegExp _reSeparador = RegExp(r'[,;\s]+');
final RegExp _reChecksum = RegExp(r'^[0-9A-Fa-f]{2}$');

List<String> _tokens(String texto) =>
    texto.trim().split(_reSeparador).where((t) => t.isNotEmpty).toList();

/// Devuelve `(payload, checksum)` de la trama.
///
/// Limpia NUL; si hay STX (0x02) toma el contenido hasta ETX (0x03) y los 2 hex
/// siguientes como checksum. Los delimitadores de control STX/ETX que se
/// cuelen en el payload (p. ej. un frame leído con `readuntil(\x03)`) se
/// eliminan para que el número sea parseable.
(String, String?) _extraerPayload(String linea) {
  var limpio = linea.replaceAll('\u0000', '');
  final idxStx = limpio.indexOf('\u0002');
  if (idxStx != -1) {
    final idxEtx = limpio.indexOf('\u0003', idxStx + 1);
    if (idxEtx != -1) {
      final payload = limpio.substring(idxStx + 1, idxEtx);
      final resto = limpio.substring(idxEtx + 1).trim();
      final checksum = _reChecksum.hasMatch(resto) ? resto : null;
      return (payload.replaceAll('\u0002', '').replaceAll('\u0003', '').trim(),
          checksum);
    }
    limpio = limpio.substring(idxStx + 1);
  }
  final payload = limpio.replaceAll('\u0002', '').replaceAll('\u0003', '');
  return (payload.trim(), null);
}

/// XOR de todos los bytes del payload == checksum (formato Toledo/GSI).
bool _checksumValido(String payload, String checksumHex) {
  final esperado = int.tryParse(checksumHex, radix: 16);
  if (esperado == null) return false;
  var xor = 0;
  for (final byte in latin1.encode(payload)) {
    xor ^= byte;
  }
  return xor == esperado;
}

String? _clasificarEstado(String payload) {
  final tokens = _tokens(payload).map((t) => t.toUpperCase()).toSet();
  if (tokens.contains('OL')) return 'overload';
  if (tokens.contains('ST')) return 'stable';
  if (tokens.contains('US')) return 'unstable';
  return null;
}

/// Convierte un token normalizado en `(valor, decimales)` si es número.
(double, int)? _candidato(String normalizado) {
  if (!_reNum.hasMatch(normalizado)) return null;
  final partes = normalizado.split('.');
  final decimales = partes.length > 1 ? partes[1].length : 0;
  final valor = double.tryParse(normalizado);
  if (valor == null) return null;
  return (valor, decimales);
}

/// Extrae **un** peso de la trama. Devuelve `(peso, null)` o `(null, motivo)`.
(double?, String?) _extraerNumero(String payload, double? capacidadMax) {
  final candidatos = <(double, int)>[];
  String? signoPendiente;

  for (final token in _tokens(payload)) {
    if (token == '+' || token == '-') {
      signoPendiente = token;
      continue;
    }
    final teniaUnidad = _reUnidadFinal.hasMatch(token);
    var cuerpo = token.replaceFirst(_reUnidadFinal, '');
    cuerpo = cuerpo.replaceAll(_reSignoEspacio, r'$1').replaceAll(',', '.');
    if (cuerpo.isEmpty) continue;

    final teniaSigno = cuerpo[0] == '+' || cuerpo[0] == '-';
    // Señal semántica: signo, decimal, unidad o signo suelto previo.
    final tieneSenal =
        teniaSigno || cuerpo.contains('.') || teniaUnidad || signoPendiente != null;
    if (!tieneSenal) continue; // Número desnudo: NO es un peso.

    final numero = _candidato(cuerpo);
    if (numero == null) continue;
    var valor = numero.$1;
    if (signoPendiente == '-') {
      valor = -valor.abs();
    } else if (signoPendiente == '+') {
      valor = valor.abs();
    }
    signoPendiente = null;
    candidatos.add((valor, numero.$2));
  }

  if (candidatos.isEmpty) {
    // Fallback: signo embebido (dirección adherida al número).
    for (final m in _reNumEmbebido.allMatches(payload)) {
      final normalizado =
          m.group(0)!.replaceAll(_reSignoEspacio, r'$1').replaceAll(',', '.');
      final numero = _candidato(normalizado);
      if (numero != null) candidatos.add(numero);
    }
  }

  if (candidatos.length > 1) return (null, 'ambiguo');
  if (candidatos.isEmpty) return (null, 'sin_numero');

  final valor = candidatos[0].$1;
  final decimales = candidatos[0].$2;
  if (decimales > _maxDecimales) return (null, 'precision');
  if (capacidadMax != null && valor.abs() > capacidadMax * _toleranciaCapacidad) {
    return (null, 'sobre_capacidad');
  }
  return (valor, null);
}

/// Parsea una trama ASCII de báscula. Devuelve un [PesoParseado].
PesoParseado parseWeightFrame(
  String linea, {
  double? capacidadMax,
  bool validarChecksum = false,
}) {
  final (payload, checksum) = _extraerPayload(linea);
  if (payload.isEmpty) return const PesoParseado(null, null, 'vacio');

  if (validarChecksum &&
      checksum != null &&
      !_checksumValido(payload, checksum)) {
    return const PesoParseado(null, null, 'checksum');
  }

  final estado = _clasificarEstado(payload);
  if (estado == 'overload') return PesoParseado(null, estado, 'sobrecarga');

  final (peso, motivo) = _extraerNumero(payload, capacidadMax);
  if (peso == null) return PesoParseado(null, estado, motivo);
  return PesoParseado(peso, estado, null);
}

/// Clasifica una línea de red: `"json"`, `"ascii"` o `null`.
///
/// El JSON del simulador BSDD gana siempre; si no, se intenta el parser ASCII.
String? clasificarTrama(String linea) {
  final texto = linea.trim();
  if (texto.isEmpty) return null;
  try {
    final payload = jsonDecode(texto);
    if (payload is Map && payload['weight_kg'] != null) return 'json';
  } on FormatException {
    // No es JSON: se intenta ASCII.
  }
  return parseWeightFrame(linea).peso != null ? 'ascii' : null;
}
