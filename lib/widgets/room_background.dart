import 'package:flutter/material.dart';

import '../managers/room_manager.dart';
import '../models/app_models.dart';

class RoomBackground extends StatelessWidget {
  const RoomBackground({super.key, required this.roomManager});

  final RoomManager roomManager;

  @override
  Widget build(BuildContext context) {
    final isNight = roomManager.bedroomMood == BedroomMood.night;
    final backgroundAsset = roomManager.currentBackgroundAsset;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 620),
      switchInCurve: Curves.easeOutQuart,
      switchOutCurve: Curves.easeInOutCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: SizedBox.expand(
        key: ValueKey<String>(backgroundAsset),
        child: Image.asset(
          backgroundAsset,
          fit: BoxFit.cover,
          alignment: Alignment.bottomCenter,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) {
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isNight
                      ? const <Color>[Color(0xFF16213E), Color(0xFF0F3460)]
                      : const <Color>[Color(0xFFB8E1FF), Color(0xFFFFF0C2)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Center(
                child: Text(
                  roomManager.roomLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.displaySmall?.copyWith(color: Colors.white),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
