import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';
import 'applicants.dart';
import 'dashboard.dart';
import 'payment_management.dart';

class AdminShell extends StatefulWidget {
  final VoidCallback onLogout;
  const AdminShell({super.key, required this.onLogout});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _i = 0;
  Widget? _sub; // dashboard ke Quick Actions se khula page
  String _subTitle = '';

  static const _items = [
    (Icons.space_dashboard_rounded, 'Dashboard', 'Overview of registrations and payments'),
    (Icons.people_alt_rounded, 'Applicants', 'Review documents and manage applications'),
    (Icons.account_balance_wallet_rounded, 'Payments', 'Confirm or reject pending payments'),
  ];

  void _openSub(String title, Widget page) => setState(() {
        _sub = page;
        _subTitle = title;
      });

  void _go(int k) => setState(() {
        _i = k;
        _sub = null;
      });

  Widget _page() {
    if (_sub != null) return KeyedSubtree(key: ValueKey(_subTitle), child: _sub!);
    return switch (_i) {
      0 => DashboardPage(onOpen: _openSub),
      1 => const ApplicantsPage(),
      _ => const PaymentManagementPage(),
    };
  }

  Widget _navTile(int k, bool drawer) {
    final on = _i == k && _sub == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Material(
        color: on ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            _go(k);
            if (drawer) Navigator.pop(context);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            child: Row(children: [
              AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(color: on ? kOrange : Colors.transparent, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 12),
              Icon(_items[k].$1, size: 20, color: on ? Colors.white : Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_items[k].$2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: on ? Colors.white : Colors.white70, fontWeight: on ? FontWeight.w700 : FontWeight.w500, fontSize: 14.5)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _menu({required bool drawer}) => Container(
        width: 260,
        decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kNavy, kBlue])),
        child: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.apartment_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Krutarth PMAY', overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                    Text('Admin Console', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(26, 0, 26, 8),
              child: Text('MENU', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
            ),
            for (var k = 0; k < _items.length; k++)
              if (k == 0 || !Api.i.isAdminOnly) if (k != 2 || Api.i.canPayments) _navTile(k, drawer),
          ]),
        ),
      );

  Widget _top(bool wide) {
    final title = _sub != null ? _subTitle : _items[_i].$2;
    final sub = _sub != null ? 'Dashboard / $_subTitle' : _items[_i].$3;
    return Container(
      height: 76,
      padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 8),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: kLine))),
      child: Row(children: [
        if (!wide)
          Builder(builder: (c) => IconButton(onPressed: () => Scaffold.of(c).openDrawer(), icon: const Icon(Icons.menu_rounded, color: kInk))),
        if (_sub != null)
          IconButton(onPressed: () => _go(0), tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded, color: kInk)),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk)),
            if (wide) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: kMuted)),
          ]),
        ),
        if (wide && (Api.i.email ?? '').isNotEmpty) ...[
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(Api.i.email!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted))),
          const SizedBox(width: 12),
        ],
        Avatar(Api.i.email ?? 'Admin', size: 38),
        const SizedBox(width: 4),
        IconButton(onPressed: widget.onLogout, tooltip: 'Logout', icon: const Icon(Icons.logout_rounded, color: kMuted)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final wide = w >= 900;
    return Scaffold(
      drawer: wide ? null : Drawer(width: 260, child: _menu(drawer: true)),
      body: Row(children: [
        if (wide) _menu(drawer: false),
        Expanded(
          child: Column(children: [
            _top(wide),
            Expanded(child: Padding(padding: EdgeInsets.all(w < 700 ? 12 : 24), child: _page())),
          ]),
        ),
      ]),
    );
  }
}