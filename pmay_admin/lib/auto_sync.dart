import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';

/// Keeps every admin screen up to date without a manual refresh.
/// Every 2 seconds it asks the server for a tiny "revision" (GET /admin/sync). Only when that revision changed
/// (someone approved a step, an applicant uploaded a file, a payment came in ...) it bumps [tick], and the open
/// screens reload their data quietly (no spinner, scroll position and typed text stay as they are).
class AutoSync {
  static const every = Duration(seconds: 2);
  static final tick = ValueNotifier<int>(0);
  static Timer? _timer;
  static String? _rev;
  static bool _busy = false;

  static void start() {
    stop();
    _timer = Timer.periodic(every, (_) => _poll());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _rev = null;
  }

  static Future<void> _poll() async {
    if (_busy || !Api.i.loggedIn) return;
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) return; // browser tab hidden / app in background
    _busy = true; // never overlap requests when the server is slow
    try {
      final r = await Api.i.get('/admin/sync');
      final rev = '${r['rev']}';
      if (_rev != null && rev != _rev) tick.value++;
      _rev = rev;
    } catch (_) {
      // offline or server waking up: try again on the next tick
    } finally {
      _busy = false;
    }
  }
}

/// Add to a screen's State (`with AutoSyncMixin`) and implement [onSync] (usually `_load(silent: true)`).
mixin AutoSyncMixin<T extends StatefulWidget> on State<T> {
  void onSync();

  void _onTick() {
    if (mounted) onSync();
  }

  @override
  void initState() {
    super.initState();
    AutoSync.tick.addListener(_onTick);
  }

  @override
  void dispose() {
    AutoSync.tick.removeListener(_onTick);
    super.dispose();
  }
}
