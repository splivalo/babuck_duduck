import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controllers/sprite_controller.dart';
import '../main.dart' show renderLog;
import '../services/asset_loader.dart';

class SpriteSequencePlayer extends StatefulWidget {
  const SpriteSequencePlayer({
    super.key,
    required this.controller,
    required this.characterLabel,
  });

  final SpriteController controller;
  final String characterLabel;

  @override
  State<SpriteSequencePlayer> createState() => _SpriteSequencePlayerState();
}

class _SpriteSequencePlayerState extends State<SpriteSequencePlayer> {
  int _rebuildCount = 0;
  bool _everHadTexture = false;
  bool _hasFirstTextureFrame = false;

  @override
  void initState() {
    super.initState();
    renderLog(
      'SpriteSequencePlayer',
      'MOUNT characterLabel=${widget.characterLabel}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        _rebuildCount += 1;
        final clip = widget.controller.clip;
        final label = clip == null
            ? widget.characterLabel
            : '${widget.characterLabel}\n${clip.name} ${widget.controller.frameIndex + 1}/${clip.effectiveFrameCount}';
        final textureFrame = widget.controller.textureFrame;
        final displayTextureFrame = widget.controller.displayTextureFrame;
        final hasDisplayTextureFrame = displayTextureFrame != null;

        final hadTexture = _everHadTexture;
        final hadFirstTextureFrame = _hasFirstTextureFrame;
        if (hasDisplayTextureFrame) {
          _everHadTexture = true;
          if (!_hasFirstTextureFrame) {
            _hasFirstTextureFrame = true;
            renderLog(
              'SpriteSequencePlayer',
              'FIRST_VISIBLE_TEXTURE frame=${widget.controller.frameIndex} clip=${clip?.name ?? 'null'}',
            );
          }
        }

        renderLog(
          'SpriteSequencePlayer',
          'BUILD #$_rebuildCount '
              'clip=${clip?.name ?? 'null'} '
              'frame=${widget.controller.frameIndex} '
              'textureFrame=${textureFrame == null ? 'null' : 'non-null'} '
              'displayTextureFrame=${displayTextureFrame == null ? 'null→BLANK' : 'non-null→VISIBLE'} '
              'hasFirstTextureFrame=$_hasFirstTextureFrame '
              'everHadTexture=$hadTexture '
              '${displayTextureFrame == null && hadTexture ? '⚠ DISAPPEAR' : ''}',
        );

        final child = displayTextureFrame == null
            ? const SizedBox.shrink()
            : _TextureFrameView(
                textureFrame: displayTextureFrame,
                label: label,
                frameIndex: widget.controller.frameIndex,
              );

        final gatedChild = AnimatedOpacity(
          opacity: hasDisplayTextureFrame ? 1 : 0,
          duration: hadFirstTextureFrame
              ? Duration.zero
              : const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          child: child,
        );

        return Stack(fit: StackFit.expand, children: <Widget>[gatedChild]);
      },
    );
  }
}

// ignore: unused_element
class _SpriteDebugOverlay extends StatelessWidget {
  const _SpriteDebugOverlay({
    required this.characterLabel,
    required this.clipName,
    required this.frameIndex,
    required this.frameCount,
    required this.textureFrame,
    required this.isLoading,
  });

  final String characterLabel;
  final String clipName;
  final int frameIndex;
  final int frameCount;
  final TextureFrame? textureFrame;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final backend = switch (textureFrame) {
      TextureFrame frame when frame.assetPath != null => 'png',
      TextureFrame _ => 'atlas',
      null => 'none',
    };
    final textureValue = textureFrame?.assetPath ?? _rectLabel(textureFrame);

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              color: Colors.white,
              fontSize: 11,
              height: 1.25,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('character: $characterLabel'),
                Text('clip: $clipName'),
                Text('backend: $backend${isLoading ? ' (loading)' : ''}'),
                Text('frame: ${frameIndex + 1}/$frameCount'),
                Text('texture: $textureValue'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _rectLabel(TextureFrame? frame) {
    final rect = frame?.sourceRect;
    if (rect == null) {
      return 'unresolved';
    }

    return 'rect(${rect.left.toStringAsFixed(0)},${rect.top.toStringAsFixed(0)},${rect.width.toStringAsFixed(0)},${rect.height.toStringAsFixed(0)})';
  }
}

class _TextureFrameView extends StatelessWidget {
  const _TextureFrameView({
    required this.textureFrame,
    required this.label,
    required this.frameIndex,
  });

  final TextureFrame textureFrame;
  final String label;
  final int frameIndex;

  @override
  Widget build(BuildContext context) {
    final assetPath = textureFrame.assetPath;
    if (assetPath != null) {
      return Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: <Widget>[
          _PngContactShadow(assetPath: assetPath),
          Align(
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              assetPath,
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) {
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      );
    }

    final image = textureFrame.image;
    final sourceRect = textureFrame.sourceRect;
    final frameWidth = textureFrame.frameWidth;
    final frameHeight = textureFrame.frameHeight;
    final shadowAssetPath = textureFrame.shadowAssetPath;
    if (image == null ||
        sourceRect == null ||
        frameWidth == null ||
        frameHeight == null) {
      return const SizedBox.shrink();
    }

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: <Widget>[
        if (shadowAssetPath != null)
          _PngContactShadow(assetPath: shadowAssetPath)
        else
          const _FallbackContactShadow(),
        CustomPaint(
          painter: _SpriteSheetFramePainter(
            image: image,
            sourceRect: sourceRect,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
          ),
        ),
      ],
    );
  }
}

class _PngContactShadow extends StatelessWidget {
  const _PngContactShadow({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stageHeight = constraints.maxHeight;
            final verticalOffset = -(stageHeight * 0.019);
            final blurSigma = (stageHeight * 0.0115).clamp(3.5, 6.5);

            return Transform.translate(
              offset: Offset(0, verticalOffset),
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.skewX(-0.5),
                child: Transform.scale(
                  scaleX: 1.06,
                  scaleY: 0.26,
                  alignment: Alignment.bottomCenter,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: blurSigma,
                      sigmaY: blurSigma,
                    ),
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.16),
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        assetPath,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.low,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FallbackContactShadow extends StatelessWidget {
  const _FallbackContactShadow();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stageWidth = constraints.maxWidth;
            final stageHeight = constraints.maxHeight;

            return Transform.translate(
              offset: Offset(0, stageHeight * 0.0345),
              child: Transform.scale(
                scaleX: 0.58,
                scaleY: 0.11,
                child: Container(
                  width: stageWidth * 0.5817,
                  height: stageHeight * 0.2299,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: RadialGradient(
                      colors: <Color>[
                        Colors.black.withValues(alpha: 0.24),
                        Colors.black.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                      stops: const <double>[0.0, 0.62, 1.0],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SpriteSheetFramePainter extends CustomPainter {
  const _SpriteSheetFramePainter({
    required this.image,
    required this.sourceRect,
    required this.frameWidth,
    required this.frameHeight,
  });

  final ui.Image image;
  final Rect sourceRect;
  final double frameWidth;
  final double frameHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final fittedSizes = applyBoxFit(
      BoxFit.contain,
      Size(frameWidth, frameHeight),
      size,
    );
    final destinationRect = Alignment.bottomCenter.inscribe(
      fittedSizes.destination,
      Offset.zero & size,
    );
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = false;

    canvas.drawImageRect(image, sourceRect, destinationRect, paint);
  }

  @override
  bool shouldRepaint(covariant _SpriteSheetFramePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.sourceRect != sourceRect ||
        oldDelegate.frameWidth != frameWidth ||
        oldDelegate.frameHeight != frameHeight;
  }
}
