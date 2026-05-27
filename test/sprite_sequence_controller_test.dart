import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:babuck_duduck/controllers/sprite_sequence_controller.dart';
import 'package:babuck_duduck/models/app_models.dart';

void main() {
  test('holds sparse playback frames for configured durations', () {
    final controller = SpriteSequenceController();
    final clip = SequenceClip(
      name: 'blink_sparse',
      assetDirectory: 'assets/characters/test/blink',
      frameCount: 4,
      fps: 12,
      frameTimings: const <AnimationFrameTiming>[
        AnimationFrameTiming(frameIndex: 0, durationMs: 1800),
        AnimationFrameTiming(frameIndex: 1, durationMs: 40),
        AnimationFrameTiming(frameIndex: 2, durationMs: 60),
        AnimationFrameTiming(frameIndex: 3, durationMs: 40),
      ],
    );

    var didComplete = false;

    fakeAsync((async) {
      controller.play(clip, onCompleted: () => didComplete = true);

      expect(controller.frameIndex, 0);
      expect(didComplete, isFalse);

      async.elapse(const Duration(milliseconds: 1799));
      expect(controller.frameIndex, 0);
      expect(didComplete, isFalse);

      async.elapse(const Duration(milliseconds: 1));
      expect(controller.frameIndex, 1);

      async.elapse(const Duration(milliseconds: 40));
      expect(controller.frameIndex, 2);

      async.elapse(const Duration(milliseconds: 60));
      expect(controller.frameIndex, 3);
      expect(didComplete, isFalse);

      async.elapse(const Duration(milliseconds: 39));
      expect(controller.frameIndex, 3);
      expect(didComplete, isFalse);

      async.elapse(const Duration(milliseconds: 1));
      expect(didComplete, isTrue);
    });
  });

  test('keeps fixed-FPS clips working without explicit timing metadata', () {
    final controller = SpriteSequenceController();
    final clip = SequenceClip(
      name: 'legacy_fixed_fps',
      assetDirectory: 'assets/characters/test/legacy',
      frameCount: 3,
      fps: 10,
    );

    fakeAsync((async) {
      controller.play(clip);

      expect(controller.frameIndex, 0);

      async.elapse(const Duration(milliseconds: 99));
      expect(controller.frameIndex, 0);

      async.elapse(const Duration(milliseconds: 1));
      expect(controller.frameIndex, 1);

      async.elapse(const Duration(milliseconds: 100));
      expect(controller.frameIndex, 2);
    });
  });

  test('maps playback timing to unique source frame paths', () {
    final controller = SpriteSequenceController();
    final clip = SequenceClip(
      name: 'sparse_source_map',
      assetDirectory: 'assets/characters/test/sparse',
      frameCount: 6,
      fps: 12,
      frameTimings: const <AnimationFrameTiming>[
        AnimationFrameTiming(frameIndex: 0, durationMs: 800),
        AnimationFrameTiming(frameIndex: 4, durationMs: 50),
        AnimationFrameTiming(frameIndex: 2, durationMs: 50),
      ],
    );

    fakeAsync((async) {
      controller.play(clip);

      expect(
        controller.currentFramePath,
        'assets/characters/test/sparse/0001.png',
      );

      async.elapse(const Duration(milliseconds: 800));
      expect(
        controller.currentFramePath,
        'assets/characters/test/sparse/0005.png',
      );

      async.elapse(const Duration(milliseconds: 50));
      expect(
        controller.currentFramePath,
        'assets/characters/test/sparse/0003.png',
      );
    });
  });

  test('fires timeline events when elapsed playback crosses event time', () {
    final controller = SpriteSequenceController();
    final clip = SequenceClip(
      name: 'event_sparse',
      assetDirectory: 'assets/characters/test/events',
      frameCount: 2,
      fps: 12,
      frameTimings: const <AnimationFrameTiming>[
        AnimationFrameTiming(frameIndex: 0, durationMs: 1000),
        AnimationFrameTiming(frameIndex: 1, durationMs: 100),
      ],
      animationEvents: const <AnimationTimelineEvent>[
        AnimationTimelineEvent(name: 'idle_swing_dudak', timeMs: 820),
      ],
    );
    final firedEvents = <String>[];

    fakeAsync((async) {
      controller.play(clip, onEvent: (event) => firedEvents.add(event.name));

      async.elapse(const Duration(milliseconds: 819));
      expect(firedEvents, isEmpty);
      expect(controller.frameIndex, 0);

      async.elapse(const Duration(milliseconds: 1));
      expect(firedEvents, <String>['idle_swing_dudak']);
      expect(controller.frameIndex, 0);

      async.elapse(const Duration(milliseconds: 179));
      expect(controller.frameIndex, 0);

      async.elapse(const Duration(milliseconds: 1));
      expect(controller.frameIndex, 1);
      expect(firedEvents, hasLength(1));
    });
  });

  test('looping events fire once per loop by default', () {
    final controller = SpriteSequenceController();
    final clip = SequenceClip(
      name: 'looping_event',
      assetDirectory: 'assets/characters/test/loop',
      frameCount: 1,
      fps: 10,
      loop: true,
      frameTimings: const <AnimationFrameTiming>[
        AnimationFrameTiming(frameIndex: 0, durationMs: 100),
      ],
      animationEvents: const <AnimationTimelineEvent>[
        AnimationTimelineEvent(name: 'pulse', timeMs: 50),
      ],
    );
    final firedEvents = <String>[];

    fakeAsync((async) {
      controller.play(clip, onEvent: (event) => firedEvents.add(event.name));

      async.elapse(const Duration(milliseconds: 50));
      async.elapse(const Duration(milliseconds: 100));
      async.elapse(const Duration(milliseconds: 50));

      expect(firedEvents, <String>['pulse', 'pulse']);
    });
  });

  test('non-repeating looping events do not fire more than once', () {
    final controller = SpriteSequenceController();
    final clip = SequenceClip(
      name: 'looping_non_repeat_event',
      assetDirectory: 'assets/characters/test/non_repeat',
      frameCount: 1,
      fps: 10,
      loop: true,
      frameTimings: const <AnimationFrameTiming>[
        AnimationFrameTiming(frameIndex: 0, durationMs: 100),
      ],
      animationEvents: const <AnimationTimelineEvent>[
        AnimationTimelineEvent(
          name: 'intro_only',
          timeMs: 50,
          repeatEachLoop: false,
        ),
      ],
    );
    final firedEvents = <String>[];

    fakeAsync((async) {
      controller.play(clip, onEvent: (event) => firedEvents.add(event.name));

      async.elapse(const Duration(milliseconds: 50));
      async.elapse(const Duration(milliseconds: 100));
      async.elapse(const Duration(milliseconds: 100));

      expect(firedEvents, <String>['intro_only']);
    });
  });
}
