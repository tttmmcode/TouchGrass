import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
        final lastActive = DateTime(
          current.lastActiveDate.year,
          current.lastActiveDate.month,
          current.lastActiveDate.day,
        );
        final yesterday = today.subtract(const Duration(days: 1));

        final int newStreak;
        final bool rainyDayConsumed;
        if (lastActive == today) {
          // Already completed today — idempotent: keep streak unchanged.
          newStreak = current.streak;
          rainyDayConsumed = false;
        } else if (lastActive == yesterday) {
          newStreak = current.streak + 1;
          rainyDayConsumed = false;
        } else if (current.settings.streakFreezesOwned > 0) {
          // Missed a day but has a Rainy Day — auto-consume to protect streak.
          newStreak = current.streak;
          rainyDayConsumed = true;
        } else {
          newStreak = 1;
          rainyDayConsumed = false;
        }

        final newLongestStreak =
            newStreak > current.longestStreak ? newStreak : current.longestStreak;

        // Only award XP/completions on first submission of the day.
        final isNewCompletionToday = lastActive != today;
        final newTotalCompletions =
            isNewCompletionToday ? current.totalCompletions + 1 : current.totalCompletions;
        final newXp = isNewCompletionToday ? current.xp + xpAmount : current.xp;
        final effectiveXpAwarded = isNewCompletionToday ? xpAmount : 0;

        // Weekly XP — reset if we've passed this week's reset boundary.
        final nowUtc = now.toUtc();
        final needsWeeklyReset = nowUtc.isAfter(current.weeklyXpResetDate);
        final newWeeklyXp = isNewCompletionToday
            ? (needsWeeklyReset
                ? effectiveXpAwarded
                : current.weeklyXp + effectiveXpAwarded)
            : current.weeklyXp;
        final newWeeklyXpResetDate = (isNewCompletionToday && needsWeeklyReset)
            ? AppConstants.nextMondayMidnightUtc()
            : current.weeklyXpResetDate;

        // League — always derived from total XP so it never drifts.
        final newLeague = LeagueDef.idForXp(newXp);

        final oldLevel = current.level;
        final newLevel = AppConstants.levelForXp(newXp);

        final newlyEarned = AchievementDefinition.computeNewlyEarned(
          alreadyEarned: current.achievements.toSet(),
          newXp: newXp,
          newStreak: newStreak,
          newLevel: newLevel,
          newTotalCompletions: newTotalCompletions,
        );

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

        await _firestore.updateDocument(
          collection: AppConstants.colUsers,
          id: uid,
          data: updateData,
        );

        final updatedSettings =
            (rainyDayConsumed || rainyDayEarned > 0)
                ? current.settings.copyWith(streakFreezesOwned: newFreezesOwned)
                : current.settings;

        return CompletionReward(
          updatedUser: current.copyWith(
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
          ),
          xpAwarded: effectiveXpAwarded,
          newStreak: newStreak,
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

        await _firestore.updateDocument(
          collection: AppConstants.colUsers,
          id: uid,
          data: {
            'xp': newXp,
            'settings.streakFreezesOwned': newFreezesOwned,
          },
        );

        return current.copyWith(
          xp: newXp,
          settings: current.settings.copyWith(
            streakFreezesOwned: newFreezesOwned,
          ),
        );
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
  /// - Email users: pass [password].
  /// - Google users: pass [password] as null.
  ///
  /// Deletion order:
  /// 1. Reauthenticate (throws on wrong credentials)
  /// 2. Delete completion documents
  /// 3. Delete daily assignment documents
  /// 4. Delete Firestore user document
  /// 5. Delete profile photo from Storage (silent failure if not found)
  /// 6. Delete Firebase Auth account
  Future<Result<void>> deleteAccount({
    required String uid,
    String? password,
  }) =>
      guardAsync(() async {
        // 1. Reauthenticate to satisfy Firebase's recent-login requirement.
        if (password != null) {
          final email = _auth.currentUser?.email ?? '';
          await _auth.reauthenticateWithPassword(
              email: email, password: password);
        } else {
          await _auth.reauthenticateWithGoogle();
        }

        // 2. Delete completion documents.
        final completionsSnap = await _firestore.queryCollection(
          collection: AppConstants.colCompletions,
          filters: [QueryFilter(field: 'userId', isEqualTo: uid)],
        );
        for (final doc in completionsSnap.docs) {
          await _firestore.deleteDocument(
            collection: AppConstants.colCompletions,
            id: doc.id,
          );
        }

        // 3. Delete per-user challenge subcollection documents.
        final challengesSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('challenges')
            .get();
        for (final doc in challengesSnap.docs) {
          await doc.reference.delete();
        }

        // 4. Delete Firestore user document.
        await _firestore.deleteDocument(
          collection: AppConstants.colUsers,
          id: uid,
        );

        // 5. Delete profile photo from Storage (best-effort).
        await _storage.deleteProfilePhoto(uid);

        // 6. Delete Firebase Auth account.
        await _auth.deleteAuthAccount();
      });

  // ── Private ────────────────────────────────────────────────────────────────

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
      return existing;
    }

    // New user — create the Firestore document.
    final newUser = UserModel.initial(
      uid: firebaseUser.uid,
      displayName: firebaseUser.displayName ?? 'Explorer',
      photoUrl: firebaseUser.photoURL,
      email: firebaseUser.email ?? '',
    );

    await _firestore.setDocument(
      collection: AppConstants.colUsers,
      id: newUser.uid,
      data: newUser.toFirestore(),
    );

    return newUser;
  }

  Future<UserModel?> _fetchUser(String uid) async {
    final doc = await _firestore.getDocument(
      collection: AppConstants.colUsers,
      id: uid,
    );
    if (doc == null) return null;
    return UserModel.fromFirestore(doc);
  }
}
