import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'challenge_model.dart';

/// An enriched adventure journal entry stored in users/{uid}/memories/{id}.
///
/// Created automatically after every successful challenge completion.
/// Mirrors core completion data and adds weather, readable location name,
/// the Gemini reflection prompt, and the challenge day number.
@immutable
class AdventureMemoryModel {
  const AdventureMemoryModel({
    required this.memoryId,
    required this.userId,
    required this.challengeId,
    required this.challengeDay,
    required this.challengeTitle,
    required this.challengeCategory,
    required this.photoUrl,
    required this.xpEarned,
    required this.verificationMethod,
    required this.completionDate,
    required this.createdAt,
    this.caption,
    this.captionPrompt,
    this.latitude,
    this.longitude,
    this.locationName,
    this.weatherCondition,
    this.weatherEmoji,
    this.captionUpdatedAt,
  });

  // ── Identity ────────────────────────────────────────────────────────────────

  /// Matches the completion document ID for cross-referencing.
  final String memoryId;
  final String userId;
  final String challengeId;

  // ── Challenge ───────────────────────────────────────────────────────────────

  /// Which consecutive day this challenge was (Day 1, Day 2 …).
  final int challengeDay;
  final String challengeTitle;
  final ChallengeCategory challengeCategory;

  // ── Media ───────────────────────────────────────────────────────────────────

  final String photoUrl;

  /// User's personal reflection (written after completion).
  final String? caption;

  /// The Gemini-generated reflection question shown to the user.
  final String? captionPrompt;

  // ── Location ────────────────────────────────────────────────────────────────

  final double? latitude;
  final double? longitude;

  /// Reverse-geocoded human-readable name, e.g. "Zilker Park, Austin TX".
  final String? locationName;

  // ── Environment ─────────────────────────────────────────────────────────────

  /// Condition string from WeatherModel, e.g. "Clear sky".
  final String? weatherCondition;

  /// Weather emoji, e.g. "☀️".
  final String? weatherEmoji;

  // ── Rewards ─────────────────────────────────────────────────────────────────

  final int xpEarned;

  /// One of "ai_verified" (Gemini confirmed the photo), "manual_override"
  /// (the user submitted after a failed/rejected AI verification), or
  /// "auto_approved" (no Gemini API key configured, so verification was
  /// skipped entirely — distinct from manual_override since the user didn't
  /// choose to bypass anything).
  final String verificationMethod;

  // ── Timestamps ──────────────────────────────────────────────────────────────

  final DateTime completionDate;
  final DateTime createdAt;
  final DateTime? captionUpdatedAt;

  // ── Computed ────────────────────────────────────────────────────────────────

  /// True only when both coordinates are present AND within valid Earth
  /// ranges (lat ±90, lng ±180), excluding the (0, 0) "null island" value
  /// that usually indicates an unset/erroneous GPS read rather than a real
  /// location — so corrupt or malformed coordinate data can never reach the
  /// map/marker/clustering pipeline.
  bool get hasLocation {
    final lat = latitude;
    final lng = longitude;
    if (lat == null || lng == null) return false;
    if (lat.isNaN || lng.isNaN) return false;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
    if (lat == 0 && lng == 0) return false;
    return true;
  }

  bool get hasCaption => caption != null && caption!.isNotEmpty;
  bool get hasWeather => weatherCondition != null;

  String get displayLocation {
    if (locationName != null && locationName!.isNotEmpty) return locationName!;
    if (hasLocation) {
      return '${latitude!.toStringAsFixed(4)}, '
          '${longitude!.toStringAsFixed(4)}';
    }
    return 'Unknown location';
  }

  String get weatherDisplay {
    if (weatherEmoji != null && weatherCondition != null) {
      return '$weatherEmoji $weatherCondition';
    }
    return weatherCondition ?? '';
  }

  String get challengeEmoji => challengeCategory.emoji;

  /// True only when Gemini actually evaluated this photo — false for both
  /// manual overrides and no-API-key auto-approvals, so callers can't
  /// accidentally lump "not AI-verified" states together with the one that
  /// really was.
  bool get isAiVerified => verificationMethod == 'ai_verified';

  /// Human-readable badge text covering all three [verificationMethod] values.
  String get verificationLabel => switch (verificationMethod) {
    'ai_verified' => '🤖 AI Verified',
    'manual_override' => '✋ Manual Submit',
    _ => '✓ Auto-Approved',
  };

  // ── Serialization ───────────────────────────────────────────────────────────

  factory AdventureMemoryModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) => AdventureMemoryModel.fromMap(doc.data()!, memoryId: doc.id);

  /// The actual parsing logic behind [fromFirestore], taking a raw map
  /// instead of a [DocumentSnapshot] so it's directly unit-testable without
  /// a real or emulated Firestore instance (a snapshot can't be constructed
  /// in a plain unit test).
  @visibleForTesting
  factory AdventureMemoryModel.fromMap(
    Map<String, dynamic> d, {
    required String memoryId,
  }) {
    return AdventureMemoryModel(
      memoryId: memoryId,
      userId: d['userId'] as String,
      challengeId: d['challengeId'] as String,
      challengeDay: d['challengeDay'] as int? ?? 1,
      challengeTitle: d['challengeTitle'] as String? ?? '',
      challengeCategory: ChallengeCategory.fromString(
        d['challengeCategory'] as String?,
      ),
      photoUrl: d['photoUrl'] as String? ?? '',
      caption: d['caption'] as String?,
      captionPrompt: d['captionPrompt'] as String?,
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
      locationName: d['locationName'] as String?,
      weatherCondition: d['weatherCondition'] as String?,
      weatherEmoji: d['weatherEmoji'] as String?,
      xpEarned: d['xpEarned'] as int? ?? 0,
      verificationMethod: d['verificationMethod'] as String? ?? 'ai_verified',
      completionDate: _tsToDate(d['completionDate']),
      createdAt: _tsToDate(d['createdAt']),
      captionUpdatedAt: d['captionUpdatedAt'] != null
          ? _tsToDate(d['captionUpdatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'challengeId': challengeId,
      'challengeDay': challengeDay,
      'challengeTitle': challengeTitle,
      'challengeCategory': challengeCategory.name,
      'photoUrl': photoUrl,
      'xpEarned': xpEarned,
      'verificationMethod': verificationMethod,
      'completionDate': Timestamp.fromDate(completionDate),
      'createdAt': FieldValue.serverTimestamp(),
      if (caption != null) 'caption': caption,
      if (captionPrompt != null) 'captionPrompt': captionPrompt,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationName != null) 'locationName': locationName,
      if (weatherCondition != null) 'weatherCondition': weatherCondition,
      if (weatherEmoji != null) 'weatherEmoji': weatherEmoji,
    };
  }

  AdventureMemoryModel copyWith({
    String? caption,
    DateTime? captionUpdatedAt,
    String? locationName,
    String? weatherCondition,
    String? weatherEmoji,
  }) => AdventureMemoryModel(
    memoryId: memoryId,
    userId: userId,
    challengeId: challengeId,
    challengeDay: challengeDay,
    challengeTitle: challengeTitle,
    challengeCategory: challengeCategory,
    photoUrl: photoUrl,
    xpEarned: xpEarned,
    verificationMethod: verificationMethod,
    completionDate: completionDate,
    createdAt: createdAt,
    captionPrompt: captionPrompt,
    latitude: latitude,
    longitude: longitude,
    caption: caption ?? this.caption,
    locationName: locationName ?? this.locationName,
    weatherCondition: weatherCondition ?? this.weatherCondition,
    weatherEmoji: weatherEmoji ?? this.weatherEmoji,
    captionUpdatedAt: captionUpdatedAt ?? this.captionUpdatedAt,
  );

  // ── Equality ────────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdventureMemoryModel && memoryId == other.memoryId;

  @override
  int get hashCode => memoryId.hashCode;

  static DateTime _tsToDate(Object? v) {
    if (v is Timestamp) return v.toDate().toLocal();
    return DateTime.now();
  }
}
