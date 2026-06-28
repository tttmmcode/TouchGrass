import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;

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
  Future<RemoteMessage?> getInitialMessage() =>
      _messaging.getInitialMessage();
}
