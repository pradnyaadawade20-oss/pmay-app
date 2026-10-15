import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'apply.dart';
import 'dashboard.dart';
import 'login.dart';
import 'notifications.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _details(BuildContext c, Map<String, dynamic>? a) {
    if (a == null) {
      toast(c, 'No profile found', error: true);
      return;
    }
    Widget row(String k, String? v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(v ?? '-', style: const TextStyle(fontWeight: FontWeight.w600))),
        ]));
    showModalBottomSheet(
        context: c,
        builder: (_) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              row('Name', '${a['first_name']} ${a['last_name']}'),
              row('Applicant ID', a['unique_id']?.toString()),
              row('Email', a['email']?.toString()),
              row('Mobile', a['phone']?.toString()),
            ])));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final a = s.applicant;
    final name = a == null ? (s.loggedIn ? 'Account' : 'Guest') : '${a['first_name']} ${a['last_name']}';

    Widget item(IconData icon, String title, String sub, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: kBlue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: sub.isEmpty ? null : Text(sub, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap);

    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        CircleAvatar(
            radius: 32,
            backgroundColor: kBlue,
            child: Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 26, color: Colors.white))),
        const SizedBox(width: 14),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text((a?['email'] ?? '').toString(), style: const TextStyle(color: Colors.black54)),
        ])),
      ]),
      if (!s.loggedIn) ...[
        const SizedBox(height: 16),
        orangeButton('Login', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()))),
        const SizedBox(height: 8),
        OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApplyScreen())),
            child: const Text('Apply for PMAY / Sign Up')),
      ],
      const SizedBox(height: 16),
      Card(
        child: Column(children: [
          item(Icons.description_outlined, 'My Application', 'View & track your applications', () {
            if (!s.loggedIn) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              return;
            }
            if (a == null) {
              toast(context, 'No application found', error: true);
              return;
            }
            Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
          }),
          const Divider(height: 1),
          item(Icons.person_outline, 'Personal Details', '', () => _details(context, a)),
          const Divider(height: 1),
          item(Icons.language, 'Language', 'English', () => toast(context, 'More languages coming soon')),
          const Divider(height: 1),
          item(Icons.notifications_none, 'Notifications', '', () => openNotifications(context)),
          const Divider(height: 1),
          item(Icons.help_outline, 'Help & Support', '', () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                    title: const Text('Help & Support'),
                    content: const Text('Phone: $supportPhone\nEmail: $supportEmail'),
                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                  ))),
          const Divider(height: 1),
          item(Icons.info_outline, 'About App', '', () => showAboutDialog(
              context: context, applicationName: 'Krutarth - PMAY', applicationVersion: '1.0.0')),
        ]),
      ),
      const SizedBox(height: 16),
      if (s.loggedIn)
        OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: Colors.red),
            onPressed: () => s.logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Logout')),
    ]);
  }
}