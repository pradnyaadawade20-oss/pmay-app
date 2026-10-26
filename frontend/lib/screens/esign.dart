import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import '../api.dart' show Api;
import '../pdf_docs.dart';

/// Screen 1: user draws the signature. Pops with PNG bytes.
class SignaturePadPage extends StatefulWidget {
  const SignaturePadPage({super.key});
  @override
  State<SignaturePadPage> createState() => _SignaturePadPageState();
}

class _SignaturePadPageState extends State<SignaturePadPage> {
  final _c = SignatureController(penStrokeWidth: 3, penColor: Colors.black, exportBackgroundColor: Colors.transparent);
  bool _agree = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    if (_c.isEmpty) return;
    final bytes = await _c.toPngBytes();
    if (bytes != null && mounted) Navigator.pop(context, bytes);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sign here')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.grey), color: Colors.white),
              child: Signature(controller: _c, height: 240, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _c.clear, child: const Text('Clear'))),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _agree,
              onChanged: (v) => setState(() => _agree = v ?? false),
              title: const Text('I have read the document and agree to sign it electronically.'),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _agree ? _done : null, child: const Text('Apply signature')),
            ),
          ]),
        ),
      );
}

/// Full e-sign flow for one document.
/// [docKind]   : allotment | agreement | bank-loan | mortgage   (for /me/documents/{kind})
/// [uploadType]: agreement_signed | bank_loan_receipt | mortgage_receipt (for /me/upload)
/// Returns true if the signed PDF was uploaded (caller should refresh AppState).
Future<bool> eSignAndUpload(BuildContext context, Api api, {required String docKind, required String uploadType}) async {
  final sig = await Navigator.push<Uint8List>(context, MaterialPageRoute(builder: (_) => const SignaturePadPage()));
  if (sig == null) return false;

  final data = await api.get('/me/documents/$docKind');
  final built = await buildDocumentPdf(Map<String, dynamic>.from(data), signature: sig);

  final f = File('${Directory.systemTemp.path}/${docKind}_signed_${DateTime.now().millisecondsSinceEpoch}.pdf');
  await f.writeAsBytes(built.bytes);
  try {
    await api.postMultipart('/me/upload', fields: {'type': uploadType}, files: {'file': f.path});
  } finally {
    if (await f.exists()) await f.delete();
  }
  return true;
}