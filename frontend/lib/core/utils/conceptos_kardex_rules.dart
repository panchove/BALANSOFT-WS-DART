/// Reglas puras del catálogo de Conceptos de Kardex (IDs 0-99).
///
/// Aisladas de la UI para poder verificarlas sin montar widgets: la regla de
/// oro del kardex es que **el ID define el signo**, y los conceptos del sistema
/// (00 saldo inicial, 10 ingreso por báscula, 60 despacho por báscula) están
/// reservados para el propio sistema.
library;

/// IDs reservados por el sistema (no editables ni reutilizables por el ADMIN).
const Set<int> idsSistemaKardex = {0, 10, 60};

/// Rangos de ID que se muestran agrupados en la pantalla.
const Map<String, String> rangosKardex = {
  '00': 'Saldo inicial',
  '01-49': 'Positivos configurables',
  '10': 'Ingreso por báscula',
  '11-49': 'Positivos configurables',
  '50-59': 'Negativos configurables',
  '60': 'Despacho por báscula',
  '61-99': 'Negativos configurables',
};

/// Signo que corresponde al rango del ID.
///
/// 00 = inicial, 01-49 = positivo, 50-99 = negativo.
String signoDeRangoKardex(int id) {
  if (id <= 0) return 'inicial';
  if (id >= 50) return 'negativo';
  return 'positivo';
}

/// `true` si el ID pertenece al sistema (no lo crea ni lo borra el usuario).
bool esConceptoSistema(int id) => idsSistemaKardex.contains(id);

/// Clave del grupo en el que se muestra el ID.
String rangoDeKardex(int id) {
  if (id == 0) return '00';
  if (id == 10) return '10';
  if (id == 60) return '60';
  if (id >= 1 && id <= 9) return '01-49';
  if (id >= 11 && id <= 49) return '11-49';
  if (id >= 50 && id <= 59) return '50-59';
  return '61-99';
}

/// IDs que el usuario puede usar: dentro de 1..99, fuera de los reservados
/// (10/60) y que no estén ya ocupados por otro concepto de la empresa.
List<int> idsLibresKardex(List<int> ocupados) {
  final usados = ocupados.toSet();
  final libres = <int>[];
  for (int id = 1; id <= 99; id++) {
    if (id == 10 || id == 60) continue;
    if (usados.contains(id)) continue;
    libres.add(id);
  }
  return libres;
}

/// Etiqueta legible del signo para la UI.
String etiquetaSignoKardex(String signo) {
  switch (signo) {
    case 'inicial':
      return 'Inicial';
    case 'negativo':
      return 'Negativo (-)';
    default:
      return 'Positivo (+)';
  }
}

/// Conceptos del catálogo que el formulario de ajuste manual puede ofrecer.
///
/// Reglas: solo activos, nunca los del sistema (0/10/60) y con el signo que
/// acompaña al tipo de movimiento seleccionado (INGRESO → positivo,
/// DESPACHO → negativo). Los de signo `inicial` (saldo inicial) no generan
/// movimiento y quedan fuera.
List<Map<String, dynamic>> conceptosKardexParaAjuste(
  List<Map<String, dynamic>> conceptos,
  String signoRequerido,
) {
  return conceptos.where((c) {
    if (c['activo'] == false) return false;
    if (c['es_sistema'] == true) return false;
    return c['signo']?.toString() == signoRequerido;
  }).toList();
}
