import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/entities/catalogs.dart';
import '../../domain/repositories/i_catalog_repository.dart';
import '../datasources/local/database_helper.dart';
import '../datasources/remote/api_client.dart';

class CatalogRepository implements ICatalogRepository {
  final ApiClient _apiClient;
  final DatabaseHelper _dbHelper;
  final Connectivity _connectivity;

  CatalogRepository({
    required ApiClient apiClient,
    required DatabaseHelper dbHelper,
    required Connectivity connectivity,
  })  : _apiClient = apiClient,
        _dbHelper = dbHelper,
        _connectivity = connectivity;

  Future<bool> get _isConnected async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  @override
  Future<CatalogData> syncCatalogs() async {
    if (await _isConnected) {
      try {
        final response = await _apiClient.getCatalogSync();
        final data = _parse(response.data as Map<String, dynamic>);
        await _cacheAll(data);
        return data;
      } catch (_) {}
    }
    final cached = await getCachedCatalogs();
    return cached ?? CatalogData.empty;
  }

  @override
  Future<CatalogData?> getCachedCatalogs() async {
    final db = await _dbHelper.database;
    final rows = await db.query('catalog_local');
    if (rows.isEmpty) return null;

    final camiones = <Camion>[];
    final trailers = <Trailer>[];
    final marcas = <Marca>[];
    final modelosCamion = <ModeloCamion>[];
    final transports = <Transport>[];
    final drivers = <Driver>[];
    final products = <Product>[];
    final warehouses = <Warehouse>[];
    final scales = <Scale>[];
    final thirdParties = <ThirdParty>[];

    for (final row in rows) {
      final extra = row['extra_json'] as String?;
      if (extra == null || extra.isEmpty) continue;
      final Map<String, dynamic> map;
      try {
        map = jsonDecode(extra) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      switch (row['tipo']) {
        case 'camion':
          camiones.add(Camion.fromJson(map));
        case 'remolque':
          trailers.add(Trailer.fromJson(map));
        case 'marca':
          marcas.add(Marca.fromJson(map));
        case 'modelo_camion':
          modelosCamion.add(ModeloCamion.fromJson(map));
        case 'transporte':
          transports.add(Transport.fromJson(map));
        case 'conductor':
          drivers.add(Driver.fromJson(map));
        case 'producto':
          products.add(Product.fromJson(map));
        case 'almacen':
          warehouses.add(Warehouse.fromJson(map));
        case 'balanza':
          scales.add(Scale.fromJson(map));
        case 'tercero':
          thirdParties.add(ThirdParty.fromJson(map));
      }
    }

    return CatalogData(
      camiones: camiones,
      trailers: trailers,
      marcas: marcas,
      modelosCamion: modelosCamion,
      transports: transports,
      drivers: drivers,
      products: products,
      warehouses: warehouses,
      scales: scales,
      thirdParties: thirdParties,
    );
  }

  CatalogData _parse(Map<String, dynamic> json) => CatalogData(
        camiones: (json['camiones'] as List? ?? [])
            .map((e) => Camion.fromJson(e as Map<String, dynamic>))
            .toList(),
        trailers: (json['remolques'] as List? ?? [])
            .map((e) => Trailer.fromJson(e as Map<String, dynamic>))
            .toList(),
        marcas: (json['marcas'] as List? ?? [])
            .map((e) => Marca.fromJson(e as Map<String, dynamic>))
            .toList(),
        modelosCamion: (json['modelos_camion'] as List? ?? [])
            .map((e) => ModeloCamion.fromJson(e as Map<String, dynamic>))
            .toList(),
        transports: (json['transportes'] as List? ?? [])
            .map((e) => Transport.fromJson(e as Map<String, dynamic>))
            .toList(),
        drivers: (json['conductores'] as List? ?? [])
            .map((e) => Driver.fromJson(e as Map<String, dynamic>))
            .toList(),
        products: (json['productos'] as List? ?? [])
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList(),
        warehouses: (json['almacenes'] as List? ?? [])
            .map((e) => Warehouse.fromJson(e as Map<String, dynamic>))
            .toList(),
        scales: (json['balanzas'] as List? ?? [])
            .map((e) => Scale.fromJson(e as Map<String, dynamic>))
            .toList(),
        thirdParties: (json['terceros'] as List? ?? [])
            .map((e) => ThirdParty.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Future<void> _cacheAll(CatalogData data) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('catalog_local');
      for (final c in data.camiones) {
        await _upsert(
          txn,
          tipo: 'camion',
          id: c.id,
          codigo: c.placa,
          nombre: c.placa,
          descripcion: c.color,
          json: c.toJson(),
        );
      }
      for (final t in data.trailers) {
        await _upsert(
          txn,
          tipo: 'remolque',
          id: t.id,
          codigo: t.placa,
          nombre: t.placa,
          descripcion: t.tipo,
          json: t.toJson(),
        );
      }
      for (final m in data.marcas) {
        await _upsert(
          txn,
          tipo: 'marca',
          id: m.id,
          codigo: null,
          nombre: m.nombre,
          descripcion: null,
          json: m.toJson(),
        );
      }
      for (final m in data.modelosCamion) {
        await _upsert(
          txn,
          tipo: 'modelo_camion',
          id: m.id,
          codigo: m.marcaId,
          nombre: m.nombre,
          descripcion:
              m.capacidadCargaTon?.toStringAsFixed(2),
          json: m.toJson(),
        );
      }
      for (final t in data.transports) {
        await _upsert(
          txn,
          tipo: 'transporte',
          id: t.id,
          codigo: t.codigo,
          nombre: t.razonSocial,
          descripcion: t.contacto,
          json: t.toJson(),
        );
      }
      for (final d in data.drivers) {
        await _upsert(
          txn,
          tipo: 'conductor',
          id: d.cedulaDni,
          codigo: d.cedulaDni,
          nombre: d.nombreCompleto,
          descripcion: d.licenciaConducir,
          json: d.toJson(),
        );
      }
      for (final p in data.products) {
        await _upsert(
          txn,
          tipo: 'producto',
          id: p.id,
          codigo: p.codigo,
          nombre: p.nombre,
          descripcion: p.descripcion,
          json: p.toJson(),
        );
      }
      for (final w in data.warehouses) {
        await _upsert(
          txn,
          tipo: 'almacen',
          id: w.id,
          codigo: w.codigo,
          nombre: w.nombre,
          descripcion: w.ubicacion,
          json: w.toJson(),
        );
      }
      for (final s in data.scales) {
        await _upsert(
          txn,
          tipo: 'balanza',
          id: s.id,
          codigo: s.codigo,
          nombre: s.descripcion,
          descripcion: s.marca,
          json: s.toJson(),
        );
      }
      for (final t in data.thirdParties) {
        await _upsert(
          txn,
          tipo: 'tercero',
          id: t.id,
          codigo: t.codigo,
          nombre: t.razonSocial,
          descripcion: t.identificacionFiscal,
          json: t.toJson(),
        );
      }
    });
  }

  Future<void> _upsert(
    DatabaseExecutor txn, {
    required String tipo,
    required String id,
    required String? codigo,
    required String? nombre,
    String? descripcion,
    required Map<String, dynamic> json,
  }) async {
    await txn.insert(
      'catalog_local',
      {
        'id': '$tipo:$id',
        'tipo': tipo,
        'codigo': codigo,
        'nombre': nombre,
        'descripcion': descripcion,
        'activo': 1,
        'extra_json': jsonEncode(json),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}