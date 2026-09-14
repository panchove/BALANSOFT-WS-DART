import 'package:flutter/material.dart';

import 'api_constants.dart';

enum CatalogFieldType { texto, multilinea, numero, entero, dropdown, email, foto }

class CatalogField {
  final String key;
  final String label;
  final IconData icono;
  final CatalogFieldType tipo;
  final bool requerido;
  final List<String>? opciones;
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
  });

  String idDe(Map<String, dynamic> fila) =>
      '${fila[idKey] ?? fila['id'] ?? ''}';

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
    subtituloFila: (f) => f['codigo'] as String?,
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

  static final CatalogSection flota = CatalogSection(
    titulo: 'Flota',
    icono: Icons.directions_car_outlined,
    recursos: [_camiones, _remolques],
  );

  static final CatalogSection inventario = CatalogSection(
    titulo: 'Inventario',
    icono: Icons.inventory_2_outlined,
    recursos: [_productos, _almacenes, _balanzas],
  );

  static final CatalogSection directorio = CatalogSection(
    titulo: 'Directorio',
    icono: Icons.people_outline,
    recursos: [_transportes, _conductores, _terceros],
  );

  static final List<CatalogSection> secciones = [flota, inventario, directorio];
}