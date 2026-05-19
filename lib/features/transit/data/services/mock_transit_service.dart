import 'dart:async';
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:arribo/features/transit/domain/models/transit_vehicle.dart';

class MockTransitService implements TransitService {
  final _random = Random();
  LatLng? _referenceLocation;
  
  void setReferenceLocation(LatLng location) {
    _referenceLocation = location;
  }

  @override
  Stream<List<TransitVehicle>> getVehiclesStream() async* {
    final List<String> lines = ['159', '60', '129', '98'];
    
    while (true) {
      final List<TransitVehicle> vehicles = [];
      final center = _referenceLocation ?? const LatLng(-34.6037, -58.3816);
      
      for (var baseLine in lines) {
        for (int i = 0; i < 3; i++) {
          final destination = baseLine == '159' ? 'Correo Central' : 
                             baseLine == '60' ? 'Constitución' : 
                             baseLine == '129' ? 'Retiro' : 'Ramal ${i % 2 == 0 ? 3 : 5}';
          
          String line = baseLine;
          if (baseLine == '98') {
            line = destination.contains('3') ? '98 - R3' : '98 - R5';
          }

          vehicles.add(
            TransitVehicle(
              id: 'bus_${line}_$i',
              line: line,
              position: LatLng(
                center.latitude + (_random.nextDouble() - 0.5) * 0.015,
                center.longitude + (_random.nextDouble() - 0.5) * 0.015,
              ),
              bearing: _random.nextDouble() * 360,
              lastUpdate: DateTime.now(),
              destination: destination,
            ),
          );
        }
      }
      yield vehicles;
      await Future.delayed(const Duration(seconds: 10));
    }
  }
}
