import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';

class StorageService {
  StorageService() : _storage = FirebaseStorage.instance;

  final FirebaseStorage _storage;

  // ── Challenge completion photos ────────────────────────────────────────────

  Future<String> uploadCompletionPhoto({
    required String userId,
    required Uint8List bytes,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path =
          '${AppConstants.storageCompletionPhotos}/$userId/$timestamp.jpg';
      final ref = _storage.ref(path);

      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      return ref.getDownloadURL();
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
    try {
      final path = '${AppConstants.storageUserAvatars}/$userId.png';
      final ref = _storage.ref(path);

      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/png'),
      );

      return ref.getDownloadURL();
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
      await _storage.ref(path).delete();
    } on FirebaseException catch (e) {
      // object-not-found is expected when the user never uploaded a photo
      if (e.code != 'object-not-found') {
        throw StorageException.uploadFailed(e);
      }
    } catch (_) {
      // Ignore other errors during account deletion cleanup
    }
  }
}
