import 'package:flutter/material.dart';
import 'package:arribo/features/ui_components/glass_card.dart';
import 'package:arribo/features/ui_components/neo_button.dart';
import 'package:arribo/features/transit/domain/models/transit_vehicle.dart';

class VehicleDetailSheet extends StatefulWidget {
  final TransitVehicle vehicle;
  final Color lineColor;
  final bool isFollowing;
  final Function(bool) onFollowChanged;

  const VehicleDetailSheet({
    super.key,
    required this.vehicle,
    required this.lineColor,
    required this.isFollowing,
    required this.onFollowChanged,
  });

  @override
  State<VehicleDetailSheet> createState() => _VehicleDetailSheetState();
}

class _VehicleDetailSheetState extends State<VehicleDetailSheet> {
  bool _isExpanded = false;

  bool _isPeakHour() {
    final hour = DateTime.now().hour;
    return (hour >= 6 && hour < 9) || (hour >= 17 && hour < 20);
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 30,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle for BottomSheet
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            
            // Header: Line & Time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Línea ${widget.vehicle.line}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.lineColor,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Hacia: ${widget.vehicle.destination}',
                        style: const TextStyle(
                          color: Colors.white, // Blanco Puro de alto contraste
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (widget.vehicle.line.startsWith('98') && _isPeakHour())
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Row(
                            children: [
                              const Icon(Icons.group, color: Colors.orangeAccent, size: 14),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Ocupación estimada: ALTA',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.orangeAccent.withValues(alpha: 0.9),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        '8 min',
                        style: TextStyle(color: Colors.cyanAccent, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text('Llegada', style: TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Follow Button (Neumorphic)
            NeoButton(
              onTap: () => widget.onFollowChanged(!widget.isFollowing),
              borderRadius: 20,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.isFollowing ? Icons.gps_fixed : Icons.gps_not_fixed,
                    color: widget.isFollowing ? widget.lineColor : Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.isFollowing ? 'Siguiendo Colectivo...' : 'Seguir Colectivo',
                    style: TextStyle(
                      color: widget.isFollowing ? widget.lineColor : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Expandable Route Details
            InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isExpanded ? 'Ocultar recorrido' : 'Ver próximas paradas',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),

            if (_isExpanded) ...[
              const SizedBox(height: 16),
              _buildStopItem('Calle 14 y 151', '2 min', true),
              _buildStopItem('Av. Mitre y 14', '5 min', false),
              _buildStopItem('Estación Berazategui', '8 min', false),
            ],
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStopItem(String name, String time, bool isNext) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(
            isNext ? Icons.radio_button_checked : Icons.radio_button_off,
            color: isNext ? widget.lineColor : Colors.white24,
            size: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: isNext ? Colors.white : Colors.white54,
                fontWeight: isNext ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(time, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}
