import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/challenge_model.dart';
import '../models/completion_model.dart';
import '../repositories/challenge_repository.dart';
import 'auth_providers.dart';
import 'user_providers.dart';

// ── Repository ────────────────────────────────────────────────────────────────

final challengeRepositoryProvider = Provider<ChallengeRepository>((ref) {
  return ChallengeRepository(
    firestoreService: ref.watch(firestoreServiceProvider),
  );
});

// ── Streams ───────────────────────────────────────────────────────────────────

final todaysChallengeProvider = StreamProvider<ChallengeModel?>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(challengeRepositoryProvider).watchTodaysChallenge(uid);
});

final recentCompletionsProvider = StreamProvider<List<CompletionModel>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(challengeRepositoryProvider).watchRecentCompletions(uid);
});

// ── Path node types ───────────────────────────────────────────────────────────

sealed class PathNode {
  const PathNode({required this.date, required this.dayNumber});
  final DateTime date;
  final int dayNumber;
}

final class ActivePathNode extends PathNode {
  const ActivePathNode({required super.date, required super.dayNumber, this.challenge});
  final ChallengeModel? challenge;
}

final class CompletedPathNode extends PathNode {
  const CompletedPathNode({required super.date, required super.dayNumber, required this.completion});
  final CompletionModel completion;
}

final class MissedPathNode extends PathNode {
  const MissedPathNode({required super.date, required super.dayNumber});
}

/// A future day that hasn't arrived yet — displayed locked on the path.
final class LockedPathNode extends PathNode {
  const LockedPathNode({required super.date, required super.dayNumber});
}

// ── Midnight tick — forces path nodes to rebuild when the calendar date rolls ──

final _midnightTickProvider = StreamProvider<int>((ref) async* {
  var tick = 0;
  yield tick;
  while (true) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    await Future<void>.delayed(tomorrow.difference(now));
    yield ++tick;
  }
});

// ── Home path synthesis ───────────────────────────────────────────────────────

final homePathNodesProvider = Provider<AsyncValue<List<PathNode>>>((ref) {
  ref.watch(_midnightTickProvider); // rebuild daily so DateTime.now() is fresh
  final challengeAsync = ref.watch(todaysChallengeProvider);
  final completionsAsync = ref.watch(recentCompletionsProvider);

  if (challengeAsync.isLoading || completionsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (challengeAsync.hasError) {
    return AsyncValue.error(
      challengeAsync.error!,
      challengeAsync.stackTrace ?? StackTrace.empty,
    );
  }

  return AsyncValue.data(
    _buildPathNodes(
      challengeAsync.valueOrNull,
      completionsAsync.valueOrNull ?? const [],
    ),
  );
});

List<PathNode> _buildPathNodes(
  ChallengeModel? challenge,
  List<CompletionModel> completions,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final todayDayNumber = challenge?.dayNumber ?? 1;

  final completedByDate = {
    for (final c in completions) c.dateOnly: c,
  };

  final nodes = <PathNode>[];

  // Index 0 is always today.
  final todayCompletion = completedByDate[today];
  nodes.add(
    todayCompletion != null
        ? CompletedPathNode(date: today, dayNumber: todayDayNumber, completion: todayCompletion)
        : ActivePathNode(date: today, dayNumber: todayDayNumber, challenge: challenge),
  );

  // Past 13 days — completed or missed. Skip days before Day 1.
  for (var i = 1; i <= 13; i++) {
    final day = today.subtract(Duration(days: i));
    final dayNum = todayDayNumber - i;
    if (dayNum <= 0) break; // don't show Day 0 or negative days
    final completion = completedByDate[day];
    nodes.add(
      completion != null
          ? CompletedPathNode(date: day, dayNumber: dayNum, completion: completion)
          : MissedPathNode(date: day, dayNumber: dayNum),
    );
  }

  // Future 7 days — shown as locked so the trail always has nodes to scroll through.
  for (var i = 1; i <= 7; i++) {
    final day = today.add(Duration(days: i));
    nodes.add(LockedPathNode(date: day, dayNumber: todayDayNumber + i));
  }

  return nodes;
}
