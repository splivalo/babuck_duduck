import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../controllers/sprite_controller.dart';
import '../controllers/sprite_sequence_controller.dart';
import '../models/app_models.dart';
import '../services/sound_manager.dart';

enum CharacterLifecycleState {
  roomSelected,
  assetsLoading,
  assetsReady,
  textureFirstBound,
  animationAllowed,
}

class CharacterManager extends ChangeNotifier {
  CharacterManager({required SoundManager soundManager, Random? random})
    : _soundManager = soundManager,
      _random = random ?? Random(),
      spriteController = SpriteController() {
    spriteController.addFirstTextureBoundListener(_handleFirstTextureBound);
  }

  final SoundManager _soundManager;
  final SpriteController spriteController;
  final Random _random;

  SpriteSequenceController get sequenceController =>
      spriteController.sequenceController;

  // 1-in-N chance the next idle is the room's "special" idle (sway by day,
  // yawn by night) instead of a blink → 20% special / 80% blink.
  static const int _specialIdleChanceDenominator = 5;

  Timer? _idleDelayTimer;
  RoomId _selectedRoom = RoomId.bedroom;
  bool _reactionPlaying = false;
  _IdleAnimationKind? _lastIdleKind;
  bool _forceNextIdleBlink = true;
  bool _forceNextIdleYawn = false;
  bool _nightMood = false;
  bool _isRoomJustEntered = true;
  bool _roomIsInitializing = false;
  int _idleSequenceToken = 0;
  int _activeIdleSchedulerId = 0;
  int _roomInitializationId = 0;
  int _loggedAssetsReadyInitializationId = 0;
  int _loggedCharacterAttachedInitializationId = 0;
  int _loggedIdleStartedInitializationId = 0;
  CharacterLifecycleState _state = CharacterLifecycleState.roomSelected;
  bool _pendingIdle = false;
  bool _pendingIdleAllowWhileInitializing = false;

  static final Map<RoomId, CharacterDefinition> _definitions =
      <RoomId, CharacterDefinition>{
        for (final room in roomNavigationOrder)
          if (roomHasReadyCharacterAssets(room))
            room: _buildCharacterDefinition(
              room,
              roomConfigMap[room]!.character,
            ),
      };

  static String _characterLabel(CharacterId id) => switch (id) {
    CharacterId.babak => 'Babak',
    CharacterId.dudak => 'Dudak',
  };

  /// Builds a room's character from its per-animation configs. The yawn is a
  /// night-only idle that only some rooms author, so it is attached only where
  /// its config has actually been migrated to an atlas (others default to
  /// pngOnly and get no yawn).
  static CharacterDefinition _buildCharacterDefinition(
    RoomId room,
    CharacterId character,
  ) {
    SequenceClip clipFor(CharacterAnimationId animationId) =>
        animationConfigFor(room, character, animationId).toSequenceClip();

    final yawnConfig = animationConfigFor(
      room,
      character,
      CharacterAnimationId.idleYawn,
    );

    return CharacterDefinition(
      id: character,
      label: _characterLabel(character),
      idleBlink: clipFor(CharacterAnimationId.idleBlink),
      idleSway: clipFor(CharacterAnimationId.idleSway),
      reactionHead: clipFor(CharacterAnimationId.reactionHead),
      reactionBelly: clipFor(CharacterAnimationId.reactionBelly),
      reactionLegs: clipFor(CharacterAnimationId.reactionLegs),
      idleYawn:
          yawnConfig.migrationStatus == AnimationMigrationStatus.migrated
          ? yawnConfig.toSequenceClip()
          : null,
    );
  }

  RoomId get selectedRoom => _selectedRoom;
  CharacterId get selectedCharacter => roomConfigMap[_selectedRoom]!.character;
  CharacterDefinition get currentCharacter => _definitions[_selectedRoom]!;
  bool get hasVisibleCharacter => roomHasReadyCharacterAssets(_selectedRoom);
  bool get reactionPlaying => _reactionPlaying;

  CharacterDefinition characterForRoom(RoomId room) => _definitions[room]!;
  bool get roomIsInitializing => _roomIsInitializing;
  int get activeIdleSchedulerId => _activeIdleSchedulerId;
  CharacterLifecycleState get lifecycleState => _state;
  bool get canPlayAnimation =>
      _state == CharacterLifecycleState.animationAllowed;

  bool get _isIdleClipActive =>
      sequenceController.clip?.name.startsWith('idle_') ?? false;

  void _logIdle(String message) {
    debugPrint(message);
  }

  void setState(CharacterLifecycleState newState) {
    if (_state == newState) {
      return;
    }

    _state = newState;
    _logIdle('LIFECYCLE_STATE state=${newState.name}');

    if (_state == CharacterLifecycleState.animationAllowed && _pendingIdle) {
      unawaited(_playIdleBurst());
    }
  }

  void _handleFirstTextureBound() {
    setState(CharacterLifecycleState.textureFirstBound);
    setState(CharacterLifecycleState.animationAllowed);
    // setState's internal check fires _playIdleBurst only when transitioning
    // into animationAllowed. If state was already animationAllowed (same-state
    // guard short-circuits), this fallback ensures _pendingIdle is not lost.
    if (_pendingIdle) {
      unawaited(_playIdleBurst());
    }
  }

  void _logRoomLifecycle(String stage, {required String source}) {
    debugPrint(
      '$stage source=$source initId=$_roomInitializationId room=${_selectedRoom.name} schedulerId=$_activeIdleSchedulerId',
    );
  }

  void _cancelIdleLoop(String source) {
    _idleSequenceToken += 1;
    _activeIdleSchedulerId = _idleSequenceToken;
    _idleDelayTimer?.cancel();
    _idleDelayTimer = null;
    _logIdle(
      'IDLE_RESET source=$source schedulerId=$_activeIdleSchedulerId room=${_selectedRoom.name}',
    );
  }

  void suspendScene() {
    _cancelIdleLoop('CharacterManager.suspendScene');
    _reactionPlaying = false;
    sequenceController.clear();
    notifyListeners();
  }

  void resumeScene() {
    requestIdleStart(source: 'CharacterManager.resumeScene');
  }

  void beginRoomInitialization(RoomId room, {required String source}) {
    _roomInitializationId += 1;
    _loggedAssetsReadyInitializationId = 0;
    _loggedCharacterAttachedInitializationId = 0;
    _loggedIdleStartedInitializationId = 0;
    _roomIsInitializing = true;
    _cancelIdleLoop(source);
    _reactionPlaying = false;
    _resetIdleDeckForRoomEntry();
    _isRoomJustEntered = true;
    _selectedRoom = room;
    _pendingIdle = false;
    _pendingIdleAllowWhileInitializing = false;
    setState(CharacterLifecycleState.roomSelected);
    setState(CharacterLifecycleState.assetsLoading);
    spriteController.resetForRoom();
    sequenceController.clear();
    _logRoomLifecycle('ROOM_INIT_START', source: source);
    notifyListeners();
  }

  void markRoomAssetsReady({required String source}) {
    if (!_roomIsInitializing ||
        _loggedAssetsReadyInitializationId == _roomInitializationId) {
      return;
    }

    _loggedAssetsReadyInitializationId = _roomInitializationId;
    _logRoomLifecycle('ROOM_ASSETS_READY', source: source);
    setState(CharacterLifecycleState.assetsReady);
    if (!spriteController.hasFirstTextureBound) {
      // Seed the first painted frame with the clip the room will open on, so
      // there's no blink→sway/yawn jump on entry.
      spriteController.warmupFirstTexture(
        _idleClipForKind(_roomEntryIdleKind()),
      );
    }
    // The entry idle (sway/yawn) is always followed by a blink. Decode the
    // blink atlas now so that first transition doesn't hitch on a cold entry.
    spriteController.prefetchClip(currentCharacter.idleBlink);
  }

  void markCharacterAttached({required String source}) {
    if (!_roomIsInitializing ||
        _loggedCharacterAttachedInitializationId == _roomInitializationId) {
      return;
    }

    _loggedCharacterAttachedInitializationId = _roomInitializationId;
    _logRoomLifecycle('CHARACTER_ATTACHED', source: source);
  }

  void completeRoomInitialization({required String source}) {
    if (!_roomIsInitializing) {
      return;
    }

    _roomIsInitializing = false;
    _logRoomLifecycle('ROOM_INIT_DONE', source: source);
    notifyListeners();
  }

  bool syncRoom(RoomId room, {bool force = false}) {
    if (!force && _selectedRoom == room && !_roomIsInitializing) {
      return false;
    }

    final didChange = _selectedRoom != room;
    beginRoomInitialization(room, source: 'CharacterManager.syncRoom');
    _logIdle('IDLE_ROOM_ENTRY_RESET room=${_selectedRoom.name}');
    return didChange;
  }

  void requestIdleStart({
    required String source,
    bool forceRestart = false,
    bool allowWhileInitializing = false,
  }) {
    if (_roomIsInitializing && !allowWhileInitializing) {
      _logIdle(
        'IDLE_BLOCKED source=$source schedulerId=$_activeIdleSchedulerId room=${_selectedRoom.name} reason=room_initializing',
      );
      return;
    }

    if (!forceRestart &&
        !_reactionPlaying &&
        _isIdleClipActive &&
        !_isRoomJustEntered) {
      _logIdle(
        'IDLE_TRIGGER_SKIPPED source=$source schedulerId=$_activeIdleSchedulerId room=${_selectedRoom.name}',
      );
      return;
    }

    _cancelIdleLoop(source);
    _reactionPlaying = false;
    _pendingIdle = true;
    _pendingIdleAllowWhileInitializing = allowWhileInitializing;
    if (!hasVisibleCharacter) {
      sequenceController.clear();
      notifyListeners();
      return;
    }

    _activeIdleSchedulerId = _idleSequenceToken;
    _logIdle(
      'IDLE_TRIGGER source=$source schedulerId=$_activeIdleSchedulerId room=${_selectedRoom.name}',
    );
    if (_loggedIdleStartedInitializationId != _roomInitializationId) {
      _loggedIdleStartedInitializationId = _roomInitializationId;
      _logRoomLifecycle('IDLE_STARTED', source: source);
    }
    notifyListeners();
    unawaited(_playIdleBurst());
  }

  void startIdleLoop({
    required String source,
    bool forceRestart = false,
    bool allowWhileInitializing = false,
  }) {
    requestIdleStart(
      source: source,
      forceRestart: forceRestart,
      allowWhileInitializing: allowWhileInitializing,
    );
  }

  void replayRoomEntryBlink({required String source}) {
    _isRoomJustEntered = true;
    _forceNextIdleBlink = true;
    requestIdleStart(
      source: source,
      forceRestart: true,
      allowWhileInitializing: true,
    );
  }

  /// Syncs the day/night idle deck without interrupting the current idle.
  /// Called on room entry so a room left with the light off keeps using the
  /// night deck (blink/yawn) instead of the day deck (blink/sway).
  void syncNightMood({required bool isNight}) {
    _nightMood = isNight;
  }

  /// Called when the player toggles the room light. Turning the light off makes
  /// the character yawn right away (if it has a yawn clip); the night idle deck
  /// (80% blink / 20% yawn) then takes over. Turning it back on reverts to the
  /// day deck (blink/sway) without interrupting the current idle.
  void handleLightToggled({required bool isNight}) {
    _nightMood = isNight;
    if (!isNight || currentCharacter.idleYawn == null) {
      return;
    }
    _forceNextIdleYawn = true;
    // The yawn is followed by a blink; make sure its atlas is decoded so that
    // transition doesn't hitch the first time the light is turned off.
    spriteController.prefetchClip(currentCharacter.idleBlink);
    requestIdleStart(
      source: 'CharacterManager.handleLightToggled',
      forceRestart: true,
    );
  }

  void handleZoneTap(TouchZone zone) {
    if (!hasVisibleCharacter || (_roomIsInitializing && !_isIdleClipActive)) {
      return;
    }

    _cancelIdleLoop('CharacterManager.handleZoneTap');
    _reactionPlaying = true;
    notifyListeners();
    unawaited(
      _soundManager.playReaction(_selectedRoom, selectedCharacter, zone),
    );
    final reactionClip = currentCharacter.reactionFor(zone);
    sequenceController.play(
      reactionClip,
      onCompleted: () {
        _reactionPlaying = false;
        // Reactions are authored so their last frame matches idleBlink frame 0
        // byte-for-byte; idleSway content has its own slight width offset.
        // Forcing blink here guarantees a seamless reaction→idle transition.
        _forceNextIdleBlink = true;
        notifyListeners();
        requestIdleStart(
          source: 'CharacterManager.handleZoneTap.onCompleted',
          forceRestart: true,
          allowWhileInitializing: _roomIsInitializing,
        );
      },
    );
  }

  void _scheduleNextIdle(int idleSequenceToken) {
    final delay = Duration(milliseconds: 400 + _random.nextInt(900));
    _logIdle(
      'IDLE_SCHEDULE source=CharacterManager._scheduleNextIdle schedulerId=$_activeIdleSchedulerId room=${_selectedRoom.name} delayMs=${delay.inMilliseconds}',
    );
    _idleDelayTimer = Timer(delay, () {
      if (idleSequenceToken != _idleSequenceToken || _reactionPlaying) {
        return;
      }

      _pendingIdle = true;
      _pendingIdleAllowWhileInitializing = _roomIsInitializing;
      unawaited(_playIdleBurst());
    });
  }

  Future<void> _playIdleBurst() async {
    if (_state != CharacterLifecycleState.animationAllowed) {
      _pendingIdle = true;
      return;
    }

    _pendingIdle = false;
    _doPlayIdleBurst();
  }

  void _doPlayIdleBurst() {
    final idleSequenceToken = _idleSequenceToken;
    final allowWhileInitializing = _pendingIdleAllowWhileInitializing;
    if (_reactionPlaying || (_roomIsInitializing && !allowWhileInitializing)) {
      return;
    }

    final clip = _takeNextIdleClip();
    _logIdle(
      'IDLE_PLAY source=CharacterManager._playIdleBurst schedulerId=$_activeIdleSchedulerId room=${_selectedRoom.name} clip=${clip.name}',
    );
    const repeatCount = 1;
    _playIdleSequence(clip, repeatCount, idleSequenceToken);
  }

  @visibleForTesting
  SequenceClip debugTakeNextIdleClip() => _takeNextIdleClip();

  @visibleForTesting
  void debugForceAnimationAllowed() {
    setState(CharacterLifecycleState.animationAllowed);
  }

  /// The idle a room opens with: yawn at night (if available), else blink at
  /// night, else sway by day.
  _IdleAnimationKind _roomEntryIdleKind() {
    if (_nightMood) {
      return currentCharacter.idleYawn != null
          ? _IdleAnimationKind.yawn
          : _IdleAnimationKind.blink;
    }
    return _IdleAnimationKind.sway;
  }

  SequenceClip _idleClipForKind(_IdleAnimationKind kind) {
    switch (kind) {
      case _IdleAnimationKind.blink:
        return currentCharacter.idleBlink;
      case _IdleAnimationKind.sway:
        return currentCharacter.idleSway;
      case _IdleAnimationKind.yawn:
        return currentCharacter.idleYawn ?? currentCharacter.idleBlink;
    }
  }

  SequenceClip _takeNextIdleClip() {
    if (_isRoomJustEntered) {
      _isRoomJustEntered = false;
      _logIdle('IDLE_ROOM_ENTRY_GATE_CONSUMED room=${_selectedRoom.name}');
      _forceNextIdleBlink = false;
      _forceNextIdleYawn = false;
      // Room entry opens with a "special" idle: yawn at night (if the character
      // has one), sway by day. The next idle is then forced to blink (special
      // never twice in a row), after which the normal 80/20 deck resumes.
      final entryKind = _roomEntryIdleKind();
      _lastIdleKind = entryKind;
      return _idleClipForKind(entryKind);
    }

    final yawn = currentCharacter.idleYawn;

    if (_forceNextIdleYawn) {
      _forceNextIdleYawn = false;
      if (yawn != null) {
        _lastIdleKind = _IdleAnimationKind.yawn;
        return yawn;
      }
    }

    if (_forceNextIdleBlink) {
      _forceNextIdleBlink = false;
      _lastIdleKind = _IdleAnimationKind.blink;
      return currentCharacter.idleBlink;
    }

    // Never play a "special" idle (sway/yawn) twice in a row.
    if (_lastIdleKind == _IdleAnimationKind.sway ||
        _lastIdleKind == _IdleAnimationKind.yawn) {
      _lastIdleKind = _IdleAnimationKind.blink;
      return currentCharacter.idleBlink;
    }

    // At night the special idle is the yawn; by day it's the sway.
    if (_nightMood && yawn != null) {
      if (_random.nextInt(_specialIdleChanceDenominator) == 0) {
        _lastIdleKind = _IdleAnimationKind.yawn;
        return yawn;
      }
      _lastIdleKind = _IdleAnimationKind.blink;
      return currentCharacter.idleBlink;
    }

    if (_random.nextInt(_specialIdleChanceDenominator) == 0) {
      _lastIdleKind = _IdleAnimationKind.sway;
      return currentCharacter.idleSway;
    }

    _lastIdleKind = _IdleAnimationKind.blink;
    return currentCharacter.idleBlink;
  }

  void _resetIdleDeckForRoomEntry() {
    _lastIdleKind = null;
    _forceNextIdleBlink = true;
    _forceNextIdleYawn = false;
  }

  void _playIdleSequence(
    SequenceClip clip,
    int remaining,
    int idleSequenceToken,
  ) {
    sequenceController.play(
      clip,
      onEvent: (event) {
        unawaited(_soundManager.playAnimationEvent(event.name));
      },
      onCompleted: () {
        if (idleSequenceToken != _idleSequenceToken || _reactionPlaying) {
          return;
        }
        if (remaining > 1) {
          _playIdleSequence(clip, remaining - 1, idleSequenceToken);
          return;
        }
        _scheduleNextIdle(idleSequenceToken);
      },
    );
  }

  @override
  void dispose() {
    _idleDelayTimer?.cancel();
    spriteController.removeFirstTextureBoundListener(_handleFirstTextureBound);
    spriteController.dispose();
    super.dispose();
  }
}

enum _IdleAnimationKind { blink, sway, yawn }
