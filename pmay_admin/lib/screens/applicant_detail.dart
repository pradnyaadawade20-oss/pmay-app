import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';
import '../web_open.dart';

class ApplicantDetail extends StatefulWidget {
  final String id;
  const ApplicantDetail({super.key, required this.id});
  @override
  State<ApplicantDetail> createState() => _ApplicantDetailState();
}

class _ApplicantDetailState extends State<ApplicantDetail> {
  Map<String, dynamic>? _a;
  List _pays = [];
  Map<String, dynamic>? _loan, _unit;
  Map<String, String> _extra = {}; // later-stage documents that exist: kind -> label
  String? _err;
  bool _busy = false;
  final _reason = TextEditingController();
  Map<String, Future<Uint8List>> _docFut = {}; // applicant's uploaded documents, loaded from the backend

  @override
  void initState() {
    super.initState();
    Api.i.get(Ep.one(widget.id)).then((r) {
      if (!mounted) return;
      setState(() {
        _a = Map<String, dynamic>.from(r['applicant'] ?? {});
        _pays = List.from(r['payments'] ?? []);
        _loan = r['loan'] is Map ? Map<String, dynamic>.from(r['loan']) : null;
        _unit = r['unit'] is Map ? Map<String, dynamic>.from(r['unit']) : null;
        _extra = _laterDocs(_a!, _loan, r['uploads']);
        _docFut = {for (final k in [...docKinds.keys, ..._extra.keys]) k: Api.i.fileBytes(Ep.doc(widget.id, k))};
      });
    }).catchError((e) {
      if (mounted) setState(() => _err = e.toString());
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  static bool _isPdf(Uint8List b) => b.length > 3 && b[0] == 0x25 && b[1] == 0x50;

  /// Large view of a document image.
  void _viewDoc(String label, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk))),
                TextButton.icon(onPressed: () => openBytes(bytes), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Open in new tab')),
                IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close_rounded, color: kMuted)),
              ]),
              const SizedBox(height: 10),
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: kBg,
                    width: double.infinity,
                    child: InteractiveViewer(maxScale: 5, child: Image.memory(bytes, fit: BoxFit.contain)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// One document card: shows the image uploaded by the applicant.
  Widget _docTile(String kind, String label) => SizedBox(
        width: 240,
        child: FutureBuilder<Uint8List>(
          future: _docFut[kind],
          builder: (context, snap) {
            final bytes = snap.data;
            final loading = snap.connectionState != ConnectionState.done;
            final pdf = bytes != null && _isPdf(bytes);
            Widget placeholder(IconData i, String t, [Color c = kMuted]) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(i, size: 34, color: c),
                  const SizedBox(height: 6),
                  Text(t, style: TextStyle(fontSize: 12.5, color: c)),
                ]);
            final Widget preview = loading
                ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                : bytes == null
                    ? placeholder(Icons.image_not_supported_outlined, 'Not uploaded')
                    : pdf
                        ? placeholder(Icons.picture_as_pdf_rounded, 'PDF document', kRed)
                        : Image.memory(bytes,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, __, ___) => placeholder(Icons.broken_image_outlined, 'Cannot preview'));
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: bytes == null ? null : () => pdf ? openBytes(bytes) : _viewDoc(label, bytes),
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kLine)),
                clipBehavior: Clip.antiAlias,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(height: 150, width: double.infinity, color: kBg, child: preview),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: kInk))),
                      if (bytes != null) Icon(pdf ? Icons.open_in_new_rounded : Icons.zoom_in_rounded, size: 18, color: kMuted),
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
      );

  /// Documents uploaded after registration (agreement, bank, loan, mortgage) that exist for this applicant.
  static Map<String, String> _laterDocs(Map<String, dynamic> a, Map<String, dynamic>? loan, [Object? uploads]) {
    final m = <String, String>{};
    if (a['agreement_receipt_path'] != null) m['agreement_signed'] = 'Signed agreement';
    // extra files of the same signed agreement (agreement_signed_2, _3 ...)
    final extra = <String>[];
    for (final u in (uploads as List?) ?? const []) {
      final t = u is Map ? '${u['upload_type']}' : '';
      if (RegExp(r'^agreement_signed_\d+$').hasMatch(t) && !extra.contains(t)) extra.add(t);
    }
    extra.sort((x, y) => (int.tryParse(x.split('_').last) ?? 0).compareTo(int.tryParse(y.split('_').last) ?? 0));
    for (final t in extra) {
      m[t] = 'Signed agreement (${t.split('_').last})';
    }
    if (loan != null) {
      const l = {
        'upi_statement': 'UPI statement',
        'itr_year1': 'ITR - year 1',
        'itr_year2': 'ITR - year 2',
        'itr_year3': 'ITR - year 3',
        'bank_statement': 'Bank statement',
      };
      l.forEach((k, v) {
        if (loan['${k}_path'] != null) m[k] = v;
      });
    }
    if (a['bank_loan_receipt_path'] != null) m['bank_loan_receipt'] = 'Bank loan receipt';
    if (a['mortgage_receipt_path'] != null) m['mortgage_receipt'] = 'Mortgage receipt';
    return m;
  }

  bool get _bankDocsComplete =>
      _loan != null && ['upi_statement', 'itr_year1', 'itr_year2', 'itr_year3', 'bank_statement'].every((k) => _loan!['${k}_path'] != null);

  /// accept/reject for the agreement receipt (stage 6) and bank documents (stage 7).
  Future<void> _reviewAt(String path, String action, String okMsg) async {
    final reason = _reason.text.trim();
    if (action == 'reject' && reason.isEmpty) {
      toast(context, 'Enter a reason for rejection', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.i.post(path, {'action': action, 'reason': reason});
      if (!mounted) return;
      toast(context, action == 'accept' ? okMsg : 'Rejected - the applicant has been asked to resubmit');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        toast(context, e.toString(), error: true);
        setState(() => _busy = false);
      }
    }
  }

  /// Approve / reject panel with a reason box; [go] is called with 'accept' or 'reject'.
  Widget _reviewBox(String title, String hint, void Function(String) go) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 22),
        SectionTitle(title, Icons.fact_check_outlined),
        const SizedBox(height: 12),
        _box(
          color: kOrange.withValues(alpha: 0.06),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hint, style: const TextStyle(color: kMuted)),
            const SizedBox(height: 12),
            TextField(controller: _reason, maxLines: 2, decoration: const InputDecoration(hintText: 'Reason / notes (required to reject)')),
            const SizedBox(height: 14),
            Row(children: [
              FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kGreen),
                  onPressed: _busy ? null : () => go('accept'),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Approve')),
              const SizedBox(width: 10),
              FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kRed),
                  onPressed: _busy ? null : () => go('reject'),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Reject')),
            ]),
          ]),
        ),
      ]);

  Future<void> _review(String decision) async {
    final reason = _reason.text.trim();
    if (decision == 'reject' && reason.isEmpty) {
      toast(context, 'Enter a reason for rejection', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.i.post(Ep.review(widget.id), {'decision': decision, 'reason': reason});
      if (!mounted) return;
      toast(context, decision == 'approve' ? 'Documents approved' : 'Application rejected');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        toast(context, e.toString(), error: true);
        setState(() => _busy = false);
      }
    }
  }

  Widget _kv(String k, Object? v, {double w = 230}) => SizedBox(
        width: w,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k.toUpperCase(), style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 3),
          Text((v == null || '$v'.isEmpty) ? '-' : '$v', style: const TextStyle(color: kInk, fontWeight: FontWeight.w500)),
        ]),
      );

  Widget _box({required Widget child, Color? color}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: color ?? const Color(0xFFF8FAFD), borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final a = _a;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 700),
        child: _err != null
            ? Padding(padding: const EdgeInsets.all(30), child: Text(_err!, style: const TextStyle(color: kRed)))
            : a == null
                ? const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))
                : Column(children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 12, 20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [kNavy, kBlue]),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(children: [
                        Avatar(fullName(a), size: 54),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(fullName(a), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text('${a['unique_id'] ?? ''}', style: const TextStyle(color: Colors.white70)),
                          ]),
                        ),
                        Container(
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                            child: stagePill(a)),
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
                      ]),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const SectionTitle('Personal information', Icons.badge_outlined),
                          const SizedBox(height: 12),
                          _box(
                            child: Wrap(spacing: 24, runSpacing: 18, children: [
                              _kv('Phone', a['phone']),
                              _kv('Email', a['email'], w: 280),
                              _kv('Date of birth', a['date_of_birth']),
                              _kv("Father's name", a['father_name']),
                              _kv("Spouse's name", a['spouse_name']),
                              _kv('Blood group', a['blood_group']),
                              _kv('Occupation', a['occupation']),
                              _kv('Aadhaar', a['aadhar_number']),
                              _kv('PAN', a['pan_number']),
                              _kv('Address', a['full_address'], w: 520),
                            ]),
                          ),
                          const SizedBox(height: 22),
                          const SectionTitle('Documents', Icons.folder_open_rounded),
                          const SizedBox(height: 12),
                          Wrap(spacing: 10, runSpacing: 10, children: [
                            for (final e in docKinds.entries) _docTile(e.key, e.value),
                          ]),
                          if (_extra.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            const SectionTitle('Agreement, bank and receipt documents', Icons.folder_copy_outlined),
                            const SizedBox(height: 12),
                            Wrap(spacing: 10, runSpacing: 10, children: [for (final e in _extra.entries) _docTile(e.key, e.value)]),
                          ],
                          if (_unit != null) ...[
                            const SizedBox(height: 22),
                            const SectionTitle('Allotted unit', Icons.home_work_outlined),
                            const SizedBox(height: 12),
                            _box(
                              child: Wrap(spacing: 24, runSpacing: 18, children: [
                                _kv('Unit', _unit!['unit_number']),
                                _kv('Tower', _unit!['tower']),
                                _kv('Floor', _unit!['floor']),
                                _kv('Carpet area (sq m)', _unit!['carpet_area_sqm']),
                                _kv('Amount', _unit!['consideration_amount']),
                              ]),
                            ),
                          ],
                          if (a['stage_2_status'] == 'rejected') ...[
                            const SizedBox(height: 22),
                            _box(
                              color: kRed.withValues(alpha: 0.06),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Icon(Icons.cancel_rounded, color: kRed),
                                const SizedBox(width: 10),
                                Expanded(child: Text('Rejected: ${a['stage_2_reason'] ?? ''}', style: const TextStyle(color: kRed, fontWeight: FontWeight.w600))),
                              ]),
                            ),
                          ],
                          if (Api.i.canReview && a['registration_stage'] == 'stage_1_registered' && a['stage_2_status'] != 'rejected') ...[
                            const SizedBox(height: 22),
                            const SectionTitle('Document verification', Icons.fact_check_outlined),
                            const SizedBox(height: 12),
                            _box(
                              color: kOrange.withValues(alpha: 0.06),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('Review the documents, then approve, or reject with a reason.', style: TextStyle(color: kMuted)),
                                const SizedBox(height: 12),
                                TextField(controller: _reason, maxLines: 2, decoration: const InputDecoration(hintText: 'Rejection reason (required to reject)')),
                                const SizedBox(height: 14),
                                Row(children: [
                                  FilledButton.icon(
                                      style: FilledButton.styleFrom(backgroundColor: kGreen),
                                      onPressed: _busy ? null : () => _review('approve'),
                                      icon: const Icon(Icons.check_rounded, size: 18),
                                      label: const Text('Approve')),
                                  const SizedBox(width: 10),
                                  FilledButton.icon(
                                      style: FilledButton.styleFrom(backgroundColor: kRed),
                                      onPressed: _busy ? null : () => _review('reject'),
                                      icon: const Icon(Icons.close_rounded, size: 18),
                                      label: const Text('Reject')),
                                ]),
                              ]),
                            ),
                          ],
                          if (a['stage_4_status'] == 'rejected' && a['registration_stage'] == 'stage_5_agreement')
                            Padding(
                                padding: const EdgeInsets.only(top: 22),
                                child: _box(
                                    color: kRed.withValues(alpha: 0.06),
                                    child: Text('Agreement rejected: ${a['stage_4_reason'] ?? ''}', style: const TextStyle(color: kRed, fontWeight: FontWeight.w600)))),
                          if (_loan != null && _loan!['loan_status'] == 'rejected')
                            Padding(
                                padding: const EdgeInsets.only(top: 22),
                                child: _box(
                                    color: kRed.withValues(alpha: 0.06),
                                    child: Text('Bank documents rejected: ${_loan!['verification_notes'] ?? ''}', style: const TextStyle(color: kRed, fontWeight: FontWeight.w600)))),
                          if (Api.i.canReview && a['registration_stage'] == 'stage_6_agreement_receipt')
                            _reviewBox('Agreement review', 'Check the signed agreement, then approve, or reject with a reason so the applicant can upload again.',
                                (act) => _reviewAt(Ep.agreementReview(widget.id), act, 'Agreement approved')),
                          if (Api.i.canReview && a['registration_stage'] == 'stage_7_bank_document' && _bankDocsComplete && _loan!['loan_status'] != 'rejected')
                            _reviewBox('Bank documents review', 'Check the UPI statement, 3 ITRs and bank statement, then approve, or reject with a reason.',
                                (act) => _reviewAt(Ep.bankReview(widget.id), act, 'Bank documents approved')),
                          const SizedBox(height: 22),
                          const SectionTitle('Payments', Icons.account_balance_wallet_outlined),
                          const SizedBox(height: 12),
                          _box(
                            child: _pays.isEmpty
                                ? const Text('No payments yet', style: TextStyle(color: kMuted))
                                : Column(children: [
                                    for (final p in _pays)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Row(children: [
                                          Text('₹${p['amount']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kInk)),
                                          const Spacer(),
                                          Pill('${p['payment_status']}', p['payment_status'] == 'pending' ? kOrange : kGreen),
                                        ]),
                                      ),
                                  ]),
                          ),
                        ]),
                      ),
                    ),
                  ]),
      ),
    );
  }
}