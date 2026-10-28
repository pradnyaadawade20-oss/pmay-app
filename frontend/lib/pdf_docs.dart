import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'mortgage_deed_pdf.dart';

/// Generates the 4 printable documents from /api/me/documents/{kind} data
/// (kind = allotment | agreement | bank-loan | mortgage).
///
/// NOTE: this holds the *facts* (parties, unit, amount, parking). The long legal clauses
/// from the website (AgreementOfSale.tsx / MortgageDeed.tsx / AllotmentLetter.tsx) should be
/// pasted into [_clauses] by whoever owns the legal text, so the app prints identical wording.
/// The default PDF font has no ₹ / Devanagari glyphs, so amounts use "Rs.".
const _titles = {
  'allotment': 'ALLOTMENT LETTER',
  'agreement': 'AGREEMENT FOR SALE',
  'bank-loan': 'HOME LOAN APPLICATION FORM',
  'mortgage': 'MORTGAGE DEED',
};

List<String> _clauses(String kind) => const []; // TODO: paste approved legal clauses per kind

String _s(dynamic v, [String d = '-']) => (v == null || v.toString().isEmpty) ? d : v.toString();
String _money(dynamic v) {
  final n = num.tryParse(_s(v, '0')) ?? 0;
  return 'Rs. ${NumberFormat.decimalPattern('en_IN').format(n)}/-';
}

String _date(dynamic v) {
  final d = DateTime.tryParse(_s(v, ''));
  return d == null ? '-' : DateFormat('dd MMM yyyy').format(d.toLocal());
}

/// Download / print flow (unsigned).
Future<void> shareDocument(Map<String, dynamic> data) async {
  final pdf = await buildDocumentPdf(data);
  await Printing.sharePdf(bytes: pdf.bytes, filename: pdf.filename);
}

/// Builds the PDF. If [signature] (PNG bytes) is given, it is stamped above the
/// "Applicant Signature" line together with the e-sign time.
Future<({Uint8List bytes, String filename})> buildDocumentPdf(Map<String, dynamic> data, {Uint8List? signature}) async {
  final kind = data['kind'] as String;
  // Mortgage hamesha naya Simple Mortgage Deed hai. Admin ne details na bhari hon to blanks (____) print hote hain.
  if (kind == 'mortgage') {
    return buildMortgageDeedPdf(data, signature: signature);
  }
  final a = Map<String, dynamic>.from(data['applicant'] ?? {});
  final u = Map<String, dynamic>.from(data['unit'] ?? {});
  final p = Map<String, dynamic>.from(data['project'] ?? {});

  final rows = <List<String>>[
    ['Applicant', '${_s(a['first_name'])} ${_s(a['last_name'])}'],
    ['Applicant ID', _s(a['unique_id'])],
    ["Father's Name", _s(a['father_name'])],
    ['Age / Occupation', '${_s(a['age'])} / ${_s(a['occupation'])}'],
    ['Address', _s(a['full_address'])],
    ['PAN', _s(a['pan_number'])],
    ['Aadhaar', _s(a['aadhar_number'])],
    if (a['has_co_applicant'] == true) ['Co-applicant', '${_s(a['co_applicant_name'])} (${_s(a['co_applicant_relation'])})'],
    ['Project', _s(p['project_name'])],
    ['RERA No.', _s(p['rera_registration_no'])],
    ['Developer', _s(p['developer_name'])],
    ['Flat / Unit', '${_s(u['unit_number'])}, Floor ${_s(u['floor'])}, Wing ${_s(u['wing'])}'],
    ['Carpet Area', '${_s(u['carpet_area_sqm'])} sq.m (RERA ${_s(u['rera_carpet_area'])})'],
    ['Parking', '${_s(u['parking_number'])} (${_s(u['parking_type'])})'],
    ['Consideration', _money(u['consideration_amount'])],
    ['Possession By', _date(p['possession_date'])],
    ['Allotment Date', _date(a['allotment_date'])],
    if (kind == 'bank-loan' || kind == 'mortgage') ['Bank', '${_s(p['bank_name'])}, ${_s(p['bank_branch'])}'],
  ];

  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (_) => [
      pw.Center(child: pw.Text(_s(p['developer_name']), style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
      pw.Center(child: pw.Text(_s(p['developer_address']), style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
      pw.SizedBox(height: 18),
      pw.Center(child: pw.Text(_titles[kind] ?? kind.toUpperCase(), style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 4),
      pw.Center(child: pw.Text('Date: ${DateFormat('dd MMM yyyy').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 9))),
      pw.SizedBox(height: 16),
      pw.TableHelper.fromTextArray(
        data: rows,
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignment: pw.Alignment.centerLeft,
        columnWidths: {0: const pw.FixedColumnWidth(110), 1: const pw.FlexColumnWidth()},
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        cellPadding: const pw.EdgeInsets.all(6),
      ),
      pw.SizedBox(height: 16),
      for (final c in _clauses(kind)) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: pw.Text(c, style: const pw.TextStyle(fontSize: 10))),
      pw.SizedBox(height: 60),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Column(children: [
          if (signature != null) pw.Image(pw.MemoryImage(signature), width: 130, height: 50, fit: pw.BoxFit.contain),
          pw.Container(width: 150, height: 0.5, color: PdfColors.black),
          pw.Text('Applicant Signature', style: const pw.TextStyle(fontSize: 9)),
          if (signature != null)
            pw.Text('e-Signed on ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        ]),
        pw.Column(children: [pw.Container(width: 150, height: 0.5, color: PdfColors.black), pw.Text('For ${_s(p['developer_name'])}', style: const pw.TextStyle(fontSize: 9))]),
      ]),
    ],
  ));
  return (bytes: await doc.save(), filename: '${kind}_${_s(a['unique_id'], 'doc')}.pdf');
}