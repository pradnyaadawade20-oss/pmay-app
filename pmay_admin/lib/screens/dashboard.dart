import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';
import 'all_applications.dart';
import 'agreement_receipts.dart';
import 'bank_documents.dart';
import 'banking_loans.dart';
import 'applicants.dart';
import 'database_tables.dart';
import 'document_settings.dart';
import 'payment_management.dart';
import 'unit_allotment.dart';
import 'validation_queue.dart';
import 'user_management.dart';

class DashboardPage extends StatefulWidget {
  final void Function(String title, Widget page) onOpen;
  const DashboardPage({super.key, required this.onOpen});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _Action {
  final IconData icon;
  final Color color;
  final String title, sub;
  final String? count, countLabel, linkLabel;
  final VoidCallback onTap;
  _Action(this.icon, this.color, this.title, this.sub, this.onTap, {this.count, this.countLabel, this.linkLabel});
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<Map<String, dynamic>> _f = Api.i.get(Ep.stats);
  late Future<Map<String, dynamic>> _sys = Api.i.get(Ep.systemStatus);

  void _refresh() => setState(() {
        _f = Api.i.get(Ep.stats);
        _sys = Api.i.get(Ep.systemStatus);
      });

  static const _purple = Color(0xFF6A47D9);
  static const _teal = Color(0xFF0891B2);

  // ---------- gradient stat cards (purane theme jaise) ----------
  Widget _stat(String label, Object? v, IconData icon, List<Color> g) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: g.last.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${v ?? 0}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1)),
              const SizedBox(height: 4),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white),
          ),
        ]),
      );

  // ---------- quick action card ----------
  Widget _actionCard(_Action a) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: a.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(minHeight: 170),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine), boxShadow: kShadow),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: a.color.withValues(alpha: 0.10), shape: BoxShape.circle),
                child: Icon(a.icon, color: a.color, size: 22),
              ),
              const SizedBox(height: 16),
              Text(a.title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: kInk)),
              const SizedBox(height: 4),
              Text(a.sub, style: const TextStyle(fontSize: 12.5, color: kMuted, height: 1.35)),
              const SizedBox(height: 14),
              const Spacer(),
              if (a.count != null)
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(a.count!, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: a.color)),
                  const SizedBox(width: 6),
                  Flexible(child: Text(a.countLabel ?? '', style: const TextStyle(fontSize: 12.5, color: kMuted))),
                ])
              else
                Row(children: [
                  Flexible(child: Text(a.linkLabel ?? '', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: a.color))),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 14, color: a.color),
                ]),
            ]),
          ),
        ),
      );

  void _o(String t, Widget p) => widget.onOpen(t, p);

  /// Cards are shown only for what the signed-in role may open (the server enforces the same rules).
  List<_Action> _actions(Map s) => [
        _Action(Icons.fact_check_rounded, kOrange, 'Validation Queue', 'Review and verify applicant documents',
            () => _o('Validation Queue', const ValidationQueuePage()),
            count: '${s['pending_review'] ?? 0}', countLabel: 'Pending'),
        if (Api.i.canPayments)
          _Action(Icons.account_balance_wallet_rounded, kBlue, 'Payment Management', 'Verify offline payments',
              () => _o('Payment Management', const PaymentManagementPage()),
              count: '${s['pending_payments'] ?? 0}', countLabel: 'Pending Verification'),
        _Action(Icons.home_work_rounded, kGreen, 'Unit Allotment', 'Manage units and allot flats to applicants',
            () => _o('Unit Allotment', const UnitAllotmentPage()),
            count: '${s['available_units'] ?? 0}', countLabel: 'Available Units'),
        _Action(Icons.description_rounded, kOrange, 'Agreement Receipts', 'Verify signed agreement receipts (Stage 6)',
            () => _o('Agreement Receipts', const AgreementReceiptsPage()),
            linkLabel: 'Review Agreements'),
        _Action(Icons.folder_copy_rounded, _teal, 'Bank Documents', 'Review bank documents for loan (Stage 7)',
            () => _o('Bank Documents', const BankDocumentsPage()),
            linkLabel: 'Review Documents'),
        _Action(Icons.account_balance_rounded, kBlue, 'Banking / Loans', 'Manage loan applications and approvals',
            () => _o('Banking / Loans', const BankingLoansPage()),
            linkLabel: 'Approve/Reject Loans'),
        _Action(Icons.people_alt_rounded, _purple, 'All Applications', 'View all forms and their current stages',
            () => _o('All Applications', const AllApplicationsPage()),
            count: '${s['total'] ?? 0}', countLabel: 'Total Forms'),
        if (Api.i.isSuper) ...[
          _Action(Icons.settings_rounded, kMuted, 'Document Settings', 'Configure document upload limits',
              () => _o('Document Settings', const DocumentSettingsPage()),
              linkLabel: 'Super Admin only'),
          _Action(Icons.manage_accounts_rounded, kRed, 'User Management', 'Manage admin users and roles',
              () => _o('User Management', const UserManagementPage()),
              linkLabel: 'Super Admin only'),
          _Action(Icons.table_chart_rounded, kNavy, 'Database Tables', 'View and manage all database tables',
              () => _o('Database Tables', const DatabaseTablesPage()),
              linkLabel: 'Super Admin only'),
        ],
      ];

  // ---------- system status ----------
  Widget _statusRow(String l, String v, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(child: Text(l, style: const TextStyle(fontSize: 13.5, color: kInk))),
          const SizedBox(width: 8),
          Text(v, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c)),
        ]),
      );

  Widget _systemStatus(Map s, bool narrow) {
    final by = (s['by_stage'] ?? {}) as Map;
    int inProg = 0;
    by.forEach((k, v) {
      if (k != 'stage_1_registered' && k != 'stage_10_completed') inProg += (v as num).toInt();
    });
    final health = Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('System Health', Icons.shield_outlined),
        const SizedBox(height: 10),
        FutureBuilder<Map<String, dynamic>>(
          future: _sys,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
            }
            if (snap.hasError) return _statusRow('Server', 'Unreachable', kRed);
            final st = (snap.data!['status'] ?? {}) as Map;
            Widget row(String label, String key, {String off = 'Not configured'}) {
              final m = (st[key] ?? {}) as Map;
              final ok = m['ok'] == true;
              return _statusRow(label, ok ? '${m['detail'] ?? 'OK'}' : (key == 'database' || key == 'storage' ? '${m['detail'] ?? 'Down'}' : off), ok ? kGreen : (key == 'database' || key == 'storage' ? kRed : kOrange));
            }

            return Column(children: [
              row('Database', 'database'),
              row('File storage', 'storage'),
              row('OTP email', 'email'),
              row('Push notifications', 'push'),
              row('Document OCR (Gemini)', 'ocr'),
            ]);
          },
        ),
      ]),
    );
    final stagesBox = Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Registration Stages', Icons.stacked_bar_chart_rounded),
        const SizedBox(height: 10),
        _statusRow('Stage 1 - Registration', '${by['stage_1_registered'] ?? 0}', kOrange),
        _statusRow('Stage 2-9 - In Progress', '$inProg', kBlue),
        _statusRow('Stage 10 - Completed', '${by['stage_10_completed'] ?? 0}', kGreen),
      ]),
    );
    return narrow
        ? Column(children: [health, const SizedBox(height: 16), stagesBox])
        : IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: health),
              const SizedBox(width: 16),
              Expanded(child: stagesBox),
            ]),
          );
  }

  /// No fixed height: each row sizes itself to its tallest card.
  Widget _grid(List<Widget> items, int cols) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += cols) {
      final chunk = items.sublist(i, math.min(i + cols, items.length));
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 16),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var j = 0; j < cols; j++) ...[
              if (j > 0) const SizedBox(width: 16),
              Expanded(child: j < chunk.length ? chunk[j] : const SizedBox.shrink()),
            ],
          ]),
        ),
      ));
    }
    return Column(children: rows);
  }

  Widget _h2(String t, IconData i) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 14),
        child: SectionTitle(t, i),
      );

  Widget _headBtns() => OutlinedButton.icon(
      onPressed: _refresh, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh'));

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_rounded, size: 44, color: kMuted),
              const SizedBox(height: 10),
              Text('${snap.error}', textAlign: TextAlign.center, style: const TextStyle(color: kRed)),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
            ]));
          }
          final s = (snap.data!['stats'] ?? {}) as Map;
          return LayoutBuilder(builder: (context, c) {
            final cols = ((c.maxWidth + 16) / (230 + 16)).floor().clamp(1, 4);
            return ListView(children: [
              Align(alignment: Alignment.centerRight, child: _headBtns()),
              const SizedBox(height: 16),
              _grid([
                _stat('Total Applicants', s['total'], Icons.people_alt_rounded, const [Color(0xFF3B7DDD), kBlue]),
                _stat('Pending Validation', s['pending_review'], Icons.hourglass_top_rounded, const [Color(0xFFFFA45C), kOrange]),
                _stat('Available Units', s['available_units'], Icons.home_work_rounded, const [Color(0xFF8B6CF0), _purple]),
                _stat('Completed', s['completed'], Icons.verified_rounded, const [Color(0xFF3CC47C), kGreen]),
              ], cols),
              _h2('Quick Actions', Icons.bolt_rounded),
              _grid([for (final a in _actions(s)) _actionCard(a)], cols),
              _h2('System Status', Icons.monitor_heart_outlined),
              _systemStatus(s, c.maxWidth < 760),
              const SizedBox(height: 8),
            ]);
          });
        },
      );
}