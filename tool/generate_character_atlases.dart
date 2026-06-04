import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int _atlasExtrusionPx = 3;

void main(List<String> args) {
  final repoRoot = Directory.current;
  final charactersRoot = Directory(
    _join(repoRoot.path, 'assets', 'characters'),
  );

  if (!charactersRoot.existsSync()) {
    stderr.writeln('Could not find assets/characters under ${repoRoot.path}.');
    exitCode = 1;
    return;
  }

  final scale = _parseScaleArg(args);
  final matchFrames = _parseMatchFramesArg(args);
  final rawTargets = args
      .where((arg) => !arg.startsWith('--'))
      .toList(growable: false);

  final animationDirs = _collectTargetAnimationDirs(
    repoRoot: repoRoot,
    charactersRoot: charactersRoot,
    rawTargets: rawTargets,
  );

  if (animationDirs.isEmpty) {
    stderr.writeln(
      args.isEmpty
          ? 'No character animation directories were found.'
          : 'No matching animation directories were found for: ${args.join(', ')}',
    );
    exitCode = 1;
    return;
  }

  var generatedCount = 0;
  for (final animationDir in animationDirs) {
    final generated = _generateAtlasForDirectory(
      animationDir,
      scale: scale,
      matchFrames: matchFrames,
    );
    if (generated) {
      generatedCount += 1;
    }
  }

  stdout.writeln(
    'Generated atlases for $generatedCount animation directories.',
  );
}

List<Directory> _collectTargetAnimationDirs({
  required Directory repoRoot,
  required Directory charactersRoot,
  required List<String> rawTargets,
}) {
  if (rawTargets.isEmpty) {
    return charactersRoot
        .listSync(recursive: true, followLinks: false)
        .whereType<Directory>()
        .where((directory) => _isAnimationDirectory(directory.path))
        .toList(growable: false)
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  final resolvedDirs = <String, Directory>{};
  for (final rawTarget in rawTargets) {
    final entity = _resolveTargetEntity(repoRoot, rawTarget);
    if (entity == null) {
      stderr.writeln('Skipping $rawTarget: path not found.');
      continue;
    }

    final animationDir = _animationDirectoryForEntity(entity);
    if (animationDir == null) {
      stderr.writeln(
        'Skipping $rawTarget: expected a PNG frame or animation directory.',
      );
      continue;
    }

    resolvedDirs[animationDir.path] = animationDir;
  }

  return resolvedDirs.values.toList(growable: false)
    ..sort((a, b) => a.path.compareTo(b.path));
}

FileSystemEntity? _resolveTargetEntity(Directory repoRoot, String rawTarget) {
  final directType = FileSystemEntity.typeSync(rawTarget);
  if (directType != FileSystemEntityType.notFound) {
    return _entityFromType(rawTarget, directType);
  }

  final relativePath = _normalizeRelativePath(rawTarget);
  final repoRelativePath = _join(repoRoot.path, relativePath);
  final repoRelativeType = FileSystemEntity.typeSync(repoRelativePath);
  if (repoRelativeType != FileSystemEntityType.notFound) {
    return _entityFromType(repoRelativePath, repoRelativeType);
  }

  return null;
}

FileSystemEntity? _entityFromType(String path, FileSystemEntityType type) {
  switch (type) {
    case FileSystemEntityType.directory:
      return Directory(path);
    case FileSystemEntityType.file:
      return File(path);
    case FileSystemEntityType.link:
    case FileSystemEntityType.unixDomainSock:
    case FileSystemEntityType.pipe:
    case FileSystemEntityType.notFound:
      return null;
  }

  return null;
}

Directory? _animationDirectoryForEntity(FileSystemEntity entity) {
  if (entity is Directory) {
    return _isAnimationDirectory(entity.path) ? entity : null;
  }

  if (entity is! File) {
    return null;
  }

  if (!entity.path.toLowerCase().endsWith('.png')) {
    return null;
  }

  final parent = entity.parent;
  return _isAnimationDirectory(parent.path) ? parent : null;
}

/// Parses an optional `--scale=<0..1>` argument. Returns 1.0 (no scaling) when
/// absent or invalid. Used to shrink the source frames before packing so the
/// resulting atlas holds fewer pixels (lower texture RAM).
double _parseScaleArg(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--scale=')) {
      final value = double.tryParse(arg.substring('--scale='.length));
      if (value != null && value > 0 && value <= 1.0) {
        return value;
      }
    }
  }
  return 1.0;
}

/// Parses an optional `--match-frames=14,15,16` argument: 1-indexed frame
/// numbers whose colour should be matched to the clip's last frame (which is
/// authored to match the blink/rest colour). Fixes AI-render colour drift on a
/// few frames without touching the others.
Set<int> _parseMatchFramesArg(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--match-frames=')) {
      return arg
          .substring('--match-frames='.length)
          .split(',')
          .map((token) => int.tryParse(token.trim()))
          .whereType<int>()
          .toSet();
    }
  }
  return const <int>{};
}

String _normalizeRelativePath(String rawPath) {
  return rawPath
      .replaceAll('/', Platform.pathSeparator)
      .replaceAll('\\', Platform.pathSeparator);
}

bool _generateAtlasForDirectory(
  Directory animationDir, {
  double scale = 1.0,
  Set<int> matchFrames = const <int>{},
}) {
  final frames =
      animationDir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.png'))
          .toList(growable: false)
        ..sort((a, b) => _frameOrder(a.path).compareTo(_frameOrder(b.path)));

  if (frames.isEmpty) {
    stderr.writeln('Skipping ${animationDir.path}: no PNG frames found.');
    return false;
  }

  final decodedFrames = <_DecodedFrame>[];
  var maxFrameWidth = 0;
  var maxFrameHeight = 0;

  for (final frameFile in frames) {
    final bytes = frameFile.readAsBytesSync();
    final image = img.decodePng(bytes);
    if (image == null) {
      stderr.writeln(
        'Skipping ${animationDir.path}: failed to decode ${frameFile.path}.',
      );
      return false;
    }

    var sanitized = _sanitizeTransparentPixels(image);
    if (scale != 1.0) {
      sanitized = img.copyResize(
        sanitized,
        width: math.max(1, (sanitized.width * scale).round()),
        height: math.max(1, (sanitized.height * scale).round()),
        interpolation: img.Interpolation.average,
      );
    }

    decodedFrames.add(
      _DecodedFrame(path: frameFile.path, image: sanitized),
    );
    maxFrameWidth = math.max(maxFrameWidth, sanitized.width);
    maxFrameHeight = math.max(maxFrameHeight, sanitized.height);
  }


  // Colour-match the requested frames to the clip's last frame (authored to the
  // blink/rest colour), fixing per-frame render colour drift.
  if (matchFrames.isNotEmpty && decodedFrames.length > 1) {
    final reference = _meanBodyColor(decodedFrames.last.image);
    if (reference[0] > 0 && reference[1] > 0 && reference[2] > 0) {
      for (final frameNumber in matchFrames) {
        final index = frameNumber - 1;
        if (index < 0 || index >= decodedFrames.length) {
          continue;
        }
        final image = decodedFrames[index].image;
        final mean = _meanBodyColor(image);
        if (mean[0] == 0 || mean[1] == 0 || mean[2] == 0) {
          continue;
        }
        _applyChannelGainInPlace(
          image,
          reference[0] / mean[0],
          reference[1] / mean[1],
          reference[2] / mean[2],
        );
      }
    }
  }

  final columns = math.max(1, math.sqrt(decodedFrames.length).ceil());
  final rows = (decodedFrames.length / columns).ceil();
  final cellWidth = maxFrameWidth + (_atlasExtrusionPx * 2);
  final cellHeight = maxFrameHeight + (_atlasExtrusionPx * 2);
  final atlas = img.Image(
    width: columns * cellWidth,
    height: rows * cellHeight,
    numChannels: 4,
  );

  final metadataFrames = <Map<String, int>>[];
  final packedFrames = <_PackedFrame>[];
  for (var index = 0; index < decodedFrames.length; index += 1) {
    final decodedFrame = decodedFrames[index];
    final column = index % columns;
    final row = index ~/ columns;
    final cellX = column * cellWidth;
    final cellY = row * cellHeight;
    final frameX = cellX + _atlasExtrusionPx;
    final frameY = cellY + _atlasExtrusionPx;

    _copyFramePixels(atlas, decodedFrame.image, frameX, frameY);
    _extrudeFrameEdges(
      atlas,
      decodedFrame.image,
      frameX,
      frameY,
      _atlasExtrusionPx,
    );
    metadataFrames.add(<String, int>{
      'x': frameX,
      'y': frameY,
      'width': decodedFrame.image.width,
      'height': decodedFrame.image.height,
    });
    packedFrames.add(
      _PackedFrame(
        sourcePath: decodedFrame.path,
        sourceImage: decodedFrame.image,
        frameX: frameX,
        frameY: frameY,
        cellX: cellX,
        cellY: cellY,
      ),
    );
  }

  final validationIssues = _validatePackedFrames(
    atlas: atlas,
    packedFrames: packedFrames,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
  );

  final parentDir = animationDir.parent;
  final animationName = animationDir.uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .last;
  final atlasImageFile = File(_join(parentDir.path, '$animationName.png'));
  final atlasMetadataFile = File(_join(parentDir.path, '$animationName.json'));

  atlasImageFile.writeAsBytesSync(img.encodePng(atlas, level: 6));
  atlasMetadataFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(<String, Object>{
      'frames': metadataFrames,
      // Frames are rendered as-authored (BoxFit.contain, bottomCenter); the art's
      // own padding defines where the character sits. Kept at 0 so every clip /
      // character lands at the same position — no grounding shift.
      'bottomInset': 0.0,
    }),
  );

  stdout.writeln('Generated ${atlasImageFile.path}');
  stdout.writeln('Generated ${atlasMetadataFile.path}');
  if (validationIssues.isEmpty) {
    stdout.writeln('Validated ${packedFrames.length} frames: no edge deltas.');
  } else {
    stderr.writeln(
      'Validation flagged ${validationIssues.length} frame issue(s) in ${animationDir.path}:',
    );
    for (final issue in validationIssues) {
      stderr.writeln('  - ${issue.describe()}');
    }
  }
  return true;
}

/// Mean RGB of the opaque body pixels (alpha > 200), as [r, g, b] doubles.
List<double> _meanBodyColor(img.Image image) {
  var r = 0.0;
  var g = 0.0;
  var b = 0.0;
  var count = 0;
  for (var y = 0; y < image.height; y += 2) {
    for (var x = 0; x < image.width; x += 2) {
      final pixel = image.getPixel(x, y);
      if (pixel.a > 200) {
        r += pixel.r;
        g += pixel.g;
        b += pixel.b;
        count += 1;
      }
    }
  }
  if (count == 0) {
    return <double>[0, 0, 0];
  }
  return <double>[r / count, g / count, b / count];
}

/// Multiplies each pixel's RGB by the per-channel gains (alpha untouched),
/// clamped to 0..255. Mutates [image] in place.
void _applyChannelGainInPlace(img.Image image, double gr, double gg, double gb) {
  for (var y = 0; y < image.height; y += 1) {
    for (var x = 0; x < image.width; x += 1) {
      final pixel = image.getPixel(x, y);
      image.setPixelRgba(
        x,
        y,
        (pixel.r * gr).clamp(0, 255).round(),
        (pixel.g * gg).clamp(0, 255).round(),
        (pixel.b * gb).clamp(0, 255).round(),
        pixel.a,
      );
    }
  }
}

/// Smallest number of fully-transparent rows at the bottom across all frames.
/// Cropping by this seats the feet at the frame bottom without clipping any
/// frame's content.

List<_FrameValidationIssue> _validatePackedFrames({
  required img.Image atlas,
  required List<_PackedFrame> packedFrames,
  required int cellWidth,
  required int cellHeight,
}) {
  final issues = <_FrameValidationIssue>[];

  for (var index = 0; index < packedFrames.length; index += 1) {
    final packedFrame = packedFrames[index];

    if (packedFrame.frameX - packedFrame.cellX != _atlasExtrusionPx ||
        packedFrame.frameY - packedFrame.cellY != _atlasExtrusionPx) {
      issues.add(
        _FrameValidationIssue(
          framePath: packedFrame.sourcePath,
          frameIndex: index,
          kind: 'spacing',
          details:
              'frame offset inside cell is ${packedFrame.frameX - packedFrame.cellX},${packedFrame.frameY - packedFrame.cellY}; expected $_atlasExtrusionPx,$_atlasExtrusionPx',
        ),
      );
    }

    if (packedFrame.cellX + cellWidth > atlas.width ||
        packedFrame.cellY + cellHeight > atlas.height) {
      issues.add(
        _FrameValidationIssue(
          framePath: packedFrame.sourcePath,
          frameIndex: index,
          kind: 'packing',
          details: 'cell overflows atlas bounds',
        ),
      );
      continue;
    }

    final cropMismatchCount = _countCropEdgeMismatches(atlas, packedFrame);
    if (cropMismatchCount > 0) {
      issues.add(
        _FrameValidationIssue(
          framePath: packedFrame.sourcePath,
          frameIndex: index,
          kind: 'crop-edge',
          details: '$cropMismatchCount border pixel(s) differ from source crop',
        ),
      );
    }

    final extrusionMismatchCount = _countExtrusionMismatches(
      atlas,
      packedFrame,
    );
    if (extrusionMismatchCount > 0) {
      issues.add(
        _FrameValidationIssue(
          framePath: packedFrame.sourcePath,
          frameIndex: index,
          kind: 'extrusion',
          details:
              '$extrusionMismatchCount extruded border pixel(s) differ from expected edge copies',
        ),
      );
    }
  }

  return issues;
}

int _countCropEdgeMismatches(img.Image atlas, _PackedFrame packedFrame) {
  final source = packedFrame.sourceImage;
  var mismatchCount = 0;

  for (var x = 0; x < source.width; x += 1) {
    if (!_samePixel(
      source.getPixel(x, 0),
      atlas.getPixel(packedFrame.frameX + x, packedFrame.frameY),
    )) {
      mismatchCount += 1;
    }
    if (!_samePixel(
      source.getPixel(x, source.height - 1),
      atlas.getPixel(
        packedFrame.frameX + x,
        packedFrame.frameY + source.height - 1,
      ),
    )) {
      mismatchCount += 1;
    }
  }

  for (var y = 0; y < source.height; y += 1) {
    if (!_samePixel(
      source.getPixel(0, y),
      atlas.getPixel(packedFrame.frameX, packedFrame.frameY + y),
    )) {
      mismatchCount += 1;
    }
    if (!_samePixel(
      source.getPixel(source.width - 1, y),
      atlas.getPixel(
        packedFrame.frameX + source.width - 1,
        packedFrame.frameY + y,
      ),
    )) {
      mismatchCount += 1;
    }
  }

  return mismatchCount;
}

int _countExtrusionMismatches(img.Image atlas, _PackedFrame packedFrame) {
  final source = packedFrame.sourceImage;
  var mismatchCount = 0;

  for (var offset = 1; offset <= _atlasExtrusionPx; offset += 1) {
    final dstLeftX = packedFrame.frameX - offset;
    final dstRightX = packedFrame.frameX + source.width - 1 + offset;
    final dstTopY = packedFrame.frameY - offset;
    final dstBottomY = packedFrame.frameY + source.height - 1 + offset;

    for (var y = 0; y < source.height; y += 1) {
      if (!_samePixel(
        source.getPixel(0, y),
        atlas.getPixel(dstLeftX, packedFrame.frameY + y),
      )) {
        mismatchCount += 1;
      }
      if (!_samePixel(
        source.getPixel(source.width - 1, y),
        atlas.getPixel(dstRightX, packedFrame.frameY + y),
      )) {
        mismatchCount += 1;
      }
    }

    for (var x = 0; x < source.width; x += 1) {
      if (!_samePixel(
        source.getPixel(x, 0),
        atlas.getPixel(packedFrame.frameX + x, dstTopY),
      )) {
        mismatchCount += 1;
      }
      if (!_samePixel(
        source.getPixel(x, source.height - 1),
        atlas.getPixel(packedFrame.frameX + x, dstBottomY),
      )) {
        mismatchCount += 1;
      }
    }

    if (!_samePixel(source.getPixel(0, 0), atlas.getPixel(dstLeftX, dstTopY))) {
      mismatchCount += 1;
    }
    if (!_samePixel(
      source.getPixel(source.width - 1, 0),
      atlas.getPixel(dstRightX, dstTopY),
    )) {
      mismatchCount += 1;
    }
    if (!_samePixel(
      source.getPixel(0, source.height - 1),
      atlas.getPixel(dstLeftX, dstBottomY),
    )) {
      mismatchCount += 1;
    }
    if (!_samePixel(
      source.getPixel(source.width - 1, source.height - 1),
      atlas.getPixel(dstRightX, dstBottomY),
    )) {
      mismatchCount += 1;
    }
  }

  return mismatchCount;
}

bool _samePixel(img.Pixel a, img.Pixel b) {
  return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a;
}

img.Image _sanitizeTransparentPixels(img.Image source) {
  final sanitized = img.Image.from(source);

  for (var y = 0; y < sanitized.height; y += 1) {
    for (var x = 0; x < sanitized.width; x += 1) {
      final pixel = sanitized.getPixel(x, y);
      if (pixel.aNormalized == 0) {
        sanitized.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }

  return sanitized;
}

void _copyFramePixels(
  img.Image atlas,
  img.Image frame,
  int frameX,
  int frameY,
) {
  for (var y = 0; y < frame.height; y += 1) {
    for (var x = 0; x < frame.width; x += 1) {
      atlas.setPixel(frameX + x, frameY + y, frame.getPixel(x, y));
    }
  }
}

void _extrudeFrameEdges(
  img.Image atlas,
  img.Image frame,
  int frameX,
  int frameY,
  int extrusionPx,
) {
  if (extrusionPx <= 0) {
    return;
  }

  final frameWidth = frame.width;
  final frameHeight = frame.height;

  for (var offset = 1; offset <= extrusionPx; offset += 1) {
    final dstLeftX = frameX - offset;
    final dstRightX = frameX + frameWidth - 1 + offset;
    final dstTopY = frameY - offset;
    final dstBottomY = frameY + frameHeight - 1 + offset;

    for (var y = 0; y < frameHeight; y += 1) {
      atlas.setPixel(dstLeftX, frameY + y, frame.getPixel(0, y));
      atlas.setPixel(dstRightX, frameY + y, frame.getPixel(frameWidth - 1, y));
    }

    for (var x = 0; x < frameWidth; x += 1) {
      atlas.setPixel(frameX + x, dstTopY, frame.getPixel(x, 0));
      atlas.setPixel(
        frameX + x,
        dstBottomY,
        frame.getPixel(x, frameHeight - 1),
      );
    }

    atlas.setPixel(dstLeftX, dstTopY, frame.getPixel(0, 0));
    atlas.setPixel(dstRightX, dstTopY, frame.getPixel(frameWidth - 1, 0));
    atlas.setPixel(dstLeftX, dstBottomY, frame.getPixel(0, frameHeight - 1));
    atlas.setPixel(
      dstRightX,
      dstBottomY,
      frame.getPixel(frameWidth - 1, frameHeight - 1),
    );
  }

  for (var offset = 1; offset <= extrusionPx; offset += 1) {
    for (var innerOffset = 1; innerOffset < extrusionPx; innerOffset += 1) {
      atlas.setPixel(
        frameX - offset,
        frameY - innerOffset,
        frame.getPixel(0, 0),
      );
      atlas.setPixel(
        frameX + frameWidth - 1 + offset,
        frameY - innerOffset,
        frame.getPixel(frameWidth - 1, 0),
      );
      atlas.setPixel(
        frameX - offset,
        frameY + frameHeight - 1 + innerOffset,
        frame.getPixel(0, frameHeight - 1),
      );
      atlas.setPixel(
        frameX + frameWidth - 1 + offset,
        frameY + frameHeight - 1 + innerOffset,
        frame.getPixel(frameWidth - 1, frameHeight - 1),
      );
    }
  }
}

bool _isAnimationDirectory(String directoryPath) {
  final normalizedPath = directoryPath.replaceAll('\\', '/');
  return normalizedPath.endsWith('/idle_blink') ||
      normalizedPath.endsWith('/idle_sway') ||
      normalizedPath.endsWith('/idle_yawn') ||
      normalizedPath.endsWith('/reaction_head') ||
      normalizedPath.endsWith('/reaction_belly') ||
      normalizedPath.endsWith('/reaction_legs');
}

int _frameOrder(String filePath) {
  final normalizedPath = filePath.replaceAll('\\', '/');
  final fileName = normalizedPath.split('/').last;
  final stem = fileName.replaceFirst(
    RegExp(r'\.png$', caseSensitive: false),
    '',
  );
  return int.tryParse(stem) ?? 0;
}

String _join(String first, String second, [String? third, String? fourth]) {
  final parts = <String>[first, second];
  if (third != null) {
    parts.add(third);
  }
  if (fourth != null) {
    parts.add(fourth);
  }
  return parts.join(Platform.pathSeparator);
}

class _DecodedFrame {
  const _DecodedFrame({required this.path, required this.image});

  final String path;
  final img.Image image;
}

class _PackedFrame {
  const _PackedFrame({
    required this.sourcePath,
    required this.sourceImage,
    required this.frameX,
    required this.frameY,
    required this.cellX,
    required this.cellY,
  });

  final String sourcePath;
  final img.Image sourceImage;
  final int frameX;
  final int frameY;
  final int cellX;
  final int cellY;
}

class _FrameValidationIssue {
  const _FrameValidationIssue({
    required this.framePath,
    required this.frameIndex,
    required this.kind,
    required this.details,
  });

  final String framePath;
  final int frameIndex;
  final String kind;
  final String details;

  String describe() {
    final normalizedPath = framePath.replaceAll('\\', '/');
    final fileName = normalizedPath.split('/').last;
    return 'frame ${frameIndex + 1} ($fileName) [$kind]: $details';
  }
}
