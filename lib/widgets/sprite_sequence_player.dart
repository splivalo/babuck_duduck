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
        final clip = widget.controller.clip;
        final displayTextureFrame = widget.controller.displayTextureFrame;
        final hasDisplayTextureFrame = displayTextureFrame != null;

        final hadFirstTextureFrame = _hasFirstTextureFrame;
        if (hasDisplayTextureFrame) {
          if (!_hasFirstTextureFrame) {
            _hasFirstTextureFrame = true;
            renderLog(
              'SpriteSequencePlayer',
              'FIRST_VISIBLE_TEXTURE frame=${widget.controller.frameIndex} clip=${clip?.name ?? 'null'}',
            );
          }
        }

        final child = displayTextureFrame == null
            ? const SizedBox.shrink()
            : Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: <Widget>[
                  _contactShadow(displayTextureFrame),
                  _spriteContent(displayTextureFrame),
                ],
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

/// The on-floor contact shadow for [textureFrame]. Rendered outside the clip
/// crossfade so it doesn't double up during a transition.
Widget _contactShadow(TextureFrame textureFrame) {
  final assetPath = textureFrame.assetPath;
  if (assetPath != null) {
    return _PngContactShadow(assetPath: assetPath);
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

  if (shadowAssetPath != null) {
    return _PngContactShadow(assetPath: shadowAssetPath);
  }

  return _SpriteSheetContactShadow(
    image: image,
    sourceRect: textureFrame.shadowSourceRect ?? sourceRect,
    frameWidth: frameWidth,
    frameHeight: frameHeight,
    bottomInset: textureFrame.bottomInset,
  );
}

/// Just the character image for [textureFrame] (the part that cross-fades on a
/// clip change). Excludes the shadow.
Widget _spriteContent(TextureFrame textureFrame) {
  final assetPath = textureFrame.assetPath;
  if (assetPath != null) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        alignment: Alignment.bottomCenter,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      ),
    );
  }

  final image = textureFrame.image;
  final sourceRect = textureFrame.sourceRect;
  final frameWidth = textureFrame.frameWidth;
  final frameHeight = textureFrame.frameHeight;
  if (image == null ||
      sourceRect == null ||
      frameWidth == null ||
      frameHeight == null) {
    return const SizedBox.shrink();
  }

  return CustomPaint(
    painter: _SpriteSheetFramePainter(
      image: image,
      sourceRect: sourceRect,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      bottomInset: textureFrame.bottomInset,
    ),
  );
}

/// Shared transform/blur/tint stack that turns any [child] into an on-floor
/// contact shadow: skewed, squashed, blurred and darkened, anchored to the
/// bottom-center of the stage. The two callers differ only in the leaf they
/// supply — a standalone PNG ([_PngContactShadow]) or an atlas frame painter
/// ([_SpriteSheetContactShadow]).
class _ContactShadow extends StatelessWidget {
  const _ContactShadow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stageHeight = constraints.maxHeight;
            // Lift the shadow up toward the feet. Increase this fraction to move
            // the contact shadow higher (closer to the soles), decrease to drop
            // it. Shared by all characters.
            final verticalOffset = -(stageHeight * 0.045);
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
                      child: child,
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

class _PngContactShadow extends StatelessWidget {
  const _PngContactShadow({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return _ContactShadow(
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        alignment: Alignment.bottomCenter,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      ),
    );
  }
}

/// Contact shadow for atlas (sprite-sheet) frames: paints the same frame as a
/// blurred, skewed, darkened silhouette on the floor — the real character
/// shape, not a generic ellipse. Mirrors [_PngContactShadow] but sources the
/// frame from the atlas image + sourceRect instead of a standalone PNG.
class _SpriteSheetContactShadow extends StatelessWidget {
  const _SpriteSheetContactShadow({
    required this.image,
    required this.sourceRect,
    required this.frameWidth,
    required this.frameHeight,
    this.bottomInset = 0.0,
  });

  final ui.Image image;
  final Rect sourceRect;
  final double frameWidth;
  final double frameHeight;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return _ContactShadow(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _SpriteSheetFramePainter(
            image: image,
            sourceRect: sourceRect,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            bottomInset: bottomInset,
          ),
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
    this.bottomInset = 0.0,
  });

  final ui.Image image;
  final Rect sourceRect;
  final double frameWidth;
  final double frameHeight;

  /// Fraction of the frame that is empty below the feet; the frame is drawn
  /// shifted down by this much so the feet sit on the floor (see [TextureFrame]).
  final double bottomInset;

  @override
  void paint(Canvas canvas, Size size) {
    final fittedSizes = applyBoxFit(
      BoxFit.contain,
      Size(frameWidth, frameHeight),
      size,
    );
    final fitted = Alignment.bottomCenter.inscribe(
      fittedSizes.destination,
      Offset.zero & size,
    );
    final destinationRect = bottomInset == 0.0
        ? fitted
        : fitted.shift(Offset(0, bottomInset * fitted.height));
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
        oldDelegate.frameHeight != frameHeight ||
        oldDelegate.bottomInset != bottomInset;
  }
}
