import 'package:flutter/foundation.dart';

enum AppFlow { splash, mainRoom }

enum CharacterId { babak, dudak }

enum RoomId { bedroom, wardrobe, baloon, rocket }

enum BedroomMood { day, night }

enum TouchZone { head, belly, legs }

enum CharacterSoundType { laugh, belly, head, legs }

enum CharacterAnimationId {
  idleBlink,
  idleSway,
  reactionHead,
  reactionBelly,
  reactionLegs,
}

enum AnimationMigrationStatus { pngOnly, atlasReady, migrated }

class AnimationFrameTiming {
  const AnimationFrameTiming({
    required this.frameIndex,
    required this.durationMs,
  });

  factory AnimationFrameTiming.fromJson(Map<String, dynamic> json) {
    return AnimationFrameTiming(
      frameIndex: (json['frameIndex'] as num).toInt(),
      durationMs: (json['durationMs'] as num).toInt(),
    );
  }

  final int frameIndex;
  final int durationMs;
}

class AnimationTimelineEvent {
  const AnimationTimelineEvent({
    required this.name,
    required this.timeMs,
    this.repeatEachLoop = true,
  });

  factory AnimationTimelineEvent.fromJson(Map<String, dynamic> json) {
    return AnimationTimelineEvent(
      name: json['name'] as String,
      timeMs: (json['timeMs'] as num).toInt(),
      repeatEachLoop: json['repeatEachLoop'] as bool? ?? true,
    );
  }

  final String name;
  final int timeMs;
  final bool repeatEachLoop;
}

class SpriteSheetFrameRect {
  const SpriteSheetFrameRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory SpriteSheetFrameRect.fromJson(Map<String, dynamic> json) {
    return SpriteSheetFrameRect(
      x: (json['x'] as num).toInt(),
      y: (json['y'] as num).toInt(),
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
    );
  }

  final int x;
  final int y;
  final int width;
  final int height;
}

abstract class FrameSource {
  const FrameSource();

  int get frameCount;

  String? frameAssetPathAt(int index) => null;
}

class PngSequenceFrameSource extends FrameSource {
  const PngSequenceFrameSource({
    required this.assetDirectory,
    required this.frameCount,
  });

  final String assetDirectory;

  @override
  final int frameCount;

  @override
  String frameAssetPathAt(int index) {
    return '$assetDirectory/${(index + 1).toString().padLeft(4, '0')}.png';
  }
}

class SpriteSheetFrameSource extends FrameSource {
  const SpriteSheetFrameSource({
    required this.imageAssetPath,
    required this.metadataAssetPath,
    required this.frameCount,
  });

  final String imageAssetPath;
  final String metadataAssetPath;

  @override
  final int frameCount;
}

/// Describes where the tappable lamp sits inside a room background image.
///
/// Coordinates are expressed as fractions of the *background image* (not the
/// screen), so the tap target lands on the lamp regardless of how `BoxFit.cover`
/// crops the image on a given phone. [imageAspectRatio] is the intrinsic
/// width / height of the background asset, needed to reproduce the cover crop.
class RoomLampConfig {
  const RoomLampConfig({
    required this.imageFractionX,
    required this.imageFractionY,
    required this.imageAspectRatio,
    this.tapSizeFactor = 0.42,
    this.minTapSize = 136.0,
    this.maxTapSize = 184.0,
  });

  final double imageFractionX;
  final double imageFractionY;
  final double imageAspectRatio;
  final double tapSizeFactor;
  final double minTapSize;
  final double maxTapSize;
}

class RoomConfig {
  const RoomConfig({
    required this.room,
    required this.label,
    required this.character,
    required this.backgroundDayAsset,
    this.stageScale = 1.0,
    this.stageLiftFactor = 0.086,
    this.backgroundNightAsset,
    this.lamp,
  });

  final RoomId room;
  final String label;
  final CharacterId character;
  final String backgroundDayAsset;
  final double stageScale;
  final double stageLiftFactor;
  final String? backgroundNightAsset;
  final RoomLampConfig? lamp;

  bool get supportsMoodToggle => backgroundNightAsset != null;

  String backgroundAsset(BedroomMood mood) {
    if (backgroundNightAsset == null) {
      return backgroundDayAsset;
    }

    return mood == BedroomMood.day ? backgroundDayAsset : backgroundNightAsset!;
  }

  String labelForMood(BedroomMood mood) {
    if (backgroundNightAsset == null) {
      return label;
    }

    return mood == BedroomMood.day ? '$label Day' : '$label Night';
  }
}

class TimedSoundCue {
  const TimedSoundCue({
    required this.assetPath,
    this.delay = Duration.zero,
    this.playbackRate = 1.0,
    this.startOffset = Duration.zero,
  });

  final String assetPath;
  final Duration delay;
  final double playbackRate;
  final Duration startOffset;
}

enum SoundPlaybackBehavior { overlap, restart, guardedRestart }

class ReactionSoundConfig {
  const ReactionSoundConfig({
    required this.cues,
    this.playbackBehavior = SoundPlaybackBehavior.overlap,
  });

  final List<TimedSoundCue> cues;
  final SoundPlaybackBehavior playbackBehavior;
}

class AnimationEventSoundConfig {
  const AnimationEventSoundConfig({
    required this.cues,
    this.playbackBehavior = SoundPlaybackBehavior.guardedRestart,
  });

  final List<TimedSoundCue> cues;
  final SoundPlaybackBehavior playbackBehavior;
}

class CharacterAnimationConfig {
  const CharacterAnimationConfig({
    required this.roomId,
    required this.characterId,
    required this.animationId,
    required this.clipName,
    required this.pngAssetDirectory,
    required this.frameCount,
    required this.fps,
    required this.migrationStatus,
    this.frameTimings,
    this.animationEvents,
    this.atlasImageAssetPath,
    this.atlasMetadataAssetPath,
  });

  final RoomId roomId;
  final CharacterId characterId;
  final CharacterAnimationId animationId;
  final String clipName;
  final String pngAssetDirectory;
  final int frameCount;
  final int fps;
  final AnimationMigrationStatus migrationStatus;
  final List<AnimationFrameTiming>? frameTimings;
  final List<AnimationTimelineEvent>? animationEvents;
  final String? atlasImageAssetPath;
  final String? atlasMetadataAssetPath;

  bool get atlasConfigured =>
      atlasImageAssetPath != null && atlasMetadataAssetPath != null;

  bool get atlasFirst => atlasConfigured;

  bool get allowRuntimePngFallback =>
      migrationStatus != AnimationMigrationStatus.migrated;

  SequenceClip toSequenceClip() {
    if (atlasConfigured && atlasFirst) {
      return SequenceClip.spriteSheet(
        name: clipName,
        imageAssetPath: atlasImageAssetPath!,
        metadataAssetPath: atlasMetadataAssetPath!,
        fallbackAssetDirectory: pngAssetDirectory,
        frameCount: frameCount,
        fps: fps,
        frameTimings: frameTimings,
        animationEvents: animationEvents,
        allowPngFallback: allowRuntimePngFallback,
      );
    }

    return SequenceClip(
      name: clipName,
      assetDirectory: pngAssetDirectory,
      frameCount: frameCount,
      fps: fps,
      frameTimings: frameTimings,
      animationEvents: animationEvents,
    );
  }
}

const Map<RoomId, RoomConfig> roomConfigMap = <RoomId, RoomConfig>{
  RoomId.bedroom: RoomConfig(
    room: RoomId.bedroom,
    label: 'Bedroom',
    character: CharacterId.babak,
    backgroundDayAsset: 'assets/backgrounds/bedroom_day.jpg',
    stageLiftFactor: 0.1,
    backgroundNightAsset: 'assets/backgrounds/bedroom_night.jpg',
    lamp: RoomLampConfig(
      imageFractionX: 0.505,
      imageFractionY: 0.43,
      imageAspectRatio: 1536 / 2720,
    ),
  ),
  RoomId.wardrobe: RoomConfig(
    room: RoomId.wardrobe,
    label: 'Wardrobe',
    character: CharacterId.dudak,
    backgroundDayAsset: 'assets/backgrounds/wardrobe_room.jpg',
    stageLiftFactor: 0.1,
  ),
  RoomId.baloon: RoomConfig(
    room: RoomId.baloon,
    label: 'Balloon Room',
    character: CharacterId.babak,
    backgroundDayAsset: 'assets/backgrounds/baloon_room.jpg',
    stageLiftFactor: 0.1,
  ),
  RoomId.rocket: RoomConfig(
    room: RoomId.rocket,
    label: 'Rocket',
    character: CharacterId.dudak,
    backgroundDayAsset: 'assets/backgrounds/rocket_room.jpg',
    stageLiftFactor: 0.1,
    backgroundNightAsset: 'assets/backgrounds/rocket_room_night.jpg',
    lamp: RoomLampConfig(
      imageFractionX: 0.335,
      imageFractionY: 0.29,
      imageAspectRatio: 1536 / 2750,
    ),
  ),
};

const List<RoomId> roomNavigationOrder = <RoomId>[
  RoomId.bedroom,
  RoomId.wardrobe,
  RoomId.baloon,
  RoomId.rocket,
];

const Set<RoomId> roomsWithReadyCharacterAssets = <RoomId>{
  RoomId.wardrobe,
  RoomId.rocket,
};

List<RoomConfig> get roomNavigationItems => roomNavigationOrder
    .map((room) => roomConfigMap[room]!)
    .toList(growable: false);

bool roomHasReadyCharacterAssets(RoomId roomId) =>
    roomsWithReadyCharacterAssets.contains(roomId);

String _characterRoomAssetRoot(RoomId roomId, CharacterId characterId) {
  switch ((roomId, characterId)) {
    case (RoomId.bedroom, CharacterId.babak):
      return 'assets/characters/babak/bedroom';
    case (RoomId.wardrobe, CharacterId.dudak):
      return 'assets/characters/dudak/wardrobe';
    case (RoomId.baloon, CharacterId.babak):
      return 'assets/characters/babak/baloon';
    case (RoomId.rocket, CharacterId.dudak):
      return 'assets/characters/dudak/rocket';
    default:
      throw StateError(
        'Invalid room/character pairing: ${roomId.name}/${characterId.name}',
      );
  }
}

String _animationDirectoryName(CharacterAnimationId animationId) {
  switch (animationId) {
    case CharacterAnimationId.idleBlink:
      return 'idle_blink';
    case CharacterAnimationId.idleSway:
      return 'idle_sway';
    case CharacterAnimationId.reactionHead:
      return 'reaction_head';
    case CharacterAnimationId.reactionBelly:
      return 'reaction_belly';
    case CharacterAnimationId.reactionLegs:
      return 'reaction_legs';
  }
}

int _defaultFrameCountForAnimation(CharacterAnimationId animationId) {
  switch (animationId) {
    case CharacterAnimationId.idleBlink:
      return 6;
    case CharacterAnimationId.idleSway:
      return 8;
    case CharacterAnimationId.reactionHead:
      return 8;
    case CharacterAnimationId.reactionBelly:
      return 10;
    case CharacterAnimationId.reactionLegs:
      return 8;
  }
}

String _roomCharacterTuningKey(RoomId roomId, CharacterId characterId) =>
    '${roomId.name}_${characterId.name}';

class RoomCharacterAnimationTuning {
  const RoomCharacterAnimationTuning({
    this.frameCounts = const <CharacterAnimationId, int>{},
    this.migrationStatuses =
        const <CharacterAnimationId, AnimationMigrationStatus>{},
    this.frameTimings =
        const <CharacterAnimationId, List<AnimationFrameTiming>>{},
    this.animationEvents =
        const <CharacterAnimationId, List<AnimationTimelineEvent>>{},
  });

  final Map<CharacterAnimationId, int> frameCounts;
  final Map<CharacterAnimationId, AnimationMigrationStatus> migrationStatuses;
  final Map<CharacterAnimationId, List<AnimationFrameTiming>> frameTimings;
  final Map<CharacterAnimationId, List<AnimationTimelineEvent>> animationEvents;
}

class RoomCharacterSoundTuning {
  const RoomCharacterSoundTuning({
    this.reactionSounds = const <TouchZone, ReactionSoundConfig>{},
    this.animationEventSounds = const <String, AnimationEventSoundConfig>{},
  });

  final Map<TouchZone, ReactionSoundConfig> reactionSounds;
  final Map<String, AnimationEventSoundConfig> animationEventSounds;
}

int _fpsForAnimation(CharacterAnimationId animationId) {
  switch (animationId) {
    case CharacterAnimationId.idleBlink:
      return 12;
    case CharacterAnimationId.idleSway:
      return 10;
    case CharacterAnimationId.reactionHead:
    case CharacterAnimationId.reactionBelly:
    case CharacterAnimationId.reactionLegs:
      return 14;
  }
}

class BlinkTimingControl {
  const BlinkTimingControl({
    required this.frameCount,
    required this.openHoldMs,
    required this.openHoldTickMs,
    required this.blinkFrameMs,
    required this.reopenHoldMs,
  });

  final int frameCount;
  final int openHoldMs;
  final int openHoldTickMs;
  final int blinkFrameMs;
  final int reopenHoldMs;
}

const BlinkTimingControl _babakRoomBlinkTiming = BlinkTimingControl(
  frameCount: 6,
  openHoldMs: 1500,
  openHoldTickMs: 75,
  blinkFrameMs: 24,
  reopenHoldMs: 64,
);

List<AnimationFrameTiming> _buildBlinkFrameTimings(BlinkTimingControl control) {
  final openFrameRepeats =
      ((control.openHoldMs + control.openHoldTickMs - 1) ~/
              control.openHoldTickMs)
          .clamp(1, 1000);
  final playbackFrames = <AnimationFrameTiming>[
    for (var index = 0; index < openFrameRepeats; index += 1)
      AnimationFrameTiming(frameIndex: 0, durationMs: control.openHoldTickMs),
  ];

  for (
    var frameIndex = 1;
    frameIndex < control.frameCount - 1;
    frameIndex += 1
  ) {
    playbackFrames.add(
      AnimationFrameTiming(
        frameIndex: frameIndex,
        durationMs: control.blinkFrameMs,
      ),
    );
  }

  if (control.frameCount > 1) {
    playbackFrames.add(
      AnimationFrameTiming(
        frameIndex: control.frameCount - 1,
        durationMs: control.reopenHoldMs,
      ),
    );
  }

  return playbackFrames;
}

final Map<String, RoomCharacterAnimationTuning>
_roomCharacterAnimationTunings = <String, RoomCharacterAnimationTuning>{
  _roomCharacterTuningKey(
    RoomId.bedroom,
    CharacterId.babak,
  ): RoomCharacterAnimationTuning(
    frameTimings: <CharacterAnimationId, List<AnimationFrameTiming>>{
      CharacterAnimationId.idleBlink: _buildBlinkFrameTimings(
        _babakRoomBlinkTiming,
      ),
    },
  ),
  _roomCharacterTuningKey(
    RoomId.baloon,
    CharacterId.babak,
  ): RoomCharacterAnimationTuning(
    frameTimings: <CharacterAnimationId, List<AnimationFrameTiming>>{
      CharacterAnimationId.idleBlink: _buildBlinkFrameTimings(
        _babakRoomBlinkTiming,
      ),
    },
  ),
  _roomCharacterTuningKey(
    RoomId.wardrobe,
    CharacterId.dudak,
  ): RoomCharacterAnimationTuning(
    migrationStatuses: const <CharacterAnimationId, AnimationMigrationStatus>{
      CharacterAnimationId.idleBlink: AnimationMigrationStatus.migrated,
      CharacterAnimationId.idleSway: AnimationMigrationStatus.migrated,
      CharacterAnimationId.reactionHead: AnimationMigrationStatus.migrated,
      CharacterAnimationId.reactionBelly: AnimationMigrationStatus.migrated,
      CharacterAnimationId.reactionLegs: AnimationMigrationStatus.migrated,
    },
    frameTimings: <CharacterAnimationId, List<AnimationFrameTiming>>{
      CharacterAnimationId.idleBlink: _buildBlinkFrameTimings(
        const BlinkTimingControl(
          frameCount: 10,
          openHoldMs: 1500,
          openHoldTickMs: 75,
          blinkFrameMs: 24,
          reopenHoldMs: 64,
        ),
      ),
    },
    animationEvents: const <CharacterAnimationId, List<AnimationTimelineEvent>>{
      CharacterAnimationId.idleSway: <AnimationTimelineEvent>[
        AnimationTimelineEvent(name: 'idle_swing_dudak_wardrobe', timeMs: 45),
      ],
    },
  ),
  _roomCharacterTuningKey(
    RoomId.rocket,
    CharacterId.dudak,
  ): const RoomCharacterAnimationTuning(
    frameCounts: <CharacterAnimationId, int>{
      CharacterAnimationId.idleBlink: 9,
      CharacterAnimationId.idleSway: 25,
      CharacterAnimationId.reactionHead: 18,
      CharacterAnimationId.reactionBelly: 33,
      CharacterAnimationId.reactionLegs: 17,
    },
    migrationStatuses: <CharacterAnimationId, AnimationMigrationStatus>{
      CharacterAnimationId.idleBlink: AnimationMigrationStatus.migrated,
      CharacterAnimationId.idleSway: AnimationMigrationStatus.migrated,
      CharacterAnimationId.reactionHead: AnimationMigrationStatus.migrated,
      CharacterAnimationId.reactionBelly: AnimationMigrationStatus.migrated,
      CharacterAnimationId.reactionLegs: AnimationMigrationStatus.migrated,
    },
    frameTimings: <CharacterAnimationId, List<AnimationFrameTiming>>{
      CharacterAnimationId.idleBlink: <AnimationFrameTiming>[
        AnimationFrameTiming(frameIndex: 0, durationMs: 1500),
        AnimationFrameTiming(frameIndex: 1, durationMs: 16),
        AnimationFrameTiming(frameIndex: 2, durationMs: 16),
        AnimationFrameTiming(frameIndex: 3, durationMs: 16),
        AnimationFrameTiming(frameIndex: 4, durationMs: 16),
        AnimationFrameTiming(frameIndex: 5, durationMs: 16),
        AnimationFrameTiming(frameIndex: 6, durationMs: 16),
        AnimationFrameTiming(frameIndex: 7, durationMs: 16),
        AnimationFrameTiming(frameIndex: 8, durationMs: 40),
      ],
      CharacterAnimationId.reactionHead: <AnimationFrameTiming>[
        AnimationFrameTiming(frameIndex: 0, durationMs: 105),
        AnimationFrameTiming(frameIndex: 1, durationMs: 71),
        AnimationFrameTiming(frameIndex: 2, durationMs: 71),
        AnimationFrameTiming(frameIndex: 3, durationMs: 71),
        AnimationFrameTiming(frameIndex: 4, durationMs: 71),
        AnimationFrameTiming(frameIndex: 5, durationMs: 71),
        AnimationFrameTiming(frameIndex: 6, durationMs: 71),
        AnimationFrameTiming(frameIndex: 7, durationMs: 71),
        AnimationFrameTiming(frameIndex: 8, durationMs: 71),
        AnimationFrameTiming(frameIndex: 9, durationMs: 71),
        AnimationFrameTiming(frameIndex: 10, durationMs: 71),
        AnimationFrameTiming(frameIndex: 11, durationMs: 71),
        AnimationFrameTiming(frameIndex: 12, durationMs: 71),
        AnimationFrameTiming(frameIndex: 13, durationMs: 71),
        AnimationFrameTiming(frameIndex: 14, durationMs: 71),
        AnimationFrameTiming(frameIndex: 15, durationMs: 71),
        AnimationFrameTiming(frameIndex: 16, durationMs: 71),
        AnimationFrameTiming(frameIndex: 17, durationMs: 71),
      ],
      CharacterAnimationId.reactionBelly: <AnimationFrameTiming>[
        AnimationFrameTiming(frameIndex: 0, durationMs: 158),
        AnimationFrameTiming(frameIndex: 1, durationMs: 71),
        AnimationFrameTiming(frameIndex: 2, durationMs: 71),
        AnimationFrameTiming(frameIndex: 3, durationMs: 71),
        AnimationFrameTiming(frameIndex: 4, durationMs: 71),
        AnimationFrameTiming(frameIndex: 5, durationMs: 71),
        AnimationFrameTiming(frameIndex: 6, durationMs: 71),
        AnimationFrameTiming(frameIndex: 7, durationMs: 71),
        AnimationFrameTiming(frameIndex: 8, durationMs: 71),
        AnimationFrameTiming(frameIndex: 9, durationMs: 71),
        AnimationFrameTiming(frameIndex: 10, durationMs: 71),
        AnimationFrameTiming(frameIndex: 11, durationMs: 71),
        AnimationFrameTiming(frameIndex: 12, durationMs: 71),
        AnimationFrameTiming(frameIndex: 13, durationMs: 71),
        AnimationFrameTiming(frameIndex: 14, durationMs: 71),
        AnimationFrameTiming(frameIndex: 15, durationMs: 71),
        AnimationFrameTiming(frameIndex: 16, durationMs: 71),
        AnimationFrameTiming(frameIndex: 17, durationMs: 71),
        AnimationFrameTiming(frameIndex: 18, durationMs: 71),
        AnimationFrameTiming(frameIndex: 19, durationMs: 71),
        AnimationFrameTiming(frameIndex: 20, durationMs: 71),
        AnimationFrameTiming(frameIndex: 21, durationMs: 71),
        AnimationFrameTiming(frameIndex: 22, durationMs: 71),
        AnimationFrameTiming(frameIndex: 23, durationMs: 71),
        AnimationFrameTiming(frameIndex: 24, durationMs: 71),
        AnimationFrameTiming(frameIndex: 25, durationMs: 71),
        AnimationFrameTiming(frameIndex: 26, durationMs: 71),
        AnimationFrameTiming(frameIndex: 27, durationMs: 71),
        AnimationFrameTiming(frameIndex: 28, durationMs: 71),
        AnimationFrameTiming(frameIndex: 29, durationMs: 71),
        AnimationFrameTiming(frameIndex: 30, durationMs: 71),
        AnimationFrameTiming(frameIndex: 31, durationMs: 71),
        AnimationFrameTiming(frameIndex: 32, durationMs: 71),
      ],
      CharacterAnimationId.reactionLegs: <AnimationFrameTiming>[
        AnimationFrameTiming(frameIndex: 0, durationMs: 152),
        AnimationFrameTiming(frameIndex: 1, durationMs: 71),
        AnimationFrameTiming(frameIndex: 2, durationMs: 71),
        AnimationFrameTiming(frameIndex: 3, durationMs: 71),
        AnimationFrameTiming(frameIndex: 4, durationMs: 71),
        AnimationFrameTiming(frameIndex: 5, durationMs: 71),
        AnimationFrameTiming(frameIndex: 6, durationMs: 71),
        AnimationFrameTiming(frameIndex: 7, durationMs: 71),
        AnimationFrameTiming(frameIndex: 8, durationMs: 71),
        AnimationFrameTiming(frameIndex: 9, durationMs: 71),
        AnimationFrameTiming(frameIndex: 10, durationMs: 71),
        AnimationFrameTiming(frameIndex: 11, durationMs: 71),
        AnimationFrameTiming(frameIndex: 12, durationMs: 71),
        AnimationFrameTiming(frameIndex: 13, durationMs: 71),
        AnimationFrameTiming(frameIndex: 14, durationMs: 71),
        AnimationFrameTiming(frameIndex: 15, durationMs: 71),
        AnimationFrameTiming(frameIndex: 16, durationMs: 71),
      ],
    },
    animationEvents: <CharacterAnimationId, List<AnimationTimelineEvent>>{
      CharacterAnimationId.idleSway: <AnimationTimelineEvent>[
        AnimationTimelineEvent(name: 'idle_swing_dudak', timeMs: 180),
      ],
    },
  ),
};

RoomCharacterAnimationTuning _roomCharacterAnimationTuning(
  RoomId roomId,
  CharacterId characterId,
) {
  return _roomCharacterAnimationTunings[_roomCharacterTuningKey(
        roomId,
        characterId,
      )] ??
      const RoomCharacterAnimationTuning();
}

final Map<String, RoomCharacterSoundTuning> _roomCharacterSoundTunings =
    <String, RoomCharacterSoundTuning>{
      _roomCharacterTuningKey(
        RoomId.bedroom,
        CharacterId.babak,
      ): const RoomCharacterSoundTuning(
        reactionSounds: <TouchZone, ReactionSoundConfig>{
          TouchZone.head: ReactionSoundConfig(
            playbackBehavior: SoundPlaybackBehavior.restart,
            cues: <TimedSoundCue>[
              TimedSoundCue(assetPath: 'assets/sounds/babak/head1.mp3'),
            ],
          ),
          TouchZone.belly: ReactionSoundConfig(cues: <TimedSoundCue>[]),
          TouchZone.legs: ReactionSoundConfig(
            playbackBehavior: SoundPlaybackBehavior.restart,
            cues: <TimedSoundCue>[
              TimedSoundCue(assetPath: 'assets/sounds/babak/legs1.mp3'),
            ],
          ),
        },
      ),
      _roomCharacterTuningKey(
        RoomId.baloon,
        CharacterId.babak,
      ): const RoomCharacterSoundTuning(
        reactionSounds: <TouchZone, ReactionSoundConfig>{
          TouchZone.head: ReactionSoundConfig(
            playbackBehavior: SoundPlaybackBehavior.restart,
            cues: <TimedSoundCue>[
              TimedSoundCue(assetPath: 'assets/sounds/babak/head1.mp3'),
            ],
          ),
          TouchZone.belly: ReactionSoundConfig(cues: <TimedSoundCue>[]),
          TouchZone.legs: ReactionSoundConfig(
            playbackBehavior: SoundPlaybackBehavior.restart,
            cues: <TimedSoundCue>[
              TimedSoundCue(assetPath: 'assets/sounds/babak/legs1.mp3'),
            ],
          ),
        },
      ),
      _roomCharacterTuningKey(
        RoomId.wardrobe,
        CharacterId.dudak,
      ): const RoomCharacterSoundTuning(
        reactionSounds: <TouchZone, ReactionSoundConfig>{
          TouchZone.head: ReactionSoundConfig(
            playbackBehavior: SoundPlaybackBehavior.restart,
            cues: <TimedSoundCue>[
              TimedSoundCue(
                assetPath: 'assets/sounds/dudak/noo.wav',
                playbackRate: 1.0,
                delay: Duration(milliseconds: 0),
              ),
            ],
          ),
          TouchZone.belly: ReactionSoundConfig(
            playbackBehavior: SoundPlaybackBehavior.restart,
            cues: <TimedSoundCue>[
              TimedSoundCue(assetPath: 'assets/sounds/dudak/belly_laugh_wardrobe.wav'),
            ],
          ),
          TouchZone.legs: ReactionSoundConfig(
            playbackBehavior: SoundPlaybackBehavior.restart,
            cues: <TimedSoundCue>[
              TimedSoundCue(
                assetPath: 'assets/sounds/dudak/legs_giggle.wav',
                playbackRate: 1.2,
              ),
            ],
          ),
        },
        animationEventSounds: <String, AnimationEventSoundConfig>{
          'idle_swing_dudak_wardrobe': AnimationEventSoundConfig(
            playbackBehavior: SoundPlaybackBehavior.guardedRestart,
            cues: <TimedSoundCue>[
              TimedSoundCue(
                assetPath: 'assets/sounds/dudak/giggle.wav',
                playbackRate: 0.8,
                delay: Duration(milliseconds: 20),
              ),
            ],
          ),
        },
      ),
      _roomCharacterTuningKey(
        RoomId.rocket,
        CharacterId.dudak,
      ): const RoomCharacterSoundTuning(
        reactionSounds: <TouchZone, ReactionSoundConfig>{
          TouchZone.head: ReactionSoundConfig(
            playbackBehavior: SoundPlaybackBehavior.restart,
            cues: <TimedSoundCue>[
              TimedSoundCue(
                assetPath: 'assets/sounds/dudak/head_punch_wobble.mp3',
                playbackRate: 1.5,
              ),
            ],
          ),
          TouchZone.belly: ReactionSoundConfig(
            playbackBehavior: SoundPlaybackBehavior.restart,
            cues: <TimedSoundCue>[
              TimedSoundCue(
                assetPath: 'assets/sounds/dudak/belly_laugh.mp3',
                playbackRate: 1.14,
              ),
            ],
          ),
          TouchZone.legs: ReactionSoundConfig(
            playbackBehavior: SoundPlaybackBehavior.restart,
            cues: <TimedSoundCue>[
              TimedSoundCue(
                assetPath: 'assets/sounds/dudak/legs_up.mp3',
                playbackRate: 2.0,
              ),
            ],
          ),
        },
        animationEventSounds: <String, AnimationEventSoundConfig>{
          'idle_swing_dudak': AnimationEventSoundConfig(
            cues: <TimedSoundCue>[
              TimedSoundCue(assetPath: 'assets/sounds/dudak/idle_swing.mp3'),
            ],
          ),
        },
      ),
    };

RoomCharacterSoundTuning _roomCharacterSoundTuning(
  RoomId roomId,
  CharacterId characterId,
) {
  return _roomCharacterSoundTunings[_roomCharacterTuningKey(
        roomId,
        characterId,
      )] ??
      const RoomCharacterSoundTuning();
}

int _frameCountForAnimation(
  RoomId roomId,
  CharacterId characterId,
  CharacterAnimationId animationId,
) {
  final tuning = _roomCharacterAnimationTuning(roomId, characterId);
  return tuning.frameCounts[animationId] ??
      _defaultFrameCountForAnimation(animationId);
}

List<AnimationFrameTiming>? _frameTimingsForAnimation(
  RoomId roomId,
  CharacterId characterId,
  CharacterAnimationId animationId,
) {
  final tuning = _roomCharacterAnimationTuning(roomId, characterId);
  return tuning.frameTimings[animationId];
}

List<AnimationTimelineEvent>? _animationEventsForAnimation(
  RoomId roomId,
  CharacterId characterId,
  CharacterAnimationId animationId,
) {
  final tuning = _roomCharacterAnimationTuning(roomId, characterId);
  return tuning.animationEvents[animationId];
}

CharacterAnimationConfig _buildCharacterAnimationConfig(
  RoomId roomId,
  CharacterId characterId,
  CharacterAnimationId animationId,
) {
  final assetRoot = _characterRoomAssetRoot(roomId, characterId);
  final animationDirectory = _animationDirectoryName(animationId);
  final directoryPath = '$assetRoot/$animationDirectory';

  return CharacterAnimationConfig(
    roomId: roomId,
    characterId: characterId,
    animationId: animationId,
    clipName: animationDirectory,
    pngAssetDirectory: directoryPath,
    atlasImageAssetPath: '$directoryPath.png',
    atlasMetadataAssetPath: '$directoryPath.json',
    frameCount: _frameCountForAnimation(roomId, characterId, animationId),
    fps: _fpsForAnimation(animationId),
    frameTimings: _frameTimingsForAnimation(roomId, characterId, animationId),
    animationEvents: _animationEventsForAnimation(
      roomId,
      characterId,
      animationId,
    ),
    migrationStatus: _migrationStatusForAnimation(
      roomId,
      characterId,
      animationId,
    ),
  );
}

AnimationMigrationStatus _migrationStatusForAnimation(
  RoomId roomId,
  CharacterId characterId,
  CharacterAnimationId animationId,
) {
  final tuning = _roomCharacterAnimationTuning(roomId, characterId);
  return tuning.migrationStatuses[animationId] ??
      AnimationMigrationStatus.pngOnly;
}

List<CharacterAnimationConfig> _buildRoomCharacterAnimationConfigs(
  RoomId roomId,
  CharacterId characterId,
) {
  return CharacterAnimationId.values
      .map(
        (animationId) =>
            _buildCharacterAnimationConfig(roomId, characterId, animationId),
      )
      .toList(growable: false);
}

final List<CharacterAnimationConfig> characterAnimationConfigs =
    <CharacterAnimationConfig>[
      ..._buildRoomCharacterAnimationConfigs(RoomId.bedroom, CharacterId.babak),
      ..._buildRoomCharacterAnimationConfigs(RoomId.baloon, CharacterId.babak),
      ..._buildRoomCharacterAnimationConfigs(
        RoomId.wardrobe,
        CharacterId.dudak,
      ),
      ..._buildRoomCharacterAnimationConfigs(RoomId.rocket, CharacterId.dudak),
    ];

String animationConfigKey(
  RoomId roomId,
  CharacterId characterId,
  CharacterAnimationId animationId,
) => '${roomId.name}_${characterId.name}_${animationId.name}';

final Map<String, CharacterAnimationConfig> characterAnimationConfigMap =
    <String, CharacterAnimationConfig>{
      for (final config in characterAnimationConfigs)
        animationConfigKey(
          config.roomId,
          config.characterId,
          config.animationId,
        ): config,
    };

CharacterAnimationConfig animationConfigFor(
  RoomId roomId,
  CharacterId characterId,
  CharacterAnimationId animationId,
) =>
    characterAnimationConfigMap[animationConfigKey(
      roomId,
      characterId,
      animationId,
    )]!;

List<CharacterAnimationConfig> animationConfigsWithStatus(
  AnimationMigrationStatus status,
) {
  return characterAnimationConfigs
      .where((config) => config.migrationStatus == status)
      .toList(growable: false);
}

Map<String, ReactionSoundConfig> buildReactionSoundConfig() {
  final config = <String, ReactionSoundConfig>{};

  for (final room in roomNavigationOrder) {
    final character = roomConfigMap[room]!.character;
    final tuning = _roomCharacterSoundTuning(room, character);
    for (final zone in TouchZone.values) {
      config[reactionConfigKey(room, character, zone)] =
          tuning.reactionSounds[zone] ??
          const ReactionSoundConfig(cues: <TimedSoundCue>[]);
    }
  }

  return config;
}

Map<String, AnimationEventSoundConfig> buildAnimationEventSoundConfig() {
  final config = <String, AnimationEventSoundConfig>{};

  for (final room in roomNavigationOrder) {
    final character = roomConfigMap[room]!.character;
    final tuning = _roomCharacterSoundTuning(room, character);
    config.addAll(tuning.animationEventSounds);
  }

  return config;
}

String reactionConfigKey(
  RoomId roomId,
  CharacterId character,
  TouchZone zone,
) => _reactionConfigKey(roomId, character, zone);

String _reactionConfigKey(
  RoomId roomId,
  CharacterId character,
  TouchZone zone,
) => '${roomId.name}_${character.name}_${zone.name}';

class SequenceClip {
  SequenceClip({
    required this.name,
    required this.assetDirectory,
    required this.frameCount,
    required this.fps,
    this.loop = false,
    List<AnimationFrameTiming>? frameTimings,
    List<AnimationTimelineEvent>? animationEvents,
    FrameSource? frameSourceOverride,
    this.fallbackFrameSource,
    this.allowPngFallback = false,
  }) : _frameTimings = frameTimings,
       _animationEvents = animationEvents,
       frameSource =
           frameSourceOverride ??
           PngSequenceFrameSource(
             assetDirectory: assetDirectory,
             frameCount: frameCount,
           );

  SequenceClip.spriteSheet({
    required this.name,
    required String imageAssetPath,
    required String metadataAssetPath,
    required String fallbackAssetDirectory,
    required this.frameCount,
    required this.fps,
    this.loop = false,
    List<AnimationFrameTiming>? frameTimings,
    List<AnimationTimelineEvent>? animationEvents,
    this.allowPngFallback = kDebugMode,
  }) : _frameTimings = frameTimings,
       _animationEvents = animationEvents,
       assetDirectory = fallbackAssetDirectory,
       frameSource = SpriteSheetFrameSource(
         imageAssetPath: imageAssetPath,
         metadataAssetPath: metadataAssetPath,
         frameCount: frameCount,
       ),
       fallbackFrameSource = PngSequenceFrameSource(
         assetDirectory: fallbackAssetDirectory,
         frameCount: frameCount,
       );

  final String name;
  final String assetDirectory;
  final int frameCount;
  final int fps;
  final bool loop;
  final FrameSource frameSource;
  final FrameSource? fallbackFrameSource;
  final bool allowPngFallback;
  final List<AnimationFrameTiming>? _frameTimings;
  final List<AnimationTimelineEvent>? _animationEvents;
  int? _resolvedFrameCount;
  List<AnimationFrameTiming>? _resolvedFrameTimings;
  List<AnimationTimelineEvent>? _resolvedAnimationEvents;

  int get effectiveFrameCount => playbackFrames.length;

  int get availableSourceFrameCount => _resolvedFrameCount ?? frameCount;

  int get totalDurationMs =>
      playbackFrames.fold<int>(0, (total, frame) => total + frame.durationMs);

  List<AnimationFrameTiming> get playbackFrames {
    final timings = _resolvedFrameTimings ?? _frameTimings;
    if (timings != null && timings.isNotEmpty) {
      return timings;
    }

    final defaultDurationMs = (1000 / fps).round();
    return <AnimationFrameTiming>[
      for (var index = 0; index < availableSourceFrameCount; index += 1)
        AnimationFrameTiming(frameIndex: index, durationMs: defaultDurationMs),
    ];
  }

  int sourceFrameIndexAt(int playbackIndex) {
    final timings = playbackFrames;
    if (timings.isEmpty) {
      return 0;
    }

    final clampedIndex = playbackIndex.clamp(0, timings.length - 1);
    return timings[clampedIndex].frameIndex.clamp(
      0,
      availableSourceFrameCount - 1,
    );
  }

  Duration frameDurationAt(int playbackIndex) {
    final timings = playbackFrames;
    if (timings.isEmpty) {
      return Duration(milliseconds: (1000 / fps).round());
    }

    final clampedIndex = playbackIndex.clamp(0, timings.length - 1);
    return Duration(milliseconds: timings[clampedIndex].durationMs);
  }

  List<AnimationTimelineEvent> get animationEvents {
    final events = _resolvedAnimationEvents ?? _animationEvents;
    if (events == null || events.isEmpty) {
      return const <AnimationTimelineEvent>[];
    }

    final sortedEvents = events.toList(growable: false)
      ..sort((left, right) => left.timeMs.compareTo(right.timeMs));
    return sortedEvents;
  }

  void resolveFrameCount(int discoveredFrameCount) {
    if (discoveredFrameCount <= 0) {
      return;
    }
    _resolvedFrameCount = discoveredFrameCount;
  }

  void resolveFrameTimings(List<AnimationFrameTiming> frameTimings) {
    if (frameTimings.isEmpty) {
      return;
    }
    _resolvedFrameTimings = frameTimings;
  }

  void resolveAnimationEvents(List<AnimationTimelineEvent> animationEvents) {
    if (animationEvents.isEmpty) {
      return;
    }
    _resolvedAnimationEvents = animationEvents;
  }

  List<String> get frames => <String>[
    for (var index = 0; index < effectiveFrameCount; index += 1)
      if ((fallbackFrameSource ?? frameSource).frameAssetPathAt(
            sourceFrameIndexAt(index),
          ) !=
          null)
        (fallbackFrameSource ?? frameSource).frameAssetPathAt(
          sourceFrameIndexAt(index),
        )!,
  ];
}

class CharacterDefinition {
  const CharacterDefinition({
    required this.id,
    required this.label,
    required this.idleBlink,
    required this.idleSway,
    required this.reactionHead,
    required this.reactionBelly,
    required this.reactionLegs,
  });

  final CharacterId id;
  final String label;
  final SequenceClip idleBlink;
  final SequenceClip idleSway;
  final SequenceClip reactionHead;
  final SequenceClip reactionBelly;
  final SequenceClip reactionLegs;

  SequenceClip reactionFor(TouchZone zone) {
    switch (zone) {
      case TouchZone.head:
        return reactionHead;
      case TouchZone.belly:
        return reactionBelly;
      case TouchZone.legs:
        return reactionLegs;
    }
  }

  List<SequenceClip> get preloadClips => <SequenceClip>[
    idleBlink,
    idleSway,
    reactionHead,
    reactionBelly,
    reactionLegs,
  ];
}

class TouchZoneLayout {
  const TouchZoneLayout({
    required this.zone,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final TouchZone zone;
  final double left;
  final double top;
  final double width;
  final double height;
}
