import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/notification_service.dart';

final notificationServiceProvider = Provider<NotificationService>(
  (_) => NotificationService(),
);

/// Emits each [RemoteMessage] received while the app is in the foreground.
final foregroundMessageProvider = StreamProvider<RemoteMessage>((ref) {
  return ref.watch(notificationServiceProvider).onForeground;
});
