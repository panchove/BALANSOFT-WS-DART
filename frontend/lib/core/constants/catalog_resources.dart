import 'package:flutter/material.dart';

import 'api_constants.dart';

enum CatalogFieldType {
  texto,
  multilinea,
  numero,
  entero,
  dropdown,
  email,
  foto
}

class CatalogField {
  final String key;
  final String label;
  final IconData icono;
  final CatalogFieldType tipo;
  final bool requerido;
  final List<String>? opciones;
  final List<String>? opcionLabels;
  final String? catalogoPath;
  final String? catalogoIdKey;
  final String? catalogoTituloKey;
  final String? hint;

  const CatalogField({
    required this.key,
    required this.label,
    required this.icono,
    this.tipo = CatalogFieldType.texto,
    this.requerido = false,
    this.opciones,
    this.opcionLabels,
    this.catalogoPath,
    this.catalogoIdKey,
    this.catalogoTituloKey,
    this.hint,
  });
}

class CatalogResource {
  final String clave;
  final String plural;
  final String singular;
  final IconData icono;
  final String listaPath;
  final String Function(String id) itemPath;
  final String idKey;
  final String Function(Map<String, dynamic> fila) tituloFila;
  final String? Function(Map<String, dynamic> fila)? subtituloFila;
  final List<CatalogField> campos;

  /// Filtro client-side aplicado en la lista por el campo `tipo`.
  /// Permite presentar un mismo catálogo (p.ej. `terceros`) segmentado
  /// como Clientes (`CLIENTE`) o Proveedores (`PROVEEDOR`) en la UI.
  final String? tipoFiltro;

  /// Si es `true`, la pantalla CRUD muestra el selector C/P/A
  /// (Cliente / Proveedor / Ambos) para segmentar la lista por `tipo`.
  final bool filtrarTipoUI;

  const CatalogResource({
    required this.clave,
    required this.plural,
    required this.singular,
    required this.icono,
    required this.listaPath,
    required this.itemPath,
    required this.idKey,
    required this.tituloFila,
    this.subtituloFila,
    required this.campos,
    this.tipoFiltro,
    this.filtrarTipoUI = false,
  });

  String idDe(Map<String, dynamic> fila) =>
      '${fila[idKey] ?? fila['id'] ?? ''}';

  bool pasaTipoFiltro(Map<String, dynamic> fila) {
    final t = tipoFiltro;
    if (t == null) return true;
    final tipo = (fila['tipo'] as String?) ?? '';
    return tipo == t || tipo == 'AMBOS';
  }

  /// Clave del primer campo tipo foto (para mostrar miniatura en la lista).
  String? get campoFotoKey {
    for (final c in campos) {
      if (c.tipo == CatalogFieldType.foto) return c.key;
    }
    return null;
  }
}

class CatalogSection {
  final String titulo;
  final IconData icono;
  final List<CatalogResource> recursos;
  final String Function(List<Map<String, dynamic>>)? etiquetaResumen;

  const CatalogSection({
    required this.titulo,
    required this.icono,
    required this.recursos,
    this.etiquetaResumen,
  });
}

class AppCatalogos {
  static final _camiones = CatalogResource(
    clave: 'camiones',
    plural: 'Camiones',
    singular: 'Camión',
    icono: Icons.directions_car_outlined,
    listaPath: ApiConstants.camiones,
    itemPath: ApiConstants.camion,
    idKey: 'id',
    tituloFila: (f) => '${f['placa'] ?? ''}',
    subtituloFila: (f) {
      final partes = <String>[
        if (f['color'] != null) f['color'] as String,
        if (f['tara_habitual'] != null) 'Tara ${f['tara_habitual']} kg',
      ];
      return partes.isEmpty ? null : partes.join(' · ');
    },
    campos: [
      const CatalogField(
        key: 'placa',
        label: 'Placa',
        icono: Icons.tag_outlined,
        requerido: true,
      ),
      const CatalogField(
        key: 'transporte_id',
        label: 'Transporte',
        icono: Icons.fire_truck_outlined,
        catalogoPath: ApiConstants.transportes,
        catalogoIdKey: 'id_transporte',
        catalogoTituloKey: 'razon_social',
      ),
      const CatalogField(
        key: 'color',
        label: 'Color',
        icono: Icons.palette_outlined,
      ),
      const CatalogField(
        key: 'tara_habitual',
        label: 'Tara habitual (kg)',
        icono: Icons.fitness_center,
        tipo: CatalogFieldType.numero,
      ),
      const CatalogField(
        key: 'foto_real_url',
        label: 'Foto del camión',
        icono: Icons.image_outlined,
        tipo: CatalogFieldType.foto,
      ),
    ],
  );

  static final _remolques = CatalogResource(
    clave: 'remolques',
    plural: 'Remolques',
    singular: 'Remolque',
    icono: Icons.local_shipping_outlined,
    listaPath: ApiConstants.remolques,
    itemPath: ApiConstants.remolque,
    idKey: 'id_remolque',
    tituloFila: (f) => '${f['placa'] ?? ''}',
    subtituloFila: (f) {
      final partes = <String>[
        if (f['tipo_remolque'] != null) f['tipo_remolque'] as String,
        if (f['tara_habitual'] != null) 'Tara ${f['tara_habitual']} kg',
      ];
      return partes.isEmpty ? null : partes.join(' · ');
    },
    campos: [
      const CatalogField(
        key: 'placa',
        label: 'Placa',
        icono: Icons.tag_outlined,
        requerido: true,
      ),
      const CatalogField(
        key: 'tipo_remolque',
        label: 'Tipo de remolque',
        icono: Icons.category_outlined,
      ),
      const CatalogField(
        key: 'tara_habitual',
        label: 'Tara habitual (kg)',
        icono: Icons.fitness_center,
        tipo: CatalogFieldType.numero,
      ),
      const CatalogField(
        key: 'foto_url',
        label: 'Foto del remolque',
        icono: Icons.image_outlined,
        tipo: CatalogFieldType.foto,
      ),
    ],
  );

  static final _productos = CatalogResource(
    clave: 'productos',
    plural: 'Productos',
    singular: 'Producto',
    icono: Icons.inventory_2_outlined,
    listaPath: ApiConstants.productos,
    itemPath: ApiConstants.producto,
    idKey: 'id_producto',
    tituloFila: (f) => '${f['nombre'] ?? ''}',
    subtituloFila: (f) {
      final partes = <String>[
        if (f['codigo'] != null) f['codigo'] as String,
        if (f['categoria_nombre'] != null) f['categoria_nombre'] as String,
      ];
      return partes.isEmpty ? null : partes.join(' · ');
    },
    campos: [
      const CatalogField(
        key: 'id_categoria',
        label: 'Categoría',
        icono: Icons.category_outlined,
        tipo: CatalogFieldType.dropdown,
        requerido: true,
        catalogoPath: ApiConstants.categorias,
        catalogoIdKey: 'id_categoria',
        catalogoTituloKey: 'nombre',
        hint: 'Seleccionar la categoría del producto',
      ),
      const CatalogField(
        key: 'codigo',
        label: 'Código',
        icono: Icons.numbers_outlined,
      ),
      const CatalogField(
        key: 'nombre',
        label: 'Nombre',
        icono: Icons.badge_outlined,
        requerido: true,
      ),
      const CatalogField(
        key: 'descripcion',
        label: 'Descripción',
        icono: Icons.notes_outlined,
        tipo: CatalogFieldType.multilinea,
      ),
      const CatalogField(
        key: 'densidad_estandar',
        label: 'Densidad estándar',
        icono: Icons.speed_outlined,
        tipo: CatalogFieldType.numero,
      ),
      const CatalogField(
        key: 'unidad_medida',
        label: 'Unidad de medida',
        icono: Icons.straighten_outlined,
        tipo: CatalogFieldType.dropdown,
        opciones: ['TON', 'KG', 'LBS', 'UN'],
      ),
    ],
  );

  static final _almacenes = CatalogResource(
    clave: 'almacenes',
    plural: 'Almacenes',
    singular: 'Almacén',
    icono: Icons.warehouse_outlined,
    listaPath: ApiConstants.almacenes,
    itemPath: ApiConstants.almacen,
    idKey: 'id_almacen',
    tituloFila: (f) => '${f['nombre'] ?? ''}',
    subtituloFila: (f) {
      final partes = <String>[
        if (f['codigo'] != null) f['codigo'] as String,
        if (f['ubicacion'] != null) f['ubicacion'] as String,
      ];
      return partes.isEmpty ? null : partes.join(' · ');
    },
    campos: [
      const CatalogField(
        key: 'codigo',
        label: 'Código',
        icono: Icons.numbers_outlined,
      ),
      const CatalogField(
        key: 'nombre',
        label: 'Nombre',
        icono: Icons.badge_outlined,
        requerido: true,
      ),
      const CatalogField(
        key: 'ubicacion',
        label: 'Ubicación',
        icono: Icons.place_outlined,
      ),
      const CatalogField(
        key: 'capacidad_max_ton',
        label: 'Capacidad máxima (ton)',
        icono: Icons.scale_outlined,
        tipo: CatalogFieldType.numero,
      ),
      const CatalogField(
        key: 'stock_actual_ton',
        label: 'Stock actual (ton)',
        icono: Icons.inventory_outlined,
        tipo: CatalogFieldType.numero,
      ),
    ],
  );

  static final _categorias = CatalogResource(
    clave: 'categorias',
    plural: 'Categorías',
    singular: 'Categoría',
    icono: Icons.category_outlined,
    listaPath: ApiConstants.categorias,
    itemPath: ApiConstants.categoria,
    idKey: 'id_categoria',
    tituloFila: (f) => '${f['nombre'] ?? ''}',
    subtituloFila: (f) {
      final partes = <String>[
        if (f['codigo'] != null) f['codigo'] as String,
        if (f['descripcion'] != null) f['descripcion'] as String,
      ];
      return partes.isEmpty ? null : partes.join(' · ');
    },
    campos: [
      const CatalogField(
        key: 'codigo',
        label: 'Código',
        icono: Icons.numbers_outlined,
      ),
      const CatalogField(
        key: 'nombre',
        label: 'Nombre',
        icono: Icons.badge_outlined,
        requerido: true,
      ),
      const CatalogField(
        key: 'descripcion',
        label: 'Descripción',
        icono: Icons.notes_outlined,
        tipo: CatalogFieldType.multilinea,
      ),
    ],
  );

  static final _balanzas = CatalogResource(
    clave: 'balanzas',
    plural: 'Balanzas',
    singular: 'Balanza',
    icono: Icons.scale_outlined,
    listaPath: ApiConstants.balanzas,
    itemPath: ApiConstants.balanza,
    idKey: 'id_balanza',
    tituloFila: (f) => '${f['descripcion'] ?? ''}',
    subtituloFila: (f) {
      final partes = <String>[
        if (f['codigo'] != null) f['codigo'] as String,
        if (f['marca'] != null) f['marca'] as String,
        if (f['capacidad_max'] != null) 'Máx ${f['capacidad_max']}',
      ];
      return partes.isEmpty ? null : partes.join(' · ');
    },
    campos: [
      const CatalogField(
        key: 'codigo',
        label: 'Código',
        icono: Icons.numbers_outlined,
      ),
      const CatalogField(
        key: 'descripcion',
        label: 'Descripción',
        icono: Icons.badge_outlined,
        requerido: true,
      ),
      const CatalogField(
        key: 'marca',
        label: 'Marca',
        icono: Icons.local_offer_outlined,
      ),
      const CatalogField(
        key: 'modelo',
        label: 'Modelo',
        icono: Icons.model_training,
      ),
      const CatalogField(
        key: 'capacidad_max',
        label: 'Capacidad máxima',
        icono: Icons.scale_outlined,
        tipo: CatalogFieldType.numero,
      ),
      const CatalogField(
        key: 'division',
        label: 'División',
        icono: Icons.vibration_outlined,
        tipo: CatalogFieldType.numero,
      ),
    ],
  );

  static final _transportes = CatalogResource(
    clave: 'transportes',
    plural: 'Transportes',
    singular: 'Transporte',
    icono: Icons.fire_truck_outlined,
    listaPath: ApiConstants.transportes,
    itemPath: ApiConstants.transporte,
    idKey: 'id_transporte',
    tituloFila: (f) => '${f['razon_social'] ?? ''}',
    subtituloFila: (f) {
      final partes = <String>[
        if (f['codigo'] != null) f['codigo'] as String,
        if (f['identificacion_fiscal'] != null)
          f['identificacion_fiscal'] as String,
      ];
      return partes.isEmpty ? null : partes.join(' · ');
    },
    campos: [
      const CatalogField(
        key: 'codigo',
        label: 'Código',
        icono: Icons.numbers_outlined,
      ),
      const CatalogField(
        key: 'razon_social',
        label: 'Razón social',
        icono: Icons.badge_outlined,
        requerido: true,
      ),
      const CatalogField(
        key: 'identificacion_fiscal',
        label: 'RIF / Identificación fiscal',
        icono: Icons.badge_outlined,
      ),
      const CatalogField(
        key: 'telefono',
        label: 'Teléfono',
        icono: Icons.phone_outlined,
      ),
      const CatalogField(
        key: 'contacto',
        label: 'Contacto',
        icono: Icons.person_outline,
      ),
    ],
  );

  static final _conductores = CatalogResource(
    clave: 'conductores',
    plural: 'Conductores',
    singular: 'Conductor',
    icono: Icons.person_outline,
    listaPath: ApiConstants.conductores,
    itemPath: ApiConstants.conductor,
    idKey: 'cedula_dni',
    tituloFila: (f) => '${f['nombre_completo'] ?? ''}',
    subtituloFila: (f) {
      final partes = <String>[
        '${f['cedula_dni'] ?? ''}',
        if (f['licencia_conducir'] != null) f['licencia_conducir'] as String,
      ];
      return partes.isEmpty ? null : partes.join(' · ');
    },
    campos: [
      const CatalogField(
        key: 'cedula_dni',
        label: 'Cédula / DNI',
        icono: Icons.badge_outlined,
        requerido: true,
      ),
      const CatalogField(
        key: 'nombre_completo',
        label: 'Nombre completo',
        icono: Icons.person_outline,
        requerido: true,
      ),
      const CatalogField(
        key: 'telefono',
        label: 'Teléfono',
        icono: Icons.phone_outlined,
      ),
      const CatalogField(
        key: 'licencia_conducir',
        label: 'Licencia de conducir',
        icono: Icons.credit_card_outlined,
      ),
      const CatalogField(
        key: 'foto_url',
        label: 'Foto del conductor',
        icono: Icons.image_outlined,
        tipo: CatalogFieldType.foto,
      ),
    ],
  );

  static final _terceros = CatalogResource(
    clave: 'terceros',
    plural: 'Terceros',
    singular: 'Tercero',
    icono: Icons.business_outlined,
    listaPath: ApiConstants.terceros,
    itemPath: ApiConstants.tercero,
    idKey: 'id_tercero',
    tituloFila: (f) => '${f['razon_social'] ?? ''}',
    subtituloFila: (f) {
      final partes = <String>[
        if (f['codigo'] != null) f['codigo'] as String,
        if (f['identificacion_fiscal'] != null)
          f['identificacion_fiscal'] as String,
      ];
      return partes.isEmpty ? null : partes.join(' · ');
    },
    campos: [
      const CatalogField(
        key: 'codigo',
        label: 'Código',
        icono: Icons.numbers_outlined,
      ),
      const CatalogField(
        key: 'tipo',
        label: 'Tipo',
        icono: Icons.category_outlined,
        tipo: CatalogFieldType.dropdown,
        opciones: ['CLIENTE', 'PROVEEDOR', 'AMBOS'],
        opcionLabels: ['Cliente', 'Proveedor', 'Cliente/Proveedor'],
        requerido: true,
      ),
      const CatalogField(
        key: 'razon_social',
        label: 'Razón social',
        icono: Icons.badge_outlined,
        requerido: true,
      ),
      const CatalogField(
        key: 'identificacion_fiscal',
        label: 'RIF / Identificación fiscal',
        icono: Icons.badge_outlined,
      ),
      const CatalogField(
        key: 'direccion',
        label: 'Dirección',
        icono: Icons.place_outlined,
        tipo: CatalogFieldType.multilinea,
      ),
      const CatalogField(
        key: 'telefono',
        label: 'Teléfono',
        icono: Icons.phone_outlined,
      ),
      const CatalogField(
        key: 'email',
        label: 'Email',
        icono: Icons.email_outlined,
        tipo: CatalogFieldType.email,
      ),
    ],
  );

  static final _clientes = CatalogResource(
    clave: 'clientes',
    plural: 'Clientes',
    singular: 'Cliente',
    icono: Icons.people_outline,
    listaPath: ApiConstants.terceros,
    itemPath: ApiConstants.tercero,
    idKey: 'id_tercero',
    tipoFiltro: 'CLIENTE',
    tituloFila: (f) => '${f['razon_social'] ?? ''}',
    subtituloFila: (f) {
      final partes = <String>[
        if (f['codigo'] != null) f['codigo'] as String,
        if (f['identificacion_fiscal'] != null)
          f['identificacion_fiscal'] as String,
      ];
      return partes.isEmpty ? null : partes.join(' · ');
    },
    campos: _terceros.campos,
  );

  static final _proveedores = CatalogResource(
    clave: 'proveedores',
    plural: 'Proveedores',
    singular: 'Proveedor',
    icono: Icons.store_outlined,
    listaPath: ApiConstants.terceros,
    itemPath: ApiConstants.tercero,
    idKey: 'id_tercero',
    tipoFiltro: 'PROVEEDOR',
    tituloFila: (f) => '${f['razon_social'] ?? ''}',
    subtituloFila: (f) {
      final partes = <String>[
        if (f['codigo'] != null) f['codigo'] as String,
        if (f['identificacion_fiscal'] != null)
          f['identificacion_fiscal'] as String,
      ];
      return partes.isEmpty ? null : partes.join(' · ');
    },
    campos: _terceros.campos,
  );

  static final _clientesYProveedores = CatalogResource(
    clave: 'terceros',
    plural: 'Clientes / Proveedores',
    singular: 'Cliente/Proveedor',
    icono: Icons.people_outline,
    listaPath: ApiConstants.terceros,
    itemPath: ApiConstants.tercero,
    idKey: 'id_tercero',
    filtrarTipoUI: true,
    tituloFila: (f) => '${f['razon_social'] ?? ''}',
    subtituloFila: (f) {
      final partes = <String>[
        if (f['codigo'] != null) f['codigo'] as String,
        if (f['identificacion_fiscal'] != null)
          f['identificacion_fiscal'] as String,
        if (f['tipo'] != null) _tipoTerceroLabel(f['tipo'] as String),
      ];
      return partes.isEmpty ? null : partes.join(' · ');
    },
    campos: _terceros.campos,
  );

  /// Etiqueta legible del rol de un tercero (CLIENTE / PROVEEDOR / AMBOS).
  static String _tipoTerceroLabel(String tipo) {
    return switch (tipo) {
      'CLIENTE' => 'Cliente',
      'PROVEEDOR' => 'Proveedor',
      'AMBOS' => 'Cliente/Proveedor',
      _ => tipo,
    };
  }

  /// Grupos de navegación según `docs/MODELO_ESTANDAR.md`.

  static final CatalogSection clientes = CatalogSection(
    titulo: 'Clientes',
    icono: Icons.people_outline,
    recursos: [_clientes],
  );

  static final CatalogSection proveedores = CatalogSection(
    titulo: 'Proveedores',
    icono: Icons.store_outlined,
    recursos: [_proveedores],
  );

  static final CatalogSection clientesYProveedores = CatalogSection(
    titulo: 'Clientes / Proveedores',
    icono: Icons.people_outline,
    recursos: [_clientesYProveedores],
  );

  static final CatalogSection flotaYTransporte = CatalogSection(
    titulo: 'Flota y Transporte',
    icono: Icons.local_shipping_outlined,
    recursos: [_camiones, _remolques, _transportes, _conductores],
  );

  static final CatalogSection inventarioBase = CatalogSection(
    titulo: 'Inventario Base',
    icono: Icons.inventory_2_outlined,
    recursos: [_productos, _categorias, _almacenes, _balanzas],
  );

  static final CatalogSection flota = CatalogSection(
    titulo: 'Flota',
    icono: Icons.directions_car_outlined,
    recursos: [_camiones, _remolques],
  );

  static final CatalogSection vehiculosYChutos = CatalogSection(
    titulo: 'Vehículos / Chutos',
    icono: Icons.directions_car_outlined,
    recursos: [_camiones, _remolques],
  );

  static final CatalogSection inventario = CatalogSection(
    titulo: 'Inventario',
    icono: Icons.inventory_2_outlined,
    recursos: [_productos, _categorias, _almacenes, _balanzas],
  );

  static final CatalogSection directorio = CatalogSection(
    titulo: 'Directorio',
    icono: Icons.people_outline,
    recursos: [_transportes, _conductores, _terceros],
  );

  static final List<CatalogSection> secciones = [flota, inventario, directorio];

  /// Accesos públicos a recursos individuales (para navegación directa desde
  /// el sidebar según docs/NAV.md).
  static CatalogResource get camionResource => _camiones;
  static CatalogResource get conductorResource => _conductores;
  static CatalogResource get transporteResource => _transportes;
  static CatalogResource get productoResource => _productos;
  static CatalogResource get categoriaResource => _categorias;
  static CatalogResource get almacenResource => _almacenes;
  static CatalogResource get tercerosResource => _clientesYProveedores;
}
