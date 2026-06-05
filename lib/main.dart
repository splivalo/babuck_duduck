import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';

/// Shared stopwatch for render-proof timing logs.
/// All log messages from render debugging reference [renderClock] so the
/// entire cold-start timeline is in a single monotonic reference frame.
final Stopwatch renderClock = Stopwatch()..start();

/// Helper: prints a line with milliseconds-since-app-start prefix.
///
/// Compiled out of release builds: in release [kDebugMode] is a const `false`,
/// so the tree-shaker drops the body (and the `print`) entirely. Callers should
/// still avoid building expensive log strings on per-frame hot paths.
void renderLog(String tag, String message) {
  if (!kDebugMode) {
    return;
  }
  // ignore: avoid_print
  print('[RENDER ${renderClock.elapsedMilliseconds}ms] [$tag] $message');
}

void main() {
  runApp(const BabuckDuduckApp());
}
