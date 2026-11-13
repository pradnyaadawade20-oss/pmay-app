import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../doc_actions.dart';
import '../payment_receipt_pdf.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

String _s(Object? v, [String d = '-']) => (v == null || '$v'.trim().isEmpty) ? d : '$v'.trim();

/// Completed payments of the signed-in applicant, newest first.
List<Map<String, dynamic>> paidPayments(AppState s) {
  final l = [for (final p in s.payments) if (p is Map && '${p['payment_status']}' == 'completed') Map<String, dynamic>.from(p)];
  l.sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
  return l;
}

/// All the facts printed on the receipt of one payment.
ReceiptInfo receiptFor(AppState s, Map payment) {
  final a = s.applicant ?? {}, u = s.unit ?? {}, p = s.project ?? {};
  final mode = '${payment['payment_method']}' == 'online' ? 'Online' : 'Offline';
  return ReceiptInfo(
    company: _s(p['developer_name'], 'PRIYANKA HOME REALTORS PVT LTD'),
    addr: _s(p['developer_address'], ''),
    rera: _s(p['rera_registration_no']),
    no: _s(payment['receipt_number']),
    date: receiptDate(payment['payment_date'] ?? payment['created_at']),
    appId: _s(a['unique_id']),
    name: '${_s(a['first_name'], '')} ${_s(a['last_name'], '')}'.trim(),
    address: _s(a['full_address']),
    contact: '${_s(a['phone'])} | ${_s(a['email'])}',
    project: _s(p['project_name']),
    unit: _s(u['unit_number']),
    fwt: '${_s(u['floor'])} / ${_s(u['wing'])} / ${_s(u['tower'])}',
    desc: 'Flat Booking / Registration Payment',
    stage: 'Booking',
    mode: mode,
    amount: num.tryParse('${payment['amount']}'),
  );
}

Future<void> downloadReceipt(BuildContext context, ReceiptInfo r) async {
  try {
    final bytes = await buildPaymentReceiptPdf(r);
    final name = 'receipt_${r.no.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf';
    final uri = await DocActions.download(bytes, name);
    if (!context.mounted || uri == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Downloaded: $name'),
        action: SnackBarAction(
            label: 'Open',
            onPressed: () => DocActions.open(uri).catchError((_) {
                  if (context.mounted) toast(context, 'No PDF viewer found. File is in your Downloads folder.', error: true);
                })),
      ));
  } catch (e) {
    if (context.mounted) toast(context, e.toString(), error: true);
  }
}

/// The receipt shown on screen, straight after a successful payment (and from the Payment step later).
class PaymentReceiptScreen extends StatelessWidget {
  final Map<String, dynamic> payment;
  const PaymentReceiptScreen({super.key, required this.payment});

  @override
  Widget build(BuildContext context) {
    final r = receiptFor(context.read<AppState>(), payment);
    Widget kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 118, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ]));
    Widget head(String t) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14, bottom: 6),
        padding: const EdgeInsets.only(bottom: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(width: 1.5, color: Color(0xFFCFD5DF)))),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)));
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Receipt')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFBBF7D0))),
          child: const Row(children: [
            Icon(Icons.check_circle, color: Color(0xFF15803D), size: 26),
            SizedBox(width: 10),
            Expanded(child: Text('Payment successful', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF15803D)))),
          ]),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(width: 2, color: Colors.black87)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Text(r.company, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            if (r.addr.isNotEmpty) Center(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(r.addr, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: Colors.black54)))),
            Center(child: Text('RERA Reg. No: ${r.rera}', style: const TextStyle(fontSize: 11.5))),
            Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 14),
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: const Color(0xFFE6EDF6),
                child: const Center(child: Text('PAYMENT RECEIPT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1)))),
            kv('Receipt No:', r.no),
            kv('Date:', r.date),
            kv('Application ID:', r.appId),
            head('RECEIVED FROM:'),
            kv('Name', r.name),
            kv('Address', r.address),
            kv('Contact', r.contact),
            head('PROPERTY DETAILS:'),
            kv('Project', r.project),
            kv('Unit No.', r.unit),
            kv('Floor / Wing / Tower', r.fwt),
            head('PAYMENT DETAILS:'),
            kv('Description', r.desc),
            kv('Payment Stage', r.stage),
            kv('Mode', r.mode),
            Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                color: const Color(0xFFEEF4FB),
                child: Row(children: [
                  const Expanded(child: Text('Total Amount Received', style: TextStyle(fontWeight: FontWeight.w700))),
                  Text(r.totalText, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ])),
            Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                color: const Color(0xFFE0E6EE),
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Amount in Words: ', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: r.words),
                ]), style: const TextStyle(fontSize: 13))),
            const SizedBox(height: 12),
            const Text('* This is a computer-generated receipt and does not require a physical signature.\n* This receipt is valid subject to realization of payment.\n* Please retain this receipt for your records.',
                style: TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.5)),
          ]),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: () => downloadReceipt(context, r), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Download Receipt (PDF)')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ]),
    );
  }
}

/// Receipts of the completed payments, listed inside the Payment step of Tracking.
class PaymentReceiptsCard extends StatelessWidget {
  const PaymentReceiptsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = paidPayments(s);
    if (list.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFBBF7D0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.receipt_long_outlined, color: Color(0xFF15803D)),
          SizedBox(width: 8),
          Text('Payment Receipt', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF15803D))),
        ]),
        for (final p in list) ...[
          const SizedBox(height: 8),
          Text('${_s(p['receipt_number'])}  -  ${receiptFor(s, p).totalText}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentReceiptScreen(payment: p))),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('View'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => downloadReceipt(context, receiptFor(s, p)), icon: const Icon(Icons.download, size: 18), label: const Text('PDF'))),
          ]),
        ],
      ]),
    );
  }
}
