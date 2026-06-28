import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'challenge_model.dart';

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

  DateTime get dateOnly => DateTime(
        completedAt.year,
        completedAt.month,
        completedAt.day,
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
      challengeCategory: ChallengeCategory.fromString(data['challengeCategory'] as String?),
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
