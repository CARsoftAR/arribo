import 'dart:async';
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Bus {
  final String id;
  final String line;
  final LatLng position;

  Bus({required this.id, required this.line, required this.position});
}

class CloudTransitService {
  final _busStreamController = StreamController<List<Bus>>.broadcast();

  Stream<List<Bus>> get busStream => _busStreamController.stream;

  void startSimulating(LatLng userLocation) {
    Timer.periodic(const Duration(seconds: 3), (timer) {
      final random = Random();
      final buses = List.generate(3, (index) {
        // Small offsets from user location
        double latOffset = (random.nextDouble() - 0.5) * 0.01;
        double lngOffset = (random.nextDouble() - 0.5) * 0.01;
        
        return Bus(
          id: 'bus_$index',
          line: index == 0 ? '60' : index == 1 ? '152' : '59',
          position: LatLng(userLocation.latitude + latOffset, userLocation.longitude + lngOffset),
        );
      });
      
      _busStreamController.add(buses);
    });
  }

  void dispose() {
    _busStreamController.close();
  }
}
