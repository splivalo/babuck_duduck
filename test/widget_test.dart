// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:math';

import 'package:babuck_duduck/app.dart';
import 'package:babuck_duduck/features/main_room/main_room_screen.dart';
import 'package:babuck_duduck/managers/character_manager.dart';
import 'package:babuck_duduck/models/app_models.dart';
import 'package:babuck_duduck/services/sound_manager.dart';
import 'package:babuck_duduck/widgets/room_navigation_bar.dart';
import 'package:babuck_duduck/widgets/sprite_sequence_player.dart';

Future<void> pumpUntilMainRoom(WidgetTester tester) async {
  for (var index = 0; index < 80; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find
        .byKey(const ValueKey<String>('room-drawer-trigger'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
  }

  fail('Main room did not appear after waiting for startup preload.');
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  required String description,
}) async {
  for (var index = 0; index < 80; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  fail('$description did not appear after waiting for preload.');
}

Future<void> pumpUntilClipLoaded(
  WidgetTester tester,
  Finder playerFinder, {
  required String description,
}) async {
  for (var index = 0; index < 80; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (playerFinder.evaluate().isEmpty) {
      continue;
    }

    final player = tester.widget<SpriteSequencePlayer>(playerFinder);
    if (player.controller.clip != null) {
      return;
    }
  }

  fail('$description clip did not start after waiting for preload.');
}

Future<void> pumpUntilRoomSelected(
  WidgetTester tester,
  RoomId room, {
  required String description,
}) async {
  for (var index = 0; index < 80; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    final mainRoom = tester.widget<MainRoomScreen>(find.byType(MainRoomScreen));
    if (mainRoom.roomManager.currentRoom == room) {
      return;
    }
  }

  fail('$description did not switch after waiting for preload.');
}

void completeRoomInitializationForTest(
  CharacterManager manager, {
  required String source,
}) {
  manager.markRoomAssetsReady(source: '$source.assetsReady');
  manager.startIdleLoop(
    source: '$source.idleStart',
    forceRestart: true,
    allowWhileInitializing: true,
  );
  manager.markCharacterAttached(source: '$source.characterAttached');
  manager.completeRoomInitialization(source: '$source.done');
}

void main() {
  test('rocket room uses Dudak atlas wiring without PNG fallback', () {
    expect(roomConfigMap[RoomId.rocket]!.character, CharacterId.dudak);

    final dudakIdleBlink = animationConfigFor(
      RoomId.rocket,
      CharacterId.dudak,
      CharacterAnimationId.idleBlink,
    ).toSequenceClip();

    expect(dudakIdleBlink.frameSource, isA<SpriteSheetFrameSource>());
    expect(dudakIdleBlink.fallbackFrameSource, isA<PngSequenceFrameSource>());
    expect(dudakIdleBlink.allowPngFallback, isFalse);
  });

  test('rocket room uses faster explicit blink timing', () {
    final dudakIdleBlink = animationConfigFor(
      RoomId.rocket,
      CharacterId.dudak,
      CharacterAnimationId.idleBlink,
    ).toSequenceClip();

    final playbackFrames = dudakIdleBlink.playbackFrames;

    expect(playbackFrames.first.frameIndex, 0);
    expect(playbackFrames.first.durationMs, 1500);
    expect(playbackFrames[1].frameIndex, 1);
    expect(playbackFrames[1].durationMs, 16);
    expect(playbackFrames.last.frameIndex, 8);
    expect(playbackFrames.last.durationMs, 40);
  });

  test('dudak idle sway exposes dudak swing event sound wiring', () {
    final dudakIdleSway = animationConfigFor(
      RoomId.wardrobe,
      CharacterId.dudak,
      CharacterAnimationId.idleSway,
    );
    final soundManager = SoundManager();

    expect(dudakIdleSway.animationEvents, isNotNull);
    expect(
      dudakIdleSway.animationEvents!.map((event) => event.name),
      contains('idle_swing_dudak_wardrobe'),
    );
    expect(
      soundManager
          .animationEventConfig('idle_swing_dudak_wardrobe')
          .cues
          .single
          .assetPath,
      'assets/sounds/dudak/giggle.wav',
    );
    expect(
      soundManager
          .animationEventConfig('idle_swing_dudak_wardrobe')
          .playbackBehavior,
      SoundPlaybackBehavior.guardedRestart,
    );
  });

  test('reaction sounds restart from centralized playback policy', () {
    final soundManager = SoundManager();

    expect(
      soundManager
          .reactionConfig(RoomId.rocket, CharacterId.dudak, TouchZone.belly)
          .playbackBehavior,
      SoundPlaybackBehavior.restart,
    );
  });

  test('room-scoped gameplay audio resolves to room channel with priority', () {
    final soundManager = SoundManager();

    expect(
      soundManager.audioChannelForAnimationEvent('idle_swing_dudak_wardrobe'),
      AudioChannel.room,
    );
    expect(
      soundManager.audioChannelForAnimationEvent('idle_swing_dudak'),
      AudioChannel.idle,
    );
    expect(
      soundManager.channelPreempts(AudioChannel.room, AudioChannel.sfx),
      isTrue,
    );
    expect(
      soundManager.channelPreempts(AudioChannel.sfx, AudioChannel.idle),
      isTrue,
    );
    expect(
      soundManager.channelPreempts(AudioChannel.idle, AudioChannel.room),
      isFalse,
    );
  });

  test(
    'wardrobe Dudak head uses room-specific sound while other tap zones stay silent',
    () {
      final soundManager = SoundManager();

      expect(
        soundManager
            .reactionConfig(RoomId.wardrobe, CharacterId.dudak, TouchZone.head)
            .cues
            .single
            .assetPath,
        'assets/sounds/dudak/noo.wav',
      );
      expect(
        soundManager
            .reactionConfig(RoomId.wardrobe, CharacterId.dudak, TouchZone.head)
            .playbackBehavior,
        SoundPlaybackBehavior.restart,
      );
      expect(
        soundManager
            .reactionConfig(RoomId.wardrobe, CharacterId.dudak, TouchZone.belly)
            .cues,
        isEmpty,
      );
      expect(
        soundManager
            .reactionConfig(RoomId.wardrobe, CharacterId.dudak, TouchZone.legs)
            .cues,
        isEmpty,
      );
    },
  );

  test('room switch to table clears stale clip then starts Babak idle', () {
    final manager = CharacterManager(soundManager: SoundManager());

    manager.sequenceController.play(
      animationConfigFor(
        RoomId.bedroom,
        CharacterId.babak,
        CharacterAnimationId.idleBlink,
      ).toSequenceClip(),
    );

    expect(manager.sequenceController.clip, isNotNull);

    final didChange = manager.syncRoom(RoomId.baloon);

    expect(didChange, isTrue);
    expect(manager.sequenceController.clip, isNull);

    completeRoomInitializationForTest(
      manager,
      source: 'test.roomSwitchToTable',
    );

    expect(manager.sequenceController.clip, isNotNull);
    expect(manager.sequenceController.clip!.name, contains('idle_'));
    expect(manager.hasVisibleCharacter, isTrue);

    manager.dispose();
  });

  test('same character can resolve room-specific animation configs', () {
    final wardrobeIdleBlink = animationConfigFor(
      RoomId.wardrobe,
      CharacterId.dudak,
      CharacterAnimationId.idleBlink,
    );
    final rocketIdleBlink = animationConfigFor(
      RoomId.rocket,
      CharacterId.dudak,
      CharacterAnimationId.idleBlink,
    );

    expect(wardrobeIdleBlink.roomId, RoomId.wardrobe);
    expect(rocketIdleBlink.roomId, RoomId.rocket);
    expect(wardrobeIdleBlink.characterId, CharacterId.dudak);
    expect(rocketIdleBlink.characterId, CharacterId.dudak);
  });

  test('repeated belly taps restart Dudak reaction immediately', () {
    fakeAsync((async) {
      final manager = CharacterManager(
        soundManager: SoundManager(
          reactionConfig: <String, ReactionSoundConfig>{},
          animationEventConfig: <String, AnimationEventSoundConfig>{},
        ),
      );

      manager.syncRoom(RoomId.rocket);
      completeRoomInitializationForTest(
        manager,
        source: 'test.repeatedBellyTaps.roomInit',
      );
      manager.handleZoneTap(TouchZone.belly);
      expect(manager.sequenceController.clip, isNotNull);
      expect(manager.sequenceController.clip!.name, 'reaction_belly');
      expect(manager.sequenceController.frameIndex, 0);

      async.elapse(const Duration(milliseconds: 160));
      expect(manager.sequenceController.frameIndex, greaterThan(0));

      manager.handleZoneTap(TouchZone.belly);
      expect(manager.sequenceController.clip, isNotNull);
      expect(manager.sequenceController.clip!.name, 'reaction_belly');
      expect(manager.sequenceController.frameIndex, 0);

      manager.dispose();
    });
  });

  test('table room now renders Babak when baloon png frames exist', () {
    expect(roomHasReadyCharacterAssets(RoomId.baloon), isTrue);
    expect(roomHasReadyCharacterAssets(RoomId.rocket), isTrue);

    final manager = CharacterManager(soundManager: SoundManager());
    manager.syncRoom(RoomId.baloon);
    completeRoomInitializationForTest(manager, source: 'test.tableRoomRender');

    expect(manager.hasVisibleCharacter, isTrue);
    expect(manager.sequenceController.clip, isNotNull);
    expect(manager.sequenceController.clip!.name, contains('idle_'));

    manager.dispose();
  });

  test('table room uses central blink timing control', () {
    final config = animationConfigFor(
      RoomId.baloon,
      CharacterId.babak,
      CharacterAnimationId.idleBlink,
    );

    final playbackFrames = config.toSequenceClip().playbackFrames;

    expect(playbackFrames.first.frameIndex, 0);
    expect(playbackFrames.first.durationMs, 75);
    expect(
      playbackFrames.take(20).every((frame) => frame.frameIndex == 0),
      isTrue,
    );
  });

  test('Babak rooms use explicit central blink timing control', () {
    final bedroomFrames = animationConfigFor(
      RoomId.bedroom,
      CharacterId.babak,
      CharacterAnimationId.idleBlink,
    ).toSequenceClip().playbackFrames;
    final tableFrames = animationConfigFor(
      RoomId.baloon,
      CharacterId.babak,
      CharacterAnimationId.idleBlink,
    ).toSequenceClip().playbackFrames;

    expect(bedroomFrames.first.frameIndex, 0);
    expect(bedroomFrames.first.durationMs, 75);
    expect(tableFrames.first.frameIndex, 0);
    expect(tableFrames.first.durationMs, 75);
    expect(
      bedroomFrames.take(20).every((frame) => frame.frameIndex == 0),
      isTrue,
    );
    expect(
      tableFrames.take(20).every((frame) => frame.frameIndex == 0),
      isTrue,
    );
  });

  test('redundant idle start does not restart active idle clip', () {
    fakeAsync((async) {
      final manager = CharacterManager(
        soundManager: SoundManager(),
        random: Random(1234),
      );

      manager.syncRoom(RoomId.baloon);
      completeRoomInitializationForTest(manager, source: 'test.initialIdle');
      async.elapse(const Duration(milliseconds: 250));

      final clipBeforeRestart = manager.sequenceController.clip;
      final frameIndexBeforeRestart = manager.sequenceController.frameIndex;

      expect(clipBeforeRestart, isNotNull);
      expect(frameIndexBeforeRestart, greaterThan(0));

      manager.startIdleLoop(source: 'test.redundantIdleStart');

      expect(manager.sequenceController.clip, same(clipBeforeRestart));
      expect(manager.sequenceController.frameIndex, frameIndexBeforeRestart);

      manager.dispose();
    });
  });

  test('idle deck keeps 7/3 distribution without back-to-back sway', () {
    final manager = CharacterManager(
      soundManager: SoundManager(),
      random: Random(1234),
    );

    manager.syncRoom(RoomId.wardrobe);

    final idleNames = List<String>.generate(
      30,
      (_) => manager.debugTakeNextIdleClip().name,
    );

    for (var index = 1; index < idleNames.length; index += 1) {
      expect(
        idleNames[index] == 'idle_sway' && idleNames[index - 1] == 'idle_sway',
        isFalse,
      );
    }

    for (var start = 0; start < idleNames.length; start += 10) {
      final batch = idleNames.sublist(start, start + 10);
      expect(batch.where((name) => name == 'idle_blink'), hasLength(7));
      expect(batch.where((name) => name == 'idle_sway'), hasLength(3));
    }

    manager.dispose();
  });

  test('room entry always starts idle on blink after prior sway', () {
    final manager = CharacterManager(
      soundManager: SoundManager(),
      random: Random(1234),
    );

    manager.syncRoom(RoomId.wardrobe);

    var sawSway = false;
    for (var index = 0; index < 20; index += 1) {
      if (manager.debugTakeNextIdleClip().name == 'idle_sway') {
        sawSway = true;
        break;
      }
    }

    expect(sawSway, isTrue);

    manager.syncRoom(RoomId.rocket);

    expect(manager.debugTakeNextIdleClip().name, 'idle_blink');

    manager.dispose();
  });

  test('room entry gate forces executed idle to blink', () {
    final manager = CharacterManager(
      soundManager: SoundManager(),
      random: Random(1234),
    );

    manager.syncRoom(RoomId.wardrobe);

    var sawSway = false;
    for (var index = 0; index < 20; index += 1) {
      if (manager.debugTakeNextIdleClip().name == 'idle_sway') {
        sawSway = true;
        break;
      }
    }

    expect(sawSway, isTrue);

    manager.syncRoom(RoomId.rocket);
    manager.startIdleLoop(
      source: 'test.roomEntryExecutionGate',
      allowWhileInitializing: true,
    );

    expect(manager.sequenceController.clip?.name, 'idle_blink');

    manager.dispose();
  });

  testWidgets('shows splash content on launch', (WidgetTester tester) async {
    await tester.pumpWidget(const BabuckDuduckApp());

    final splashImage = tester.widget<Image>(
      find.byKey(const ValueKey<String>('app-splash-image')),
    );

    expect(splashImage.image, isA<AssetImage>());
    expect((splashImage.image as AssetImage).assetName, 'assets/ui/splash.jpg');
    expect(
      find.byKey(const ValueKey<String>('app-splash-progress')),
      findsOneWidget,
    );

    await pumpUntilMainRoom(tester);
  });

  testWidgets('opens main room directly after splash', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BabuckDuduckApp());
    await pumpUntilMainRoom(tester);

    expect(find.text('Choose a friend'), findsNothing);
    expect(find.text('Tap the lamp'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('room-drawer-trigger')),
      findsOneWidget,
    );
  });

  testWidgets('can switch to rocket room from the main room', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BabuckDuduckApp());
    await pumpUntilMainRoom(tester);

    await tester.tap(find.byKey(const ValueKey<String>('room-drawer-trigger')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('room-drawer-item-rocket')),
    );
    await tester.pump();

    expect(find.text('Tap the lamp'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('room-drawer-trigger')),
      findsOneWidget,
    );
  });

  testWidgets('rocket room renders a Dudak rocket png frame', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BabuckDuduckApp());
    await pumpUntilMainRoom(tester);

    await tester.tap(find.byKey(const ValueKey<String>('room-drawer-trigger')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('room-drawer-item-rocket')),
    );
    await pumpUntilClipLoaded(
      tester,
      find.byType(SpriteSequencePlayer),
      description: 'Rocket sprite player',
    );

    final player = tester.widget<SpriteSequencePlayer>(
      find.byType(SpriteSequencePlayer),
    );
    expect(player.controller.clip, isNotNull);
    expect(player.controller.clip!.name, contains('idle_'));
  });

  testWidgets('switching from rocket to bedroom clears stale rocket frame', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BabuckDuduckApp());
    await pumpUntilMainRoom(tester);

    await tester.tap(find.byKey(const ValueKey<String>('room-drawer-trigger')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('room-drawer-item-rocket')),
    );
    await pumpUntilClipLoaded(
      tester,
      find.byType(SpriteSequencePlayer),
      description: 'Rocket sprite player',
    );

    tester
        .widget<RoomNavigationBar>(find.byType(RoomNavigationBar))
        .onRoomSelected(RoomId.bedroom);
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('bedroom-lamp-target')),
      description: 'Bedroom lamp target',
    );

    final assetNames = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>()
        .map((provider) => provider.assetName)
        .toList(growable: false);

    expect(
      assetNames.where((name) => name.startsWith('assets/characters/')),
      isEmpty,
    );
  });

  testWidgets('can switch rooms more than once in a row', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BabuckDuduckApp());
    await pumpUntilMainRoom(tester);

    await tester.tap(find.byKey(const ValueKey<String>('room-drawer-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('room-drawer-item-rocket')),
    );
    await pumpUntilClipLoaded(
      tester,
      find.byType(SpriteSequencePlayer),
      description: 'Rocket sprite player',
    );

    final navigationBar = tester.widget<RoomNavigationBar>(
      find.byType(RoomNavigationBar),
    );
    navigationBar.onRoomSelected(RoomId.bedroom);
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('bedroom-lamp-target')),
      description: 'Bedroom lamp target',
    );
    await tester.pump(const Duration(milliseconds: 1000));

    final updatedMainRoom = tester.widget<MainRoomScreen>(
      find.byType(MainRoomScreen),
    );
    expect(updatedMainRoom.roomManager.currentRoom, RoomId.bedroom);

    tester
        .widget<RoomNavigationBar>(find.byType(RoomNavigationBar))
        .onRoomSelected(RoomId.wardrobe);
    await pumpUntilRoomSelected(
      tester,
      RoomId.wardrobe,
      description: 'Wardrobe room',
    );

    final finalMainRoom = tester.widget<MainRoomScreen>(
      find.byType(MainRoomScreen),
    );
    expect(finalMainRoom.roomManager.currentRoom, RoomId.wardrobe);
  });

  testWidgets(
    'launch then rocket to wardrobe keeps wardrobe character visible',
    (WidgetTester tester) async {
      await tester.pumpWidget(const BabuckDuduckApp());
      await pumpUntilMainRoom(tester);

      tester
          .widget<RoomNavigationBar>(find.byType(RoomNavigationBar))
          .onRoomSelected(RoomId.rocket);
      await pumpUntilRoomSelected(
        tester,
        RoomId.rocket,
        description: 'Rocket room',
      );

      tester
          .widget<RoomNavigationBar>(find.byType(RoomNavigationBar))
          .onRoomSelected(RoomId.wardrobe);
      await pumpUntilRoomSelected(
        tester,
        RoomId.wardrobe,
        description: 'Wardrobe room',
      );
      await pumpUntilClipLoaded(
        tester,
        find.byType(SpriteSequencePlayer),
        description: 'Wardrobe sprite player',
      );

      for (var index = 0; index < 8; index += 1) {
        await tester.pump(const Duration(milliseconds: 120));

        final mainRoom = tester.widget<MainRoomScreen>(
          find.byType(MainRoomScreen),
        );
        final player = tester.widget<SpriteSequencePlayer>(
          find.byType(SpriteSequencePlayer),
        );

        expect(mainRoom.roomManager.currentRoom, RoomId.wardrobe);
        expect(player.controller.clip, isNotNull);
      }
    },
  );

  testWidgets('table room first visible idle stays on blink', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BabuckDuduckApp());
    await pumpUntilMainRoom(tester);

    tester
        .widget<RoomNavigationBar>(find.byType(RoomNavigationBar))
        .onRoomSelected(RoomId.baloon);
    await pumpUntilRoomSelected(
      tester,
      RoomId.baloon,
      description: 'Table room',
    );
    await pumpUntilClipLoaded(
      tester,
      find.byType(SpriteSequencePlayer),
      description: 'Table sprite player',
    );

    final player = tester.widget<SpriteSequencePlayer>(
      find.byType(SpriteSequencePlayer),
    );

    expect(player.controller.clip?.name, 'idle_blink');
  });

  testWidgets('rocket room belly tap triggers Dudak belly reaction', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BabuckDuduckApp());
    await pumpUntilMainRoom(tester);

    await tester.tap(find.byKey(const ValueKey<String>('room-drawer-trigger')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('room-drawer-item-rocket')),
    );
    await pumpUntilClipLoaded(
      tester,
      find.byType(SpriteSequencePlayer),
      description: 'Rocket sprite player',
    );

    final playerFinder = find.byType(SpriteSequencePlayer);
    final player = tester.widget<SpriteSequencePlayer>(playerFinder);
    expect(player.controller.clip, isNotNull);

    final mainRoom = tester.widget<MainRoomScreen>(find.byType(MainRoomScreen));
    mainRoom.characterManager.handleZoneTap(TouchZone.belly);
    await tester.pump();

    expect(player.controller.clip, isNotNull);
    expect(player.controller.clip!.name, 'reaction_belly');
  });

  testWidgets('rocket room head tap triggers Dudak head reaction', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BabuckDuduckApp());
    await pumpUntilMainRoom(tester);

    await tester.tap(find.byKey(const ValueKey<String>('room-drawer-trigger')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('room-drawer-item-rocket')),
    );
    await pumpUntilClipLoaded(
      tester,
      find.byType(SpriteSequencePlayer),
      description: 'Rocket sprite player',
    );

    final playerFinder = find.byType(SpriteSequencePlayer);
    final player = tester.widget<SpriteSequencePlayer>(playerFinder);
    expect(player.controller.clip, isNotNull);

    final mainRoom = tester.widget<MainRoomScreen>(find.byType(MainRoomScreen));
    mainRoom.characterManager.handleZoneTap(TouchZone.head);
    await tester.pump();

    expect(player.controller.clip, isNotNull);
    expect(player.controller.clip!.name, 'reaction_head');
  });
}
