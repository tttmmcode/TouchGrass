import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';
import '../core/result.dart';
import '../models/challenge_model.dart';
import '../models/completion_model.dart';
import '../services/firestore_service.dart';

class CompletionRepository {
  const CompletionRepository({required FirestoreService firestoreService})
      : _firestore = firestoreService;

  final FirestoreService _firestore;

  Future<Result<CompletionModel>> createCompletion({
    required String userId,
    required String challengeId,
    required String challengeTitle,
    required String challengeEmoji,
    required ChallengeCategory challengeCategory,
    required String photoUrl,
    required Map<String, dynamic> verificationResult,
    required int xpAwarded,
    required bool overrideUsed,
    DateTime? assignmentDate,
    GeoPoint? location,
    String? caption,
  }) =>
      guardAsync(() async {
        final now = DateTime.now();

        final temp = CompletionModel(
          id: '',
          userId: userId,
          challengeId: challengeId,
          challengeTitle: challengeTitle,
          challengeEmoji: challengeEmoji,
          challengeCategory: challengeCategory,
          photoUrl: photoUrl,
          verificationResult: verificationResult,
          completedAt: now,
          xpAwarded: xpAwarded,
          overrideUsed: overrideUsed,
          assignmentDate: assignmentDate,
          location: location,
          caption: caption,
        );

        final ref = await _firestore.addDocument(
          collection: AppConstants.colCompletions,
          data: temp.toFirestore(),
        );

        return CompletionModel(
          id: ref.id,
          userId: userId,
          challengeId: challengeId,
          challengeTitle: challengeTitle,
          challengeEmoji: challengeEmoji,
          challengeCategory: challengeCategory,
          photoUrl: photoUrl,
          verificationResult: verificationResult,
          completedAt: now,
          xpAwarded: xpAwarded,
          overrideUsed: overrideUsed,
          assignmentDate: assignmentDate,
          location: location,
          caption: caption,
        );
      });
}
