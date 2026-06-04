import '../models/app_models.dart';

class TouchZoneManager {
  const TouchZoneManager();

  static const List<TouchZoneLayout> _babakZones = <TouchZoneLayout>[
    TouchZoneLayout(
      zone: TouchZone.head,
      left: 0.17,
      top: 0.37,
      width: 0.66,
      height: 0.24,
    ),
    TouchZoneLayout(
      zone: TouchZone.belly,
      left: 0.17,
      top: 0.61,
      width: 0.66,
      height: 0.22,
    ),
    TouchZoneLayout(
      zone: TouchZone.legs,
      left: 0.20,
      top: 0.83,
      width: 0.60,
      height: 0.14,
    ),
  ];

  static const List<TouchZoneLayout> _dudakZones = <TouchZoneLayout>[
    TouchZoneLayout(
      zone: TouchZone.head,
      left: 0.16,
      top: 0.12,
      width: 0.68,
      height: 0.35,
    ),
    TouchZoneLayout(
      zone: TouchZone.belly,
      left: 0.16,
      top: 0.47,
      width: 0.68,
      height: 0.31,
    ),
    TouchZoneLayout(
      zone: TouchZone.legs,
      left: 0.16,
      top: 0.78,
      width: 0.68,
      height: 0.18,
    ),
  ];


  List<TouchZoneLayout> zonesForCharacter(CharacterId characterId) {
    return switch (characterId) {
      CharacterId.babak => _babakZones,
      CharacterId.dudak => _dudakZones,
    };
  }
}
