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
      shadowAssetPath = assetPath,
      shadowSourceRect = null,
      bottomInset = 0.0;

  const TextureFrame.spriteSheet({
    required this.image,
    required this.sourceRect,
    required this.frameWidth,
    required this.frameHeight,
    this.shadowAssetPath,
    this.shadowSourceRect,
    this.bottomInset = 0.0,
  }) : assetPath = null;

  final String? assetPath;
  final ui.Image? image;
  final Rect? sourceRect;
  final double? frameWidth;
  final double? frameHeight;
  final String? shadowAssetPath;

  /// Atlas rect of the current frame's silhouette, used to draw the contact
  /// shadow. Tracks the frame being drawn so the shadow follows the character's
  /// motion (sway, yawn, reactions) instead of staying frozen on frame 0.
  final Rect? shadowSourceRect;

  /// Fraction of the frame height that is empty below the character's feet.
  /// The renderer shifts the sprite and its shadow down by this so the feet
  /// rest on the floor regardless of art padding (0 for art with no padding).
  final double bottomInset;
}

class _SpriteSheetAsset {
  const _SpriteSheetAsset({
    required this.image,
    required this.frames,
    this.playbackFrames,
    this.animationEvents,
    this.bottomInset = 0.0,
  });

  final ui.Image image;
  final List<SpriteSheetFrameRect> frames;
  final List<AnimationFrameTiming>? playbackFrames;
  final List<AnimationTimelineEvent>? animationEvents;
  final double bottomInset;
}

class AssetLoader {
  static const int _maxActiveSpriteSheets = 7;
  static const int _maxPngSequenceProbeFrames = 240;

  final LinkedHashMap<String, _SpriteSheetAsset> _spriteSheetCache =
      LinkedHashMap<String, _SpriteSheetAsset>();
  final Map<String, Future<_SpriteSheetAsset?>> _pendingSpriteSheetLoads =
      <String, Future<_SpriteSheetAsset?>>{};
  bool _renderPipelineWarmed = false;
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

  /// Lightweight startup warm: decodes and caches only the idle atlases
  /// (blink + sway) so the first idle shows instantly, without decoding the
  /// heavy reaction atlases. Reactions are decoded later, per room, by
  /// [activateCharacterRoom] on room entry — so startup never holds both
  /// character rooms' full atlas sets in memory at once.
  Future<void> preloadCharacterIdles(
    CharacterDefinition character,
    BuildContext context,
  ) async {
    final configuration = createLocalImageConfiguration(context);
    await _prepareClip(character.idleBlink);
    await _prepareClip(character.idleSway);
    await _preloadClip(character.idleBlink, configuration);
    await _preloadClip(character.idleSway, configuration);
  }

  /// Scopes the sprite-sheet cache to a single room: disposes every resident
  /// atlas that does not belong to [character], then decodes and caches this
  /// room's atlases so its reactions play instantly (no decode hitch on tap).
  ///
  /// Called on room entry so two character rooms never stay resident at once —
  /// keeping peak texture memory at one room (~330 MB) instead of ~600 MB.
  /// The previous room is freed first, so switching rooms re-decodes the new
  /// room's atlases rather than holding both.
  Future<void> activateCharacterRoom(CharacterDefinition character) async {
    final clips = character.preloadClips;
    retainSpriteSheetsForClips(clips);
    for (final clip in clips) {
      await _prepareClip(clip);
    }
  }

  /// Disposes every resident sprite sheet whose atlas is not used by [clips],
  /// freeing its decoded GPU image. Pass an empty iterable to free them all.
  void retainSpriteSheetsForClips(Iterable<SequenceClip> clips) {
    final keepKeys = <String>{};
    for (final clip in clips) {
      final frameSource = clip.frameSource;
      if (frameSource is SpriteSheetFrameSource) {
        keepKeys.add(_spriteSheetCacheKey(frameSource));
      }
    }

    final staleKeys = _spriteSheetCache.keys
        .where((key) => !keepKeys.contains(key))
        .toList(growable: false);
    for (final key in staleKeys) {
      final evicted = _spriteSheetCache.remove(key);
      evicted?.image.dispose();
    }
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
    final frameSource = clip.frameSource;

    // Prefer the resident atlas — packing every frame into one texture is the
    // whole point of the migration (RAM). Only fall back to a PNG-sequence frame
    // when the atlas isn't resident yet (e.g. mid-load) or for PNG-only clips.
    if (frameSource is SpriteSheetFrameSource) {
      final spriteSheet = _loadResidentSpriteSheet(frameSource);
      if (spriteSheet != null && sourceFrameIndex < spriteSheet.frames.length) {
        final frame = spriteSheet.frames[sourceFrameIndex];
        return TextureFrame.spriteSheet(
          image: spriteSheet.image,
          sourceRect: _frameRect(frame),
          frameWidth: frame.width.toDouble(),
          frameHeight: frame.height.toDouble(),
          shadowSourceRect: _frameRect(frame),
          bottomInset: spriteSheet.bottomInset,
        );
      }
    }

    if (_pngSequenceFramePathsCache.containsKey(clip.assetDirectory)) {
      final cachedPngFrame = _loadPngTextureFrameSync(clip, sourceFrameIndex);
      if (cachedPngFrame != null) {
        return cachedPngFrame;
      }
    }

    return null;
  }

  Rect _frameRect(SpriteSheetFrameRect frame) => Rect.fromLTWH(
    frame.x.toDouble(),
    frame.y.toDouble(),
    frame.width.toDouble(),
    frame.height.toDouble(),
  );

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
          sourceRect: _frameRect(frame),
          frameWidth: frame.width.toDouble(),
          frameHeight: frame.height.toDouble(),
          shadowSourceRect: _frameRect(frame),
          bottomInset: spriteSheet.bottomInset,
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

  String _spriteSheetCacheKey(SpriteSheetFrameSource frameSource) =>
      '${frameSource.imageAssetPath}|${frameSource.metadataAssetPath}';

  Future<_SpriteSheetAsset?> _loadSpriteSheet(
    SpriteSheetFrameSource frameSource,
  ) async {
    final cacheKey = _spriteSheetCacheKey(frameSource);

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
    final cacheKey = _spriteSheetCacheKey(frameSource);
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
      // Decoding only produces a CPU-side image; the expensive GPU texture
      // upload otherwise happens lazily on the first paint of this atlas,
      // causing a one-time hitch the first time an animation plays. Warm it
      // here (once per atlas, during room activation) so the first real frame
      // is smooth.
      await _warmUpImageOnGpu(image);
      final metadata = _parseSpriteSheetMetadata(metadataText);
      return _SpriteSheetAsset(
        image: image,
        frames: metadata.frames,
        playbackFrames: metadata.playbackFrames,
        animationEvents: metadata.animationEvents,
        bottomInset: metadata.bottomInset,
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

  /// Forces [image]'s texture onto the GPU by rasterizing a tiny draw of it.
  /// `Picture.toImage` runs on the raster thread and must bind the source
  /// texture to sample it, so the upload cost is paid here (off the first
  /// paint). The 8x8 output is throwaway.
  Future<void> _warmUpImageOnGpu(ui.Image image) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final src = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      canvas.drawImageRect(
        image,
        src,
        const Rect.fromLTWH(0, 0, 8, 8),
        Paint()..filterQuality = FilterQuality.low,
      );

      if (!_renderPipelineWarmed) {
        _renderPipelineWarmed = true;
        // Compile the contact-shadow render pipeline once (Gaussian blur + a
        // srcIn colour filter inside a save layer — exactly what
        // _SpriteSheetContactShadow does). Otherwise these shaders compile on
        // the first character paint, which lands on the cold-start room and
        // hitches. Between rooms they're already compiled, hence smooth there.
        final shadowPaint = Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4)
          ..colorFilter = const ColorFilter.mode(Colors.black, BlendMode.srcIn);
        canvas.saveLayer(const Rect.fromLTWH(0, 0, 8, 8), shadowPaint);
        canvas.drawImageRect(
          image,
          src,
          const Rect.fromLTWH(0, 0, 8, 8),
          Paint()..filterQuality = FilterQuality.low,
        );
        canvas.restore();
      }

      final picture = recorder.endRecording();
      final warmed = await picture.toImage(8, 8);
      picture.dispose();
      warmed.dispose();
    } catch (_) {
      // Warm-up is best-effort; rendering still works without it.
    }
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

    final bottomInset = switch (decoded) {
      Map<String, dynamic> map when map['bottomInset'] is num =>
        (map['bottomInset'] as num).toDouble(),
      _ => 0.0,
    };

    return _ParsedSpriteSheetMetadata(
      frames: frames,
      playbackFrames: playbackFrames.isEmpty ? null : playbackFrames,
      animationEvents: animationEvents.isEmpty ? null : animationEvents,
      bottomInset: bottomInset,
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
    this.bottomInset = 0.0,
  });

  final List<SpriteSheetFrameRect> frames;
  final List<AnimationFrameTiming>? playbackFrames;
  final List<AnimationTimelineEvent>? animationEvents;
  final double bottomInset;
}
