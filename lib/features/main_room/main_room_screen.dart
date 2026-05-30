import 'dart:async';

import 'package:flutter/material.dart';

import '../../managers/character_manager.dart';
import '../../managers/room_manager.dart';
import '../../managers/touch_zone_manager.dart';
import '../../models/app_models.dart';
import '../../services/asset_loader.dart';
import '../../services/sound_manager.dart';
import '../../widgets/character_touch_zones.dart';
import '../../widgets/room_background.dart';
import '../../widgets/room_navigation_bar.dart';
import '../../widgets/sprite_sequence_player.dart';

import '../../main.dart' show renderLog;

class MainRoomScreen extends StatefulWidget {
  const MainRoomScreen({
    super.key,
    required this.roomManager,
    required this.characterManager,
    required this.assetLoader,
    required this.soundManager,
    this.initialAssetsReady = false,
  });

  final RoomManager roomManager;
  final CharacterManager characterManager;
  final AssetLoader assetLoader;
  final SoundManager soundManager;
  final bool initialAssetsReady;

  @override
  State<MainRoomScreen> createState() => _MainRoomScreenState();
}

class _MainRoomScreenState extends State<MainRoomScreen> {
  final TouchZoneManager _touchZoneManager = const TouchZoneManager();

  @override
  void initState() {
    super.initState();
    widget.characterManager.spriteController.bindAssetLoader(
      widget.assetLoader,
    );
    _enterRoom(
      widget.roomManager.currentRoom,
      source: 'MainRoomScreen.initState',
    );
  }

  @override
  void didUpdateWidget(covariant MainRoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetLoader != widget.assetLoader) {
      widget.characterManager.spriteController.bindAssetLoader(
        widget.assetLoader,
      );
    }
  }

  void _enterRoom(RoomId room, {required String source}) {
    renderLog('MainRoomScreen', 'ENTER_ROOM room=${room.name} source=$source');
    widget.characterManager.syncRoom(room);
    widget.characterManager.markRoomAssetsReady(source: source);
    widget.characterManager.markCharacterAttached(source: source);
    widget.characterManager.requestIdleStart(
      source: source,
      forceRestart: true,
      allowWhileInitializing: true,
    );
    widget.characterManager.completeRoomInitialization(source: source);
  }

  void _handleRoomSelected(RoomId room) {
    if (widget.roomManager.currentRoom == room) {
      return;
    }
    unawaited(widget.soundManager.stopAllRoomAudio());
    widget.roomManager.switchRoom(room);
    _enterRoom(room, source: 'MainRoomScreen._handleRoomSelected');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.roomManager,
        widget.characterManager,
      ]),
      builder: (context, _) {
        final currentRoom = widget.roomManager.currentRoom;
        final hasCharacter = roomHasReadyCharacterAssets(currentRoom);
        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              RoomBackground(roomManager: widget.roomManager),
              SafeArea(
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 16),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final roomConfig = roomConfigMap[currentRoom]!;
                            const baseStageWidth = 361.0;
                            const baseStageHeight = 522.0;
                            const stageAspectRatio =
                                baseStageWidth / baseStageHeight;

                            var stageWidth = constraints.maxWidth
                                .clamp(0.0, baseStageWidth)
                                .toDouble();
                            var stageHeight = stageWidth / stageAspectRatio;
                            final maxStageHeight = constraints.maxHeight * 0.94;

                            if (stageHeight > maxStageHeight) {
                              stageHeight = maxStageHeight;
                              stageWidth = stageHeight * stageAspectRatio;
                            }

                            stageWidth *= roomConfig.stageScale;
                            stageHeight *= roomConfig.stageScale;

                            final verticalLift =
                                stageHeight * roomConfig.stageLiftFactor;

                            return Align(
                              alignment: Alignment.bottomCenter,
                              child: Transform.translate(
                                offset: Offset(0, -verticalLift),
                                child: SizedBox(
                                  width: stageWidth,
                                  height: stageHeight,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    clipBehavior: Clip.none,
                                    children: <Widget>[
                                      if (hasCharacter)
                                        SpriteSequencePlayer(
                                          key: ValueKey<RoomId>(currentRoom),
                                          controller: widget
                                              .characterManager
                                              .spriteController,
                                          characterLabel: widget
                                              .characterManager
                                              .currentCharacter
                                              .label,
                                        ),
                                      if (hasCharacter)
                                        CharacterTouchZones(
                                          zones: _touchZoneManager
                                              .zonesForCharacter(
                                                widget
                                                    .roomManager
                                                    .currentRoomCharacter,
                                              ),
                                          onZoneTap: widget
                                              .characterManager
                                              .handleZoneTap,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (roomConfigMap[currentRoom]!.lamp != null)
                _RoomLampTarget(
                  room: currentRoom,
                  lamp: roomConfigMap[currentRoom]!.lamp!,
                  onTap: widget.roomManager.toggleBedroomMood,
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 28, 14, 0),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: RoomNavigationBar(
                      currentRoom: currentRoom,
                      onRoomSelectionRequested: (_) {},
                      onRoomSelected: _handleRoomSelected,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Invisible tap target placed over the lamp drawn into a room background.
///
/// The lamp is part of the background image, which is painted with
/// `BoxFit.cover` + bottom-center alignment. So the on-screen position of the
/// lamp depends on how the image is cropped on each phone. This widget
/// reproduces that exact cover crop and anchors the tap target to the lamp's
/// position *within the image*, so it stays on the lamp on every screen size.
class _RoomLampTarget extends StatelessWidget {
  const _RoomLampTarget({
    required this.room,
    required this.lamp,
    required this.onTap,
  });

  final RoomId room;
  final RoomLampConfig lamp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boxWidth = constraints.maxWidth;
          final boxHeight = constraints.maxHeight;

          // Reproduce BoxFit.cover: scale the image up until it covers the box,
          // keeping its aspect ratio. One axis fills the box, the other spills.
          var renderedWidth = boxWidth;
          var renderedHeight = boxWidth / lamp.imageAspectRatio;
          if (renderedHeight < boxHeight) {
            renderedHeight = boxHeight;
            renderedWidth = boxHeight * lamp.imageAspectRatio;
          }

          // Alignment.bottomCenter: horizontally centered, anchored to bottom.
          final offsetX = (boxWidth - renderedWidth) / 2;
          final offsetY = boxHeight - renderedHeight;

          final lampX = offsetX + lamp.imageFractionX * renderedWidth;
          final lampY = offsetY + lamp.imageFractionY * renderedHeight;

          final tapTargetSize = (boxWidth * lamp.tapSizeFactor).clamp(
            lamp.minTapSize,
            lamp.maxTapSize,
          );

          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: lampX - (tapTargetSize / 2),
                top: lampY - (tapTargetSize / 2),
                child: GestureDetector(
                  key: ValueKey<String>('${room.name}-lamp-target'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: SizedBox(
                    width: tapTargetSize,
                    height: tapTargetSize,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
