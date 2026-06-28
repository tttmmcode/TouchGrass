import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper around Firebase Performance Monitoring.
///
/// Usage — wrap an async operation:
/// ```dart
/// final data = await PerfService.trace('challenge_load', () => loadChallenge());
/// ```
///
/// Usage — manual start/stop (for screen load times):
/// ```dart
/// final t = PerfService.newTrace('leaderboard_load')..start();
/// // ... when data arrives ...
/// t.stop();
/// ```
abstract final class PerfService {
  // ── Named trace constants ─────────────────────────────────────────────────────
  static const String traceStartup = 'app_startup';
  static const String traceChallengeLoad = 'challenge_load';
  static const String traceLeaderboardLoad = 'leaderboard_load';
  static const String traceMapLoad = 'map_load';
  static const String traceCameraLaunch = 'camera_launch';

  // ── API ───────────────────────────────────────────────────────────────────────

  /// Returns a started [Trace]. Call [Trace.stop] when the operation finishes.
  static Trace? startTrace(String name) {
    if (kIsWeb) return null;
    try {
      final t = FirebasePerformance.instance.newTrace(name);
      t.start();
      return t;
    } catch (e) {
      debugPrint('[PerfService] startTrace($name) error: $e');
      return null;
    }
  }

  /// Wraps [fn] in a named trace and returns its result.
  static Future<T> trace<T>(String name, Future<T> Function() fn) async {
    final t = startTrace(name);
    try {
      return await fn();
    } finally {
      await t?.stop();
    }
  }
}
