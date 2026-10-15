import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../state.dart';
import '../widgets.dart';

/// Booking payment: pay online with Razorpay, or upload an offline (bank/cheque) receipt for admin verification.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _rzp = Razorpay();
  final _amount = TextEditingController();
  String? _receipt;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().project;
    _amount.text = (num.tryParse('${p?['booking_amount'] ?? 25000}') ?? 25000).toStringAsFixed(0);
    _rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      setState(() => _busy = false);
      toast(context, r.message ?? 'Payment failed', error: true);
    });
  }

  @override
  void dispose() {
    _rzp.clear();
    super.dispose();
  }

  double get _amt => double.tryParse(_amount.text.trim()) ?? 0;

  Future<void> _payOnline() async {
    setState(() => _busy = true);
    try {
      final o = await context.read<AppState>().api.postJson('/payments/order', {'amount': _amt});
      _rzp.open({
        'key': o['keyId'],
        'order_id': o['orderId'],
        'amount': ((o['amount'] as num) * 100).round(),
        'name': 'PMAY Registration',
        'description': 'Booking amount',
        'prefill': {'contact': o['phone'], 'email': o['email']},
      });
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _onSuccess(PaymentSuccessResponse r) async {
    try {
      final s = context.read<AppState>();
      await s.api.postJson('/payments/verify', {
        'razorpay_order_id': r.orderId,
        'razorpay_payment_id': r.paymentId,
        'razorpay_signature': r.signature,
      });
      await s.refresh();
      if (mounted) {
        toast(context, 'Payment successful');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, 'Payment received but verification failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitOffline() async {
    if (_receipt == null) {
      toast(context, 'Choose your payment receipt first', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final s = context.read<AppState>();
      await s.api.postMultipart('/payments/offline', fields: {'amount': _amt.toStringAsFixed(0)}, files: {'receipt': _receipt!});
      await s.refresh();
      if (mounted) {
        toast(context, 'Submitted. Admin will verify your payment.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().project ?? {};
    return Scaffold(
      appBar: AppBar(title: const Text('Booking Payment')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Total property cost: Rs. ${p['total_cost'] ?? '2550000'}'),
        Text('Minimum booking amount: Rs. ${p['booking_amount'] ?? '25000'}'),
        const SizedBox(height: 14),
        TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount (Rs.)', prefixText: 'Rs. ')),
        const SizedBox(height: 14),
        FilledButton.icon(
            onPressed: _busy ? null : _payOnline, icon: const Icon(Icons.payment), label: const Text('Pay Online (Razorpay)')),
        const Divider(height: 40),
        Text('Or pay by bank transfer / cheque', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Bank: ${p['bank_name'] ?? '-'}\nBranch: ${p['bank_branch'] ?? '-'}\n'
            'Account No: ${p['bank_account_no'] ?? 'Contact admin'}\nIFSC: ${p['bank_ifsc'] ?? 'Contact admin'}'),
        const SizedBox(height: 12),
        UploadTile(
            label: 'Payment receipt',
            path: _receipt,
            onPick: () async {
              final f = await pickDoc();
              if (f != null) setState(() => _receipt = f);
            }),
        OutlinedButton(onPressed: _busy ? null : _submitOffline, child: const Text('Submit for verification')),
      ]),
    );
  }
}
