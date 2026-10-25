/// Reglas de las **fotos de placa** del pesaje (config por empresa, migración
/// 027 de BALANSOFT-WS).
///
/// La placa se pide **una sola vez por boleto**, en la pesada que elija el
/// operador (entrada o salida); una vez capturada, el bloque no se vuelve a
/// ofrecer en la otra pesada. El backend refleja ese estado en
/// `boletos_pesaje.fotos_placa_tomadas`.
///
/// Este módulo concentra la decisión en funciones **puras** (sin `BuildContext`
/// ni red) para poder probarla sin montar el formulario de pesaje completo.
library;

/// Sufijos de foto aceptados por la API (`CamaraCapturarIn.foto`).
const List<String> sufijosPlacaApi = ['placa_trasera', 'frente', 'placa_remolque'];

/// Sufijos que debe aportar el operador para el vehículo actual.
///
/// Sin remolque: **placa trasera del camión + frente del camión**.
/// Con remolque: **placa del remolque + frente del camión** (la placa del
/// remolque solo se distingue por la etiqueta; el sufijo que viaja a la API
/// sigue siendo `placa_trasera`, porque describe la posición de la toma).
List<String> sufijosPlacaRequeridos({required bool remolque}) =>
    const ['placa_trasera', 'frente'];

/// ¿El bloque de captura de placa debe ofrecerse en el formulario?
///
/// Solo si la empresa activó las fotos de placa **y** el boleto aún no las
/// tiene. Un boleto que ya pasó por la otra pesada con fotos no vuelve a pedirlas.
bool debeCapturarPlaca({
  required bool activas,
  required bool yaTomadas,
}) =>
    activas && !yaTomadas;

/// ¿El guardado debe bloquearse por falta de fotos de placa?
///
/// Bloquea solo cuando la empresa las marcó **obligatorias**, están activas, el
/// boleto aún no las tiene y el operador no ha capturado ninguna.
bool exigeFotosPlacaAlGuardar({
  required bool activas,
  required bool obligatorias,
  required bool yaTomadas,
  required bool hayFotos,
}) =>
    activas && obligatorias && !yaTomadas && !hayFotos;

/// Renombra las fotos del respaldo local con los sufijos de placa, para que el
/// backend las guarde como `tipo='placa'` (y fije `fotos_placa_tomadas`).
///
/// El `PhotoPickerField` entrega los bytes sin nombre significativo; aquí se
/// asignan los sufijos en orden (el que sobra cae a `placa_N`).
List<String> nombresPlacaLocal(int cantidad, {required bool remolque}) {
  final sufijos = sufijosPlacaRequeridos(remolque: remolque);
  return [
    for (var i = 0; i < cantidad; i++)
      '${i < sufijos.length ? sufijos[i] : 'placa_${i + 1}'}.jpg',
  ];
}
