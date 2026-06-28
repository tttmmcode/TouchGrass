import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../core/errors/app_exception.dart';

/// Wraps Firebase Auth, Google Sign-In, and Apple Sign-In.
///
/// This class translates platform-specific exceptions into our
/// [AppException] hierarchy so the repository layer never sees raw
/// [FirebaseAuthException] or SDK-specific types.
class AuthService {
  AuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  // ── Streams ────────────────────────────────────────────────────────────────

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // ── Sign-in ────────────────────────────────────────────────────────────────

  Future<UserCredential> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Web uses a popup flow; google_sign_in package is mobile-only.
        return await _auth.signInWithPopup(GoogleAuthProvider());
      }

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw AuthException.cancelled();

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return _auth.signInWithCredential(credential);
    } on AuthException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    } catch (e) {
      throw AuthException.providerError(e);
    }
  }

  Future<UserCredential> signInWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      return _auth.signInWithCredential(oauthCredential);
    } on AuthException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw AuthException.cancelled();
      }
      throw AuthException.providerError(e);
    } catch (e) {
      throw AuthException.providerError(e);
    }
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    } catch (e) {
      throw AuthException.providerError(e);
    }
  }

  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (displayName != null && displayName.isNotEmpty) {
        await credential.user?.updateDisplayName(displayName.trim());
      }
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    } catch (e) {
      throw AuthException.providerError(e);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    } catch (e) {
      throw AuthException.providerError(e);
    }
  }

  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  // ── Reauthentication (required before sensitive operations) ───────────────

  /// Reauthenticates an email/password user.
  /// Must be called before [deleteAccount] for email users.
  Future<void> reauthenticateWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = EmailAuthProvider.credential(
        email: email.trim(),
        password: password,
      );
      await _auth.currentUser?.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    } catch (e) {
      throw AuthException.providerError(e);
    }
  }

  /// Reauthenticates a Google user.
  /// Must be called before [deleteAccount] for Google users.
  Future<void> reauthenticateWithGoogle() async {
    try {
      if (kIsWeb) {
        await _auth.currentUser?.reauthenticateWithPopup(GoogleAuthProvider());
        return;
      }
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw AuthException.cancelled();

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.currentUser?.reauthenticateWithCredential(credential);
    } on AuthException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    } catch (e) {
      throw AuthException.providerError(e);
    }
  }

  /// Deletes the current Firebase Auth account.
  /// Caller must reauthenticate first.
  Future<void> deleteAuthAccount() async {
    try {
      await _auth.currentUser?.delete();
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  AppException _mapFirebaseException(FirebaseAuthException e) {
    return switch (e.code) {
      'user-disabled' => AuthException.accountDisabled(),
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' =>
        const DataException(message: 'Email or password is incorrect.'),
      'email-already-in-use' =>
        const DataException(
            message: 'An account with this email already exists.'),
      'weak-password' =>
        const DataException(
            message: 'Password must be at least 6 characters.'),
      'invalid-email' =>
        const DataException(message: 'Please enter a valid email address.'),
      'network-request-failed' => NetworkException.noConnection(),
      'popup-closed-by-user' ||
      'cancelled-popup-request' =>
        AuthException.cancelled(),
      _ => AuthException.providerError(e),
    };
  }
}
