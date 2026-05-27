import 'package:flutter/material.dart';

import '../../models/app_models.dart';

class RoomButtonUiConfig {
  const RoomButtonUiConfig({
    required this.room,
    required this.assetPath,
    required this.mockIcon,
  });

  final RoomId room;
  final String assetPath;
  final IconData mockIcon;
}

const Map<RoomId, RoomButtonUiConfig> roomButtonUiConfigMap =
    <RoomId, RoomButtonUiConfig>{
      RoomId.bedroom: RoomButtonUiConfig(
        room: RoomId.bedroom,
        assetPath: 'assets/ui/menu_lamp.png',
        mockIcon: Icons.bed_rounded,
      ),
      RoomId.wardrobe: RoomButtonUiConfig(
        room: RoomId.wardrobe,
        assetPath: 'assets/ui/menu_wardrobe.png',
        mockIcon: Icons.checkroom_rounded,
      ),
      RoomId.baloon: RoomButtonUiConfig(
        room: RoomId.baloon,
        assetPath: 'assets/ui/menu_baloon.png',
        mockIcon: Icons.table_restaurant_rounded,
      ),
      RoomId.rocket: RoomButtonUiConfig(
        room: RoomId.rocket,
        assetPath: 'assets/ui/menu_rocket.png',
        mockIcon: Icons.rocket_launch_rounded,
      ),
    };
