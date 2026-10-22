import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';
import '../web_open.dart';

int _stageNo(Map a) => int.tryParse(RegExp(r'stage_(\d+)').firstMatch('${a['registration_stage']}')?.group(1) ?? '') ?? 0;

bool _rejected(Map a) => _stageNo(a) == 7 && ('${a['loan_status']}' == 'rejected' || '${a['bank_docs_status']}' == 'rejected');
bool _pending(Map a) => a['registration_stage'] == 'stage_7_bank_document' && !_rejected(a);
bool _approved(Map a) => _stageNo(a) >= 8;

/// Bank submission = UPI statement + 3 ITRs + bank statement (5 documents).
String _docs(Map a) {
  final n = a['bank_documents_count'] ?? a['bank_docs_count'] ?? 5;
  return '$n documents';
}

class BankDocumentsPage extends StatefulWidget {
  const BankDocumentsPage({super.key});
  @override
  State<BankDocumentsPage> createState() => _BankDocumentsPageState();
}

class _BankDocumentsPageState extends State<BankDocumentsPage> {
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
    final changed = await showDialog<bool>(context: context, builder: (_) => BankDocumentDialog(id: '${a['id']}'));
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
      _stat('Total Submissions', _all.length, kInk, Icons.description_outlined),
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
                ? SizedBox(
                    width: c.maxWidth < 760 ? 760 : c.maxWidth,
                    child: const Column(children: [
                    Padding(
                        padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
                        child: Row(children: [
                          Expanded(flex: 2, child: Text('Form No.', style: hs)),
                          Expanded(flex: 3, child: Text('Applicant', style: hs)),
                          Expanded(flex: 3, child: Text('Documents', style: hs)),
                          Expanded(flex: 2, child: Text('Status', style: hs)),
                          Expanded(flex: 2, child: Text('Actions', style: hs)),
                        ])),
                    Divider(height: 1, color: kLine),
                    Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: Text('No bank document submissions found', style: TextStyle(fontSize: 15.5, color: kMuted)))),
                  ]))
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
                      DataColumn(label: Text('Documents')),
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
                          DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.folder_copy_outlined, size: 17, color: kMuted),
                            const SizedBox(width: 8),
                            Text(_docs(a), style: const TextStyle(fontSize: 15, color: kInk)),
                          ])),
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

/// "Bank Document Review" popup: applicant info, the 5 bank documents (View Document),
/// notes and Reject / Approve (pending submissions only).
class BankDocumentDialog extends StatefulWidget {
  final String id;
  const BankDocumentDialog({super.key, required this.id});
  @override
  State<BankDocumentDialog> createState() => _BankDocumentDialogState();
}

class _BankDocumentDialogState extends State<BankDocumentDialog> {
  static const _docs = [
    ('upi_statement', 'UPI Statement'),
    ('itr_year1', 'ITR Year 1'),
    ('itr_year2', 'ITR Year 2'),
    ('itr_year3', 'ITR Year 3'),
    ('bank_statement', 'Bank Statement (6 months)'),
  ];

  Map<String, dynamic>? _a;
  Map<String, dynamic> _loan = {};
  String? _err;
  bool _busy = false;
  final _notes = TextEditingController();
  final _bytes = <String, Future<Uint8List>>{};

  @override
  void initState() {
    super.initState();
    Api.i.get(Ep.one(widget.id)).then((r) {
      if (!mounted) return;
      setState(() {
        _a = Map<String, dynamic>.from(r['applicant'] ?? {});
        _loan = r['loan'] is Map ? Map<String, dynamic>.from(r['loan']) : {};
        _notes.text = '${_loan['loan_status']}' == 'rejected' ? '${_loan['verification_notes'] ?? ''}' : '';
      });
    }).catchError((e) {
      if (mounted) setState(() => _err = e.toString());
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  bool _has(String kind) => '${_loan['${kind}_path'] ?? ''}'.isNotEmpty;
  bool get _complete => _docs.every((d) => _has(d.$1));
  bool get _canAct =>
      Api.i.canReview && _a != null && _a!['registration_stage'] == 'stage_7_bank_document' && _complete && '${_loan['loan_status']}' != 'rejected';

  Future<void> _view(String kind, String label) async {
    final f = _bytes.putIfAbsent(kind, () => Api.i.fileBytes(Ep.doc(widget.id, kind)));
    try {
      final b = Uint8List.fromList(await f);
      if (!mounted) return;
      final pdf = b.length > 3 && b[0] == 0x25 && b[1] == 0x50;
      if (pdf) {
        openBytes(b);
        return;
      }
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
                  TextButton.icon(onPressed: () => openBytes(b), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Open in new tab')),
                  IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close_rounded, color: kMuted)),
                ]),
                const SizedBox(height: 10),
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(color: kBg, width: double.infinity, child: InteractiveViewer(maxScale: 5, child: Image.memory(b, fit: BoxFit.contain))),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    } catch (e) {
      _bytes.remove(kind);
      if (mounted) toast(context, 'Document not available: $e', error: true);
    }
  }

  Future<void> _act(String action) async {
    final notes = _notes.text.trim();
    if (action == 'reject' && notes.isEmpty) {
      toast(context, 'Enter notes for rejection', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.i.post(Ep.bankReview(widget.id), {'action': action, 'reason': notes});
      if (!mounted) return;
      toast(context, action == 'accept' ? 'Bank documents approved' : 'Bank documents rejected');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        toast(context, e.toString(), error: true);
        setState(() => _busy = false);
      }
    }
  }

  Widget _kv(String k, String v) => Text.rich(TextSpan(children: [
        TextSpan(text: '$k:  ', style: const TextStyle(color: kMuted)),
        TextSpan(text: v, style: const TextStyle(color: kInk, fontWeight: FontWeight.w600)),
      ]), style: const TextStyle(fontSize: 13.5));

  Widget _docRow(String kind, String label) {
    final has = _has(kind);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: kLine)),
      child: Row(children: [
        const Icon(Icons.description_outlined, size: 18, color: kMuted),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk))),
        if (has)
          TextButton.icon(
              onPressed: () => _view(kind, label),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('View Document', style: TextStyle(fontSize: 13)))
        else
          const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Not uploaded', style: TextStyle(fontSize: 13, color: kMuted))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
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
                    padding: const EdgeInsets.all(24),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Bank Document Review', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: kInk)),
                            const SizedBox(height: 4),
                            Text('${a['unique_id'] ?? '-'} - ${fullName(a)}', style: const TextStyle(fontSize: 13.5, color: kMuted)),
                          ]),
                        ),
                        InkWell(onTap: () => Navigator.pop(context), child: const Icon(Icons.close_rounded, color: kMuted, size: 22)),
                      ]),
                      const SizedBox(height: 20),
                      const Text('Applicant Information', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: kInk)),
                      const SizedBox(height: 10),
                      LayoutBuilder(builder: (context, c) {
                        final items = [
                          _kv('Name', fullName(a)),
                          _kv('Email', '${a['email'] ?? '-'}'),
                          _kv('Phone', '${a['phone'] ?? '-'}'),
                          _kv('Stage', '${a['registration_stage'] ?? '-'}'),
                        ];
                        if (c.maxWidth < 480) {
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final i in items) Padding(padding: const EdgeInsets.only(bottom: 8), child: i)]);
                        }
                        return Column(children: [
                          Row(children: [Expanded(child: items[0]), Expanded(child: items[1])]),
                          const SizedBox(height: 12),
                          Row(children: [Expanded(child: items[2]), Expanded(child: items[3])]),
                        ]);
                      }),
                      const SizedBox(height: 20),
                      const Text('Uploaded Documents', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: kInk)),
                      const SizedBox(height: 10),
                      for (final d in _docs) _docRow(d.$1, d.$2),
                      const SizedBox(height: 8),
                      if (_canAct) ...[
                        const Text('Notes (Required for rejection)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kInk)),
                        const SizedBox(height: 6),
                        TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(hintText: 'Add notes about these bank documents...')),
                        const SizedBox(height: 14),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          OutlinedButton(
                              onPressed: _busy ? null : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(foregroundColor: kInk),
                              child: const Text('Cancel')),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: kRed),
                              onPressed: _busy ? null : () => _act('reject'),
                              icon: const Icon(Icons.cancel_outlined, size: 17),
                              label: const Text('Reject')),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: kGreen),
                              onPressed: _busy ? null : () => _act('accept'),
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
                              label: const Text('Approve')),
                        ]),
                      ] else ...[
                        if ('${_loan['loan_status']}' == 'rejected' && '${_loan['verification_notes'] ?? ''}'.isNotEmpty)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: kRed.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
                            child: Text('Rejected: ${_loan['verification_notes']}', style: const TextStyle(color: kRed, fontWeight: FontWeight.w600)),
                          ),
                        Align(alignment: Alignment.centerRight, child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))),
                      ],
                    ]),
                  ),
      ),
    );
  }
}