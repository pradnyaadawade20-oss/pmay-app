import 'package:flutter/material.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptions.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../widgets.dart';

/// Booking payment (online only) via Cashfree: UPI / Cards / Net Banking.
/// Cash / cheque / DD payments are collected by the admin at the office (Admin panel -> Collect Payment).
/// The server confirms every payment with Cashfree before the application moves to the next stage.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _cf = CFPaymentGatewayService();
  final _amount = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().project;
    _amount.text = (num.tryParse('${p?['booking_amount'] ?? 25000}') ?? 25000).toStringAsFixed(0);
    // must be set before doPayment()
    _cf.setCallback(_onCashfreeDone, _onCashfreeError);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double get _amt => double.tryParse(_amount.text.trim()) ?? 0;

  void _stopBusy() {
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _payOnline() async {
    if (_amt <= 0) {
      toast(context, 'Enter a valid amount', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final o = await context.read<AppState>().api.postJson('/payments/order', {'amount': _amt});
      final env = '${o['environment']}' == 'production' ? CFEnvironment.PRODUCTION : CFEnvironment.SANDBOX;
      final session = CFSessionBuilder()
          .setEnvironment(env)
          .setOrderId('${o['orderId']}')
          .setPaymentSessionId('${o['paymentSessionId']}')
          .build();
      _cf.doPayment(CFWebCheckoutPaymentBuilder().setSession(session).build());
    } on CFException catch (e) {
      _stopBusy();
      if (mounted) toast(context, e.message, error: true);
    } catch (e) {
      _stopBusy();
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  /// Cashfree says the checkout finished -> ask OUR server for the real result (it checks with Cashfree).
  Future<void> _onCashfreeDone(String orderId) async {
    try {
      final s = context.read<AppState>();
      final r = await s.api.postJson('/payments/verify', {'order_id': orderId});
      final status = '${r['status']}';
      if (status == 'paid') {
        await s.refresh();
        if (mounted) {
          toast(context, 'Payment successful');
          Navigator.pop(context);
        }
      } else if (mounted) {
        toast(
            context,
            status == 'failed'
                ? 'Payment failed. Please try again.'
                : 'Payment not completed yet. If money was debited, it will be confirmed automatically.',
            error: true);
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not confirm payment: $e', error: true);
    } finally {
      _stopBusy();
    }
  }

  void _onCashfreeError(CFErrorResponse err, String orderId) {
    _stopBusy();
    if (mounted) toast(context, err.getMessage() ?? 'Payment cancelled or failed', error: true);
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
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount (Rs.)', prefixText: 'Rs. ')),
        const SizedBox(height: 14),
        FilledButton.icon(
            onPressed: _busy ? null : _payOnline,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.payment),
            label: const Text('Pay Online (UPI / Card / Net Banking)')),
        const SizedBox(height: 10),
        const Text('You will be taken to the secure Cashfree payment page. Your booking is confirmed automatically once the payment succeeds.',
            style: TextStyle(fontSize: 12.5, color: Colors.black54)),
        const Divider(height: 40),
        Text('Want to pay by cash / cheque / DD?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Please visit our office. Our admin will collect the payment and update your status.'),
      ]),
    );
  }
}