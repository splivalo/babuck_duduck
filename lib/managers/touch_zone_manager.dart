import '../models/app_models.dart';

class TouchZoneManager {
  const TouchZoneManager();

  static final List<TouchZoneLayout> _babakZones = _verticalThirdZones(
    left: 0.22,
    top: 0.08,
    width: 0.56,
    height: 0.78,
  );

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

  static const double _zoneThird = 1 / 3;

  static List<TouchZoneLayout> _verticalThirdZones({
    required double left,
    required double top,
    required double width,
    required double height,
  }) => <TouchZoneLayout>[
    TouchZoneLayout(
      zone: TouchZone.head,
      left: left,
      top: top,
      width: width,
      height: height * _zoneThird,
    ),
    TouchZoneLayout(
      zone: TouchZone.belly,
      left: left,
      top: top + (height * _zoneThird),
      width: width,
      height: height * _zoneThird,
    ),
    TouchZoneLayout(
      zone: TouchZone.legs,
      left: left,
      top: top + (height * _zoneThird * 2),
      width: width,
      height: height * _zoneThird,
    ),
  ];

  List<TouchZoneLayout> zonesForCharacter(CharacterId characterId) {
    return switch (characterId) {
      CharacterId.babak => _babakZones,
      CharacterId.dudak => _dudakZones,
    };
  }
}
