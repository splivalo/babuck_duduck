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
  static const Duration _roomCrossfadeInDuration = Duration(milliseconds: 240);
  static const Duration _roomCrossfadeOutDuration = Duration(milliseconds: 350);
  static const Duration _blurFadeOutDuration = Duration(milliseconds: 500);
  static const Duration _roomSwitchHoldDuration = Duration(milliseconds: 90);
  static const Duration _minimumBlurVisibilityDuration = Duration(
    milliseconds: 460,
  );
  static const Duration _characterFrameHardTimeout = Duration(seconds: 4);
  static const Duration _maxTransitionDuration = Duration(milliseconds: 3500);

  final TouchZoneManager _touchZoneManager = const TouchZoneManager();
  late bool _characterAssetsReady;
  late bool _characterFrameReady;
  int _buildCount = 0;
  int _visibleAssetsRequestToken = 0;
  int _roomSelectionWarmupToken = 0;
  int _transitionEpochCounter = 0;
  int _activeTransitionEpoch = 0;
  bool _roomTransitionInProgress = false;
  bool _roomTransitionOverlayVisible = false;
  bool _roomTransitionBlurVisible = false;
  bool _awaitingTransitionCharacterFrame = false;
  DateTime? _characterFrameWaitStartedAt;
  RoomId? _activeTransitionTargetRoom;
  RoomId? _activeTransitionSourceRoom;
  String? _transitionCrossfadeBackgroundAsset;
  String? _transitionBlurBackgroundAsset;
  DateTime? _transitionStartedAt;
  DateTime? _roomSwitchCommittedAt;
  RoomId? _queuedRoomSelection;
  RoomId? _pendingSelectionWarmupRoom;
  Future<bool>? _pendingSelectionWarmupFuture;
  Timer? _roomTransitionFailSafeTimer;
  Timer? _roomTransitionOverlayReleaseTimer;
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
    required int transitionEpoch,
  }) {
    _roomTransitionFailSafeTimer?.cancel();
    _roomTransitionFailSafeTimer = Timer(
      const Duration(milliseconds: 1200),
      () {
        if (!mounted ||
            !_isActiveRoomInitialization(token, room) ||
            !_isActiveTransition(transitionEpoch, room)) {
          return;
        }

        if (!_roomTransitionInProgress || !_awaitingTransitionCharacterFrame) {
          return;
        }

        if (!_characterAssetsReady) {
          setState(() {
            _characterAssetsReady = true;
          });
        }

        if (widget.characterManager.spriteController.textureFrame == null) {
          final waitStartedAt = _characterFrameWaitStartedAt;
          if (waitStartedAt != null &&
              DateTime.now().difference(waitStartedAt) >=
                  _characterFrameHardTimeout) {
            _abortTransitionAndRestoreSourceRoom(
              source: 'MainRoomScreen._roomTransitionFailSafe.timeout',
            );
            return;
          }

          _scheduleRoomTransitionFailSafe(
            room: room,
            token: token,
            transitionEpoch: transitionEpoch,
          );
          return;
        }

        if (!_characterFrameReady) {
          setState(() {
            _characterFrameReady = true;
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
        _characterFrameWaitStartedAt = null;
        _dismissRoomTransitionOverlay();
      },
    );
  }

  bool _isActiveRoomInitialization(int token, RoomId room) {
    return mounted &&
        _roomInitialization.token == token &&
        widget.roomManager.currentRoom == room;
  }

  bool _isActiveTransition(int transitionEpoch, RoomId room) {
    return mounted &&
        _activeTransitionEpoch == transitionEpoch &&
        _activeTransitionTargetRoom == room;
  }

  void _forceResetTransitionState() {
    renderLog(
      'MainRoomScreen',
      'TRANSITION_FORCE_RESET epoch=$_activeTransitionEpoch '
          'target=${_activeTransitionTargetRoom?.name ?? 'null'} '
          'source=${_activeTransitionSourceRoom?.name ?? 'null'}',
    );
    _roomTransitionOverlayReleaseTimer?.cancel();
    _roomTransitionOverlayReleaseTimer = null;
    _roomTransitionFailSafeTimer?.cancel();
    _roomTransitionFailSafeTimer = null;
    _roomSwitchCommittedAt = null;
    _transitionStartedAt = null;

    if (!mounted) {
      return;
    }

    setState(() {
      _roomTransitionInProgress = false;
      _roomTransitionOverlayVisible = false;
      _roomTransitionBlurVisible = false;
      _awaitingTransitionCharacterFrame = false;
      _characterFrameWaitStartedAt = null;
      _activeTransitionEpoch = 0;
      _activeTransitionTargetRoom = null;
      _activeTransitionSourceRoom = null;
    });

    Timer(_blurFadeOutDuration, () {
      if (!mounted || _roomTransitionInProgress) {
        return;
      }
      setState(() {
        _transitionCrossfadeBackgroundAsset = null;
        _transitionBlurBackgroundAsset = null;
      });
    });

    _drainQueuedRoomSelection();
  }

  void _abortTransitionAndRestoreSourceRoom({required String source}) {
    renderLog(
      'MainRoomScreen',
      'TRANSITION_ABORT source=$source '
          'target=${_activeTransitionTargetRoom?.name ?? 'null'} '
          'restoreTo=${_activeTransitionSourceRoom?.name ?? 'null'}',
    );
    final sourceRoom = _activeTransitionSourceRoom;
    if (sourceRoom != null && widget.roomManager.currentRoom != sourceRoom) {
      widget.roomManager.switchRoom(sourceRoom);
      _beginRoomInitialization(sourceRoom, source: source);
      unawaited(_preloadVisibleAssets());
    }
    _forceResetTransitionState();
  }

  void _drainQueuedRoomSelection() {
    final queuedRoom = _queuedRoomSelection;
    _queuedRoomSelection = null;
    if (queuedRoom == null || queuedRoom == widget.roomManager.currentRoom) {
      return;
    }
    renderLog(
      'MainRoomScreen',
      'QUEUE_DRAIN room=${queuedRoom.name}',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_handleRoomSelected(queuedRoom));
    });
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

  void _requestRoomSelectionWarmup(RoomId room) {
    if (_roomTransitionInProgress || widget.roomManager.currentRoom == room) {
      return;
    }

    final token = ++_roomSelectionWarmupToken;
    _pendingSelectionWarmupRoom = room;
    _pendingSelectionWarmupFuture = () async {
      try {
        if (roomHasReadyCharacterAssets(room)) {
          final targetCharacter = widget.characterManager.characterForRoom(
            room,
          );
          await widget.assetLoader.prepareCharacterPlayback(targetCharacter);
        }

        if (!mounted ||
            _roomSelectionWarmupToken != token ||
            _pendingSelectionWarmupRoom != room) {
          return !roomHasReadyCharacterAssets(room);
        }

        return _preloadAssetsForRoom(room);
      } catch (_) {
        return !roomHasReadyCharacterAssets(room);
      }
    }();
  }

  Future<bool>? _takeRoomSelectionWarmup(RoomId room) {
    if (_pendingSelectionWarmupRoom != room) {
      return null;
    }

    final warmupFuture = _pendingSelectionWarmupFuture;
    _pendingSelectionWarmupRoom = null;
    _pendingSelectionWarmupFuture = null;
    return warmupFuture;
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

      return true;
    }

    unawaited(
      widget.soundManager.preloadForCharacter(room, roomConfig.character),
    );

    await backgroundPreload;
    if (!mounted) {
      return false;
    }

    return true;
  }

  Future<void> _handleRoomSelected(RoomId room) async {
    if (_roomTransitionInProgress) {
      final startedAt = _transitionStartedAt;
      if (startedAt != null &&
          DateTime.now().difference(startedAt) >= _maxTransitionDuration) {
        _forceResetTransitionState();
      } else {
        _queuedRoomSelection = room;
        if (mounted && !_roomTransitionBlurVisible) {
          setState(() {
            _roomTransitionBlurVisible = true;
          });
        }
        return;
      }
    }

    if (widget.roomManager.currentRoom == room) {
      return;
    }

    final shouldWaitForCharacterFrame = roomHasReadyCharacterAssets(room);
    final sourceRoom = widget.roomManager.currentRoom;
    final transitionEpoch = ++_transitionEpochCounter;
    renderLog(
      'MainRoomScreen',
      'TRANSITION_START epoch=$transitionEpoch '
          '${sourceRoom.name}→${room.name} '
          'waitForCharacter=$shouldWaitForCharacterFrame',
    );
    var roomReady = !shouldWaitForCharacterFrame;
    CharacterDefinition? targetCharacter;

    setState(() {
      _roomTransitionInProgress = true;
      _roomTransitionOverlayVisible = false;
      _roomTransitionBlurVisible = true;
      _transitionBlurBackgroundAsset = _backgroundAssetForRoom(sourceRoom);
      _characterAssetsReady = !shouldWaitForCharacterFrame;
      _characterFrameReady = !shouldWaitForCharacterFrame;
      _awaitingTransitionCharacterFrame = shouldWaitForCharacterFrame;
      _characterFrameWaitStartedAt = shouldWaitForCharacterFrame
          ? DateTime.now()
          : null;
      _transitionStartedAt = DateTime.now();
      _activeTransitionEpoch = transitionEpoch;
      _activeTransitionTargetRoom = room;
      _activeTransitionSourceRoom = sourceRoom;
    });
    _roomTransitionOverlayReleaseTimer?.cancel();
    _roomTransitionOverlayReleaseTimer = null;
    _roomSwitchCommittedAt = null;

    _visibleAssetsRequestToken += 1;
    unawaited(widget.soundManager.stopAllRoomAudio());

    try {
      final warmupFuture = _takeRoomSelectionWarmup(room);
      roomReady = await (warmupFuture ?? _preloadAssetsForRoom(room));
    } catch (_) {
      roomReady = !shouldWaitForCharacterFrame;
    }

    if (shouldWaitForCharacterFrame) {
      targetCharacter = widget.characterManager.characterForRoom(room);
      try {
        await widget.assetLoader.prepareCharacterPlayback(targetCharacter);
      } catch (_) {
        // Best effort only; post-switch readiness gate is authoritative.
      }
    }

    if (!mounted) {
      return;
    }

    if (!_isActiveTransition(transitionEpoch, room)) {
      _forceResetTransitionState();
      return;
    }

    final nextRoomBackgroundAsset = _backgroundAssetForRoom(room);
    setState(() {
      _transitionBlurBackgroundAsset = nextRoomBackgroundAsset;
      _transitionCrossfadeBackgroundAsset = nextRoomBackgroundAsset;
      _roomTransitionOverlayVisible = true;
    });

    await Future<void>.delayed(_roomCrossfadeInDuration + _roomSwitchHoldDuration);
    if (!mounted || !_isActiveTransition(transitionEpoch, room)) {
      _forceResetTransitionState();
      return;
    }

    widget.roomManager.switchRoom(room);
    _roomSwitchCommittedAt = DateTime.now();
    _beginRoomInitialization(
      room,
      source: 'MainRoomScreen._handleRoomSelected',
    );

    if (shouldWaitForCharacterFrame) {
      final roomInitializationToken = _roomInitialization.token;
      _scheduleRoomTransitionFailSafe(
        room: room,
        token: roomInitializationToken,
        transitionEpoch: transitionEpoch,
      );

      if (!mounted ||
          !_isActiveRoomInitialization(roomInitializationToken, room) ||
          !_isActiveTransition(transitionEpoch, room)) {
        _forceResetTransitionState();
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

      if (targetCharacter != null) {
        widget.characterManager.spriteController.warmupFirstTexture(
          targetCharacter.idleBlink,
        );
      }

      try {
        await widget.characterManager.spriteController.firstTextureBound
            .timeout(_characterFrameHardTimeout);
      } catch (_) {}

      if (!mounted ||
          !_isActiveRoomInitialization(roomInitializationToken, room) ||
          !_isActiveTransition(transitionEpoch, room)) {
        _forceResetTransitionState();
        return;
      }

      if (widget.characterManager.spriteController.textureFrame == null) {
        _abortTransitionAndRestoreSourceRoom(
          source: 'MainRoomScreen._handleRoomSelected.frameMissing',
        );
        return;
      }

      if (!_characterFrameReady) {
        setState(() {
          _characterFrameReady = true;
        });
      }

      _awaitingTransitionCharacterFrame = false;
      _characterFrameWaitStartedAt = null;
      _roomTransitionBlurVisible = false;
      _dismissRoomTransitionOverlay();
    }

    if (!mounted) {
      return;
    }

    if (!_isActiveTransition(transitionEpoch, room)) {
      _forceResetTransitionState();
      return;
    }

    setState(() {
      if (!shouldWaitForCharacterFrame) {
        _roomTransitionBlurVisible = false;
      }
    });

    if (!shouldWaitForCharacterFrame) {
      _dismissRoomTransitionOverlay();
    }

    unawaited(_finishRoomSelection(room, preloadedRoomReady: roomReady));
  }

  Future<void> _finishRoomSelection(
    RoomId room, {
    bool? preloadedRoomReady,
  }) async {
    var roomReady = !roomHasReadyCharacterAssets(room);
    try {
      if (preloadedRoomReady != null) {
        roomReady = preloadedRoomReady;
      } else {
        roomReady = await _preloadAssetsForRoom(room);
      }
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

    // Ignore texture notifications that arrive before the target room switch
    // is committed. Those can belong to the previous room and must not end
    // the active transition.
    if (_roomSwitchCommittedAt == null ||
        _activeTransitionTargetRoom != widget.roomManager.currentRoom) {
      return;
    }

    _roomTransitionFailSafeTimer?.cancel();
    _roomTransitionFailSafeTimer = null;
    _awaitingTransitionCharacterFrame = false;
    _characterFrameWaitStartedAt = null;
    _roomTransitionBlurVisible = false;
    _dismissRoomTransitionOverlay();
  }

  void _dismissRoomTransitionOverlay() {
    if (!_roomTransitionInProgress) {
      return;
    }

    final transitionStartedAt = _transitionStartedAt;
    if (transitionStartedAt != null) {
      final elapsedSinceStart = DateTime.now().difference(transitionStartedAt);
      final remainingBlurTime =
          _minimumBlurVisibilityDuration - elapsedSinceStart;
      if (remainingBlurTime > Duration.zero) {
        _roomTransitionOverlayReleaseTimer?.cancel();
        _roomTransitionOverlayReleaseTimer = Timer(remainingBlurTime, () {
          if (!mounted) {
            return;
          }
          _dismissRoomTransitionOverlay();
        });
        return;
      }
    }

    final durationMs = _transitionStartedAt != null
        ? DateTime.now().difference(_transitionStartedAt!).inMilliseconds
        : -1;
    renderLog(
      'MainRoomScreen',
      'TRANSITION_END epoch=$_activeTransitionEpoch durationMs=$durationMs',
    );

    setState(() {
      _roomTransitionOverlayVisible = false;
      _roomTransitionBlurVisible = false;
      _roomTransitionInProgress = false;
      _transitionStartedAt = null;
      _characterFrameWaitStartedAt = null;
      _activeTransitionEpoch = 0;
      _activeTransitionTargetRoom = null;
      _activeTransitionSourceRoom = null;
    });

    _roomSwitchCommittedAt = null;
    _roomTransitionOverlayReleaseTimer?.cancel();
    _roomTransitionOverlayReleaseTimer = null;
    _roomTransitionFailSafeTimer?.cancel();
    _roomTransitionFailSafeTimer = null;

    Timer(_blurFadeOutDuration, () {
      if (!mounted || _roomTransitionInProgress) {
        return;
      }
      setState(() {
        _transitionCrossfadeBackgroundAsset = null;
        _transitionBlurBackgroundAsset = null;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _maybeCompleteRoomInitialization(
        source: 'MainRoomScreen._dismissRoomTransitionOverlay',
      );

      _drainQueuedRoomSelection();
    });
  }

  @override
  void dispose() {
    _roomTransitionFailSafeTimer?.cancel();
    _roomTransitionOverlayReleaseTimer?.cancel();
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
                                        child: AnimatedOpacity(
                                          opacity: _roomTransitionBlurVisible
                                              ? 0
                                              : 1,
                                          duration: const Duration(
                                            milliseconds: 120,
                                          ),
                                          curve: Curves.easeOut,
                                          child: SpriteSequencePlayer(
                                            key: ValueKey<RoomId>(
                                              widget.roomManager.currentRoom,
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
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: _roomTransitionOverlayVisible
                        ? _roomCrossfadeInDuration
                        : _roomCrossfadeOutDuration,
                    curve: Curves.easeInOutCubic,
                    opacity: _roomTransitionOverlayVisible ? 1 : 0,
                    child: _transitionCrossfadeBackgroundAsset == null
                        ? const SizedBox.shrink()
                        : _RoomCrossfadeOverlay(
                            backgroundAsset:
                                _transitionCrossfadeBackgroundAsset!,
                          ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_roomTransitionBlurVisible,
                  child: AnimatedOpacity(
                    duration: _roomTransitionBlurVisible
                        ? const Duration(milliseconds: 280)
                        : _blurFadeOutDuration,
                    curve: _roomTransitionBlurVisible
                        ? Curves.easeInOutCubic
                        : Curves.easeOut,
                    opacity: _roomTransitionBlurVisible ? 1 : 0,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        if (_transitionBlurBackgroundAsset != null)
                          ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: 10,
                              sigmaY: 10,
                            ),
                            child: _RoomCrossfadeOverlay(
                              backgroundAsset: _transitionBlurBackgroundAsset!,
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 28, 14, 0),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: RoomNavigationBar(
                      currentRoom: widget.roomManager.currentRoom,
                      onRoomSelectionRequested: _requestRoomSelectionWarmup,
                      onRoomSelected: (room) {
                        unawaited(_handleRoomSelected(room));
                      },
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

class _RoomCrossfadeOverlay extends StatelessWidget {
  const _RoomCrossfadeOverlay({required this.backgroundAsset});

  final String backgroundAsset;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      backgroundAsset,
      fit: BoxFit.cover,
      alignment: Alignment.bottomCenter,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        return const ColoredBox(color: Color(0xFFE7DED4));
      },
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
