import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// SIMPLE MORTGAGE DEED, built from the approved draft (clauses 1-12 + schedule).
/// Used only when the admin has filled in the deed details (data['deed'] is not empty);
/// otherwise pdf_docs.dart keeps printing the old mortgage document.
///
/// The default PDF font has no rupee glyph, so amounts print as "Rs.".

const _blank = '____________';

String _t(Map m, String k) {
  final v = m[k];
  return (v == null || v.toString().trim().isEmpty) ? '' : v.toString().trim();
}

String _v(Object? v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? _blank : s;
}

String _rs(Object? v) {
  final s = (v ?? '').toString().replaceAll(',', '').trim();
  final n = num.tryParse(s);
  if (n == null) return s.isEmpty ? _blank : s;
  return 'Rs. ${NumberFormat.decimalPattern('en_IN').format(n)}/-';
}

String _dateLong(String s) {
  final d = DateTime.tryParse(s);
  return d == null ? (s.isEmpty ? _blank : s) : DateFormat('dd MMMM yyyy').format(d);
}

Future<({Uint8List bytes, String filename})> buildMortgageDeedPdf(Map<String, dynamic> data,
    {Uint8List? signature}) async {
  final a = Map<String, dynamic>.from(data['applicant'] ?? {});
  final u = Map<String, dynamic>.from(data['unit'] ?? {});
  final p = Map<String, dynamic>.from(data['project'] ?? {});
  final d = Map<String, dynamic>.from(data['deed'] ?? {});
  final sc = Map<String, dynamic>.from(data['schedule'] ?? {});

  // boundaries: per-applicant value wins, otherwise the project default
  String bound(String k) => _t(d, k).isNotEmpty ? _t(d, k) : _t(sc, k);

  final name = '${a['first_name'] ?? ''} ${a['last_name'] ?? ''}'.trim();
  final place = _v(_t(d, 'exec_place'));
  final date = _dateLong(_t(d, 'exec_date'));
  final loanAmt = _rs(_t(d, 'loan_amount'));
  final bankName = _t(d, 'bank_name').isNotEmpty ? _t(d, 'bank_name') : _t(p, 'bank_name');
  final bankBranch = _t(d, 'bank_branch').isNotEmpty ? _t(d, 'bank_branch') : _t(p, 'bank_branch');
  final building = _t(u, 'building_name').isNotEmpty ? _t(u, 'building_name') : _t(p, 'project_name');
  final instType = _t(d, 'installment_type').isEmpty ? 'monthly' : _t(d, 'installment_type');

  final intro = <String>[
    'This deed of mortgage made and executed on $date at $place between',
    '${_v(name)}, Age ${_v(a['age'])}, Occupation ${_v(a['occupation'])}, Residing At ${_v(a['full_address'])}, '
        'PAN ${_v(a['pan_number'])}, UID ${_v(a['aadhar_number'])}, Mobile No. ${_v(a['phone'])}, Email id ${_v(a['email'])}, '
        'HEREINAFTER Called "the Mortgager" (which expression shall unless excluded by or repugnant to the subject to the context include '
        'his/her heirs, executors administrators representative assigns and transferee in interest of the) one part AND',
    '${_v(bankName)}, represented by its Authorized Signatory ${_v(_t(d, 'signatory_designation'))}, Bank Address: ${_v(_t(d, 'bank_address'))}, '
        'Branch at ${_v(bankBranch)}, TAN No: ${_v(_t(d, 'bank_tan'))}, UID ${_v(_t(d, 'bank_uid'))}, Mobile No. ${_v(_t(d, 'bank_mobile'))}, '
        'Email id ${_v(_t(d, 'bank_email'))} hereinafter called the "Mortgagee" (which expression shall unless excluded by or repugnant to the '
        'subject or context include its successors, transferees-in-interest and assigns) the other part.',
  ];

  final recitals = <String>[
    "AND WHEREAS the mortgagor is the sole and absolute owner of immovable Property described in Schedule hereunder, and hereinafter referred to as the 'said Property'",
    'Whereas, the Mortgagor is the absolute owner, having acquired the property, by ${_v(_t(d, 'ownership_by'))} and since then Mortgagor has been in possession and enjoyment of the schedule property and paying taxes and levies thereon, as sole and absolute owner thereof.',
    'Whereas Mortgagor being in need of money for the purpose of ${_v(_t(d, 'loan_purpose').isEmpty ? 'Purchase of flat' : _t(d, 'loan_purpose'))}. Mortgagor requested the Mortgagee to lend him a sum of $loanAmt which the Mortgagee has agreed to do on the Mortgagor executing these presents with a view to secure the repayment thereof with interest as hereinafter provided.',
    'AND WHEREAS mortgagor assured unto the mortgagee that he/she would pay the said amount which is an outstanding debt payable from the mortgagor to the mortgagee along with interest thereon;',
    'AND WHEREAS the mortgagees have agreed to grant loan up to $loanAmt FROM TIME TO TIME to the mortgagors agreeing to utilize the amounts so advanced for the purpose applied for and on such terms and conditions as the mortgagees may stipulate from time to time and on the mortgagees securing the same by executing a mortgage of their immovable property',
    'AND WHEREAS the mortgagee agreed to give time to the mortgagor so as to enable him/her/them to make the payment of the aforesaid debt; however, the mortgagee insisted on the mortgagor so as to furnish unto the mortgagee security for this payment of debt;',
    'AND WHEREAS considering the cooperation extended by the mortgagee by giving time to the mortgagor the payment of the aforesaid debt, the mortgagor readily agreed to confer such a security unto the mortgagee;',
    'AND WHEREAS the parties hereto had due deliberations and discussions, and the mortgagor has agreed to mortgage the said property in favour of the mortgagee as a collateral security;',
    'AND WHEREAS the parties hereto have arrived at an understanding which they have decided to reduce into writing being these presents;',
  ];

  final extra = _t(d, 'extra_terms');
  final clauses = <String>[
    '1) That the mortgagor does hereby mortgage the said property in favour of the mortgagee subject to the terms and conditions stated in this deed.',
    '2) That the mortgagor is liable to pay unto the mortgagee an amount of $loanAmt as a debt, and for the purpose of securing repayment of this debt, mortgage the said property in favour of the mortgagee.',
    '3) That the mortgagor hereby agrees to repay the said amount of debt within a period of ${_v(_t(d, 'loan_period_years'))} years from execution of these present.',
    '4) That the mortgagor hereby assures to pay unto the mortgagee the said amount of $loanAmt along with interest thereon at the rate of ${_v(_t(d, 'interest_rate'))}% per annum.'
        '${_t(d, 'installment_amount').isEmpty ? '' : ' And the Mortgagor would also repay loan amount with interest to Mortgagee at ${_rs(_t(d, 'installment_amount'))} $instType installment.'}',
    '5) That the mortgagor assures unto the mortgagee that the said property is his/her absolute property, and no one else has any right, title or interest in the same. The mortgagor hereby assures unto the mortgagee that the said property is free from any encumbrances.',
    '6) That the mortgagor hereby assures unto the mortgagee that he/she will not deal with the said property in any manner so as to prejudicially affect the rights of the mortgagee.',
    '7) And it is further agreed and declared by the Mortgagor that he shall also be liable to pay and shall pay all the costs, charges and expenses that the Mortgagee will incur for the protection of the mortgage security and or for the realization of the mortgage amount and the same shall be deemed to form part of the mortgage amount and the security therefore as aforesaid',
    '8) And it is further agreed that during the pending of the security hereby created and until repayment of the mortgage amount, the Mortgagor will get insured and keep insured the said scheduled property from any loss and damages due to fire or any other incident in the sum of at least ${_rs(_t(d, 'insurance_amount'))} with some Insurance Company of repute and pay all premium in the insurance policy as and when it becomes due and payable in respect thereof to such company and shall hand over the policy to the Mortgagee duly endorsed in his name as assignee and in the event of the Mortgagor failing to do so or to pay the premium, the Mortgagee will be entitled to insure the said property and structures and/or to pay the premium thereon and the amount paid by the Mortgagee in respect thereof will be deemed to form part of the mortgage amount.',
    '9) That in the event, if the mortgagor fails to repay the aforesaid amount of debt along with interest thereon, then the mortgagee shall be entitled to claim foreclosure of the mortgage, and in the default of the mortgagor, the mortgagee shall be entitled to enforce all such remedies available against the mortgagor as are available to the mortgagee under simple mortgage.',
    '10) All the obligations of the Mortgagor and all the rights and remedies and powers of the Mortgagee under the law for the time being in force except so far as they be expressly varied or may be inconsistent with these presents shall be deemed to be incorporated in these presents. PROVIDED THAT the provision of Sections 61, 65A and 67A, respectively, of the Transfer of Property Act, 1882, shall not apply to these presents or to the Mortgagor or the Mortgagee inters and this shall be deemed a contract to the contrary for the purpose of these sections.',
    '11) The Mortgagor confirms and declares that he/she has actual possession of the Mortgaged Premises and has absolute power and authority to mortgage the Mortgaged Premises in favour of the Mortgagee and provided that the possession of the said mortgaged property is / will neither be given nor agreed to be given to Mortgagee except in the event of default.',
    if (extra.isNotEmpty) '11A) $extra',
    '12) That all the expenses towards stamp duty, registration charges and incidental expenses thereto were agreed to be borne out by the mortgagor, and accordingly he/she has done so.',
  ];

  final authority = _t(sc, 'authority_name').isEmpty
      ? _blank
      : '${_t(sc, 'authority_name')}${_t(sc, 'authority_type').isEmpty ? '' : ' (${_t(sc, 'authority_type')})'}';
  final survey = _t(sc, 'survey_no').isEmpty ? _blank : '${_t(sc, 'survey_type').isEmpty ? 'Survey No.' : _t(sc, 'survey_type')} ${_t(sc, 'survey_no')}';
  final schedule =
      'All that piece and parcel of land situated within Registration Division and District ${_v(_t(sc, 'district'))} Sub-Division and Taluka ${_v(_t(sc, 'taluka'))} '
      'within the limits of $authority situate At. Village ${_v(_t(sc, 'village'))} $survey Hissa/Plot No. ${_v(_t(sc, 'plot_no'))} '
      'With Constructed Building name as ${_v(building)} Flat No./House No. ${_v(u['unit_number'])} Floor No. ${_v(u['floor'])} '
      'Area ${_v(u['carpet_area_sqm'])} sqmts. And bounded by as follows:';

  const body = pw.TextStyle(fontSize: 10, lineSpacing: 2.5);
  const bold = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);

  pw.Widget para(String t, {pw.TextStyle style = body, pw.TextAlign align = pw.TextAlign.justify, double gap = 7}) =>
      pw.Padding(padding: pw.EdgeInsets.only(bottom: gap), child: pw.Text(t, style: style, textAlign: align));

  pw.Widget sigBlock(String label, String who, {Uint8List? img, String? note, String? sub}) => pw.Container(
        width: 210,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(height: img == null ? 34 : 0),
          if (img != null) pw.Image(pw.MemoryImage(img), width: 130, height: 50, fit: pw.BoxFit.contain),
          pw.Container(height: 0.5, color: PdfColors.black),
          pw.SizedBox(height: 3),
          pw.Text(label, style: bold),
          pw.Text(_v(who), style: const pw.TextStyle(fontSize: 9)),
          if (sub != null && sub.isNotEmpty) pw.Text(sub, style: const pw.TextStyle(fontSize: 9)),
          if (note != null) pw.Text(note, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        ]),
      );

  final signedNote = signature == null
      ? null
      : 'e-Signed on ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}';

  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(46, 42, 46, 42),
    footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight, child: pw.Text('Page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))),
    build: (_) => [
      para('SIMPLE MORTGAGE DEED', style: const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold), align: pw.TextAlign.center, gap: 16),
      for (final t in intro) para(t),
      for (final t in recitals) para(t),
      para('NOW, THIS DEED WITNESS as follows:', style: bold),
      for (final t in clauses) para(t),
      para('THE SCHEDULE OF THE PROPERTY ABOVE REFERRED TO', style: bold, align: pw.TextAlign.center, gap: 8),
      para(schedule),
      para('On or towards the East : ${_v(bound('east'))}', gap: 3),
      para('On or towards the South : ${_v(bound('south'))}', gap: 3),
      para('On or towards the West : ${_v(bound('west'))}', gap: 3),
      para('On or towards the North : ${_v(bound('north'))}', gap: 14),
      para('IN WITNESS WHEREOF the parties hereto have signed hereunder at $place on this $date.', gap: 22),
      pw.Wrap(spacing: 30, runSpacing: 24, children: [
        sigBlock("MORTGAGOR'S Name and SIGN", name, img: signature, note: signedNote),
        sigBlock("MORTGAGEE'S Name and SIGN", _t(d, 'signatory_name'), sub: _t(d, 'signatory_designation')),
      ]),
      pw.SizedBox(height: 22),
      para('WITNESSES:', style: bold, gap: 10),
      pw.Wrap(spacing: 30, runSpacing: 24, children: [
        sigBlock('1. Name and sign', _t(d, 'witness1_name'), sub: _t(d, 'witness1_address')),
        sigBlock('2. Name and sign', _t(d, 'witness2_name'), sub: _t(d, 'witness2_address')),
      ]),
    ],
  ));
  return (bytes: await doc.save(), filename: 'mortgage_deed_${_t(a, 'unique_id').isEmpty ? 'doc' : _t(a, 'unique_id')}.pdf');
}