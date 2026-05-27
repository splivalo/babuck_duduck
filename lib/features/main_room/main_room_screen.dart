import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../controllers/sprite_controller.dart';
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

class _RoomInitializationState {
  int token = 0;
  bool assetsReady = false;
  bool characterAttached = false;
  bool idleStarted = false;

  void begin({required bool hasCharacterAssets}) {
    token += 1;
    assetsReady = !hasCharacterAssets;
    characterAttached = !hasCharacterAssets;
    idleStarted = false;
  }
}

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
  late bool _characterAssetsReady;
  late bool _characterFrameReady;
  int _buildCount = 0;
  int _visibleAssetsRequestToken = 0;
  bool _roomTransitionSelectionLocked = false;
  bool _roomTransitionInProgress = false;
  bool _roomTransitionOverlayVisible = false;
  bool _awaitingTransitionCharacterFrame = false;
  bool _roomTransitionOverlayFullyVisible = false;
  bool _roomTransitionDismissPending = false;
  String? _transitionOverlayBackgroundAsset;
  Timer? _roomTransitionFailSafeTimer;
  final _RoomInitializationState _roomInitialization =
      _RoomInitializationState();

  @override
  void initState() {
    super.initState();
    renderLog(
      'MainRoomScreen',
      'MOUNT initialAssetsReady=${widget.initialAssetsReady}',
    );
    _bindSpriteController(widget.characterManager.spriteController);
    _beginRoomInitialization(
      widget.roomManager.currentRoom,
      source: 'MainRoomScreen.initState',
    );
    _characterAssetsReady =
        widget.initialAssetsReady ||
        !roomHasReadyCharacterAssets(widget.roomManager.currentRoom);
    _characterFrameReady =
        _characterAssetsReady ||
        !roomHasReadyCharacterAssets(widget.roomManager.currentRoom);
    if (_characterAssetsReady) {
      _markRoomAssetsReady(
        room: widget.roomManager.currentRoom,
        token: _roomInitialization.token,
        source: 'MainRoomScreen.initState.assetsReady',
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _preloadVisibleAssets();
      });
    }
  }

  @override
  void didUpdateWidget(covariant MainRoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.characterManager != widget.characterManager) {
      _unbindSpriteController(oldWidget.characterManager.spriteController);
      _bindSpriteController(widget.characterManager.spriteController);
      return;
    }

    if (oldWidget.assetLoader != widget.assetLoader) {
      widget.characterManager.spriteController.bindAssetLoader(
        widget.assetLoader,
      );
    }
  }

  void _bindSpriteController(SpriteController spriteController) {
    spriteController.bindAssetLoader(widget.assetLoader);
    spriteController.addTextureFrameResolvedListener(
      _handleTransitionCharacterFrameResolved,
    );
  }

  void _unbindSpriteController(SpriteController spriteController) {
    spriteController.removeTextureFrameResolvedListener(
      _handleTransitionCharacterFrameResolved,
    );
  }

  void _beginRoomInitialization(RoomId room, {required String source}) {
    _roomTransitionFailSafeTimer?.cancel();
    _roomTransitionFailSafeTimer = null;
    _roomInitialization.begin(
      hasCharacterAssets: roomHasReadyCharacterAssets(room),
    );
    widget.characterManager.beginRoomInitialization(room, source: source);
  }

  void _scheduleRoomTransitionFailSafe({
    required RoomId room,
    required int token,
  }) {
    _roomTransitionFailSafeTimer?.cancel();
    _roomTransitionFailSafeTimer = Timer(
      const Duration(milliseconds: 1200),
      () {
        if (!mounted || !_isActiveRoomInitialization(token, room)) {
          return;
        }

        if (!_roomTransitionInProgress || !_awaitingTransitionCharacterFrame) {
          return;
        }

        if (!_characterFrameReady) {
          setState(() {
            _characterFrameReady = true;
          });
        }

        if (!_characterAssetsReady) {
          setState(() {
            _characterAssetsReady = true;
          });
        }

        if (!_roomInitialization.assetsReady) {
          _markRoomAssetsReady(
            room: room,
            token: token,
            source: 'MainRoomScreen._roomTransitionFailSafeTimer',
          );
        }

        _maybeStartRoomInitializationIdle(
          room: room,
          token: token,
          source: 'MainRoomScreen._roomTransitionFailSafeTimer',
        );

        if (!_roomInitialization.characterAttached) {
          _roomInitialization.characterAttached = true;
          widget.characterManager.markCharacterAttached(
            source: 'MainRoomScreen._roomTransitionFailSafeTimer',
          );
        }

        _awaitingTransitionCharacterFrame = false;
        _dismissRoomTransitionOverlay();
      },
    );
  }

  bool _isActiveRoomInitialization(int token, RoomId room) {
    return mounted &&
        _roomInitialization.token == token &&
        widget.roomManager.currentRoom == room;
  }

  void _markRoomAssetsReady({
    required RoomId room,
    required int token,
    required String source,
  }) {
    if (!_isActiveRoomInitialization(token, room) ||
        _roomInitialization.assetsReady) {
      return;
    }

    _roomInitialization.assetsReady = true;
    widget.characterManager.markRoomAssetsReady(source: source);
    _queueRoomInitializationIdleStart(room: room, token: token, source: source);
  }

  void _queueRoomInitializationIdleStart({
    required RoomId room,
    required int token,
    required String source,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeStartRoomInitializationIdle(
        room: room,
        token: token,
        source: source,
      );
    });
  }

  void _maybeStartRoomInitializationIdle({
    required RoomId room,
    required int token,
    required String source,
  }) {
    if (!_isActiveRoomInitialization(token, room) ||
        _roomInitialization.idleStarted ||
        !_roomInitialization.assetsReady) {
      return;
    }

    _roomInitialization.idleStarted = true;
    widget.characterManager.requestIdleStart(
      source: source,
      forceRestart: true,
      allowWhileInitializing: true,
    );
  }

  void _maybeCompleteRoomInitialization({required String source}) {
    final room = widget.roomManager.currentRoom;
    if (!widget.characterManager.roomIsInitializing ||
        !_roomInitialization.assetsReady ||
        !_roomInitialization.idleStarted ||
        (_roomTransitionInProgress ||
            _roomTransitionOverlayVisible ||
            _awaitingTransitionCharacterFrame) ||
        (roomHasReadyCharacterAssets(room) &&
            !_roomInitialization.characterAttached)) {
      return;
    }

    widget.characterManager.completeRoomInitialization(source: source);
  }

  Future<void> _preloadVisibleAssets() async {
    if (!mounted) {
      return;
    }

    final requestToken = ++_visibleAssetsRequestToken;
    final room = widget.roomManager.currentRoom;
    final roomInitializationToken = _roomInitialization.token;
    final character = widget.characterManager.characterForRoom(room);
    final shouldPreloadCharacter = roomHasReadyCharacterAssets(room);

    if (shouldPreloadCharacter && _characterFrameReady) {
      _characterFrameReady = false;
    }

    if (shouldPreloadCharacter &&
        _characterAssetsReady &&
        _isActiveVisibleAssetsRequest(requestToken, room)) {
      setState(() {
        _characterAssetsReady = false;
      });
    }

    final currentRoomConfig = roomConfigMap[room]!;
    final roomIndex = roomNavigationOrder.indexOf(room);
    final nextRoom =
        roomNavigationOrder[(roomIndex + 1) % roomNavigationOrder.length];
    final previousRoom =
        roomNavigationOrder[(roomIndex - 1 + roomNavigationOrder.length) %
            roomNavigationOrder.length];
    final extraBackgroundAssets = currentRoomConfig.supportsMoodToggle
        ? <String>[
            currentRoomConfig.backgroundDayAsset,
            currentRoomConfig.backgroundNightAsset!,
          ]
        : const <String>[];

    final backgroundPreload = widget.assetLoader.preloadRoomScene(
      context: context,
      currentBackgroundAsset: _backgroundAssetForRoom(room),
      nextBackgroundAsset: roomConfigMap[nextRoom]!.backgroundAsset(
        BedroomMood.day,
      ),
      previousBackgroundAsset: roomConfigMap[previousRoom]!.backgroundAsset(
        BedroomMood.day,
      ),
      extraBackgroundAssets: extraBackgroundAssets,
    );

    if (shouldPreloadCharacter) {
      await widget.assetLoader.preloadCharacterScene(character, context);
      if (!_isActiveVisibleAssetsRequest(requestToken, room)) {
        return;
      }

      unawaited(widget.soundManager.preloadForCharacter(room, character.id));
      if (!_isActiveVisibleAssetsRequest(requestToken, room)) {
        return;
      }

      if (!_characterAssetsReady) {
        setState(() {
          _characterAssetsReady = true;
        });
      }

      _markRoomAssetsReady(
        room: room,
        token: roomInitializationToken,
        source: 'MainRoomScreen._preloadVisibleAssets.characterReady',
      );
    }

    await backgroundPreload;
    if (!_isActiveVisibleAssetsRequest(requestToken, room)) {
      return;
    }

    if (!shouldPreloadCharacter) {
      _markRoomAssetsReady(
        room: room,
        token: roomInitializationToken,
        source: 'MainRoomScreen._preloadVisibleAssets.backgroundReady',
      );
    }
  }

  bool _isActiveVisibleAssetsRequest(int requestToken, RoomId room) {
    return mounted &&
        _visibleAssetsRequestToken == requestToken &&
        widget.roomManager.currentRoom == room;
  }

  Future<bool> _preloadAssetsForRoom(RoomId room) async {
    final roomConfig = roomConfigMap[room]!;
    final targetBackgroundAsset = _backgroundAssetForRoom(room);
    final roomIndex = roomNavigationOrder.indexOf(room);
    final nextRoom =
        roomNavigationOrder[(roomIndex + 1) % roomNavigationOrder.length];
    final previousRoom =
        roomNavigationOrder[(roomIndex - 1 + roomNavigationOrder.length) %
            roomNavigationOrder.length];
    final extraBackgroundAssets = roomConfig.supportsMoodToggle
        ? <String>[
            roomConfig.backgroundDayAsset,
            roomConfig.backgroundNightAsset!,
          ]
        : const <String>[];

    final backgroundPreload = widget.assetLoader.preloadRoomScene(
      context: context,
      currentBackgroundAsset: targetBackgroundAsset,
      nextBackgroundAsset: roomConfigMap[nextRoom]!.backgroundAsset(
        BedroomMood.day,
      ),
      previousBackgroundAsset: roomConfigMap[previousRoom]!.backgroundAsset(
        BedroomMood.day,
      ),
      extraBackgroundAssets: extraBackgroundAssets,
    );

    if (!roomHasReadyCharacterAssets(room)) {
      await backgroundPreload;
      if (!mounted) {
        return false;
      }

      if (_transitionOverlayBackgroundAsset != targetBackgroundAsset) {
        setState(() {
          _transitionOverlayBackgroundAsset = targetBackgroundAsset;
        });
      }

      return true;
    }

    unawaited(
      widget.soundManager.preloadForCharacter(room, roomConfig.character),
    );

    await backgroundPreload;
    if (!mounted) {
      return false;
    }

    if (_transitionOverlayBackgroundAsset != targetBackgroundAsset) {
      setState(() {
        _transitionOverlayBackgroundAsset = targetBackgroundAsset;
      });
    }

    return true;
  }

  Future<void> _handleRoomSelected(RoomId room) async {
    if (_roomTransitionSelectionLocked ||
        widget.roomManager.currentRoom == room) {
      return;
    }

    final shouldWaitForCharacterFrame = roomHasReadyCharacterAssets(room);

    setState(() {
      _roomTransitionSelectionLocked = true;
      _roomTransitionInProgress = true;
      _roomTransitionOverlayVisible = true;
      _characterAssetsReady = !shouldWaitForCharacterFrame;
      _characterFrameReady = !shouldWaitForCharacterFrame;
      _awaitingTransitionCharacterFrame = shouldWaitForCharacterFrame;
      _roomTransitionOverlayFullyVisible = false;
      _roomTransitionDismissPending = false;
      _transitionOverlayBackgroundAsset = _backgroundAssetForRoom(
        widget.roomManager.currentRoom,
      );
    });

    _visibleAssetsRequestToken += 1;
    unawaited(widget.soundManager.stopAllRoomAudio());
    widget.roomManager.switchRoom(room);
    _beginRoomInitialization(
      room,
      source: 'MainRoomScreen._handleRoomSelected',
    );

    if (shouldWaitForCharacterFrame) {
      final roomInitializationToken = _roomInitialization.token;
      _scheduleRoomTransitionFailSafe(
        room: room,
        token: roomInitializationToken,
      );

      final targetCharacter = widget.characterManager.characterForRoom(room);
      unawaited(
        () async {
          await widget.assetLoader.prepareCharacterPlayback(targetCharacter);
          if (!mounted ||
              !_isActiveRoomInitialization(roomInitializationToken, room)) {
            return;
          }

          if (!_characterAssetsReady) {
            setState(() {
              _characterAssetsReady = true;
            });
          }

          _markRoomAssetsReady(
            room: room,
            token: roomInitializationToken,
            source: 'MainRoomScreen._handleRoomSelected.characterReady',
          );

          unawaited(
            widget.assetLoader.loadTextureFrame(targetCharacter.idleBlink, 0),
          );
        }().catchError((_) {}),
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _roomTransitionSelectionLocked = false;
    });

    if (!shouldWaitForCharacterFrame) {
      _dismissRoomTransitionOverlay();
    }

    unawaited(_finishRoomSelection(room));
  }

  Future<void> _finishRoomSelection(RoomId room) async {
    var roomReady = !roomHasReadyCharacterAssets(room);
    try {
      roomReady = await _preloadAssetsForRoom(room);
    } catch (_) {
      roomReady = !roomHasReadyCharacterAssets(room);
    }

    if (!mounted || widget.roomManager.currentRoom != room) {
      return;
    }

    if (_characterAssetsReady != roomReady) {
      setState(() {
        _characterAssetsReady = roomReady;
      });
    }

    if (roomReady) {
      _markRoomAssetsReady(
        room: room,
        token: _roomInitialization.token,
        source: 'MainRoomScreen._finishRoomSelection.roomReady',
      );
    }

    if (!roomReady) {
      unawaited(_preloadVisibleAssets());
      return;
    }
  }

  void _handleTransitionCharacterFrameResolved(int frameIndex) {
    if (!_characterFrameReady) {
      setState(() {
        _characterFrameReady = true;
      });
    }

    renderLog(
      'MainRoomScreen',
      'TEXTURE_BIND frameIndex=$frameIndex '
          '_characterAssetsReady=$_characterAssetsReady '
          '_characterFrameReady=$_characterFrameReady '
          '_roomTransitionInProgress=$_roomTransitionInProgress',
    );

    if (!_roomInitialization.characterAttached) {
      final shouldReplayRoomEntryBlink =
          _roomTransitionInProgress ||
          _awaitingTransitionCharacterFrame ||
          _roomTransitionOverlayVisible;
      final isFreshBlinkFrameAlreadyVisible =
          widget.characterManager.sequenceController.clip?.name ==
              'idle_blink' &&
          frameIndex == 0;
      _roomInitialization.characterAttached = true;
      if (shouldReplayRoomEntryBlink && !isFreshBlinkFrameAlreadyVisible) {
        widget.characterManager.replayRoomEntryBlink(
          source: 'MainRoomScreen._handleTransitionCharacterFrameResolved',
        );
      }
      widget.characterManager.markCharacterAttached(
        source: 'MainRoomScreen._handleTransitionCharacterFrameResolved',
      );
      _maybeCompleteRoomInitialization(
        source: 'MainRoomScreen._handleTransitionCharacterFrameResolved',
      );
    }

    if (!_roomTransitionInProgress || !_awaitingTransitionCharacterFrame) {
      return;
    }

    if (frameIndex != 0) {
      return;
    }

    _roomTransitionFailSafeTimer?.cancel();
    _roomTransitionFailSafeTimer = null;
    _awaitingTransitionCharacterFrame = false;
    _dismissRoomTransitionOverlay();
  }

  void _dismissRoomTransitionOverlay() {
    if (!_roomTransitionInProgress && !_roomTransitionOverlayVisible) {
      return;
    }

    if (_roomTransitionOverlayVisible && !_roomTransitionOverlayFullyVisible) {
      _roomTransitionDismissPending = true;
      return;
    }

    setState(() {
      _roomTransitionOverlayVisible = false;
      _roomTransitionInProgress = false;
      _roomTransitionDismissPending = false;
    });

    _roomTransitionFailSafeTimer?.cancel();
    _roomTransitionFailSafeTimer = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _maybeCompleteRoomInitialization(
        source: 'MainRoomScreen._dismissRoomTransitionOverlay',
      );
    });
  }

  void _handleTransitionOverlayAnimationEnd() {
    if (_roomTransitionOverlayVisible) {
      _roomTransitionOverlayFullyVisible = true;
      if (_roomTransitionDismissPending) {
        _dismissRoomTransitionOverlay();
      }
      return;
    }

    if (_roomTransitionInProgress) {
      return;
    }

    if (_transitionOverlayBackgroundAsset == null) {
      return;
    }

    setState(() {
      _roomTransitionOverlayFullyVisible = false;
      _transitionOverlayBackgroundAsset = null;
    });

    _maybeCompleteRoomInitialization(
      source: 'MainRoomScreen._handleTransitionOverlayAnimationEnd',
    );
  }

  @override
  void dispose() {
    _roomTransitionFailSafeTimer?.cancel();
    _unbindSpriteController(widget.characterManager.spriteController);
    super.dispose();
  }

  String _backgroundAssetForRoom(RoomId room) {
    final roomConfig = roomConfigMap[room]!;
    return roomConfig.backgroundAsset(
      room == RoomId.bedroom ? widget.roomManager.bedroomMood : BedroomMood.day,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.roomManager,
        widget.characterManager,
      ]),
      builder: (context, _) {
        _buildCount += 1;
        renderLog(
          'MainRoomScreen',
          'BUILD #$_buildCount '
              '_characterAssetsReady=$_characterAssetsReady '
              '_characterFrameReady=$_characterFrameReady '
              'roomIsInitializing=${widget.characterManager.roomIsInitializing} '
              'textureFrame=${widget.characterManager.spriteController.textureFrame == null ? 'null' : 'non-null'} '
              'clip=${widget.characterManager.spriteController.clip?.name ?? 'null'}',
        );
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
                            final roomConfig =
                                roomConfigMap[widget.roomManager.currentRoom]!;
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
                                      Visibility(
                                        visible: roomHasReadyCharacterAssets(
                                          widget.roomManager.currentRoom,
                                        ),
                                        maintainState: true,
                                        maintainAnimation: true,
                                        maintainSize: true,
                                        child: SpriteSequencePlayer(
                                          key: const ValueKey<String>(
                                            'main-room-sprite-player',
                                          ),
                                          controller: widget
                                              .characterManager
                                              .spriteController,
                                          characterLabel: widget
                                              .characterManager
                                              .currentCharacter
                                              .label,
                                        ),
                                      ),
                                      if (roomHasReadyCharacterAssets(
                                        widget.roomManager.currentRoom,
                                      ))
                                        IgnorePointer(
                                          ignoring: !_characterAssetsReady,
                                          child: Opacity(
                                            opacity: _characterAssetsReady
                                                ? 1
                                                : 0,
                                            child: CharacterTouchZones(
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
                                          ),
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
              if (widget.roomManager.currentRoom == RoomId.bedroom)
                _BedroomLampTarget(
                  bedroomMood: widget.roomManager.bedroomMood,
                  onTap: () {
                    widget.roomManager.toggleBedroomMood();
                    _preloadVisibleAssets();
                  },
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 28, 14, 0),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: RoomNavigationBar(
                      currentRoom: widget.roomManager.currentRoom,
                      onRoomSelected: (room) {
                        unawaited(_handleRoomSelected(room));
                      },
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_roomTransitionOverlayVisible,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 360),
                    curve: Curves.easeInOutCubic,
                    opacity: _roomTransitionOverlayVisible ? 1 : 0,
                    onEnd: _handleTransitionOverlayAnimationEnd,
                    child: _transitionOverlayBackgroundAsset == null
                        ? const SizedBox.shrink()
                        : _RoomTransitionOverlay(
                            backgroundAsset: _transitionOverlayBackgroundAsset!,
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

class _RoomTransitionOverlay extends StatelessWidget {
  const _RoomTransitionOverlay({required this.backgroundAsset});

  final String backgroundAsset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutQuart,
          switchOutCurve: Curves.easeInOutCubic,
          child: SizedBox.expand(
            key: ValueKey<String>(backgroundAsset),
            child: Image.asset(
              backgroundAsset,
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) {
                return const ColoredBox(color: Color(0xFFE7DED4));
              },
            ),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.16),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: const LinearProgressIndicator(
                        minHeight: 14,
                        backgroundColor: Color(0x40FFFFFF),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF7DB7FF),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BedroomLampTarget extends StatelessWidget {
  const _BedroomLampTarget({required this.bedroomMood, required this.onTap});

  static const double _lampCenterX = 0.505;
  static const double _lampCenterY = 0.452;

  final BedroomMood bedroomMood;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sceneWidth = constraints.maxWidth;
          final sceneHeight = constraints.maxHeight;
          final tapTargetSize = (sceneWidth * 0.42).clamp(136.0, 184.0);
          final left = (sceneWidth * _lampCenterX) - (tapTargetSize / 2);
          final top = (sceneHeight * _lampCenterY) - (tapTargetSize / 2);

          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: left,
                top: top,
                child: GestureDetector(
                  key: const ValueKey<String>('bedroom-lamp-target'),
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
