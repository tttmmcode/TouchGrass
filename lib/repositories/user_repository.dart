import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/result.dart';
import '../models/achievement_definition.dart';
import '../models/adventure_memory_model.dart';
import '../models/completion_model.dart';
import '../models/completion_reward.dart';
import '../models/league_definition.dart';
import '../models/user_model.dart';
import '../services/account_deletion_service.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import 'completion_repository.dart';

/// Orchestrates authentication, the Firestore user document, and profile
/// photo storage.
///
/// All public methods return [Result<T>] — callers never see raw exceptions.
class UserRepository {
  UserRepository({
    required AuthService authService,
    required FirestoreService firestoreService,
    required StorageService storageService,
    FirebaseFirestore? db,
    AccountDeletionService? accountDeletion,
  }) : _auth = authService,
       _firestore = firestoreService,
       _storage = storageService,
       _db = db ?? FirebaseFirestore.instance,
       _accountDeletion = accountDeletion ?? CloudAccountDeletionService();

  final AuthService _auth;
  final FirestoreService _firestore;
  final StorageService _storage;

  /// Used for batched writes and subcollections ([FirestoreService] only
  /// covers single top-level documents). Injectable for tests.
  final FirebaseFirestore _db;
  final AccountDeletionService _accountDeletion;

  // ── Authentication ─────────────────────────────────────────────────────────

  Future<Result<UserModel>> signInWithGoogle() =>
      guardAsync(() async => _resolveUser(await _auth.signInWithGoogle()));

  Future<Result<UserModel>> signInWithApple() =>
      guardAsync(() async => _resolveUser(await _auth.signInWithApple()));

  Future<Result<void>> signOut() => guardAsync(_auth.signOut);

  Future<Result<UserModel>> signInWithEmail({
    required String email,
    required String password,
  }) => guardAsync(
    () async => _resolveUser(
      await _auth.signInWithEmail(email: email, password: password),
    ),
  );

  Future<Result<UserModel>> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) => guardAsync(
    () async => _resolveUser(
      await _auth.signUpWithEmail(
        email: email,
        password: password,
        displayName: displayName,
      ),
    ),
  );

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
  ) => guardAsync(
    () => _firestore.updateDocument(
      collection: AppConstants.colUsers,
      id: uid,
      data: fields,
    ),
  );

  /// Uploads a new profile photo, saves the URL in Firestore, and returns
  /// the download URL.
  ///
  /// Writes only `photoUrl`: an avatar is not an adventure photo, so it
  /// never touches `totalPhotosUploaded`, XP, streaks or completions
  /// (audit P2-9). Adventure photos are counted by `totalCompletions` —
  /// exactly one photo per completion, validated by firestore.rules.
  Future<Result<String>> uploadProfilePhoto({
    required String uid,
    required Uint8List imageBytes,
  }) => guardAsync(() async {
    final url = await _storage.uploadProfilePhoto(
      userId: uid,
      bytes: imageBytes,
    );
    await _firestore.updateDocument(
      collection: AppConstants.colUsers,
      id: uid,
      data: {'photoUrl': url},
    );
    final current = await _fetchUser(uid);
    if (current != null) {
      await _syncPublicMirror(current, overrides: {'photoUrl': url});
    }
    return url;
  });

  // ── XP & rewards ──────────────────────────────────────────────────────────

  /// Persists [draft] and its reward in ONE atomic batch, returning the
  /// completion exactly as stored and the reward exactly as committed.
  ///
  /// firestore.rules only accept a reward update that is committed together
  /// with a brand-new completion document (named by `lastCompletionId`), and
  /// completions are create-only — so a retry, double-tap or second device
  /// can never be rewarded twice, and either both writes land or neither
  /// does. The stored completion's `xpAwarded` is the XP actually granted
  /// (0 for a same-day resubmission), so the Journal never shows XP the
  /// user didn't receive.
  ///
  /// "Already completed today?" is decided by `lastCompletionDate` — never
  /// by `lastActiveDate`, which every sign-in refreshes (audit D-01: that
  /// conflation made a user's first completion on any sign-in day award
  /// nothing). Accounts created before the field existed fall back, once,
  /// to their latest completion document; no migration is needed.
  ///
  /// Fails with a friendly [DataException] if this day's completion already
  /// exists. The leaderboard mirror is refreshed afterwards, best-effort:
  /// it is derived data, so a failure there must not turn an
  /// already-committed completion into a reported error.
  ///
  /// [journalEntry], when given, builds the Journal entry (memory) from the
  /// completion as it will be stored, and it is written in the same batch
  /// (audit D-13): the entry exists exactly when the completion does, with
  /// the same photo and the XP actually granted — a failure saves neither,
  /// and a retry can't create a second entry (same ID, create-only).
  Future<Result<CompletionCommit>> commitCompletion(
    CompletionModel draft, {
    AdventureMemoryModel Function(CompletionModel completion)? journalEntry,
    DateTime? now,
  }) => guardAsync(() async {
    final uid = draft.userId;
    final completions = CompletionRepository(db: _db);

    // Fast, friendly path for the common retry/double-submit case. The
    // rules are the real guard (create-only), checked again at commit.
    if (await completions.exists(draft.id)) throw _alreadyCompleted();

    final current = await _fetchUser(uid);
    if (current == null) throw DataException.notFound('User $uid');

    final lastCompletion =
        current.lastCompletionDate ?? await completions.latestCompletedAt(uid);

    final plan = planCompletionReward(
      current: current,
      lastCompletionDate: lastCompletion,
      xpAmount: draft.xpAwarded,
      now: now ?? DateTime.now(),
    );
    final completion = draft.withXpAwarded(plan.reward.xpAwarded);
    final memory = journalEntry?.call(completion);
    if (memory != null &&
        (memory.memoryId != completion.id ||
            memory.photoUrl != completion.photoUrl ||
            memory.xpEarned != completion.xpAwarded)) {
      throw ArgumentError('Journal entry must mirror its completion');
    }

    final batch = _db.batch()
      ..set(
        _db.collection(AppConstants.colCompletions).doc(completion.id),
        completion.toFirestore(),
      )
      ..update(_db.collection(AppConstants.colUsers).doc(uid), {
        ...plan.updateData,
        'lastCompletionId': completion.id,
      });
    if (memory != null) {
      batch.set(
        _db
            .collection(AppConstants.colUsers)
            .doc(uid)
            .collection(AppConstants.colUserMemories)
            .doc(memory.memoryId),
        memory.toFirestore(),
      );
    }

    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      // Completions are create-only, so the common cause is a
      // concurrent submission winning the race; anything else is
      // reported honestly as unsaved.
      final alreadyDone = await completions
          .exists(completion.id)
          .catchError((Object _) => false);
      if (alreadyDone) throw _alreadyCompleted(e);
      throw DataException(
        message:
            "We couldn't save your adventure. Nothing was recorded — "
            'please try again.',
        cause: e,
      );
    }

    try {
      await _syncPublicMirror(plan.reward.updatedUser);
    } catch (e, st) {
      CrashReporter.recordError(
        e,
        st,
        reason: 'leaderboard mirror sync after completion failed',
      );
    }

    return CompletionCommit(
      completion: completion,
      reward: plan.reward,
      journalEntry: memory,
    );
  });

  static DataException _alreadyCompleted([Object? cause]) => DataException(
    message: "You've already completed today's challenge.",
    cause: cause,
  );

  /// Spends [AppConstants.streakFreezeCostXp] XP to purchase one streak freeze.
  Future<Result<UserModel>> buyStreakFreeze(String uid) => guardAsync(() async {
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
        'level': AppConstants.levelForXp(newXp),
        'currentLeague': newLeague,
        'settings.streakFreezesOwned': newFreezesOwned,
      },
    );

    final updated = current.copyWith(
      xp: newXp,
      currentLeague: newLeague,
      settings: current.settings.copyWith(streakFreezesOwned: newFreezesOwned),
    );
    await _syncPublicMirror(updated);
    return updated;
  });

  /// Saves the user's chosen companion type to Firestore.
  Future<Result<void>> updateCompanionType({
    required String uid,
    required String companionType,
  }) => guardAsync(
    () => _firestore.updateDocument(
      collection: AppConstants.colUsers,
      id: uid,
      data: {'settings.companionType': companionType},
    ),
  );

  // ── Account deletion ───────────────────────────────────────────────────────

  /// Permanently deletes the account (audit D-04).
  ///
  /// 1. Re-authenticates (email: [password]; Google/Apple: [providerId]
  ///    selects the native flow) — the server requires a recent sign-in.
  /// 2. Calls the server-side `deleteAccount` function, which removes every
  ///    user-owned document and file and then the Auth account, and is safe
  ///    to retry after any failure.
  /// 3. Signs out locally — only after the server confirmed full deletion.
  ///
  /// Returns an error (never success) if any step fails. The client no
  /// longer deletes data itself: the old client-side cascade could not get
  /// past the security rules and left accounts half-deleted.
  Future<Result<void>> deleteAccount({
    required String uid,
    String? password,
    String? providerId,
  }) => guardAsync(() async {
    if (_auth.currentUser?.uid != uid) {
      throw const DataException(
        message: 'Please sign in to the account you want to delete.',
      );
    }
    if (password != null) {
      await _auth.reauthenticateWithPassword(
        email: _auth.currentUser?.email ?? '',
        password: password,
      );
    } else if (providerId == 'apple.com') {
      await _auth.reauthenticateWithApple();
    } else {
      await _auth.reauthenticateWithGoogle();
    }

    await _accountDeletion.deleteCurrentAccount();
    AnalyticsService.resetAfterAccountDeletion();

    // The Auth user no longer exists; clear local session state. A
    // failure here doesn't undo the deletion, so it isn't reported.
    try {
      await _auth.signOut();
    } catch (_) {}
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

  /// Claims [username] for [uid] in the [AppConstants.colUsernames]
  /// registry, releasing [previousUsername] in the same atomic batch if
  /// given. Throws [DataException] if the name belongs to someone else —
  /// callers must not swallow that, or two users could share a handle.
  ///
  /// Claims are create-only in firestore.rules: a write to an existing claim
  /// is an update, which is always denied. So uniqueness is enforced by the
  /// server even under concurrent claims — of two simultaneous attempts on
  /// one name, exactly one commit succeeds; the loser gets permission-denied,
  /// reported as "taken". (A plain batch rather than a transaction also
  /// avoids cloud_firestore_web's runTransaction error-propagation gap; see
  /// KNOWN_BUGS.md A1.)
  Future<void> _claimUsername(
    String uid,
    String username, {
    String? previousUsername,
  }) async {
    final db = _db;
    final newRef = db.collection(AppConstants.colUsernames).doc(username);
    final existing = await newRef.get();
    final alreadyMine = existing.exists && existing.data()?['uid'] == uid;
    if (existing.exists && !alreadyMine) {
      throw const DataException(message: 'That username is already taken.');
    }

    final batch = db.batch();
    if (!alreadyMine) batch.set(newRef, {'uid': uid});
    if (previousUsername != null &&
        previousUsername.isNotEmpty &&
        previousUsername != username) {
      batch.delete(
        db.collection(AppConstants.colUsernames).doc(previousUsername),
      );
    }
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw DataException(
          message: 'That username is already taken.',
          cause: e,
        );
      }
      rethrow;
    }
  }

  /// Changes the user's username, atomically enforcing uniqueness via
  /// [_claimUsername]. No-ops if [newUsername] already matches
  /// [currentUsername].
  Future<Result<void>> updateUsername({
    required String uid,
    required String currentUsername,
    required String newUsername,
  }) => guardAsync(() async {
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

  // ── Private ────────────────────────────────────────────────────────────────

  /// Mirrors the safe-to-share subset of [user] into
  /// [AppConstants.colLeaderboardPublic], so leaderboard/league reads never
  /// need access to the full (private) `/users/{uid}` document.
  ///
  /// Merges rather than overwrites, so partial callers (e.g.
  /// [uploadProfilePhoto]) can pass just the field(s) that changed via
  /// [overrides] without clobbering the rest.
  Future<void> _syncPublicMirror(
    UserModel user, {
    Map<String, dynamic>? overrides,
  }) {
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
      photoUrl: await signInProviderPhoto(firebaseUser),
      email: firebaseUser.email ?? '',
    );

    try {
      await _claimUsername(newUser.uid, newUser.username);
    } on DataException {
      // The auto-generated username (display name + short uid suffix)
      // collided — astronomically rare, but fall back to a longer,
      // guaranteed-unique suffix rather than fail sign-up over it.
      newUser = newUser.copyWith(
        username:
            '${newUser.username}_${newUser.uid.substring(0, 8).toLowerCase()}',
      );
      await _claimUsername(newUser.uid, newUser.username);
    }

    await _firestore.setDocument(
      collection: AppConstants.colUsers,
      id: newUser.uid,
      data: {
        ...newUser.toFirestore(),
        // Server clock, not the device's: firestore.rules require both to
        // equal request.time so "Member Since" can't be backdated.
        'createdAt': FieldValue.serverTimestamp(),
        'lastActiveDate': FieldValue.serverTimestamp(),
      },
    );
    await _syncPublicMirror(newUser);

    return newUser;
  }

  /// The sign-in provider's photo exactly as the verified ID token carries
  /// it (the `picture` claim, set by Google sign-in). firestore.rules only
  /// accept a new profile's photo if it equals that claim (audit N-6), so
  /// this never fails sign-up: when the claim is missing or unreadable the
  /// profile starts without a photo (initials), and the user can upload one.
  @visibleForTesting
  static Future<String?> signInProviderPhoto(User user) async {
    try {
      final picture = (await user.getIdTokenResult()).claims?['picture'];
      return picture is String && picture.isNotEmpty && picture.length <= 2048
          ? picture
          : null;
    } catch (_) {
      return null;
    }
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
  const StreakOutcome({
    required this.newStreak,
    required this.rainyDayConsumed,
  });
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

/// Pure streak-transition decision used by [planCompletionReward].
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

/// The Firestore update and resulting [CompletionReward] for one completion.
@immutable
class CompletionRewardPlan {
  const CompletionRewardPlan({required this.updateData, required this.reward});

  /// Field updates for the user document (may contain [FieldValue]s).
  final Map<String, dynamic> updateData;
  final CompletionReward reward;
}

/// Computes the reward for a completion worth [xpAmount] XP, given the
/// user's [current] state, their [lastCompletionDate] (null = never
/// completed) and [now] (device-local time).
///
/// Pure — no I/O — so the rules it implements are unit-testable, and so
/// firestore.rules' `isValidRewardTransition` can be checked against it.
/// Streak rules ([resolveStreakOutcome]), by local calendar day of the last
/// completion:
/// - today          → already completed: no XP, streak unchanged.
/// - yesterday      → consecutive day: streak +1.
/// - exactly one missed day + freeze available → freeze absorbs it.
/// - anything else (or never completed) → streak (re)starts at 1.
CompletionRewardPlan planCompletionReward({
  required UserModel current,
  required DateTime? lastCompletionDate,
  required int xpAmount,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  // Stored as UTC; convert to local before extracting the calendar day so
  // it's compared in the same reference frame as `today` (local `now`).
  // Never completed → a date far enough back to count as a fresh start.
  final lastLocal = lastCompletionDate?.toLocal();
  final lastActive = lastLocal == null
      ? DateTime(1970)
      : DateTime(lastLocal.year, lastLocal.month, lastLocal.day);

  final streakOutcome = resolveStreakOutcome(
    today: today,
    lastActiveDay: lastActive,
    currentStreak: current.streak,
    freezesOwned: current.settings.streakFreezesOwned,
  );
  final newStreak = streakOutcome.newStreak;
  final rainyDayConsumed = streakOutcome.rainyDayConsumed;

  final newLongestStreak = newStreak > current.longestStreak
      ? newStreak
      : current.longestStreak;

  // Only award XP/completions on first submission of the day.
  final isNewCompletionToday = lastActive != today;
  final newTotalCompletions = isNewCompletionToday
      ? current.totalCompletions + 1
      : current.totalCompletions;
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

  // Newly-earned achievements carry their own XP reward (shown to the user
  // on the unlock card) — credited now so level/league/leaderboard reflect
  // the true total for this completion.
  final achievementXpBonus = AchievementDefinition.totalXpReward(newlyEarned);
  final newXp = baseXp + achievementXpBonus;
  final newWeeklyXp = baseWeeklyXp + achievementXpBonus;
  final newLevel = AppConstants.levelForXp(newXp);

  // League — always derived from total XP so it never drifts.
  final newLeague = LeagueDef.idForXp(newXp);

  // Rainy Day earnings at streak milestones (only when streak changed).
  int rainyDayEarned = 0;
  if (newStreak != current.streak) {
    if (newStreak == AppConstants.rainyDayEarnStreak7) rainyDayEarned = 1;
    if (newStreak == AppConstants.rainyDayEarnStreak30) rainyDayEarned = 2;
  }

  int newFreezesOwned = current.settings.streakFreezesOwned;
  if (rainyDayConsumed) newFreezesOwned -= 1;
  if (rainyDayEarned > 0) newFreezesOwned += rainyDayEarned;

  // Track total Rainy Days consumed (repurposes rainyDayCount field).
  final newRainyDayCount = rainyDayConsumed
      ? current.rainyDayCount + 1
      : current.rainyDayCount;

  // The freeze absorbs exactly one missed day — the one between lastActive
  // and today — so record that specific calendar date (calendar-field
  // arithmetic for DST safety, as in resolveStreakOutcome).
  final frozenDateKey = rainyDayConsumed
      ? UserRepository.dateKeyForCalendarDay(
          DateTime(today.year, today.month, today.day - 1),
        )
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
    'lastCompletionDate': FieldValue.serverTimestamp(),
  };
  if (needsWeeklyReset && isNewCompletionToday) {
    updateData['weeklyXpResetDate'] = Timestamp.fromDate(newWeeklyXpResetDate);
  }
  if (newlyEarned.isNotEmpty) {
    updateData['achievements'] = FieldValue.arrayUnion(newlyEarned);
    for (final id in newlyEarned) {
      updateData['achievementTimestamps.$id'] = FieldValue.serverTimestamp();
    }
  }
  if (rainyDayConsumed || rainyDayEarned > 0) {
    updateData['settings.streakFreezesOwned'] = newFreezesOwned;
  }
  if (frozenDateKey != null) {
    updateData['frozenDates'] = FieldValue.arrayUnion([frozenDateKey]);
  }

  final updatedSettings = (rainyDayConsumed || rainyDayEarned > 0)
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
    lastCompletionDate: now.toUtc(),
    achievements: [...current.achievements, ...newlyEarned],
    settings: updatedSettings,
    frozenDates: newFrozenDates,
  );

  return CompletionRewardPlan(
    updateData: updateData,
    reward: CompletionReward(
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
    ),
  );
}

/// A committed completion: the document exactly as stored (with the XP
/// actually granted) and the reward that was applied with it.
@immutable
class CompletionCommit {
  const CompletionCommit({
    required this.completion,
    required this.reward,
    this.journalEntry,
  });
  final CompletionModel completion;
  final CompletionReward reward;

  /// The Journal entry committed with [completion], if one was requested.
  final AdventureMemoryModel? journalEntry;
}
