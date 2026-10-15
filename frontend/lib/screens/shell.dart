import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home.dart';
import 'login.dart';
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
  bool _drawerOpen = false;
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

  void _help() => showDialog(
      context: context,
      builder: (_) => AlertDialog(
            title: const Text('Help & Support'),
            content: const Text('Phone: $supportPhone\nEmail: $supportEmail'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
          ));

  Widget _drawer(AppState s) {
    final a = s.applicant;
    final name = a == null ? (s.loggedIn ? 'Account' : 'Guest') : '${a['first_name']} ${a['last_name']}';
    final email = (a?['email'] ?? '').toString();
    Widget item(IconData icon, String label, VoidCallback onTap, {bool selected = false}) => ListTile(
        leading: Icon(icon, color: selected ? kBlue : Colors.black54),
        title: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        selected: selected,
        selectedTileColor: kBlue.withValues(alpha: 0.08),
        onTap: () {
          Navigator.pop(context);
          onTap();
        });
    return Drawer(
      child: ListView(padding: EdgeInsets.zero, children: [
        UserAccountsDrawerHeader(
          decoration: const BoxDecoration(color: kBlue),
          accountName: Text(name),
          accountEmail: Text(email),
          currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 24, color: kBlue))),
        ),
        item(Icons.home_outlined, 'Home', () => _go(0), selected: _i == 0),
        item(Icons.route_outlined, 'Tracking', () => _go(1), selected: _i == 1),
        item(Icons.location_city_outlined, 'Projects', () => _go(2), selected: _i == 2),
        item(Icons.person_outline, 'Profile', () => _go(3), selected: _i == 3),
        item(Icons.notifications_none, 'Notifications', () => openNotifications(context)),
        item(Icons.help_outline, 'Help & Support', _help),
        item(Icons.settings_outlined, 'Settings', () => toast(context, 'Coming soon')),
        const Divider(),
        if (s.loggedIn)
          item(Icons.logout, 'Logout', () => s.logout())
        else
          item(Icons.login, 'Login', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()))),
      ]),
    );
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
      // Drawer khula ho to normal back (drawer band) chalne do.
      canPop: _drawerOpen,
      onPopInvokedWithResult: _onBack,
      child: Scaffold(
      onDrawerChanged: (open) => setState(() => _drawerOpen = open),
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
          if (!s.loggedIn)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                child: const Text('Login', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          IconButton(
              icon: Badge(smallSize: 9, isLabelVisible: hasUnreadNotifications(s), child: const Icon(Icons.notifications_none)),
              onPressed: () => openNotifications(context)),
        ],
      ),
      drawer: _drawer(s),
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