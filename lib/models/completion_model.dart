import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'challenge_model.dart';

/// What every completion records today. Completions are on the honor
/// system: no AI or other automated check looks at the photo (AI photo
/// verification is disabled, audit D-06). Phase 7G replaced the earlier
/// wording, which advertised AI verification as a "premium feature".
const honorSystemReason = 'Completed on the honor system with your photo.';

@immutable
class CompletionModel {
  const CompletionModel({
    required this.id,
    required this.userId,
    required this.challengeId,
    required this.challengeTitle,
    required this.challengeEmoji,
    required this.challengeCategory,
    required this.photoUrl,
    required this.verificationResult,
    required this.completedAt,
    required this.xpAwarded,
    required this.overrideUsed,
    this.assignmentDate,
    this.location,
    this.caption,
  });

  final String id;
  final String userId;
  final String challengeId;
  final String challengeTitle;
  final String challengeEmoji;
  final ChallengeCategory challengeCategory;
  final String photoUrl;
  final Map<String, dynamic> verificationResult;
  final DateTime completedAt;
  final int xpAwarded;
  final bool overrideUsed;
  final DateTime? assignmentDate;
  final GeoPoint? location;
  final String? caption;

  // Derived from verificationResult map for convenient access.
  double get confidenceScore =>
      (verificationResult['confidence'] as num?)?.toDouble() ?? 0.0;
  String get verificationExplanation =>
      verificationResult['reason'] as String? ?? '';

  /// The line Challenge details shows for how this was completed. Only a
  /// result with a confidence score came from an AI check (older app
  /// versions); everything else was an honor-system completion, whatever
  /// wording its app version stored ("AI verification is a premium
  /// feature", "AI verification not configured"), so it shows
  /// [honorSystemReason] — never a claim about AI (Phase 7G).
  String get verificationDisplayText =>
      verificationResult.containsKey('confidence')
      ? verificationExplanation
      : honorSystemReason;

  DateTime get dateOnly =>
      DateTime(completedAt.year, completedAt.month, completedAt.day);

  /// This completion with [xpAwarded] replaced — used to record the XP that
  /// was actually committed (0 for a same-day resubmission), so the Journal
  /// and challenge detail never show XP the user didn't receive (audit D-01).
  CompletionModel withXpAwarded(int xp) => CompletionModel(
    id: id,
    userId: userId,
    challengeId: challengeId,
    challengeTitle: challengeTitle,
    challengeEmoji: challengeEmoji,
    challengeCategory: challengeCategory,
    photoUrl: photoUrl,
    verificationResult: verificationResult,
    completedAt: completedAt,
    xpAwarded: xp,
    overrideUsed: overrideUsed,
    assignmentDate: assignmentDate,
    location: location,
    caption: caption,
  );

  factory CompletionModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return CompletionModel(
      id: doc.id,
      userId: data['userId'] as String,
      challengeId: data['challengeId'] as String,
      challengeTitle: data['challengeTitle'] as String? ?? '',
      challengeEmoji: data['challengeEmoji'] as String? ?? '🌿',
      challengeCategory: ChallengeCategory.fromString(
        data['challengeCategory'] as String?,
      ),
      photoUrl: data['photoUrl'] as String,
      verificationResult: Map<String, dynamic>.from(
        data['verificationResult'] as Map? ?? const {},
      ),
      completedAt: (data['completedAt'] as Timestamp).toDate(),
      xpAwarded: (data['xpAwarded'] as num).toInt(),
      overrideUsed: data['overrideUsed'] as bool? ?? false,
      assignmentDate: data['assignmentDate'] != null
          ? (data['assignmentDate'] as Timestamp).toDate()
          : null,
      location: data['location'] as GeoPoint?,
      caption: data['caption'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'userId': userId,
    'challengeId': challengeId,
    'challengeTitle': challengeTitle,
    'challengeEmoji': challengeEmoji,
    'challengeCategory': challengeCategory.name,
    'photoUrl': photoUrl,
    'verificationResult': verificationResult,
    'completedAt': FieldValue.serverTimestamp(),
    'xpAwarded': xpAwarded,
    'overrideUsed': overrideUsed,
    if (assignmentDate != null)
      'assignmentDate': Timestamp.fromDate(assignmentDate!),
    if (location != null) 'location': location,
    if (caption != null) 'caption': caption,
  };
}
