import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/result.dart';
import '../models/achievement_definition.dart';
import '../models/completion_reward.dart';
import '../models/league_definition.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

/// Orchestrates authentication, the Firestore user document, and profile
/// photo storage.
///
/// All public methods return [Result<T>] — callers never see raw exceptions.
class UserRepository {
  const UserRepository({
    required AuthService authService,
    required FirestoreService firestoreService,
    required StorageService storageService,
  })  : _auth = authService,
        _firestore = firestoreService,
        _storage = storageService;

  final AuthService _auth;
  final FirestoreService _firestore;
  final StorageService _storage;

  // ── Authentication ─────────────────────────────────────────────────────────

  Future<Result<UserModel>> signInWithGoogle() =>
      guardAsync(() async => _resolveUser(await _auth.signInWithGoogle()));

  Future<Result<UserModel>> signInWithApple() =>
      guardAsync(() async => _resolveUser(await _auth.signInWithApple()));

  Future<Result<void>> signOut() => guardAsync(_auth.signOut);

  Future<Result<UserModel>> signInWithEmail({
    required String email,
    required String password,
  }) =>
      guardAsync(() async => _resolveUser(
            await _auth.signInWithEmail(email: email, password: password),
          ));

  Future<Result<UserModel>> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) =>
      guardAsync(() async => _resolveUser(
            await _auth.signUpWithEmail(
              email: email,
              password: password,
              displayName: displayName,
            ),
          ));

  Future<Result<void>> sendPasswordResetEmail(String email) =>
      guardAsync(() => _auth.sendPasswordResetEmail(email));

  // ── User document ─────────────────────────────────────────────────────────

  /// Fetches the current user's document, or null if not signed in.
  Future<Result<UserModel?>> fetchCurrentUser() => guardAsync(() async {
        final uid = _auth.currentUser?.uid;
        if (uid == null) return null;
        return _fetchUser(uid);
      });

  /// Fetches a specific user's document by [uid], or null if it doesn't exist.
  Future<Result<UserModel?>> fetchUser(String uid) =>
      guardAsync(() => _fetchUser(uid));

  /// Real-time stream of the user document. Emits null when signed out.
  Stream<UserModel?> watchUser(String uid) {
    return _firestore
        .watchDocument(collection: AppConstants.colUsers, id: uid)
        .map((doc) => doc.exists ? UserModel.fromFirestore(doc) : null);
  }

  /// Applies a partial update to the user's Firestore document.
  Future<Result<void>> updateUserFields(
    String uid,
    Map<String, dynamic> fields,
  ) =>
      guardAsync(() => _firestore.updateDocument(
            collection: AppConstants.colUsers,
            id: uid,
            data: fields,
          ));

  /// Uploads a new profile photo, saves the URL in Firestore, and returns
  /// the download URL.
  Future<Result<String>> uploadProfilePhoto({
    required String uid,
    required Uint8List imageBytes,
  }) =>
      guardAsync(() async {
        final url = await _storage.uploadProfilePhoto(
          userId: uid,
          bytes: imageBytes,
        );
        await _firestore.updateDocument(
          collection: AppConstants.colUsers,
          id: uid,
          data: {
            'photoUrl': url,
            'totalPhotosUploaded': FieldValue.increment(1),
          },
        );
        final current = await _fetchUser(uid);
        if (current != null) {
          await _syncPublicMirror(current, overrides: {'photoUrl': url});
        }
        return url;
      });

  // ── XP & rewards ──────────────────────────────────────────────────────────

  /// Awards XP to a user and recalculates level atomically.
  Future<Result<UserModel>> awardXp(String uid, int amount) =>
      guardAsync(() async {
        final current = await _fetchUser(uid);
        if (current == null) throw DataException.notFound('User $uid');

        final updated = current.copyWith(xp: current.xp + amount);

        await _firestore.updateDocument(
          collection: AppConstants.colUsers,
          id: uid,
          data: {
            'xp': updated.xp,
            'level': updated.level,
          },
        );

        return updated;
      });

  /// Awards XP and updates the streak after a successful challenge completion.
  ///
  /// Streak rules:
  /// - `lastActiveDate` == today  → already completed, keep streak unchanged.
  /// - `lastActiveDate` == yesterday → consecutive day, increment streak.
  /// - anything older + freeze available → freeze absorbs miss, streak kept.
  /// - anything older + no freeze → reset streak to 1.
  Future<Result<CompletionReward>> awardCompletionRewards({
    required String uid,
    required int xpAmount,
  }) =>
      guardAsync(() async {
        final current = await _fetchUser(uid);
        if (current == null) throw DataException.notFound('User $uid');

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        // lastActiveDate is stored/parsed as UTC; convert to local before
        // extracting the calendar day so it's compared in the same
        // reference frame as `today` (local `DateTime.now()`).
        final lastActiveLocal = current.lastActiveDate.toLocal();
        final lastActive = DateTime(
          lastActiveLocal.year,
          lastActiveLocal.month,
          lastActiveLocal.day,
        );

        final streakOutcome = resolveStreakOutcome(
          today: today,
          lastActiveDay: lastActive,
          currentStreak: current.streak,
          freezesOwned: current.settings.streakFreezesOwned,
        );
        final newStreak = streakOutcome.newStreak;
        final rainyDayConsumed = streakOutcome.rainyDayConsumed;

        final newLongestStreak =
            newStreak > current.longestStreak ? newStreak : current.longestStreak;

        // Only award XP/completions on first submission of the day.
        final isNewCompletionToday = lastActive != today;
        final newTotalCompletions =
            isNewCompletionToday ? current.totalCompletions + 1 : current.totalCompletions;
        final baseXp = isNewCompletionToday ? current.xp + xpAmount : current.xp;
        final effectiveXpAwarded = isNewCompletionToday ? xpAmount : 0;

        // Weekly XP — reset if we've passed this week's reset boundary.
        final nowUtc = now.toUtc();
        final needsWeeklyReset = nowUtc.isAfter(current.weeklyXpResetDate);
        final baseWeeklyXp = isNewCompletionToday
            ? (needsWeeklyReset
                ? effectiveXpAwarded
                : current.weeklyXp + effectiveXpAwarded)
            : current.weeklyXp;
        final newWeeklyXpResetDate = (isNewCompletionToday && needsWeeklyReset)
            ? AppConstants.nextMondayMidnightUtc()
            : current.weeklyXpResetDate;

        final oldLevel = current.level;
        final baseLevel = AppConstants.levelForXp(baseXp);

        final newlyEarned = AchievementDefinition.computeNewlyEarned(
          alreadyEarned: current.achievements.toSet(),
          newXp: baseXp,
          newStreak: newStreak,
          newLevel: baseLevel,
          newTotalCompletions: newTotalCompletions,
        );

        // Newly-earned achievements carry their own XP reward (shown to the
        // user on the unlock card) — credit it now so level/league/
        // leaderboard reflect the true total for this completion instead of
        // silently never crediting it.
        final achievementXpBonus =
            AchievementDefinition.totalXpReward(newlyEarned);
        final newXp = baseXp + achievementXpBonus;
        final newWeeklyXp = baseWeeklyXp + achievementXpBonus;
        final newLevel = AppConstants.levelForXp(newXp);

        // League — always derived from total XP so it never drifts.
        final newLeague = LeagueDef.idForXp(newXp);

        // Rainy Day earnings at streak milestones (only when streak incremented).
        int rainyDayEarned = 0;
        if (newStreak != current.streak) {
          // Just hit 7-day milestone.
          if (newStreak == AppConstants.rainyDayEarnStreak7) rainyDayEarned = 1;
          // Just hit 30-day milestone.
          if (newStreak == AppConstants.rainyDayEarnStreak30) rainyDayEarned = 2;
        }

        int newFreezesOwned = current.settings.streakFreezesOwned;
        if (rainyDayConsumed) newFreezesOwned -= 1;
        if (rainyDayEarned > 0) newFreezesOwned += rainyDayEarned;

        // Track total Rainy Days consumed (repurposes rainyDayCount field).
        final newRainyDayCount =
            rainyDayConsumed ? current.rainyDayCount + 1 : current.rainyDayCount;

        // The freeze absorbs exactly one missed day — the one between
        // lastActive and today — so record that specific calendar date.
        // Without this, the streak calendar has no way to know WHICH day
        // was frozen versus genuinely missed; it can only see the lifetime
        // counter. Calendar-field arithmetic, not Duration subtraction, for
        // the same DST-safety reason as resolveStreakOutcome above.
        final frozenDateKey = rainyDayConsumed
            ? dateKeyForCalendarDay(DateTime(today.year, today.month, today.day - 1))
            : null;
        final newFrozenDates = frozenDateKey != null
            ? [...current.frozenDates, frozenDateKey]
            : current.frozenDates;

        final updateData = <String, dynamic>{
          'xp': newXp,
          'weeklyXp': newWeeklyXp,
          'level': newLevel,
          'streak': newStreak,
          'longestStreak': newLongestStreak,
          'totalCompletions': newTotalCompletions,
          'rainyDayCount': newRainyDayCount,
          'currentLeague': newLeague,
          'lastActiveDate': FieldValue.serverTimestamp(),
        };
        if (needsWeeklyReset && isNewCompletionToday) {
          updateData['weeklyXpResetDate'] =
              Timestamp.fromDate(newWeeklyXpResetDate);
        }
        if (newlyEarned.isNotEmpty) {
          updateData['achievements'] = FieldValue.arrayUnion(newlyEarned);
          for (final id in newlyEarned) {
            updateData['achievementTimestamps.$id'] =
                FieldValue.serverTimestamp();
          }
        }
        if (rainyDayConsumed || rainyDayEarned > 0) {
          updateData['settings.streakFreezesOwned'] = newFreezesOwned;
        }
        if (frozenDateKey != null) {
          updateData['frozenDates'] = FieldValue.arrayUnion([frozenDateKey]);
        }

        await _firestore.updateDocument(
          collection: AppConstants.colUsers,
          id: uid,
          data: updateData,
        );

        final updatedSettings =
            (rainyDayConsumed || rainyDayEarned > 0)
                ? current.settings.copyWith(streakFreezesOwned: newFreezesOwned)
                : current.settings;

        final updatedUser = current.copyWith(
          xp: newXp,
          weeklyXp: newWeeklyXp,
          weeklyXpResetDate: newWeeklyXpResetDate,
          streak: newStreak,
          longestStreak: newLongestStreak,
          totalCompletions: newTotalCompletions,
          rainyDayCount: newRainyDayCount,
          currentLeague: newLeague,
          lastActiveDate: now,
          achievements: [...current.achievements, ...newlyEarned],
          settings: updatedSettings,
          frozenDates: newFrozenDates,
        );

        await _syncPublicMirror(updatedUser);

        return CompletionReward(
          updatedUser: updatedUser,
          xpAwarded: effectiveXpAwarded,
          newStreak: newStreak,
          previousStreak: current.streak,
          leveledUp: newLevel > oldLevel,
          newLevel: newLevel,
          newAchievements: newlyEarned,
          rainyDayConsumed: rainyDayConsumed,
          rainyDayEarned: rainyDayEarned,
          rainyDaysAvailable: newFreezesOwned,
          previousLeague: current.currentLeague,
        );
      });

  /// Spends [AppConstants.streakFreezeCostXp] XP to purchase one streak freeze.
  Future<Result<UserModel>> buyStreakFreeze(String uid) =>
      guardAsync(() async {
        final current = await _fetchUser(uid);
        if (current == null) throw DataException.notFound('User $uid');

        if (current.xp < AppConstants.streakFreezeCostXp) {
          throw const DataException(
            message:
                'You need ${AppConstants.streakFreezeCostXp} XP to buy a streak freeze.',
          );
        }

        final newXp = current.xp - AppConstants.streakFreezeCostXp;
        final newFreezesOwned = current.settings.streakFreezesOwned + 1;
        // Spending XP is the one path that can move a user below their
        // current league's floor — recompute it so the stored field (and
        // the public leaderboard mirror) never goes stale.
        final newLeague = LeagueDef.idForXp(newXp);

        await _firestore.updateDocument(
          collection: AppConstants.colUsers,
          id: uid,
          data: {
            'xp': newXp,
            'currentLeague': newLeague,
            'settings.streakFreezesOwned': newFreezesOwned,
          },
        );

        final updated = current.copyWith(
          xp: newXp,
          currentLeague: newLeague,
          settings: current.settings.copyWith(
            streakFreezesOwned: newFreezesOwned,
          ),
        );
        await _syncPublicMirror(updated);
        return updated;
      });

  /// Saves the user's chosen companion type to Firestore.
  Future<Result<void>> updateCompanionType({
    required String uid,
    required String companionType,
  }) =>
      guardAsync(() => _firestore.updateDocument(
            collection: AppConstants.colUsers,
            id: uid,
            data: {'settings.companionType': companionType},
          ));

  // ── Account deletion ───────────────────────────────────────────────────────

  /// Permanently deletes the account.
  ///
  /// Requires reauthentication first:
  /// - Email users: pass [password]; [providerId] is ignored.
  /// - Google/Apple users: pass [password] as null and [providerId] as the
  ///   Firebase provider ID ('google.com' / 'apple.com') so the correct
  ///   native reauth flow is used.
  ///
  /// Deletion order:
  /// 1. Reauthenticate (throws on wrong credentials)
  /// 2. Delete completion documents (batched)
  /// 3. Delete per-user challenge subcollection documents (batched)
  /// 4. Delete per-user memory subcollection documents (batched)
  /// 5. Delete the public leaderboard mirror document
  /// 6. Release the username claim so it becomes available again
  /// 7. Delete Firestore user document
  /// 8. Delete profile + completion photos from Storage (best-effort)
  /// 9. Delete Firebase Auth account
  Future<Result<void>> deleteAccount({
    required String uid,
    String? password,
    String? providerId,
  }) =>
      guardAsync(() async {
        // 1. Reauthenticate to satisfy Firebase's recent-login requirement.
        if (password != null) {
          final email = _auth.currentUser?.email ?? '';
          await _auth.reauthenticateWithPassword(
              email: email, password: password);
        } else if (providerId == 'apple.com') {
          await _auth.reauthenticateWithApple();
        } else {
          await _auth.reauthenticateWithGoogle();
        }

        final db = FirebaseFirestore.instance;

        // 2. Delete completion documents.
        final completionsSnap = await _firestore.queryCollection(
          collection: AppConstants.colCompletions,
          filters: [QueryFilter(field: 'userId', isEqualTo: uid)],
        );
        await _batchDelete(
            db, completionsSnap.docs.map((d) => d.reference));

        // 3. Delete per-user challenge subcollection documents.
        final challengesSnap = await db
            .collection(AppConstants.colUsers)
            .doc(uid)
            .collection(AppConstants.colUserChallenges)
            .get();
        await _batchDelete(db, challengesSnap.docs.map((d) => d.reference));

        // 4. Delete per-user memory subcollection documents.
        final memoriesSnap = await db
            .collection(AppConstants.colUsers)
            .doc(uid)
            .collection(AppConstants.colUserMemories)
            .get();
        await _batchDelete(db, memoriesSnap.docs.map((d) => d.reference));

        // 5. Delete the public leaderboard mirror document.
        await _firestore.deleteDocument(
          collection: AppConstants.colLeaderboardPublic,
          id: uid,
        );

        // 6. Release the username claim (best-effort — a deleted account's
        // handle should become available again, not stay squatted forever).
        final departingUser = await _fetchUser(uid);
        if (departingUser != null) {
          try {
            await _firestore.deleteDocument(
              collection: AppConstants.colUsernames,
              id: departingUser.username,
            );
          } catch (_) {}
        }

        // 7. Delete Firestore user document.
        await _firestore.deleteDocument(
          collection: AppConstants.colUsers,
          id: uid,
        );

        // 8. Delete photos from Storage (best-effort).
        await _storage.deleteProfilePhoto(uid);
        await _storage.deleteCompletionPhotos(uid);

        // 9. Delete Firebase Auth account.
        await _auth.deleteAuthAccount();
      });

  /// Sets whether the user's profile is visible on public leaderboards.
  ///
  /// Enabling (re)creates the [AppConstants.colLeaderboardPublic] mirror
  /// document; disabling deletes it, so an opted-out user is unreadable by
  /// anyone but themselves — not just filtered client-side.
  Future<Result<void>> setProfilePublic(String uid, bool isPublic) =>
      guardAsync(() async {
        await _firestore.updateDocument(
          collection: AppConstants.colUsers,
          id: uid,
          data: {'settings.profilePublic': isPublic},
        );

        if (isPublic) {
          final current = await _fetchUser(uid);
          if (current != null) await _syncPublicMirror(current);
        } else {
          await _firestore.deleteDocument(
            collection: AppConstants.colLeaderboardPublic,
            id: uid,
          );
        }
      });

  /// Atomically claims [username] for [uid] in the [AppConstants.colUsernames]
  /// registry, releasing [previousUsername] in the same transaction if given.
  /// Throws [DataException] if the username is already claimed by a
  /// different uid — callers must not silently swallow that failure, since
  /// letting it through would mean two users end up with the same handle.
  Future<void> _claimUsername(
    String uid,
    String username, {
    String? previousUsername,
  }) async {
    final db = FirebaseFirestore.instance;
    final newRef = db.collection(AppConstants.colUsernames).doc(username);
    await db.runTransaction((tx) async {
      final newSnap = await tx.get(newRef);
      if (newSnap.exists && newSnap.data()?['uid'] != uid) {
        throw const DataException(message: 'That username is already taken.');
      }
      if (previousUsername != null && previousUsername != username) {
        tx.delete(db.collection(AppConstants.colUsernames).doc(previousUsername));
      }
      tx.set(newRef, {'uid': uid});
    });
  }

  /// Changes the user's username, atomically enforcing uniqueness via
  /// [_claimUsername]. No-ops if [newUsername] already matches
  /// [currentUsername].
  Future<Result<void>> updateUsername({
    required String uid,
    required String currentUsername,
    required String newUsername,
  }) =>
      guardAsync(() async {
        if (newUsername == currentUsername) return;
        await _claimUsername(uid, newUsername, previousUsername: currentUsername);
        await _firestore.updateDocument(
          collection: AppConstants.colUsers,
          id: uid,
          data: {'username': newUsername},
        );
        final current = await _fetchUser(uid);
        if (current != null) await _syncPublicMirror(current);
      });

  /// Deletes [refs] in batches of 500 (Firestore's per-batch write limit)
  /// instead of one sequential round trip per document.
  Future<void> _batchDelete(
    FirebaseFirestore db,
    Iterable<DocumentReference<Map<String, dynamic>>> refs,
  ) async {
    final list = refs.toList();
    for (var i = 0; i < list.length; i += 500) {
      final batch = db.batch();
      for (final ref in list.skip(i).take(500)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  /// Mirrors the safe-to-share subset of [user] into
  /// [AppConstants.colLeaderboardPublic], so leaderboard/league reads never
  /// need access to the full (private) `/users/{uid}` document.
  ///
  /// Merges rather than overwrites, so partial callers (e.g.
  /// [uploadProfilePhoto]) can pass just the field(s) that changed via
  /// [overrides] without clobbering the rest.
  Future<void> _syncPublicMirror(UserModel user,
      {Map<String, dynamic>? overrides}) {
    if (!user.settings.profilePublic) return Future.value();
    return _firestore.setDocument(
      collection: AppConstants.colLeaderboardPublic,
      id: user.uid,
      merge: true,
      data: {
        'displayName': user.displayName,
        'username': user.username,
        'photoUrl': user.photoUrl,
        'xp': user.xp,
        'weeklyXp': user.weeklyXp,
        'streak': user.streak,
        'currentLeague': user.currentLeague,
        ...?overrides,
      },
    );
  }

  Future<UserModel> _resolveUser(UserCredential credential) async {
    final firebaseUser = credential.user;
    if (firebaseUser == null) throw AuthException.noUser();

    final existing = await _fetchUser(firebaseUser.uid);
    if (existing != null) {
      // Returning user — keep lastActiveDate fresh.
      await _firestore.updateDocument(
        collection: AppConstants.colUsers,
        id: firebaseUser.uid,
        data: {'lastActiveDate': FieldValue.serverTimestamp()},
      );
      // Also backfills the public mirror for accounts created before the
      // mirror collection existed.
      await _syncPublicMirror(existing);
      return existing;
    }

    // New user — create the Firestore document.
    var newUser = UserModel.initial(
      uid: firebaseUser.uid,
      displayName: firebaseUser.displayName ?? 'Explorer',
      photoUrl: firebaseUser.photoURL,
      email: firebaseUser.email ?? '',
    );

    try {
      await _claimUsername(newUser.uid, newUser.username);
    } on DataException {
      // The auto-generated username (display name + short uid suffix)
      // collided — astronomically rare, but fall back to a longer,
      // guaranteed-unique suffix rather than fail sign-up over it.
      newUser = newUser.copyWith(
        username: '${newUser.username}_${newUser.uid.substring(0, 8).toLowerCase()}',
      );
      await _claimUsername(newUser.uid, newUser.username);
    }

    await _firestore.setDocument(
      collection: AppConstants.colUsers,
      id: newUser.uid,
      data: newUser.toFirestore(),
    );
    await _syncPublicMirror(newUser);

    return newUser;
  }

  /// Formats a calendar-day [DateTime] (year/month/day only) as "yyyy-MM-dd"
  /// for use as a stable, sortable key in [UserModel.frozenDates].
  @visibleForTesting
  static String dateKeyForCalendarDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  Future<UserModel?> _fetchUser(String uid) async {
    final doc = await _firestore.getDocument(
      collection: AppConstants.colUsers,
      id: uid,
    );
    if (doc == null) return null;
    return UserModel.fromFirestore(doc);
  }
}

/// Result of [resolveStreakOutcome].
@visibleForTesting
class StreakOutcome {
  const StreakOutcome({required this.newStreak, required this.rainyDayConsumed});
  final int newStreak;
  final bool rainyDayConsumed;

  @override
  bool operator ==(Object other) =>
      other is StreakOutcome &&
      newStreak == other.newStreak &&
      rainyDayConsumed == other.rainyDayConsumed;

  @override
  int get hashCode => Object.hash(newStreak, rainyDayConsumed);

  @override
  String toString() =>
      'StreakOutcome(newStreak: $newStreak, rainyDayConsumed: $rainyDayConsumed)';
}

/// Pure streak-transition decision used by [UserRepository.awardCompletionRewards].
///
/// Extracted from that method so it can be unit tested directly — the
/// surrounding Firestore read/write can't be exercised without a Firestore
/// fake, but this decision logic (the actual streak rules) can be.
///
/// All [DateTime]s must already be truncated to a calendar day (year/month/
/// day only, no time component) in the same reference frame — callers are
/// responsible for local/UTC normalization.
@visibleForTesting
StreakOutcome resolveStreakOutcome({
  required DateTime today,
  required DateTime lastActiveDay,
  required int currentStreak,
  required int freezesOwned,
}) {
  // Calendar-field arithmetic, not Duration subtraction: subtracting a
  // fixed elapsed duration from a local midnight isn't guaranteed to land
  // on the next local midnight across a DST transition (a day can be 23 or
  // 25 hours long), which would spuriously break this equality check and
  // reset a streak that should have incremented. DateTime's constructor
  // normalizes out-of-range day values (e.g. day 0 rolls into the previous
  // month), so this is safe at month/year boundaries too.
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final twoDaysAgo = DateTime(today.year, today.month, today.day - 2);

  if (lastActiveDay == today) {
    // Already completed today — idempotent: keep streak unchanged.
    return StreakOutcome(newStreak: currentStreak, rainyDayConsumed: false);
  }
  if (lastActiveDay == yesterday) {
    return StreakOutcome(newStreak: currentStreak + 1, rainyDayConsumed: false);
  }
  if (lastActiveDay == twoDaysAgo && freezesOwned > 0) {
    // Exactly one day missed and a Rainy Day is available — auto-consume to
    // protect the streak. A freeze only ever covers a single missed day;
    // longer gaps reset the streak regardless of freezes owned (previously
    // any gap length was forgiven for the cost of one freeze, which let a
    // months-long absence preserve a streak — not the intended "rained one
    // day" semantics).
    return StreakOutcome(newStreak: currentStreak, rainyDayConsumed: true);
  }
  return const StreakOutcome(newStreak: 1, rainyDayConsumed: false);
}
