import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onPrepare,
    required this.onFinished,
  });

  final Future<void> Function(BuildContext, ValueChanged<double>) onPrepare;

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const Duration _minimumVisibleDuration = Duration(milliseconds: 1200);

  bool _startedPreparation = false;
  double _progress = 0.0;
  final Stopwatch _visibleStopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _visibleStopwatch.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startPreparation();
    });
  }

  @override
  void dispose() {
    _visibleStopwatch.stop();
    super.dispose();
  }

  Future<void> _startPreparation() async {
    if (_startedPreparation || !mounted) {
      return;
    }

    _startedPreparation = true;

    await widget.onPrepare(context, (value) {
      if (!mounted) {
        return;
      }

      setState(() {
        _progress = value.clamp(0.0, 1.0);
      });
    });

    final remainingVisibleTime =
        _minimumVisibleDuration - _visibleStopwatch.elapsed;
    if (remainingVisibleTime > Duration.zero) {
      await Future<void>.delayed(remainingVisibleTime);
    }

    if (!mounted) {
      return;
    }

    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            'assets/ui/splash.jpg',
            key: const ValueKey<String>('app-splash-image'),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return const ColoredBox(color: Color(0xFFFFE4D2));
            },
          ),
          Align(
            alignment: const Alignment(0, 0.08),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: _progress),
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              builder: (context, animatedProgress, child) {
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              key: const ValueKey<String>(
                                'app-splash-progress',
                              ),
                              minHeight: 14,
                              value: animatedProgress,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.24,
                              ),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF7DB7FF),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
