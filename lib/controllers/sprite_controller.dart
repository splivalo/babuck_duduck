import 'dart:async';

import 'package:flutter/foundation.dart';

import '../main.dart' show renderLog;
import '../models/app_models.dart';
import '../services/asset_loader.dart';
import 'sprite_sequence_controller.dart';

class SpriteController extends ChangeNotifier {
  SpriteController({SpriteSequenceController? sequenceController})
    : sequenceController = sequenceController ?? SpriteSequenceController(),
      _ownsSequenceController = sequenceController == null {
    this.sequenceController.addListener(_handleSequenceChanged);
  }

  final SpriteSequenceController sequenceController;
  final bool _ownsSequenceController;
  final Set<ValueChanged<int>> _textureFrameResolvedListeners =
      <ValueChanged<int>>{};
  final Set<VoidCallback> _firstTextureBoundListeners = <VoidCallback>{};

  AssetLoader? _assetLoader;
  TextureFrame? _textureFrame;
  TextureFrame? _displayFallbackTextureFrame;
  Object? _pendingTextureRequestToken;
  int _playbackRevision = 0;
  bool _isDisposed = false;
  bool _allowDisplayFallback = false;
  Completer<void> _firstTextureBoundCompleter = Completer<void>();

  SequenceClip? get clip => sequenceController.clip;
  int get frameIndex => sequenceController.frameIndex;
  TextureFrame? get textureFrame => _textureFrame;
  TextureFrame? get displayTextureFrame =>
      _textureFrame ??
      (_allowDisplayFallback ? _displayFallbackTextureFrame : null);
  String? get currentFramePath => sequenceController.currentFramePath;
  bool get hasFirstTextureBound =>
      _firstTextureBoundCompleter.isCompleted || _textureFrame != null;
  Future<void> get firstTextureBound => hasFirstTextureBound
      ? Future<void>.value()
      : _firstTextureBoundCompleter.future;

  void bindAssetLoader(AssetLoader assetLoader) {
    if (identical(_assetLoader, assetLoader)) {
      return;
    }
    _assetLoader = assetLoader;
    _resolveTextureFrameForCurrentState(_playbackRevision);
  }

  void play(
    SequenceClip clip, {
    VoidCallback? onCompleted,
    void Function(AnimationTimelineEvent event)? onEvent,
  }) {
    sequenceController.play(clip, onCompleted: onCompleted, onEvent: onEvent);
  }

  void stop() {
    sequenceController.stop();
  }

  void clear() {
    sequenceController.clear();
  }

  Future<void> ensureFirstTextureBound(SequenceClip seedClip) {
    if (hasFirstTextureBound || _isDisposed) {
      return Future<void>.value();
    }
    return firstTextureBound;
  }

  void warmupFirstTexture(SequenceClip seedClip) {
    if (hasFirstTextureBound || _isDisposed || _assetLoader == null) {
      return;
    }
    unawaited(_resolveFirstTextureFromSeed(seedClip));
  }

  Future<void> _resolveFirstTextureFromSeed(SequenceClip seedClip) async {
    final assetLoader = _assetLoader;
    final capturedRevision = _playbackRevision;
    if (assetLoader == null || _isDisposed || hasFirstTextureBound) return;
    renderLog(
      'SpriteController',
      'warmupFirstTexture AWAIT clip=${seedClip.name} frame=0',
    );
    final textureFrame = await assetLoader.loadTextureFrame(seedClip, 0);
    if (_isDisposed ||
        _playbackRevision != capturedRevision ||
        hasFirstTextureBound ||
        textureFrame == null) {
      return;
    }
    final textureChanged = !identical(_textureFrame, textureFrame);
    final wasNull = _textureFrame == null;
    _textureFrame = textureFrame;
    _displayFallbackTextureFrame = null;
    _allowDisplayFallback = false;
    if (wasNull && textureChanged && !_firstTextureBoundCompleter.isCompleted) {
      _firstTextureBoundCompleter.complete();
      renderLog(
        'SpriteController',
        'warmupFirstTexture FIRST_TEXTURE_BOUND clip=${seedClip.name} frame=0',
      );
      for (final listener in _firstTextureBoundListeners) {
        listener();
      }
    }
    if (textureChanged) {
      notifyListeners();
    }
    for (final listener in _textureFrameResolvedListeners) {
      listener(0);
    }
  }

  void resetForRoom() {
    _displayFallbackTextureFrame = _textureFrame;
    _textureFrame = null;
    _pendingTextureRequestToken = null;
    _playbackRevision += 1;
    _allowDisplayFallback = _displayFallbackTextureFrame != null;
    _firstTextureBoundCompleter = Completer<void>();
    renderLog('SpriteController', 'resetForRoom rev=$_playbackRevision');
    notifyListeners();
  }

  void addTextureFrameResolvedListener(ValueChanged<int> listener) {
    _textureFrameResolvedListeners.add(listener);
  }

  void removeTextureFrameResolvedListener(ValueChanged<int> listener) {
    _textureFrameResolvedListeners.remove(listener);
  }

  void addFirstTextureBoundListener(VoidCallback listener) {
    _firstTextureBoundListeners.add(listener);
  }

  void removeFirstTextureBoundListener(VoidCallback listener) {
    _firstTextureBoundListeners.remove(listener);
  }

  void _handleSequenceChanged() {
    _playbackRevision += 1;
    final clip = this.clip;
    renderLog(
      'SpriteController',
      '_handleSequenceChanged rev=$_playbackRevision '
          'clip=${clip?.name ?? 'null'} '
          'frameIndex=$frameIndex '
          'textureFrame=${_textureFrame == null ? 'null' : 'non-null'}',
    );
    _resolveTextureFrameForCurrentState(_playbackRevision);
    // notifyListeners() is intentionally NOT called here.
    // _resolveTextureFrameForCurrentState calls notifyListeners() once the
    // texture is actually bound, preventing a blank SizedBox.shrink() frame
    // on cold start (when _textureFrame is null before the first play()).
    // On clip=null (clear), _resolveTextureFrameForCurrentState returns early
    // and the old _textureFrame is preserved, so no visual change occurs.
  }

  Future<void> _resolveTextureFrameForCurrentState(int playbackRevision) async {
    final activeClip = clip;
    final assetLoader = _assetLoader;
    if (activeClip == null || assetLoader == null) {
      renderLog(
        'SpriteController',
        '_resolveTextureFrame rev=$playbackRevision SKIP '
            '(clip=${activeClip?.name ?? 'null'} assetLoader=${assetLoader == null ? 'null' : 'set'})',
      );
      return;
    }

    final activeFrameIndex = frameIndex;
    final requestToken = Object();
    _pendingTextureRequestToken = requestToken;

    renderLog(
      'SpriteController',
      '_resolveTextureFrame rev=$playbackRevision AWAIT '
          'clip=${activeClip.name} frame=$activeFrameIndex '
          'textureFrame_before=${_textureFrame == null ? 'null' : 'non-null'}',
    );

    final textureFrame = await assetLoader.loadTextureFrame(
      activeClip,
      activeFrameIndex,
    );

    if (_isDisposed ||
        _pendingTextureRequestToken != requestToken ||
        playbackRevision != _playbackRevision ||
        textureFrame == null) {
      renderLog(
        'SpriteController',
        '_resolveTextureFrame rev=$playbackRevision DROPPED '
            '(disposed=$_isDisposed tokenMatch=${_pendingTextureRequestToken == requestToken} '
            'revMatch=${playbackRevision == _playbackRevision} frameNull=${textureFrame == null})',
      );
      return;
    }

    final textureChanged = !identical(_textureFrame, textureFrame);
    final wasNull = _textureFrame == null;
    _textureFrame = textureFrame;
    _displayFallbackTextureFrame = null;
    _allowDisplayFallback = false;

    if (wasNull && textureChanged && !_firstTextureBoundCompleter.isCompleted) {
      _firstTextureBoundCompleter.complete();
      renderLog(
        'SpriteController',
        '_resolveTextureFrame rev=$playbackRevision FIRST_TEXTURE_BOUND '
            'clip=${activeClip.name} frame=$activeFrameIndex',
      );
      for (final listener in _firstTextureBoundListeners) {
        listener();
      }
    }

    renderLog(
      'SpriteController',
      '_resolveTextureFrame rev=$playbackRevision BOUND '
          'clip=${activeClip.name} frame=$activeFrameIndex '
          'wasNull=$wasNull textureChanged=$textureChanged',
    );

    if (textureChanged) {
      notifyListeners();
    }

    for (final listener in _textureFrameResolvedListeners) {
      listener(activeFrameIndex);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pendingTextureRequestToken = null;
    sequenceController.removeListener(_handleSequenceChanged);
    if (_ownsSequenceController) {
      sequenceController.dispose();
    }
    super.dispose();
  }
}
