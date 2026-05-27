import 'dart:convert';
import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:ui' as ui;

import '../models/app_models.dart';

class TextureFrame {
  const TextureFrame.png({required this.assetPath})
    : image = null,
      sourceRect = null,
      frameWidth = null,
      frameHeight = null,
      shadowAssetPath = assetPath;

  const TextureFrame.spriteSheet({
    required this.image,
    required this.sourceRect,
    required this.frameWidth,
    required this.frameHeight,
    this.shadowAssetPath,
  }) : assetPath = null;

  final String? assetPath;
  final ui.Image? image;
  final Rect? sourceRect;
  final double? frameWidth;
  final double? frameHeight;
  final String? shadowAssetPath;
}

class _SpriteSheetAsset {
  const _SpriteSheetAsset({
    required this.image,
    required this.frames,
    this.playbackFrames,
    this.animationEvents,
  });

  final ui.Image image;
  final List<SpriteSheetFrameRect> frames;
  final List<AnimationFrameTiming>? playbackFrames;
  final List<AnimationTimelineEvent>? animationEvents;
}

class AssetLoader {
  static const int _maxActiveSpriteSheets = 8;
  static const int _maxSceneBackgrounds = 3;
  static const int _maxPngSequenceProbeFrames = 240;

  final LinkedHashMap<String, _SpriteSheetAsset> _spriteSheetCache =
      LinkedHashMap<String, _SpriteSheetAsset>();
  final Map<String, Future<_SpriteSheetAsset?>> _pendingSpriteSheetLoads =
      <String, Future<_SpriteSheetAsset?>>{};
  final LinkedHashMap<String, AssetImage> _sceneBackgroundCache =
      LinkedHashMap<String, AssetImage>();
  Future<Set<String>>? _assetManifestFuture;
  final Map<String, int> _pngSequenceFrameCountCache = <String, int>{};
  final Map<String, List<String>> _pngSequenceFramePathsCache =
      <String, List<String>>{};
  final Map<String, bool> _assetExistsCache = <String, bool>{};
  final Set<String> _missingSpriteSheetCache = <String>{};

  Future<void> preloadRoomBackground(
    BuildContext context,
    String assetPath,
  ) async {
    final configuration = createLocalImageConfiguration(context);

    if (!await _assetExists(assetPath)) {
      return;
    }

    try {
      await _precacheAsset(AssetImage(assetPath), configuration);
    } catch (_) {}
  }

  Future<void> preloadRoomScene({
    required BuildContext context,
    required String currentBackgroundAsset,
    String? nextBackgroundAsset,
    String? previousBackgroundAsset,
    Iterable<String> extraBackgroundAssets = const <String>[],
  }) async {
    final desiredAssets = <String>{
      currentBackgroundAsset,
      ?nextBackgroundAsset,
      ?previousBackgroundAsset,
      ...extraBackgroundAssets,
    };

    for (final assetPath in desiredAssets) {
      await preloadRoomBackground(context, assetPath);
      _touchSceneBackground(assetPath);
    }

    await _evictUnusedSceneBackgrounds(desiredAssets);
  }

  Future<void> preloadCharacter(
    CharacterDefinition character,
    BuildContext context,
  ) async {
    final configuration = createLocalImageConfiguration(context);

    for (final clip in character.preloadClips) {
      await _prepareClip(clip);
      await _preloadClip(clip, configuration);
    }
  }

  Future<void> prepareCharacterPlayback(CharacterDefinition character) async {
    for (final clip in character.preloadClips) {
      await _prepareClip(clip);
    }
  }

  Future<void> preloadCharacterScene(
    CharacterDefinition character,
    BuildContext context,
  ) async {
    final configuration = createLocalImageConfiguration(context);
    for (final clip in character.preloadClips) {
      await _prepareClip(clip);
    }
    await _preloadClip(character.idleBlink, configuration);
    await _preloadClip(character.idleSway, configuration);
  }

  Future<void> _prepareClip(SequenceClip clip) async {
    final frameSource = clip.frameSource;
    if (frameSource is PngSequenceFrameSource) {
      final discoveredFrameCount = await _discoverPngSequenceFrameCount(
        frameSource,
      );
      clip.resolveFrameCount(discoveredFrameCount);
      return;
    }

    if (frameSource is SpriteSheetFrameSource) {
      final spriteSheet = await _loadSpriteSheet(frameSource);
      if (spriteSheet != null) {
        clip.resolveFrameCount(spriteSheet.frames.length);
        if (spriteSheet.playbackFrames != null) {
          clip.resolveFrameTimings(spriteSheet.playbackFrames!);
        }
        if (spriteSheet.animationEvents != null) {
          clip.resolveAnimationEvents(spriteSheet.animationEvents!);
        }
        final fallbackFrameSource = clip.fallbackFrameSource;
        if (fallbackFrameSource is PngSequenceFrameSource) {
          await _discoverPngSequenceFramePaths(fallbackFrameSource);
        }
        return;
      }

      final fallbackFrameSource = clip.fallbackFrameSource;
      if (fallbackFrameSource is PngSequenceFrameSource) {
        final discoveredFrameCount = await _discoverPngSequenceFrameCount(
          fallbackFrameSource,
        );
        clip.resolveFrameCount(discoveredFrameCount);
      }
    }
  }

  Future<void> _preloadClip(
    SequenceClip clip,
    ImageConfiguration configuration,
  ) async {
    final frameSource = clip.frameSource;
    if (frameSource is SpriteSheetFrameSource) {
      final spriteSheet = await _loadSpriteSheet(frameSource);
      if (spriteSheet != null) {
        return;
      }

      final fallbackFrameSource = clip.fallbackFrameSource;
      if (clip.allowPngFallback &&
          fallbackFrameSource is PngSequenceFrameSource) {
        await _preloadPngSequence(fallbackFrameSource, configuration);
      }
      return;
    }

    if (frameSource is PngSequenceFrameSource) {
      await _preloadPngSequence(frameSource, configuration);
    }
  }

  Future<void> _preloadPngSequence(
    PngSequenceFrameSource frameSource,
    ImageConfiguration configuration,
  ) async {
    final framePaths = await _discoverPngSequenceFramePaths(frameSource);
    for (var index = 0; index < framePaths.length && index < 2; index += 1) {
      try {
        await _precacheAsset(AssetImage(framePaths[index]), configuration);
      } catch (_) {}
    }
  }

  Future<void> _precacheAsset(
    ImageProvider provider,
    ImageConfiguration configuration,
  ) async {
    final completer = Completer<void>();
    final stream = provider.resolve(configuration);
    late final ImageStreamListener listener;

    listener = ImageStreamListener(
      (image, synchronousCall) {
        if (!completer.isCompleted) {
          completer.complete();
        }
        stream.removeListener(listener);
      },
      onError: (exception, stackTrace) {
        if (!completer.isCompleted) {
          completer.complete();
        }
        stream.removeListener(listener);
      },
    );

    stream.addListener(listener);
    await completer.future;
  }

  Future<TextureFrame?> loadTextureFrame(SequenceClip clip, int index) {
    final cachedFrame = _loadTextureFrameSync(clip, index);
    if (cachedFrame != null) {
      return SynchronousFuture<TextureFrame?>(cachedFrame);
    }

    return _loadTextureFrameAsync(clip, index);
  }

  TextureFrame? _loadTextureFrameSync(SequenceClip clip, int index) {
    final sourceFrameIndex = clip.sourceFrameIndexAt(index);

    if (_pngSequenceFramePathsCache.containsKey(clip.assetDirectory)) {
      final cachedPngFrame = _loadPngTextureFrameSync(clip, sourceFrameIndex);
      if (cachedPngFrame != null) {
        return cachedPngFrame;
      }
    }

    final frameSource = clip.frameSource;
    if (frameSource is! SpriteSheetFrameSource) {
      return null;
    }

    final spriteSheet = _loadResidentSpriteSheet(frameSource);
    if (spriteSheet == null || sourceFrameIndex >= spriteSheet.frames.length) {
      return null;
    }

    final frame = spriteSheet.frames[sourceFrameIndex];
    return TextureFrame.spriteSheet(
      image: spriteSheet.image,
      sourceRect: Rect.fromLTWH(
        frame.x.toDouble(),
        frame.y.toDouble(),
        frame.width.toDouble(),
        frame.height.toDouble(),
      ),
      frameWidth: frame.width.toDouble(),
      frameHeight: frame.height.toDouble(),
    );
  }

  Future<TextureFrame?> _loadTextureFrameAsync(
    SequenceClip clip,
    int index,
  ) async {
    await _prepareClip(clip);
    final sourceFrameIndex = clip.sourceFrameIndexAt(index);
    final frameSource = clip.frameSource;

    if (frameSource is PngSequenceFrameSource) {
      return _loadPngTextureFrame(frameSource, sourceFrameIndex);
    }

    if (frameSource is SpriteSheetFrameSource) {
      final spriteSheet = await _loadSpriteSheet(frameSource);
      if (spriteSheet != null && sourceFrameIndex < spriteSheet.frames.length) {
        final frame = spriteSheet.frames[sourceFrameIndex];
        return TextureFrame.spriteSheet(
          image: spriteSheet.image,
          sourceRect: Rect.fromLTWH(
            frame.x.toDouble(),
            frame.y.toDouble(),
            frame.width.toDouble(),
            frame.height.toDouble(),
          ),
          frameWidth: frame.width.toDouble(),
          frameHeight: frame.height.toDouble(),
        );
      }

      final fallbackFrameSource = clip.fallbackFrameSource;
      if (clip.allowPngFallback &&
          fallbackFrameSource is PngSequenceFrameSource) {
        return _loadPngTextureFrame(fallbackFrameSource, sourceFrameIndex);
      }
    }

    return null;
  }

  TextureFrame? _loadPngTextureFrameSync(SequenceClip clip, int index) {
    final cachedPaths = _pngSequenceFramePathsCache[clip.assetDirectory];
    if (cachedPaths == null || cachedPaths.isEmpty) {
      return null;
    }

    final clampedIndex = index.clamp(0, cachedPaths.length - 1);
    return TextureFrame.png(assetPath: cachedPaths[clampedIndex]);
  }

  Future<TextureFrame?> _loadPngTextureFrame(
    PngSequenceFrameSource frameSource,
    int index,
  ) async {
    final cachedPaths = _pngSequenceFramePathsCache[frameSource.assetDirectory];
    if (cachedPaths != null && cachedPaths.isNotEmpty) {
      final clampedIndex = index.clamp(0, cachedPaths.length - 1);
      return TextureFrame.png(assetPath: cachedPaths[clampedIndex]);
    }

    final assetPath = await _firstExistingFrameAssetPath(frameSource, index);
    if (assetPath == null) {
      return null;
    }
    return TextureFrame.png(assetPath: assetPath);
  }

  Future<int> _discoverPngSequenceFrameCount(
    PngSequenceFrameSource frameSource,
  ) async {
    final cachedFrameCount =
        _pngSequenceFrameCountCache[frameSource.assetDirectory];
    if (cachedFrameCount != null) {
      return cachedFrameCount;
    }

    final framePaths = await _discoverPngSequenceFramePaths(frameSource);
    final discoveredFrameCount = framePaths.isEmpty
        ? frameSource.frameCount
        : framePaths.length;
    _pngSequenceFrameCountCache[frameSource.assetDirectory] =
        discoveredFrameCount;
    return discoveredFrameCount;
  }

  Future<List<String>> _discoverPngSequenceFramePaths(
    PngSequenceFrameSource frameSource,
  ) async {
    final cachedPaths = _pngSequenceFramePathsCache[frameSource.assetDirectory];
    if (cachedPaths != null) {
      return cachedPaths;
    }

    final manifestEntries = await _loadAssetManifestEntries();
    final prefix = '${frameSource.assetDirectory}/';
    final matchedFrames =
        manifestEntries
            .where((path) {
              if (!path.startsWith(prefix) || !path.endsWith('.png')) {
                return false;
              }

              final fileName = path.substring(prefix.length);
              return RegExp(r'^\d{3,4}\.png$').hasMatch(fileName);
            })
            .toList(growable: false)
          ..sort();

    if (matchedFrames.isNotEmpty) {
      _pngSequenceFramePathsCache[frameSource.assetDirectory] = matchedFrames;
      return matchedFrames;
    }

    final probedFrames = await _probePngSequenceFramePaths(frameSource);
    _pngSequenceFramePathsCache[frameSource.assetDirectory] = probedFrames;
    return probedFrames;
  }

  Future<List<String>> _probePngSequenceFramePaths(
    PngSequenceFrameSource frameSource,
  ) async {
    final matchedFrames = <String>[];
    var misses = 0;

    for (var index = 0; index < _maxPngSequenceProbeFrames; index += 1) {
      final assetPath = await _firstExistingFrameAssetPath(frameSource, index);
      if (assetPath != null) {
        matchedFrames.add(assetPath);
        misses = 0;
        continue;
      }

      misses += 1;
      if (matchedFrames.isNotEmpty || misses >= 2) {
        break;
      }
    }

    return matchedFrames;
  }

  Future<String?> _firstExistingFrameAssetPath(
    PngSequenceFrameSource frameSource,
    int index,
  ) async {
    for (final assetPath in _frameAssetPathCandidates(frameSource, index)) {
      if (await _assetExists(assetPath)) {
        return assetPath;
      }
    }

    return null;
  }

  List<String> _frameAssetPathCandidates(
    PngSequenceFrameSource frameSource,
    int index,
  ) {
    final frameNumber = index + 1;
    return <String>[
      frameSource.frameAssetPathAt(index),
      '${frameSource.assetDirectory}/${frameNumber.toString().padLeft(3, '0')}.png',
    ];
  }

  Future<Set<String>> _loadAssetManifestEntries() {
    return _assetManifestFuture ??= _readAssetManifestEntries();
  }

  Future<Set<String>> _readAssetManifestEntries() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assetPaths = manifest.listAssets();
      if (assetPaths.isNotEmpty) {
        return assetPaths.toSet();
      }
    } catch (_) {}

    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final decoded = jsonDecode(manifestContent) as Map<String, dynamic>;
      return decoded.keys.toSet();
    } catch (_) {
      return <String>{};
    }
  }

  void _touchSceneBackground(String assetPath) {
    final existing = _sceneBackgroundCache.remove(assetPath);
    _sceneBackgroundCache[assetPath] = existing ?? AssetImage(assetPath);
  }

  Future<void> _evictUnusedSceneBackgrounds(Set<String> desiredAssets) async {
    final staleAssets = _sceneBackgroundCache.keys
        .where((assetPath) => !desiredAssets.contains(assetPath))
        .toList(growable: false);

    for (final assetPath in staleAssets) {
      final provider = _sceneBackgroundCache.remove(assetPath);
      if (provider != null) {
        await provider.evict();
      }
    }

    while (_sceneBackgroundCache.length > _maxSceneBackgrounds) {
      final oldestKey = _sceneBackgroundCache.keys.first;
      final provider = _sceneBackgroundCache.remove(oldestKey);
      if (provider != null) {
        await provider.evict();
      }
    }
  }

  Future<_SpriteSheetAsset?> _loadSpriteSheet(
    SpriteSheetFrameSource frameSource,
  ) async {
    final cacheKey =
        '${frameSource.imageAssetPath}|${frameSource.metadataAssetPath}';

    if (_missingSpriteSheetCache.contains(cacheKey)) {
      return null;
    }

    final cachedAsset = _spriteSheetCache.remove(cacheKey);
    if (cachedAsset != null) {
      _spriteSheetCache[cacheKey] = cachedAsset;
      return cachedAsset;
    }

    final pendingAsset = _pendingSpriteSheetLoads[cacheKey];
    if (pendingAsset != null) {
      return pendingAsset;
    }

    final future = _decodeSpriteSheet(frameSource).then((asset) {
      _pendingSpriteSheetLoads.remove(cacheKey);
      if (asset != null) {
        _missingSpriteSheetCache.remove(cacheKey);
        _insertSpriteSheet(cacheKey, asset);
      } else {
        _missingSpriteSheetCache.add(cacheKey);
      }
      return asset;
    });

    _pendingSpriteSheetLoads[cacheKey] = future;
    return future;
  }

  _SpriteSheetAsset? _loadResidentSpriteSheet(
    SpriteSheetFrameSource frameSource,
  ) {
    final cacheKey =
        '${frameSource.imageAssetPath}|${frameSource.metadataAssetPath}';
    final cachedAsset = _spriteSheetCache.remove(cacheKey);
    if (cachedAsset == null) {
      return null;
    }

    _spriteSheetCache[cacheKey] = cachedAsset;
    return cachedAsset;
  }

  void _insertSpriteSheet(String cacheKey, _SpriteSheetAsset asset) {
    if (_spriteSheetCache.containsKey(cacheKey)) {
      final previous = _spriteSheetCache.remove(cacheKey);
      previous?.image.dispose();
    }

    while (_spriteSheetCache.length >= _maxActiveSpriteSheets) {
      final oldestKey = _spriteSheetCache.keys.first;
      final evicted = _spriteSheetCache.remove(oldestKey);
      evicted?.image.dispose();
    }

    _spriteSheetCache[cacheKey] = asset;
  }

  Future<_SpriteSheetAsset?> _decodeSpriteSheet(
    SpriteSheetFrameSource frameSource,
  ) async {
    try {
      final imageBytes = await rootBundle.load(frameSource.imageAssetPath);
      final metadataText = await rootBundle.loadString(
        frameSource.metadataAssetPath,
      );
      final image = await _decodeUiImage(imageBytes);
      final metadata = _parseSpriteSheetMetadata(metadataText);
      return _SpriteSheetAsset(
        image: image,
        frames: metadata.frames,
        playbackFrames: metadata.playbackFrames,
        animationEvents: metadata.animationEvents,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ui.Image> _decodeUiImage(ByteData bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes.buffer.asUint8List(), completer.complete);
    return completer.future;
  }

  _ParsedSpriteSheetMetadata _parseSpriteSheetMetadata(String metadataText) {
    final decoded = jsonDecode(metadataText);
    final rawFrames = switch (decoded) {
      List<dynamic> frames => frames,
      Map<String, dynamic> map when map['frames'] is List<dynamic> =>
        map['frames'] as List<dynamic>,
      _ => const <dynamic>[],
    };

    final rawSequence = switch (decoded) {
      Map<String, dynamic> map when map['sequence'] is List<dynamic> =>
        map['sequence'] as List<dynamic>,
      Map<String, dynamic> map when map['timings'] is List<dynamic> =>
        map['timings'] as List<dynamic>,
      _ => const <dynamic>[],
    };

    final rawEvents = switch (decoded) {
      Map<String, dynamic> map when map['events'] is List<dynamic> =>
        map['events'] as List<dynamic>,
      _ => const <dynamic>[],
    };

    final frames = rawFrames
        .whereType<Map<String, dynamic>>()
        .map(SpriteSheetFrameRect.fromJson)
        .toList(growable: false);

    final playbackFrames = rawSequence
        .whereType<Map<String, dynamic>>()
        .map(AnimationFrameTiming.fromJson)
        .toList(growable: false);

    final animationEvents = rawEvents
        .whereType<Map<String, dynamic>>()
        .map(AnimationTimelineEvent.fromJson)
        .toList(growable: false);

    return _ParsedSpriteSheetMetadata(
      frames: frames,
      playbackFrames: playbackFrames.isEmpty ? null : playbackFrames,
      animationEvents: animationEvents.isEmpty ? null : animationEvents,
    );
  }

  Future<bool> _assetExists(String assetPath) async {
    final cached = _assetExistsCache[assetPath];
    if (cached != null) {
      return cached;
    }

    final manifestEntries = await _loadAssetManifestEntries();
    if (manifestEntries.contains(assetPath)) {
      _assetExistsCache[assetPath] = true;
      return true;
    }

    try {
      await rootBundle.load(assetPath);
      _assetExistsCache[assetPath] = true;
      return true;
    } catch (_) {
      _assetExistsCache[assetPath] = false;
      return false;
    }
  }

  void dispose() {
    for (final provider in _sceneBackgroundCache.values) {
      unawaited(provider.evict());
    }
    _sceneBackgroundCache.clear();
    for (final spriteSheet in _spriteSheetCache.values) {
      spriteSheet.image.dispose();
    }
    _spriteSheetCache.clear();
    _pendingSpriteSheetLoads.clear();
  }
}

class _ParsedSpriteSheetMetadata {
  const _ParsedSpriteSheetMetadata({
    required this.frames,
    required this.playbackFrames,
    required this.animationEvents,
  });

  final List<SpriteSheetFrameRect> frames;
  final List<AnimationFrameTiming>? playbackFrames;
  final List<AnimationTimelineEvent>? animationEvents;
}
