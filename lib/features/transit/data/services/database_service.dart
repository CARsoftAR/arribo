import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FavoriteStop {
  final String id;
  final String name;

  FavoriteStop({required this.id, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'name': name};
}

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    // Ensure shapes are loaded from local assets if needed
    ensureShapesLoaded();
    return _database!;
  }

  Future<void> syncOfficialShapes() async {
    try {
      final response = await http.get(Uri.parse(
        'https://raw.githubusercontent.com/CARsoftAR/arribo/main/assets/data/official_gtfs_shapes.json'
      )).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> shapesList = jsonDecode(response.body);
        final db = await database;
        await db.transaction((txn) async {
          for (var shape in shapesList) {
            final shapeId = shape['shape_id'] as String;
            final lat = (shape['shape_pt_lat'] as num).toDouble();
            final lon = (shape['shape_pt_lon'] as num).toDouble();
            final seq = shape['shape_pt_sequence'] as int;

            await txn.insert('shapes', {
              'shape_id': shapeId,
              'shape_pt_lat': lat,
              'shape_pt_lon': lon,
              'shape_pt_sequence': seq,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        });
        print('[Database] Official GTFS shapes synced successfully!');
      }
    } catch (e) {
      print('[Database] Official shapes sync skipped: $e (Using local fallback detailed JSONs)');
    }
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'arribo_favorites.db');
    return await openDatabase(
      path,
      version: 14,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE favorites(id TEXT PRIMARY KEY, name TEXT)');
        await _createOfflineTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createOfflineTables(db);
        }
        if (oldVersion < 3) {
          await db.execute('CREATE TABLE IF NOT EXISTS shapes (shape_id TEXT, shape_pt_lat REAL, shape_pt_lon REAL, shape_pt_sequence INTEGER, PRIMARY KEY (shape_id, shape_pt_sequence))');
          await _seedShapesTable(db);
        }
        if (oldVersion < 4) {
          // Force drop and clean re-seed of shapes and routes to get the full 35km paths
          await db.execute('DROP TABLE IF EXISTS shapes');
          await db.execute('DROP TABLE IF EXISTS routes');
          await db.execute('CREATE TABLE IF NOT EXISTS shapes (shape_id TEXT, shape_pt_lat REAL, shape_pt_lon REAL, shape_pt_sequence INTEGER, PRIMARY KEY (shape_id, shape_pt_sequence))');
          await db.execute('CREATE TABLE IF NOT EXISTS routes (id TEXT PRIMARY KEY, line TEXT, route_points TEXT)');
          await _seedShapesTable(db);
          await _seedRoutesTable(db);
        }
        if (oldVersion < 5) {
          // Force drop and clean re-seed of shapes and routes to get the full 35km paths and branch shapes
          await db.execute('DROP TABLE IF EXISTS shapes');
          await db.execute('DROP TABLE IF EXISTS routes');
          await db.execute('CREATE TABLE IF NOT EXISTS shapes (shape_id TEXT, shape_pt_lat REAL, shape_pt_lon REAL, shape_pt_sequence INTEGER, PRIMARY KEY (shape_id, shape_pt_sequence))');
          await db.execute('CREATE TABLE IF NOT EXISTS routes (id TEXT PRIMARY KEY, line TEXT, route_points TEXT)');
          await _seedShapesTable(db);
          await _seedRoutesTable(db);
        }
        if (oldVersion < 6) {
          // Force drop and clean re-seed of shapes and routes to get the full 35km paths and branch shapes
          await db.execute('DROP TABLE IF EXISTS shapes');
          await db.execute('DROP TABLE IF EXISTS routes');
          await db.execute('CREATE TABLE IF NOT EXISTS shapes (shape_id TEXT, shape_pt_lat REAL, shape_pt_lon REAL, shape_pt_sequence INTEGER, PRIMARY KEY (shape_id, shape_pt_sequence))');
          await db.execute('CREATE TABLE IF NOT EXISTS routes (id TEXT PRIMARY KEY, line TEXT, route_points TEXT)');
          await _seedShapesTable(db);
          await _seedRoutesTable(db);
        }
        if (oldVersion < 7) {
          // Force drop and clean re-seed with OSRM high-resolution street-aligned geometries
          await db.execute('DROP TABLE IF EXISTS shapes');
          await db.execute('DROP TABLE IF EXISTS routes');
          await db.execute('CREATE TABLE IF NOT EXISTS shapes (shape_id TEXT, shape_pt_lat REAL, shape_pt_lon REAL, shape_pt_sequence INTEGER, PRIMARY KEY (shape_id, shape_pt_sequence))');
          await db.execute('CREATE TABLE IF NOT EXISTS routes (id TEXT PRIMARY KEY, line TEXT, route_points TEXT)');
          await _seedShapesTable(db);
          await _seedRoutesTable(db);
        }
        if (oldVersion < 8) {
          // Force drop and clean re-seed with OSRM high-precision avenue-only geometries
          await db.execute('DROP TABLE IF EXISTS shapes');
          await db.execute('DROP TABLE IF EXISTS routes');
          await db.execute('CREATE TABLE IF NOT EXISTS shapes (shape_id TEXT, shape_pt_lat REAL, shape_pt_lon REAL, shape_pt_sequence INTEGER, PRIMARY KEY (shape_id, shape_pt_sequence))');
          await db.execute('CREATE TABLE IF NOT EXISTS routes (id TEXT PRIMARY KEY, line TEXT, route_points TEXT)');
          await _seedShapesTable(db);
          await _seedRoutesTable(db);
        }
        if (oldVersion < 9) {
          // Force drop and clean re-seed with OSRM high-precision separate branch geometries for all six branches
          await db.execute('DROP TABLE IF EXISTS shapes');
          await db.execute('DROP TABLE IF EXISTS routes');
          await db.execute('CREATE TABLE IF NOT EXISTS shapes (shape_id TEXT, shape_pt_lat REAL, shape_pt_lon REAL, shape_pt_sequence INTEGER, PRIMARY KEY (shape_id, shape_pt_sequence))');
          await db.execute('CREATE TABLE IF NOT EXISTS routes (id TEXT PRIMARY KEY, line TEXT, route_points TEXT)');
          await _seedShapesTable(db);
          await _seedRoutesTable(db);
        }
        if (oldVersion < 10) {
          // Force drop and clean re-seed with official dynamic shape support
          await db.execute('DROP TABLE IF EXISTS shapes');
          await db.execute('DROP TABLE IF EXISTS routes');
          await db.execute('CREATE TABLE IF NOT EXISTS shapes (shape_id TEXT, shape_pt_lat REAL, shape_pt_lon REAL, shape_pt_sequence INTEGER, PRIMARY KEY (shape_id, shape_pt_sequence))');
          await db.execute('CREATE TABLE IF NOT EXISTS routes (id TEXT PRIMARY KEY, line TEXT, route_points TEXT)');
          await _seedShapesTable(db);
          await _seedRoutesTable(db);
        }
        if (oldVersion < 11) {
          // Force drop and clean re-seed with official dynamic shapes and correct stop sequences
          await db.execute('DROP TABLE IF EXISTS shapes');
          await db.execute('DROP TABLE IF EXISTS routes');
          await db.execute('DROP TABLE IF EXISTS stops');
          await db.execute('CREATE TABLE IF NOT EXISTS shapes (shape_id TEXT, shape_pt_lat REAL, shape_pt_lon REAL, shape_pt_sequence INTEGER, PRIMARY KEY (shape_id, shape_pt_sequence))');
          await db.execute('CREATE TABLE IF NOT EXISTS routes (id TEXT PRIMARY KEY, line TEXT, route_points TEXT)');
          await db.execute('CREATE TABLE IF NOT EXISTS stops (id TEXT PRIMARY KEY, line TEXT, name TEXT, latitude REAL, longitude REAL, sequence INTEGER)');
          await _seedShapesTable(db);
          await _seedRoutesTable(db);
          await _seedStopsTable(db);
        }
        if (oldVersion < 12) {
          // Force drop and clean re-seed with correct Acceso Sudeste highway geometry for Ramal 2
          await db.execute('DROP TABLE IF EXISTS shapes');
          await db.execute('DROP TABLE IF EXISTS routes');
          await db.execute('DROP TABLE IF EXISTS stops');
          await db.execute('CREATE TABLE IF NOT EXISTS shapes (shape_id TEXT, shape_pt_lat REAL, shape_pt_lon REAL, shape_pt_sequence INTEGER, PRIMARY KEY (shape_id, shape_pt_sequence))');
          await db.execute('CREATE TABLE IF NOT EXISTS routes (id TEXT PRIMARY KEY, line TEXT, route_points TEXT)');
          await db.execute('CREATE TABLE IF NOT EXISTS stops (id TEXT PRIMARY KEY, line TEXT, name TEXT, latitude REAL, longitude REAL, sequence INTEGER)');
          await _seedShapesTable(db);
          await _seedRoutesTable(db);
          await _seedStopsTable(db);
        }
        if (oldVersion < 13) {
          await db.execute('CREATE INDEX IF NOT EXISTS idx_shapes_shape_sequence ON shapes(shape_id, shape_pt_sequence)');
        }
        if (oldVersion < 14) {
          // Force drop shapes table and seed with official shapes_filtrados.txt from GTFS AMBA
          await db.execute('DROP TABLE IF EXISTS shapes');
          await db.execute('CREATE TABLE IF NOT EXISTS shapes (shape_id TEXT, shape_pt_lat REAL, shape_pt_lon REAL, shape_pt_sequence INTEGER, PRIMARY KEY (shape_id, shape_pt_sequence))');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_shapes_shape_sequence ON shapes(shape_id, shape_pt_sequence)');
          await _seedShapesTable(db);
        }
      },
    );
  }

  Future<void> _seedShapesTable(Database db) async {
    try {
      final csvContent = await rootBundle.loadString('assets/data/shapes_filtrados.txt');
      final lines = csvContent.split('\n');
      if (lines.isNotEmpty) {
        final header = lines[0].toLowerCase();
        final partsHeader = header.split(',');
        
        int colShapeId = partsHeader.indexOf('shape_id');
        int colLat = partsHeader.indexOf('shape_pt_lat');
        int colLon = partsHeader.indexOf('shape_pt_lon');
        int colSeq = partsHeader.indexOf('shape_pt_sequence');

        if (colShapeId == -1) colShapeId = 0;
        if (colLat == -1) colLat = 2;
        if (colLon == -1) colLon = 3;
        if (colSeq == -1) colSeq = 4;

        await db.transaction((txn) async {
          final batch = txn.batch();
          int count = 0;
          for (int i = 1; i < lines.length; i++) {
            final line = lines[i].trim();
            if (line.isEmpty) continue;

            final parts = line.split(',');
            if (parts.length <= colShapeId || 
                parts.length <= colLat || 
                parts.length <= colLon || 
                parts.length <= colSeq) continue;

            try {
              final shapeId = parts[colShapeId].trim();
              final lat = double.parse(parts[colLat].trim());
              final lon = double.parse(parts[colLon].trim());
              final sequence = int.parse(parts[colSeq].trim());

              batch.insert('shapes', {
                'shape_id': shapeId,
                'shape_pt_lat': lat,
                'shape_pt_lon': lon,
                'shape_pt_sequence': sequence,
              }, conflictAlgorithm: ConflictAlgorithm.replace);

              count++;
              if (count % 500 == 0) {
                await batch.commit(noResult: true);
              }
            } catch (_) {
              // skip malformed row
            }
          }
          if (count % 500 != 0) {
            await batch.commit(noResult: true);
          }
        });
        print('[Database] Seeded high-precision official shapes from shapes_filtrados.txt successfully!');
        return;
      }
    } catch (e) {
      print('[Database] Failed to seed official shapes: $e. Using local detailed JSONs as fallback.');
    }

    // 1. Seed Shapes for 159 (High-resolution curves)
    final Map<String, String> shapeAssetMap159 = {
      '159_r1_shape': 'assets/data/route_159_r1_detailed.json',
      '159_r2_shape': 'assets/data/route_159_r2_detailed.json',
      '159_azul_shape': 'assets/data/route_159_azul_detailed.json',
      '159_roja_shape': 'assets/data/route_159_roja_detailed.json',
    };

    for (final entry in shapeAssetMap159.entries) {
      final shapeId = entry.key;
      final assetPath = entry.value;
      try {
        String jsonStr;
        try {
          jsonStr = await rootBundle.loadString(assetPath);
        } catch (_) {
          jsonStr = await rootBundle.loadString('assets/data/route_159.json');
        }
        final List<dynamic> pointsList = jsonDecode(jsonStr);
        for (int i = 0; i < pointsList.length; i++) {
          final pt = pointsList[i];
          final lat = (pt['lat'] as num).toDouble();
          final lon = (pt['lng'] as num).toDouble();
          await db.insert('shapes', {
            'shape_id': shapeId,
            'shape_pt_lat': lat,
            'shape_pt_lon': lon,
            'shape_pt_sequence': i + 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } catch (e) {
        // Fallback mocks for 159 branches in test environments
        final List<Map<String, dynamic>> fallback159 = [
          {'shape_id': shapeId, 'shape_pt_lat': -34.7680, 'shape_pt_lon': -58.2120, 'shape_pt_sequence': 1},
          {'shape_id': shapeId, 'shape_pt_lat': -34.7670, 'shape_pt_lon': -58.2120, 'shape_pt_sequence': 2},
          {'shape_id': shapeId, 'shape_pt_lat': -34.7660, 'shape_pt_lon': -58.2120, 'shape_pt_sequence': 3},
          {'shape_id': shapeId, 'shape_pt_lat': -34.7650, 'shape_pt_lon': -58.2120, 'shape_pt_sequence': 4},
          {'shape_id': shapeId, 'shape_pt_lat': -34.7635, 'shape_pt_lon': -58.2120, 'shape_pt_sequence': 5},
          {'shape_id': shapeId, 'shape_pt_lat': -34.7635, 'shape_pt_lon': -58.2150, 'shape_pt_sequence': 6},
          {'shape_id': shapeId, 'shape_pt_lat': -34.7635, 'shape_pt_lon': -58.2180, 'shape_pt_sequence': 7},
          {'shape_id': shapeId, 'shape_pt_lat': -34.7635, 'shape_pt_lon': -58.2220, 'shape_pt_sequence': 8},
          {'shape_id': shapeId, 'shape_pt_lat': -34.7635, 'shape_pt_lon': -58.2250, 'shape_pt_sequence': 9},
        ];
        for (var pt in fallback159) {
          await db.insert('shapes', pt, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    }

    // 2. Seed Shapes for 98 (R3 and R5)
    final Map<String, String> shapeAssetMap98 = {
      '98_r3_shape': 'assets/data/route_98_r3_detailed.json',
      '98_r5_shape': 'assets/data/route_98_r5_detailed.json',
    };

    for (final entry in shapeAssetMap98.entries) {
      final shapeId = entry.key;
      final assetPath = entry.value;
      try {
        String jsonStr;
        try {
          jsonStr = await rootBundle.loadString(assetPath);
        } catch (_) {
          jsonStr = await rootBundle.loadString('assets/data/route_98.json');
        }
        final List<dynamic> pointsList = jsonDecode(jsonStr);
        for (int i = 0; i < pointsList.length; i++) {
          final pt = pointsList[i];
          final lat = (pt['lat'] as num).toDouble();
          final lon = (pt['lng'] as num).toDouble();
          await db.insert('shapes', {
            'shape_id': shapeId,
            'shape_pt_lat': lat,
            'shape_pt_lon': lon,
            'shape_pt_sequence': i + 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } catch (e) {
        if (shapeId.contains('r3')) {
          final List<Map<String, dynamic>> fallback98R3 = [
            {'shape_id': '98_r3_shape', 'shape_pt_lat': -34.7680, 'shape_pt_lon': -58.2115, 'shape_pt_sequence': 1},
            {'shape_id': '98_r3_shape', 'shape_pt_lat': -34.7660, 'shape_pt_lon': -58.2115, 'shape_pt_sequence': 2},
            {'shape_id': '98_r3_shape', 'shape_pt_lat': -34.7645, 'shape_pt_lon': -58.2115, 'shape_pt_sequence': 3},
            {'shape_id': '98_r3_shape', 'shape_pt_lat': -34.7630, 'shape_pt_lon': -58.2115, 'shape_pt_sequence': 4},
            {'shape_id': '98_r3_shape', 'shape_pt_lat': -34.7630, 'shape_pt_lon': -58.2150, 'shape_pt_sequence': 5},
            {'shape_id': '98_r3_shape', 'shape_pt_lat': -34.7630, 'shape_pt_lon': -58.2180, 'shape_pt_sequence': 6},
            {'shape_id': '98_r3_shape', 'shape_pt_lat': -34.7630, 'shape_pt_lon': -58.2220, 'shape_pt_sequence': 7},
            {'shape_id': '98_r3_shape', 'shape_pt_lat': -34.7630, 'shape_pt_lon': -58.2250, 'shape_pt_sequence': 8},
          ];
          for (var pt in fallback98R3) {
            await db.insert('shapes', pt, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        } else {
          final List<Map<String, dynamic>> fallback98R5 = [
            {'shape_id': '98_r5_shape', 'shape_pt_lat': -34.7590, 'shape_pt_lon': -58.2120, 'shape_pt_sequence': 1},
            {'shape_id': '98_r5_shape', 'shape_pt_lat': -34.7605, 'shape_pt_lon': -58.2120, 'shape_pt_sequence': 2},
            {'shape_id': '98_r5_shape', 'shape_pt_lat': -34.7620, 'shape_pt_lon': -58.2120, 'shape_pt_sequence': 3},
            {'shape_id': '98_r5_shape', 'shape_pt_lat': -34.7635, 'shape_pt_lon': -58.2120, 'shape_pt_sequence': 4},
            {'shape_id': '98_r5_shape', 'shape_pt_lat': -34.7635, 'shape_pt_lon': -58.2150, 'shape_pt_sequence': 5},
            {'shape_id': '98_r5_shape', 'shape_pt_lat': -34.7635, 'shape_pt_lon': -58.2180, 'shape_pt_sequence': 6},
            {'shape_id': '98_r5_shape', 'shape_pt_lat': -34.7635, 'shape_pt_lon': -58.2220, 'shape_pt_sequence': 7},
            {'shape_id': '98_r5_shape', 'shape_pt_lat': -34.7635, 'shape_pt_lon': -58.2250, 'shape_pt_sequence': 8},
          ];
          for (var pt in fallback98R5) {
            await db.insert('shapes', pt, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }
    }
  }

  Future<void> _seedRoutesTable(Database db) async {
    // Seed Routes with full path string for both 159 and 98 R3/R5
    try {
      String route159JsonStr;
      try {
        route159JsonStr = await rootBundle.loadString('assets/data/route_159_r2_detailed.json');
      } catch (_) {
        route159JsonStr = await rootBundle.loadString('assets/data/route_159.json');
      }
      await db.insert('routes', {
        'id': '159',
        'line': '159',
        'route_points': route159JsonStr,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      await db.insert('routes', {
        'id': '159',
        'line': '159',
        'route_points': '[{"lat":-34.7680,"lng":-58.2120},{"lat":-34.7670,"lng":-58.2120},{"lat":-34.7660,"lng":-58.2120},{"lat":-34.7650,"lng":-58.2120},{"lat":-34.7635,"lng":-58.2120},{"lat":-34.7635,"lng":-58.2150},{"lat":-34.7635,"lng":-58.2180},{"lat":-34.7635,"lng":-58.2220},{"lat":-34.7635,"lng":-58.2250}]'
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    try {
      String route98JsonStr;
      try {
        route98JsonStr = await rootBundle.loadString('assets/data/route_98_r5_detailed.json');
      } catch (_) {
        route98JsonStr = await rootBundle.loadString('assets/data/route_98.json');
      }
      await db.insert('routes', {
        'id': '98_R3',
        'line': '98 - R3',
        'route_points': route98JsonStr,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      
      await db.insert('routes', {
        'id': '98_R5',
        'line': '98 - R5',
        'route_points': route98JsonStr,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      await db.insert('routes', {
        'id': '98_R3',
        'line': '98 - R3',
        'route_points': '[{"lat":-34.7680,"lng":-58.2115},{"lat":-34.7660,"lng":-58.2115},{"lat":-34.7645,"lng":-58.2115},{"lat":-34.7630,"lng":-58.2115},{"lat":-34.7630,"lng":-58.2150},{"lat":-34.7630,"lng":-58.2180},{"lat":-34.7630,"lng":-58.2220},{"lat":-34.7630,"lng":-58.2250}]'
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      
      await db.insert('routes', {
        'id': '98_R5',
        'line': '98 - R5',
        'route_points': '[{"lat":-34.7590,"lng":-58.2120},{"lat":-34.7605,"lng":-58.2120},{"lat":-34.7620,"lng":-58.2120},{"lat":-34.7635,"lng":-58.2120},{"lat":-34.7635,"lng":-58.2150},{"lat":-34.7635,"lng":-58.2180},{"lat":-34.7635,"lng":-58.2220},{"lat":-34.7635,"lng":-58.2250}]'
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _createOfflineTables(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS routes (id TEXT PRIMARY KEY, line TEXT, route_points TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS stops (id TEXT PRIMARY KEY, line TEXT, name TEXT, latitude REAL, longitude REAL, sequence INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS schedules (id INTEGER PRIMARY KEY AUTOINCREMENT, line TEXT, departure_time TEXT, direction TEXT, trip_duration_minutes INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS shapes (shape_id TEXT, shape_pt_lat REAL, shape_pt_lon REAL, shape_pt_sequence INTEGER, PRIMARY KEY (shape_id, shape_pt_sequence))');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_shapes_shape_sequence ON shapes(shape_id, shape_pt_sequence)');
    
    await _seedShapesTable(db);
    await _seedRoutesTable(db);
    await _seedStopsTable(db);

    // Populate schedules: depart every 15 minutes all day (96 departures per route)
    for (int hour = 0; hour < 24; hour++) {
      for (int min = 0; min < 60; min += 15) {
        final timeStr = '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
        await db.insert('schedules', {
          'line': '159',
          'departure_time': timeStr,
          'direction': 'Ida',
          'trip_duration_minutes': 40
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        
        await db.insert('schedules', {
          'line': '98 - R3',
          'departure_time': timeStr,
          'direction': 'Ida',
          'trip_duration_minutes': 40
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        
        await db.insert('schedules', {
          'line': '98 - R5',
          'departure_time': timeStr,
          'direction': 'Ida',
          'trip_duration_minutes': 40
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  Future<void> _seedStopsTable(Database db) async {
    final List<Map<String, dynamic>> stops = [
      // 159 Ramal 1 (Cruce Varela)
      {'id': 's_159_r1_1', 'line': '159_r1_shape', 'name': 'Constitución (CABA)', 'latitude': -34.6282, 'longitude': -58.3798, 'sequence': 1},
      {'id': 's_159_r1_2', 'line': '159_r1_shape', 'name': 'Av. Mitre y Av. España (Avellaneda)', 'latitude': -34.6625, 'longitude': -58.3667, 'sequence': 2},
      {'id': 's_159_r1_3', 'line': '159_r1_shape', 'name': 'Triángulo de Bernal', 'latitude': -34.7001, 'longitude': -58.3060, 'sequence': 3},
      {'id': 's_159_r1_4', 'line': '159_r1_shape', 'name': 'Av. Calchaquí y Av. 12 de Octubre', 'latitude': -34.7395, 'longitude': -58.2715, 'sequence': 4},
      {'id': 's_159_r1_5', 'line': '159_r1_shape', 'name': 'Av. Calchaquí y Av. Smith', 'latitude': -34.7570, 'longitude': -58.2710, 'sequence': 5},
      {'id': 's_159_r1_6', 'line': '159_r1_shape', 'name': 'Cruce Varela (Terminal)', 'latitude': -34.7959, 'longitude': -58.2748, 'sequence': 6},

      // 159 Ramal 2 (Villa España)
      {'id': 's_159_r2_1', 'line': '159_r2_shape', 'name': 'Constitución (CABA)', 'latitude': -34.6282, 'longitude': -58.3798, 'sequence': 1},
      {'id': 's_159_r2_2', 'line': '159_r2_shape', 'name': 'Autopista Bs As - La Plata (Dock Sud)', 'latitude': -34.6400, 'longitude': -58.3480, 'sequence': 2},
      {'id': 's_159_r2_3', 'line': '159_r2_shape', 'name': 'Acceso Sudeste (Bernal Oeste)', 'latitude': -34.6850, 'longitude': -58.3180, 'sequence': 3},
      {'id': 's_159_r2_4', 'line': '159_r2_shape', 'name': 'Av. Los Quilmes y Av. Zapiola (Quilmes)', 'latitude': -34.7210, 'longitude': -58.2880, 'sequence': 4},
      {'id': 's_159_r2_5', 'line': '159_r2_shape', 'name': 'Av. Mitre y Primera Junta (Quilmes)', 'latitude': -34.7330, 'longitude': -58.2600, 'sequence': 5},
      {'id': 's_159_r2_6', 'line': '159_r2_shape', 'name': 'Av. Mitre y Av. 14 (Berazategui)', 'latitude': -34.7611, 'longitude': -58.2115, 'sequence': 6},
      {'id': 's_159_r2_7', 'line': '159_r2_shape', 'name': 'Villa España (Calle 149 & 24)', 'latitude': -34.7675, 'longitude': -58.2015, 'sequence': 7},

      // 159 L Azul (Alpargatas)
      {'id': 's_159_azul_1', 'line': '159_azul_shape', 'name': 'Constitución (CABA)', 'latitude': -34.6282, 'longitude': -58.3798, 'sequence': 1},
      {'id': 's_159_azul_2', 'line': '159_azul_shape', 'name': 'Av. Mitre y Av. España (Avellaneda)', 'latitude': -34.6625, 'longitude': -58.3667, 'sequence': 2},
      {'id': 's_159_azul_3', 'line': '159_azul_shape', 'name': 'Triángulo de Bernal', 'latitude': -34.7001, 'longitude': -58.3060, 'sequence': 3},
      {'id': 's_159_azul_4', 'line': '159_azul_shape', 'name': 'Calle 14 y Calle 148 (Berazategui)', 'latitude': -34.7611, 'longitude': -58.2115, 'sequence': 4},
      {'id': 's_159_azul_5', 'line': '159_azul_shape', 'name': 'Calle 14 y Av. Mitre', 'latitude': -34.7650, 'longitude': -58.2160, 'sequence': 5},
      {'id': 's_159_azul_6', 'line': '159_azul_shape', 'name': 'Av. Mitre y Calle 40', 'latitude': -34.8100, 'longitude': -58.1950, 'sequence': 6},
      {'id': 's_159_azul_7', 'line': '159_azul_shape', 'name': 'Rotonda de Alpargatas (Terminal)', 'latitude': -34.8582, 'longitude': -58.1738, 'sequence': 7},

      // 159 L Roja (Alpargatas)
      {'id': 's_159_roja_1', 'line': '159_roja_shape', 'name': 'Constitución (CABA)', 'latitude': -34.6282, 'longitude': -58.3798, 'sequence': 1},
      {'id': 's_159_roja_2', 'line': '159_roja_shape', 'name': 'Av. Mitre y Av. España (Avellaneda)', 'latitude': -34.6625, 'longitude': -58.3667, 'sequence': 2},
      {'id': 's_159_roja_3', 'line': '159_roja_shape', 'name': 'Triángulo de Bernal', 'latitude': -34.7001, 'longitude': -58.3060, 'sequence': 3},
      {'id': 's_159_roja_4', 'line': '159_roja_shape', 'name': 'Calle 14 y Calle 148 (Berazategui)', 'latitude': -34.7611, 'longitude': -58.2115, 'sequence': 4},
      {'id': 's_159_roja_5', 'line': '159_roja_shape', 'name': 'Calle 14 y Av. Mitre', 'latitude': -34.7650, 'longitude': -58.2160, 'sequence': 5},
      {'id': 's_159_roja_6', 'line': '159_roja_shape', 'name': 'Av. Mitre y Calle 40', 'latitude': -34.8100, 'longitude': -58.1950, 'sequence': 6},
      {'id': 's_159_roja_7', 'line': '159_roja_shape', 'name': 'Rotonda de Alpargatas (Terminal)', 'latitude': -34.8582, 'longitude': -58.1738, 'sequence': 7},

      // 98 Ramal 3 (Lisandro de la Torre)
      {'id': 's_98_r3_1', 'line': '98_r3_shape', 'name': 'Once (CABA)', 'latitude': -34.6097, 'longitude': -58.4068, 'sequence': 1},
      {'id': 's_98_r3_2', 'line': '98_r3_shape', 'name': 'Av. Mitre y Av. España (Avellaneda)', 'latitude': -34.6625, 'longitude': -58.3667, 'sequence': 2},
      {'id': 's_98_r3_3', 'line': '98_r3_shape', 'name': 'Triángulo de Bernal', 'latitude': -34.7001, 'longitude': -58.3060, 'sequence': 3},
      {'id': 's_98_r3_4', 'line': '98_r3_shape', 'name': 'Av. Mitre y Calle 14 (Berazategui)', 'latitude': -34.7611, 'longitude': -58.2115, 'sequence': 4},
      {'id': 's_98_r3_5', 'line': '98_r3_shape', 'name': 'Estación Lisandro de la Torre', 'latitude': -34.7628, 'longitude': -58.2115, 'sequence': 5},

      // 98 Ramal 5 (Av. Mitre)
      {'id': 's_98_r5_1', 'line': '98_r5_shape', 'name': 'Once (CABA)', 'latitude': -34.6097, 'longitude': -58.4068, 'sequence': 1},
      {'id': 's_98_r5_2', 'line': '98_r5_shape', 'name': 'Av. Mitre y Av. España (Avellaneda)', 'latitude': -34.6625, 'longitude': -58.3667, 'sequence': 2},
      {'id': 's_98_r5_3', 'line': '98_r5_shape', 'name': 'Triángulo de Bernal', 'latitude': -34.7001, 'longitude': -58.3060, 'sequence': 3},
      {'id': 's_98_r5_4', 'line': '98_r5_shape', 'name': 'Av. Mitre y Calle 14 (Berazategui)', 'latitude': -34.7611, 'longitude': -58.2115, 'sequence': 4},
      {'id': 's_98_r5_5', 'line': '98_r5_shape', 'name': 'Av. Mitre y Calle 15 (Terminal)', 'latitude': -34.7650, 'longitude': -58.2160, 'sequence': 5},
    ];

    for (final stop in stops) {
      await db.insert('stops', stop, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<bool> addFavorite(FavoriteStop stop) async {
    final db = await database;
    
    // Check current count
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM favorites')) ?? 0;
    
    if (count >= 3) {
      return false; // Limit reached
    }

    await db.insert(
      'favorites',
      stop.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return true;
  }

  Future<List<FavoriteStop>> getFavorites() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('favorites');
    return List.generate(maps.length, (i) {
      return FavoriteStop(
        id: maps[i]['id'],
        name: maps[i]['name'],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getOfflineRoutes() async {
    final db = await database;
    return await db.query('routes');
  }

  Future<List<Map<String, dynamic>>> getOfflineStops() async {
    final db = await database;
    return await db.query('stops');
  }

  Future<List<Map<String, dynamic>>> getOfflineSchedules() async {
    final db = await database;
    return await db.query('schedules');
  }

  Future<List<Map<String, dynamic>>> getStopsForShape(String shapeId) async {
    final db = await database;
    return await db.query(
      'stops',
      where: 'line = ?',
      whereArgs: [shapeId],
      orderBy: 'sequence ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getShapesForId(String shapeId) async {
    final db = await database;
    return await db.query(
      'shapes',
      where: 'shape_id = ?',
      whereArgs: [shapeId],
      orderBy: 'shape_pt_sequence ASC',
    );
  }

  Future<List<LatLng>> getRouteShape(String shapeId) async {
    final db = await database;
    
    // Map internal app shapeId to official high-precision GTFS shapeId from shapes_filtrados.txt
    String targetId = shapeId;
    if (shapeId == '159_r1_shape') {
      targetId = '1793'; // 159D Cruce Varela Ida
    } else if (shapeId == '159_r2_shape') {
      targetId = '1795'; // 159E Villa España via Autopista/Acceso Sudeste (official high-precision alignment)
    } else if (shapeId == '159_azul_shape') {
      targetId = '1809'; // 159K Alpargatas via Autopista
    } else if (shapeId == '159_roja_shape') {
      targetId = '1799'; // 159H Expreso/Roja via Autopista
    } else if (shapeId == '98_r3_shape') {
      targetId = '691';  // 98C Villa España
    } else if (shapeId == '98_r5_shape') {
      targetId = '695';  // 98E Once - Av Mitre
    }

    final results = await db.query(
      'shapes',
      where: 'shape_id = ?',
      whereArgs: [targetId],
      orderBy: 'shape_pt_sequence ASC',
    );

    if (results.isNotEmpty) {
      return results.map((row) => LatLng(
        row['shape_pt_lat'] as double,
        row['shape_pt_lon'] as double,
      )).toList();
    }

    // Fallback to query with original shapeId if not found in GTFS official mapping
    final fallbackResults = await db.query(
      'shapes',
      where: 'shape_id = ?',
      whereArgs: [shapeId],
      orderBy: 'shape_pt_sequence ASC',
    );

    return fallbackResults.map((row) => LatLng(
      row['shape_pt_lat'] as double,
      row['shape_pt_lon'] as double,
    )).toList();
  }

  Future<int> ingestGtfsShapesFromCsv(String csvContent) async {
    final db = await database;
    final lines = csvContent.split('\n');
    if (lines.isEmpty) return 0;

    int insertedCount = 0;

    await db.transaction((txn) async {
      final batch = txn.batch();

      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final parts = line.split(',');
        if (parts.length < 5) continue;

        try {
          final shapeId = parts[0].trim();
          final lat = double.parse(parts[2].trim());
          final lon = double.parse(parts[3].trim());
          final sequence = int.parse(parts[4].trim());

          batch.insert('shapes', {
            'shape_id': shapeId,
            'shape_pt_lat': lat,
            'shape_pt_lon': lon,
            'shape_pt_sequence': sequence,
          }, conflictAlgorithm: ConflictAlgorithm.replace);

          insertedCount++;
          if (insertedCount % 1000 == 0) {
            await batch.commit(noResult: true);
          }
        } catch (e) {
          continue;
        }
      }

      await batch.commit(noResult: true);
    });

    print('[Database] GTFS shapes ingestion complete: $insertedCount points inserted');
    return insertedCount;
  }

  Future<int> loadShapesFromAssets() async {
    try {
      final csvContent = await rootBundle.loadString('assets/data/shapes_filtrados.txt');
      return await ingestGtfsShapesFromCsv(csvContent);
    } catch (e) {
      print('[Database] Error loading shapes from assets: $e');
      return 0;
    }
  }

  Future<void> ensureShapesLoaded() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM shapes')
    ) ?? 0;
    
    if (count < 1000) {
      print('[Database] Shapes table almost empty ($count points), loading from assets...');
      await loadShapesFromAssets();
    }
  }

  Future<int> ingestGtfsShapesFromJson(List<dynamic> shapesList) async {
    final db = await database;
    int insertedCount = 0;

    await db.transaction((txn) async {
      final batch = txn.batch();

      for (var shape in shapesList) {
        final shapeId = shape['shape_id'] as String;
        final lat = (shape['shape_pt_lat'] as num).toDouble();
        final lon = (shape['shape_pt_lon'] as num).toDouble();
        final seq = shape['shape_pt_sequence'] as int;

        batch.insert('shapes', {
          'shape_id': shapeId,
          'shape_pt_lat': lat,
          'shape_pt_lon': lon,
          'shape_pt_sequence': seq,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        insertedCount++;
        if (insertedCount % 500 == 0) {
          await batch.commit(noResult: true);
        }
      }

      await batch.commit(noResult: true);
    });

    print('[Database] JSON shapes ingestion complete: $insertedCount points inserted');
    return insertedCount;
  }
}
