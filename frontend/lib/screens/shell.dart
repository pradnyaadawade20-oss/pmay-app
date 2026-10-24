import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../widgets.dart';
import 'home.dart';
import 'notifications.dart';
import 'profile.dart';
import 'projects.dart';
import 'dashboard.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _i = 0;
  DateTime? _lastBack;
  static const _titles = ['Krutarth - PMAY', 'Tracking', 'Projects', 'Profile'];

  void _go(int i) => setState(() => _i = i);

  /// Back: tab != Home -> Home pe jao. Home pe -> do baar back dabane par hi app band.
  void _onBack(bool didPop, Object? result) {
    if (didPop) return;
    if (_i != 0) {
      _go(0);
      return;
    }
    final now = DateTime.now();
    if (_lastBack == null || now.difference(_lastBack!) > const Duration(seconds: 2)) {
      _lastBack = now;
      toast(context, 'Press back again to exit');
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // e.g. OTP verified -> jump to Tracking tab
    if (s.pendingTab != null) {
      final t = s.pendingTab!;
      s.pendingTab = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _go(t);
      });
    }
    final pages = [
      HomeScreen(onTab: _go),
      const TrackingScreen(),
      const ProjectsScreen(),
      const ProfileScreen(),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onBack,
      child: Scaffold(
      appBar: AppBar(
        title: _i == 0
            ? const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Krutarth - PMAY', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Pradhan Mantri Awas Yojana - Urban',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.white70)),
              ])
            : Text(_titles[_i]),
        actions: [
          IconButton(
              icon: Badge(smallSize: 9, isLabelVisible: hasUnreadNotifications(s), child: const Icon(Icons.notifications_none)),
              onPressed: () => openNotifications(context)),
        ],
      ),
      body: pages[_i],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Tracking'),
          NavigationDestination(
              icon: Icon(Icons.location_city_outlined), selectedIcon: Icon(Icons.location_city), label: 'Projects'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    ),
    );
  }
}