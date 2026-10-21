import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';
import 'dart:typed_data';
import '../web_open.dart';

int _stageNo(Map a) => int.tryParse(RegExp(r'stage_(\d+)').firstMatch('${a['registration_stage']}')?.group(1) ?? '') ?? 0;

bool _pending(Map a) => a['registration_stage'] == 'stage_6_agreement_receipt';
bool _approved(Map a) => _stageNo(a) >= 7;
bool _rejected(Map a) => a['stage_4_status'] == 'rejected' && _stageNo(a) == 5;

String _submitted(Map a) {
  for (final k in ['agreement_receipt_at', 'agreement_submitted_at', 'agreement_uploaded_at']) {
    final d = DateTime.tryParse('${a[k] ?? ''}')?.toLocal();
    if (d != null) return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
  return 'N/A';
}

class AgreementReceiptsPage extends StatefulWidget {
  const AgreementReceiptsPage({super.key});
  @override
  State<AgreementReceiptsPage> createState() => _AgreementReceiptsPageState();
}

class _AgreementReceiptsPageState extends State<AgreementReceiptsPage> {
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _err;
  int _tab = 0; // 0 pending, 1 approved, 2 rejected
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final r = await Api.i.get(Ep.list('', ''));
      _all = List<Map<String, dynamic>>.from(r['applicants'] ?? []).where((a) => _pending(a) || _approved(a) || _rejected(a)).toList();
    } catch (e) {
      _err = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _nP => _all.where(_pending).length;
  int get _nA => _all.where(_approved).length;
  int get _nR => _all.where(_rejected).length;

  List<Map<String, dynamic>> get _rows {
    final q = _q.trim().toLowerCase();
    final f = switch (_tab) { 0 => _pending, 1 => _approved, _ => _rejected };
    return _all.where(f).where((a) {
      if (q.isEmpty) return true;
      return '${a['unique_id']} ${fullName(a)} ${a['email']}'.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _view(Map a) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => AgreementReceiptDialog(id: '${a['id']}'));
    if (changed == true) _load();
  }

  Widget _stat(String label, int v, Color c, IconData icon) => Container(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kLine), boxShadow: kShadow),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 14, color: kMuted, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Text('$v', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: c, height: 1.1)),
            ]),
          ),
          Icon(icon, size: 20, color: c == kInk ? kMuted : c),
        ]),
      );

  Widget _stats(double w) {
    final cards = [
      _stat('Total Receipts', _all.length, kInk, Icons.description_outlined),
      _stat('Pending Review', _nP, const Color(0xFFD98B00), Icons.schedule_rounded),
      _stat('Approved', _nA, kGreen, Icons.task_outlined),
      _stat('Rejected', _nR, kRed, Icons.cancel_presentation_rounded),
    ];
    final cols = w >= 900 ? 4 : 2;
    final cw = (w - 20 * (cols - 1)) / cols;
    return Wrap(spacing: 20, runSpacing: 16, children: [for (final c in cards) SizedBox(width: cw, child: c)]);
  }

  Widget _tabBtn(int i, IconData icon, String label, int n) {
    final on = _tab == i;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _tab = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: on ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: on ? kInk : kMuted),
          const SizedBox(width: 8),
          Text('$label ($n)', style: TextStyle(fontSize: 14.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? kInk : kMuted)),
        ]),
      ),
    );
  }

  Widget _tabs() => Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: const Color(0xFFE4E9F2), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _tabBtn(0, Icons.schedule_rounded, 'Pending', _nP),
          _tabBtn(1, Icons.check_circle_outline_rounded, 'Approved', _nA),
          _tabBtn(2, Icons.cancel_outlined, 'Rejected', _nR),
        ]),
      );

  Widget _statusPill(Map a) {
    final (t, c) = _pending(a) ? ('Pending', kOrange) : (_approved(a) ? ('Approved', kGreen) : ('Rejected', kRed));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c)),
    );
  }

  Widget _table(List<Map<String, dynamic>> rows) {
    const hs = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: kMuted);
    return Panel(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth < 760 ? 760 : c.maxWidth),
            child: rows.isEmpty
                ? const Column(children: [
                    Padding(
                        padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
                        child: Row(children: [
                          Expanded(flex: 2, child: Text('Form No.', style: hs)),
                          Expanded(flex: 3, child: Text('Applicant', style: hs)),
                          Expanded(flex: 3, child: Text('Submitted On', style: hs)),
                          Expanded(flex: 2, child: Text('Status', style: hs)),
                          Expanded(flex: 2, child: Text('Actions', style: hs)),
                        ])),
                    Divider(height: 1, color: kLine),
                    Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: Text('No agreement receipts found', style: TextStyle(fontSize: 15.5, color: kMuted)))),
                  ])
                : DataTable(
                    showCheckboxColumn: false,
                    headingRowHeight: 60,
                    dataRowMinHeight: 78,
                    dataRowMaxHeight: 78,
                    horizontalMargin: 20,
                    columnSpacing: 40,
                    headingTextStyle: hs,
                    headingRowColor: const WidgetStatePropertyAll(Colors.white),
                    columns: const [
                      DataColumn(label: Text('Form No.')),
                      DataColumn(label: Text('Applicant')),
                      DataColumn(label: Text('Submitted On')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: [
                      for (final a in rows)
                        DataRow(cells: [
                          DataCell(Text('${a['unique_id'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w700, color: kInk, fontSize: 15))),
                          DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(fullName(a), style: const TextStyle(fontWeight: FontWeight.w700, color: kInk, fontSize: 15)),
                            Text('${a['email'] ?? '-'}', style: const TextStyle(color: kMuted, fontSize: 14)),
                          ])),
                          DataCell(Text(_submitted(a), style: const TextStyle(fontSize: 15, color: kInk))),
                          DataCell(_statusPill(a)),
                          DataCell(OutlinedButton.icon(
                            onPressed: () => _view(a),
                            icon: const Icon(Icons.visibility_outlined, size: 18),
                            label: const Text('View'),
                            style: OutlinedButton.styleFrom(foregroundColor: kInk, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
                          )),
                        ]),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        EmptyState(icon: Icons.cloud_off_rounded, title: 'Failed to load data', sub: _err!),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _load, child: const Text('Retry')),
      ]));
    }
    return LayoutBuilder(
      builder: (context, c) => ListView(children: [
        _stats(c.maxWidth),
        const SizedBox(height: 24),
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 12, children: [
          _tabs(),
          SizedBox(
            width: c.maxWidth < 520 ? c.maxWidth : 400,
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(hintText: 'Search by Form No., Name, Email...', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        _table(_rows),
      ]),
    );
  }
}

/// "Agreement Receipt Details" popup opened by the View button.
class AgreementReceiptDialog extends StatefulWidget {
  final String id;
  const AgreementReceiptDialog({super.key, required this.id});
  @override
  State<AgreementReceiptDialog> createState() => _AgreementReceiptDialogState();
}

class _AgreementReceiptDialogState extends State<AgreementReceiptDialog> {
  Map<String, dynamic>? _a;
  String? _err;
  Uint8List? _doc;
  bool _busy = false;
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.get(Ep.one(widget.id));
      final a = Map<String, dynamic>.from(r['applicant'] ?? {});
      Uint8List? bytes;
      if (a['agreement_receipt_path'] != null) {
        try {
          bytes = await Api.i.fileBytes(Ep.doc(widget.id, 'agreement_signed'));
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
        _a = a;
        _doc = bytes;
      });
      }
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    }
  }

  Future<void> _act(String action) async {
    final reason = _reason.text.trim();
    if (action == 'reject' && reason.isEmpty) {
      toast(context, 'Enter a reason for rejection', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.i.post(Ep.agreementReview(widget.id), {'action': action, 'reason': reason});
      if (!mounted) return;
      toast(context, action == 'accept' ? 'Agreement approved' : 'Agreement rejected');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, e.toString(), error: true);
      }
    }
  }

  Widget _kv(String k, String v) => Text.rich(TextSpan(children: [
        TextSpan(text: '$k: ', style: const TextStyle(color: kMuted)),
        TextSpan(text: v, style: const TextStyle(color: kInk, fontWeight: FontWeight.w600)),
      ]), style: const TextStyle(fontSize: 14.5));

  Widget _docView() {
    final b = _doc;
    if (b == null) return const Text('No document uploaded', style: TextStyle(fontSize: 16, color: kMuted));
    final pdf = b.length > 3 && b[0] == 0x25 && b[1] == 0x50;
    if (pdf) {
      return OutlinedButton.icon(onPressed: () => openBytes(b), icon: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: const Text('Open receipt (PDF)'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(color: kBg, constraints: const BoxConstraints(maxHeight: 320), width: double.infinity, child: Image.memory(b, fit: BoxFit.contain)),
      ),
      TextButton.icon(onPressed: () => openBytes(b), icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Open in new tab')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840, maxHeight: 720),
        child: _err != null
            ? Padding(padding: const EdgeInsets.all(30), child: Text(_err!, style: const TextStyle(color: kRed)))
            : a == null
                ? const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(30),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Agreement Receipt Details', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: kInk)),
                            const SizedBox(height: 4),
                            Text('${a['unique_id'] ?? '-'} - ${fullName(a)}', style: const TextStyle(fontSize: 15, color: kMuted)),
                          ]),
                        ),
                        InkWell(onTap: () => Navigator.pop(context), child: const Icon(Icons.close_rounded, color: kMuted, size: 22)),
                      ]),
                      const SizedBox(height: 22),
                      const Text('Applicant Information', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: kInk)),
                      const SizedBox(height: 12),
                      LayoutBuilder(builder: (context, c) {
                        final items = [
                          _kv('Name', fullName(a)),
                          _kv('Email', '${a['email'] ?? '-'}'),
                          _kv('Phone', '${a['phone'] ?? '-'}'),
                          _kv('Submitted', _submitted(a)),
                        ];
                        if (c.maxWidth < 520) {
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final i in items) Padding(padding: const EdgeInsets.only(bottom: 10), child: i)]);
                        }
                        return Column(children: [
                          Row(children: [Expanded(child: items[0]), Expanded(child: items[1])]),
                          const SizedBox(height: 14),
                          Row(children: [Expanded(child: items[2]), Expanded(child: items[3])]),
                        ]);
                      }),
                      const SizedBox(height: 22),
                      const Text('Uploaded Agreement Receipt', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: kInk)),
                      const SizedBox(height: 10),
                      _docView(),
                      if (Api.i.canReview && a['registration_stage'] == 'stage_6_agreement_receipt') ...[
                        const SizedBox(height: 18),
                        TextField(controller: _reason, maxLines: 2, decoration: const InputDecoration(hintText: 'Rejection reason (required to reject)')),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: FilledButton(onPressed: _busy ? null : () => _act('accept'), child: const Text('Approve'))),
                          const SizedBox(width: 12),
                          Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: kRed), onPressed: _busy ? null : () => _act('reject'), child: const Text('Reject'))),
                        ]),
                      ],
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(foregroundColor: kInk, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
                          child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ]),
                  ),
      ),
    );
  }
}