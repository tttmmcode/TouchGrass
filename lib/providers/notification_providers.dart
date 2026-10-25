import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../services/notification_service.dart';
import 'auth_providers.dart';
import 'user_providers.dart';

final notificationServiceProvider = Provider<NotificationService>(
  (_) => NotificationService(),
);

/// Emits each [RemoteMessage] received while the app is in the foreground.
final foregroundMessageProvider = StreamProvider<RemoteMessage>((ref) {
  return ref.watch(notificationServiceProvider).onForeground;
});

/// Saves this device's FCM token to the signed-in user's document, and keeps
/// it current if the OS rotates it during the session.
///
/// Keyed off [authStateProvider] (uid) rather than [currentUserProvider], so
/// this only re-runs on actual sign-in/out — not on every unrelated field
/// change the realtime user-document listener emits.
///
/// Watch this once from the app root (alongside [analyticsBootstrapProvider]
/// in user_providers.dart) so it stays alive for the whole session.
final fcmTokenSyncProvider = Provider<void>((ref) {
  // No token is stored while no reminders exist (Phase 8, data
  // minimisation).
  if (!AppConstants.remindersAvailable) return;
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return;

  final notificationService = ref.watch(notificationServiceProvider);
  final userRepository = ref.watch(userRepositoryProvider);

  Future<void> saveToken(String? token) async {
    if (token == null || token.isEmpty) return;
    await userRepository.updateUserFields(uid, {'fcmToken': token});
  }

  notificationService.getToken().then(saveToken);
  final subscription = notificationService.onTokenRefresh.listen(saveToken);
  ref.onDispose(subscription.cancel);
});
