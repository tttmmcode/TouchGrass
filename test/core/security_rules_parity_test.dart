// Drift guard between firestore.rules and the Dart models/constants.
//
// The rules are the only trusted enforcement layer (no backend yet), and
// they hard-code game constants and per-collection field allow-lists. If a
// model gains a field or a constant changes without the rules following,
// every affected write starts failing in production with permission-denied.
// These tests read the real rules file and fail fast instead. Behavioural
// allow/deny coverage lives in firestore-tests/ (emulator).

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/companions/companion.dart';
import 'package:touchgrass/core/constants/app_constants.dart';
import 'package:touchgrass/core/data/challenge_seed_library.dart';
import 'package:touchgrass/models/achievement_definition.dart';
import 'package:touchgrass/models/adventure_memory_model.dart';
import 'package:touchgrass/models/challenge_model.dart';
import 'package:touchgrass/models/completion_model.dart';
import 'package:touchgrass/models/user_model.dart';
import 'package:touchgrass/repositories/feedback_repository.dart';
import 'package:touchgrass/services/challenge_generation_service.dart';
import 'package:touchgrass/services/storage_service.dart';

void main() {
  final rules = File('firestore.rules').readAsStringSync();

  /// Body of `function <name>(...) { ... }` up to the next `function` or
  /// `match` declaration.
  String fn(String name) {
    final start = rules.indexOf('function $name(');
    expect(start, isNot(-1), reason: 'rules function $name() not found');
    final rest = rules.substring(start + 1);
    final next = RegExp(r'\n\s*(function |match )').firstMatch(rest);
    return next == null ? rest : rest.substring(0, next.start);
  }

  Set<String> quoted(String text) =>
      RegExp("'([^']*)'").allMatches(text).map((m) => m.group(1)!).toSet();

  /// The first `hasOnly([...])` list inside a rules function.
  Set<String> hasOnlyKeys(String functionName) {
    final body = fn(functionName);
    final m = RegExp(r'hasOnly\(\[([^\]]*)\]\)').firstMatch(body);
    expect(m, isNotNull, reason: 'no hasOnly([...]) in $functionName');
    return quoted(m!.group(1)!);
  }

  int returnsInt(String functionName) => int.parse(
    RegExp(r'return (\d+);').firstMatch(fn(functionName))!.group(1)!,
  );

  group('game constants', () {
    test('reroll cap', () {
      expect(returnsInt('maxRerolls'), AppConstants.maxRerollsPerDay);
    });
    test('streak-freeze cost', () {
      expect(returnsInt('freezeCostXp'), AppConstants.streakFreezeCostXp);
    });
    test('initial Rainy Days', () {
      expect(returnsInt('initialFreezes'), AppConstants.rainyDaysInitial);
    });
    test('level formula divisor', () {
      expect(fn('levelForXp'), contains('xp / ${AppConstants.xpPerLevel}'));
    });
    test('challenge XP per difficulty', () {
      final body = fn('xpForDifficulty');
      for (final d in ChallengeDifficulty.values) {
        expect(body, contains("difficulty == '${d.name}' ? ${d.xpReward}"));
      }
    });
    test(
      'achievement IDs, XP bonuses and thresholds cover the whole catalog',
      () {
        final ids = quoted(fn('achievementIds'));
        expect(ids, AchievementDefinition.catalog.map((a) => a.id).toSet());
        final bonus = fn('achievementBonus');
        for (final a in AchievementDefinition.catalog) {
          expect(bonus, contains("hasAny(['${a.id}']) ? ${a.xpReward} :"));
          expect(fn('achievementsEarned'), contains("hasAny(['${a.id}'])"));
        }
      },
    );
    test('feedback daily cap and message length', () {
      expect(returnsInt('maxFeedbackPerDay'), FeedbackRepository.maxPerDay);
      expect(
        fn('isValidFeedback'),
        contains('d.message.size() <= ${FeedbackRepository.maxMessageLength}'),
      );
    });
    test('feedback types', () {
      final body = fn('isValidFeedback');
      for (final t in FeedbackType.values) {
        expect(body, contains("'${t.name}'"));
      }
    });
    test('companion types', () {
      final body = fn('validEditableSettings');
      for (final t in CompanionType.values) {
        expect(body, contains("'${t.name}'"));
      }
    });
  });

  group('usernames satisfy the registry rule [a-z0-9_]{1,100}', () {
    final pattern = RegExp(r'^[a-z0-9_]{1,100}$');
    for (final name in [
      'Explorer',
      'Ünïcödé Nåme!!',
      '',
      'A very long display name ' * 10,
    ]) {
      test(
        'auto-generated from "${name.length > 20 ? '${name.substring(0, 20)}…' : name}"',
        () {
          final user = UserModel.initial(
            uid: 'AbCdEfGh1234',
            displayName: name,
          );
          expect(
            pattern.hasMatch(user.username),
            isTrue,
            reason: user.username,
          );
        },
      );
    }
  });

  group('field allow-lists match what the app writes', () {
    test('new user document (UserModel.toFirestore)', () {
      final doc = UserModel.initial(
        uid: 'u1',
        displayName: 'Explorer',
      ).toFirestore();
      expect(hasOnlyKeys('isValidNewProfile'), containsAll(doc.keys));
    });

    test('user settings map (UserSettings.toMap)', () {
      expect(
        quoted(fn('settingsKeys')),
        UserSettings.defaults().toMap().keys.toSet(),
      );
    });

    test('completion document (CompletionModel.toFirestore)', () {
      final doc = CompletionModel(
        id: 'u1_2026-03-11',
        userId: 'u1',
        challengeId: '2026-03-11',
        challengeTitle: 't',
        challengeEmoji: 'e',
        challengeCategory: ChallengeCategory.nature,
        photoUrl: 'p',
        verificationResult: const {'reason': 'r'},
        completedAt: DateTime(2026, 3, 11),
        xpAwarded: 50,
        overrideUsed: false,
        assignmentDate: DateTime(2026, 3, 11),
        location: const GeoPoint(1, 2),
        caption: 'c',
      ).toFirestore();
      expect(hasOnlyKeys('isValidNewCompletion'), containsAll(doc.keys));
    });

    test('per-user challenge document (ChallengeModel.toFirestore)', () {
      final seed = ChallengeSeedLibrary.selectSeed(
        dayNumber: 1,
        userId: 'u1',
        difficulty: ChallengeDifficulty.easy,
      );
      final doc = const ChallengeGenerationService()
          .generate(seed: seed, userId: 'u1', dayNumber: 1)
          .copyWith(completionDate: DateTime(2026, 3, 11))
          .toFirestore();
      expect(hasOnlyKeys('isValidChallengeContent'), containsAll(doc.keys));
    });

    test('location-derived memory fields gated by the D-09 setting', () {
      final keys = quoted(
        RegExp(
          r'return \[([^\]]*)\]',
        ).firstMatch(fn('locationDerivedKeys'))!.group(1)!,
      );
      expect(keys, {
        'latitude',
        'longitude',
        'locationName',
        'weatherCondition',
        'weatherEmoji',
      });
      expect(hasOnlyKeys('isValidNewMemory'), containsAll(keys));
    });

    test(
      'completion photo path matches the rules and storage.rules (D-13)',
      () {
        expect(
          completionPhotoPath('u1', '2026-03-11'),
          'completion_photos/u1/2026-03-11.jpg',
        );
        expect(
          fn('isValidNewCompletion'),
          contains("'%2F' + d.challengeId + '[.]jpg"),
        );
        expect(
          File('storage.rules').readAsStringSync(),
          contains("fileName.matches('[0-9]{4}-[0-9]{2}-[0-9]{2}[.]jpg')"),
        );
      },
    );

    test('memory document (AdventureMemoryModel.toFirestore)', () {
      final doc = AdventureMemoryModel(
        memoryId: 'm',
        userId: 'u1',
        challengeId: '2026-03-11',
        challengeDay: 1,
        challengeTitle: 't',
        challengeCategory: ChallengeCategory.nature,
        photoUrl: 'p',
        xpEarned: 50,
        verificationMethod: 'auto_approved',
        completionDate: DateTime(2026, 3, 11),
        createdAt: DateTime(2026, 3, 11),
        caption: 'c',
        captionPrompt: 'q',
        latitude: 1,
        longitude: 2,
        locationName: 'n',
        weatherCondition: 'w',
        weatherEmoji: 'x',
      ).toFirestore();
      expect(hasOnlyKeys('isValidNewMemory'), containsAll(doc.keys));
    });
  });
}
