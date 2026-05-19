import 'package:google_maps_flutter/google_maps_flutter.dart';

class TransitVehicle {
  final String id;
  final String line;
  final LatLng position;
  final double bearing;
  final DateTime lastUpdate;
  final String destination;
  final int? delay; // Delay in seconds (from Trip Updates)
  final String? shapeId; // Dynamic GTFS shape identifier

  TransitVehicle({
    required this.id,
    required this.line,
    required this.position,
    required this.bearing,
    required this.lastUpdate,
    this.destination = 'Terminal',
    this.delay,
    this.shapeId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'line': line,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'bearing': bearing,
      'lastUpdate': lastUpdate.toIso8601String(),
      'destination': destination,
      'delay': delay,
      'shapeId': shapeId,
    };
  }

  factory TransitVehicle.fromJson(Map<String, dynamic> json) {
    return TransitVehicle(
      id: json['id'] as String,
      line: json['line'] as String,
      position: LatLng(json['latitude'] as double, json['longitude'] as double),
      bearing: (json['bearing'] as num).toDouble(),
      lastUpdate: DateTime.parse(json['lastUpdate'] as String),
      destination: json['destination'] as String? ?? 'Terminal',
      delay: json['delay'] as int?,
      shapeId: json['shapeId'] as String?,
    );
  }
}

abstract class TransitService {
  Stream<List<TransitVehicle>> getVehiclesStream();
}
