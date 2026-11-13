import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'aadhaar.dart';

/// The two documents the applicant signs: Agreement of Sale and Allotment Letter.
/// Same wording and layout as the documents the admin panel's Document Generator prints
/// (pmay_admin/lib/screens/all_applications.dart) - keep the two in step.
/// The built-in PDF fonts have no Rupee sign, so amounts use "Rs.".

// Fixed promoter details (same as the admin panel).
const _promoterName = 'M/S. PRIYANKA HOME REALTORS PVT LTD';
const _promoterDesc =
    'a Private Company incorporated under the provisions of the Companies Act, having its registered office at Office No. A-1 & A-2, 1st Floor, Swastik Residency CHS, Survey No 65, Hissa No 4, Village Ambivali, Taluka Kalyan, District Thane - 421102, CIN: U70102MH2011PTC222565, PAN: AACCP8176E';
const _land =
    '29137.40 Sq. Mtr. bearing Survey Nos. 65,67,78,81,82,83,84,89,118,119,122,123,124 (Part) & 125 situated at Village Ambivali, Taluka Kalyan, District Thane';
const _place = 'Ambivali, Kalyan, Thane';
const _defProject = 'DABBEWALA & CHARMAKAR BUILDING';
const _defRera = 'P52000054498';
const _defDeveloper = 'PRIYANKA HOME REALTORS PVT LTD';

// ---------- small helpers ----------
const _blank = '________';

String _s(Object? v, [String d = _blank]) {
  final t = (v ?? '').toString().trim();
  return t.isEmpty ? d : t;
}

Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

String _ord(int d) => (d % 100 >= 11 && d % 100 <= 13)
    ? 'th'
    : switch (d % 10) {
        1 => 'st',
        2 => 'nd',
        3 => 'rd',
        _ => 'th',
      };

String _dmy(DateTime d) => DateFormat('dd/MM/yyyy').format(d);
String _inr(num n) => NumberFormat.decimalPattern('en_IN').format(n); // 2550000 -> 25,50,000
String _rs(num? n) => n == null ? _blank : 'Rs. ${_inr(n)}/-';
num? _num(Object? v) => num.tryParse('${v ?? ''}'.replaceAll(',', '').trim());

/// "1" -> "1st Floor"; a value that already says "Floor" is kept.
String _floorText(String v) {
  final n = int.tryParse(v.trim());
  if (n != null) return '$n${_ord(n)} Floor';
  return v.toLowerCase().contains('floor') || v == _blank ? v : '$v Floor';
}

const _onesW = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
const _tensW = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

/// 2550000 -> "Twenty Five Lakh Fifty Thousand" (Indian numbering).
String _words(int n) {
  if (n <= 0) return 'Zero';
  String two(int x) => x < 20 ? _onesW[x] : '${_tensW[x ~/ 10]}${x % 10 == 0 ? '' : ' ${_onesW[x % 10]}'}';
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

// ---------- pdf building blocks ----------
const _body = 11.0;

pw.TextStyle _t({double size = _body, bool bold = false, bool underline = false, PdfColor? color}) => pw.TextStyle(
    fontSize: size,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    decoration: underline ? pw.TextDecoration.underline : null,
    color: color,
    lineSpacing: 2.5);

/// `**text**` is bold.
pw.Widget _rich(String t, {double size = _body, bool justify = true}) {
  final parts = t.split('**');
  return pw.RichText(
    textAlign: justify ? pw.TextAlign.justify : pw.TextAlign.left,
    text: pw.TextSpan(style: _t(size: size), children: [
      for (var i = 0; i < parts.length; i++) pw.TextSpan(text: parts[i], style: i.isOdd ? _t(size: size, bold: true) : null),
    ]),
  );
}

pw.Widget _p(String t, {bool justify = true}) => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: _rich(t, justify: justify));

pw.Widget _h(String t, {double size = 15}) => pw.Padding(padding: const pw.EdgeInsets.only(top: 14, bottom: 5), child: pw.Text(t, style: _t(size: size, bold: true)));

pw.Widget _cell(String t, {bool bold = false, bool right = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: pw.Text(t, textAlign: right ? pw.TextAlign.right : pw.TextAlign.left, style: _t(bold: bold)));

/// Bordered two-column table, bold labels on the left.
pw.Widget _kv(List<List<String>> rows) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6),
    child: pw.Table(
      border: pw.TableBorder.all(width: 1.2),
      columnWidths: {0: const pw.FractionColumnWidth(0.34), 1: const pw.FlexColumnWidth()},
      children: [
        for (final r in rows) pw.TableRow(children: [_cell(r[0], bold: true), _cell(r[1])]),
      ],
    ));

/// Bordered table with a shaded heading row; [boldLast] makes the last row bold (totals).
pw.Widget _grid(List<List<String>> rows, {Map<int, pw.TableColumnWidth>? widths, bool boldLast = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6),
    child: pw.Table(
      border: pw.TableBorder.all(width: 1.2),
      columnWidths: widths,
      children: [
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: i == 0 ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF2F2F2)) : null,
            children: [for (final c in rows[i]) _cell(c, bold: i == 0 || (boldLast && i == rows.length - 1))],
          ),
      ],
    ));

/// Keeps a heading and its table together: a section that does not fit moves to the next page as a whole.
/// (A bare Column may be split between its children by the page layout; Inseparable keeps it on one page.)
pw.Widget _keep(List<pw.Widget> children) => pw.Inseparable(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: children));

// The built-in PDF fonts cannot draw the bullet character, so the dot is drawn as a small circle.
pw.Widget _bullets(List<String> items) => pw.Padding(
    padding: const pw.EdgeInsets.fromLTRB(16, 2, 0, 6),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      for (final i in items)
        pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Padding(padding: const pw.EdgeInsets.only(top: 5), child: pw.Container(width: 4, height: 4, decoration: const pw.BoxDecoration(color: PdfColors.black, shape: pw.BoxShape.circle))),
              pw.SizedBox(width: 8),
              pw.Expanded(child: pw.Text(i, style: _t())),
            ])),
    ]));

pw.Widget _numbered(List<String> items) => pw.Padding(
    padding: const pw.EdgeInsets.fromLTRB(14, 2, 0, 6),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      for (var i = 0; i < items.length; i++) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.5), child: pw.Text('${i + 1}. ${items[i]}', style: _t())),
    ]));

pw.Widget _rule({double w = 1.2, double width = 190}) => pw.Container(width: width, height: w, color: PdfColors.black);

/// A blank signature line with a caption.
pw.Widget _signLine(String caption, {double width = 190}) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(height: 46),
      _rule(width: width),
      pw.SizedBox(height: 3),
      pw.Text(caption, style: _t(size: 10)),
    ]);

pw.Document _newDoc() => pw.Document(
    theme: pw.ThemeData.withFont(base: pw.Font.times(), bold: pw.Font.timesBold(), italic: pw.Font.timesItalic(), boldItalic: pw.Font.timesBoldItalic()));

const _margin = pw.EdgeInsets.fromLTRB(46, 44, 46, 44);

// =====================================================================
// Agreement of Sale
// =====================================================================
Future<({Uint8List bytes, String filename})> buildAgreementOfSalePdf(Map<String, dynamic> data) async {
  final a = _m(data['applicant']), u = _m(data['unit']), p = _m(data['project']);
  final now = DateTime.now();

  final name = '${_s(a['first_name'], '')} ${_s(a['last_name'], '')}'.trim().toUpperCase();
  final dob = DateTime.tryParse(_s(a['date_of_birth'], ''));
  final storedAge = int.tryParse('${a['age'] ?? ''}');
  final age = dob != null ? '${(now.difference(dob).inDays / 365.25).floor()}' : (storedAge != null ? '$storedAge' : '____');
  final project = _s(p['project_name'], _defProject);
  final rera = _s(p['rera_registration_no'], _defRera);
  final flat = _s(u['unit_number']);
  final floor = _floorText(_s(u['floor']));
  final wing = _s(u['wing']);
  final tower = _s(u['tower']);
  final total = _num(u['consideration_amount']);
  final totalTxt = _rs(total);
  final words = total == null ? _blank : _words(total.round());
  final carpet = _s(u['carpet_area_sqm'], '').isEmpty ? _blank : '${u['carpet_area_sqm']} Sq. Mtr.';
  final parkNo = _s(u['parking_number'], '');
  final parking = parkNo.isEmpty ? _blank : '$parkNo${_s(u['parking_type'], '').isEmpty ? '' : ' (${u['parking_type']})'}';
  final pd = DateTime.tryParse(_s(p['possession_date'], '2028-12-31'));
  final possession = pd == null ? '31/12/2028' : _dmy(pd);
  final aadhaar = formatAadhaar(a['aadhar_number']).isEmpty ? _blank : formatAadhaar(a['aadhar_number']);

  const stagesPct = [
    ('On Booking / Agreement', 10),
    ('On Completion of Plinth', 20),
    ('On Completion of 4th Slab', 20),
    ('On Completion of 8th Slab', 20),
    ('On Completion of Brick Work', 15),
    ('On Possession', 15),
  ];
  final schedule = <List<String>>[
    ['Sr. No.', 'Stage', 'Percentage', 'Amount (Rs.)'],
    for (var i = 0; i < stagesPct.length; i++) ['${i + 1}', stagesPct[i].$1, '${stagesPct[i].$2}%', total == null ? _blank : _inr(total * stagesPct[i].$2 / 100)],
    ['', 'Total', '100%', total == null ? _blank : _inr(total)],
  ];


  final doc = _newDoc();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: _margin,
    build: (_) => [
      pw.Center(child: pw.Text('AGREEMENT OF SALE', style: _t(size: 21, bold: true, underline: true))),
      pw.SizedBox(height: 10),
      _p('Made at $_place on this **${now.day}${_ord(now.day)} day of ${DateFormat('MMMM, yyyy').format(now)}**'),
      _h('BETWEEN:'),
      _p('**$_promoterName**, $_promoterDesc(Hereinafter referred to as "**THE PROMOTER**" which expression shall mean and include its successors, partners, executors and assignees of ONE PART)'),
      _p('**AND**'),
      _p('**$name**, Age $age Years, Occupation: ${_s(a['occupation'], 'N/A')}, (PAN NO ${_s(a['pan_number'])}), (AADHAR NO. ${aadhaar.replaceAll(' ', ' ')}), Residing At: ${_s(a['full_address'])}, Mobile No. ${_s(a['phone'])}, Email: ${_s(a['email'])}(Hereinafter called the "**PURCHASER/ALLOTTEE**" which expression shall, unless repugnant to the context mean and include his heirs, executors, legal representatives, successors and assigns) OF OTHER PART.'),
      _h('WHEREAS:'),
      _p('A. The Promoter is absolute owner and in possession of land admeasuring $_land (hereinafter referred to as "The said land") and is developing a project known as "**$project**" thereon registered under MahaRERA vide Registration No. **$rera**.'),
      _p('B. The Purchaser, having been satisfied as to the title and ownership of the Promoter in and to the Said Premises and having understood the nature and extent of the project, has agreed to purchase from the Promoter Flat No. **$flat** on the **$floor**, Wing **$wing**, Building/Tower **$tower** in the Said Building together with proportionate undivided share in the Said Land (Hereinafter referred to as "**The Said Flat**").'),
      pw.NewPage(),
      _h('SCHEDULE - THE SAID FLAT'),
      _kv([
        ['Project Name', project],
        ['RERA Registration No.', rera],
        ['Flat No.', flat],
        ['Floor', floor],
        ['Wing', wing],
        ['Tower/Building', tower],
        ['Carpet Area', carpet],
        ['Parking No.', parking],
        ['Total Consideration', '$totalTxt ($words)'],
      ]),
      _h('NOW THIS AGREEMENT WITNESSETH AS UNDER:'),
      _p('**1. SALE CONSIDERATION:** The Purchaser agrees to pay to the Promoter for the Said Flat a total consideration of **$totalTxt** (Rupees $words Only) as per the payment schedule annexed hereto.'),
      _p('**2. PAYMENT SCHEDULE:** The Purchaser shall pay the consideration in the following manner:'),
      _grid(schedule,
          widths: {0: const pw.FractionColumnWidth(0.14), 1: const pw.FractionColumnWidth(0.38), 2: const pw.FractionColumnWidth(0.2), 3: const pw.FractionColumnWidth(0.28)},
          boldLast: true),
      pw.NewPage(),
      _h('TERMS AND CONDITIONS:'),
      _p('**3. POSSESSION:** The Promoter shall endeavor to hand over possession of the Said Flat to the Purchaser on or before **$possession**, subject to force majeure conditions and timely payment of all dues by the Purchaser.'),
      _p('**4. STAMP DUTY AND REGISTRATION:** The Purchaser shall bear and pay the stamp duty, registration charges, and all other charges, levies, and taxes payable in respect of this Agreement and/or any other documents to be executed in pursuance hereof.'),
      _p('**5. MAINTENANCE:** The Purchaser agrees to pay maintenance charges as decided by the Promoter/Society from the date of possession or deemed possession, whichever is earlier.'),
      _p('**6. CANCELLATION:** In the event of cancellation by the Purchaser:'),
      _bullets(['Before registration of Agreement - Forfeiture of 10% of total consideration', 'After registration of Agreement - Forfeiture of 20% of total consideration']),
      _p('**7. DEFAULT IN PAYMENT:** In case of default in payment of any installment by the Purchaser, interest @ 18% p.a. shall be payable on the delayed amount.'),
      _p('**8. TRANSFER:** The Purchaser shall not transfer, assign, or part with possession of the Said Flat before taking possession without prior written consent of the Promoter.'),
      _p('**9. COMMON AREAS:** The Purchaser shall have the right to use common areas, facilities, and amenities in the project as per the approved plans and specifications.'),
      _p('**10. ALTERATIONS:** The Purchaser shall not make any structural alterations to the Said Flat without prior approval from the concerned authorities and the Society.'),
      pw.NewPage(),
      _h('IN WITNESS WHEREOF'),
      _p('The parties hereto have set and subscribed their respective hands and seals on the day, month and year first hereinabove written.'),
      pw.SizedBox(height: 26),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('PROMOTER:', style: _t(bold: true)),
          pw.SizedBox(height: 8),
          pw.Text('For $_promoterName', style: _t()),
          _signLine('Authorized Signatory'),
        ])),
        pw.SizedBox(width: 30),
        pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('PURCHASER:', style: _t(bold: true)),
          pw.SizedBox(height: 8),
          pw.Text(name, style: _t()),
          _signLine('Signature'),
        ])),
      ]),
      pw.SizedBox(height: 34),
      pw.Text('WITNESSES:', style: _t(bold: true)),
      pw.SizedBox(height: 10),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        for (final n in ['1.', '2.']) ...[
          pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(n, style: _t()), pw.Text('Name:', style: _t())]),
            pw.SizedBox(height: 16),
            _rule(width: 220),
            pw.SizedBox(height: 8),
            pw.Text('Address:', style: _t()),
            pw.SizedBox(height: 16),
            _rule(width: 220),
            pw.SizedBox(height: 8),
            pw.Text('Signature:', style: _t()),
            pw.SizedBox(height: 16),
            _rule(width: 220),
          ])),
          if (n == '1.') pw.SizedBox(width: 30),
        ],
      ]),
    ],
  ));
  return (bytes: await doc.save(), filename: 'agreement_${_s(a['unique_id'], 'doc')}.pdf');
}

// =====================================================================
// Allotment Letter (MahaRERA model form, Annexure 1)
// =====================================================================
Future<({Uint8List bytes, String filename})> buildAllotmentLetterPdf(Map<String, dynamic> data) async {
  final a = _m(data['applicant']), u = _m(data['unit']), p = _m(data['project']);
  final now = DateTime.now();

  final name = '${_s(a['first_name'], '')} ${_s(a['last_name'], '')}'.trim();
  final addr = _s(a['full_address']);
  final uid = _s(a['unique_id']);
  final project = _s(p['project_name'], _defProject);
  final rera = _s(p['rera_registration_no'], _defRera);
  final developer = _s(p['developer_name'], _defDeveloper);
  final father = _s(a['father_name'], '').isNotEmpty ? _s(a['father_name']) : _s(a['spouse_name'], '-');
  final flat = _s(u['unit_number']);
  final carpet = _s(u['carpet_area_sqm'], '').isEmpty ? _blank : '${u['carpet_area_sqm']} Sq. Mtr.';
  final parkArea = _s(u['parking_area_sqm'], '').isEmpty ? _blank : '${u['parking_area_sqm']} Sq. Mtr.';
  final total = _num(u['consideration_amount']);

  // the booking payment: first completed payment
  final pays = ((data['payments'] as List?) ?? const []).map(_m).toList();
  final paidRow = pays.firstWhere((x) => '${x['payment_status']}' == 'completed', orElse: () => <String, dynamic>{});
  final paid = _num(paidRow['amount']);
  final payDate = _s(paidRow['payment_date'] ?? paidRow['created_at'], '').isEmpty ? _blank : _s(paidRow['payment_date'] ?? paidRow['created_at']).split('T').first;
  final aadhaar = formatAadhaar(a['aadhar_number']).isEmpty ? _blank : formatAadhaar(a['aadhar_number']);
  final pd = DateTime.tryParse(_s(p['possession_date'], '2028-12-31'));
  final possession = pd == null ? '31/12/2028' : _dmy(pd);

  final doc = _newDoc();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: _margin,
    build: (_) => [
      pw.Center(child: pw.Text('MODEL FORM OF ALLOTMENT LETTER', style: _t(size: 20, bold: true))),
      pw.SizedBox(height: 6),
      pw.Text('(As per MahaRERA Guidelines - Annexure 1)', style: _t(size: 10, color: PdfColors.grey700)),
      pw.SizedBox(height: 14),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [_rich('**Date:** ${_dmy(now)}'), _rich('**RERA No:** $rera')]),
      _p('**Ref No:** $uid/ALLOT/${now.year}'),
      pw.SizedBox(height: 8),
      _p('**To,**'),
      _p(name),
      _p(addr),
      _p('Mobile: ${_s(a['phone'])}'),
      _p('Email: ${_s(a['email'])}'),
      pw.SizedBox(height: 4),
      _p('**Sub:** Allotment of Flat No. $flat in $project'),
      _p('Dear Sir/Madam,'),
      _p('With reference to your application for booking of flat in our project "$project", we are pleased to inform you that Flat No. **$flat** has been provisionally allotted to you, subject to the terms and conditions mentioned herein and in the Agreement of Sale.'),
      _keep([
      _h('1. ALLOTTEE DETAILS', size: 14),
      _kv([
        ['Name of Allottee', name],
        ["Father's/Spouse's Name", father],
        ['Address', addr],
        ['Phone', _s(a['phone'])],
        ['Email', _s(a['email'])],
        ['PAN', _s(a['pan_number'])],
        ['Aadhar', aadhaar],
      ]),
      ]),
      _keep([
      _h('2. FLAT/UNIT DETAILS', size: 14),
      _kv([
        ['Project Name', project],
        ['Flat No.', flat],
        ['Floor', _s(u['floor'])],
        ['Wing', _s(u['wing'])],
        ['Tower/Building', _s(u['tower'])],
        ['Carpet Area', carpet],
      ]),
      ]),
      _keep([
      _h('3. PARKING DETAILS', size: 14),
      _kv([
        ['Parking No.', _s(u['parking_number'])],
        ['Type', _s(u['parking_type'])],
        ['Area', parkArea],
      ]),
      ]),
      _keep([
      _h('4. CONSIDERATION & PAYMENT DETAILS', size: 14),
      _kv([
        ['Total Consideration', _rs(total)],
        ['Amount Paid (Booking)', _rs(paid)],
        ['Payment Date', payDate],
        ['Receipt No.', _s(paidRow['receipt_number'])],
        ['Balance Amount', total == null || paid == null ? _blank : _rs(total - paid)],
      ]),
      ]),
      _keep([
      _h('5. POSSESSION DATE', size: 14),
      _p('The expected date of possession is **$possession**, subject to force majeure and timely payment of dues.'),
      ]),
      _keep([
      _h('6. TERMS & CONDITIONS', size: 14),
      _numbered([
        'This allotment is provisional and subject to execution of Agreement of Sale.',
        'The Allottee shall pay the balance consideration as per the payment schedule.',
        'GST, Stamp Duty, Registration charges shall be borne by the Allottee.',
        'This letter does not create any right, title or interest in the flat.',
        'The allotment is non-transferable without prior consent of the Promoter.',
      ]),
      ]),
      _keep([
      _h('7. CANCELLATION POLICY', size: 14),
      _grid([
        ['Time of Cancellation', 'Deduction'],
        ['Within 30 days of booking', '5% of booking amount'],
        ['After 30 days but before Agreement', '10% of total consideration'],
        ['After Agreement registration', '20% of total consideration'],
      ], widths: {0: const pw.FractionColumnWidth(0.5), 1: const pw.FractionColumnWidth(0.5)}),
      ]),
      pw.SizedBox(height: 6),
      _keep([
      _p('Please acknowledge receipt of this allotment letter by signing the duplicate copy and returning the same to us at the earliest.'),
      _p('Thanking you,'),
      _p('Yours faithfully,'),
      _p('For $developer'),
      pw.SizedBox(height: 30),
      _rule(width: 190),
      pw.SizedBox(height: 3),
      pw.Text('Authorized Signatory', style: _t()),
      ]),
      pw.SizedBox(height: 22),
      pw.Divider(color: PdfColors.grey400, thickness: 0.8),
      pw.SizedBox(height: 8),
      _keep([
      pw.Text('ACKNOWLEDGEMENT BY ALLOTTEE', style: _t(size: 13, bold: true)),
      _p('I/We hereby acknowledge receipt of this Allotment Letter and agree to abide by all the terms and conditions mentioned herein.'),
      pw.SizedBox(height: 10),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Row(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [pw.Text('Date: ', style: _t()), _rule(width: 120)]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _signLine('Signature of Allottee', width: 190),
          pw.SizedBox(height: 4),
          pw.Text('($name)', style: _t()),
        ]),
      ]),
      ]),
    ],
  ));
  return (bytes: await doc.save(), filename: 'allotment_${_s(a['unique_id'], 'doc')}.pdf');
}
