import 'package:arribo/features/transit/domain/models/transit_vehicle.dart';
import 'gtfs_realtime_service.dart';

class TransitServiceFactory {
  static TransitService create() {
    // Retornamos el servicio oficial GTFS-Realtime (Protobuf)
    return GtfsRealtimeTransitService();
  }
}
