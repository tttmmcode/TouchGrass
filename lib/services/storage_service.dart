import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/image_metadata.dart';

/// Storage path of the photo for [userId]'s completion of [challengeId]
/// (a `yyyy-MM-dd` date key). One fixed object per completion (audit D-13):
/// retrying an upload replaces the same file instead of leaving orphans, and
/// firestore.rules only accept a completion whose photoUrl points here.
String completionPhotoPath(String userId, String challengeId) =>
    '${AppConstants.storageCompletionPhotos}/$userId/$challengeId.jpg';

class StorageService {
  StorageService() : _storage = FirebaseStorage.instance;

  final FirebaseStorage _storage;

  static const _timeout = Duration(seconds: AppConstants.networkTimeoutSeconds);

  // ── Challenge completion photos ────────────────────────────────────────────

  /// Uploads the photo for [userId]'s completion of [challengeId] and returns
  /// its download URL. Idempotent: a retry overwrites the same object.
  /// Callers must not call this once the completion exists — overwriting
  /// can replace the download token the saved completion points to.
  ///
  /// Embedded metadata (EXIF/XMP, including GPS coordinates) is removed
  /// first (audit N-2): location may only be saved through the user's
  /// location setting, never inside the photo file.
  Future<String> uploadCompletionPhoto({
    required String userId,
    required String challengeId,
    required Uint8List bytes,
  }) async {
    final Uint8List clean;
    try {
      clean = await compute(stripImageMetadata, bytes);
    } on UnreadableImageException {
      throw const StorageException(
        message:
            "We couldn't read that photo. Please choose a JPEG or PNG "
            'photo, or take a new one.',
      );
    }
    if (clean.length >= AppConstants.maxCompletionPhotoBytes) {
      throw StorageException.fileTooLarge();
    }
    try {
      final ref = _storage.ref(completionPhotoPath(userId, challengeId));

      await ref
          .putData(clean, SettableMetadata(contentType: 'image/jpeg'))
          .timeout(_timeout);

      return ref.getDownloadURL();
    } on TimeoutException {
      throw NetworkException.timeout();
    } on FirebaseException catch (e) {
      throw StorageException.uploadFailed(e);
    } catch (e) {
      throw StorageException.uploadFailed(e);
    }
  }

  // ── Profile photos ─────────────────────────────────────────────────────────

  /// Uploads (or replaces) the user's profile photo.
  /// Returns its download URL (other signed-in users see it on the
  /// leaderboard).
  ///
  /// Embedded metadata is removed first, and the photo is always stored as
  /// a PNG (Phase 7C): the Settings crop already redraws it, but this is the
  /// upload boundary, so any other caller is covered too.
  Future<String> uploadProfilePhoto({
    required String userId,
    required Uint8List bytes,
  }) async {
    final Uint8List clean;
    try {
      clean = await compute(sanitizeProfilePhoto, bytes);
    } on UnreadableImageException {
      throw const StorageException(
        message:
            "We couldn't read that photo. Please choose a JPEG or PNG "
            'photo, or take a new one.',
      );
    }
    if (clean.length >= AppConstants.maxProfilePhotoBytes) {
      throw StorageException.fileTooLarge();
    }
    try {
      final path = '${AppConstants.storageUserAvatars}/$userId.png';
      final ref = _storage.ref(path);

      await ref
          .putData(clean, SettableMetadata(contentType: 'image/png'))
          .timeout(_timeout);

      return ref.getDownloadURL();
    } on TimeoutException {
      throw NetworkException.timeout();
    } on FirebaseException catch (e) {
      throw StorageException.uploadFailed(e);
    } catch (e) {
      throw StorageException.uploadFailed(e);
    }
  }
}
