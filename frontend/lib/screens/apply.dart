import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../theme.dart';
import 'otp.dart';
import '../widgets.dart';

/// Krutarth Registration (website jaisa single-page form).
/// Submit par account bhi ban jaata hai (/auth/register).
class ApplyScreen extends StatefulWidget {
  const ApplyScreen({super.key});
  @override
  State<ApplyScreen> createState() => _ApplyScreenState();
}

class _ApplyScreenState extends State<ApplyScreen> {
  final _form = GlobalKey<FormState>();
  bool _busy = false, _hasCo = false, _hide = true;
  List<Map<String, dynamic>> _admins = [];

  final _c = <String, TextEditingController>{
    for (final k in [
      'firstName', 'lastName', 'fatherName', 'spouseName', 'dateOfBirth', 'occupation', 'fullAddress',
      'phone', 'email', 'aadharNumber', 'panNumber', 'password',
      'coApplicantName', 'coApplicantRelation', 'coApplicantDob', 'coApplicantAadhar', 'coApplicantPan', 'coApplicantPhone'
    ])
      k: TextEditingController()
  };
  String? _blood, _adminId;
  final _files = <String, String?>{
    'aadhar_front': null, 'aadhar_back': null, 'pan_front': null, 'passport_photo': null, 'membership_proof': null
  };

  @override
  void initState() {
    super.initState();
    context.read<AppState>().api.get('/public/admins').then((r) {
      if (mounted) setState(() => _admins = List<Map<String, dynamic>>.from(r['admins'] ?? []));
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  /// Reads the chosen Aadhaar / PAN image on the server (OCR) and pre-fills EMPTY form fields.
  /// Never overwrites what the user typed; silently does nothing if OCR is unavailable.
  Future<void> _autoFill(String key, String path) async {
    if (!const {'aadhar_front', 'aadhar_back', 'pan_front'}.contains(key)) return;
    final sm = ScaffoldMessenger.of(context);
    sm.hideCurrentSnackBar();
    sm.showSnackBar(const SnackBar(duration: Duration(minutes: 2), content: Text('Reading your document...')));
    try {
      final r = await context.read<AppState>().api.postMultipart('/ocr/extract', fields: {'type': key}, files: {'file': path});
      final f = Map<String, dynamic>.from(r['fields'] ?? {});
      var filled = 0;
      setState(() {
        f.forEach((k, v) {
          final c = _c[k];
          if (c != null && c.text.trim().isEmpty && '$v'.trim().isNotEmpty) {
            c.text = '$v';
            filled++;
          }
        });
      });
      sm.hideCurrentSnackBar();
      sm.showSnackBar(SnackBar(
          content: Text(filled > 0
              ? '$filled field(s) filled from your document. Please check them.'
              : 'Could not read details from this image. Please type them.')));
    } catch (_) {
      sm.hideCurrentSnackBar();
      sm.showSnackBar(const SnackBar(content: Text('Could not read this document automatically. Please type the details.')));
    }
  }

  // ---------- UI helpers ----------
  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Divider(height: 1),
        ]),
      );

  Widget _label(String t, {bool req = false, String? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Expanded(
              child: Text.rich(TextSpan(text: t, children: [
            if (req) const TextSpan(text: ' *', style: TextStyle(color: Colors.red)),
          ]), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
          if (trailing != null) Text(trailing, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      );

  InputDecoration _dec(String hint, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF6F8FB),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.black12)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.black12)),
      );

  /// Label upar + input neeche (website jaisa).
  Widget _field(String key, String label,
          {bool req = true,
          String hint = '',
          TextInputType? type,
          String? Function(String?)? validator,
          bool obscure = false,
          int maxLines = 1,
          int? maxLen,
          Widget? suffix,
          String? helper}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(label, req: req),
          TextFormField(
              controller: _c[key],
              keyboardType: type,
              obscureText: obscure,
              maxLines: obscure ? 1 : maxLines,
              maxLength: maxLen,
              decoration: _dec(hint, suffix: suffix).copyWith(counterText: ''),
              validator: validator ?? (req ? _req : null)),
          if (helper != null)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(helper, style: const TextStyle(fontSize: 12, color: Colors.black54))),
        ]),
      );

  Widget _dateField(String key, String label, {bool req = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(label, req: req),
          TextFormField(
            controller: _c[key],
            readOnly: true,
            decoration: _dec('yyyy-mm-dd', suffix: const Icon(Icons.calendar_today, size: 18)),
            validator: req ? _req : null,
            onTap: () async {
              final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime(1990),
                  firstDate: DateTime(1930),
                  lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)));
              if (d != null) _c[key]!.text = DateFormat('yyyy-MM-dd').format(d);
            },
          ),
        ]),
      );

  /// File picker row: label + Max size, "Choose File  No file chosen".
  Widget _upload(String key, String label, String max, {String? note, IconData? icon, Color? tint, Color? border}) {
    final path = _files[key];
    final box = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (note != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Icon(icon ?? Icons.photo_camera_outlined, size: 16, color: border ?? kBlue),
            const SizedBox(width: 6),
            Expanded(child: Text(note, style: const TextStyle(fontSize: 13, color: Colors.black87))),
          ]),
        ),
      _label(label, req: true, trailing: 'Max $max'),
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final p = await pickDoc();
          if (p != null) {
            setState(() => _files[key] = p);
            _autoFill(key, p);
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12)),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFFEFEFEF), borderRadius: BorderRadius.circular(6)),
              child: const Text('Choose File', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(path == null ? 'No file chosen' : path.split(RegExp(r'[\\/]')).last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: path == null ? Colors.black54 : Colors.green.shade700))),
            if (path != null) Icon(Icons.check_circle, size: 18, color: Colors.green.shade600),
          ]),
        ),
      ),
    ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: tint == null
          ? box
          : Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: tint, borderRadius: BorderRadius.circular(10), border: Border.all(color: (border ?? kBlue).withValues(alpha: 0.35))),
              child: box),
    );
  }

  Widget _blood_() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('Blood Group'),
          DropdownButtonFormField<String>(
              initialValue: _blood,
              decoration: _dec('Select'),
              items: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => _blood = v),
        ]),
      );

  Widget _adminBox() => Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFEEF3FB), borderRadius: BorderRadius.circular(10), border: Border.all(color: kBlue.withValues(alpha: 0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.badge_outlined, size: 18, color: kBlue),
            SizedBox(width: 8),
            Text.rich(TextSpan(text: 'Select Admin Helping You', children: [TextSpan(text: ' *', style: TextStyle(color: Colors.red))]),
                style: TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
              initialValue: _adminId,
              isExpanded: true,
              decoration: _dec('Select an admin').copyWith(fillColor: Colors.white),
              items: _admins.map((a) => DropdownMenuItem(value: a['id'] as String, child: Text(a['name'] as String))).toList(),
              validator: (v) => _admins.isEmpty || v != null ? null : 'Please select an admin',
              onChanged: (v) => setState(() => _adminId = v)),
          const SizedBox(height: 6),
          const Text('Select the admin who is assisting you with registration', style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      );

  // ---------- submit ----------
  Future<void> _submit() async {
    if (!_form.currentState!.validate()) {
      toast(context, 'Please fill all required fields', error: true);
      return;
    }
    if (_files.values.any((v) => v == null)) {
      toast(context, 'Please upload all 5 documents', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final fields = <String, String>{
        for (final e in _c.entries) e.key: e.value.text.trim(),
        'panNumber': _c['panNumber']!.text.trim().toUpperCase(),
        'bloodGroup': _blood ?? '',
        'handlingAdminId': _adminId ?? '',
        'hasCoApplicant': _hasCo.toString(),
      };
      await context.read<AppState>().registerWith(fields, {for (final e in _files.entries) e.key: e.value!});
      if (mounted) {
        // registration done -> show "Verify Your Contact" screen
        final nav = Navigator.of(context);
        nav.popUntil((r) => r.isFirst);
        nav.push(MaterialPageRoute(builder: (_) => const OtpScreen()));
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(title: const Text('Krutarth Registration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))]),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 10),
              const Center(child: Icon(Icons.assignment_outlined, size: 44, color: kBlue)),
              const SizedBox(height: 6),
              const Center(child: Text('Krutarth Registration', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
              const Center(
                  child: Padding(
                      padding: EdgeInsets.only(top: 2, bottom: 14),
                      child: Text('Stage 1: Account Registration & Document Upload',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)))),
              if (_admins.isNotEmpty) _adminBox(),

              _section('Document Uploads'),
              const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Documents are validated using AI to ensure they match the expected format. This helps speed up verification.',
                      style: TextStyle(color: Colors.black54, fontSize: 13))),
              _upload('passport_photo', 'Passport Size Photo', '2MB',
                  note: 'Recent passport size photograph with white background', tint: const Color(0xFFEEF3FB), border: kBlue),
              _upload('membership_proof', 'Membership Proof', '5MB',
                  note: 'Dabbewala Association / Charmakar Samaj membership card or receipt',
                  icon: Icons.badge_outlined,
                  tint: const Color(0xFFFFF1E6),
                  border: kOrange),
              _upload('aadhar_front', 'Aadhar Card Front', '5MB'),
              _upload('aadhar_back', 'Aadhar Card Back', '5MB'),
              _upload('pan_front', 'PAN Card', '5MB'),

              _section('Personal Details'),
              _field('firstName', 'First Name'),
              _field('lastName', 'Last Name'),
              _field('fatherName', "Father's Name"),
              _field('spouseName', "Spouse's Name (if applicable)", req: false),
              _dateField('dateOfBirth', 'Date of Birth'),
              _field('occupation', 'Occupation', req: false, hint: 'e.g., Business, Service, etc.'),
              _blood_(),
              InkWell(
                onTap: () => setState(() => _hasCo = !_hasCo),
                child: Row(children: [
                  Checkbox(value: _hasCo, onChanged: (v) => setState(() => _hasCo = v ?? false)),
                  const Icon(Icons.person_add_alt, size: 20),
                  const SizedBox(width: 8),
                  const Text('Add Co-Applicant', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
              ),
              if (_hasCo) ...[
                const SizedBox(height: 8),
                _field('coApplicantName', 'Co-applicant Name'),
                _field('coApplicantRelation', 'Relation'),
                _dateField('coApplicantDob', 'Co-applicant Date of Birth'),
                _field('coApplicantAadhar', 'Co-applicant Aadhaar', type: TextInputType.number, maxLen: 12),
                _field('coApplicantPan', 'Co-applicant PAN', maxLen: 10),
                _field('coApplicantPhone', 'Co-applicant Phone', type: TextInputType.phone, maxLen: 10),
              ],

              _section('Contact Details'),
              _field('email', 'Email',
                  type: TextInputType.emailAddress,
                  validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v ?? '') ? null : 'Enter valid email'),
              _field('phone', 'Mobile Number',
                  hint: '10 digit number',
                  type: TextInputType.phone,
                  maxLen: 10,
                  validator: (v) => RegExp(r'^\d{10}$').hasMatch(v ?? '') ? null : 'Enter 10 digit number'),
              _field('fullAddress', 'Full Address', hint: 'Enter your complete residential address', maxLines: 4),

              _section('Identity Documents'),
              _field('aadharNumber', 'Aadhar Number',
                  hint: '12 digit number',
                  type: TextInputType.number,
                  maxLen: 12,
                  validator: (v) => RegExp(r'^\d{12}$').hasMatch(v ?? '') ? null : 'Enter 12 digit Aadhaar'),
              _field('panNumber', 'PAN Number',
                  hint: 'ABCDE1234F',
                  maxLen: 10,
                  validator: (v) => RegExp(r'^[A-Za-z]{5}[0-9]{4}[A-Za-z]$').hasMatch(v ?? '') ? null : 'Invalid PAN (ABCDE1234F)'),

              _section('Account Security'),
              _field('password', 'Password',
                  obscure: _hide,
                  helper: 'Minimum 8 characters',
                  suffix: IconButton(
                      icon: Icon(_hide ? Icons.visibility : Icons.visibility_off, size: 20),
                      onPressed: () => setState(() => _hide = !_hide)),
                  validator: (v) => (v ?? '').length >= 8 ? null : 'Minimum 8 characters'),

              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: kBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Submit Registration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 14),
              const Center(
                  child: Text('By submitting, you agree to the terms and conditions of the PMAY scheme',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54))),
            ]),
          ),
        ),
      ),
    );
  }
}