import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'balansoft_ws.db');

    return await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE weighing_local ADD COLUMN id_remolque TEXT');
      await db.execute(
          'ALTER TABLE weighing_local ADD COLUMN costo_flete REAL');
    }
    if (oldVersion < 3) {
      for (final col in [
        'ADD COLUMN numero_boleto TEXT',
        'ADD COLUMN peso_neto_declarado REAL',
        'ADD COLUMN peso_diferencia REAL',
        'ADD COLUMN porcentaje_desviacion REAL',
        'ADD COLUMN motivo_anulacion TEXT',
      ]) {
        try {
          await db.execute('ALTER TABLE weighing_local $col');
        } catch (_) {}
      }
    }
    if (oldVersion < 4) {
      await db.execute(
          'ALTER TABLE weighing_local ADD COLUMN fallido INTEGER DEFAULT 0');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE weighing_local (
        boleto TEXT PRIMARY KEY,
            numero_boleto TEXT,
            id_vehiculo TEXT,
            remolque INTEGER DEFAULT 0,
            id_remolque TEXT,
            id_transporte TEXT,
        id_conductor TEXT,
        id_producto TEXT,
        id_almacen TEXT,
        id_balanza TEXT,
        tipo_tercero TEXT,
        id_tercero TEXT,
        multi_despacho_recepcion INTEGER DEFAULT 0,
        fecha_hora_entrada TEXT,
        fecha_hora_salida TEXT,
        peso_entrada_vehiculo REAL DEFAULT 0,
        peso_entrada_remolque REAL,
        peso_salida_vehiculo REAL,
        peso_salida_remolque REAL,
        peso_bruto REAL,
        peso_tara REAL,
        peso_neto REAL,
        peso_neto_declarado REAL,
        peso_diferencia REAL,
        porcentaje_desviacion REAL,
        diferencia_peso REAL,
        porcentaje_diferencia REAL,
        densidad REAL,
        litros REAL,
        unidades REAL,
        flete TEXT,
        costo_flete REAL,
        documento TEXT,
        observaciones TEXT,
        motivo_anulacion TEXT,
        estado_boleto TEXT DEFAULT 'PENDIENTE',
        sincronizado INTEGER DEFAULT 0,
        pendiente INTEGER DEFAULT 0,
        intentos_sync INTEGER DEFAULT 0,
        fallido INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE catalog_local (
        id TEXT PRIMARY KEY,
        tipo TEXT,
        codigo TEXT,
        nombre TEXT,
        descripcion TEXT,
        activo INTEGER DEFAULT 1,
        extra_json TEXT,
        updated_at TEXT
      )
    ''');
  }
}
