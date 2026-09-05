import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/navigation.dart';
import '../screens/notifications/notifications_screen.dart';
import 'auth_service.dart';

// Required by FCM to deliver messages while the app is backgrounded or
// terminated — the OS shows the system notification for the payload's
// `notification` block automatically in that state, so this only has to
// exist, not do anything.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Registers this device for push, and shows a heads-up banner for messages
/// that arrive while the app is in the foreground (FCM does not do this on
/// its own — Android silently drops the visual for a foregrounded app).
class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;
  PushService._internal();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  final _authService = AuthService();
  bool _foregroundHandlingInitialized = false;

  static const _channel = AndroidNotificationChannel(
    'reminders',
    'Reminders',
    description: 'Game reminders and activity nudges',
    importance: Importance.high,
  );

  Future<void> initForegroundHandling() async {
    if (_foregroundHandlingInitialized) return;
    _foregroundHandlingInitialized = true;

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (_) => _openNotifications(),
    );

    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    });

    // Backgrounded (tapped from the shade) and cold-started-from-terminated
    // both land here or in getInitialMessage — either way, open the bell.
    FirebaseMessaging.onMessageOpenedApp.listen((_) => _openNotifications());
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) _openNotifications();
  }

  void _openNotifications() {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  // Best-effort: permission denial or a token fetch failure must not block
  // sign-in, so every failure here is swallowed rather than surfaced.
  Future<void> requestPermissionAndRegister() async {
    try {
      await _messaging.requestPermission();
      final fcmToken = await _messaging.getToken();
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (fcmToken == null || idToken == null) return;

      await _authService.registerDeviceToken(
        fcmToken: fcmToken,
        token: idToken,
      );

      _messaging.onTokenRefresh.listen((newToken) async {
        final refreshedIdToken =
            await FirebaseAuth.instance.currentUser?.getIdToken();
        if (refreshedIdToken == null) return;
        await _authService.registerDeviceToken(
          fcmToken: newToken,
          token: refreshedIdToken,
        );
      });
    } catch (_) {
      // See comment above.
    }
  }
}
