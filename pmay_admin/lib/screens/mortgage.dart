import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';
import '../web_open.dart';

/// Mortgage stage: applicants at Stage 9 (mortgage deed to be signed & receipt uploaded)
/// and Stage 10 (completed, receipt uploaded). Read-only: the receipt moves the applicant
/// straight to Completed, so there is no approve/reject step here.
bool _awaiting(Map a) => a['registration_stage'] == 'stage_9_mortgage';
bool _completed(Map a) => a['registration_stage'] == 'stage_10_completed';

String _fmtD(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
  return d == null ? 'N/A' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _fmtDT(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
  if (d == null) return 'N/A';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.month}/${d.day}/${d.year}, $h:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

class MortgagePage extends StatefulWidget {
  const MortgagePage({super.key});
  @override
  State<MortgagePage> createState() => _MortgagePageState();
}

class _MortgagePageState extends State<MortgagePage> {
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _err;
  int _tab = 0; // 0 awaiting receipt, 1 completed
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
      _all = List<Map<String, dynamic>>.from(r['applicants'] ?? []).where((a) => _awaiting(a) || _completed(a)).toList();
    } catch (e) {
      _err = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _nA => _all.where(_awaiting).length;
  int get _nC => _all.where(_completed).length;

  List<Map<String, dynamic>> get _rows {
    final q = _q.trim().toLowerCase();
    return _all.where(_tab == 0 ? _awaiting : _completed).where((a) {
      if (q.isEmpty) return true;
      return '${a['unique_id']} ${fullName(a)} ${a['email']} ${a['phone']}'.toLowerCase().contains(q);
    }).toList();
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
      _stat('Total', _all.length, kInk, Icons.gavel_rounded),
      _stat('Awaiting Receipt', _nA, const Color(0xFFD98B00), Icons.schedule_rounded),
      _stat('Completed', _nC, kGreen, Icons.task_outlined),
    ];
    final cols = w >= 760 ? 3 : 1;
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
          _tabBtn(0, Icons.schedule_rounded, 'Awaiting Receipt', _nA),
          _tabBtn(1, Icons.check_circle_outline_rounded, 'Completed', _nC),
        ]),
      );

  Widget _pill(Map a) {
    final (t, c) = _completed(a) ? ('Completed', kGreen) : ('Awaiting Receipt', kOrange);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c)),
    );
  }

  Future<void> _view(Map a) => showDialog<void>(context: context, builder: (_) => MortgageDialog(id: '${a['id']}'));

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
                ? SizedBox(
                    width: c.maxWidth < 760 ? 760 : c.maxWidth,
                    child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: Text('No mortgage records found', style: TextStyle(fontSize: 15.5, color: kMuted)))))
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
                      DataColumn(label: Text('Signed On')),
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
                          DataCell(Text(_completed(a) ? _fmtD(a['mortgage_deed_signed_at'] ?? a['updated_at']) : '-', style: const TextStyle(fontSize: 15, color: kInk))),
                          DataCell(_pill(a)),
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
              decoration: const InputDecoration(hintText: 'Search by Form No., Name, Email, Phone...', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        _table(_rows),
      ]),
    );
  }
}

/// Details popup: applicant info + mortgage receipt (image shown inline, PDF opens in a new tab).
class MortgageDialog extends StatefulWidget {
  final String id;
  const MortgageDialog({super.key, required this.id});
  @override
  State<MortgageDialog> createState() => _MortgageDialogState();
}

class _MortgageDialogState extends State<MortgageDialog> {
  Map<String, dynamic>? _a;
  Map<String, dynamic> _loan = {};
  Uint8List? _doc;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.get(Ep.one(widget.id));
      final a = Map<String, dynamic>.from(r['applicant'] ?? {});
      final loan = Map<String, dynamic>.from((r['loan'] as Map?) ?? {});
      Uint8List? bytes;
      if ('${a['mortgage_receipt_path'] ?? ''}'.isNotEmpty) {
        try {
          bytes = await Api.i.fileBytes(Ep.doc(widget.id, 'mortgage_receipt'));
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _a = a;
          _loan = loan;
          _doc = bytes;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    }
  }

  Widget _kv(String k, Object? v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
          TextSpan(text: (v == null || '$v'.isEmpty) ? '-' : '$v', style: const TextStyle(color: kInk)),
        ]), style: const TextStyle(fontSize: 13.5)),
      );

  Widget _docView() {
    final b = _doc;
    if (b == null) return const Text('Mortgage receipt not uploaded yet', style: TextStyle(fontSize: 14, color: kMuted));
    final pdf = b.length > 3 && b[0] == 0x25 && b[1] == 0x50;
    if (pdf) {
      return OutlinedButton.icon(
          onPressed: () => openBytes(b), icon: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: const Text('Open mortgage receipt (PDF)'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(color: kBg, constraints: const BoxConstraints(maxHeight: 340), width: double.infinity, child: Image.memory(b, fit: BoxFit.contain)),
      ),
      TextButton.icon(onPressed: () => openBytes(b), icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Open in new tab')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final done = a != null && _completed(a);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: _err != null
            ? Padding(padding: const EdgeInsets.all(30), child: Text(_err!, style: const TextStyle(color: kRed)))
            : a == null
                ? const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            Text('Mortgage: ${a['unique_id'] ?? '-'}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
                            Pill(done ? 'Completed' : 'Awaiting Receipt', done ? kGreen : kOrange),
                          ]),
                        ),
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: kMuted)),
                      ]),
                      const Text('Applicant details and mortgage receipt', style: TextStyle(fontSize: 12.5, color: kMuted)),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kLine)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                          const SizedBox(height: 12),
                          _kv('Name', fullName(a)),
                          _kv('Email', a['email']),
                          _kv('Phone', a['phone']),
                          if (_loan['loan_amount'] != null) _kv('Loan Amount', '₹ ${_loan['loan_amount']}'),
                          if (_loan['loan_status'] != null) _kv('Loan Status', _loan['loan_status']),
                          if (done) _kv('Mortgage Signed At', _fmtDT(a['mortgage_deed_signed_at'])),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kLine)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Mortgage Receipt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                          const SizedBox(height: 12),
                          _docView(),
                        ]),
                      ),
                    ]),
                  ),
      ),
    );
  }
}