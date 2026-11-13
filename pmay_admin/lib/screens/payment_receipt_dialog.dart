import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';
import '../payment_receipt_pdf.dart';
import '../web_open.dart';

String _s(Object? v, [String d = '-']) => (v == null || '$v'.trim().isEmpty) ? d : '$v'.trim();

/// Builds the receipt facts from /admin/applicants/{id} (applicant, unit, project) and one payment.
ReceiptInfo _info(Map applicant, Map unit, Map project, Map payment) {
  final method = '${payment['payment_mode'] ?? ''}'.trim().isNotEmpty ? '${payment['payment_mode']}' : '${payment['payment_method'] ?? 'offline'}';
  return ReceiptInfo(
    company: _s(project['developer_name'], 'PRIYANKA HOME REALTORS PVT LTD'),
    addr: _s(project['developer_address'], ''),
    rera: _s(project['rera_registration_no']),
    no: _s(payment['receipt_number']),
    date: receiptDate(payment['payment_date'] ?? payment['created_at']),
    appId: _s(applicant['unique_id']),
    name: fullName(applicant),
    address: _s(applicant['full_address']),
    contact: '${_s(applicant['phone'])} | ${_s(applicant['email'])}',
    project: _s(project['project_name']),
    unit: _s(unit['unit_number']),
    fwt: '${_s(unit['floor'])} / ${_s(unit['wing'])} / ${_s(unit['tower'])}',
    desc: 'Flat Booking / Registration Payment',
    stage: 'Booking',
    mode: method.isEmpty ? 'Offline' : '${method[0].toUpperCase()}${method.substring(1)}',
    amount: num.tryParse('${payment['amount']}'),
  );
}

/// Shows the Payment Receipt of an applicant's completed payment (the given [paymentId], else the latest one)
/// with a PDF download. Used right after a payment is collected / confirmed and from the payment details.
Future<void> showPaymentReceipt(BuildContext context, {required Object? applicantId, Object? paymentId}) async {
  if (applicantId == null) return;
  try {
    final r = await Api.i.get(Ep.one('$applicantId'));
    final pays = [for (final p in (r['payments'] as List? ?? [])) if (p is Map && '${p['payment_status']}' == 'completed') Map<String, dynamic>.from(p)];
    pays.sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    final pick = paymentId == null ? (pays.isEmpty ? null : pays.first) : pays.where((p) => '${p['id']}' == '$paymentId').firstOrNull;
    if (pick == null) {
      if (context.mounted) toast(context, 'No completed payment found for a receipt yet', error: true);
      return;
    }
    final info = _info(Map.from(r['applicant'] ?? {}), Map.from(r['unit'] ?? {}), Map.from(r['project'] ?? {}), pick);
    if (!context.mounted) return;
    await showDialog<void>(context: context, builder: (_) => PaymentReceiptDialog(info: info));
  } catch (e) {
    if (context.mounted) toast(context, e.toString(), error: true);
  }
}

class PaymentReceiptDialog extends StatelessWidget {
  final ReceiptInfo info;
  const PaymentReceiptDialog({super.key, required this.info});

  Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 150, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kInk))),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 14, color: kInk))),
      ]));

  Widget _head(String t) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16, bottom: 6),
      padding: const EdgeInsets.only(bottom: 4),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(width: 1.5, color: Color(0xFFCFD5DF)))),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kInk)));

  String get _file => 'receipt_${info.no.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf';

  @override
  Widget build(BuildContext context) {
    final r = info;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 12, 6),
            child: Row(children: [
              const Icon(Icons.check_circle, color: kGreen),
              const SizedBox(width: 8),
              const Expanded(child: Text('Payment Receipt', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: kInk)),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 12),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(width: 2.5, color: const Color(0xFF111111))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Text(r.company, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk))),
                  if (r.addr.isNotEmpty) Center(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(r.addr, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: kMuted)))),
                  Center(child: Text('RERA Reg. No: ${r.rera}', style: const TextStyle(fontSize: 13, color: kInk))),
                  Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 18),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      color: const Color(0xFFE6EDF6),
                      child: const Center(child: Text('PAYMENT RECEIPT', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 1, color: kInk)))),
                  _kv('Receipt No:', r.no),
                  _kv('Date:', r.date),
                  _kv('Application ID:', r.appId),
                  _head('RECEIVED FROM:'),
                  _kv('Name', r.name),
                  _kv('Address', r.address),
                  _kv('Contact', r.contact),
                  _head('PROPERTY DETAILS:'),
                  _kv('Project', r.project),
                  _kv('Unit No.', r.unit),
                  _kv('Floor / Wing / Tower', r.fwt),
                  _head('PAYMENT DETAILS:'),
                  _kv('Description', r.desc),
                  _kv('Payment Stage', r.stage),
                  _kv('Mode', r.mode),
                  Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(14),
                      color: const Color(0xFFEEF4FB),
                      child: Row(children: [
                        const Expanded(child: Text('Total Amount Received', style: TextStyle(fontWeight: FontWeight.w700, color: kInk))),
                        Text(r.totalText, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: kInk)),
                      ])),
                  Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.all(14),
                      color: const Color(0xFFE0E6EE),
                      child: Text.rich(TextSpan(children: [
                        const TextSpan(text: 'Amount in Words: ', style: TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: r.words),
                      ]), style: const TextStyle(fontSize: 14, color: kInk))),
                  const SizedBox(height: 12),
                  const Text('* This is a computer-generated receipt and does not require a physical signature.\n* This receipt is valid subject to realization of payment.\n* Please retain this receipt for your records.',
                      style: TextStyle(fontSize: 12.5, color: kMuted, height: 1.6)),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 18),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () async => openBytes(await buildPaymentReceiptPdf(r)),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open / Print'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () async => downloadBytes(_file, await buildPaymentReceiptPdf(r), 'application/pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Download PDF'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
