import 'package:flutter/widgets.dart';

import 'app.dart';

/// Shared stopwatch for render-proof timing logs.
/// All log messages from render debugging reference [renderClock] so the
/// entire cold-start timeline is in a single monotonic reference frame.
final Stopwatch renderClock = Stopwatch()..start();

/// Helper: prints a line with milliseconds-since-app-start prefix.
void renderLog(String tag, String message) {
  // ignore: avoid_print
  print('[RENDER ${renderClock.elapsedMilliseconds}ms] [$tag] $message');
}

void main() {
  runApp(const BabuckDuduckApp());
}
