import 'package:flutter/foundation.dart';
import 'api.dart';
import 'push.dart';

/// App-wide state: auth + the applicant's full record (/api/me).
class AppState extends ChangeNotifier {
  final Api api = Api();
  bool ready = false;
  bool get loggedIn => api.token != null;
  bool guest = false; // Get Started -> home without login
  bool get inApp => loggedIn || guest;

  /// Set to a tab index to make MainShell jump to that tab (e.g. 1 = Tracking after OTP verify).
  int? pendingTab;

  void goToTab(int i) {
    pendingTab = i;
    notifyListeners();
  }

  // ---- notifications: stored on the server (/me/notifications) ----
  List<Map<String, dynamic>> notifications = [];
  int unread = 0;
  bool verifyNoteRead = false; // local "Verify your account" card

  Future<void> loadNotifications() async {
    if (!loggedIn) return;
    try {
      final r = await api.get('/me/notifications');
      notifications = List<Map<String, dynamic>>.from((r['notifications'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
      unread = (r['unread'] ?? 0) as int;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markRead(String id) async {
    if (id == 'verify') {
      if (!verifyNoteRead) {
        verifyNoteRead = true;
        notifyListeners();
      }
      return;
    }
    final i = notifications.indexWhere((n) => '${n['id']}' == id);
    if (i < 0 || notifications[i]['read_at'] != null) return;
    notifications[i]['read_at'] = DateTime.now().toIso8601String(); // optimistic
    unread = unread > 0 ? unread - 1 : 0;
    notifyListeners();
    try {
      await api.postJson('/me/notifications/read', {'ids': [id]});
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    final now = DateTime.now().toIso8601String();
    for (final n in notifications) {
      n['read_at'] ??= now;
    }
    unread = 0;
    verifyNoteRead = true;
    notifyListeners();
    try {
      await api.postJson('/me/notifications/read', {'all': true});
    } catch (_) {}
  }

  // ---- push (FCM) ----
  String? _pushToken;

  /// Ask permission, get the FCM token and register it with the backend. Safe to call repeatedly.
  Future<void> registerPush() async {
    if (!loggedIn) return;
    final t = await PushService.getToken();
    if (t == null) {
      debugPrint('FCM: no token (notification permission denied or Firebase not configured)');
      return;
    }
    _pushToken = t;
    debugPrint('FCM token: $t'); // paste in Firebase Console > Messaging > Send test message
    try {
      await api.postJson('/me/device-token', {'token': t, 'platform': 'android'});
    } catch (_) {}
  }

  Future<void> _unregisterPush() async {
    final t = _pushToken;
    _pushToken = null;
    if (t == null || !loggedIn) return;
    try {
      await api.postJson('/me/device-token/delete', {'token': t});
    } catch (_) {}
  }

  void enterGuest() {
    guest = true;
    notifyListeners();
  }
  Map<String, dynamic>? me; // whole /me response
  List<String> roles = [];

  Map<String, dynamic>? get applicant => me?['applicant'] as Map<String, dynamic>?;
  Map<String, dynamic>? get unit => me?['unit'] as Map<String, dynamic>?;
  Map<String, dynamic>? get project => me?['project'] as Map<String, dynamic>?;
  Map<String, dynamic>? get loan => me?['loan'] as Map<String, dynamic>?;
  List get payments => (me?['payments'] as List?) ?? [];
  String get stage => (applicant?['registration_stage'] ?? 'stage_1_registered') as String;

  Future<void> init() async {
    api.onUnauthorized = () => logout();
    await api.loadToken();
    await PushService.init(
      onForeground: (title, body) {
        refresh().catchError((_) {}); // stage may have changed
      },
      onOpened: () => goToTab(1), // tapped a push -> Tracking tab
      onTokenRefresh: (_) => registerPush(),
    );
    PushService.askPermission(); // ask "Allow notifications?" right when the app first opens
    if (loggedIn) {
      try {
        await refresh();
      } catch (_) {}
      registerPush();
    }
    ready = true;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final r = await api.postJson('/auth/login', {'email': email, 'password': password});
    await api.saveToken(r['token'] as String);
    roles = List<String>.from(r['roles'] ?? []);
    await refresh();
    registerPush();
  }

  String? get email => me?['email'] as String?;

  /// Email + password only: creates the account and logs the user in (application is filled later).
  Future<void> signUp(String email, String password) async {
    final r = await api.postJson('/auth/signup', {'email': email, 'password': password});
    await api.saveToken(r['token'] as String);
    roles = [];
    await refresh();
    registerPush();
  }

  Future<void> registerWith(Map<String, String> fields, Map<String, String> files) async {
    final r = await api.postMultipart('/auth/register', fields: fields, files: files);
    await api.saveToken(r['token'] as String);
    await refresh();
    registerPush();
  }

  Future<void> refresh() async {
    me = await api.get('/me');
    roles = List<String>.from(me?['roles'] ?? []);
    notifyListeners();
    await loadNotifications();
  }

  Future<void> logout() async {
    await _unregisterPush(); // stop pushes to this device for the old account
    await api.saveToken(null);
    guest = false;
    me = null;
    roles = [];
    notifications = [];
    unread = 0;
    verifyNoteRead = false;
    notifyListeners();
  }
}