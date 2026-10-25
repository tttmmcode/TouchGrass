import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/support_contact.dart';
import '../core/errors/app_exception.dart';

/// Deletes the signed-in user's account server-side (audit D-04).
///
/// The client cannot delete its own data — firestore.rules / storage.rules
/// deny those deletes on purpose — so the `deleteAccount` Cloud Function
/// (functions/src/index.ts) removes every user-owned document, file and
/// finally the Auth account with the Admin SDK. It is idempotent: after any
/// failure the user can simply retry.
abstract class AccountDeletionService {
  /// Completes only when the server confirms the account is fully deleted;
  /// throws an [AppException] otherwise. Never reports partial success.
  Future<void> deleteCurrentAccount();
}

class CloudAccountDeletionService implements AccountDeletionService {
  CloudAccountDeletionService({FirebaseFunctions? functions})
    : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;

  // Resolved lazily so constructing the service never touches Firebase.
  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'us-central1');

  @override
  Future<void> deleteCurrentAccount() async {
    final Object? data;
    try {
      final result = await _functions
          .httpsCallable(
            'deleteAccount',
            options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
          )
          .call<Object?>();
      data = result.data;
    } on FirebaseFunctionsException catch (e) {
      throw mapAccountDeletionError(e.code, e);
    } catch (e) {
      throw mapAccountDeletionError('unknown', e);
    }
    if (data is! Map || data['deleted'] != true) {
      throw mapAccountDeletionError('unknown', data);
    }
  }
}

/// Maps a callable error code to a message that is honest about what
/// happened: nothing here ever claims the account was deleted.
@visibleForTesting
AppException mapAccountDeletionError(String code, [Object? cause]) {
  return switch (code) {
    'failed-precondition' => DataException(
      message:
          'For your security, please sign in again, then delete your account.',
      cause: cause,
    ),
    'unauthenticated' => DataException(
      message: 'Your session expired. Please sign in again and retry.',
      cause: cause,
    ),
    // The request may have reached the server before the connection
    // dropped or the client gave up waiting, so deletion may have finished
    // or be partly done: say so honestly. Retrying is safe (idempotent).
    'unavailable' || 'deadline-exceeded' => NetworkException(
      message:
          "We couldn't confirm that your account was deleted because the "
          'connection was interrupted. Please check your connection and try '
          'again — retrying is safe and finishes anything left.',
      cause: cause,
    ),
    'not-found' => DataException(
      message:
          "Account deletion isn't available right now, so your account was "
          'not deleted. Please try again later, or ${SupportContact.reachUs}.',
      cause: cause,
    ),
    _ => DataException(
      message:
          "We couldn't finish deleting your account. Please try again — "
          'anything already removed stays removed. If this keeps happening, '
          '${SupportContact.reachUs}.',
      cause: cause,
    ),
  };
}
