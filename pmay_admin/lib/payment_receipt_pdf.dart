import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Everything printed on a Payment Receipt. The customer app and the admin panel both build it
/// (this file is shared by both) so the PDF looks the same on both sides.
class ReceiptInfo {
  final String company, addr, rera, no, date, appId, name, address, contact, project, unit, fwt, desc, stage, mode;
  final num? amount;
  const ReceiptInfo({
    required this.company,
    required this.addr,
    required this.rera,
    required this.no,
    required this.date,
    required this.appId,
    required this.name,
    required this.address,
    required this.contact,
    required this.project,
    required this.unit,
    required this.fwt,
    required this.desc,
    required this.stage,
    required this.mode,
    required this.amount,
  });

  String get amountText => amount == null ? '________' : inrFormat(amount!);
  String get totalText => amount == null ? '________' : 'Rs. ${inrFormat(amount!)}/-';
  String get words => amount == null ? '________' : 'Rupees ${inrWords(amount!.round())} Only';
}

/// 2550000 -> "25,50,000" (Indian digit grouping).
String inrFormat(num v) {
  final neg = v < 0;
  final fixed = v.abs().toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
  final parts = fixed.split('.');
  var s = parts[0];
  if (s.length > 3) {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    s = '${groups.join(',')},$last3';
  }
  return '${neg ? '-' : ''}$s${parts.length > 1 ? '.${parts[1]}' : ''}';
}

const _ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

/// 2550000 -> "Twenty Five Lakh Fifty Thousand" (Indian numbering).
String inrWords(int n) {
  if (n <= 0) return 'Zero';
  String two(int x) => x < 20 ? _ones[x] : '${_tens[x ~/ 10]}${x % 10 == 0 ? '' : ' ${_ones[x % 10]}'}';
  final parts = <String>[];
  void add(int x, String unit) {
    if (x > 0) parts.add('${two(x)} $unit');
  }

  add(n ~/ 10000000, 'Crore');
  add((n ~/ 100000) % 100, 'Lakh');
  add((n ~/ 1000) % 100, 'Thousand');
  add((n ~/ 100) % 10, 'Hundred');
  if (n % 100 > 0) parts.add(two(n % 100));
  return parts.join(' ');
}

/// dd/MM/yyyy from a date or an ISO string; '________' when missing.
String receiptDate(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
  if (d == null) return '________';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// The Payment Receipt as a PDF (A4, boxed layout: parties, property, payment table, amount in words).
Future<Uint8List> buildPaymentReceiptPdf(ReceiptInfo r) async {
  const ink = PdfColor.fromInt(0xFF111111);
  const grey = PdfColor.fromInt(0xFF6B7585);
  const rule = PdfColor.fromInt(0xFFCFD5DF);
  pw.TextStyle t({double size = 10, bool bold = false, PdfColor color = PdfColors.black}) =>
      pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color);

  pw.Widget cell(String s, {bool bold = false, bool right = false, double size = 10}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      child: pw.Text(s, textAlign: right ? pw.TextAlign.right : pw.TextAlign.left, style: t(size: size, bold: bold)));

  pw.Widget section(String s) => pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 16, bottom: 6),
      padding: const pw.EdgeInsets.only(bottom: 3),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1.5, color: rule))),
      child: pw.Text(s, style: t(bold: true)));

  pw.Widget kv(List<(String, String)> rows) => pw.Table(
      border: pw.TableBorder.all(width: 1, color: PdfColors.grey800),
      columnWidths: const {0: pw.FractionColumnWidth(0.27), 1: pw.FlexColumnWidth()},
      children: [for (final e in rows) pw.TableRow(children: [cell(e.$1, bold: true), cell(e.$2)])]);

  pw.Widget sign(String s) => pw.Container(
      width: 150, padding: const pw.EdgeInsets.only(top: 3), decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 1.5, color: ink))), child: pw.Text(s, style: t()));

  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(30),
    build: (_) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(22, 20, 22, 16),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 2, color: ink)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Center(child: pw.Text(r.company, textAlign: pw.TextAlign.center, style: t(size: 17, bold: true))),
        pw.SizedBox(height: 4),
        pw.Center(child: pw.Text(r.addr, textAlign: pw.TextAlign.center, style: t(size: 9, color: grey))),
        pw.Center(child: pw.Text('RERA Reg. No: ${r.rera}', style: t(size: 9))),
        pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(top: 16, bottom: 14),
            padding: const pw.EdgeInsets.symmetric(vertical: 12),
            color: const PdfColor.fromInt(0xFFE6EDF6),
            child: pw.Center(child: pw.Text('PAYMENT RECEIPT', style: t(size: 15, bold: true)))),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.RichText(text: pw.TextSpan(children: [pw.TextSpan(text: 'Receipt No: ', style: t(bold: true)), pw.TextSpan(text: r.no, style: t())])),
            pw.SizedBox(height: 3),
            pw.RichText(text: pw.TextSpan(children: [pw.TextSpan(text: 'Date: ', style: t(bold: true)), pw.TextSpan(text: r.date, style: t())])),
          ]),
          pw.RichText(text: pw.TextSpan(children: [pw.TextSpan(text: 'Application ID: ', style: t(bold: true)), pw.TextSpan(text: r.appId, style: t())])),
        ]),
        section('RECEIVED FROM:'),
        kv([('Name', r.name), ('Address', r.address), ('Contact', r.contact)]),
        section('PROPERTY DETAILS:'),
        kv([('Project', r.project), ('Unit No.', r.unit), ('Floor / Wing / Tower', r.fwt)]),
        section('PAYMENT DETAILS:'),
        pw.Table(
          border: pw.TableBorder.all(width: 1, color: PdfColors.grey800),
          columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.4), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1.5)},
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
              cell('Description', bold: true), cell('Payment Stage', bold: true), cell('Mode', bold: true), cell('Amount (Rs.)', bold: true, right: true)
            ]),
            pw.TableRow(children: [cell(r.desc), cell(r.stage), cell(r.mode), cell(r.amountText, bold: true, right: true)]),
          ],
        ),
        pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFEEF4FB), border: pw.Border.all(width: 1, color: PdfColors.grey800)),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Text('Total Amount Received:  ', style: t(bold: true)),
              pw.Text(r.totalText, style: t(size: 12, bold: true)),
            ])),
        pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(top: 16, bottom: 14),
            padding: const pw.EdgeInsets.all(10),
            color: const PdfColor.fromInt(0xFFE0E6EE),
            child: pw.RichText(text: pw.TextSpan(children: [pw.TextSpan(text: 'Amount in Words: ', style: t(bold: true)), pw.TextSpan(text: r.words, style: t())]))),
        pw.Text(
            '* This is a computer-generated receipt and does not require a physical signature.\n* This receipt is valid subject to realization of payment.\n* Please retain this receipt for your records.',
            style: t(size: 8.5, color: grey)),
        pw.SizedBox(height: 34),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          sign('Applicant Signature'),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('For ${r.company}', style: t(bold: true)),
            pw.SizedBox(height: 28),
            sign('Authorized Signatory'),
          ]),
        ]),
        pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(top: 30),
            padding: const pw.EdgeInsets.only(top: 10),
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 1, color: rule))),
            child: pw.Text('Thank you for choosing ${r.project}\nFor any queries, please contact us at our registered office',
                textAlign: pw.TextAlign.center, style: t(size: 9, color: grey))),
      ]),
    ),
  ));
  return doc.save();
}
