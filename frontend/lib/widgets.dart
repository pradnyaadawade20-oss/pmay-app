import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'api.dart';

void toast(BuildContext c, String msg, {bool error = false}) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: error ? Colors.red.shade700 : null));
}

/// Picks a jpg/png/pdf and returns the local path (or null).
Future<String?> pickDoc() async {
  final r = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'], withData: kIsWeb);
  final f = r?.files.single;
  if (f == null) return null;
  if (kIsWeb) {
    // web: no path available, keep bytes in memory
    if (f.bytes == null) return null;
    return WebFiles.put(f.name, f.bytes!);
  }
  return f.path;
}

class UploadTile extends StatelessWidget {
  final String label;
  final String? path; // locally picked
  final bool uploaded; // already on server
  final VoidCallback onPick;
  const UploadTile(
      {super.key, required this.label, required this.onPick, this.path, this.uploaded = false});

  @override
  Widget build(BuildContext context) {
    final picked = path != null;
    return Card(
      child: ListTile(
        leading: Icon(
            picked || uploaded ? Icons.check_circle : Icons.upload_file,
            color: picked || uploaded ? Colors.green : null),
        title: Text(label),
        subtitle: Text(picked
            ? path!.split('/').last
            : uploaded
                ? 'Uploaded'
                : 'JPG / PNG / PDF'),
        trailing: TextButton(onPressed: onPick, child: Text(picked || uploaded ? 'Change' : 'Choose')),
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String title;
  final String? message;
  final List<Widget> children;
  const InfoCard(
      {super.key,
      required this.icon,
      required this.title,
      this.message,
      this.color,
      this.children = const []});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
            ]),
            if (message != null) ...[const SizedBox(height: 8), Text(message!)],
            ...children.map((w) => Padding(padding: const EdgeInsets.only(top: 12), child: w)),
          ]),
        ),
      );
}

/// Website ka "Registration Process" section (8 stages) – Home screen par sirf info.
class RegistrationProcess extends StatelessWidget {
  const RegistrationProcess({super.key});

  static const _steps = [
    (Icons.how_to_reg_rounded, 'Registration', 'Submit personal details & documents'),
    (Icons.verified_user_rounded, 'Verification', 'Aadhar & PAN verification'),
    (Icons.fact_check_rounded, 'Validation', 'Admin validates documents'),
    (Icons.payments_rounded, 'Payment', 'Online/Offline payment'),
    (Icons.home_work_rounded, 'Allotment', 'Unit allocation'),
    (Icons.draw_rounded, 'Agreement', 'Sign Agreement of Sale'),
    (Icons.account_balance_rounded, 'Bank Loan', 'Loan processing'),
    (Icons.key_rounded, 'Possession', 'Final handover'),
  ];
  // "Soft Blue + White" theme
  static const _accent = Color(0xFF2272D6);
  static const _border = Color(0xFFC8D9F2);
  static const _title = Color(0xFF1E2F4D);
  static const _subtitle = Color(0xFF5B6B82);

  Widget _card(int i) {
    final n = '${i + 1}';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 64,
              height: 4,
              decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 12),
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: _accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
              child: Icon(_steps[i].$1, color: _accent, size: 25),
            ),
            const SizedBox(width: 10),
            Text('STEP $n',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: _accent)),
          ]),
          const SizedBox(height: 14),
          Text(_steps[i].$2, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: _title)),
          const SizedBox(height: 4),
          Text(_steps[i].$3, style: const TextStyle(fontSize: 12.5, color: _subtitle, height: 1.35)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const Text('Registration Process',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1B1B1B))),
      const SizedBox(height: 8),
      Container(
          width: 52,
          height: 4,
          decoration: BoxDecoration(color: const Color(0xFFF57C20), borderRadius: BorderRadius.circular(4))),
      const SizedBox(height: 12),
      const Text('Simple 8-stage process from registration to possession',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: Colors.black54)),
      const SizedBox(height: 18),
      for (var r = 0; r < _steps.length; r += 2) ...[
        if (r > 0) const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _card(r)),
            const SizedBox(width: 12),
            Expanded(child: r + 1 < _steps.length ? _card(r + 1) : const SizedBox()),
          ]),
        ),
      ],
    ]);
  }
}