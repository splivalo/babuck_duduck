import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/app_models.dart';

class SoundManager {
  SoundManager({
    Map<String, ReactionSoundConfig>? reactionConfig,
    Map<String, AnimationEventSoundConfig>? animationEventConfig,
  }) : _reactionConfig = reactionConfig ?? buildReactionSoundConfig(),
       _animationEventConfig =
           animationEventConfig ?? buildAnimationEventSoundConfig(),
       _channelRequestTokens = <AudioChannel, int>{
         for (final channel in AudioChannel.values) channel: 0,
       };

  final Set<String> _preloadedAssets = <String>{};
  final Map<String, ReactionSoundConfig> _reactionConfig;
  final Map<String, AnimationEventSoundConfig> _animationEventConfig;
  final Map<String, AudioPlayer> _cuePlayers = <String, AudioPlayer>{};
  final Map<String, Future<AudioPlayer?>> _cuePlayerPreparations =
      <String, Future<AudioPlayer?>>{};
  final Map<AudioChannel, AudioPlayer?> _activeChannelPlayer =
      <AudioChannel, AudioPlayer?>{
        for (final channel in AudioChannel.values) channel: null,
      };
  final Map<AudioChannel, int> _channelRequestTokens;
  final Map<String, DateTime> _lastReusableCuePlayAt = <String, DateTime>{};
  final Map<String, String> _resolvedAssetPaths = <String, String>{};

  static const Duration _reusableEventReplayGuard = Duration(milliseconds: 160);

  ReactionSoundConfig reactionConfig(
    RoomId roomId,
    CharacterId character,
    TouchZone zone,
  ) {
    final config = _reactionConfig[reactionConfigKey(roomId, character, zone)];
    return config ?? const ReactionSoundConfig(cues: <TimedSoundCue>[]);
  }

  AnimationEventSoundConfig animationEventConfig(String eventName) {
    return _animationEventConfig[eventName] ??
        const AnimationEventSoundConfig(cues: <TimedSoundCue>[]);
  }

  Future<void> playReaction(
    RoomId roomId,
    CharacterId character,
    TouchZone zone,
  ) async {
    final config = reactionConfig(roomId, character, zone);
    await Future.wait(
      config.cues.map(
        (cue) => play(
          channel: AudioChannel.sfx,
          cue: cue,
          playbackBehavior: config.playbackBehavior,
        ),
      ),
    );
  }

  Future<void> playAnimationEvent(String eventName) async {
    final config = animationEventConfig(eventName);
    final channel = audioChannelForAnimationEvent(eventName);
    await Future.wait(
      config.cues.map(
        (cue) => switch (channel) {
          AudioChannel.room => playRoomCue(
            cue,
            playbackBehavior: config.playbackBehavior,
          ),
          _ => play(
            channel: channel,
            cue: cue,
            playbackBehavior: config.playbackBehavior,
          ),
        },
      ),
    );
  }

  Future<void> playRoomCue(
    TimedSoundCue cue, {
    SoundPlaybackBehavior playbackBehavior = SoundPlaybackBehavior.restart,
  }) {
    return play(
      channel: AudioChannel.room,
      cue: cue,
      playbackBehavior: playbackBehavior,
    );
  }

  @visibleForTesting
  AudioChannel audioChannelForAnimationEvent(String eventName) {
    return _isRoomScopedAnimationEvent(eventName)
        ? AudioChannel.room
        : AudioChannel.idle;
  }

  @visibleForTesting
  bool channelPreempts(AudioChannel contender, AudioChannel active) {
    return _channelPriority(contender) > _channelPriority(active);
  }

  Future<void> preloadForCharacter(RoomId roomId, CharacterId character) async {
    final cues = <TimedSoundCue>[
      for (final zone in TouchZone.values)
        ...reactionConfig(roomId, character, zone).cues,
      for (final config in _animationEventConfig.values) ...config.cues,
    ];

    for (final cue in cues) {
      unawaited(_ensureCuePlayer(cue));
    }
  }

  Future<void> play({
    required AudioChannel channel,
    required TimedSoundCue cue,
    required SoundPlaybackBehavior playbackBehavior,
  }) async {
    final requestToken = _nextChannelRequestToken(channel);

    if (cue.delay > Duration.zero) {
      await Future<void>.delayed(cue.delay);
    }

    if (_channelRequestTokens[channel] != requestToken) {
      return;
    }

    final assetPath = await _resolvePlayableAssetPath(cue.assetPath);
    if (_channelRequestTokens[channel] != requestToken) {
      return;
    }

    final now = DateTime.now();
    final lastPlayAt = _lastReusableCuePlayAt[assetPath];
    if (playbackBehavior == SoundPlaybackBehavior.guardedRestart &&
        lastPlayAt != null &&
        now.difference(lastPlayAt) < _reusableEventReplayGuard) {
      return;
    }
    _lastReusableCuePlayAt[assetPath] = now;

    await _interruptLowerPriorityChannels(channel);
    if (_channelRequestTokens[channel] != requestToken) {
      return;
    }

    final player = await _ensureCuePlayer(cue);
    if (player == null || _channelRequestTokens[channel] != requestToken) {
      return;
    }

    final previousActive = _activeChannelPlayer[channel];
    if (previousActive != null && previousActive != player) {
      try {
        await previousActive.stop();
      } catch (_) {}
    }
    _activeChannelPlayer[channel] = player;

    try {
      await player.stop();
      if (_channelRequestTokens[channel] != requestToken) {
        return;
      }

      await player.setPlaybackRate(cue.playbackRate);
      if (_channelRequestTokens[channel] != requestToken) {
        return;
      }

      if (cue.startOffset > Duration.zero) {
        await player.seek(cue.startOffset);
        if (_channelRequestTokens[channel] != requestToken) {
          return;
        }
      }

      await player.resume();
    } catch (_) {
      return;
    }
  }

  Future<AudioPlayer?> _ensureCuePlayer(TimedSoundCue cue) async {
    final assetPath = await _resolvePlayableAssetPath(cue.assetPath);
    final cached = _cuePlayers[assetPath];
    if (cached != null) {
      return cached;
    }

    final inFlight = _cuePlayerPreparations[assetPath];
    if (inFlight != null) {
      return inFlight;
    }

    final preparation = _prepareCuePlayer(assetPath);
    _cuePlayerPreparations[assetPath] = preparation;
    final player = await preparation;
    _cuePlayerPreparations.remove(assetPath);
    if (player != null) {
      _cuePlayers[assetPath] = player;
    }
    return player;
  }

  Future<AudioPlayer?> _prepareCuePlayer(String assetPath) async {
    final player = AudioPlayer();
    try {
      await player.setReleaseMode(ReleaseMode.stop);
    } catch (_) {}
    try {
      await player.setSource(AssetSource(_assetSourcePath(assetPath)));
    } catch (_) {
      try {
        await player.dispose();
      } catch (_) {}
      return null;
    }
    return player;
  }

  int _nextChannelRequestToken(AudioChannel channel) {
    final nextToken = (_channelRequestTokens[channel] ?? 0) + 1;
    _channelRequestTokens[channel] = nextToken;
    return nextToken;
  }

  Future<void> _interruptLowerPriorityChannels(AudioChannel channel) async {
    for (final lowerChannel in AudioChannel.values) {
      if (_channelPriority(lowerChannel) >= _channelPriority(channel)) {
        continue;
      }

      _nextChannelRequestToken(lowerChannel);
      final activePlayer = _activeChannelPlayer[lowerChannel];
      if (activePlayer == null) {
        continue;
      }
      try {
        await activePlayer.stop();
      } catch (_) {}
      _activeChannelPlayer[lowerChannel] = null;
    }
  }

  bool _isRoomScopedAnimationEvent(String eventName) {
    for (final room in RoomId.values) {
      if (eventName.endsWith('_${room.name}')) {
        return true;
      }
    }

    return false;
  }

  int _channelPriority(AudioChannel channel) {
    return switch (channel) {
      AudioChannel.idle => 0,
      AudioChannel.sfx => 1,
      AudioChannel.room => 2,
    };
  }

  String _assetSourcePath(String assetPath) {
    return assetPath.replaceFirst('assets/', '');
  }

  Future<String> _resolvePlayableAssetPath(String assetPath) async {
    final cachedPath = _resolvedAssetPaths[assetPath];
    if (cachedPath != null) {
      return cachedPath;
    }

    final wavPath = assetPath.endsWith('.mp3')
        ? '${assetPath.substring(0, assetPath.length - 4)}.wav'
        : null;

    final candidates = <String>[
      if (wavPath case final String wavAssetPath) wavAssetPath,
      assetPath,
    ];

    for (final candidate in candidates) {
      if (_preloadedAssets.contains(candidate)) {
        _resolvedAssetPaths[assetPath] = candidate;
        return candidate;
      }

      try {
        await rootBundle.load(candidate);
        _preloadedAssets.add(candidate);
        _resolvedAssetPaths[assetPath] = candidate;
        return candidate;
      } catch (_) {}
    }

    _resolvedAssetPaths[assetPath] = assetPath;
    return assetPath;
  }

  Future<void> stopAllRoomAudio() async {
    _lastReusableCuePlayAt.clear();

    for (final channel in AudioChannel.values) {
      _nextChannelRequestToken(channel);
      final activePlayer = _activeChannelPlayer[channel];
      if (activePlayer == null) {
        continue;
      }
      try {
        await activePlayer.stop();
      } catch (_) {}
      _activeChannelPlayer[channel] = null;
    }
  }

  void dispose() {
    _lastReusableCuePlayAt.clear();
    _resolvedAssetPaths.clear();
    for (final entry in _activeChannelPlayer.entries) {
      _activeChannelPlayer[entry.key] = null;
    }
    for (final player in _cuePlayers.values) {
      unawaited(player.dispose());
    }
    _cuePlayers.clear();
    _cuePlayerPreparations.clear();
  }
}

enum AudioChannel { idle, sfx, room }
