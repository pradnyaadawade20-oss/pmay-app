import 'package:flutter/material.dart';
import '../common.dart';
import 'dashboard.dart';

/// Layout used ONLY when the signed-in user is an Allotment Manager (Api.i.isAllotOnly).
/// No sidebar: a simple top bar like the screenshots.
///  - Unit Allotment   -> "Krutarth - Allotment Dashboard"  [Dashboard] [Logout]
///  - All Applications -> "<- Back"  "Krutarth - All Applications"  [Logout]
class AllotShell extends StatefulWidget {
  final VoidCallback onLogout;
  const AllotShell({super.key, required this.onLogout});
  @override
  State<AllotShell> createState() => _AllotShellState();
}

class _AllotShellState extends State<AllotShell> {
  Widget? _sub;
  String _subTitle = '';

  void _open(String title, Widget page) => setState(() {
        _sub = page;
        _subTitle = title;
      });

  void _home() => setState(() => _sub = null);

  bool get _isApps => _sub != null && _subTitle == 'All Applications';

  Widget _logout() => OutlinedButton.icon(
        onPressed: widget.onLogout,
        icon: const Icon(Icons.logout_rounded, size: 18, color: kInk),
        label: const Text('Logout', style: TextStyle(color: kInk, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
      );

  Widget _header(bool wide) {
    final title = _isApps ? 'Krutarth - All Applications' : 'Krutarth - Allotment Dashboard';
    final icon = _isApps ? Icons.people_alt_outlined : Icons.apartment_rounded;
    return Container(
      height: 76,
      padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: kLine))),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: Row(children: [
            if (_isApps) ...[
              TextButton.icon(
                onPressed: _home,
                icon: const Icon(Icons.arrow_back_rounded, size: 18, color: kInk),
                label: const Text('Back', style: TextStyle(color: kInk, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 12),
            ],
            Icon(icon, size: 30, color: kBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: wide ? 24 : 17, fontWeight: FontWeight.w800, color: kInk)),
            ),
            if (!_isApps && _sub != null)
              TextButton(
                onPressed: _home,
                child: const Text('Dashboard', style: TextStyle(color: kInk, fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            const SizedBox(width: 8),
            _logout(),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final wide = w >= 700;
    final body = _sub != null ? KeyedSubtree(key: ValueKey(_subTitle), child: _sub!) : DashboardPage(onOpen: _open);
    return Scaffold(
      body: Column(children: [
        _header(wide),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1500),
              child: Padding(padding: EdgeInsets.all(wide ? 24 : 12), child: body),
            ),
          ),
        ),
      ]),
    );
  }
}