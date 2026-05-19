import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart' as gtfs;
import 'package:arribo/features/transit/domain/models/transit_vehicle.dart';
import 'package:arribo/core/config/debug_config.dart';
import 'package:arribo/features/transit/data/services/database_service.dart';
import 'package:flutter/services.dart' show rootBundle;

class GtfsRealtimeTransitService implements TransitService {
  // Endpoints oficiales del Gobierno
  static const String _baseUrl = 'https://apitransporte.buenosaires.gob.ar';
  static const String _positionsEndpoint = '/colectivos/vehiclePositions';
  static const String _tripUpdatesEndpoint = '/colectivos/tripUpdates';

  GtfsRealtimeTransitService() {
    try {
      HttpOverrides.global = _DevHttpOverrides();
    } catch (_) {
      // Ignorar si ya están configurados
    }
  }

  // Historial de vehículos simulados para fallback suave
  static List<LatLng> _route159 = [];
  static List<LatLng> _route159R1 = [];
  static List<LatLng> _route159R2 = [];
  static List<LatLng> _route159Azul = [];
  static List<LatLng> _route159Roja = [];
  static List<LatLng> _routeR3 = [];
  static List<LatLng> _routeR5 = [];

  static bool _routesLoaded = false;

  static Future<void> _loadFullRoutesIfNeeded() async {
    if (_routesLoaded) return;
    final Map<String, String> shapeAssetMap = {
      '159_r1': 'assets/data/route_159_r1_detailed.json',
      '159_r2': 'assets/data/route_159_r2_detailed.json',
      '159_azul': 'assets/data/route_159_azul_detailed.json',
      '159_roja': 'assets/data/route_159_roja_detailed.json',
      '98_r3': 'assets/data/route_98_r3_detailed.json',
      '98_r5': 'assets/data/route_98_r5_detailed.json',
    };

    final Map<String, List<LatLng>> loadedRoutes = {};

    for (final entry in shapeAssetMap.entries) {
      final key = entry.key;
      final assetPath = entry.value;
      try {
        String jsonStr;
        try {
          jsonStr = await rootBundle.loadString(assetPath);
        } catch (_) {
          jsonStr = await rootBundle.loadString(key.startsWith('159') ? 'assets/data/route_159.json' : 'assets/data/route_98.json');
        }
        final List<dynamic> pointsList = jsonDecode(jsonStr);
        loadedRoutes[key] = pointsList.map((pt) => LatLng((pt['lat'] as num).toDouble(), (pt['lng'] as num).toDouble())).toList();
      } catch (e) {
        print('[GTFS-RT] Error loading branch $key: $e');
      }
    }

    _route159R1 = loadedRoutes['159_r1'] ?? [];
    _route159R2 = loadedRoutes['159_r2'] ?? [];
    _route159Azul = loadedRoutes['159_azul'] ?? [];
    _route159Roja = loadedRoutes['159_roja'] ?? [];
    _routeR3 = loadedRoutes['98_r3'] ?? [];
    _routeR5 = loadedRoutes['98_r5'] ?? [];
    
    // Fallback base route for general usage
    _route159 = _route159R2;

    _routesLoaded = true;
  }

  @override
  Stream<List<TransitVehicle>> getVehiclesStream() async* {
    // Diagnóstico silencioso de red de ambos servidores
    _runSilentDiagnostics();
    await _loadFullRoutesIfNeeded();

    while (true) {
      final String clientID = dotenv.env['TRANSIT_CLIENT_ID'] ?? '';
      final String clientSecret = dotenv.env['TRANSIT_SECRET'] ?? '';
      final bool useMock = dotenv.env['USE_MOCK']?.toLowerCase() == 'true';
      
      if (useMock) {
        DebugConfig.updateStatus('SIMULADOR ACTIVO (Forzado por .env)', loading: false);
        yield _filterVehicles(_simulateProfessionalMovement());
        if (Platform.environment.containsKey('FLUTTER_TEST')) {
          break;
        }
        await Future.delayed(const Duration(seconds: 15));
        continue;
      }
      
      List<TransitVehicle> vehicles = [];
      bool success = false;
      String? gcbaError;

      // ==========================================
      // INTENTO 1: API Oficial de Transporte GCBA (Prioridad - Con credenciales de desarrollador)
      // ==========================================
      if (clientID.isEmpty || clientID == 'mock' || clientSecret.isEmpty || clientSecret == 'mock') {
        gcbaError = 'Credenciales ausentes o inválidas ("mock") en .env';
      } else {
        try {
          DebugConfig.updateStatus('Conectando a API Oficial GCBA...', loading: true);
          
          // Obtener Trip Updates en paralelo para calcular demoras
          final Map<String, int> tripDelays = {};
          final Map<String, int> vehicleDelays = {};
          
          try {
            final tripUpdatesUri = Uri.parse('$_baseUrl$_tripUpdatesEndpoint?client_id=$clientID&client_secret=$clientSecret');

            final tripResponse = await http.get(
              tripUpdatesUri,
              headers: {
                'Accept': 'application/x-protobuf',
                'User-Agent': 'Mozilla/5.0',
                'client_id': clientID,
                'client_secret': clientSecret,
              },
            ).timeout(const Duration(seconds: 20));

            if (tripResponse.statusCode == 200) {
              final tripFeed = gtfs.FeedMessage.fromBuffer(tripResponse.bodyBytes);
              for (final entity in tripFeed.entity) {
                if (entity.hasTripUpdate()) {
                  final tu = entity.tripUpdate;
                  final String? tripId = tu.hasTrip() ? tu.trip.tripId : null;
                  final String? vehicleId = tu.hasVehicle() ? tu.vehicle.id : null;

                  if (tu.hasDelay()) {
                    if (tripId != null) tripDelays[tripId] = tu.delay;
                  } else if (tu.stopTimeUpdate.isNotEmpty) {
                    final firstUpdate = tu.stopTimeUpdate.first;
                    if (firstUpdate.hasArrival() && firstUpdate.arrival.hasDelay()) {
                      final delayValue = firstUpdate.arrival.delay;
                      if (tripId != null) tripDelays[tripId] = delayValue;
                      if (vehicleId != null) vehicleDelays[vehicleId] = delayValue;
                    }
                  }
                }
              }
            } else {
              print('[GTFS-RT] Error en TripUpdates: Código HTTP ${tripResponse.statusCode}');
            }
          } catch (e) {
            print('[GTFS-RT] GCBA TripUpdates fail: $e');
          }

          // Obtener posiciones
          final positionsUri = Uri.parse('$_baseUrl$_positionsEndpoint?client_id=$clientID&client_secret=$clientSecret');

          final positionsResponse = await http.get(
            positionsUri,
            headers: {
              'Accept': 'application/x-protobuf',
              'User-Agent': 'Mozilla/5.0',
              'client_id': clientID,
              'client_secret': clientSecret,
            },
          ).timeout(const Duration(seconds: 20));

          if (positionsResponse.statusCode == 200 && positionsResponse.bodyBytes.isNotEmpty) {
            final feed = gtfs.FeedMessage.fromBuffer(positionsResponse.bodyBytes);
            vehicles = _parseFeedMessage(feed, tripDelays: tripDelays, vehicleDelays: vehicleDelays);
            if (vehicles.isNotEmpty) {
              DebugConfig.updateStatus('CONECTADO: API Oficial GCBA (Protobuf)', loading: false);
              DebugConfig.detailedError.value = null; // Clean errors
              DebugConfig.connectionState.value = TransitConnectionState.online;
              DebugConfig.cacheTimestamp.value = DateTime.now();
              
              // Persist locally in SharedPreferences
              _saveVehiclesToCache(vehicles);

              success = true;
              yield _filterVehicles(vehicles);
            } else {
              gcbaError = 'Error: Respuesta vacía o formato incorrecto (0 colectivos parseados)';
            }
          } else {
            gcbaError = 'Error: ${positionsResponse.statusCode} ${_getHttpStatusMessage(positionsResponse.statusCode)}';
            print('[GTFS-RT] Error en API GCBA: $gcbaError');
          }
        } catch (e) {
          gcbaError = 'Excepción API GCBA: $e';
          print('[GTFS-RT] Excepción al consultar API Oficial GCBA: $e');
        }
      }

      // ==========================================
      // INTENTO 2: Fallback a Modo Consulta Offline (Con persistencia local y predicción analítica / teórica de SQLite)
      // ==========================================
      if (!success) {
        final cachedVehicles = await _loadVehiclesFromCache();
        final timestamp = DebugConfig.cacheTimestamp.value;
        
        bool cacheServed = false;
        if (cachedVehicles.isNotEmpty && timestamp != null) {
          final int elapsedSeconds = DateTime.now().difference(timestamp).inSeconds;
          
          if (elapsedSeconds < 180) {
            // Apply software prediction (dead reckoning) for vehicles less than 3 minutes old!
            final int elapsedMinutes = elapsedSeconds ~/ 60;
            DebugConfig.connectionState.value = TransitConnectionState.cached;
            DebugConfig.updateStatus(
              elapsedMinutes == 0
                  ? 'Datos de hace unos segundos (Servidor lento)'
                  : 'Datos de hace $elapsedMinutes min (Servidor lento)', 
              loading: false
            );
            
            final predictedVehicles = _applySoftwarePrediction(cachedVehicles, timestamp);
            yield _filterVehicles(predictedVehicles);
            cacheServed = true;
          }
        }
        
        if (!cacheServed) {
          // If no cache or cache is stale, load theoretical schedules from local SQLite database!
          final theoreticalVehicles = await _loadTheoreticalVehicles();
          if (theoreticalVehicles.isNotEmpty) {
            DebugConfig.connectionState.value = TransitConnectionState.cached;
            DebugConfig.updateStatus('Modo Offline: Posiciones Teóricas por Horario', loading: false);
            yield _filterVehicles(theoreticalVehicles);
          } else {
            DebugConfig.connectionState.value = TransitConnectionState.offline;
            DebugConfig.updateStatus('Servidores caídos. Modo consulta offline', loading: false);
            yield <TransitVehicle>[];
          }
        }

        String finalError = '';
        if (gcbaError != null) finalError += 'GCBA: $gcbaError';
        if (finalError.isEmpty) finalError = 'Error desconocido o sin conexión a internet';
        
        DebugConfig.detailedError.value = _redactSecrets(finalError);
      }

      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        break;
      }
      await Future.delayed(const Duration(seconds: 15)); // Intervalo recomendado GTFS-RT
    }
  }

  Future<void> _saveVehiclesToCache(List<TransitVehicle> vehicles) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> jsonList = vehicles.map((v) => v.toJson()).toList();
      final String jsonStr = jsonEncode(jsonList);
      await prefs.setString('cached_vehicles', jsonStr);
      await prefs.setString('cached_timestamp', DateTime.now().toIso8601String());
    } catch (e) {
      print('[GTFS-RT] Error guardando caché: $e');
    }
  }

  Future<List<TransitVehicle>> _loadVehiclesFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('cached_vehicles');
      final String? timeStr = prefs.getString('cached_timestamp');
      if (jsonStr != null && timeStr != null) {
        final DateTime timestamp = DateTime.parse(timeStr);
        DebugConfig.cacheTimestamp.value = timestamp;
        
        final List<dynamic> decoded = jsonDecode(jsonStr);
        return decoded.map((item) => TransitVehicle.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      print('[GTFS-RT] Error cargando caché: $e');
    }
    return [];
  }

  List<TransitVehicle> _applySoftwarePrediction(List<TransitVehicle> cachedVehicles, DateTime cacheTime) {
    final double elapsedSeconds = DateTime.now().difference(cacheTime).inSeconds.toDouble();
    if (elapsedSeconds <= 0) return cachedVehicles;
    
    // Max projection of 3 minutes (180 seconds)
    final double cappedSeconds = elapsedSeconds > 180.0 ? 180.0 : elapsedSeconds;
    final double speedMps = 8.5; // ~30 km/h typical bus speed
    final double distance = cappedSeconds * speedMps;

    return cachedVehicles.map((v) {
      final newPos = _projectPosition(v.position, v.bearing, distance);
      return TransitVehicle(
        id: v.id,
        line: v.line,
        position: newPos,
        bearing: v.bearing,
        lastUpdate: v.lastUpdate.add(Duration(seconds: cappedSeconds.toInt())),
        destination: v.destination,
        delay: v.delay,
      );
    }).toList();
  }

  LatLng _projectPosition(LatLng start, double bearingDegrees, double distanceMeters) {
    final double bearingRad = bearingDegrees * 3.141592653589793 / 180.0;
    const double earthRadius = 6371000.0; // meters

    final double dLat = distanceMeters * cos(bearingRad) / earthRadius;
    final double dLng = distanceMeters * sin(bearingRad) / (earthRadius * cos(start.latitude * 3.141592653589793 / 180.0));

    return LatLng(
      start.latitude + dLat * (180.0 / 3.141592653589793),
      start.longitude + dLng * (180.0 / 3.141592653589793),
    );
  }

  String _getHttpStatusMessage(int statusCode) {
    switch (statusCode) {
      case 400: return '400 Bad Request (Paquete o URL mal formada)';
      case 401: return '401 Unauthorized (Claves inválidas o vencidas)';
      case 403: return '403 Forbidden (Acceso denegado, IP bloqueada)';
      case 404: return '404 Not Found (Endpoint inexistente)';
      case 429: return '429 Too Many Requests (Exceso de límite de consultas)';
      case 500: return '500 Internal Server Error (Servidor GCBA caído)';
      case 502: return '502 Bad Gateway (Puerta de enlace incorrecta)';
      case 503: return '503 Service Unavailable (Servidor sobrecargado)';
      default: return 'Error HTTP $statusCode';
    }
  }

  // Parser unificado del FeedMessage de GTFS-Realtime
  List<TransitVehicle> _parseFeedMessage(
    gtfs.FeedMessage feed, {
    Map<String, int>? tripDelays,
    Map<String, int>? vehicleDelays,
  }) {
    final List<TransitVehicle> parsedVehicles = [];

    for (final entity in feed.entity) {
      if (entity.hasVehicle()) {
        final vp = entity.vehicle;
        final String routeId = vp.hasTrip() ? vp.trip.routeId : '';
        
        // Clean line identifier
        String line = routeId;
        if (line.contains('-')) {
          line = line.split('-').first;
        }
        line = line.trim();

        // ONLY parse if it is Line 159 or Line 98! Skip all other lines of AMBA immediately!
        if (!line.startsWith('159') && !line.startsWith('98')) {
          continue;
        }

        final pos = vp.position;
        final double lat = pos.latitude;
        final double lng = pos.longitude;
        final double bearing = pos.bearing;
        
        if (lat == 0.0 || lng == 0.0) continue;

        final String vehicleId = vp.hasVehicle() && vp.vehicle.hasId() ? vp.vehicle.id : entity.id;
        final String? tripId = vp.hasTrip() ? vp.trip.tripId : null;

        // Buscar demora asociada si existe
        int? delay;
        if (tripDelays != null && tripId != null && tripDelays.containsKey(tripId)) {
          delay = tripDelays[tripId];
        } else if (vehicleDelays != null && vehicleDelays.containsKey(vehicleId)) {
          delay = vehicleDelays[vehicleId];
        }

        // Enriquecer el destino con el ramal/delay
        String destination = vp.hasTrip() && vp.trip.hasTripId() 
            ? 'Recorrido ${vp.trip.tripId}' 
            : 'En recorrido';

        if (delay != null) {
          final minutes = (delay / 60).round();
          if (minutes > 0) {
            destination += ' (+$minutes min)';
          } else if (minutes < 0) {
            destination += ' ($minutes min)';
          } else {
            destination += ' (A tiempo)';
          }
        }

        // Filtro para mostrar líneas principales de interés del AMBA
        if (line.contains('98') || line.contains('159') || line.contains('60') || line.contains('129')) {
          parsedVehicles.add(
            TransitVehicle(
              id: vehicleId,
              line: line,
              position: LatLng(lat, lng),
              bearing: bearing,
              lastUpdate: DateTime.fromMillisecondsSinceEpoch(
                vp.hasTimestamp() ? vp.timestamp.toInt() * 1000 : DateTime.now().millisecondsSinceEpoch
              ),
              destination: destination,
              delay: delay,
            ),
          );
        }
      }
    }
    return parsedVehicles;
  }

  void _runSilentDiagnostics() async {
    // Skip diagnostics in tests to prevent pending timers and network requests
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;



    // Diagnóstico de API GCBA
    try {
      final res = await InternetAddress.lookup('apitransporte.buenosaires.gob.ar').timeout(const Duration(seconds: 4));
      if (res.isNotEmpty) {
        DebugConfig.updateStatus('GCBA API DNS OK');
      }
    } catch (e) {
      DebugConfig.updateStatus('GCBA DNS Fail: $e');
    }
  }

  List<TransitVehicle> _simulateProfessionalMovement() {
    final DateTime now = DateTime.now();
    final int secondsInHour = now.minute * 60 + now.second;
    final int segmentDuration = 10;
    
    final int indexR3 = _routeR3.isNotEmpty ? (secondsInHour ~/ segmentDuration) % (_routeR3.length - 1) : 0;
    final int indexR5 = _routeR5.isNotEmpty ? (secondsInHour ~/ segmentDuration) % (_routeR5.length - 1) : 0;
    final int indexR1 = _route159R1.isNotEmpty ? (secondsInHour ~/ segmentDuration) % (_route159R1.length - 1) : 0;
    final int indexR2 = _route159R2.isNotEmpty ? (secondsInHour ~/ segmentDuration) % (_route159R2.length - 1) : 0;
    final int indexAzul = _route159Azul.isNotEmpty ? (secondsInHour ~/ segmentDuration) % (_route159Azul.length - 1) : 0;
    final int indexRoja = _route159Roja.isNotEmpty ? (secondsInHour ~/ segmentDuration) % (_route159Roja.length - 1) : 0;
    final double t = (secondsInHour % segmentDuration) / segmentDuration.toDouble();

    return [
      _createSimulatedVehicle('sim_98_r3', '98 - Ramal 3 (Lisandro de la Torre)', _routeR3, indexR3, t, 'Once - Berazategui (Lisandro de la Torre)', 120),
      _createSimulatedVehicle('sim_98_r5', '98 - Ramal 5 (Av. Mitre)', _routeR5, indexR5, t, 'Once - Berazategui (Av. Mitre)', 0),
      _createSimulatedVehicle('sim_159_r1', '159 - Ramal 1 (Cruce Varela)', _route159R1, indexR1, t, 'Cruce Varela', 60),
      _createSimulatedVehicle('sim_159_r2', '159 - Ramal 2 (Villa España)', _route159R2, indexR2, t, 'Villa España', 120),
      _createSimulatedVehicle('sim_159_azul', '159 - L Azul (Alpargatas)', _route159Azul, indexAzul, t, 'Alpargatas', 180),
      _createSimulatedVehicle('sim_159_roja', '159 - L Roja (Alpargatas)', _route159Roja, indexRoja, t, 'Alpargatas', 240),
    ];
  }

  TransitVehicle _createSimulatedVehicle(String id, String line, List<LatLng> route, int index, double t, String dest, int? delay) {
    if (route.isEmpty) {
      return TransitVehicle(
        id: id,
        line: line,
        position: const LatLng(-34.7611, -58.2115),
        bearing: 0.0,
        lastUpdate: DateTime.now(),
        destination: dest,
        delay: delay,
      );
    }
    final int safeIndex = index % route.length;
    final int nextIndex = (safeIndex + 1) % route.length;
    final start = route[safeIndex];
    final end = route[nextIndex];
    
    final lat = start.latitude + (end.latitude - start.latitude) * t;
    final lng = start.longitude + (end.longitude - start.longitude) * t;
    
    return TransitVehicle(
      id: id,
      line: line,
      position: LatLng(lat, lng),
      bearing: Geolocator.bearingBetween(start.latitude, start.longitude, end.latitude, end.longitude),
      lastUpdate: DateTime.now(),
      destination: dest,
      delay: delay,
    );
  }

  Future<List<TransitVehicle>> _loadTheoreticalVehicles() async {
    final List<TransitVehicle> theoreticalVehicles = [];
    try {
      final dbService = DatabaseService();
      final List<Map<String, dynamic>> rawSchedules = await dbService.getOfflineSchedules();

      // Pre-load all sorted shapes into a map
      final Map<String, List<LatLng>> routesMap = {};
      
      final shapeMapping = {
        '159': '159_azul_shape',
        '98 - R3': '98_r3_shape',
        '98 - R5': '98_r5_shape',
      };

      for (final entry in shapeMapping.entries) {
        final List<Map<String, dynamic>> pointsData = List.from(
          await dbService.getShapesForId(entry.value)
        );
        if (pointsData.isNotEmpty) {
          // Explicit sort on shape_pt_sequence to be absolutely safe
          pointsData.sort((a, b) => (a['shape_pt_sequence'] as int).compareTo(b['shape_pt_sequence'] as int));
          
          routesMap[entry.key] = pointsData.map((pt) {
            return LatLng(pt['shape_pt_lat'] as double, pt['shape_pt_lon'] as double);
          }).toList();
        }
      }

      final DateTime now = DateTime.now();
      final int currentSecondsSinceMidnight = now.hour * 3600 + now.minute * 60 + now.second;

      for (final s in rawSchedules) {
        final String line = s['line'] as String;
        final String depTime = s['departure_time'] as String;
        final int durationMinutes = s['trip_duration_minutes'] as int;

        // Parse departure time
        final List<String> parts = depTime.split(':');
        if (parts.length != 2) continue;
        final int depHour = int.parse(parts[0]);
        final int depMin = int.parse(parts[1]);
        final int depSecondsSinceMidnight = depHour * 3600 + depMin * 60;

        // Calculate time elapsed since departure
        int elapsedSeconds = currentSecondsSinceMidnight - depSecondsSinceMidnight;
        if (elapsedSeconds < 0) continue;

        final int durationSeconds = durationMinutes * 60;
        if (elapsedSeconds < durationSeconds) {
          // Bus is currently active!
          final double fraction = elapsedSeconds.toDouble() / durationSeconds.toDouble();
          final List<LatLng>? path = routesMap[line];
          if (path != null && path.isNotEmpty) {
            final LatLng pos = _interpolatePosition(path, fraction);
            
            // Calculate bearing
            double bearing = 0.0;
            final double totalPoints = (path.length - 1).toDouble();
            final double indexDouble = fraction * totalPoints;
            final int index = indexDouble.floor();
            if (index < path.length - 1) {
              bearing = Geolocator.bearingBetween(
                path[index].latitude, path[index].longitude,
                path[index + 1].latitude, path[index + 1].longitude
              );
            }

            final String dest = line.startsWith('159') 
                ? 'Correo Central (Horario Teórico)' 
                : 'Once - Berazategui (Horario Teórico)';

            theoreticalVehicles.add(
              TransitVehicle(
                id: 'teorico_${line.replaceAll(' ', '_')}_$depTime',
                line: line,
                position: pos,
                bearing: bearing,
                lastUpdate: DateTime.now(),
                destination: dest,
                delay: null, // Theoretical
              ),
            );
          }
        }
      }
    } catch (e) {
      print('[GTFS-RT] Error cargando vehículos teóricos de SQLite: $e');
    }
    return theoreticalVehicles;
  }

  LatLng _interpolatePosition(List<LatLng> path, double fraction) {
    if (path.isEmpty) return const LatLng(0, 0);
    if (path.length == 1 || fraction <= 0.0) return path.first;
    if (fraction >= 1.0) return path.last;

    final double totalPoints = (path.length - 1).toDouble();
    final double indexDouble = fraction * totalPoints;
    final int index = indexDouble.floor();
    final double t = indexDouble - index;

    final LatLng start = path[index];
    final LatLng end = path[index + 1];

    return LatLng(
      start.latitude + (end.latitude - start.latitude) * t,
      start.longitude + (end.longitude - start.longitude) * t,
    );
  }

  String _redactSecrets(String input) {
    final String clientID = dotenv.env['TRANSIT_CLIENT_ID'] ?? '';
    final String clientSecret = dotenv.env['TRANSIT_SECRET'] ?? '';
    
    String redacted = input;
    if (clientID.isNotEmpty && clientID != 'mock') {
      redacted = redacted.replaceAll(clientID, '***CLIENT_ID***');
    }
    if (clientSecret.isNotEmpty && clientSecret != 'mock') {
      redacted = redacted.replaceAll(clientSecret, '***CLIENT_SECRET***');
    }
    return redacted;
  }

  // Función estructural para filtrado de colectivos de interés (Favoritos/Simulación).
  // Actualmente configurado para forzar que muestre únicamente 98 y 159.
  List<TransitVehicle> _filterVehicles(List<TransitVehicle> list) {
    return list.where((vehicle) {
      final String line = vehicle.line.split('-').first.trim().toLowerCase();
      return line.contains('98') || line.contains('159');
    }).toList();
  }
}

class _DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}
