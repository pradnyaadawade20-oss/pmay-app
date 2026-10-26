import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../theme.dart';
import '../tour.dart';
import '../widgets.dart';
import 'apply.dart';
import 'dashboard.dart';
import 'auth.dart';
import 'login.dart';
import 'notifications.dart';
import 'profile_pages.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

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
          Text((a?['email'] ?? s.email ?? '').toString(), style: const TextStyle(color: Colors.black54)),
        ])),
      ]),
      if (!s.loggedIn) ...[
        const SizedBox(height: 16),
        orangeButton('Login', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen()))),
        const SizedBox(height: 8),
        OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen(startOnSignUp: true))),
            child: const Text('Sign Up')),
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
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ApplyScreen()));
              return;
            }
            Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
          }),
          const Divider(height: 1),
          item(Icons.person_outline, 'Personal Details', 'Your registration information', () {
            if (a == null) {
              toast(context, 'No profile found', error: true);
              return;
            }
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonalDetailsScreen()));
          }),
          const Divider(height: 1),
          item(Icons.language, 'Language', 'English', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LanguageScreen()))),
          const Divider(height: 1),
          item(Icons.notifications_none, 'Notifications', 'Updates about your application', () => openNotifications(context)),
          const Divider(height: 1),
          item(Icons.tour_outlined, 'App Guide', 'Take a quick tour of the app', () {
            final overlay = Overlay.of(context, rootOverlay: true);
            context.read<AppState>().goToTab(0); // tour Home se shuru hota hai
            Future.delayed(const Duration(milliseconds: 500), () => AppTour.startOn(overlay));
          }),
          const Divider(height: 1),
          item(Icons.help_outline, 'Help & Support', 'Contact us & FAQs', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpSupportScreen()))),
          const Divider(height: 1),
          item(Icons.info_outline, 'About App', 'Version 1.0.0', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()))),
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