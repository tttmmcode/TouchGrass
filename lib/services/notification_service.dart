import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;

  /// This device's FCM registration token, for storing on the user's
  /// Firestore document so a future backend can send targeted (not just
  /// topic-broadcast) notifications. Never throws — a missing token just
  /// means this device won't receive targeted pushes, not a fatal error.
  ///
  /// Web needs a VAPID key (`getToken(vapidKey:)`) — see
  /// `AppConstants.fcmVapidKey` (KNOWN_BUGS.md B4). Until one is supplied
  /// via `--dart-define=FCM_VAPID_KEY=...`, this intentionally returns null
  /// on web rather than guessing one; once it is, this starts working with
  /// no other code changes.
  Future<String?> getToken() async {
    if (kIsWeb && !AppConstants.fcmVapidConfigured) return null;
    try {
      return await _messaging.getToken(
        vapidKey: kIsWeb ? AppConstants.fcmVapidKey : null,
      );
    } catch (e) {
      debugPrint('[NotificationService] getToken failed: $e');
      return null;
    }
  }

  /// Fires whenever the OS rotates this device's FCM token (happens
  /// periodically, independent of sign-in/out) — callers should re-save it.
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  Future<void> initialize() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    if (!kIsWeb) {
      // iOS: show alert/badge/sound even when the app is in the foreground.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Topic subscriptions are not supported on web.
      await _messaging.subscribeToTopic(AppConstants.fcmTopicDaily);
      await _messaging.subscribeToTopic(AppConstants.fcmTopicStreakWarning);
    }
  }

  /// Foreground messages — app is open and in focus.
  Stream<RemoteMessage> get onForeground => FirebaseMessaging.onMessage;

  /// User tapped a notification while the app was in the background.
  Stream<RemoteMessage> get onTap => FirebaseMessaging.onMessageOpenedApp;

  /// Returns the notification that launched the app from terminated state,
  /// or null when the app was opened normally.
  Future<RemoteMessage?> getInitialMessage() => _messaging.getInitialMessage();
}
