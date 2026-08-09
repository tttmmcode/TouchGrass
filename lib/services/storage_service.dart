import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';

class StorageService {
  StorageService() : _storage = FirebaseStorage.instance;

  final FirebaseStorage _storage;

  static const _timeout =
      Duration(seconds: AppConstants.networkTimeoutSeconds);

  // ── Challenge completion photos ────────────────────────────────────────────

  Future<String> uploadCompletionPhoto({
    required String userId,
    required Uint8List bytes,
  }) async {
    if (bytes.length >= AppConstants.maxCompletionPhotoBytes) {
      throw StorageException.fileTooLarge();
    }
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path =
          '${AppConstants.storageCompletionPhotos}/$userId/$timestamp.jpg';
      final ref = _storage.ref(path);

      await ref
          .putData(bytes, SettableMetadata(contentType: 'image/jpeg'))
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
  /// Returns the public download URL.
  Future<String> uploadProfilePhoto({
    required String userId,
    required Uint8List bytes,
  }) async {
    if (bytes.length >= AppConstants.maxProfilePhotoBytes) {
      throw StorageException.fileTooLarge();
    }
    try {
      final path = '${AppConstants.storageUserAvatars}/$userId.png';
      final ref = _storage.ref(path);

      await ref
          .putData(bytes, SettableMetadata(contentType: 'image/png'))
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

  /// Deletes the user's profile photo from Storage.
  /// Silently ignores "not found" — the file may never have been uploaded.
  Future<void> deleteProfilePhoto(String userId) async {
    try {
      final path = '${AppConstants.storageUserAvatars}/$userId.png';
      await _storage.ref(path).delete().timeout(_timeout);
    } on FirebaseException catch (e) {
      // object-not-found is expected when the user never uploaded a photo
      if (e.code != 'object-not-found') {
        throw StorageException.uploadFailed(e);
      }
    } catch (_) {
      // Ignore other errors (including timeout) during account deletion cleanup
    }
  }

  /// Deletes every completion photo uploaded by [userId]. Best-effort —
  /// used during account deletion, where a partial Storage cleanup failure
  /// shouldn't block the rest of the cascade.
  Future<void> deleteCompletionPhotos(String userId) async {
    try {
      final dir = _storage.ref('${AppConstants.storageCompletionPhotos}/$userId');
      final listing = await dir.listAll().timeout(_timeout);
      await Future.wait(listing.items.map((ref) => ref.delete()))
          .timeout(_timeout);
    } catch (_) {
      // Ignore — best-effort cleanup during account deletion.
    }
  }
}
