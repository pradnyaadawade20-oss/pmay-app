import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';
import '../web_open.dart';
import 'cheque_payment_dialog.dart';
import 'collect_payment_dialog.dart';
import 'payments.dart';

/// Price of one unit per applicant (Rs 25,50,000 = 25.5 L). Change here if it differs.
const kUnitPrice = 2550000;
const _kPageSize = 20;

// ---------------- formatting helpers ----------------
String _inr(num v) {
  final neg = v < 0;
  final s = v.round().abs().toString();
  if (s.length <= 3) return '${neg ? '-' : ''}$s';
  final last = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${neg ? '-' : ''}${parts.join(',')},$last';
}

String lakh(num v) => v >= 100000 ? '₹${(v / 100000).toStringAsFixed(2)} L' : '₹${_inr(v)}';

String _cap(String s) {
  final t = s.replaceAll('_', ' ').trim();
  return t.isEmpty ? '-' : t[0].toUpperCase() + t.substring(1);
}

String _d(DateTime? d) => d == null ? '-' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

// ---------------- payment field accessors (defensive about key names) ----------------
num _amt(Map p) => num.tryParse('${p['amount']}') ?? 0;
String _st(Map p) => '${p['payment_status'] ?? ''}'.toLowerCase();
bool _paid(Map p) => const ['completed', 'confirmed', 'success', 'paid'].contains(_st(p));
bool _failed(Map p) => const ['failed', 'rejected'].contains(_st(p));
bool _pend(Map p) => _st(p) == 'pending';
String _method(Map p) => _cap('${p['mode'] ?? p['payment_method'] ?? p['method'] ?? 'offline'}');
String _stage(Map p) => _cap('${p['payment_stage'] ?? p['stage'] ?? p['payment_type'] ?? 'Booking'}');
String _name(Map p) => '${p['applicant_name'] ?? '-'}';
String _uid(Map p) => '${p['unique_id'] ?? '-'}';
String _receipt(Map p) {
  final v = p['receipt_number'] ?? p['receipt_no'] ?? p['transaction_id'];
  return (v == null || '$v'.isEmpty) ? '-' : '$v';
}

DateTime? _date(Map p) {
  for (final k in ['payment_date', 'created_at', 'paid_at']) {
    final d = DateTime.tryParse('${p[k] ?? ''}');
    if (d != null) return d.toLocal();
  }
  return null;
}

Color _stColor(Map p) => _paid(p) ? kGreen : (_failed(p) ? kRed : kOrange);

// =====================================================================
//  PAYMENT MANAGEMENT PAGE
// =====================================================================
class PaymentManagementPage extends StatefulWidget {
  const PaymentManagementPage({super.key});
  @override
  State<PaymentManagementPage> createState() => _PaymentManagementPageState();
}

class _PaymentManagementPageState extends State<PaymentManagementPage> {
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _awaiting = []; // applicants at the payment stage (the user app only shows "Awaiting Payment")
  bool _loading = true;
  String? _err;
  int _tab = 1; // 0 awaiting, 1 all payments, 2 balances, 3 charts

  // all-payments filters
  final _q = TextEditingController();
  String _fStatus = '', _fMethod = '', _fStage = '';
  int _sortCol = 2; // 0 applicant, 1 amount, 2 date
  bool _asc = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      Map<String, dynamic> r;
      try {
        r = await Api.i.get(Ep.payments('all'));
      } catch (_) {
        r = await Api.i.get(Ep.payments(''));
      }
      _all = List<Map<String, dynamic>>.from(r['payments'] ?? []);
      try {
        final a = await Api.i.get(Ep.list('', 'stage_3_payment'));
        _awaiting = List<Map<String, dynamic>>.from(a['applicants'] ?? []);
      } catch (_) {
        _awaiting = [];
      }
    } catch (e) {
      _err = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  // ---------- derived numbers ----------
  Set<String> get _applicants => _all.map(_uid).toSet();
  num get _expected => _applicants.length * kUnitPrice;
  num get _collected => _all.where(_paid).fold<num>(0, (a, p) => a + _amt(p));
  int get _pendingN => _all.where((p) => _pend(p) && _method(p).toLowerCase() != 'online').length;
  int get _failedN => _all.where(_failed).length;

  // ---------- stat cards ----------
  Widget _stat(IconData icon, String label, String value, String sub, Color c, {Color? valueColor}) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kLine), boxShadow: kShadow),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
         child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: c), // coloured accent on the left edge
          Expanded(
           child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 20, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(icon, size: 17, color: kMuted),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: const TextStyle(fontSize: 13.5, color: kMuted, fontWeight: FontWeight.w500))),
          ]),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: valueColor ?? kInk)),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(fontSize: 12, color: kMuted)),
            ]),
           ),
          ),
         ]),
        ),
      );

  Widget _stats(double w) {
    final cards = [
      _stat(Icons.currency_rupee_rounded, 'Total Expected', lakh(_expected), '${_applicants.length} applicants × ₹${kUnitPrice / 100000}L', kBlue),
      _stat(Icons.trending_up_rounded, 'Total Collected', lakh(_collected), '${_all.where(_paid).length} payments received', kGreen, valueColor: kGreen),
      _stat(Icons.account_balance_wallet_outlined, 'Total Balance Due', lakh((_expected - _collected).clamp(0, double.infinity)), 'Pending collection', const Color(0xFFF2B100),
          valueColor: const Color(0xFFD98B00)),
      _stat(Icons.schedule_rounded, 'Pending Verification', '$_pendingN', '$_failedN failed/rejected', kOrange, valueColor: kOrange),
    ];
    final cols = w >= 1000 ? 4 : (w >= 560 ? 2 : 1);
    final cw = (w - 16 * (cols - 1)) / cols;
    return Wrap(spacing: 16, runSpacing: 16, children: [for (final c in cards) SizedBox(width: cw, child: c)]);
  }

  // ---------- tabs ----------
  Widget _tabBtn(int i, String label, {IconData? icon}) {
    final on = _tab == i;
    return Material(
      color: on ? kBlue : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (_tab != i) {
            setState(() {
              _tab = i;
              _page = 0;
            });
            if (_tab == 1 || _tab == 2 || _tab == 3) _load(); // refresh after confirm/reject in the Awaiting tab
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: on ? kBlue : kLine)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16, color: on ? Colors.white : kInk), const SizedBox(width: 8)],
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? Colors.white : kInk)),
          ]),
        ),
      ),
    );
  }

  Widget _tabsRow() => Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _tabBtn(0, 'Awaiting Payment (${_awaiting.length})', icon: Icons.schedule_rounded),
        _tabBtn(1, 'All Payments'),
        _tabBtn(2, 'Applicant Balances'),
        _tabBtn(3, 'Charts', icon: Icons.bar_chart_rounded),
        if (Api.i.canPayments)
          FilledButton.icon(
            onPressed: () async {
              final saved = await showChequePaymentDialog(context);
              if (saved == true) _load();
            },
            icon: const Icon(Icons.add_card_rounded, size: 18),
            label: const Text('Record Cheque Payment'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
          ),
        OutlinedButton.icon(
          onPressed: _all.isEmpty ? null : _exportCsv,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Export CSV'),
          style: OutlinedButton.styleFrom(foregroundColor: kInk, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
        ),
      ]);

  // ---------- Awaiting Payment tab ----------
  Widget _awaitingTab() {
    Future<void> record(String? id) async {
      final saved = await showChequePaymentDialog(context, applicantId: id);
      if (saved == true) _load();
    }

    // Collect Payment: online (Cashfree) or cash (receipt upload)
    Future<void> collect(Map a, {required bool offline}) async {
      final uid = '${a['unique_id'] ?? ''}';
      final paid = _all.where((p) => _uid(p) == uid && _paid(p)).fold<num>(0, (s, p) => s + _amt(p));
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CollectPaymentDialog(
          applicant: {
            'id': a['id'],
            'unique_id': uid,
            'applicant_name': '${a['first_name'] ?? ''} ${a['last_name'] ?? ''}'.trim(),
            'email': a['email'],
            'phone': a['phone'],
            'paid': paid,
          },
          totalCost: kUnitPrice,
          startOffline: offline,
        ),
      );
      if (saved == true) _load();
    }

    final people = _awaiting;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _section(
        'Applicants awaiting payment',
        'Documents are verified. Collect the booking payment online (Cashfree), in cash, or record a cheque - the applicant then moves to allotment.',
        people.isEmpty
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: EmptyState(icon: Icons.check_circle_outline_rounded, title: 'All caught up', sub: 'No applicant is waiting for payment'))
            : Column(children: [
                for (final a in people)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kLine))),
                    child: Row(children: [
                      Avatar('${a['first_name'] ?? ''} ${a['last_name'] ?? ''}', size: 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${a['first_name'] ?? ''} ${a['last_name'] ?? ''}'.trim(), style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
                          Text('${a['unique_id'] ?? ''}  -  ${a['phone'] ?? ''}', style: const TextStyle(fontSize: 12.5, color: kMuted)),
                        ]),
                      ),
                      const Pill('Awaiting payment', kOrange),
                      const SizedBox(width: 12),
                      if (Api.i.canPayments)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
                            FilledButton.icon(
                              onPressed: () => collect(a, offline: false),
                              icon: const Icon(Icons.credit_card_rounded, size: 18),
                              label: const Text('Online'),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: kInk),
                              onPressed: () => collect(a, offline: true),
                              icon: const Icon(Icons.payments_outlined, size: 18),
                              label: const Text('Cash'),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: kInk),
                              onPressed: () => record('${a['id']}'),
                              icon: const Icon(Icons.add_card_rounded, size: 18),
                              label: const Text('Cheque'),
                            ),
                          ]),
                        ),
                    ]),
                  ),
              ]),
      ),
      if (_pendingN > 0) ...[
        const SizedBox(height: 20),
        const Text('Payments to verify', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
        const SizedBox(height: 10),
        const SizedBox(height: 620, child: PaymentsPage()), // existing Confirm / Reject screen for offline receipts
      ],
    ]);
  }

  // ---------- CSV ----------
  void _exportCsv() {
    String e(Object? v) => '"${'$v'.replaceAll('"', '""')}"';
    final b = StringBuffer('Applicant ID,Name,Amount,Method,Status,Stage,Receipt No,Date\n');
    for (final p in _all) {
      b.writeln([_uid(p), _name(p), _amt(p), _method(p), _cap(_st(p)), _stage(p), _receipt(p), _d(_date(p))].map(e).join(','));
    }
    downloadBytes('payments.csv', Uint8List.fromList(utf8.encode(b.toString())), 'text/csv');
  }

  // ---------- section panel ----------
  Widget _section(String title, String sub, Widget child) => Panel(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(fontSize: 14, color: kMuted)),
          const SizedBox(height: 18),
          child,
        ]),
      );

  // =====================================================================
  //  TAB 1: ALL PAYMENTS
  // =====================================================================
  List<Map<String, dynamic>> get _filtered {
    final q = _q.text.trim().toLowerCase();
    final out = _all.where((p) {
      if (q.isNotEmpty) {
        final hay = '${_uid(p)} ${_name(p)} ${p['email'] ?? ''} ${_receipt(p)}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      if (_fStatus.isNotEmpty && _st(p) != _fStatus && !(_fStatus == 'completed' && _paid(p)) && !(_fStatus == 'failed' && _failed(p))) return false;
      if (_fMethod.isNotEmpty && _method(p) != _fMethod) return false;
      if (_fStage.isNotEmpty && _stage(p) != _fStage) return false;
      return true;
    }).toList();
    out.sort((a, b) {
      final c = switch (_sortCol) {
        0 => _uid(a).compareTo(_uid(b)),
        1 => _amt(a).compareTo(_amt(b)),
        _ => (_date(a) ?? DateTime(2000)).compareTo(_date(b) ?? DateTime(2000)),
      };
      return _asc ? c : -c;
    });
    return out;
  }

  Widget _dd(String hint, String value, List<String> opts, void Function(String) on, {IconData? icon}) => DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(isDense: true, prefixIcon: icon == null ? null : Icon(icon, size: 18)),
        items: [
          DropdownMenuItem(value: '', child: Text(hint)),
          for (final o in opts) DropdownMenuItem(value: o, child: Text(o.isEmpty ? '' : _cap(o))),
        ],
        onChanged: (v) => setState(() {
          on(v ?? '');
          _page = 0;
        }),
      );

  Widget _allPayments(double w) {
    final rows = _filtered;
    final pages = math.max(1, (rows.length / _kPageSize).ceil());
    final page = _page.clamp(0, pages - 1);
    final shown = rows.skip(page * _kPageSize).take(_kPageSize).toList();
    final methods = _all.map(_method).toSet().toList()..sort();
    final stagesL = _all.map(_stage).toSet().toList()..sort();
    final narrow = w < 900;
    Widget f(Widget c) => narrow ? SizedBox(width: double.infinity, child: c) : Expanded(child: c);
    final filters = [
      Expanded(
        flex: narrow ? 0 : 2,
        child: TextField(
          controller: _q,
          onChanged: (_) => setState(() => _page = 0),
          decoration: const InputDecoration(hintText: 'Search by ID, name, email, or receipt...', prefixIcon: Icon(Icons.search_rounded), isDense: true),
        ),
      ),
      f(_dd('All Status', _fStatus, const ['completed', 'pending', 'failed'], (v) => _fStatus = v, icon: Icons.filter_alt_outlined)),
      f(_dd('All Methods', _fMethod, methods, (v) => _fMethod = v)),
      f(_dd('All Stages', _fStage, stagesL, (v) => _fStage = v)),
    ];
    return _section(
      'All Payments',
      'View, filter, and verify payment records',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        narrow
            ? Column(children: [
                for (final x in filters) Padding(padding: const EdgeInsets.only(bottom: 10), child: x is Expanded ? x.child : x),
              ])
            : Row(children: [
                for (var i = 0; i < filters.length; i++) ...[if (i > 0) const SizedBox(width: 16), filters[i]],
              ]),
        const SizedBox(height: 10),
        if (shown.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: EmptyState(icon: Icons.search_off_rounded, title: 'No payments found', sub: 'Try changing your search or filters'))
        else
          LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: c.maxWidth < 950 ? 950 : c.maxWidth),
                child: DataTable(
                  showCheckboxColumn: false,
                  sortColumnIndex: _sortCol == 0 ? 0 : (_sortCol == 1 ? 1 : 6),
                  sortAscending: _asc,
                  dataRowMinHeight: 70,
                  dataRowMaxHeight: 70,
                  horizontalMargin: 8,
                  columnSpacing: 28,
                  columns: [
                    DataColumn(label: const Text('Applicant'), onSort: (_, a) => setState(() => (_sortCol = 0, _asc = a))),
                    DataColumn(label: const Text('Amount'), onSort: (_, a) => setState(() => (_sortCol = 1, _asc = a))),
                    const DataColumn(label: Text('Method')),
                    const DataColumn(label: Text('Status')),
                    const DataColumn(label: Text('Stage')),
                    const DataColumn(label: Text('Receipt No.')),
                    DataColumn(label: const Text('Date'), onSort: (_, a) => setState(() => (_sortCol = 2, _asc = a))),
                    const DataColumn(label: Text('Action')),
                  ],
                  rows: [
                    for (final p in shown)
                      DataRow(cells: [
                        DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_uid(p), style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
                          Text(_name(p), style: const TextStyle(fontSize: 13, color: kMuted)),
                        ])),
                        DataCell(Text('₹${_inr(_amt(p))}', style: const TextStyle(fontWeight: FontWeight.w600, color: kInk))),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine)),
                          child: Text(_method(p), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kInk)),
                        )),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: _stColor(p).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                          child: Text(_cap(_st(p)), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _stColor(p))),
                        )),
                        DataCell(Text(_stage(p), style: const TextStyle(color: kInk))),
                        DataCell(Text(_receipt(p), style: const TextStyle(color: kMuted))),
                        DataCell(Text(_d(_date(p)), style: const TextStyle(color: kInk))),
                        DataCell(OutlinedButton.icon(
                          onPressed: () => showDialog<void>(context: context, builder: (_) => PaymentDetailsDialog(payment: p)),
                          icon: const Icon(Icons.visibility_outlined, size: 17),
                          label: const Text('View'),
                          style: OutlinedButton.styleFrom(foregroundColor: kInk),
                        )),
                      ]),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('${rows.length} payments  •  Page ${page + 1} of $pages', style: const TextStyle(color: kMuted, fontSize: 13)),
          IconButton(onPressed: page > 0 ? () => setState(() => _page = page - 1) : null, icon: const Icon(Icons.chevron_left_rounded)),
          IconButton(onPressed: page < pages - 1 ? () => setState(() => _page = page + 1) : null, icon: const Icon(Icons.chevron_right_rounded)),
        ]),
      ]),
    );
  }

  // =====================================================================
  //  TAB 2: APPLICANT BALANCES
  // =====================================================================
  Widget _balances() {
    final byApp = <String, List<Map<String, dynamic>>>{};
    for (final p in _all) {
      byApp.putIfAbsent(_uid(p), () => []).add(p);
    }
    final ids = byApp.keys.toList()..sort((a, b) => b.compareTo(a));
    Widget h(String t, {TextAlign a = TextAlign.left}) => Text(t, textAlign: a, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kMuted));
    return _section(
      'Applicant Balances',
      'View total expected, paid, and balance per applicant',
      LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth < 800 ? 800 : c.maxWidth),
            child: DataTable(
              dataRowMinHeight: 64,
              dataRowMaxHeight: 64,
              horizontalMargin: 8,
              columns: [
                DataColumn(label: h('Applicant ID')),
                DataColumn(label: h('Name')),
                DataColumn(label: h('Total Expected'), numeric: true),
                DataColumn(label: h('Total Paid'), numeric: true),
                DataColumn(label: h('Balance Due'), numeric: true),
                DataColumn(label: h('Payments')),
              ],
              rows: [
                for (final id in ids)
                  () {
                    final list = byApp[id]!;
                    final paid = list.where(_paid).fold<num>(0, (a, p) => a + _amt(p));
                    final bal = (kUnitPrice - paid).clamp(0, double.infinity);
                    return DataRow(cells: [
                      DataCell(Text(id, style: const TextStyle(fontFamily: 'monospace', fontSize: 15, color: kInk))),
                      DataCell(Text(_name(list.first), style: const TextStyle(fontSize: 15, color: kInk))),
                      DataCell(Text('₹${_inr(kUnitPrice)}', style: const TextStyle(fontSize: 15, color: kInk))),
                      DataCell(Text('₹${_inr(paid)}', style: const TextStyle(fontSize: 15, color: kGreen, fontWeight: FontWeight.w600))),
                      DataCell(Text('₹${_inr(bal)}', style: TextStyle(fontSize: 15, color: bal > 0 ? kRed : kGreen, fontWeight: FontWeight.w600))),
                      DataCell(Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine)),
                        child: Text('${list.length} payments', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kInk)),
                      )),
                    ]);
                  }(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================================
  //  TAB 3: CHARTS
  // =====================================================================
  Widget _chartCard(String title, String sub, Widget chart, {double h = 300}) => Panel(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(fontSize: 14, color: kMuted)),
          const SizedBox(height: 18),
          SizedBox(height: h, width: double.infinity, child: chart),
        ]),
      );

  Widget _charts(double w) {
    final today = DateTime.now();
    final days = [for (var i = 29; i >= 0; i--) DateTime(today.year, today.month, today.day).subtract(Duration(days: i))];
    final perDay = List<double>.filled(30, 0);
    for (final p in _all.where(_paid)) {
      final d = _date(p);
      if (d == null) continue;
      final k = DateTime(d.year, d.month, d.day);
      final idx = days.indexWhere((x) => x == k);
      if (idx >= 0) perDay[idx] += _amt(p).toDouble();
    }
    var run = _all.where(_paid).where((p) {
      final d = _date(p);
      return d != null && DateTime(d.year, d.month, d.day).isBefore(days.first);
    }).fold<double>(0, (a, p) => a + _amt(p).toDouble());
    final cumul = <double>[];
    for (final v in perDay) {
      run += v;
      cumul.add(run);
    }
    const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final xl = [for (final d in days) '${mon[d.month - 1]} ${d.day.toString().padLeft(2, '0')}'];

    // status distribution
    final counts = <String, int>{};
    for (final p in _all) {
      final k = _paid(p) ? 'Completed' : (_failed(p) ? 'Failed' : 'Pending');
      counts[k] = (counts[k] ?? 0) + 1;
    }
    const colors = {'Completed': kGreen, 'Pending': kOrange, 'Failed': kRed};

    // stage-wise
    final byStage = <String, double>{};
    for (final p in _all.where(_paid)) {
      byStage[_stage(p)] = (byStage[_stage(p)] ?? 0) + _amt(p).toDouble();
    }
    for (final p in _all) {
      byStage.putIfAbsent(_stage(p), () => 0);
    }
    final maxStage = byStage.values.fold<double>(0, math.max);

    final donut = _all.isEmpty
        ? const Center(child: Text('No data', style: TextStyle(color: kMuted)))
        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final e in counts.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('${e.key} ${(e.value * 100 / _all.length).round()}%', style: TextStyle(fontSize: 16, color: colors[e.key])),
                ),
            ]),
            const SizedBox(width: 20),
            SizedBox(
              width: 200,
              height: 200,
              child: CustomPaint(painter: _DonutPainter([for (final e in counts.entries) (e.value.toDouble(), colors[e.key]!)])),
            ),
          ]);

    final stageBars = byStage.isEmpty
        ? const Center(child: Text('No data', style: TextStyle(color: kMuted)))
        : ListView(children: [
            for (final e in byStage.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  SizedBox(width: 90, child: Text(e.key, style: const TextStyle(fontSize: 13, color: kInk))),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => Stack(children: [
                        Container(height: 26, decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(6))),
                        Container(
                            height: 26,
                            width: maxStage <= 0 ? 0 : c.maxWidth * e.value / maxStage,
                            decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(6))),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('₹${_inr(e.value)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kInk)),
                ]),
              ),
          ]);

    final cards = [
      _chartCard('Daily Collection Trends', 'Payment collections over the last 30 days', CustomPaint(painter: _LinePainter(perDay, xl, kBlue))),
      _chartCard('Payment Status Distribution', 'Breakdown by payment status', donut),
      _chartCard('Stage-wise Collection', 'Payment amounts by registration stage', stageBars),
      _chartCard('Cumulative Collection Progress', 'Total collection growth over time', CustomPaint(painter: _LinePainter(cumul, xl, kGreen, fill: true))),
    ];
    if (w < 900) {
      return Column(children: [for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 16), child: c)]);
    }
    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: cards[0]), const SizedBox(width: 16), Expanded(child: cards[1])]),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: cards[2]), const SizedBox(width: 16), Expanded(child: cards[3])]),
    ]);
  }

  // =====================================================================
  @override
  Widget build(BuildContext context) {
    if (_loading && _all.isEmpty) return const Center(child: CircularProgressIndicator());
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
        const SizedBox(height: 20),
        _tabsRow(),
        const SizedBox(height: 20),
        switch (_tab) {
          0 => _awaitingTab(),
          1 => _allPayments(c.maxWidth),
          2 => _balances(),
          _ => _charts(c.maxWidth),
        },
        const SizedBox(height: 16),
      ]),
    );
  }
}

// =====================================================================
//  PAYMENT DETAILS POPUP
// =====================================================================
class PaymentDetailsDialog extends StatelessWidget {
  final Map payment;
  const PaymentDetailsDialog({super.key, required this.payment});

  Widget _kv(String k, Widget v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: const TextStyle(fontSize: 15, color: kMuted)),
        const SizedBox(height: 4),
        v,
      ]);

  Widget _t(String s, {double size = 16, FontWeight w = FontWeight.w600}) => Text(s, style: TextStyle(fontSize: size, fontWeight: w, color: kInk));

  Future<void> _receiptOpen(BuildContext context) async {
    try {
      final b = await Api.i.fileBytes(Ep.payReceipt('${payment['id']}'));
      openBytes(b);
    } catch (_) {
      if (context.mounted) toast(context, 'No receipt uploaded for this payment', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = payment;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _t('Payment Details', size: 22, w: FontWeight.w800),
                  const SizedBox(height: 4),
                  Text('${_uid(p)} - ${_name(p)}', style: const TextStyle(fontSize: 15, color: kMuted)),
                ]),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: kInk)),
            ]),
            const SizedBox(height: 22),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _kv('Amount', _t('₹${_inr(_amt(p))}', size: 18, w: FontWeight.w800))),
              Expanded(child: _kv('Method', _t(_method(p)))),
            ]),
            const SizedBox(height: 22),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: _kv(
                    'Status',
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: _stColor(p).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text(_cap(_st(p)), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _stColor(p))),
                    )),
              ),
              Expanded(child: _kv('Stage', _t(_stage(p)))),
            ]),
            const SizedBox(height: 22),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _kv('Email', _t('${p['email'] ?? p['applicant_email'] ?? '-'}'))),
              Expanded(child: _kv('Phone', _t('${p['phone'] ?? p['applicant_phone'] ?? '-'}'))),
            ]),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _receiptOpen(context),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('View Uploaded Receipt'),
                style: OutlinedButton.styleFrom(foregroundColor: kInk, padding: const EdgeInsets.symmetric(vertical: 18)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// =====================================================================
//  SMALL CHART PAINTERS (no extra packages needed)
// =====================================================================
class _LinePainter extends CustomPainter {
  final List<double> v;
  final List<String> xl;
  final Color color;
  final bool fill;
  _LinePainter(this.v, this.xl, this.color, {this.fill = false});

  void _text(Canvas c, String s, Offset o, {TextAlign align = TextAlign.left, double size = 10.5}) {
    final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(fontSize: size, color: kMuted)), textDirection: TextDirection.ltr)..layout();
    final dx = align == TextAlign.right ? o.dx - tp.width : (align == TextAlign.center ? o.dx - tp.width / 2 : o.dx);
    tp.paint(c, Offset(dx, o.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const l = 60.0, b = 24.0, t = 8.0, r = 10.0;
    final w = size.width - l - r, h = size.height - b - t;
    final mx = v.fold<double>(0, math.max);
    final top = mx <= 0 ? 4.0 : mx;
    final grid = Paint()..color = kLine..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = t + h - h * i / 4;
      canvas.drawLine(Offset(l, y), Offset(l + w, y), grid);
      _text(canvas, '₹${_inr(top * i / 4)}', Offset(l - 6, y), align: TextAlign.right);
    }
    if (v.length < 2) return;
    final pts = [for (var i = 0; i < v.length; i++) Offset(l + w * i / (v.length - 1), t + h - h * v[i] / top)];
    for (var i = 0; i < v.length; i += 4) {
      canvas.drawLine(Offset(pts[i].dx, t + h), Offset(pts[i].dx, t + h + 4), grid);
      _text(canvas, xl[i], Offset(pts[i].dx, t + h + 14), align: TextAlign.center, size: 9.5);
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    if (fill) {
      final area = Path.from(path)..lineTo(pts.last.dx, t + h)..lineTo(pts.first.dx, t + h)..close();
      canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.12));
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _LinePainter o) => o.v != v || o.color != color;
}

class _DonutPainter extends CustomPainter {
  final List<(double, Color)> parts;
  _DonutPainter(this.parts);

  @override
  void paint(Canvas canvas, Size size) {
    final total = parts.fold<double>(0, (a, p) => a + p.$1);
    if (total <= 0) return;
    const stroke = 38.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    var start = -math.pi / 2;
    for (final p in parts) {
      final sweep = 2 * math.pi * p.$1 / total;
      canvas.drawArc(rect, start, sweep, false, Paint()..color = p.$2..style = PaintingStyle.stroke..strokeWidth = stroke);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter o) => o.parts != parts;
}