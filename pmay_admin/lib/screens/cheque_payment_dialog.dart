import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../common.dart';
import '../web_open.dart';

/// "Record Cheque Payment": the admin uploads a photo of the cheque as payment proof. The payment is saved
/// (kept for future reference, visible in Payment Management) and the applicant moves on to allotment.
/// Returns true when a payment was recorded.
Future<bool?> showChequePaymentDialog(BuildContext context) =>
    showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => const ChequePaymentDialog());

class ChequePaymentDialog extends StatefulWidget {
  const ChequePaymentDialog({super.key});
  @override
  State<ChequePaymentDialog> createState() => _ChequePaymentDialogState();
}

class _ChequePaymentDialogState extends State<ChequePaymentDialog> {
  List<Map<String, dynamic>> _people = [];
  String? _id;
  bool _loading = true, _busy = false;
  String? _err;
  final _amount = TextEditingController(text: '25000');
  final _no = TextEditingController();
  final _bank = TextEditingController();
  final _note = TextEditingController();
  String? _fileName;
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    Api.i.get(Ep.list('', 'stage_3_payment')).then((r) {
      if (!mounted) return;
      setState(() {
        _people = List<Map<String, dynamic>>.from(r['applicants'] ?? []);
        _loading = false;
      });
    }).catchError((e) {
      if (mounted) {
        setState(() {
          _err = '$e';
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _no.dispose();
    _bank.dispose();
    _note.dispose();
    super.dispose();
  }

  static bool _isPdf(Uint8List b) => b.length > 3 && b[0] == 0x25 && b[1] == 0x50;

  Future<void> _pick() async {
    final f = await pickPhotoOrPdf();
    if (f == null || !mounted) return;
    if (f.bytes.length > 5 * 1024 * 1024) {
      toast(context, 'The file is larger than 5 MB. Choose a smaller photo.', error: true);
      return;
    }
    setState(() {
      _fileName = f.name;
      _bytes = f.bytes;
      _err = null;
    });
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (_id == null) return setState(() => _err = 'Select the applicant');
    if (amount == null || amount <= 0) return setState(() => _err = 'Enter the cheque amount');
    if (_bytes == null) return setState(() => _err = 'Upload a photo of the cheque');
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Api.i.postFile(Ep.cheque(_id!),
          fields: {'amount': _amount.text.trim(), 'cheque_number': _no.text.trim(), 'bank': _bank.text.trim(), 'note': _note.text.trim()},
          field: 'file',
          filename: _fileName ?? 'cheque.jpg',
          bytes: _bytes!);
      if (!mounted) return;
      toast(context, 'Cheque payment recorded');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = '$e';
        });
      }
    }
  }

  String _label(Map p) => '${p['unique_id'] ?? ''} - ${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();

  Widget _field(String label, TextEditingController c, {String? hint, TextInputType? type, List<TextInputFormatter>? fmt, int maxLen = 80}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: type,
          inputFormatters: fmt,
          maxLength: maxLen,
          enabled: !_busy,
          decoration: InputDecoration(labelText: label, hintText: hint, counterText: '', isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final img = _bytes != null && !_isPdf(_bytes!);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.receipt_long_outlined, color: kBlue, size: 24),
              const SizedBox(width: 10),
              const Expanded(child: Text('Record Cheque Payment', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk))),
              InkWell(onTap: _busy ? null : () => Navigator.pop(context, false), child: const Icon(Icons.close_rounded, color: kMuted, size: 20)),
            ]),
            const SizedBox(height: 4),
            const Text('Upload a photo of the cheque as payment proof. It is saved with the payment and the applicant moves to the allotment stage.',
                style: TextStyle(fontSize: 13.5, color: kMuted)),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_people.isEmpty)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20), child: Text('No applicant is waiting for payment right now.', style: TextStyle(color: kMuted)))
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Applicant (awaiting payment)', isDense: true),
                items: [for (final p in _people) DropdownMenuItem(value: '${p['id']}', child: Text(_label(p), overflow: TextOverflow.ellipsis))],
                onChanged: _busy ? null : (v) => setState(() => _id = v),
              ),
              const SizedBox(height: 12),
              _field('Amount (Rs)', _amount, type: TextInputType.number, fmt: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], maxLen: 12),
              _field('Cheque number (optional)', _no, maxLen: 40),
              _field('Bank name (optional)', _bank),
              _field('Note (optional)', _note, hint: 'e.g. received at office on 24 Oct', maxLen: 300),
              const Text('Cheque photo', style: TextStyle(fontWeight: FontWeight.w600, color: kInk)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF4F6FB), borderRadius: BorderRadius.circular(10), border: Border.all(color: kLine)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (img)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_bytes!, height: 160, width: double.infinity, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('Cannot preview this image')),
                    )
                  else if (_bytes != null)
                    const Row(children: [Icon(Icons.picture_as_pdf_rounded, color: kRed), SizedBox(width: 8), Text('PDF selected')])
                  else
                    const Text('No photo chosen yet', style: TextStyle(color: kMuted)),
                  if (_fileName != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_fileName!, style: const TextStyle(fontSize: 12.5, color: kMuted))),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: Text(_bytes == null ? 'Choose cheque photo' : 'Change photo'),
                  ),
                  const SizedBox(height: 4),
                  const Text('JPG, PNG or PDF, up to 5 MB.', style: TextStyle(fontSize: 12, color: kMuted)),
                ]),
              ),
            ],
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: const TextStyle(color: kRed, fontSize: 13))),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: (_busy || _loading || _people.isEmpty) ? null : _save,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text('Save Payment', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
