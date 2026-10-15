import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'api.dart' show kMock;

/// Lets us show an in-app banner when a push arrives while the app is open.
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

void showPushBanner(String? title, String? body) {
  if (title == null && body == null) return;
  messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null) Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        if (body != null) Text(body),
      ]),
    ));
}

/// Background / terminated pushes with a "notification" payload are shown by Android itself.
@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage m) async {}

/// Firebase Cloud Messaging wrapper. If Firebase is not configured (no google-services.json),
/// or on web / demo mode, everything silently becomes a no-op and the app works as before.
class PushService {
  static bool _ready = false;

  static Future<void> init({
    required void Function(String? title, String? body) onForeground,
    required VoidCallback onOpened,
    required void Function(String token) onTokenRefresh,
  }) async {
    if (kIsWeb || kMock || _ready) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Push disabled (Firebase not configured): $e');
      return;
    }
    _ready = true;
    final fm = FirebaseMessaging.instance;
    FirebaseMessaging.onBackgroundMessage(_bgHandler);
    FirebaseMessaging.onMessage.listen((m) => onForeground(m.notification?.title, m.notification?.body));
    FirebaseMessaging.onMessageOpenedApp.listen((_) => onOpened());
    fm.onTokenRefresh.listen(onTokenRefresh);
    if (await fm.getInitialMessage() != null) onOpened(); // app launched by tapping a push
  }

  static Future<AuthorizationStatus?>? _perm;

  /// Shows the system "Allow notifications?" dialog (Android 13+). Safe to call many times:
  /// concurrent calls share one dialog. Call it as soon as the app starts.
  static Future<AuthorizationStatus?> askPermission() {
    if (!_ready) return Future.value(null);
    return _perm ??= _ask().whenComplete(() => _perm = null);
  }

  static Future<AuthorizationStatus?> _ask() async {
    try {
      return (await FirebaseMessaging.instance.requestPermission()).authorizationStatus;
    } catch (e) {
      debugPrint('Notification permission error: $e');
      return null;
    }
  }

  /// Returns the device token (null if notifications are denied or unavailable).
  static Future<String?> getToken() async {
    if (!_ready) return null;
    try {
      final st = await askPermission();
      if (st == null || st == AuthorizationStatus.denied) return null;
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('FCM token error: $e');
      return null;
    }
  }
}