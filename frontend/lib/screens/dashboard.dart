import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../api.dart' show kMock;
import '../doc_actions.dart';
import '../pdf_docs.dart';
import '../state.dart';
import '../widgets.dart';
import '../theme.dart';
import 'apply.dart';
import 'esign.dart';
import 'bank_docs.dart';
import 'login.dart';
import 'otp.dart';
import 'notifications.dart';
import 'profile_pages.dart';

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
  /// Show the gradient "Tracking" header (used in the main tab; the pushed page has its own AppBar).
  final bool showHeader;
  const TrackingScreen({super.key, this.showHeader = false});
  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  bool _busy = false;

  /// [multi] lets the user select several files at once (used for the signed agreement:
  /// signed allotment letter + signed agreement, as images or PDFs).
  Future<void> _upload(String type, {bool multi = false}) async {
    final s = context.read<AppState>();
    final List<String> picked;
    if (multi) {
      picked = await pickDocs();
    } else {
      final f = await pickDoc();
      picked = f == null ? <String>[] : [f];
    }
    if (picked.isEmpty) return;
    if (picked.length > 10) {
      toast(context, 'You can upload at most 10 files at once', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await s.api.postMultipart('/me/upload', fields: {'type': type}, fileLists: {'file': picked});
      await s.refresh();
      if (mounted) toast(context, picked.length > 1 ? '${picked.length} documents uploaded successfully' : 'Uploaded successfully');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _docBusy = false;

  Future<({Uint8List bytes, String filename})> _buildPdf(String kind) async {
    final d = await context.read<AppState>().api.get('/me/documents/$kind');
    return buildDocumentPdf(d);
  }

  /// Download: saves the PDF to the phone's Downloads folder.
  Future<void> _eSign(String docKind, String uploadType) async {
    final s = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final ok = await eSignAndUpload(context, s.api, docKind: docKind, uploadType: uploadType);
      if (ok) {
        await s.refresh();
        if (mounted) toast(context, 'Document e-signed and submitted');
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> _doc(String kind) async {
    if (_docBusy) return;
    setState(() => _docBusy = true);
    try {
      final pdf = await _buildPdf(kind);
      final uri = await DocActions.download(pdf.bytes, pdf.filename);
      if (!mounted || uri == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Downloaded: ${pdf.filename}'),
          action: SnackBarAction(
              label: 'Open',
              onPressed: () => DocActions.open(uri).catchError((_) {
                    if (mounted) toast(context, 'No PDF viewer found. File is in your Downloads folder.', error: true);
                  })),
        ));
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _docBusy = false);
    }
  }

  /// Share: sends the PDF directly to WhatsApp.
  Future<void> _shareDoc(String kind, String label) async {
    if (_docBusy) return;
    setState(() => _docBusy = true);
    try {
      final pdf = await _buildPdf(kind);
      await DocActions.shareWhatsApp(pdf.bytes, pdf.filename, text: label);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _docBusy = false);
    }
  }

  /// [Download] [Share] pair for one document.
  Widget _docRow(String label, String kind) => Row(children: [
        Expanded(
            child: OutlinedButton.icon(
                onPressed: _docBusy ? null : () => _doc(kind),
                icon: const Icon(Icons.download),
                label: Text(label, overflow: TextOverflow.ellipsis))),
        const SizedBox(width: 10),
        OutlinedButton.icon(
            onPressed: _docBusy ? null : () => _shareDoc(kind, label),
            icon: const Icon(Icons.share),
            label: const Text('Share')),
      ]);

  Widget _stageCard(AppState s) {
    final a = s.applicant!;
    switch (s.stage) {
      case 'stage_1_registered':
        if (a['stage_2_status'] == 'rejected') {
          return _StatusCard(icon: Icons.cancel, color: Colors.red, title: 'Application rejected', badge: 'Rejected', message: '${a['stage_2_reason'] ?? 'Please contact support.'}');
        }
        final unverified = a['email_verified'] != true && a['phone_verified'] != true;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _StatusCard(icon: Icons.schedule, color: Colors.amber, title: 'Awaiting Validation',
              message: 'Your documents are being reviewed by our team.', children: [
            Text('Please wait while we verify your Aadhar and PAN documents. This usually takes 1-2 business days. '
                'You will be notified once your documents are verified.',
                style: TextStyle(color: Colors.black54, height: 1.4)),
          ]),
          if (unverified) ...[
            const SizedBox(height: 12),
            _StatusCard(icon: Icons.verified_user, color: Colors.orange, title: 'Verify your account',
                message: 'Verify your phone or email to continue.', children: [
              FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OtpScreen())), child: const Text('Verify now'))
            ]),
          ],
        ]);
      case 'stage_3_payment':
        return const _StatusCard(icon: Icons.schedule, color: Colors.amber, title: 'Awaiting Payment');
      case 'stage_4_allotment':
        return const _StatusCard(icon: Icons.home_work, color: Colors.orange, title: 'Awaiting house allotment', message: 'Payment received. A unit will be allotted to you soon.');
      case 'stage_5_agreement':
        return _StatusCard(icon: Icons.description, color: Colors.blue, title: 'Sign the agreement',
            message: a['stage_4_status'] == 'rejected' ? 'Rejected: ${a['stage_4_reason'] ?? ''}. Please upload again.' : 'Download, print, sign and upload both the allotment letter and the agreement. Select all files together (images or PDF).',
            children: [
              _docRow('Allotment letter', 'allotment'),
              _docRow('Agreement for sale', 'agreement'),
              FilledButton.icon(onPressed: _busy ? null : () => _eSign('agreement', 'agreement_signed'), icon: const Icon(Icons.draw), label: const Text('E-sign agreement')),
              FilledButton.icon(onPressed: _busy ? null : () => _upload('agreement_signed', multi: true), icon: const Icon(Icons.upload_file), label: const Text('Upload signed agreement')),
            ]);
      case 'stage_6_agreement_receipt':
        return const _StatusCard(icon: Icons.hourglass_top, color: Colors.orange, title: 'Agreement under review', message: 'Admin is verifying your signed agreement.');
      case 'stage_7_bank_document':
        return const _StatusCard(icon: Icons.account_balance, color: Colors.blue, title: 'Bank documents',
            message: 'Upload all documents required for your home loan.', children: [BankDocsCard()]);
      case 'stage_8_bank_loan':
        return _StatusCard(icon: Icons.account_balance, color: Colors.blue, title: 'Bank loan form',
            message: 'Download the form, submit it at your bank and upload the receipt.', children: [
          OutlinedButton.icon(onPressed: () => _doc('bank-loan'), icon: const Icon(Icons.download), label: const Text('Download loan form')),
          FilledButton.icon(onPressed: _busy ? null : () => _eSign('bank-loan', 'bank_loan_receipt'), icon: const Icon(Icons.draw), label: const Text('E-sign loan form')),
          FilledButton.icon(onPressed: _busy ? null : () => _upload('bank_loan_receipt'), icon: const Icon(Icons.upload_file), label: const Text('Upload loan receipt')),
        ]);
      case 'stage_9_mortgage':
        return _StatusCard(icon: Icons.gavel, color: Colors.blue, title: 'Mortgage deed',
            message: 'Download, sign and upload the mortgage deed receipt.', children: [
          OutlinedButton.icon(onPressed: () => _doc('mortgage'), icon: const Icon(Icons.download), label: const Text('Download mortgage deed')),
          FilledButton.icon(onPressed: _busy ? null : () => _eSign('mortgage', 'mortgage_receipt'), icon: const Icon(Icons.draw), label: const Text('E-sign mortgage deed')),
          FilledButton.icon(onPressed: _busy ? null : () => _upload('mortgage_receipt'), icon: const Icon(Icons.upload_file), label: const Text('Upload mortgage receipt')),
        ]);
      case 'stage_10_completed':
        return _StatusCard(icon: Icons.celebration, color: Colors.green, title: 'Registration complete!', badge: 'Completed',
            message: 'Congratulations. Your flat: ${s.unit?['unit_number'] ?? '-'}', children: [
          OutlinedButton(onPressed: () => _doc('agreement'), child: const Text('Download agreement')),
        ]);
      default:
        return const SizedBox();
    }
  }

  // ---------- progress (9 steps) ----------
  static const _steps = [
    ('Registration', 'Account & Documents', Icons.person_outline),
    ('Validation', 'Document Verification', Icons.fact_check_outlined),
    ('Payment', 'Booking Payment', Icons.payments_outlined),
    ('Allotment', 'House Allotment', Icons.home_work_outlined),
    ('Agreement', 'Agreement Registration', Icons.description_outlined),
    ('Agreement Receipt', 'Upload Signed Agreement', Icons.upload_outlined),
    ('Bank Documents', 'Bank Document Submission', Icons.account_balance_outlined),
    ('Possession', 'Final Possession', Icons.vpn_key_outlined),
    ('Closure', 'Application Closure', Icons.verified_user_outlined),
  ];
  static const _msgs = [
    ('Registration in progress', 'Complete your account and documents.'),
    ('We are validating your documents.', 'You will be notified once verified.'),
    ('Booking payment pending.', 'Complete the payment to continue.'),
    ('We are processing your allotment.', 'You will be notified once the unit is assigned.'),
    ('Your agreement is ready.', 'Download, sign and upload it.'),
    ('Your signed agreement is under review.', 'You will be notified after approval.'),
    ('Bank documents required.', 'Upload all documents for your home loan.'),
    ('Possession in progress.', 'Loan and mortgage formalities are being completed.'),
    ('Closing your application.', 'Almost done!'),
  ];
  static const _green = Color(0xFF2E9E4F);
  int? _open; // null = follow current step

  /// Current step number (1..9); 10 = everything done.
  int _cur(AppState s) {
    final n = stageNumber(s.stage);
    if (n >= 10) return 10;
    if (n >= 8) return 8;
    return n;
  }

  Widget _pill(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      );

  Widget _header(AppState s) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Container(
          padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 10, 28),
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0B2A7A), kBlue]),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Tracking', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text('Stay updated on your registration\njourney in real time.', style: TextStyle(color: Colors.white, fontSize: 15, height: 1.3)),
              ]),
            ),
            IconButton(
              icon: Badge(
                  smallSize: 11,
                  isLabelVisible: hasUnreadNotifications(s),
                  child: const Icon(Icons.notifications_none, color: Colors.white, size: 30)),
              onPressed: () => openNotifications(context),
            ),
          ]),
        ),
      );

  Widget _cardBox({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: child,
      );

  Widget _overall(int cur) {
    final done = (cur - 1).clamp(0, 9); // steps fully completed
    final pct = cur > 9 ? 100 : (cur / 9 * 100).floor();
    final start = (cur - 4).clamp(0, 2); // 7-dot window like the design
    final dots = <Widget>[];
    for (var k = start; k < start + 7; k++) {
      final n = k + 1;
      final isDone = cur > n, isCur = cur == n;
      if (dots.isNotEmpty) dots.add(Expanded(child: Container(height: 2, color: cur > n - 1 ? _green : Colors.black12)));
      dots.add(isDone
          ? const CircleAvatar(radius: 13, backgroundColor: _green, child: Icon(Icons.check, size: 16, color: Colors.white))
          : Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: isCur ? kBlue : Colors.black26, width: 2)),
              child: isCur ? const Center(child: CircleAvatar(radius: 5, backgroundColor: kBlue)) : null));
    }
    final shown = cur > 9 ? 9 : cur;
    return _cardBox(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Overall Progress', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Row(children: dots),
            const SizedBox(height: 10),
            Text.rich(TextSpan(children: [
              TextSpan(text: '${cur > 9 ? 9 : shown} of 9 steps', style: const TextStyle(color: kBlue, fontWeight: FontWeight.w600)),
              const TextSpan(text: ' completed', style: TextStyle(color: Colors.black54)),
            ]), style: const TextStyle(fontSize: 13)),
          ]),
        ),
        const SizedBox(width: 14),
        SizedBox(
          width: 68,
          height: 68,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(width: 68, height: 68, child: CircularProgressIndicator(value: pct / 100, strokeWidth: 5, backgroundColor: Colors.black12, color: kBlue)),
            Text('$pct%', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kBlue)),
          ]),
        ),
      ]),
    );
  }

  Widget _stepDot(int n, int cur) {
    if (cur > n) {
      return const CircleAvatar(radius: 19, backgroundColor: _green, child: Icon(Icons.check, size: 22, color: Colors.white));
    }
    final isCur = cur == n;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: isCur ? kBlue : Colors.black26, width: 2)),
      child: Icon(isCur ? Icons.schedule : _steps[n - 1].$3, size: 20, color: isCur ? kBlue : Colors.black45),
    );
  }

  Widget _stepsList(int cur) {
    final open = _open ?? (cur > 9 ? 0 : cur);
    return _cardBox(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(children: [
        for (var i = 0; i < _steps.length; i++)
          Builder(builder: (_) {
            final n = i + 1;
            final isDone = cur > n, isCur = cur == n;
            final expanded = open == n;
            final titleColor = isCur ? kBlue : Colors.black87;
            return Column(children: [
              InkWell(
                onTap: () => setState(() => _open = expanded ? 0 : n),
                child: IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(
                      width: 38,
                      child: Column(children: [
                        const SizedBox(height: 10),
                        _stepDot(n, cur),
                        if (i < _steps.length - 1 || expanded)
                          Expanded(child: Container(width: 2, margin: const EdgeInsets.only(top: 2), color: isDone ? _green : (isCur ? kBlue.withValues(alpha: 0.4) : Colors.black12))),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('$n. ${_steps[i].$1}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: titleColor)),
                                const SizedBox(height: 2),
                                Text(_steps[i].$2, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                              ]),
                            ),
                            isDone
                                ? _pill('Completed', _green, const Color(0xFFE6F4EA))
                                : isCur
                                    ? _pill('In Progress', kBlue, const Color(0xFFE8EEFB))
                                    : _pill('Pending', Colors.black54, const Color(0xFFEFEFF2)),
                            const SizedBox(width: 6),
                            Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: expanded ? kBlue : Colors.black38),
                          ]),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(left: 33, bottom: 12),
                    decoration: BoxDecoration(
                        border: Border(left: BorderSide(width: 2, color: i == _steps.length - 1 ? Colors.transparent : (isDone ? _green : (isCur ? kBlue.withValues(alpha: 0.4) : Colors.black12))))),
                    child: isCur
                        ? _stageCard(context.read<AppState>())
                        : Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: const Color(0xFFEFF3FD), borderRadius: BorderRadius.circular(12)),
                            child: Row(children: [
                              Icon(_steps[i].$3, color: kBlue, size: 30),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(isDone ? '${_steps[i].$1} completed' : _msgs[i].$1,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: kBlue)),
                                  const SizedBox(height: 2),
                                  Text(isDone ? 'This step is done.' : _msgs[i].$2, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
                                ]),
                              ),
                            ]),
                          ),
                  ),
                ),
              if (i < _steps.length - 1) const Divider(height: 1, indent: 52),
            ]);
          }),
      ]),
    );
  }

  Widget _help() => _cardBox(
        child: Row(children: [
          const CircleAvatar(radius: 26, backgroundColor: Color(0xFFE8EEFB), child: Icon(Icons.headset_mic_outlined, color: kBlue, size: 28)),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Need help?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Our support team is here to assist you.', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
            ]),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 12)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpSupportScreen())),
            icon: const Icon(Icons.headset_mic_outlined, size: 18),
            label: const Text('Contact\nSupport', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.1)),
          ),
        ]),
      );

  String _name(Map<String, dynamic> a) =>
      '${a['first_name'] ?? ''} ${a['last_name'] ?? ''}'.trim();

  /// "Your Details" card: shown once the application is validated (stage 3 onwards).
  Widget _detailsCard(Map<String, dynamic> a) {
    Widget row(String k, String v, {Color? vc}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(k, style: const TextStyle(color: Colors.black54, fontSize: 14)),
            const SizedBox(width: 16),
            Flexible(child: Text(v, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: vc ?? Colors.black87))),
          ]),
        );
    Widget verified(bool ok) => Text(ok ? 'Verified' : 'Pending',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: ok ? Colors.green.shade700 : Colors.amber.shade800));
    Widget vrow(String k, bool ok) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(k, style: const TextStyle(color: Colors.black54, fontSize: 14)),
            verified(ok),
          ]),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your Details', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        row('Application ID', '${a['unique_id'] ?? '-'}'),
        row('Name', _name(a)),
        row('Email', '${a['email'] ?? '-'}'),
        row('Phone', '${a['phone'] ?? '-'}'),
        vrow('Email Verified', a['email_verified'] == true),
        vrow('Phone Verified', a['phone_verified'] == true),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final a = s.applicant;
    Widget content;
    if (!s.loggedIn) {
      content = Padding(
        padding: const EdgeInsets.all(16),
        child: InfoCard(icon: Icons.route, color: kBlue, title: 'Track your application',
            message: 'Login or register to see your registration progress here.', children: [
          FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApplyScreen())), child: const Text('Apply Now')),
          OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())), child: const Text('Login')),
        ]),
      );
    } else if (a == null) {
      content = Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(s.roles.isNotEmpty
          ? 'This is an admin account. Please use the admin panel.' : 'No application found.')));
    } else {
      content = Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text('Welcome, ${_name(a)}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            const SizedBox(width: 8),
            const Text('👋', style: TextStyle(fontSize: 22)),
          ]),
          const SizedBox(height: 4),
          const Text("Here's the latest status of your application.", style: TextStyle(color: Colors.black54, fontSize: 15)),
          const SizedBox(height: 16),
          if (stageNumber(s.stage) >= 3 && a['stage_2_status'] != 'rejected') ...[
            _detailsCard(a),
            const SizedBox(height: 16),
          ],
          _overall(_cur(s)),
          const SizedBox(height: 16),
          _stepsList(_cur(s)),
          const SizedBox(height: 16),
          _help(),
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
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: s.refresh,
      child: ListView(padding: EdgeInsets.zero, children: [
        if (widget.showHeader) _header(s),
        content,
      ]),
    );
  }
}

/// Status card at the top of Tracking: tinted background, round icon, status pill.
class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String title;
  final String? message;
  final String badge;
  final List<Widget> children;
  const _StatusCard(
      {required this.icon, required this.title, this.message, this.color, this.badge = 'In Progress', this.children = const []});

  @override
  Widget build(BuildContext context) {
    final c = color ?? kBlue;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.withValues(alpha: 0.10), Colors.white),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: 28, backgroundColor: c.withValues(alpha: 0.2), child: Icon(icon, color: c, size: 30)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              if (message != null) ...[const SizedBox(height: 6), Text(message!, style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.3))],
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
            child: Text(badge, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: HSLColor.fromColor(c).withLightness(0.35).toColor())),
          ),
        ]),
        ...children.map((w) => Padding(padding: const EdgeInsets.only(top: 12), child: w)),
      ]),
    );
  }
}

int stageNumber(String st) => int.tryParse(st.split('_')[1]) ?? 1;