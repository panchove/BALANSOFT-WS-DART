import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/config/menu_config.dart';
import 'package:balansoft_ws/core/constants/accesos_default.dart';
import 'package:balansoft_ws/core/i18n/translations.dart';
import 'package:balansoft_ws/presentation/widgets/app_sidebar.dart';

/// Tests del menú lateral configurable por `menu.json`.
///
/// Cubren: siembra del archivo, lectura/escritura, quitar, reordenar, mover
/// entre secciones, separadores, tolerancia a JSON inválido y round-trip del
/// árbol por defecto.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpOverride;
  late Directory tmpSistema;

  setUp(() {
    tmpOverride = Directory.systemTemp.createTempSync('menu_override');
    tmpSistema = Directory.systemTemp.createTempSync('menu_sistema');
    MenuConfigPaths.pruebasOverrideDir = tmpOverride.path;
    MenuConfigPaths.pruebasSistemaDir = tmpSistema.path;
    MenuConfig.errores = <String>[];
    MenuConfig.inyectarParaPruebas(MenuConfig.arbolPorDefecto);
  });

  tearDown(() {
    MenuConfigPaths.pruebasOverrideDir = null;
    MenuConfigPaths.pruebasSistemaDir = null;
    MenuConfig.errores = <String>[];
    MenuConfig.inyectarParaPruebas(MenuConfig.arbolPorDefecto);
    tmpOverride.deleteSync(recursive: true);
    tmpSistema.deleteSync(recursive: true);
  });

  /// Reproducción plana de un árbol para comparar round-trips.
  List<String> aplanar(List<MenuNode> nodos) {
    final out = <String>[];
    void v(List<MenuNode> ns) {
      for (final n in ns) {
        if (n.esSeparador) {
          out.add('SEP');
          continue;
        }
        final tipo =
            n.isSectionHeader ? 'SEC' : (n.children != null ? 'GRP' : 'OPC');
        out.add([
          tipo,
          n.label,
          n.clave ?? '-',
          '${n.index ?? '-'}',
          n.accion ?? '-',
          n.shortcut ?? '-',
          n.rolesPermitidos == null
              ? '-'
              : (n.rolesPermitidos!.toList()..sort()).join(','),
          MenuIconos.nombreDe(n.icon) ?? '-',
          MenuIconos.nombreDe(n.activeIcon) ?? '-',
          n.claveI18n ?? '-',
        ].join('|'));
        if (n.children != null) v(n.children!);
      }
    }

    v(nodos);
    return out;
  }

  void escribirEn(Directory dir, String contenido) {
    File('${dir.path}${Platform.pathSeparator}menu.json')
        .writeAsStringSync(contenido);
  }

  String jsonMenu(Object menu) => jsonEncode({
        'version': 1,
        'menu': menu,
      });

  group('MenuConfig.cargar — archivo y siembra', () {
    test('sin menu.json siembra el árbol por defecto listo para editar',
        () async {
      await MenuConfig.cargar();

      final f = File(MenuConfigPaths.overridePath);
      expect(f.existsSync(), isTrue,
          reason: 'debe crearse el menu.json editable en el override');

      final doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      expect(doc['version'], 1);
      expect(doc['menu'], isA<List<dynamic>>());
      expect(doc['menu'] as List, isNotEmpty);
      expect(MenuConfig.errores, isEmpty);
      expect(MenuConfig.arbol, MenuConfig.arbolPorDefecto);
      expect(MenuConfig.ruta, MenuConfigPaths.overridePath);
    });

    test('lee el menu.json del override aplicando quitar/reordenar/mover',
        () async {
      // Kardex primero, luego separador, luego Inicio; Categorías movida aquí
      // desde otra sección; Reportes eliminado.
      escribirEn(
        tmpOverride,
        jsonMenu([
          {
            'tipo': 'seccion',
            'label': 'MI SECCIÓN',
            'hijos': [
              {'tipo': 'opcion', 'label': 'Kardex', 'clave': 'kardex'},
              {'tipo': 'separador'},
              {'tipo': 'opcion', 'label': 'Inicio', 'clave': 'inicio'},
              {
                'tipo': 'opcion',
                'label': 'Categorías',
                'clave': 'categorias'
              },
            ],
          },
        ]),
      );

      await MenuConfig.cargar();

      expect(MenuConfig.errores, isEmpty, reason: MenuConfig.errores.join(' / '));
      final raiz = MenuConfig.arbol;
      expect(raiz, hasLength(1));
      expect(raiz.first.label, 'MI SECCIÓN');
      expect(raiz.first.isSectionHeader, isTrue);

      final hijos = raiz.first.children!;
      expect(hijos.map((n) => n.label),
          ['Kardex', '', 'Inicio', 'Categorías'],
          reason: 'el orden del JSON manda y el separador se conserva');

      // Destinos resueltos por `clave` → índice de `_pages`.
      expect(hijos[0].index, 9); // kardex
      expect(hijos[0].isPage, isTrue);
      expect(hijos[1].esSeparador, isTrue);
      expect(hijos[1].isLeaf, isFalse);
      expect(hijos[2].index, 0); // inicio
      expect(hijos[3].index, 6); // categorias
      expect(MenuConfig.arbol.any((n) => n.label == 'REPORTES'), isFalse,
          reason: 'lo que no está en el JSON no aparece');
    });

    test('el override manda sobre el menu.json del sistema', () async {
      escribirEn(tmpSistema, jsonMenu([
        {
          'tipo': 'seccion',
          'label': 'SISTEMA',
          'hijos': [
            {'tipo': 'opcion', 'label': 'Inicio', 'clave': 'inicio'},
          ],
        },
      ]));
      escribirEn(tmpOverride, jsonMenu([
        {
          'tipo': 'seccion',
          'label': 'USUARIO',
          'hijos': [
            {'tipo': 'opcion', 'label': 'Kardex', 'clave': 'kardex'},
          ],
        },
      ]));

      await MenuConfig.cargar();

      expect(MenuConfig.arbol.single.label, 'USUARIO');
      expect(MenuConfig.ruta, MenuConfigPaths.overridePath);
    });

    test('usa el menu.json del sistema si el override no existe', () async {
      escribirEn(tmpSistema, jsonMenu([
        {
          'tipo': 'seccion',
          'label': 'SISTEMA',
          'hijos': [
            {'tipo': 'opcion', 'label': 'Inicio', 'clave': 'inicio'},
          ],
        },
      ]));

      await MenuConfig.cargar();

      expect(MenuConfig.arbol.single.label, 'SISTEMA');
      expect(MenuConfig.ruta, MenuConfigPaths.sistemaPath);
      expect(File(MenuConfigPaths.overridePath).existsSync(), isFalse,
          reason: 'si había un archivo en sistema no se siembra otro');
    });
  });

  group('MenuConfig.cargar — tolerancia a errores', () {
    test('JSON inválido degrada al árbol por defecto y lo reporta', () async {
      escribirEn(tmpOverride, 'esto no es { json');

      await MenuConfig.cargar();

      expect(MenuConfig.arbol, MenuConfig.arbolPorDefecto);
      expect(MenuConfig.errores, isNotEmpty);
    });

    test('sin lista "menu" degrada al árbol por defecto', () async {
      escribirEn(tmpOverride, jsonEncode({'version': 1, 'otra': []}));

      await MenuConfig.cargar();

      expect(MenuConfig.arbol, MenuConfig.arbolPorDefecto);
      expect(MenuConfig.errores.join(' '), contains('menu'));
    });

    test('una clave desconocida descarta esa opción y registra el error',
        () async {
      escribirEn(tmpOverride, jsonMenu([
        {
          'tipo': 'seccion',
          'label': 'X',
          'hijos': [
            {'tipo': 'opcion', 'label': 'No existe', 'clave': 'trucos'},
            {'tipo': 'opcion', 'label': 'Inicio', 'clave': 'inicio'},
          ],
        },
      ]));

      await MenuConfig.cargar();

      expect(MenuConfig.errores.join(' '), contains('trucos'));
      final hijos = MenuConfig.arbol.single.children!;
      expect(hijos.map((n) => n.label), ['Inicio'],
          reason: 'la opción inválida se cae, la válida sobrevive');
    });

    test('una opción sin clave ni acción se descarta', () async {
      final nodos = MenuConfig.desdeJson([
        {'tipo': 'opcion', 'label': 'Huerfana'},
      ]);

      expect(nodos, isEmpty);
      expect(MenuConfig.errores.join(' '), contains('clave'));
    });

    test('una acción que no empieza por "go:" se rechaza', () async {
      final nodos = MenuConfig.desdeJson([
        {
          'tipo': 'opcion',
          'label': 'Rara',
          'accion': 'imprimir_algo',
        },
      ]);

      expect(nodos, isEmpty);
      expect(MenuConfig.errores.join(' '), contains('go:'));
    });

    test('un nodo sin "tipo" o con tipo desconocido se descarta', () async {
      final nodos = MenuConfig.desdeJson([
        {'label': 'Sin tipo'},
        {'tipo': 'marciano', 'label': 'Alien'},
        'no soy un objeto',
      ]);

      expect(nodos, isEmpty);
      expect(MenuConfig.errores, hasLength(3));
    });
  });

  group('Separadores', () {
    test('{"tipo": "separador"} parsea como separador y no como hoja', () {
      final nodos = MenuConfig.desdeJson([
        {
          'tipo': 'seccion',
          'label': 'X',
          'hijos': [
            {'tipo': 'opcion', 'label': 'Inicio', 'clave': 'inicio'},
            {'tipo': 'separador'},
            {'tipo': 'opcion', 'label': 'Kardex', 'clave': 'kardex'},
          ],
        },
      ]);

      final sep = nodos.single.children![1];
      expect(sep.esSeparador, isTrue);
      expect(sep.isLeaf, isFalse);
      expect(sep.isPage, isFalse);
      expect(sep.isGrupo, isFalse);
      expect(sep.index, isNull);
      expect(sep.accion, isNull);
    });

    test('limpiarSeparadores recorta inicio, fin y consecutivos', () {
      const sep = MenuNode.separador();
      final op = MenuConfig.desdeJson([
        {'tipo': 'opcion', 'label': 'Inicio', 'clave': 'inicio'},
      ]).single;

      final salida = MenuConfig.limpiarSeparadores([
        sep,
        sep,
        op,
        sep,
        sep,
        sep,
        op,
        sep,
        sep,
      ]);

      expect(salida, hasLength(3));
      expect(salida[0].esSeparador, isFalse);
      expect(salida[1].esSeparador, isTrue);
      expect(salida[2].esSeparador, isFalse);
    });

    test('el árbol por defecto trae las opciones de la estructura pedida', () {
      final nodos = <MenuNode>[];
      void v(List<MenuNode> ns) {
        for (final n in ns) {
          nodos.add(n);
          if (n.children != null) v(n.children!);
        }
      }

      v(MenuConfig.arbolPorDefecto);

      final porClave = {
        for (final n in nodos)
          if (n.clave != null) n.clave!: n,
      };
      expect(porClave['roles']?.index, 23);
      expect(porClave['reportes_diarios']?.index, 24);
      expect(porClave['reportes_mensuales']?.index, 25);
      expect(porClave['reportes_personalizado']?.index, 26);

      final acciones = {for (final n in nodos) if (n.accion != null) n.accion!};
      expect(acciones.contains('go:ayuda_manuales'), isTrue);
      expect(acciones.contains('go:ayuda_pagina'), isTrue);
      expect(acciones.contains('go:ayuda_version'), isTrue);
      expect(acciones.contains('go:ayuda_tutorial'), isTrue);
    });

    test('el árbol por defecto trae separadores en los grupos del cliente', () {
      final cols = aplanar(MenuConfig.arbolPorDefecto);
      // La estructura pedida usa separadores dentro de CATÁLOGOS, GESTIÓN,
      // CONSULTAR y MANTENIMIENTO.
      expect(cols.where((c) => c == 'SEP'), isNotEmpty);
      // Nunca un separador como último nodo global (los recorta filtrarMenu,
      // y el árbol por defecto ya viene limpio).
      expect(cols.last, isNot('SEP'));
    });
  });

  group('Serialización y round-trip', () {
    test('el árbol por defecto sobrevive ida y vuelta a JSON', () {
      final doc = MenuConfig.aJson(MenuConfig.arbolPorDefecto);
      final reparse =
          MenuConfig.desdeJson(doc['menu'] as List<dynamic>);

      expect(aplanar(reparse), aplanar(MenuConfig.arbolPorDefecto));
      expect(MenuConfig.errores, isEmpty, reason: MenuConfig.errores.join(' / '));
    });

    test('el documento serializado es JSON válido y re-readable por cargar()',
        () async {
      final crudo = const JsonEncoder.withIndent('  ')
          .convert(MenuConfig.aJson(MenuConfig.arbolPorDefecto));
      escribirEn(tmpOverride, crudo);

      await MenuConfig.cargar();

      expect(MenuConfig.errores, isEmpty, reason: MenuConfig.errores.join(' / '));
      expect(aplanar(MenuConfig.arbol), aplanar(MenuConfig.arbolPorDefecto));
    });

    test('los destinos documentados del JSON son los reales', () {
      expect(MenuConfig.clavesDisponibles,
          containsAll(['inicio', 'kardex', 'dispositivos', 'diseno_ticket']));
      expect(MenuConfig.accionesDisponibles,
          containsAll(['go:pesaje_manual', 'go:auditoria', 'go:ayuda']));
    });
  });

  group('Iconos', () {
    test('icono desconocido usa el de respaldo sin lanzar', () {
      final nodo = MenuConfig.desdeJson([
        {
          'tipo': 'opcion',
          'label': 'Inicio',
          'clave': 'inicio',
          'icono': 'esto_no_existe',
        },
      ]).single;

      expect(nodo.icon, isNotNull);
      expect(nodo.icon, isNot(Icons.dashboard_outlined));
    });

    test('icono válido se resuelve por nombre', () {
      final nodo = MenuConfig.desdeJson([
        {
          'tipo': 'opcion',
          'label': 'Inicio',
          'clave': 'inicio',
          'icono': 'dashboard_outlined',
          'icono_activo': 'dashboard',
        },
      ]).single;

      expect(nodo.icon, Icons.dashboard_outlined);
      expect(nodo.activeIcon, Icons.dashboard);
      expect(MenuIconos.nombreDe(nodo.icon), 'dashboard_outlined');
    });

    test('una opción sin icono no revienta (icono de respaldo)', () {
      final nodo = MenuConfig.desdeJson([
        {'tipo': 'opcion', 'label': 'Inicio', 'clave': 'inicio'},
      ]).single;

      expect(nodo.icon, isNotNull);
    });
  });

  group('i18n de los nodos', () {
    test('la clave i18n explícita manda sobre la etiqueta', () {
      final nodo = MenuConfig.desdeJson([
        {
          'tipo': 'opcion',
          'label': 'Mi panel favorito',
          'clave': 'inicio',
          'i18n': 'menu_inicio',
        },
      ]).single;

      expect(AppSidebar.traducirNodo(nodo, 'en'),
          AppTranslations.tr('menu_inicio', langCode: 'en'));
      expect(AppSidebar.traducirNodo(nodo, 'en'), isNot('Mi panel favorito'));
    });

    test('una etiqueta sin clave i18n conocida se muestra literal', () {
      final nodo = MenuConfig.desdeJson([
        {'tipo': 'opcion', 'label': 'Panel de Juan', 'clave': 'inicio'},
      ]).single;

      expect(AppSidebar.traducirNodo(nodo, 'es'), 'Panel de Juan');
    });

    test('la etiqueta por defecto sigue traduciéndose por el mapa label→clave',
        () {
      final nodo = MenuConfig.desdeJson([
        {'tipo': 'opcion', 'label': 'Kardex', 'clave': 'kardex'},
      ]).single;

      expect(AppSidebar.traducirNodo(nodo, 'en'),
          AppTranslations.tr('menu_kardex', langCode: 'en'));
    });
  });

  group('Poda por rol (filtrarMenu)', () {
    test('los separadores llegan al árbol y limpiarSeparadores los normaliza',
        () {
      // La poda por rol necesita DI, así que su comportamiento completo se
      // cubre en test/widget/navigation_shortcuts_test.dart. Aquí validamos el
      // insumo: separadores internos se conservan; extremos y dobles, no.
      final nodos = MenuConfig.desdeJson([
        {
          'tipo': 'seccion',
          'label': 'X',
          'hijos': [
            {'tipo': 'separador'},
            {'tipo': 'opcion', 'label': 'Inicio', 'clave': 'inicio'},
            {'tipo': 'separador'},
            {'tipo': 'separador'},
            {'tipo': 'opcion', 'label': 'Seguridad', 'clave': 'seguridad'},
            {'tipo': 'separador'},
          ],
        },
      ]);

      final hijos = nodos.single.children!;
      expect(hijos, hasLength(3),
          reason: 'al construir el grupo ya se recortan extremos y dobles');
      expect(hijos.first.esSeparador, isFalse);
      expect(hijos[1].esSeparador, isTrue);
      expect(hijos.last.esSeparador, isFalse);

      expect(MenuConfig.limpiarSeparadores(hijos), hasLength(3));
    });
  });

  group('Dispositivos separado en vistas independientes', () {
    /// Hojas del árbol por defecto que son páginas (tienen índice).
    List<MenuNode> hojas(List<MenuNode> nodos) {
      final out = <MenuNode>[];
      void v(List<MenuNode> ns) {
        for (final n in ns) {
          if (n.children != null) {
            v(n.children!);
          } else if (!n.esSeparador && n.accion == null) {
            out.add(n);
          }
        }
      }
      v(nodos);
      return out;
    }

    test('cada vista de dispositivo declara su clave e índice propio', () {
      final porclave = {
        for (final n in hojas(MenuConfig.arbolPorDefecto)) n.clave: n,
      };

      const esperado = {
        'dispositivos_basculas': 13,
        'dispositivos_indicadores': 27,
        'dispositivos_semaforos': 28,
        'dispositivos_camaras': 29,
        'dispositivos_impresoras': 30,
      };

      for (final entrada in esperado.entries) {
        final nodo = porclave[entrada.key];
        expect(nodo, isNotNull, reason: '${entrada.key} debe existir en el menú');
        expect(nodo!.index, entrada.value,
            reason: '${entrada.key} debe abrir la página ${entrada.value}');
        expect(nodo.accion, isNull,
            reason: '${entrada.key} ya no es una hoja-acción: navega por clave');
      }
    });

    test('las claves de dispositivo están en clavesDisponibles', () {
      for (final clave in [
        'dispositivos_basculas',
        'dispositivos_indicadores',
        'dispositivos_semaforos',
        'dispositivos_camaras',
        'dispositivos_impresoras',
      ]) {
        expect(MenuConfig.clavesDisponibles, contains(clave));
        expect(AccesosDefault.indiceDe(clave), greaterThanOrEqualTo(0));
      }
    });

    test('un menu.json legado con go:dispositivos_* sigue resolviendo', () {
      // Compatibilidad: el nodo se acepta (el validador solo exige el prefijo
      // `go:`) y el shell mapea la acción vieja a la misma vista que la clave
      // nueva (`go:dispositivos_camaras` → `_claveAIndice` → índice 29).
      final nodos = MenuConfig.desdeJson([
        {
          'tipo': 'opcion',
          'label': 'Semáforos',
          'icono': 'traffic_outlined',
          'accion': 'go:dispositivos_semaforos',
        },
        {
          'tipo': 'opcion',
          'label': 'Cámaras',
          'icono': 'photo_camera_outlined',
          'clave': 'dispositivos_camaras',
        },
      ]);

      expect(nodos, hasLength(2));
      expect(nodos.first.accion, 'go:dispositivos_semaforos');
      expect(nodos.last.clave, 'dispositivos_camaras');
      expect(nodos.last.index, 29);
    });

    test('un menu.json con la clave nueva resuelve su índice', () {
      final nodos = MenuConfig.desdeJson([
        {
          'tipo': 'opcion',
          'label': 'Cámaras',
          'icono': 'photo_camera_outlined',
          'clave': 'dispositivos_camaras',
        },
      ]);

      expect(nodos, hasLength(1));
      expect(nodos.single.clave, 'dispositivos_camaras');
      expect(nodos.single.index, 29);
      expect(MenuConfig.errores, isEmpty);
    });
  });
}
