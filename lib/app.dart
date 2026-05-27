import 'dart:async';

import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/main_room/main_room_screen.dart';
import 'features/splash/splash_screen.dart';
import 'managers/character_manager.dart';
import 'managers/room_manager.dart';
import 'models/app_models.dart';
import 'services/asset_loader.dart';
import 'services/sound_manager.dart';

class BabuckDuduckApp extends StatefulWidget {
  const BabuckDuduckApp({super.key});

  @override
  State<BabuckDuduckApp> createState() => _BabuckDuduckAppState();
}

class _BabuckDuduckAppState extends State<BabuckDuduckApp>
    with WidgetsBindingObserver {
  final RoomManager _roomManager = RoomManager();
  final SoundManager _soundManager = SoundManager();
  final AssetLoader _assetLoader = AssetLoader();
  late final CharacterManager _characterManager = CharacterManager(
    soundManager: _soundManager,
  );

  AppFlow _flow = AppFlow.splash;
  bool _startupAssetsReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_flow == AppFlow.mainRoom) {
          _characterManager.resumeScene();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _characterManager.suspendScene();
        unawaited(_soundManager.stopAllRoomAudio());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _characterManager.dispose();
    _roomManager.dispose();
    _soundManager.dispose();
    _assetLoader.dispose();
    super.dispose();
  }

  void _goToMainRoom() {
    _characterManager.syncRoom(_roomManager.currentRoom);
    setState(() {
      _flow = AppFlow.mainRoom;
    });
  }

  Future<void> _prepareStartupScene(
    BuildContext context,
    ValueChanged<double> onProgress,
  ) async {
    var startupSucceeded = true;

    _characterManager.syncRoom(_roomManager.currentRoom);
    onProgress(0.12);

    final currentRoomConfig = roomConfigMap[_roomManager.currentRoom]!;
    final extraBackgroundAssets = currentRoomConfig.supportsMoodToggle
        ? <String>[
            currentRoomConfig.backgroundDayAsset,
            currentRoomConfig.backgroundNightAsset!,
          ]
        : const <String>[];

    try {
      await _assetLoader
          .preloadRoomScene(
            context: context,
            currentBackgroundAsset: _roomManager.currentBackgroundAsset,
            nextBackgroundAsset: roomConfigMap[_roomManager.nextRoom]!
                .backgroundAsset(BedroomMood.day),
            previousBackgroundAsset: roomConfigMap[_roomManager.previousRoom]!
                .backgroundAsset(BedroomMood.day),
            extraBackgroundAssets: extraBackgroundAssets,
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      startupSucceeded = false;
    }
    if (!context.mounted) {
      return;
    }
    onProgress(0.58);

    if (roomHasReadyCharacterAssets(_roomManager.currentRoom)) {
      try {
        await _assetLoader
            .preloadCharacter(_characterManager.currentCharacter, context)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        startupSucceeded = false;
      }
      if (!context.mounted) {
        return;
      }
      onProgress(0.86);

      try {
        await _soundManager
            .preloadForCharacter(
              _roomManager.currentRoom,
              _roomManager.currentRoomCharacter,
            )
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        startupSucceeded = false;
      }
    }

    _startupAssetsReady = startupSucceeded;
    onProgress(1.0);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Babak & Dudak',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: switch (_flow) {
          AppFlow.splash => SplashScreen(
            onPrepare: _prepareStartupScene,
            onFinished: _goToMainRoom,
          ),
          AppFlow.mainRoom => MainRoomScreen(
            roomManager: _roomManager,
            characterManager: _characterManager,
            assetLoader: _assetLoader,
            soundManager: _soundManager,
            initialAssetsReady: _startupAssetsReady,
          ),
        },
      ),
    );
  }
}
