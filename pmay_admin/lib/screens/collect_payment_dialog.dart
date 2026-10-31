import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';
import '../cashfree_web.dart';
import '../web_file_pick.dart';

String _inr(num v) {
  final s = v.round().abs().toString();
  if (s.length <= 3) return s;
  final last = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last';
}

/// "Collect Payment" modal: an admin takes a booking payment on behalf of an applicant,
/// either online via Cashfree (charged there and then) or by uploading an offline receipt
/// (cash/cheque/DD the admin already has in hand).
class CollectPaymentDialog extends StatefulWidget {
  final Map applicant; // {id, unique_id, applicant_name, email, phone, paid}
  final num totalCost;
  final bool startOffline; // open pre-selected on the offline tab (used by the "Upload Receipt" action)
  const CollectPaymentDialog({super.key, required this.applicant, required this.totalCost, this.startOffline = false});

  @override
  State<CollectPaymentDialog> createState() => _CollectPaymentDialogState();
}

class _CollectPaymentDialogState extends State<CollectPaymentDialog> {
  late final TextEditingController _amount;
  late bool _online;
  bool _busy = false;
  String? _fileName;
  Uint8List? _fileBytes;

  num get _paid => num.tryParse('${widget.applicant['paid']}') ?? 0;
  num get _balance => (widget.totalCost - _paid).clamp(0, double.infinity);
  num get _amt => num.tryParse(_amount.text.trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    _online = !widget.startOffline;
    final def = _balance > 0 && _balance < 25000 ? _balance : 25000;
    _amount = TextEditingController(text: def.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final f = await pickFile();
    if (f != null) setState(() {
      _fileName = f.name;
      _fileBytes = f.bytes;
    });
  }

  /// After the Cashfree popup closes, ask OUR server for the real status (it checks with Cashfree).
  Future<void> _verifyOnline(String orderId) async {
    try {
      final r = await Api.i.post(Ep.collectVerify, {'order_id': orderId});
      final status = '${r['status']}';
      if (!mounted) return;
      if (status == 'paid') {
        toast(context, 'Payment collected');
        Navigator.pop(context, true);
      } else if (status == 'failed') {
        toast(context, 'Payment failed. Please try again.', error: true);
      } else {
        toast(context, 'Payment was not completed. Try again, or close this and check All Payments later.', error: true);
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not confirm payment: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_amt <= 0) {
      toast(context, 'Enter a valid amount', error: true);
      return;
    }
    if (!_online && _fileBytes == null) {
      toast(context, 'Choose the payment receipt first', error: true);
      return;
    }
    setState(() => _busy = true);

    if (_online) {
      try {
        final o = await Api.i.post(Ep.collectOrder, {'applicant_id': '${widget.applicant['id']}', 'amount': _amt});
        await openCashfreeCheckout(paymentSessionId: '${o['paymentSessionId']}', environment: '${o['environment']}');
        await _verifyOnline('${o['orderId']}');
      } catch (e) {
        if (mounted) {
          setState(() => _busy = false);
          toast(context, e.toString(), error: true);
        }
      }
      return;
    }

    try {
      await Api.i.postMultipart(Ep.collectOffline,
          fields: {'applicant_id': '${widget.applicant['id']}', 'amount': _amt.toStringAsFixed(0), 'mode': 'cash'},
          fileField: 'receipt',
          fileName: _fileName,
          fileBytes: _fileBytes);
      if (mounted) {
        toast(context, 'Payment recorded');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stat(String label, num value, Color bg, Color fg) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12.5, color: kMuted)),
            const SizedBox(height: 4),
            Text('₹${_inr(value)}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: fg)),
          ]),
        ),
      );

  Widget _methodTile({required bool selected, required IconData icon, required String title, required String sub, required VoidCallback onTap}) =>
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: selected ? kBlue : kLine, width: selected ? 1.6 : 1)),
            child: Row(children: [
              Radio<bool>(value: true, groupValue: selected ? true : null, onChanged: (_) => onTap(), activeColor: kBlue),
              Icon(icon, size: 20, color: kInk),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
                  Text(sub, style: const TextStyle(fontSize: 12.5, color: kMuted)),
                ]),
              ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final a = widget.applicant;
    final name = '${a['applicant_name'] ?? '-'}';
    final uid = '${a['unique_id'] ?? '-'}';
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Collect Payment', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: kInk)),
                  const SizedBox(height: 4),
                  Text('Process payment for $uid - $name', style: const TextStyle(fontSize: 13.5, color: kMuted)),
                ]),
              ),
              IconButton(onPressed: _busy ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: kInk)),
            ]),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [Icon(Icons.person_outline_rounded, size: 17, color: kMuted), SizedBox(width: 6), Text('Customer Details', style: TextStyle(fontWeight: FontWeight.w700, color: kInk))]),
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text('ID: $uid', style: const TextStyle(fontSize: 13.5, color: kInk))),
                  Expanded(child: Text('Name: $name', style: const TextStyle(fontSize: 13.5, color: kInk))),
                ]),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text('Email: ${a['email'] ?? '-'}', style: const TextStyle(fontSize: 13.5, color: kInk))),
                  Expanded(child: Text('Phone: ${a['phone'] ?? '-'}', style: const TextStyle(fontSize: 13.5, color: kInk))),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              _stat('Total Cost', widget.totalCost, kBg, kInk),
              const SizedBox(width: 10),
              _stat('Paid', _paid, kGreen.withValues(alpha: 0.10), kGreen),
              const SizedBox(width: 10),
              _stat('Balance', _balance, kOrange.withValues(alpha: 0.10), const Color(0xFFD98B00)),
            ]),
            const SizedBox(height: 18),
            const Text('Payment Amount (₹)', style: TextStyle(fontWeight: FontWeight.w600, color: kInk)),
            const SizedBox(height: 6),
            TextField(controller: _amount, keyboardType: TextInputType.number, enabled: !_busy),
            const SizedBox(height: 16),
            _methodTile(
              selected: _online,
              icon: Icons.credit_card_rounded,
              title: 'Online (Cashfree)',
              sub: 'Collect via UPI/Cards/Net Banking',
              onTap: _busy ? () {} : () => setState(() => _online = true),
            ),
            const SizedBox(height: 10),
            _methodTile(
              selected: !_online,
              icon: Icons.account_balance_outlined,
              title: 'Cash (Offline Receipt)',
              sub: 'Cash received - upload the receipt as proof',
              onTap: _busy ? () {} : () => setState(() => _online = false),
            ),
            if (!_online) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickReceipt,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(_fileName ?? 'Choose receipt file'),
                style: OutlinedButton.styleFrom(foregroundColor: kInk, padding: const EdgeInsets.symmetric(vertical: 14), alignment: Alignment.centerLeft),
              ),
            ],
            const SizedBox(height: 22),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context), style: OutlinedButton.styleFrom(foregroundColor: kInk), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.credit_card_rounded, size: 18),
                  label: Text('Collect ₹${_inr(_amt)}'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}