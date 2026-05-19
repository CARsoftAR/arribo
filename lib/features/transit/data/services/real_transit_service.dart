import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:arribo/features/transit/domain/models/transit_vehicle.dart';
import 'package:arribo/core/config/debug_config.dart';
import 'package:flutter/services.dart' show rootBundle;

class RealTransitService implements TransitService {
  static const String _publicApiUrl =
      'https://api.sube.gob.ar/v1/sube/micro/posiciones';

  // Historial de vehículos (Solo reales, sin semillas)
  List<TransitVehicle> _lastValidVehicles = [];

  // Rutas reales de precisión (Calle 14, Mitre, Diagonal)
  static List<LatLng> _routeR3 = [
    const LatLng(-34.7618, -58.2120), // Calle 14 y 147
    const LatLng(-34.7625, -58.2120), // Calle 14 y 148
    const LatLng(-34.7635, -58.2120), // Cruce Calle 14 y Av. Mitre
    const LatLng(-34.7645, -58.2120), // Av. Mitre hacia el Sur
  ];

  static List<LatLng> _routeR5 = [
    const LatLng(-34.7595, -58.2140), // Calle 13 y 146
    const LatLng(-34.7615, -58.2120), // Inicio Diagonal Lisandro de la Torre
    const LatLng(-34.7635, -58.2100), // Diagonal y Av. 14
    const LatLng(-34.7650, -58.2080), // Diagonal hacia el Sudeste
  ];

  static bool _routesLoaded = false;

  static Future<void> _loadFullRoutesIfNeeded() async {
    if (_routesLoaded) return;
    try {
      String route98JsonStr;
      try {
        route98JsonStr = await rootBundle.loadString('assets/data/route_98_r5_detailed.json');
      } catch (_) {
        route98JsonStr = await rootBundle.loadString('assets/data/route_98.json');
      }
      final List<dynamic> route98List = jsonDecode(route98JsonStr);
      final List<LatLng> parsed98 = route98List.map((pt) => LatLng((pt['lat'] as num).toDouble(), (pt['lng'] as num).toDouble())).toList();
      if (parsed98.isNotEmpty) {
        _routeR5 = parsed98;
        
        // Lisandro de la Torre Ramal 3 setup (dynamic intersection split)
        int splitIndex98 = parsed98.indexWhere((pt) => 
          (pt.latitude - -34.7635).abs() < 0.001 && 
          (pt.longitude - -58.2117).abs() < 0.001
        );
        if (splitIndex98 == -1) {
          splitIndex98 = (parsed98.length - 8).clamp(0, parsed98.length);
        }
        
        _routeR3 = List<LatLng>.from(parsed98.sublist(0, splitIndex98 + 1));
        final List<LatLng> r3Streets = [
          const LatLng(-34.7640, -58.2120),
          const LatLng(-34.7650, -58.2120),
          const LatLng(-34.7660, -58.2120),
          const LatLng(-34.7670, -58.2120),
          const LatLng(-34.7680, -58.2120),
          const LatLng(-34.7690, -58.2120),
          const LatLng(-34.7700, -58.2120),
        ];
        _routeR3.addAll(r3Streets);
      }
    } catch (e) {
      print('[Real-Transit] Error loading full route 98 from JSON: $e');
    }
    _routesLoaded = true;
  }

  @override
  Stream<List<TransitVehicle>> getVehiclesStream() async* {
    // PRUEBA DE DIAGNÓSTICO INICIAL (DNS SILENCIOSO)
    _runSilentDiagnostic();
    await _loadFullRoutesIfNeeded();

    while (true) {
      try {
        // Intento de conexión real en segundo plano
        final response = await http.get(
          Uri.parse(_publicApiUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
          },
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final List<dynamic> rawData = json.decode(response.body);
          final List<TransitVehicle> vehicles = _parseAndFilter(rawData);
          if (vehicles.isNotEmpty) {
            DebugConfig.updateStatus('CONECTADO A DATOS REALES', loading: false);
            yield vehicles;
          } else {
            yield _simulateProfessionalMovement();
          }
        } else {
          DebugConfig.updateStatus('DEV MODE | Simulando Ruta 98 R3/R5', loading: false);
          yield _simulateProfessionalMovement();
        }
      } catch (e) {
        DebugConfig.updateStatus('DEV MODE | Simulando Ruta 98 R3/R5', loading: false);
        yield _simulateProfessionalMovement();
      }
      
      await Future.delayed(const Duration(seconds: 5)); // Movimiento más frecuente
    }
  }

  void _runSilentDiagnostic() async {
    try {
      final res = await InternetAddress.lookup('api.sube.gob.ar').timeout(const Duration(seconds: 5));
      if (res.isNotEmpty) {
        DebugConfig.updateStatus('SUBE DNS OK');
      }
    } catch (e) {
      DebugConfig.updateStatus('SUBE DNS Fail: $e');
    }
  }

  List<TransitVehicle> _simulateProfessionalMovement() {
    final DateTime now = DateTime.now();
    final int secondsInHour = now.minute * 60 + now.second;
    
    // Simulación suave basada en el tiempo absoluto del minuto
    final int segmentDuration = 10; // Segundos por segmento
    
    final int indexR3 = (secondsInHour ~/ segmentDuration) % (_routeR3.length - 1);
    final int indexR5 = (secondsInHour ~/ segmentDuration) % (_routeR5.length - 1);
    final double t = (secondsInHour % segmentDuration) / segmentDuration.toDouble();

    return [
      _createSimulatedVehicle('sim_98_r3', '98 - Ramal 3 (Lisandro de la Torre)', _routeR3, indexR3, t, 'Once - Berazategui (Lisandro de la Torre)'),
      _createSimulatedVehicle('sim_98_r5', '98 - Ramal 5 (Av. Mitre)', _routeR5, indexR5, t, 'Once - Berazategui (Av. Mitre)'),
    ];
  }

  TransitVehicle _createSimulatedVehicle(String id, String line, List<LatLng> route, int index, double t, String dest) {
    final start = route[index];
    final end = route[index + 1];
    
    final lat = start.latitude + (end.latitude - start.latitude) * t;
    final lng = start.longitude + (end.longitude - start.longitude) * t;
    
    return TransitVehicle(
      id: id,
      line: line,
      position: LatLng(lat, lng),
      bearing: Geolocator.bearingBetween(start.latitude, start.longitude, end.latitude, end.longitude),
      lastUpdate: DateTime.now(),
      destination: dest,
    );
  }

  List<TransitVehicle> _parseAndFilter(List<dynamic> rawData) {
    final List<TransitVehicle> validVehicles = [];

    for (var item in rawData) {
      try {
        final double lat = (item['latitud'] ?? item['lat'] ?? item['latitude'] ?? 0.0).toDouble();
        final double lng = (item['longitud'] ?? item['lon'] ?? item['lng'] ?? item['longitude'] ?? 0.0).toDouble();

        if (lat == 0.0 || lng == 0.0) continue;

        String line = (item['linea'] ?? item['route_short_name'] ?? item['route_id'] ?? 'Unknown').toString();
        final String destination = (item['destino'] ?? item['trip_headsign'] ?? 'En recorrido').toString();

        // Identificación de Ramal: '98 - R3' o '98 - R5' (Mejora de UX)
        if (line.contains('98')) {
          if (destination.contains('3')) {
            line = '98 - R3';
          } else if (destination.contains('5')) {
            line = '98 - R5';
          }
        }

        // FILTRO RELAJADO: Si es 98 o 159, lo mostramos SIEMPRE
        if (line.contains('98') || line.contains('159')) {
          validVehicles.add(
            TransitVehicle(
              id: (item['id'] ?? item['interno'] ?? item['vehicle_id'] ?? item['unit_id'] ?? 'unknown').toString(),
              line: line,
              position: LatLng(lat, lng),
              bearing: (item['rumbo'] ?? item['bearing'] ?? item['direction'] ?? item['heading'] ?? 0.0).toDouble(),
              lastUpdate: DateTime.now(),
              destination: destination,
            ),
          );
        }
      } catch (e) {
        continue;
      }
    }
    return validVehicles;
  }
}
