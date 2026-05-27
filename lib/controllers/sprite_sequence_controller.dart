import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_models.dart';

class SpriteSequenceController extends ChangeNotifier {
  SequenceClip? _clip;
  int _frameIndex = 0;
  int _elapsedLoopTimeMs = 0;
  int _currentFrameStartTimeMs = 0;
  Timer? _timer;
  VoidCallback? _onCompleted;
  void Function(AnimationTimelineEvent event)? _onEvent;
  final Set<int> _firedNonRepeatingEventIndices = <int>{};

  SequenceClip? get clip => _clip;
  int get frameIndex => _frameIndex;
  String? get currentFramePath {
    final activeClip = _clip;
    if (activeClip == null) {
      return null;
    }
    return activeClip.frameSource.frameAssetPathAt(
      activeClip.sourceFrameIndexAt(_frameIndex),
    );
  }

  void play(
    SequenceClip clip, {
    VoidCallback? onCompleted,
    void Function(AnimationTimelineEvent event)? onEvent,
  }) {
    stop();
    _clip = clip;
    _frameIndex = 0;
    _elapsedLoopTimeMs = 0;
    _currentFrameStartTimeMs = 0;
    _onCompleted = onCompleted;
    _onEvent = onEvent;
    _firedNonRepeatingEventIndices.clear();
    notifyListeners();

    if (clip.effectiveFrameCount <= 0) {
      _complete();
      return;
    }

    _emitLoopStartEvents(clip);
    _scheduleCurrentFrame();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void clear() {
    stop();
    _clip = null;
    _frameIndex = 0;
    _elapsedLoopTimeMs = 0;
    _currentFrameStartTimeMs = 0;
    _onCompleted = null;
    _onEvent = null;
    _firedNonRepeatingEventIndices.clear();
    notifyListeners();
  }

  void _complete() {
    _timer?.cancel();
    _timer = null;
    final callback = _onCompleted;
    _onCompleted = null;
    _onEvent = null;
    callback?.call();
  }

  void _scheduleCurrentFrame() {
    final activeClip = _clip;
    if (activeClip == null) {
      return;
    }
    final currentTimeMs = _elapsedLoopTimeMs;
    final frameEndTimeMs =
        _currentFrameStartTimeMs +
        activeClip.frameDurationAt(_frameIndex).inMilliseconds;
    final nextEventTimeMs = _nextEventTimeMs(
      activeClip,
      currentTimeMs,
      frameEndTimeMs,
    );
    final nextTickTimeMs = nextEventTimeMs ?? frameEndTimeMs;
    final waitMs = (nextTickTimeMs - currentTimeMs).clamp(0, frameEndTimeMs);

    _timer = Timer(Duration(milliseconds: waitMs), () {
      _advancePlayback(nextTickTimeMs, frameEndTimeMs);
    });
  }

  void _advancePlayback(int targetTimeMs, int frameEndTimeMs) {
    final activeClip = _clip;
    if (activeClip == null) {
      return;
    }

    final previousTimeMs = _elapsedLoopTimeMs;
    _elapsedLoopTimeMs = targetTimeMs;
    _emitEventsBetween(activeClip, previousTimeMs, targetTimeMs);

    if (targetTimeMs < frameEndTimeMs) {
      _scheduleCurrentFrame();
      return;
    }

    final nextIndex = _frameIndex + 1;
    if (nextIndex >= activeClip.effectiveFrameCount) {
      if (activeClip.loop) {
        _frameIndex = 0;
        _elapsedLoopTimeMs = 0;
        _currentFrameStartTimeMs = 0;
        notifyListeners();
        _emitLoopStartEvents(activeClip);
        _scheduleCurrentFrame();
        return;
      }

      _complete();
      return;
    }

    _frameIndex = nextIndex;
    _currentFrameStartTimeMs = frameEndTimeMs;
    notifyListeners();
    _scheduleCurrentFrame();
  }

  int? _nextEventTimeMs(
    SequenceClip clip,
    int currentTimeMs,
    int frameEndTimeMs,
  ) {
    int? nextEventTimeMs;

    for (var index = 0; index < clip.animationEvents.length; index += 1) {
      final event = clip.animationEvents[index];
      if (_shouldSkipEvent(index, event)) {
        continue;
      }
      if (event.timeMs <= currentTimeMs || event.timeMs > frameEndTimeMs) {
        continue;
      }
      nextEventTimeMs = nextEventTimeMs == null
          ? event.timeMs
          : (event.timeMs < nextEventTimeMs ? event.timeMs : nextEventTimeMs);
    }

    return nextEventTimeMs;
  }

  void _emitEventsBetween(SequenceClip clip, int startTimeMs, int endTimeMs) {
    for (var index = 0; index < clip.animationEvents.length; index += 1) {
      final event = clip.animationEvents[index];
      if (_shouldSkipEvent(index, event)) {
        continue;
      }
      if (event.timeMs <= startTimeMs || event.timeMs > endTimeMs) {
        continue;
      }
      _fireEvent(index, event);
    }
  }

  void _emitLoopStartEvents(SequenceClip clip) {
    for (var index = 0; index < clip.animationEvents.length; index += 1) {
      final event = clip.animationEvents[index];
      if (_shouldSkipEvent(index, event)) {
        continue;
      }
      if (event.timeMs > 0) {
        continue;
      }
      _fireEvent(index, event);
    }
  }

  bool _shouldSkipEvent(int index, AnimationTimelineEvent event) {
    return !event.repeatEachLoop &&
        _firedNonRepeatingEventIndices.contains(index);
  }

  void _fireEvent(int index, AnimationTimelineEvent event) {
    if (!event.repeatEachLoop) {
      _firedNonRepeatingEventIndices.add(index);
    }
    _onEvent?.call(event);
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
