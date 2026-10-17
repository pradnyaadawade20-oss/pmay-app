import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

// ---------- shared helpers ----------

const _stageLabels = [
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

Widget _section(String title, List<Widget> children) => Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kBlue)),
          const SizedBox(height: 6),
          ...children,
        ]),
      ),
    );

// =====================================================================
// Personal Details
// =====================================================================
class PersonalDetailsScreen extends StatelessWidget {
  const PersonalDetailsScreen({super.key});

  static String _v(dynamic x) => (x == null || '$x'.trim().isEmpty) ? '-' : '$x'.trim();
  static String _date(dynamic x) {
    final t = _v(x);
    return t.length >= 10 && t != '-' ? t.substring(0, 10) : t;
  }

  static String _maskAadhar(dynamic x) {
    final d = _v(x).replaceAll(RegExp(r'\D'), '');
    return d.length < 4 ? '-' : 'XXXX XXXX ${d.substring(d.length - 4)}';
  }

  static String _maskPan(dynamic x) {
    final p = _v(x);
    return p.length != 10 ? p : 'XXXXX${p.substring(5)}';
  }

  Widget _row(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(v, textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w600, color: color))),
        ]),
      );

  Widget _verified(String k, dynamic ok) =>
      _row(k, ok == true ? 'Verified' : 'Pending', color: ok == true ? Colors.green.shade700 : Colors.orange.shade700);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final a = s.applicant;
    return Scaffold(
      appBar: AppBar(title: const Text('Personal Details')),
      body: a == null
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No profile found.')))
          : RefreshIndicator(
              onRefresh: s.refresh,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                _section('Application', [
                  _row('Application ID', _v(a['unique_id'])),
                  const Divider(height: 1),
                  _row('Current Stage', () {
                    final n = int.tryParse('${a['registration_stage']}'.split('_')[1]) ?? 1;
                    return _stageLabels[(n - 1).clamp(0, _stageLabels.length - 1)].$1;
                  }()),
                ]),
                _section('Personal Information', [
                  _row('Name', '${_v(a['first_name'])} ${_v(a['last_name'])}'.replaceAll('- -', '-')),
                  const Divider(height: 1),
                  _row("Father's Name", _v(a['father_name'])),
                  const Divider(height: 1),
                  _row("Spouse's Name", _v(a['spouse_name'])),
                  const Divider(height: 1),
                  _row('Date of Birth', _date(a['date_of_birth'])),
                  const Divider(height: 1),
                  _row('Age', _v(a['age'])),
                  const Divider(height: 1),
                  _row('Occupation', _v(a['occupation'])),
                  const Divider(height: 1),
                  _row('Blood Group', _v(a['blood_group'])),
                  const Divider(height: 1),
                  _row('Address', _v(a['full_address'])),
                ]),
                _section('Contact', [
                  _row('Email', _v(a['email'])),
                  const Divider(height: 1),
                  _verified('Email Status', a['email_verified']),
                  const Divider(height: 1),
                  _row('Phone', _v(a['phone'])),
                  const Divider(height: 1),
                  _verified('Phone Status', a['phone_verified']),
                ]),
                _section('Identity Documents', [
                  _row('Aadhar No.', _maskAadhar(a['aadhar_number'])),
                  const Divider(height: 1),
                  _row('PAN No.', _maskPan(a['pan_number'])),
                ]),
                if (a['has_co_applicant'] == true)
                  _section('Co-Applicant', [
                    _row('Name', _v(a['co_applicant_name'])),
                    const Divider(height: 1),
                    _row('Relation', _v(a['co_applicant_relation'])),
                    const Divider(height: 1),
                    _row('Date of Birth', _date(a['co_applicant_dob'])),
                    const Divider(height: 1),
                    _row('Phone', _v(a['co_applicant_phone'])),
                    const Divider(height: 1),
                    _row('Aadhar No.', _maskAadhar(a['co_applicant_aadhar'])),
                    const Divider(height: 1),
                    _row('PAN No.', _maskPan(a['co_applicant_pan'])),
                  ]),
              ]),
            ),
    );
  }
}

// =====================================================================
// Language
// =====================================================================
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tile(String name, String native, {required bool selected}) => ListTile(
          leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? kBlue : Colors.black38),
          title: Text(name, style: TextStyle(fontWeight: FontWeight.w600, color: selected ? null : Colors.black45)),
          subtitle: Text(native),
          trailing: selected
              ? const Icon(Icons.check_circle, color: kBlue)
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(12)),
                  child: const Text('Coming soon', style: TextStyle(fontSize: 11.5, color: Colors.black54)),
                ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Language')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('App language', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Krutarth - PMAY is currently available in English. More languages will be added soon.',
            style: TextStyle(color: Colors.black54, height: 1.4)),
        const SizedBox(height: 14),
        Card(
          child: Column(children: [
            tile('English', 'English', selected: true),
            const Divider(height: 1),
            tile('Hindi', 'हिन्दी', selected: false),
            const Divider(height: 1),
            tile('Marathi', 'मराठी', selected: false),
          ]),
        ),
      ]),
    );
  }
}

// =====================================================================
// Help & Support
// =====================================================================
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const _faqs = [
    ('How do I register?',
        'Tap "Apply for PMAY / Sign Up", fill in your personal details, upload the 5 required documents '
            '(Aadhar front and back, PAN, passport photo and membership proof) and submit. After that, verify '
            'your email or phone number with an OTP.'),
    ('How long does validation take?',
        'Our team verifies your Aadhar and PAN documents, which usually takes 1-2 business days. '
            'You will get a notification as soon as your application is accepted.'),
    ('I did not receive my OTP. What should I do?',
        'Check that the email or phone number on your profile is correct and look in your spam folder. '
            'Then go to Tracking, tap "Verify now" and request a new OTP.'),
    ('How do I pay the booking amount?',
        'Once your documents are accepted, open Tracking and go to the Payment step. You can pay online, or pay '
            'through the bank and upload the payment receipt. Offline payments are confirmed by our admin team.'),
    ('Why can I not see the next step?',
        'Each step opens only after the previous one is approved by our team. Pull down on the Tracking screen '
            'to refresh, and check your notifications for updates.'),
    ('How do I get my agreement?',
        'When your application reaches the Agreement step, download the agreement from the Tracking screen, '
            'print it, sign it and upload the signed copy.'),
  ];

  void _copy(BuildContext c, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    toast(c, '$label copied');
  }

  @override
  Widget build(BuildContext context) {
    Widget contact(IconData icon, String label, String value) => ListTile(
          leading: Icon(icon, color: kBlue),
          title: Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          subtitle: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
          trailing: const Icon(Icons.copy, size: 20),
          onTap: () => _copy(context, label, value),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Contact us', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Card(
          child: Column(children: [
            contact(Icons.phone_outlined, 'Phone', supportPhone),
            const Divider(height: 1),
            contact(Icons.mail_outline, 'Email', supportEmail),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Text('Tap a contact to copy it.', style: TextStyle(fontSize: 12, color: Colors.black54)),
        ),
        const SizedBox(height: 20),
        const Text('Frequently asked questions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < _faqs.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  title: Text(_faqs[i].$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  children: [Text(_faqs[i].$2, style: const TextStyle(color: Colors.black54, height: 1.45))],
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

// =====================================================================
// About App
// =====================================================================
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _features = [
    (Icons.how_to_reg_outlined, 'Easy registration', 'Apply and upload your documents from your phone.'),
    (Icons.route_outlined, 'Live tracking', 'See exactly which step your application is at.'),
    (Icons.payments_outlined, 'Booking payment', 'Pay online, or upload an offline payment receipt.'),
    (Icons.notifications_none, 'Instant updates', 'Get notified when your application moves ahead.'),
    (Icons.picture_as_pdf_outlined, 'Printable documents', 'Download your application documents as PDF.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About App')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(22)),
            child: const Icon(Icons.home_work_rounded, color: Colors.white, size: 44),
          ),
        ),
        const SizedBox(height: 14),
        const Center(child: Text('Krutarth - PMAY', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
        const SizedBox(height: 2),
        const Center(child: Text('Pradhan Mantri Awas Yojana - Urban', style: TextStyle(color: Colors.black54))),
        const SizedBox(height: 6),
        const Center(child: Text('Version 1.0.0', style: TextStyle(fontSize: 12.5, color: Colors.black45))),
        const SizedBox(height: 20),
        _section('About', [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Krutarth - PMAY helps applicants register for PMAY housing projects, submit their documents, '
              'pay the booking amount and track every step of their application, all in one place.',
              style: TextStyle(color: Colors.black54, height: 1.45),
            ),
          ),
        ]),
        _section('Key features', [
          for (final f in _features)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(f.$1, color: kBlue),
              title: Text(f.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(f.$3),
            ),
        ]),
        _section('Registration steps', [
          for (var i = 0; i < _stageLabels.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: CircleAvatar(
                radius: 13,
                backgroundColor: kBlue.withValues(alpha: 0.12),
                child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: kBlue, fontWeight: FontWeight.bold)),
              ),
              title: Text(_stageLabels[i].$1, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_stageLabels[i].$2),
            ),
        ]),
      ]),
    );
  }
}