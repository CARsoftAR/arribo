import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart' show rootBundle;

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
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'arribo_favorites.db');
    return await openDatabase(
      path,
      version: 9,
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
      },
    );
  }

  Future<void> _seedShapesTable(Database db) async {
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
    
    await _seedShapesTable(db);
    await _seedRoutesTable(db);

    // Populate default stops
    await db.insert('stops', {'id': 's_159_1', 'line': '159', 'name': 'Calle 17 y 151 (Inicio)', 'latitude': -34.7650, 'longitude': -58.2150, 'sequence': 1}, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('stops', {'id': 's_159_2', 'line': '159', 'name': 'Calle 15 y 149 (Terminal MOQSA)', 'latitude': -34.7635, 'longitude': -58.2120, 'sequence': 2}, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('stops', {'id': 's_98_3_1', 'line': '98 - R3', 'name': 'Calle 14 y 147 (Inicio)', 'latitude': -34.7618, 'longitude': -58.2120, 'sequence': 1}, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('stops', {'id': 's_98_3_2', 'line': '98 - R3', 'name': 'Calle 15 y 149 (Terminal MOQSA)', 'latitude': -34.7635, 'longitude': -58.2120, 'sequence': 2}, conflictAlgorithm: ConflictAlgorithm.replace);

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

  Future<List<Map<String, dynamic>>> getShapesForId(String shapeId) async {
    final db = await database;
    return await db.query(
      'shapes',
      where: 'shape_id = ?',
      whereArgs: [shapeId],
      orderBy: 'shape_pt_sequence ASC',
    );
  }
}
