import 'package:balansoft_ws/core/config/menu_config.dart';

void main() async {
  await MenuConfig.cargar();
  print('Errores: ${MenuConfig.errores}');
  print('Cargado: ${MenuConfig.cargado}');
  print('Árbol length: ${MenuConfig.arbol.length}');
  
  // Contar secciones vs opciones
  int secciones = 0, opciones = 0;
  for (var node in MenuConfig.arbol) {
    if (node.isSectionHeader) secciones++;
    if (node.isLeaf) opciones++;
  }
  print('Secciones: $secciones, Opciones: $opciones');
  
  // Ver si el árbol tiene los elementos esperados
  bool tieneReportes = MenuConfig.arbol.any((n) => n.label == 'REPORTES');
  bool tieneMantenimiento = MenuConfig.arbol.any((n) => n.label == 'MANTENIMIENTO');
  print('Tiene REPORTES: $tieneReportes');
  print('Tiene MANTENIMIENTO: $tieneMantenimiento');
}
