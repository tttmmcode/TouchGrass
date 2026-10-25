// Unit tests for planCompletionReward — the pure reward computation that
// UserRepository.commitCompletion writes in one atomic batch with the
// completion (audit D-02), deciding "already completed today?" from
// lastCompletionDate only (audit D-01). The repository flow itself is
// covered against fake_cloud_firestore in commit_completion_test.dart.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/models/user_model.dart';
import 'package:touchgrass/repositories/user_repository.dart';

void main() {
  // Local noon, so calendar-day math is unaffected by the test machine's TZ.
  final now = DateTime(2026, 3, 11, 12);
  final yesterday = DateTime(2026, 3, 10, 12);
  final twoDaysAgo = DateTime(2026, 3, 9, 12);

  UserModel user({
    int xp = 100,
    int weeklyXp = 100,
    int streak = 1,
    int longestStreak = 1,
    int totalCompletions = 1,
    DateTime? lastActive,
    DateTime? weeklyReset,
    // xp_100 already earned: a 100-XP user qualifies for it, so leaving it
    // out would make every case below also unlock it.
    List<String> achievements = const ['first_touch', 'xp_100'],
    int freezes = 3,
  }) => UserModel(
    uid: 'u1',
    email: 'a@b.com',
    username: 'explorer_ab12',
    displayName: 'Explorer',
    xp: xp,
    weeklyXp: weeklyXp,
    weeklyXpResetDate: weeklyReset ?? DateTime.utc(2026, 3, 16),
    streak: streak,
    longestStreak: longestStreak,
    totalCompletions: totalCompletions,
    totalPhotosUploaded: 0,
    rainyDayCount: 0,
    currentLeague: 'seedling',
    createdAt: DateTime.utc(2026, 1, 1),
    lastActiveDate: (lastActive ?? now).toUtc(),
    achievements: achievements,
    settings: UserSettings.defaults().copyWith(streakFreezesOwned: freezes),
  );

  CompletionRewardPlan plan(
    UserModel current, {
    required DateTime? lastCompletion,
    int xp = 50,
    DateTime? at,
  }) => planCompletionReward(
    current: current,
    lastCompletionDate: lastCompletion?.toUtc(),
    xpAmount: xp,
    now: at ?? now,
  );

  // Exactly the keys firestore.rules' isCompletionReward() allows, minus
  // lastCompletionId (added by commitCompletion itself).
  const rulesRewardKeys = {
    'xp',
    'weeklyXp',
    'weeklyXpResetDate',
    'level',
    'streak',
    'longestStreak',
    'totalCompletions',
    'rainyDayCount',
    'currentLeague',
    'lastActiveDate',
    'achievements',
    'settings',
    'frozenDates',
    'lastCompletionDate',
  };
  Set<String> topLevelKeys(Map<String, dynamic> m) =>
      m.keys.map((k) => k.split('.').first).toSet()
        ..remove('achievementTimestamps');

  group('D-01 — sign-in never blocks a reward', () {
    test('brand-new account (signed up today, never completed) earns full XP '
        'and starts a streak of 1', () {
      final fresh = user(
        xp: 0,
        weeklyXp: 0,
        streak: 0,
        longestStreak: 0,
        totalCompletions: 0,
        achievements: const [],
        lastActive: now,
      );
      final p = plan(fresh, lastCompletion: null, xp: 25);
      expect(p.reward.xpAwarded, 25);
      expect(p.updateData['streak'], 1);
      expect(p.updateData['totalCompletions'], 1);
      expect(p.reward.newAchievements, ['first_touch']);
      // 25 challenge XP + 25 first_touch bonus.
      expect(p.updateData['xp'], 50);
    });

    test('returning user who signed in today but last completed yesterday '
        'earns XP and extends the streak', () {
      final p = plan(user(lastActive: now), lastCompletion: yesterday);
      expect(p.reward.xpAwarded, 50);
      expect(p.updateData['streak'], 2);
    });

    test('lastActiveDate (sign-in) is ignored entirely — only the '
        'completion date matters', () {
      final signedInToday = plan(
        user(lastActive: now),
        lastCompletion: yesterday,
      );
      final signedInLongAgo = plan(
        user(lastActive: DateTime(2025, 1, 1)),
        lastCompletion: yesterday,
      );
      expect(signedInToday.updateData['xp'], signedInLongAgo.updateData['xp']);
      expect(
        signedInToday.updateData['streak'],
        signedInLongAgo.updateData['streak'],
      );
    });

    test('stamps lastCompletionDate with the server clock', () {
      final p = plan(user(), lastCompletion: yesterday);
      expect(p.updateData['lastCompletionDate'], FieldValue.serverTimestamp());
      expect(p.reward.updatedUser.lastCompletionDate, now.toUtc());
    });
  });

  group('day boundaries', () {
    test('23:59 yesterday → 00:01 today is a new day (+XP, streak +1)', () {
      final p = plan(
        user(),
        lastCompletion: DateTime(2026, 3, 10, 23, 59),
        at: DateTime(2026, 3, 11, 0, 1),
      );
      expect(p.reward.xpAwarded, 50);
      expect(p.updateData['streak'], 2);
    });

    test('00:01 → 23:59 the same day is a repeat (no XP)', () {
      final p = plan(
        user(),
        lastCompletion: DateTime(2026, 3, 11, 0, 1),
        at: DateTime(2026, 3, 11, 23, 59),
      );
      expect(p.reward.xpAwarded, 0);
      expect(p.updateData['streak'], 1);
    });

    test('a gap of several days restarts the streak at 1', () {
      final p = plan(
        user(streak: 9, longestStreak: 9),
        lastCompletion: DateTime(2026, 3, 1),
      );
      expect(p.updateData['streak'], 1);
      expect(p.updateData['longestStreak'], 9);
      expect(p.reward.xpAwarded, 50);
    });
  });

  group('consecutive day', () {
    final p = plan(user(), lastCompletion: yesterday);

    test('awards the challenge XP and extends the streak', () {
      expect(p.reward.xpAwarded, 50);
      expect(p.updateData['xp'], 150);
      expect(p.updateData['streak'], 2);
      expect(p.updateData['longestStreak'], 2);
      expect(p.updateData['totalCompletions'], 2);
      expect(p.updateData['weeklyXp'], 150);
    });

    test('level and league are derived from total XP', () {
      expect(p.updateData['level'], 2);
      expect(p.updateData['currentLeague'], 'seedling');
    });

    test(
      'lastActiveDate is a server timestamp (rules require request.time)',
      () {
        expect(p.updateData['lastActiveDate'], FieldValue.serverTimestamp());
      },
    );

    test('only writes fields the security rules accept for a reward', () {
      expect(rulesRewardKeys.containsAll(topLevelKeys(p.updateData)), isTrue);
    });
  });

  group('same-day resubmission', () {
    final p = plan(user(), lastCompletion: now);
    test('awards nothing and keeps the streak', () {
      expect(p.reward.xpAwarded, 0);
      expect(p.updateData['xp'], 100);
      expect(p.updateData['streak'], 1);
      expect(p.updateData['totalCompletions'], 1);
    });
  });

  group('achievements', () {
    test('a newly qualifying achievement is awarded even on a same-day '
        'resubmission (bonus only, no challenge XP)', () {
      final p = plan(
        user(achievements: const ['first_touch']),
        lastCompletion: now,
      );
      expect(p.reward.newAchievements, ['xp_100']);
      expect(p.reward.xpAwarded, 0);
      expect(p.updateData['xp'], 125);
    });

    test('streak_3 is earned with its exact +50 XP bonus', () {
      final p = plan(
        user(streak: 2, longestStreak: 2),
        lastCompletion: yesterday,
      );
      expect(p.reward.newAchievements, ['streak_3']);
      // 100 + 50 (challenge) + 50 (streak_3 bonus).
      expect(p.updateData['xp'], 200);
      expect(p.updateData['weeklyXp'], 200);
      expect(
        p.updateData.containsKey('achievementTimestamps.streak_3'),
        isTrue,
      );
    });
  });

  group('Rainy Days', () {
    test('one missed day consumes a freeze and records the frozen date', () {
      final p = plan(
        user(streak: 4, longestStreak: 4),
        lastCompletion: twoDaysAgo,
      );
      expect(p.reward.rainyDayConsumed, isTrue);
      expect(p.updateData['streak'], 4);
      expect(p.updateData['rainyDayCount'], 1);
      expect(p.updateData['settings.streakFreezesOwned'], 2);
      expect(
        p.updateData['frozenDates'],
        FieldValue.arrayUnion(['2026-03-10']),
      );
    });

    test('reaching a 7-day streak earns one freeze', () {
      final p = plan(
        user(
          streak: 6,
          longestStreak: 6,
          achievements: const ['first_touch', 'streak_3', 'xp_100'],
        ),
        lastCompletion: yesterday,
      );
      expect(p.updateData['streak'], 7);
      expect(p.reward.rainyDayEarned, 1);
      expect(p.updateData['settings.streakFreezesOwned'], 4);
    });
  });

  group('weekly XP', () {
    test('restarts at this award once the weekly boundary has passed', () {
      final p = plan(
        user(weeklyXp: 900, weeklyReset: DateTime.utc(2026, 3, 9)),
        lastCompletion: yesterday,
      );
      expect(p.updateData['weeklyXp'], 50);
      expect(p.updateData['weeklyXpResetDate'], isA<Timestamp>());
    });
  });
}
