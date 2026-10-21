import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';
import 'applicant_detail.dart';

int _stageNo(Map a) => int.tryParse(RegExp(r'stage_(\d+)').firstMatch('${a['registration_stage']}')?.group(1) ?? '') ?? 0;

bool _rejected(Map a) => _stageNo(a) == 8 && '${a['bank_loan_status'] ?? a['loan_application_status']}' == 'rejected';
bool _pending(Map a) => _stageNo(a) == 8 && !_rejected(a);
bool _approved(Map a) => _stageNo(a) >= 9;

String _bank(Map a) {
  final v = '${a['bank_name'] ?? a['loan_bank_name'] ?? ''}'.trim();
  return v.isEmpty ? '-' : v;
}

String _amount(Map a) {
  final n = num.tryParse('${a['loan_amount'] ?? ''}');
  if (n == null) return '-';
  final d = n.round().toString();
  if (d.length <= 3) return '₹ $d';
  final head = d.substring(0, d.length - 3).replaceAllMapped(RegExp(r'(\d)(?=(\d\d)+$)'), (m) => '${m[1]},');
  return '₹ $head,${d.substring(d.length - 3)}';
}

class BankingLoansPage extends StatefulWidget {
  const BankingLoansPage({super.key});
  @override
  State<BankingLoansPage> createState() => _BankingLoansPageState();
}

class _BankingLoansPageState extends State<BankingLoansPage> {
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
      return '${a['unique_id']} ${fullName(a)} ${a['email']} ${_bank(a)}'.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _view(Map a) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => ApplicantDetail(id: '${a['id']}'));
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
      _stat('Total Applications', _all.length, kInk, Icons.description_outlined),
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
                          Expanded(flex: 2, child: Text('Bank', style: hs)),
                          Expanded(flex: 2, child: Text('Loan Amount', style: hs)),
                          Expanded(flex: 2, child: Text('Status', style: hs)),
                          Expanded(flex: 2, child: Text('Actions', style: hs)),
                        ])),
                    Divider(height: 1, color: kLine),
                    Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: Text('No loan applications found', style: TextStyle(fontSize: 15.5, color: kMuted)))),
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
                      DataColumn(label: Text('Bank')),
                      DataColumn(label: Text('Loan Amount')),
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
                          DataCell(Text(_bank(a), style: const TextStyle(fontSize: 15, color: kInk))),
                          DataCell(Text(_amount(a), style: const TextStyle(fontSize: 15, color: kInk))),
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
              decoration: const InputDecoration(hintText: 'Search by Form No., Name, Bank...', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        _table(_rows),
      ]),
    );
  }
}