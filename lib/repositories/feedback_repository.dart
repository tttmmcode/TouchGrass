import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/result.dart';

/// Kinds of message the Settings screen can send.
enum FeedbackType { feedback, bug }

/// Submits user feedback / bug reports to `feedback/{id}`.
///
/// firestore.rules make this collection write-only and narrowly validated
/// (audit N-1): create only, by the signed-in user, for themselves, with a
/// fixed field set, a bounded message, a server timestamp, and at most
/// [maxPerDay] submissions per user per UTC day — enforced by the document
/// ID `{uid}_{yyyy-MM-dd}_{1..maxPerDay}`, which the rules require and
/// which can each be created only once. Nobody can read, edit or delete
/// feedback from the client; it is reviewed in the Firebase console.
class FeedbackRepository {
  FeedbackRepository({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Must match `maxFeedbackPerDay()` in firestore.rules.
  static const int maxPerDay = 5;

  /// Must match the message bound in firestore.rules.
  static const int maxMessageLength = 1000;

  /// Recorded with each message (helps triage); not a security field.
  static const String appVersion = '1.0.0';

  Future<Result<void>> submit({
    required String? userId,
    required FeedbackType type,
    required String message,
    DateTime? now,
  }) => guardAsync(() async {
    if (userId == null || userId.isEmpty) {
      throw const DataException(message: 'Please sign in to send feedback.');
    }
    final text = validateFeedbackMessage(message);
    final day = utcDateKey((now ?? DateTime.now()).toUtc());
    final data = {
      'type': type.name,
      'message': text,
      'userId': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'appVersion': appVersion,
    };

    final id = await claimFeedbackSlot(
      userId: userId,
      day: day,
      tryCreate: (id) => _tryCreate(id, data),
    );
    if (id == null) {
      throw const DataException(
        message:
            "You've sent $maxPerDay messages today — thank you! "
            'Please try again tomorrow.',
      );
    }
  });

  /// Creates `feedback/[id]`; returns false if the slot is already taken
  /// (the rules deny writing to an existing document).
  Future<bool> _tryCreate(String id, Map<String, dynamic> data) async {
    try {
      await _db.collection(AppConstants.colFeedback).doc(id).set(data);
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return false;
      rethrow;
    }
  }
}

/// Trims [message] and checks it against the rules' bounds, throwing a
/// friendly [DataException] instead of letting the server reject it.
@visibleForTesting
String validateFeedbackMessage(String message) {
  final text = message.trim();
  if (text.isEmpty) {
    throw const DataException(message: 'Please write a message first.');
  }
  if (text.length > FeedbackRepository.maxMessageLength) {
    throw const DataException(
      message:
          'Please keep your message under '
          '${FeedbackRepository.maxMessageLength} characters.',
    );
  }
  return text;
}

/// `yyyy-MM-dd` for a UTC date — the day component of feedback IDs.
@visibleForTesting
String utcDateKey(DateTime utc) =>
    '${utc.year.toString().padLeft(4, '0')}-'
    '${utc.month.toString().padLeft(2, '0')}-'
    '${utc.day.toString().padLeft(2, '0')}';

/// Tries slots `{userId}_{day}_1` … `_{maxPerDay}` in order and returns the
/// first ID [tryCreate] succeeds on, or null once every slot is taken.
@visibleForTesting
Future<String?> claimFeedbackSlot({
  required String userId,
  required String day,
  required Future<bool> Function(String id) tryCreate,
}) async {
  for (var slot = 1; slot <= FeedbackRepository.maxPerDay; slot++) {
    final id = '${userId}_${day}_$slot';
    if (await tryCreate(id)) return id;
  }
  return null;
}
