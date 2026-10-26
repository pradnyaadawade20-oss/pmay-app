import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import '../api.dart' show Api;
import '../pdf_docs.dart';

/// What the user chose to put on the document: a drawn signature or the thumb impression recorded at the office.
class SignResult {
  final Uint8List bytes;
  final bool isThumb;
  const SignResult(this.bytes, this.isThumb);
}

/// Screen 1: user draws the signature, or (if staff recorded one) uses the thumb impression.
class SignaturePadPage extends StatefulWidget {
  final Uint8List? thumb;
  const SignaturePadPage({super.key, this.thumb});
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
    if (bytes != null && mounted) Navigator.pop(context, SignResult(bytes, false));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sign here')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
            const SizedBox(height: 12),
            FilledButton(onPressed: _agree ? _done : null, child: const Text('Apply signature')),
            if (widget.thumb != null) ...[
              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider()),
              Row(children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), color: Colors.white),
                  child: Image.memory(widget.thumb!, fit: BoxFit.contain),
                ),
                const SizedBox(width: 14),
                const Expanded(child: Text('Aapka thumb impression office mein record ho chuka hai. Sign nahi kar sakte to ise use karein.')),
              ]),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _agree ? () => Navigator.pop(context, SignResult(widget.thumb!, true)) : null,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Use thumb impression'),
              ),
            ],
          ]),
        ),
      );
}

/// Full e-sign flow for one document.
/// [docKind]   : allotment | agreement | bank-loan | mortgage   (for /me/documents/{kind})
/// [uploadType]: agreement_signed | bank_loan_receipt | mortgage_receipt (for /me/upload)
/// Returns true if the signed PDF was uploaded (caller should refresh AppState).
Future<bool> eSignAndUpload(BuildContext context, Api api, {required String docKind, required String uploadType}) async {
  Uint8List? thumb;
  try {
    final t = await api.myThumb(); // null if staff has not recorded a thumb impression
    if (t != null) thumb = Uint8List.fromList(t);
  } catch (_) {}
  if (!context.mounted) return false;

  final res = await Navigator.push<SignResult>(context, MaterialPageRoute(builder: (_) => SignaturePadPage(thumb: thumb)));
  if (res == null) return false;

  final data = await api.get('/me/documents/$docKind');
  final built = await buildDocumentPdf(Map<String, dynamic>.from(data), signature: res.bytes, thumb: res.isThumb);

  final f = File('${Directory.systemTemp.path}/${docKind}_signed_${DateTime.now().millisecondsSinceEpoch}.pdf');
  await f.writeAsBytes(built.bytes);
  try {
    await api.postMultipart('/me/upload', fields: {'type': uploadType}, files: {'file': f.path});
  } finally {
    if (await f.exists()) await f.delete();
  }
  return true;
}