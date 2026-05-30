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
                                        _NightTintedCharacter(
                                          grade: roomConfig.nightGrade,
                                          active:
                                              widget.roomManager.bedroomMood ==
                                              BedroomMood.night,
                                          child: SpriteSequencePlayer(
                                            key: ValueKey<RoomId>(currentRoom),
                                            controller: widget
                                                .characterManager
                                                .spriteController,
                                            characterLabel: widget
                                                .characterManager
                                                .currentCharacter
                                                .label,
                                          ),
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

/// Grades the character so it looks like it sits in the dark while the room is
/// in night mood, without touching the sprite artwork.
///
/// Rather than uniformly multiplying every pixel (which crushes bright eyes and
/// flattens shading), this remaps the sprite's tonal range with a per-channel
/// linear color matrix anchored at white: pure white maps to [grade.highlight]
/// and mid-grey maps to [grade.midtone]. Keeping the highlight white leaves the
/// brightest pixels (eyes / whites) untouched like the original, while a dark,
/// cool midtone dims and cools the body and crushes the shadows so the shading
/// still shows. Alpha is left untouched, so transparency is preserved.
///
/// [active] drives a smooth fade: the grade animates in/out by lerping the
/// highlight from white and the midtone from mid-grey (which together form the
/// identity / daylight matrix). A null [grade] disables the effect entirely.
class _NightTintedCharacter extends StatelessWidget {
  const _NightTintedCharacter({
    required this.grade,
    required this.active,
    required this.child,
  });

  final NightGrade? grade;
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final grade = this.grade;
    if (grade == null) {
      return child;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: active ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
      child: child,
      builder: (context, t, child) {
        if (t <= 0.0) {
          return child!;
        }
        final highlight = Color.lerp(
          const Color(0xFFFFFFFF),
          grade.highlight,
          t,
        )!;
        final midtone = Color.lerp(const Color(0xFF808080), grade.midtone, t)!;
        final saturation = 1.0 + (grade.saturation - 1.0) * t;
        return ColorFiltered(
          colorFilter: _nightColorMatrix(highlight, midtone, saturation),
          child: child,
        );
      },
    );
  }
}

/// Builds a color matrix that first desaturates the sprite toward its own
/// luminance by [saturation] (1.0 = full colour, 0.0 = grey), then applies a
/// per-channel night grade anchored at white: a fully bright input channel
/// (255) maps to [highlight] and a mid-grey input (128) maps to [midtone], with
/// the line extrapolated and clamped for the rest. Keeping [highlight] white
/// leaves bright pixels (eyes / whites) untouched. Alpha is left untouched.
///
/// The two stages compose into a single matrix: because the night grade is a
/// per-channel scale `d_c` plus offset `o_c`, the combined row is the
/// saturation row scaled by `d_c`, with `o_c` in the offset column. Channel
/// components are read as normalized doubles (0..1) via the modern `Color` API;
/// matrix inputs/outputs are on the 0..255 scale.
ColorFilter _nightColorMatrix(Color highlight, Color midtone, double saturation) {
  // Night grade: out = scale * in + offset through (255 -> highlight) and
  // (128 -> midtone), per channel.
  double scale(double hi, double mid) => (hi - mid) * 255.0 / (255.0 - 128.0);
  final dR = scale(highlight.r, midtone.r);
  final dG = scale(highlight.g, midtone.g);
  final dB = scale(highlight.b, midtone.b);
  final oR = midtone.r * 255.0 - dR * 128.0;
  final oG = midtone.g * 255.0 - dG * 128.0;
  final oB = midtone.b * 255.0 - dB * 128.0;

  // Saturation: blend each channel toward Rec. 709 luminance.
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final s = saturation;
  final inv = 1.0 - s;
  final sat = <double>[
    inv * lr + s, inv * lg, inv * lb, // R row
    inv * lr, inv * lg + s, inv * lb, // G row
    inv * lr, inv * lg, inv * lb + s, // B row
  ];

  return ColorFilter.matrix(<double>[
    dR * sat[0], dR * sat[1], dR * sat[2], 0, oR,
    dG * sat[3], dG * sat[4], dG * sat[5], 0, oG,
    dB * sat[6], dB * sat[7], dB * sat[8], 0, oB,
    0, 0, 0, 1, 0,
  ]);
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
