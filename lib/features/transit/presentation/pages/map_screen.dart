import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:arribo/core/config/debug_config.dart';
import 'package:arribo/core/constants/map_style.dart';
import 'package:arribo/features/ui_components/glass_card.dart';
import 'package:arribo/features/ui_components/neo_button.dart';
import 'package:arribo/features/transit/data/services/transit_service_factory.dart';
import 'package:arribo/features/transit/data/services/database_service.dart';
import 'package:arribo/features/transit/data/services/mock_transit_service.dart';
import 'package:arribo/features/transit/domain/models/transit_vehicle.dart';
import 'package:arribo/features/transit/presentation/widgets/vehicle_detail_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  final TransitService _transitService = TransitServiceFactory.create();
  final DatabaseService _databaseService = DatabaseService();
  final TextEditingController _searchController = TextEditingController();
  
  Set<Marker> _markers = {};
  Set<Marker> _terminalMarkers = {};
  Set<Polyline> _polylines = {};
  List<TransitVehicle> _allVehicles = [];
  String _searchFilter = '';
  bool _hasActiveSearch = false; // Estado de búsqueda activa para inicio limpio
  LatLng? _userLocation;
  
  // Ramales selection state variables
  String? _activeSearchedLine;
  final Set<String> _selectedRamales = {};
  bool _showBranchSelector = false;
  final Map<String, List<String>> _lineRamales = {
    '159': [
      '159 - Ramal 1 (Cruce Varela)',
      '159 - Ramal 2 (Villa España)',
      '159 - L Azul (Alpargatas)',
      '159 - L Roja (Alpargatas)',
    ],
    '98': [
      '98 - Ramal 3 (Lisandro de la Torre)',
      '98 - Ramal 5 (Av. Mitre)',
    ]
  };
  
  // Follow & Animation logic
  String? _followedVehicleId;
  bool _showProximityAlert = false;
  Timer? _pulseTimer;
  double _pulseGlow = 0.5;
  bool _isPulseGrowing = true;
  String? _errorMessage; // Para capturar errores visibles
  TransitVehicle? _selectedVehicle; // Vehículo actualmente seleccionado

  // Interpolation logic
  late AnimationController _interpolationController;
  final Map<String, LatLng> _previousPositions = {};
  final Map<String, LatLng> _targetPositions = {};
  StreamSubscription<List<TransitVehicle>>? _transitSubscription;
  
  // Vibration logic for peak hours
  double _vibrationScale = 1.0;
  
  // Cache for markers to improve performance
  final Map<String, BitmapDescriptor> _markerCache = {};
  
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(-34.7611, -58.2115), // Berazategui center (Hardcoded)
    zoom: 15.0,
    tilt: 45.0,
    bearing: 0.0,
  );

  bool _isPeakHour() {
    final hour = DateTime.now().hour;
    return (hour >= 6 && hour < 9) || (hour >= 17 && hour < 20);
  }

  @override
  void initState() {
    super.initState();
    _interpolationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000), // Smooth 2s transition
    )..addListener(() {
      _updateMarkers();
    });
    _determinePosition();
    _startTransitStream();
    _startPulseAnimation();
  }


  @override
  void dispose() {
    _searchController.dispose();
    _pulseTimer?.cancel();
    _transitSubscription?.cancel();
    _interpolationController.dispose();
    super.dispose();
  }

  void _startPulseAnimation() {
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      
      setState(() {
        if (_isPulseGrowing) {
          _pulseGlow += 0.1;
          if (_pulseGlow >= 1.0) _isPulseGrowing = false;
        } else {
          _pulseGlow -= 0.1;
          if (_pulseGlow <= 0.3) _isPulseGrowing = true;
        }

        // Vibration logic (only if peak hour)
        if (_isPeakHour()) {
          _vibrationScale = 0.95 + (Random().nextDouble() * 0.1);
        } else {
          _vibrationScale = 1.0;
        }
      });
      
      if (_terminalMarkers.isNotEmpty) {
        _updateTerminalMarkers();
      }
    });
  }

  void _startTransitStream() {
    _transitSubscription = _transitService.getVehiclesStream().listen((vehicles) {
      if (!mounted) return;

      // Capture positions for interpolation
      _previousPositions.clear();
      for (var v in _allVehicles) {
        _previousPositions[v.id] = v.position;
      }

      _targetPositions.clear();
      for (var v in vehicles) {
        _targetPositions[v.id] = v.position;
      }

      _allVehicles = vehicles;
      
      // Trigger smooth "flying" interpolation
      _interpolationController.forward(from: 0.0);
      
      // Handle Auto-Follow
      if (_followedVehicleId != null) {
        final followed = vehicles.cast<TransitVehicle?>().firstWhere(
          (v) => v?.id == _followedVehicleId, 
          orElse: () => null
        );
        
        if (followed != null) {
          _mapController?.animateCamera(CameraUpdate.newLatLng(followed.position));
          
          // Proximity Alert (approx 500m)
          if (_userLocation != null) {
            double distance = Geolocator.distanceBetween(
              _userLocation!.latitude, _userLocation!.longitude,
              followed.position.latitude, followed.position.longitude
            );
            if (distance < 500 && !_showProximityAlert) {
              setState(() => _showProximityAlert = true);
              HapticFeedback.vibrate();
            } else if (distance >= 500 && _showProximityAlert) {
              setState(() => _showProximityAlert = false);
            }
          }
        }
      }
    });
  }

  Color _getLineColor(String line) {
    if (line.startsWith('159')) return const Color(0xFF0052CC); // Azul Premium
    
    // Diferenciación específica para Línea 98 (Expreso Quilmes - Verde Oscuro con letras y rutas Amarillas)
    if (line.startsWith('98')) return const Color(0xFFFCD116);
    
    if (line.startsWith('60')) return const Color(0xFFFFD700); // Amarillo
    if (line.startsWith('129')) return const Color(0xFFD32F2F); // Rojo
    if (line.startsWith('148')) return const Color(0xFF2E7D32); // Verde
    return const Color(0xFF94A3B8); // Neutro elegante
  }

  // Mapeo de colores de fondo institucionales oficiales
  static const Map<String, Color> _lineBackgroundColors = {
    '159': Color(0xFF39B54A), // Verde MOQSA
    '98': Color(0xFF137A3E),  // Verde de carrocería 98
    '60': Color(0xFFFFD700),   // Amarillo 60
    '129': Color(0xFFD32F2F),  // Rojo 129
    '148': Color(0xFF2E7D32),  // Verde 148
  };

  // Mapeo de colores de texto e iconos institucionales oficiales
  static const Map<String, Color> _lineTextColors = {
    '159': Color(0xFFFFFFFF), // Blanco
    '98': Color(0xFFFCD116),  // Amarillo de laterales 98
    '60': Color(0xFF000000),   // Negro para contraste sobre Amarillo
    '129': Color(0xFFFFFFFF), // Blanco
    '148': Color(0xFFFFFFFF), // Blanco
  };

  Color _getHeaderColor() {
    // 1. Si hay un colectivo seleccionado/abierto
    if (_selectedVehicle != null) {
      return _getLineInstitutionalColor(_selectedVehicle!.line);
    }
    // 2. Si hay un colectivo siendo seguido
    if (_followedVehicleId != null) {
      final followed = _allVehicles.cast<TransitVehicle?>().firstWhere(
        (v) => v?.id == _followedVehicleId,
        orElse: () => null,
      );
      if (followed != null) {
        return _getLineInstitutionalColor(followed.line);
      }
    }
    // 3. Si hay un filtro ingresado en el buscador
    if (_hasActiveSearch && _searchFilter.trim().isNotEmpty) {
      return _getLineInstitutionalColor(_searchFilter);
    }
    // Color verde base de MOQSA
    return const Color(0xFF39B54A);
  }

  Color _getHeaderTextColor() {
    // 1. Si hay un colectivo seleccionado/abierto
    if (_selectedVehicle != null) {
      return _getLineInstitutionalTextColor(_selectedVehicle!.line);
    }
    // 2. Si hay un colectivo siendo seguido
    if (_followedVehicleId != null) {
      final followed = _allVehicles.cast<TransitVehicle?>().firstWhere(
        (v) => v?.id == _followedVehicleId,
        orElse: () => null,
      );
      if (followed != null) {
        return _getLineInstitutionalTextColor(followed.line);
      }
    }
    // 3. Si hay un filtro ingresado en el buscador
    if (_hasActiveSearch && _searchFilter.trim().isNotEmpty) {
      return _getLineInstitutionalTextColor(_searchFilter);
    }
    // Color blanco base
    return const Color(0xFFFFFFFF);
  }

  Color _getLineInstitutionalColor(String rawLine) {
    String cleanLine = rawLine.toLowerCase();
    if (cleanLine.contains('-')) {
      cleanLine = cleanLine.split('-').first.trim();
    }
    for (final key in _lineBackgroundColors.keys) {
      if (cleanLine.startsWith(key)) {
        return _lineBackgroundColors[key]!;
      }
    }
    return const Color(0xFF39B54A);
  }

  Color _getLineInstitutionalTextColor(String rawLine) {
    String cleanLine = rawLine.toLowerCase();
    if (cleanLine.contains('-')) {
      cleanLine = cleanLine.split('-').first.trim();
    }
    for (final key in _lineTextColors.keys) {
      if (cleanLine.startsWith(key)) {
        return _lineTextColors[key]!;
      }
    }
    return const Color(0xFFFFFFFF);
  }

  String? _getDefaultStartLine() {
    // Estructura preparada en las preferencias para configurar una línea de inicio por defecto
    return null; // Retorna null por defecto para inicio limpio, personalizable en el futuro
  }

  void _updateMarkers() async {
    final bool hasDefaultStartLine = _getDefaultStartLine() != null;
    if (!_hasActiveSearch && !hasDefaultStartLine) {
      if (mounted) {
        setState(() {
          _markers = {};
        });
      }
      return;
    }

    final activeFilter = _searchFilter.isEmpty ? (_getDefaultStartLine() ?? '') : _searchFilter;

    final filtered = activeFilter.isEmpty 
        ? _allVehicles 
        : _allVehicles.where((v) {
            final String name = v.line.toLowerCase();
            
            // If the searched line has branches, we strictly filter by selected branches
            if (_activeSearchedLine != null && _lineRamales.containsKey(_activeSearchedLine)) {
              if (name.startsWith(_activeSearchedLine!.toLowerCase())) {
                if (_selectedRamales.isEmpty) return false;
                
                // Si el nombre tiene un ramal explícito (ej: simuladores) filtramos fino
                if (name.contains('ramal') || name.contains(' - ') || name.contains('l azul') || name.contains('l roja')) {
                  return _selectedRamales.any((selectedBranch) {
                    final String branchNameClean = selectedBranch.toLowerCase();
                    if (branchNameClean.contains('ramal 1') && (name.contains('ramal 1') || v.destination.toLowerCase().contains('cruce'))) return true;
                    if (branchNameClean.contains('ramal 2') && (name.contains('ramal 2') || v.destination.toLowerCase().contains('españa'))) return true;
                    if (branchNameClean.contains('l azul') && (name.contains('l azul') || v.destination.toLowerCase().contains('azul') || v.destination.toLowerCase().contains('alpargatas'))) return true;
                    if (branchNameClean.contains('l roja') && (name.contains('l roja') || v.destination.toLowerCase().contains('roja'))) return true;
                    if (branchNameClean.contains('ramal 3') && (name.contains('ramal 3') || name.contains('r3'))) return true;
                    if (branchNameClean.contains('ramal 5') && (name.contains('ramal 5') || name.contains('r5'))) return true;
                    return false;
                  });
                }
                
                // Si es un vehículo real del GCBA (ej "159A", "98"), lo mostramos si hay algún ramal seleccionado de esa línea
                return _selectedRamales.any((selectedBranch) => selectedBranch.startsWith(_activeSearchedLine!));
              }
              return false;
            }

            // Normal fallback smart search
            final List<String> terms = activeFilter.toLowerCase().trim().split(RegExp(r'\s+'));
            return terms.every((term) => name.contains(term));
          }).toList();

    final newMarkers = <Marker>{};
    final double t = _interpolationController.value;

    // Detect overlapping to apply small offsets
    final Map<String, int> positionCounts = {};

    for (final vehicle in filtered) {
      final isFollowed = vehicle.id == _followedVehicleId;
      
      // Calculate Interpolated Position
      LatLng currentPos = vehicle.position;
      double rotation = vehicle.bearing;

      if (_previousPositions.containsKey(vehicle.id)) {
        final start = _previousPositions[vehicle.id]!;
        currentPos = LatLng(
          start.latitude + (vehicle.position.latitude - start.latitude) * t,
          start.longitude + (vehicle.position.longitude - start.longitude) * t,
        );

        // Rotation Calculation (Heading): If bearing is 0, calculate from vector
        if (rotation == 0) {
          rotation = Geolocator.bearingBetween(
            start.latitude, start.longitude,
            vehicle.position.latitude, vehicle.position.longitude
          );
        }
      }

      // Anti-overlapping Logic: Small offset for same coordinates
      final String posKey = '${vehicle.position.latitude.toStringAsFixed(5)},${vehicle.position.longitude.toStringAsFixed(5)}';
      final int count = positionCounts[posKey] ?? 0;
      positionCounts[posKey] = count + 1;
      
      if (count > 0) {
        // Apply a tiny offset (approx 1-2 meters) based on count
        currentPos = LatLng(
          currentPos.latitude + (count * 0.00002),
          currentPos.longitude + (count * 0.00002),
        );
      }

      BitmapDescriptor icon;
      if (isFollowed || _isPeakHour()) {
        icon = await _createNeonBusMarker(vehicle.line, isHighlighted: isFollowed);
      } else {
        if (!_markerCache.containsKey(vehicle.line)) {
          _markerCache[vehicle.line] = await _createNeonBusMarker(vehicle.line);
        }
        icon = _markerCache[vehicle.line]!;
      }

      String lineNum = vehicle.line;
      String branch = 'Común';
      if (vehicle.line.contains('-')) {
        final parts = vehicle.line.split('-');
        lineNum = parts.first.trim();
        branch = parts.sublist(1).join('-').trim();
      }
      if (lineNum == '159' && branch == 'Común') {
        branch = 'L Azul';
      }

      newMarkers.add(
        Marker(
          markerId: MarkerId(vehicle.id),
          position: currentPos,
          icon: icon,
          anchor: const Offset(0.5, 0.85),
          flat: false,
          zIndex: isFollowed ? 100 : (10 + vehicle.id.hashCode % 50),
          infoWindow: InfoWindow(
            title: 'Llegando • Línea $lineNum',
            snippet: 'Ramal: $branch • Arribando',
          ),
          onTap: () => _showVehicleDetails(vehicle),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _markers = newMarkers;
      });
    }
  }

  void _showVehicleDetails(TransitVehicle vehicle) {
    setState(() {
      _selectedVehicle = vehicle;
    });
    _showRouteFor(vehicle);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => VehicleDetailSheet(
        vehicle: vehicle,
        lineColor: _getLineColor(vehicle.line),
        isFollowing: _followedVehicleId == vehicle.id,
        onFollowChanged: (isFollowing) {
          setState(() {
            _followedVehicleId = isFollowing ? vehicle.id : null;
            if (!isFollowing) _showProximityAlert = false;
          });
          Navigator.pop(context);
          if (isFollowing) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Siguiendo línea ${vehicle.line}...'),
                backgroundColor: _getLineColor(vehicle.line),
              ),
            );
          }
        },
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _selectedVehicle = null;
        });
      }
    });
  }

  void _showRouteForLine(String line) async {
    try {
      final clean = line.trim().toLowerCase();
      final List<String> targetShapeIds = [];
      
      if (clean.contains('159')) {
        if (_selectedRamales.contains('159 - Ramal 1 (Cruce Varela)')) {
          targetShapeIds.add('159_r1_shape');
        }
        if (_selectedRamales.contains('159 - Ramal 2 (Villa España)')) {
          targetShapeIds.add('159_r2_shape');
        }
        if (_selectedRamales.contains('159 - L Azul (Alpargatas)')) {
          targetShapeIds.add('159_azul_shape');
        }
        if (_selectedRamales.contains('159 - L Roja (Alpargatas)')) {
          targetShapeIds.add('159_roja_shape');
        }
      } else if (clean.contains('98')) {
        // Draw branch-specific shapes for Expreso Quilmes based on checkboxes
        if (_selectedRamales.contains('98 - Ramal 3 (Lisandro de la Torre)')) {
          targetShapeIds.add('98_r3_shape');
        }
        if (_selectedRamales.contains('98 - Ramal 5 (Av. Mitre)')) {
          targetShapeIds.add('98_r5_shape');
        }
      }

      final Set<Polyline> newPolylines = {};
      final Color color = _getLineInstitutionalColor(line);

      for (final shapeId in targetShapeIds) {
        final List<Map<String, dynamic>> pointsData = List.from(
          await _databaseService.getShapesForId(shapeId)
        );

        if (pointsData.isEmpty) continue;

        // Explicitly sort by shape_pt_sequence to guarantee sequential street alignment
        pointsData.sort((a, b) => (a['shape_pt_sequence'] as int).compareTo(b['shape_pt_sequence'] as int));

        final List<LatLng> points = pointsData.map((pt) {
          return LatLng(pt['shape_pt_lat'] as double, pt['shape_pt_lon'] as double);
        }).toList();

        Color routeColor = color;
        if (shapeId.contains('98')) {
          routeColor = shapeId.contains('r3')
              ? const Color(0xFF137A3E) // Dark Green for Ramal 3
              : const Color(0xFFE11D48); // Red Accent for Ramal 5
        } else {
          if (shapeId.contains('r1')) {
            routeColor = const Color(0xFF0EA5E9); // Sky Blue for Ramal 1
          } else if (shapeId.contains('r2')) {
            routeColor = const Color(0xFF8B5CF6); // Violet for Ramal 2
          } else if (shapeId.contains('azul')) {
            routeColor = const Color(0xFF3B82F6); // Premium Blue for L Azul
          } else if (shapeId.contains('roja')) {
            routeColor = const Color(0xFFEF4444); // Premium Red for L Roja
          } else {
            routeColor = const Color(0xFF0052CC); // Fallback MOQSA
          }
        }

        newPolylines.add(
          Polyline(
            polylineId: PolylineId('route_$shapeId'),
            points: points,
            color: routeColor.withValues(alpha: 0.95), 
            width: 5, 
            jointType: JointType.round,
            endCap: Cap.roundCap,
            startCap: Cap.roundCap,
          ),
        );
      }

      setState(() {
        _polylines = newPolylines;
      });
      _updateTerminalMarkers();
    } catch (e) {
      debugPrint('Error cargando ruta dinámica GTFS shapes: $e');
    }
  }

  void _showRouteFor(TransitVehicle vehicle) async {
    _showRouteForLine(vehicle.line);
  }

  void _updateTerminalMarkers() async {
    if (_polylines.isEmpty) return;
    
    final newTerminalMarkers = <Marker>{};
    
    for (final polyline in _polylines) {
      final points = polyline.points;
      final Color color = polyline.color;
      final String idSuffix = polyline.polylineId.value;
      
      final termAIcon = await _createTerminalMarker('A', color, intensity: _pulseGlow);
      final termBIcon = await _createTerminalMarker('B', color, intensity: _pulseGlow);
      
      newTerminalMarkers.add(
        Marker(
          markerId: MarkerId('term_a_$idSuffix'),
          position: points.first,
          icon: termAIcon,
          anchor: const Offset(0.5, 0.5),
          zIndex: 5,
        ),
      );
      
      newTerminalMarkers.add(
        Marker(
          markerId: MarkerId('term_b_$idSuffix'),
          position: points.last,
          icon: termBIcon,
          anchor: const Offset(0.5, 0.5),
          zIndex: 5,
          infoWindow: const InfoWindow(title: 'Terminal de Arribo'),
        ),
      );
    }
    
    setState(() {
      _terminalMarkers = newTerminalMarkers;
    });
  }

  Future<BitmapDescriptor> _createTerminalMarker(String label, Color color, {double intensity = 0.5}) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double size = 100.0; // Larger canvas for better glow
    
    // subtle pulsing Neon Glow
    final Paint glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3 * intensity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12.0 * intensity);
    canvas.drawCircle(Offset(size / 2, size / 2), 22 * intensity, glowPaint);

    final Paint outerGlow = Paint()
      ..color = color.withValues(alpha: 0.15 * intensity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 35.0 * intensity);
    canvas.drawCircle(Offset(size / 2, size / 2), 35 * intensity, outerGlow);

    // Glass Circle (Frosted effect)
    final Paint glassPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size / 2, size / 2), 18, glassPaint);
    
    final Paint borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(Offset(size / 2, size / 2), 18, borderPaint);

    // Red A/B Text with inner neon glow
    TextPainter painter = TextPainter(textDirection: TextDirection.ltr);
    painter.text = TextSpan(
      text: label,
      style: TextStyle(
        fontSize: 22.0,
        color: color, // Bright Red
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            color: color.withValues(alpha: 0.8),
            blurRadius: 10.0 * intensity,
          ),
        ],
      ),
    );
    painter.layout();
    painter.paint(canvas, Offset(size / 2 - painter.width / 2, size / 2 - painter.height / 2));

    final ui.Image image = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition();
      _userLocation = LatLng(position.latitude, position.longitude);
      
      // Update mock service if applicable
      if (_transitService is MockTransitService) {
        (_transitService as MockTransitService).setReferenceLocation(_userLocation!);
      }
      
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _userLocation!,
            zoom: 15.5,
            tilt: 45.0,
            bearing: 0.0,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error obteniendo ubicación: $e');
    }
  }

  Future<BitmapDescriptor> _createNeonBusMarker(String label, {bool isHighlighted = false}) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    
    // Clean MOQSA droplet pin marker without any text labels
    const double size = 64.0;
    final double centerX = size / 2;
    final double radius = isHighlighted ? 15.0 : 12.0;
    // Mathematically anchor the tip at exactly y = 54.0
    final double centerY = 54.0 - radius * 1.5;
    
    final Color moqsaGreen = _getLineInstitutionalColor(label);
    
    // 1. Draw Droplet Shape Path pointing down
    final Path dropletPath = Path();
    dropletPath.moveTo(centerX, centerY + radius * 1.5); // pointed tip
    
    // Left curve to droplet circle edge
    dropletPath.cubicTo(
      centerX - radius * 1.25, centerY + radius * 0.8,
      centerX - radius, centerY + radius * 0.35,
      centerX - radius, centerY
    );
    // Upper arc
    dropletPath.arcTo(
      Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
      pi, pi, false
    );
    // Right curve back to pointed tip
    dropletPath.cubicTo(
      centerX + radius, centerY + radius * 0.35,
      centerX + radius * 1.25, centerY + radius * 0.8,
      centerX, centerY + radius * 1.5
    );
    dropletPath.close();

    // 2. Fill MOQSA Green and draw white border
    final Paint dropletPaint = Paint()
      ..color = moqsaGreen
      ..style = PaintingStyle.fill;
    canvas.drawPath(dropletPath, dropletPaint);

    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(dropletPath, borderPaint);

    // 3. Draw White Front-Facing Bus Icon inside the droplet circle
    final Paint whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final double busW = radius * 0.9;
    final double busH = radius * 1.0;
    final double busL = centerX - busW / 2;
    final double busT = centerY - busH / 2 - 1.0;

    // Main bus body box
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(busL, busT, busW, busH),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
        bottomLeft: const Radius.circular(1.5),
        bottomRight: const Radius.circular(1.5),
      ),
      whitePaint,
    );

    // Windshield (Cutout)
    final Paint cutPaint = Paint()
      ..color = moqsaGreen
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(busL + 1.0, busT + 1.5, busW - 2, busH * 0.35),
        const Radius.circular(0.8),
      ),
      cutPaint,
    );

    // Headlights (Cutout dots)
    canvas.drawCircle(Offset(busL + 2.0, busT + busH - 2.5), 0.8, cutPaint);
    canvas.drawCircle(Offset(busL + busW - 2.0, busT + busH - 2.5), 0.8, cutPaint);

    // Wheels
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(busL + 1.0, busT + busH, 2.0, 1.0),
        const Radius.circular(0.4),
      ),
      whitePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(busL + busW - 3.0, busT + busH, 2.0, 1.0),
        const Radius.circular(0.4),
      ),
      whitePaint,
    );

    // 4. Return PNG bytes
    final ui.Image image = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  void _showPremiumDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, color: Colors.cyanAccent, size: 50),
                  const SizedBox(height: 16),
                  const Text(
                    '¡Llegaste al límite gratuito!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Actualizá a Arribo PRO para guardar favoritos ilimitados en todo Buenos Aires.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  NeoButton(
                    onTap: () => Navigator.pop(context),
                    borderRadius: 15,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    child: const Text('Saber más', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveCurrentStop() async {
    final stop = FavoriteStop(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Parada ${DateTime.now().second}',
    );
    
    final success = await _databaseService.addFavorite(stop);
    
    if (!mounted) return;
    if (!success) {
      HapticFeedback.heavyImpact();
      _showPremiumDialog();
    } else {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parada guardada en favoritos.')));
    }
  }

  void _onSearch(String val) {
    final String cleanVal = val.trim();
    String? matchedLine;
    if (cleanVal.toLowerCase().contains('159')) {
      matchedLine = '159';
    } else if (cleanVal.toLowerCase().contains('98')) {
      matchedLine = '98';
    }

    setState(() {
      _searchFilter = val;
      if (cleanVal.isNotEmpty) {
        _hasActiveSearch = true;
        if (matchedLine != null) {
          if (_activeSearchedLine != matchedLine) {
            _activeSearchedLine = matchedLine;
            _selectedRamales.clear();
            _polylines = {};
            _terminalMarkers = {};
          }
          _showBranchSelector = true;
        } else {
          _activeSearchedLine = null;
          _selectedRamales.clear();
          _showBranchSelector = false;
        }
      } else {
        _hasActiveSearch = false;
        _activeSearchedLine = null;
        _selectedRamales.clear();
        _showBranchSelector = false;
        _polylines = {};
        _terminalMarkers = {};
      }
    });

    _updateMarkers();
    
    if (cleanVal.isNotEmpty && _hasActiveSearch) {
      _showRouteForLine(val);

      final buses = _allVehicles.where((v) {
        final lineName = v.line.toLowerCase();
        if (matchedLine != null) {
          return lineName.contains(matchedLine.toLowerCase());
        }
        return lineName.contains(cleanVal.toLowerCase());
      }).toList();

      if (buses.isNotEmpty) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: buses.first.position,
              zoom: 13.0, // Global overview zoom
              tilt: 45.0,
              bearing: 0.0,
            ),
          ),
        );
      } else {
        // Center of the 35km global route path
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            const CameraPosition(
              target: LatLng(-34.7000, -58.3000), // Midpoint of Once-Berazategui path
              zoom: 11.5,
              tilt: 40.0,
              bearing: 0.0,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              'Error de Mapa: $_errorMessage',
              style: const TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_userLocation == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.cyanAccent),
              SizedBox(height: 20),
              Text('Cargando...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            child: GoogleMap(
              initialCameraPosition: _initialPosition,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              myLocationEnabled: true,
              zoomGesturesEnabled: true,
              scrollGesturesEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
              style: MapConstants.moqsaCleanStyle,
              markers: {..._markers, ..._terminalMarkers},
              polylines: _polylines,
              onMapCreated: (GoogleMapController controller) {
                try {
                  _mapController = controller;
                  debugPrint("Map Created Successfully");
                } catch (e) {
                  setState(() => _errorMessage = "onMapCreated: $e");
                }
              },
            ),
          ),

          // Green Top Bar (MOQSA style with dynamic/fluid colors)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 10,
                bottom: 12,
                left: 20,
                right: 20,
              ),
              decoration: BoxDecoration(
                color: _getHeaderColor(), // Dynamic institutional color
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.directions_bus, 
                    color: _getHeaderTextColor(), 
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Mapa próximos arribos',
                      style: TextStyle(
                        color: _getHeaderTextColor(),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<TransitConnectionState>(
                    valueListenable: DebugConfig.connectionState,
                    builder: (context, state, child) {
                      IconData iconData;
                      Color iconColor;
                      String tooltip;
                      
                      switch (state) {
                        case TransitConnectionState.online:
                          iconData = Icons.wifi;
                          iconColor = const Color(0xFF00E676); // Green
                          tooltip = 'Tiempo real activo';
                          break;
                        case TransitConnectionState.cached:
                          iconData = Icons.wifi_protected_setup;
                          iconColor = const Color(0xFFFFD700); // Yellow/Gold
                          tooltip = 'Caché cargada (Reconectando)';
                          break;
                        case TransitConnectionState.offline:
                          iconData = Icons.signal_wifi_off;
                          iconColor = const Color(0xFFE11D48); // Red
                          tooltip = 'Servidores caídos (Offline)';
                          break;
                      }
                      
                      return Tooltip(
                        message: tooltip,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            iconData,
                            color: iconColor,
                            size: 20,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Proximity Alert Banner
          if (_showProximityAlert)
            Positioned(
              top: 185,
              left: 20,
              right: 20,
              child: GlassCard(
                borderRadius: 15,
                opacity: 0.8,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active, color: Colors.cyanAccent),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '¡Tu colectivo está cerca! Preparate.',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                      onPressed: () => setState(() => _showProximityAlert = false),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            top: 115,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: const Color(0xFF39B54A), width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: DebugConfig.isLoading,
                    builder: (context, loading, _) {
                      if (!loading) return const Icon(Icons.search, color: Color(0xFF555555));
                      return const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF39B54A)),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearch,
                      style: const TextStyle(color: Colors.black),
                      decoration: const InputDecoration(
                        hintText: 'Buscar línea en Buenos Aires...',
                        hintStyle: TextStyle(color: Color(0xFF777777)),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.star_border, color: Color(0xFF39B54A)),
                    onPressed: _saveCurrentStop,
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 15,
            left: 20,
            right: 100,
            child: ValueListenableBuilder<String>(
              valueListenable: DebugConfig.transitStatus,
              builder: (context, status, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: Text(
                    'STATUS: $status',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: (status.contains('Offline') || status.contains('Error') || status.contains('Fallido')) 
                          ? Colors.redAccent 
                          : Colors.cyanAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              },
            ),
          ),

          if (_showBranchSelector && _activeSearchedLine != null && _lineRamales.containsKey(_activeSearchedLine)) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showBranchSelector = false;
                  });
                },
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ),
            ),
            Positioned(
              bottom: 110,
              left: 20,
              right: 20,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: 1.0,
                child: GlassCard(
                  borderRadius: 24,
                  opacity: 0.2,
                  blur: 10.0,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.alt_route, color: Color(0xFF39B54A), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ramales de Línea $_activeSearchedLine',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_selectedRamales.length} seleccionados',
                            style: const TextStyle(
                              color: Color(0xFF39B54A),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setState(() {
                                _showBranchSelector = false;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: _lineRamales[_activeSearchedLine]!.map((ramal) {
                              final isSelected = _selectedRamales.contains(ramal);
                              return Theme(
                                data: ThemeData(
                                  unselectedWidgetColor: Colors.white30,
                                ),
                                child: CheckboxListTile(
                                  value: isSelected,
                                  title: Text(
                                    ramal,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white70,
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    ),
                                  ),
                                  activeColor: const Color(0xFF39B54A),
                                  checkColor: Colors.white,
                                  dense: true,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  contentPadding: EdgeInsets.zero,
                                  onChanged: (bool? checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedRamales.add(ramal);
                                      } else {
                                        _selectedRamales.remove(ramal);
                                      }
                                    });
                                    _showRouteForLine(_searchFilter);
                                    _updateMarkers();
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF39B54A),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            setState(() {
                              _showBranchSelector = false;
                            });
                          },
                          child: const Text(
                            'Confirmar Selección',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          Positioned(
            bottom: 40,
            right: 20,
            child: NeoButton(
              onTap: _determinePosition,
              borderRadius: 30,
              padding: const EdgeInsets.all(16),
              child: const Icon(Icons.my_location, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}
