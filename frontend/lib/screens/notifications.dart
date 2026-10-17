import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../theme.dart';
import 'otp.dart';

/// Bell icon / drawer / Profile se yahi screen khulti hai.
void openNotifications(BuildContext context) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
}

enum _Go { none, verify, track }

class _Note {
  final String id;
  final IconData icon;
  final Color color;
  final String title, message;
  final _Go go;
  final DateTime time;
  final bool unread;
  const _Note(this.id, this.icon, this.color, this.title, this.message, this.go, this.time, this.unread);
}

(IconData, Color) _style(String kind) {
  const red = Colors.red;
  final green = Colors.green.shade700;
  return switch (kind) {
    'validation_accepted' => (Icons.payments_outlined, kBlue),
    'validation_rejected' || 'payment_rejected' || 'agreement_rejected' || 'bank_docs_rejected' => (Icons.cancel_outlined, red),
    'payment_accepted' => (Icons.home_work_outlined, kOrange),
    'unit_allotted' => (Icons.description_outlined, kBlue),
    'agreement_submitted' || 'bank_docs_submitted' => (Icons.hourglass_top, kOrange),
    'agreement_accepted' || 'bank_docs_accepted' => (Icons.account_balance_outlined, kBlue),
    'loan_receipt_submitted' => (Icons.gavel, kBlue),
    'completed' => (Icons.celebration_outlined, green),
    _ => (Icons.notifications_none, kBlue),
  };
}

/// Server notifications + two local prompts (welcome for guests, "verify" until the account is verified).
List<_Note> _build(AppState s) {
  final now = DateTime.now();
  if (!s.loggedIn || s.applicant == null) {
    return [
      _Note('welcome', Icons.campaign_outlined, kBlue, 'Welcome to Krutarth - PMAY',
          'Login or register to track your application and get updates here.', _Go.none, now, false),
    ];
  }
  final a = s.applicant!;
  final verified = a['email_verified'] == true || a['phone_verified'] == true;
  return [
    if (!verified)
      _Note('verify', Icons.verified_user_outlined, kOrange, 'Verify your account',
          'Verify your email or phone number to continue. Tap to verify now.', _Go.verify, now, !s.verifyNoteRead),
    for (final n in s.notifications) _fromServer(n, now),
  ];
}

_Note _fromServer(Map<String, dynamic> n, DateTime fallback) {
  final (icon, color) = _style('${n['kind']}');
  return _Note('${n['id']}', icon, color, '${n['title']}', '${n['body']}', _Go.track,
      DateTime.tryParse('${n['created_at']}')?.toLocal() ?? fallback, n['read_at'] == null);
}

/// Bell badge.
bool hasUnreadNotifications(AppState s) => _build(s).any((n) => n.unread);

String _timeText(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} hr ago';
  if (d.inHours < 48) return 'Yesterday, ${DateFormat('h:mm a').format(t)}';
  return DateFormat('d MMM yyyy, h:mm a').format(t);
}

const _dotColor = Color(0xFFE53935);

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppState>().loadNotifications());
  }

  void _tap(BuildContext context, _Note n) {
    final s = context.read<AppState>();
    s.markRead(n.id); // read karte hi dot hat jaata hai
    switch (n.go) {
      case _Go.verify:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const OtpScreen()));
      case _Go.track:
        s.goToTab(1); // Tracking tab
        Navigator.pop(context);
      case _Go.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final items = _build(s);
    final anyUnread = items.any((n) => n.unread);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton.icon(
            onPressed: anyUnread ? () => s.markAllRead() : null,
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('Mark all as read', style: TextStyle(fontSize: 12.5)),
            style: TextButton.styleFrom(foregroundColor: Colors.white, disabledForegroundColor: Colors.white54),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: s.loadNotifications,
        child: items.isEmpty
            ? ListView(children: const [
                SizedBox(height: 200),
                Center(child: Text('No notifications yet', style: TextStyle(color: Colors.black54))),
              ])
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final n = items[i];
                  final isNew = n.unread;
                  return Material(
                    color: isNew ? n.color.withValues(alpha: 0.07) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _tap(context, n),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: n.color.withValues(alpha: isNew ? 0.35 : 0.15)),
                          boxShadow: [BoxShadow(color: n.color.withValues(alpha: isNew ? 0.12 : 0.04), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(color: n.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
                            child: Icon(n.icon, color: n.color, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(
                                  child: Text(n.title, style: TextStyle(fontSize: 15.5, fontWeight: isNew ? FontWeight.bold : FontWeight.w600)),
                                ),
                                if (isNew)
                                  Container(
                                      width: 10,
                                      height: 10,
                                      margin: const EdgeInsets.only(left: 8),
                                      decoration: const BoxDecoration(color: _dotColor, shape: BoxShape.circle)),
                              ]),
                              const SizedBox(height: 3),
                              Text(n.message, style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.4)),
                              if (n.id != 'welcome' && n.id != 'verify') ...[
                                const SizedBox(height: 8),
                                Row(children: [
                                  const Icon(Icons.access_time, size: 13, color: Colors.black38),
                                  const SizedBox(width: 4),
                                  Text(_timeText(n.time), style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
                                ]),
                              ],
                            ]),
                          ),
                          if (n.go != _Go.none)
                            const Padding(padding: EdgeInsets.only(left: 6, top: 10), child: Icon(Icons.chevron_right, color: Colors.black38)),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}