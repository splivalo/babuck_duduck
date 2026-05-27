import 'package:flutter/foundation.dart';

import '../models/app_models.dart';

class RoomManager extends ChangeNotifier {
  static const List<RoomId> _navigationOrder = roomNavigationOrder;

  RoomId _currentRoom = RoomId.bedroom;
  BedroomMood _bedroomMood = BedroomMood.day;

  RoomId get currentRoom => _currentRoom;
  BedroomMood get bedroomMood => _bedroomMood;
  RoomConfig get currentRoomConfig => roomConfigMap[_currentRoom]!;
  CharacterId get currentRoomCharacter => currentRoomConfig.character;
  RoomId get nextRoom =>
      _navigationOrder[(_navigationOrder.indexOf(_currentRoom) + 1) %
          _navigationOrder.length];
  RoomId get previousRoom =>
      _navigationOrder[(_navigationOrder.indexOf(_currentRoom) -
              1 +
              _navigationOrder.length) %
          _navigationOrder.length];

  String get currentBackgroundAsset {
    return currentRoomConfig.backgroundAsset(_bedroomMood);
  }

  String get roomLabel {
    return currentRoomConfig.labelForMood(_bedroomMood);
  }

  void switchRoom(RoomId room) {
    if (_currentRoom == room) {
      return;
    }
    _currentRoom = room;
    notifyListeners();
  }

  void toggleBedroomMood() {
    if (_currentRoom != RoomId.bedroom) {
      return;
    }
    _bedroomMood = _bedroomMood == BedroomMood.day
        ? BedroomMood.night
        : BedroomMood.day;
    notifyListeners();
  }
}
