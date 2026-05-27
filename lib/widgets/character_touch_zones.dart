import 'package:flutter/material.dart';

import '../models/app_models.dart';

class CharacterTouchZones extends StatelessWidget {
  const CharacterTouchZones({
    super.key,
    required this.zones,
    required this.onZoneTap,
    this.showDebugOverlay = false,
  });

  final List<TouchZoneLayout> zones;
  final ValueChanged<TouchZone> onZoneTap;
  final bool showDebugOverlay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: zones.map((zone) {
            return Positioned(
              left: zone.left * constraints.maxWidth,
              top: zone.top * constraints.maxHeight,
              width: zone.width * constraints.maxWidth,
              height: zone.height * constraints.maxHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onZoneTap(zone.zone),
                child: DecoratedBox(
                  decoration: showDebugOverlay
                      ? BoxDecoration(
                          color: _zoneColor(zone.zone).withValues(alpha: 0.24),
                          border: Border.all(
                            color: _zoneColor(
                              zone.zone,
                            ).withValues(alpha: 0.92),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        )
                      : const BoxDecoration(),
                  child: showDebugOverlay
                      ? Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _zoneColor(
                                  zone.zone,
                                ).withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                child: Text(
                                  zone.zone.name.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.expand(),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  static Color _zoneColor(TouchZone zone) {
    return switch (zone) {
      TouchZone.head => const Color(0xFF3B82F6),
      TouchZone.belly => const Color(0xFFF59E0B),
      TouchZone.legs => const Color(0xFF10B981),
    };
  }
}
