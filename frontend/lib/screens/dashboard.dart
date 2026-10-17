import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../api.dart' show kMock;
import '../pdf_docs.dart';
import '../state.dart';
import '../widgets.dart';
import '../theme.dart';
import 'apply.dart';
import 'bank_docs.dart';
import 'login.dart';
import 'otp.dart';
import 'payment.dart';

/// Full page version (AppBar + tracking body) – used where it is pushed as a route.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('My Application'), actions: [
        IconButton(icon: const Icon(Icons.logout), onPressed: () { s.logout(); Navigator.of(context).popUntil((r) => r.isFirst); }),
      ]),
      body: const TrackingScreen(),
    );
  }
}

/// Tracking tab body: welcome, vertical registration progress, current action, details.
class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});
  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  bool _busy = false;

  Future<void> _upload(String type) async {
    final s = context.read<AppState>();
    final f = await pickDoc();
    if (f == null) return;
    setState(() => _busy = true);
    try {
      await s.api.postMultipart('/me/upload', fields: {'type': type}, files: {'file': f});
      await s.refresh();
      if (mounted) toast(context, 'Uploaded successfully');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doc(String kind) async {
    try {
      final d = await context.read<AppState>().api.get('/me/documents/$kind');
      await shareDocument(d);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  // ---------- payment info boxes ----------
  String _money(dynamic v, num fallback) {
    final n = num.tryParse('${v ?? ''}') ?? fallback;
    return '\u20b9${NumberFormat.decimalPattern('en_IN').format(n)}';
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: v),
            ]),
            style: const TextStyle(color: Colors.black87, height: 1.4)),
      );

  Widget _costBox(AppState s, {required bool pending}) {
    final p = s.project ?? {};
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (pending) ...[
          const Text(
              'Please visit our office or contact our team to complete your payment. Our admin will process your payment and update your status.',
              style: TextStyle(color: Colors.black54, height: 1.4)),
          const SizedBox(height: 8),
        ],
        _kv('Total Property Cost', _money(p['total_cost'], 2550000)),
        const SizedBox(height: 4),
        _kv('Minimum Booking Amount', _money(p['booking_amount'], 25000)),
      ]),
    );
  }

  Widget _bankBox(AppState s) {
    final p = s.project ?? {};
    String v(dynamic x, String d) => (x == null || '$x'.isEmpty) ? d : '$x';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFE8F0FB), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Bank Details for Payment', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        _kv('Bank', v(p['bank_name'], 'Yes Bank Ltd')),
        _kv('Branch', v(p['bank_branch'], 'Kalyan Branch')),
        _kv('Account Name', v(p['bank_account_name'], 'Priyanka Home Realtors Pvt Ltd')),
        _kv('Account No', v(p['bank_account_no'], '[Contact Admin]')),
        _kv('IFSC', v(p['bank_ifsc'], '[Contact Admin]')),
      ]),
    );
  }

  Widget _stageCard(AppState s) {
    final a = s.applicant!;
    switch (s.stage) {
      case 'stage_1_registered':
        if (a['stage_2_status'] == 'rejected') {
          return InfoCard(icon: Icons.cancel, color: Colors.red, title: 'Application rejected', message: '${a['stage_2_reason'] ?? 'Please contact support.'}');
        }
        final unverified = a['email_verified'] != true && a['phone_verified'] != true;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const InfoCard(icon: Icons.schedule, color: Colors.amber, title: 'Awaiting Validation',
              message: 'Your documents are being reviewed by our team.', children: [
            Text('Please wait while we verify your Aadhar and PAN documents. This usually takes 1-2 business days. '
                'You will be notified once your documents are verified.',
                style: TextStyle(color: Colors.black54, height: 1.4)),
          ]),
          if (unverified) ...[
            const SizedBox(height: 12),
            InfoCard(icon: Icons.verified_user, color: Colors.orange, title: 'Verify your account',
                message: 'Verify your phone or email to continue.', children: [
              FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OtpScreen())), child: const Text('Verify now'))
            ]),
          ],
        ]);
      case 'stage_3_payment':
        final pending = s.payments.where((p) => p['payment_status'] == 'pending').isNotEmpty;
        if (pending) {
          return InfoCard(
              icon: Icons.schedule,
              color: Colors.amber,
              title: 'Awaiting Payment Processing',
              message: 'Your payment is being processed by our admin team.',
              children: [
                _costBox(s, pending: true),
                _bankBox(s),
                const Text('Once payment is confirmed by admin, you will be moved to the next stage automatically.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Colors.black54)),
              ]);
        }
        return InfoCard(
            icon: Icons.payment,
            color: Colors.blue,
            title: 'Booking Payment',
            message: 'Documents verified. Pay the booking amount to proceed.',
            children: [
              _costBox(s, pending: false),
              FilledButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentScreen())),
                  child: const Text('Proceed to payment')),
            ]);
      case 'stage_4_allotment':
        return const InfoCard(icon: Icons.home_work, color: Colors.orange, title: 'Awaiting house allotment', message: 'Payment received. A unit will be allotted to you soon.');
      case 'stage_5_agreement':
        return InfoCard(icon: Icons.description, color: Colors.blue, title: 'Sign the agreement',
            message: a['stage_4_status'] == 'rejected' ? 'Rejected: ${a['stage_4_reason'] ?? ''}. Please upload again.' : 'Download, print, sign and upload the agreement.',
            children: [
              OutlinedButton.icon(onPressed: () => _doc('allotment'), icon: const Icon(Icons.download), label: const Text('Allotment letter')),
              OutlinedButton.icon(onPressed: () => _doc('agreement'), icon: const Icon(Icons.download), label: const Text('Agreement for sale')),
              FilledButton.icon(onPressed: _busy ? null : () => _upload('agreement_signed'), icon: const Icon(Icons.upload_file), label: const Text('Upload signed agreement')),
            ]);
      case 'stage_6_agreement_receipt':
        return const InfoCard(icon: Icons.hourglass_top, color: Colors.orange, title: 'Agreement under review', message: 'Admin is verifying your signed agreement.');
      case 'stage_7_bank_document':
        return const InfoCard(icon: Icons.account_balance, color: Colors.blue, title: 'Bank documents',
            message: 'Upload all documents required for your home loan.', children: [BankDocsCard()]);
      case 'stage_8_bank_loan':
        return InfoCard(icon: Icons.account_balance, color: Colors.blue, title: 'Bank loan form',
            message: 'Download the form, submit it at your bank and upload the receipt.', children: [
          OutlinedButton.icon(onPressed: () => _doc('bank-loan'), icon: const Icon(Icons.download), label: const Text('Download loan form')),
          FilledButton.icon(onPressed: _busy ? null : () => _upload('bank_loan_receipt'), icon: const Icon(Icons.upload_file), label: const Text('Upload loan receipt')),
        ]);
      case 'stage_9_mortgage':
        return InfoCard(icon: Icons.gavel, color: Colors.blue, title: 'Mortgage deed',
            message: 'Download, sign and upload the mortgage deed receipt.', children: [
          OutlinedButton.icon(onPressed: () => _doc('mortgage'), icon: const Icon(Icons.download), label: const Text('Download mortgage deed')),
          FilledButton.icon(onPressed: _busy ? null : () => _upload('mortgage_receipt'), icon: const Icon(Icons.upload_file), label: const Text('Upload mortgage receipt')),
        ]);
      case 'stage_10_completed':
        return InfoCard(icon: Icons.celebration, color: Colors.green, title: 'Registration complete!',
            message: 'Congratulations. Your flat: ${s.unit?['unit_number'] ?? '-'}', children: [
          OutlinedButton(onPressed: () => _doc('agreement'), child: const Text('Download agreement')),
        ]);
      default:
        return const SizedBox();
    }
  }

  // ---------- vertical progress ----------
  static const _steps = [
    ('Registration', 'Account & Documents'),
    ('Validation', 'Document Verification'),
    ('Payment', 'Booking Payment'),
    ('Allotment', 'House Allotment'),
    ('Agreement', 'Agreement Registration'),
    ('Agreement Receipt', 'Upload Signed Agreement'),
    ('Bank Documents', 'Upload Bank Docs'),
    ('Bank Loan', 'Loan Processing'),
    ('Mortgage', 'Mortgage Deed'),
    ('Completed', 'Registration Complete'),
  ];

  Widget _dot(bool done, bool current) {
    if (done) {
      return const CircleAvatar(radius: 16, backgroundColor: Colors.green, child: Icon(Icons.check, size: 18, color: Colors.white));
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: current ? kBlue.withValues(alpha: 0.08) : Colors.white,
        border: Border.all(color: current ? kBlue : Colors.black26, width: 2),
      ),
      child: current ? const Icon(Icons.schedule, size: 18, color: kBlue) : null,
    );
  }

  Widget _progress(AppState s) {
    final cur = s.stage == 'stage_10_completed' ? _steps.length + 1 : stageNumber(s.stage);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Registration Progress', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),
          for (var i = 0; i < _steps.length; i++)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 32,
                  child: Column(children: [
                    _dot(cur > i + 1, cur == i + 1),
                    if (i < _steps.length - 1)
                      Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: cur > i + 1 ? Colors.green : Colors.black12)),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 4, bottom: i < _steps.length - 1 ? 18 : 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_steps[i].$1,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: cur == i + 1 ? FontWeight.bold : FontWeight.w600,
                              color: cur == i + 1 ? kBlue : (cur > i + 1 ? Colors.black87 : Colors.black54))),
                      const SizedBox(height: 2),
                      Text(_steps[i].$2, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
                    ]),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _details(Map<String, dynamic> a) {
    Widget row(String k, String? v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(v == null || v.isEmpty ? '-' : v, textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w600, color: color))),
        ]));
    Widget verified(String k, dynamic ok) =>
        row(k, ok == true ? 'Verified' : 'Pending', color: ok == true ? Colors.green.shade700 : Colors.orange.shade700);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          row('Application ID', a['unique_id']?.toString()),
          const Divider(height: 1),
          row('Name', _name(a)),
          const Divider(height: 1),
          row('Email', a['email']?.toString()),
          const Divider(height: 1),
          row('Phone', a['phone']?.toString()),
          const Divider(height: 1),
          verified('Email Verified', a['email_verified']),
          const Divider(height: 1),
          verified('Phone Verified', a['phone_verified']),
        ]),
      ),
    );
  }

  String _name(Map<String, dynamic> a) =>
      '${a['first_name'] ?? ''} ${a['last_name'] ?? ''}'.trim();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final a = s.applicant;
    if (!s.loggedIn) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        InfoCard(icon: Icons.route, color: kBlue, title: 'Track your application',
            message: 'Login or register to see your registration progress here.', children: [
          FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApplyScreen())), child: const Text('Apply Now')),
          OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())), child: const Text('Login')),
        ]),
      ]);
    }
    if (a == null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(s.roles.isNotEmpty
          ? 'This is an admin account. Please use the admin panel.' : 'No application found.')));
    }
    return RefreshIndicator(
      onRefresh: s.refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Welcome, ${_name(a)}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Track your registration progress and complete pending actions below.', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 16),
        _stageCard(s), // current status / action first
        const SizedBox(height: 12),
        _progress(s),
        const SizedBox(height: 12),
        _details(a),
        if (kMock) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              await s.api.postJson('/mock/advance', {});
              await s.refresh();
            },
            icon: const Icon(Icons.skip_next),
            label: const Text('Demo: next stage'),
          ),
        ],
        const SizedBox(height: 8),
      ]),
    );
  }
}

int stageNumber(String st) => int.tryParse(st.split('_')[1]) ?? 1;