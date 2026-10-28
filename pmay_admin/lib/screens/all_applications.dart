import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';
import '../web_open.dart';
import 'allot_ui.dart';
import 'applicant_detail.dart';
import 'applicants.dart' show openStageScreen;
import 'payment_management.dart' show PaymentManagementPage;
import 'validation_queue.dart' show ReviewApplicantDialog;
import 'unit_allotment.dart';

// ---------------------------------------------------------------- helpers
/// Stage keys as defined by the backend. If the Stage 2 key differs, change it here only.
const stageOptions = <(String, String)>[
  ('stage_1_registered', 'Stage 1 - Registered'),
  ('stage_2_validation', 'Stage 2 - Validation'),
  ('stage_3_payment', 'Stage 3 - Payment'),
  ('stage_4_allotment', 'Stage 4 - Allotment'),
  ('stage_5_agreement', 'Stage 5 - Agreement'),
  ('stage_6_agreement_receipt', 'Stage 6 - Agreement Receipt'),
  ('stage_7_bank_document', 'Stage 7 - Bank Documents'),
  ('stage_8_bank_loan', 'Stage 8 - Bank Loan'),
  ('stage_9_mortgage', 'Stage 9 - Mortgage'),
  ('stage_10_completed', 'Stage 10 - Completed'),
];

int stageNo(Object? k) {
  final m = RegExp(r'stage_(\d+)').firstMatch('$k');
  return m == null ? 0 : int.parse(m.group(1)!);
}

String stageLabel(Object? k) => stageOptions.firstWhere((e) => e.$1 == '$k', orElse: () => ('$k', '$k')).$2;

Color stageColor(Object? k) {
  final n = stageNo(k);
  return n <= 2 ? kBlue : kGreen;
}

const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monFull = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
String _ord(int d) => (d % 100 >= 11 && d % 100 <= 13)
    ? 'th'
    : switch (d % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
String shortDate(Object? v) {
  final d = _dt(v);
  return d == null ? '-' : '${_mon[d.month - 1]} ${d.day}, ${d.year}';
}

String longDate(Object? v) {
  final d = _dt(v);
  return d == null ? '-' : '${_monFull[d.month - 1]} ${d.day}${_ord(d.day)}, ${d.year}';
}

String _by(Map a) {
  final v = a['handled_by_name'] ?? a['handled_by'];
  return (v == null || '$v'.isEmpty) ? '-' : '$v';
}

DateTime? _upd(Map a) => _dt(a['updated_at'] ?? a['created_at']);
String _csv(String v) => '"${v.replaceAll('"', '""')}"';

// ---------------------------------------------------------------- page
class AllApplicationsPage extends StatefulWidget {
  /// Shell's sub-screen opener: choosing a stage in the dropdown opens that stage's screen.
  final void Function(String title, Widget page)? onOpen;
  const AllApplicationsPage({super.key, this.onOpen});
  @override
  State<AllApplicationsPage> createState() => _AllApplicationsPageState();
}

class _AllApplicationsPageState extends State<AllApplicationsPage> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _err;
  String _stage = '';
  String _admin = '';
  int _col = 4;
  bool _asc = false;

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
      final r = await Api.i.get(Ep.list('', ''));
      _all = List<Map<String, dynamic>>.from(r['applicants'] ?? []);
    } catch (e) {
      _err = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _view {
    final q = _q.text.trim().toLowerCase();
    final l = _all.where((a) {
      if (_stage.isNotEmpty && a['registration_stage'] != _stage) return false;
      if (_admin.isNotEmpty && _by(a) != _admin) return false;
      if (q.isEmpty) return true;
      return '${a['unique_id']} ${fullName(a)} ${a['email']} ${a['phone']}'.toLowerCase().contains(q);
    }).toList();
    int c(Map a, Map b) {
      switch (_col) {
        case 0:
          return '${a['unique_id']}'.compareTo('${b['unique_id']}');
        case 1:
          return fullName(a).toLowerCase().compareTo(fullName(b).toLowerCase());
        case 2:
          return '${a['email'] ?? a['phone']}'.compareTo('${b['email'] ?? b['phone']}');
        case 3:
          return stageNo(a['registration_stage']).compareTo(stageNo(b['registration_stage']));
        default:
          return (_upd(a)?.millisecondsSinceEpoch ?? 0).compareTo(_upd(b)?.millisecondsSinceEpoch ?? 0);
      }
    }

    l.sort((a, b) => _asc ? c(a, b) : c(b, a));
    return l;
  }

  Future<void> _open(Map<String, dynamic> a) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => AppDetailsDialog(a: a));
    if (changed == true) _load();
  }

  void _export() {
    final rows = _view;
    final b = StringBuffer('Form No,Name,Email,Phone,Stage,Updated,Handled By\n');
    for (final a in rows) {
      b.writeln([
        '${a['unique_id'] ?? ''}',
        fullName(a),
        '${a['email'] ?? ''}',
        '${a['phone'] ?? ''}',
        stageLabel(a['registration_stage']),
        shortDate(a['updated_at'] ?? a['created_at']),
        _by(a),
      ].map(_csv).join(','));
    }
    downloadText('applications.csv', b.toString());
    toast(context, '${rows.length} applications exported');
  }

  Widget _stat(String label, int v, IconData icon, Color c, double w) => SizedBox(
        width: w,
        child: Container(
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
        ),
      );

  Widget _stats() => LayoutBuilder(builder: (context, c) {
        final cols = ((c.maxWidth + 16) / (210 + 16)).floor().clamp(1, 4);
        final w = (c.maxWidth - 16 * (cols - 1)) / cols;
        int n(bool Function(int) f) => _all.where((a) => f(stageNo(a['registration_stage']))).length;
        return Wrap(spacing: 16, runSpacing: 16, children: [
          _stat('Total Applications', _all.length, Icons.people_alt_outlined, kInk, w),
          _stat('Stage 1-3', n((s) => s >= 1 && s <= 3), Icons.schedule_rounded, kBlue, w),
          _stat('Stage 4-6', n((s) => s >= 4 && s <= 6), Icons.home_outlined, const Color(0xFF6A47D9), w),
          _stat('Completed', n((s) => s == 10), Icons.check_circle_outline_rounded, kGreen, w),
        ]);
      });

  Widget _toolbar() {
    final admins = _all.map(_by).where((e) => e != '-').toSet().toList()..sort();
    return Panel(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(builder: (context, c) {
        double w(double max) => c.maxWidth < max ? c.maxWidth : max;
        return Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.filter_alt_outlined, size: 18, color: kInk),
            SizedBox(width: 6),
            Text('Filters:', style: TextStyle(fontWeight: FontWeight.w600, color: kInk)),
          ]),
          SizedBox(
              width: w(320),
              child: TextField(
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'Search by Form No., Name, Email, Phone...', prefixIcon: Icon(Icons.search_rounded), isDense: true))),
          if (Api.i.isAllotOnly)
            AllotSelect(
              width: w(200),
              value: _stage,
              items: {'': 'All Stages', for (final e in stageOptions) e.$1: e.$2},
              onChanged: (v) => setState(() => _stage = v), // Allotment Manager: filter only, no jump to other screens
            )
          else
          SizedBox(
            width: w(200),
            child: DropdownButtonFormField<String>(
              initialValue: _stage,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [
                const DropdownMenuItem(value: '', child: Text('All Stages')),
                for (final e in stageOptions) DropdownMenuItem(value: e.$1, child: Text(e.$2, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                final st = v ?? '';
                if (st.isNotEmpty && widget.onOpen != null) {
                  openStageScreen(widget.onOpen!, st);
                  return;
                }
                setState(() => _stage = st);
              },
            ),
          ),
          if (Api.i.isAllotOnly)
            AllotSelect(
              width: w(180),
              value: _admin,
              items: {'': 'All Admins', for (final e in admins) e: e},
              onChanged: (v) => setState(() => _admin = v),
            )
          else
          SizedBox(
            width: w(180),
            child: DropdownButtonFormField<String>(
              initialValue: _admin,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [
                const DropdownMenuItem(value: '', child: Text('All Admins')),
                for (final e in admins) DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _admin = v ?? ''),
            ),
          ),
          OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Export CSV')),
        ]);
      }),
    );
  }

  static final _sq = IconButton.styleFrom(side: const BorderSide(color: kLine), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)));

  bool _needsValidation(Map a) => a['registration_stage'] == 'stage_1_registered' && a['stage_2_status'] != 'rejected';

  Future<void> _validate(Map a) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => ReviewApplicantDialog(id: '${a['id']}'));
    if (changed == true) _load();
  }

  void _payments() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _PageFrame('Payment Management', PaymentManagementPage())));

  Widget _actions(Map<String, dynamic> a) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'View details', onPressed: () => _open(a), icon: const Icon(Icons.visibility_outlined, size: 19, color: kInk), style: _sq),
        if (_needsValidation(a) && Api.i.canReview) ...[
          const SizedBox(width: 6),
          IconButton(tooltip: 'Validate documents', onPressed: () => _validate(a), icon: const Icon(Icons.assignment_turned_in_outlined, size: 19, color: kInk), style: _sq),
        ],
        if (stageNo(a['registration_stage']) == 3 && Api.i.canPayments) ...[
          const SizedBox(width: 6),
          IconButton(
              tooltip: 'Payments',
              onPressed: _payments,
              icon: const Icon(Icons.currency_rupee_rounded, size: 19, color: Colors.white),
              style: IconButton.styleFrom(backgroundColor: kBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
        ],
      ]);

  DataColumn _c(String t, int i) => DataColumn(
        label: Text(t),
        onSort: (ci, asc) => setState(() {
          _col = ci;
          _asc = asc;
        }),
      );

  Widget _table(List<Map<String, dynamic>> rows) => Panel(
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: math.max(c.maxWidth, 940)),
              child: DataTable(
                showCheckboxColumn: false,
                sortColumnIndex: _col,
                sortAscending: _asc,
                dataRowMinHeight: 72,
                dataRowMaxHeight: 72,
                horizontalMargin: 22,
                columnSpacing: 28,
                headingTextStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: kMuted),
                headingRowColor: const WidgetStatePropertyAll(Colors.white),
                columns: [
                  _c('Form No.', 0),
                  _c('Name', 1),
                  _c('Contact', 2),
                  _c('Stage', 3),
                  _c('Updated', 4),
                  const DataColumn(label: Text('Handled By')),
                  const DataColumn(label: Text('Actions')),
                ],
                rows: [
                  for (final a in rows)
                    DataRow(onSelectChanged: (_) => _open(a), cells: [
                      DataCell(Text('${a['unique_id'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w700, color: kInk))),
                      DataCell(Text(fullName(a), style: const TextStyle(fontWeight: FontWeight.w700, color: kInk))),
                      DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${a['email'] ?? '-'}', style: const TextStyle(color: kInk, fontSize: 13)),
                        Text('${a['phone'] ?? '-'}', style: const TextStyle(fontSize: 12, color: kMuted)),
                      ])),
                      DataCell(Pill('Stage ${stageNo(a['registration_stage'])}', stageColor(a['registration_stage']))),
                      DataCell(Text(shortDate(a['updated_at'] ?? a['created_at']), style: const TextStyle(color: kMuted))),
                      DataCell(Text(_by(a), style: const TextStyle(color: kInk))),
                      DataCell(_actions(a)),
                    ]),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) {
      return Center(child: EmptyState(icon: Icons.cloud_off_rounded, title: 'Failed to load data', sub: _err!));
    }
    final rows = _view;
    return ListView(children: [
      _stats(),
      const SizedBox(height: 16),
      _toolbar(),
      const SizedBox(height: 14),
      Text('Showing ${rows.length} of ${_all.length} applications', style: const TextStyle(color: kMuted, fontSize: 13)),
      const SizedBox(height: 12),
      if (rows.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: EmptyState(icon: Icons.search_off_rounded, title: 'No applications found', sub: 'Try changing your search or filters'))
      else
        _table(rows),
      const SizedBox(height: 8),
    ]);
  }
}

// ---------------------------------------------------------------- details dialog
class AppDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> a;
  const AppDetailsDialog({super.key, required this.a});
  @override
  State<AppDetailsDialog> createState() => _AppDetailsDialogState();
}

class _AppDetailsDialogState extends State<AppDetailsDialog> {
  late String _sel = '${widget.a['registration_stage']}';
  bool _busy = false;
  Map<String, dynamic> get a => widget.a;
  String get _cur => '${a['registration_stage']}';

  Future<void> _update() async {
    setState(() => _busy = true);
    try {
      await Api.i.post(Ep.setStage('${a['id']}'), {'stage': _sel});
      if (!mounted) return;
      toast(context, 'Stage updated: ${stageLabel(_sel)}');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, e.toString(), error: true);
      }
    }
  }

  /// Opens the full applicant review (documents, loan, unit, payments and approve/reject actions).
  void _openDetail() {
    final root = Navigator.of(context, rootNavigator: true);
    final rootCtx = root.context;
    root.pop(false);
    showDialog<void>(context: rootCtx, builder: (_) => ApplicantDetail(id: '${a['id']}'));
  }

  void _go(Widget page) {
    final nav = Navigator.of(context);
    nav.pop(false);
    nav.push(MaterialPageRoute(builder: (_) => page));
  }

  Widget _info(String k, String v) => Text.rich(TextSpan(children: [
        TextSpan(text: '$k: ', style: const TextStyle(color: kMuted, fontSize: 13)),
        TextSpan(text: v, style: const TextStyle(color: kInk, fontSize: 13.5, fontWeight: FontWeight.w700)),
      ]));

  Widget _sec(String t, IconData i) => Padding(padding: const EdgeInsets.only(top: 22, bottom: 10), child: SectionTitle(t, i));

  Widget _grey(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFF1F3F7), borderRadius: BorderRadius.circular(10)),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Form No', '${a['unique_id'] ?? '-'}'),
      ('Name', fullName(a)),
      ('Email', '${a['email'] ?? '-'}'),
      ('Phone', '${a['phone'] ?? '-'}'),
      ('Registered', longDate(a['created_at'])),
      ('Last Updated', longDate(a['updated_at'] ?? a['created_at'])),
    ];
    final canUpdate = Api.i.isSuper && _sel != _cur && !_busy;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Application Details', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: kInk)),
                  const SizedBox(height: 2),
                  Text('${a['unique_id'] ?? '-'} - ${fullName(a)}', style: const TextStyle(color: kMuted, fontSize: 13)),
                ]),
              ),
              IconButton(onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.close_rounded, size: 20)),
            ]),
            _sec('Applicant Information', Icons.people_alt_outlined),
            _grey(LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 460;
              final w = wide ? (c.maxWidth - 16) / 2 : c.maxWidth;
              return Wrap(spacing: 16, runSpacing: 14, children: [
                for (final i in items) SizedBox(width: w, child: _info(i.$1, i.$2)),
              ]);
            })),
            _sec('Current Stage', Icons.schedule_rounded),
            _grey(Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: stageColor(_cur).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(stageLabel(_cur), style: TextStyle(color: stageColor(_cur), fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            )),
            if (Api.i.isSuper) ...[
            _sec('Change Stage', Icons.arrow_forward_rounded),
            LayoutBuilder(builder: (context, c) {
              return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: c.maxWidth < 260 ? c.maxWidth : 260,
                  child: DropdownButtonFormField<String>(
                    initialValue: stageOptions.any((e) => e.$1 == _sel) ? _sel : null,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true),
                    items: [for (final e in stageOptions) DropdownMenuItem(value: e.$1, child: Text(e.$2, overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => _sel = v ?? _sel),
                  ),
                ),
                FilledButton(
                  onPressed: canUpdate ? _update : null,
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Update Stage'),
                ),
              ]);
            }),
            ],
            const SizedBox(height: 22),
            const Divider(height: 1, color: kLine),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(
                  onPressed: () => _go(DocumentGeneratorPage(a: a)),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('View Documents')),
              OutlinedButton.icon(
                  onPressed: _openDetail,
                  icon: const Icon(Icons.account_balance_outlined, size: 18),
                  label: const Text('View Loan')),
              OutlinedButton.icon(
                  onPressed: () => _go(const _PageFrame('Unit Allotment', UnitAllotmentPage())),
                  icon: const Icon(Icons.home_outlined, size: 18),
                  label: const Text('Manage Allotment')),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _PageFrame extends StatelessWidget {
  final String title;
  final Widget child;
  const _PageFrame(this.title, this.child);
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: const Border(bottom: BorderSide(color: kLine)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: kInk, fontSize: 20)),
        ),
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      );
}

// ---------------------------------------------------------------- document generator
/// Fixed promoter details: edit them here.
const _promoterName = 'M/S. PRIYANKA HOME REALTORS PVT LTD';
const _promoterDesc =
    'a Private Company incorporated under the provisions of the Companies Act, having its registered office at Office No. A-1 & A-2, 1st Floor, Swastik Residency CHS, Survey No 65, Hissa No 4, Village Ambivali, Taluka Kalyan, District Thane - 421102, CIN: U70102MH2011PTC222565, PAN: AACCP8176E';
const _project = 'DABBEWALA & CHARMAKAR BUILDING';
const _rera = 'P52000054498';
const _place = 'Ambivali, Kalyan, Thane';
const _land =
    '29137.40 Sq. Mtr. bearing Survey Nos. 65,67,78,81,82,83,84,89,118,119,122,123,124 (Part) & 125 situated at Village Ambivali, Taluka Kalyan, District Thane';

const docTypes = ['Agreement of Sale', 'Allotment Letter', 'Mortgage Deed', 'Payment Receipt'];
const pageSizes = {
  'A4': 'A4 (210×297mm)',
  'A3': 'A3 (297×420mm)',
  'Legal': 'Legal (216×356mm)',
  'Letter': 'Letter (216×279mm)',
};

String _v(Map a, String k, [String d = '________']) {
  final x = a[k];
  return (x == null || '$x'.trim().isEmpty) ? d : '$x';
}

// ---------- Simple Mortgage Deed (same text as the customer app PDF; blanks print as ____________) ----------
const _mdBlank = '____________';

String _mdT(Map m, String k) {
  final v = m[k];
  return (v == null || '$v'.trim().isEmpty) ? '' : '$v'.trim();
}

String _mdV(Object? v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? _mdBlank : s;
}

String _mdInr(num n) {
  final neg = n < 0;
  final x = n.abs();
  final fixed = x == x.truncate() ? x.truncate().toString() : x.toStringAsFixed(2);
  final parts = fixed.split('.');
  var whole = parts[0];
  if (whole.length > 3) {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final g = <String>[];
    while (rest.length > 2) {
      g.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) g.insert(0, rest);
    whole = '${g.join(',')},$last3';
  }
  return '${neg ? '-' : ''}$whole${parts.length > 1 ? '.${parts[1]}' : ''}';
}

String _mdRs(Object? v) {
  final s = (v ?? '').toString().replaceAll(',', '').trim();
  final n = num.tryParse(s);
  if (n == null) return s.isEmpty ? _mdBlank : s;
  return 'Rs. ${_mdInr(n)}/-';
}

String _mdDate(String s) {
  final d = DateTime.tryParse(s);
  if (d == null) return s.isEmpty ? _mdBlank : s;
  return '${d.day.toString().padLeft(2, '0')} ${_monFull[d.month - 1]} ${d.year}';
}

List<(String, String)> _mortgageDeedBlocks(Map a, String name, String age) {
  final d = a['_deed'] is Map ? Map<String, dynamic>.from(a['_deed']) : <String, dynamic>{};
  final sc = a['_schedule'] is Map ? Map<String, dynamic>.from(a['_schedule']) : <String, dynamic>{};
  final u = a['_unit'] is Map ? Map<String, dynamic>.from(a['_unit']) : <String, dynamic>{};
  final p = a['_project'] is Map ? Map<String, dynamic>.from(a['_project']) : <String, dynamic>{};

  String bound(String k) => _mdT(d, k).isNotEmpty ? _mdT(d, k) : _mdT(sc, k);

  final person = fullName(a);
  final place = _mdV(_mdT(d, 'exec_place'));
  final date = _mdDate(_mdT(d, 'exec_date'));
  final loanAmt = _mdRs(_mdT(d, 'loan_amount'));
  final bankName = _mdT(d, 'bank_name').isNotEmpty ? _mdT(d, 'bank_name') : _mdT(p, 'bank_name');
  final bankBranch = _mdT(d, 'bank_branch').isNotEmpty ? _mdT(d, 'bank_branch') : _mdT(p, 'bank_branch');
  final building = _mdT(u, 'building_name').isNotEmpty ? _mdT(u, 'building_name') : _mdT(p, 'project_name');
  final instType = _mdT(d, 'installment_type').isEmpty ? 'monthly' : _mdT(d, 'installment_type');
  final purpose = _mdT(d, 'loan_purpose').isEmpty ? 'Purchase of flat' : _mdT(d, 'loan_purpose');
  final extra = _mdT(d, 'extra_terms');

  final authority = _mdT(sc, 'authority_name').isEmpty
      ? _mdBlank
      : '${_mdT(sc, 'authority_name')}${_mdT(sc, 'authority_type').isEmpty ? '' : ' (${_mdT(sc, 'authority_type')})'}';
  final survey = _mdT(sc, 'survey_no').isEmpty
      ? _mdBlank
      : '${_mdT(sc, 'survey_type').isEmpty ? 'Survey No.' : _mdT(sc, 'survey_type')} ${_mdT(sc, 'survey_no')}';
  final schedule =
      'All that piece and parcel of land situated within Registration Division and District ${_mdV(_mdT(sc, 'district'))} Sub-Division and Taluka ${_mdV(_mdT(sc, 'taluka'))} '
      'within the limits of $authority situate At. Village ${_mdV(_mdT(sc, 'village'))} $survey Hissa/Plot No. ${_mdV(_mdT(sc, 'plot_no'))} '
      'With Constructed Building name as ${_mdV(building)} Flat No./House No. ${_mdV(u['unit_number'])} Floor No. ${_mdV(u['floor'])} '
      'Area ${_mdV(u['carpet_area_sqm'])} sqmts. And bounded by as follows:';

  String sign(String label, String who, [String sub = '']) =>
      '\n\n______________________________\n**$label**\n${_mdV(who)}${sub.isEmpty ? '' : '\n$sub'}';

  return [
    ('title', 'SIMPLE MORTGAGE DEED'),
    ('p', 'This deed of mortgage made and executed on $date at $place between'),
    ('p',
        '${_mdV(person)}, Age ${_mdV(age == '____' ? '' : age)}, Occupation ${_mdV(a['occupation'])}, Residing At ${_mdV(a['full_address'])}, '
            'PAN ${_mdV(a['pan_number'])}, UID ${_mdV(a['aadhar_number'])}, Mobile No. ${_mdV(a['phone'])}, Email id ${_mdV(a['email'])}, '
            'HEREINAFTER Called "the Mortgager" (which expression shall unless excluded by or repugnant to the subject to the context include '
            'his/her heirs, executors administrators representative assigns and transferee in interest of the) one part AND'),
    ('p',
        '${_mdV(bankName)}, represented by its Authorized Signatory ${_mdV(_mdT(d, 'signatory_designation'))}, Bank Address: ${_mdV(_mdT(d, 'bank_address'))}, '
            'Branch at ${_mdV(bankBranch)}, TAN No: ${_mdV(_mdT(d, 'bank_tan'))}, UID ${_mdV(_mdT(d, 'bank_uid'))}, Mobile No. ${_mdV(_mdT(d, 'bank_mobile'))}, '
            'Email id ${_mdV(_mdT(d, 'bank_email'))} hereinafter called the "Mortgagee" (which expression shall unless excluded by or repugnant to the '
            'subject or context include its successors, transferees-in-interest and assigns) the other part.'),
    ('p', "AND WHEREAS the mortgagor is the sole and absolute owner of immovable Property described in Schedule hereunder, and hereinafter referred to as the 'said Property'"),
    ('p',
        'Whereas, the Mortgagor is the absolute owner, having acquired the property, by ${_mdV(_mdT(d, 'ownership_by'))} and since then Mortgagor has been in possession and enjoyment of the schedule property and paying taxes and levies thereon, as sole and absolute owner thereof.'),
    ('p',
        'Whereas Mortgagor being in need of money for the purpose of $purpose. Mortgagor requested the Mortgagee to lend him a sum of $loanAmt which the Mortgagee has agreed to do on the Mortgagor executing these presents with a view to secure the repayment thereof with interest as hereinafter provided.'),
    ('p', 'AND WHEREAS mortgagor assured unto the mortgagee that he/she would pay the said amount which is an outstanding debt payable from the mortgagor to the mortgagee along with interest thereon;'),
    ('p',
        'AND WHEREAS the mortgagees have agreed to grant loan up to $loanAmt FROM TIME TO TIME to the mortgagors agreeing to utilize the amounts so advanced for the purpose applied for and on such terms and conditions as the mortgagees may stipulate from time to time and on the mortgagees securing the same by executing a mortgage of their immovable property'),
    ('p', 'AND WHEREAS the mortgagee agreed to give time to the mortgagor so as to enable him/her/them to make the payment of the aforesaid debt; however, the mortgagee insisted on the mortgagor so as to furnish unto the mortgagee security for this payment of debt;'),
    ('p', 'AND WHEREAS considering the cooperation extended by the mortgagee by giving time to the mortgagor the payment of the aforesaid debt, the mortgagor readily agreed to confer such a security unto the mortgagee;'),
    ('p', 'AND WHEREAS the parties hereto had due deliberations and discussions, and the mortgagor has agreed to mortgage the said property in favour of the mortgagee as a collateral security;'),
    ('p', 'AND WHEREAS the parties hereto have arrived at an understanding which they have decided to reduce into writing being these presents;'),
    ('h', 'NOW, THIS DEED WITNESS as follows:'),
    ('p', '1) That the mortgagor does hereby mortgage the said property in favour of the mortgagee subject to the terms and conditions stated in this deed.'),
    ('p', '2) That the mortgagor is liable to pay unto the mortgagee an amount of $loanAmt as a debt, and for the purpose of securing repayment of this debt, mortgage the said property in favour of the mortgagee.'),
    ('p', '3) That the mortgagor hereby agrees to repay the said amount of debt within a period of ${_mdV(_mdT(d, 'loan_period_years'))} years from execution of these present.'),
    ('p',
        '4) That the mortgagor hereby assures to pay unto the mortgagee the said amount of $loanAmt along with interest thereon at the rate of ${_mdV(_mdT(d, 'interest_rate'))}% per annum.'
            '${_mdT(d, 'installment_amount').isEmpty ? '' : ' And the Mortgagor would also repay loan amount with interest to Mortgagee at ${_mdRs(_mdT(d, 'installment_amount'))} $instType installment.'}'),
    ('p', '5) That the mortgagor assures unto the mortgagee that the said property is his/her absolute property, and no one else has any right, title or interest in the same. The mortgagor hereby assures unto the mortgagee that the said property is free from any encumbrances.'),
    ('p', '6) That the mortgagor hereby assures unto the mortgagee that he/she will not deal with the said property in any manner so as to prejudicially affect the rights of the mortgagee.'),
    ('p', '7) And it is further agreed and declared by the Mortgagor that he shall also be liable to pay and shall pay all the costs, charges and expenses that the Mortgagee will incur for the protection of the mortgage security and or for the realization of the mortgage amount and the same shall be deemed to form part of the mortgage amount and the security therefore as aforesaid'),
    ('p',
        '8) And it is further agreed that during the pending of the security hereby created and until repayment of the mortgage amount, the Mortgagor will get insured and keep insured the said scheduled property from any loss and damages due to fire or any other incident in the sum of at least ${_mdRs(_mdT(d, 'insurance_amount'))} with some Insurance Company of repute and pay all premium in the insurance policy as and when it becomes due and payable in respect thereof to such company and shall hand over the policy to the Mortgagee duly endorsed in his name as assignee and in the event of the Mortgagor failing to do so or to pay the premium, the Mortgagee will be entitled to insure the said property and structures and/or to pay the premium thereon and the amount paid by the Mortgagee in respect thereof will be deemed to form part of the mortgage amount.'),
    ('p', '9) That in the event, if the mortgagor fails to repay the aforesaid amount of debt along with interest thereon, then the mortgagee shall be entitled to claim foreclosure of the mortgage, and in the default of the mortgagor, the mortgagee shall be entitled to enforce all such remedies available against the mortgagor as are available to the mortgagee under simple mortgage.'),
    ('p', '10) All the obligations of the Mortgagor and all the rights and remedies and powers of the Mortgagee under the law for the time being in force except so far as they be expressly varied or may be inconsistent with these presents shall be deemed to be incorporated in these presents. PROVIDED THAT the provision of Sections 61, 65A and 67A, respectively, of the Transfer of Property Act, 1882, shall not apply to these presents or to the Mortgagor or the Mortgagee inters and this shall be deemed a contract to the contrary for the purpose of these sections.'),
    ('p', '11) The Mortgagor confirms and declares that he/she has actual possession of the Mortgaged Premises and has absolute power and authority to mortgage the Mortgaged Premises in favour of the Mortgagee and provided that the possession of the said mortgaged property is / will neither be given nor agreed to be given to Mortgagee except in the event of default.'),
    if (extra.isNotEmpty) ('p', '11A) $extra'),
    ('p', '12) That all the expenses towards stamp duty, registration charges and incidental expenses thereto were agreed to be borne out by the mortgagor, and accordingly he/she has done so.'),
    ('h', 'THE SCHEDULE OF THE PROPERTY ABOVE REFERRED TO'),
    ('p', schedule),
    ('p', 'On or towards the East : ${_mdV(bound('east'))}\nOn or towards the South : ${_mdV(bound('south'))}\nOn or towards the West : ${_mdV(bound('west'))}\nOn or towards the North : ${_mdV(bound('north'))}'),
    ('p', 'IN WITNESS WHEREOF the parties hereto have signed hereunder at $place on this $date.'),
    ('p', sign("MORTGAGOR'S Name and SIGN", person)),
    ('p', sign("MORTGAGEE'S Name and SIGN", _mdT(d, 'signatory_name'), _mdT(d, 'signatory_designation'))),
    ('h', 'WITNESSES:'),
    ('p', sign('1. Name and sign', _mdT(d, 'witness1_name'), _mdT(d, 'witness1_address'))),
    ('p', sign('2. Name and sign', _mdT(d, 'witness2_name'), _mdT(d, 'witness2_address'))),
  ];
}


/// kind: title | h | p.   `**text**` = bold.
List<(String, String)> docBlocks(String doc, Map a) {
  final now = DateTime.now();
  final day = '${now.day}${_ord(now.day)}';
  final month = '${_monFull[now.month - 1]}, ${now.year}';
  final name = fullName(a).toUpperCase();
  final dob = DateTime.tryParse(_v(a, 'date_of_birth', ''));
  final age = dob == null ? '____' : '${(now.difference(dob).inDays / 365.25).floor()}';
  final flat = _v(a, 'flat_no');
  final floor = _v(a, 'floor');
  final wing = _v(a, 'wing');
  final tower = _v(a, 'tower');
  final value = _v(a, 'agreement_value');
  final addr = _v(a, 'full_address');
  switch (doc) {
    case 'Allotment Letter':
      return [
        ('title', 'ALLOTMENT LETTER'),
        ('p', 'Date: **$day $month**'),
        ('p', 'To,\n**$name**\n$addr'),
        ('p', 'Sub: Allotment of Flat No. **$flat** in **$_project**'),
        ('p',
            'Dear Sir/Madam, with reference to your application ${_v(a, 'unique_id')}, we are pleased to allot to you Flat No. **$flat** on the **$floor** Floor, Wing **$wing**, Building/Tower **$tower** in the project "**$_project**" registered under MahaRERA vide Registration No. **$_rera**.'),
        ('p', 'The allotment is subject to the terms and conditions of the Agreement of Sale to be executed between us.'),
        ('p', 'Yours faithfully,\n**For $_promoterName**'),
      ];
    case 'Mortgage Deed':
      return _mortgageDeedBlocks(a, name, age);
    case 'Payment Receipt':
      return [
        ('title', 'PAYMENT RECEIPT'),
        ('p', 'Receipt No: **${_v(a, 'receipt_no')}**          Date: **$day $month**'),
        ('p',
            'Received with thanks from **$name** (Form No. **${_v(a, 'unique_id')}**) a sum of **₹ ${_v(a, 'amount_paid')}** towards booking of Flat No. **$flat**, **$floor** Floor, Wing **$wing**, Building/Tower **$tower** in "**$_project**".'),
        ('p', 'Mode of payment: **${_v(a, 'payment_mode', 'Offline')}**'),
        ('p', '**For $_promoterName**\nAuthorised Signatory'),
      ];
    default:
      return [
        ('title', 'AGREEMENT OF SALE'),
        ('p', 'Made at $_place on this **$day** day of **$month**'),
        ('h', 'BETWEEN:'),
        ('p',
            '**$_promoterName**, $_promoterDesc (Hereinafter referred to as "**THE PROMOTER**" which expression shall mean and include its successors, partners, executors and assignees of ONE PART)'),
        ('h', 'AND'),
        ('p',
            '**$name**, Age $age Years, Occupation: ${_v(a, 'occupation', 'N/A')}, (PAN NO ${_v(a, 'pan_number')}), (AADHAR NO. ${_v(a, 'aadhar_number')}), Residing At: $addr, Mobile No. ${_v(a, 'phone')}, Email: ${_v(a, 'email')} (Hereinafter called the "**PURCHASER/ALLOTTEE**" which expression shall, unless repugnant to the context mean and include his heirs, executors, legal representatives, successors and assigns) OF OTHER PART.'),
        ('h', 'WHEREAS:'),
        ('p',
            'A. The Promoter is absolute owner and in possession of land admeasuring $_land (hereinafter referred to as "The said land") and is developing a project known as "**$_project**" thereon registered under MahaRERA vide Registration No. **$_rera**.'),
        ('p',
            'B. The Purchaser, having been satisfied as to the title and ownership of the Promoter in and to the Said Premises and having understood the nature and extent of the project, has agreed to purchase from the Promoter Flat No. **$flat** on the **$floor** Floor, Wing **$wing**, Building/Tower **$tower** in the Said Building together with proportionate undivided share in the Said Land (Hereinafter referred to as "**The Said Flat**").'),
        ('h', 'NOW THIS AGREEMENT WITNESSETH:'),
        ('p', '1. The Promoter shall sell and the Purchaser shall purchase the Said Flat for a total consideration of **₹ $value**.'),
        ('p', '2. The Purchaser shall pay the consideration to the Promoter as per the payment schedule agreed between the parties.'),
      ];
  }
}

List<InlineSpan> _spans(String t, TextStyle base) {
  final parts = t.split('**');
  return [for (var i = 0; i < parts.length; i++) TextSpan(text: parts[i], style: i.isOdd ? base.copyWith(fontWeight: FontWeight.w800) : base)];
}

String _inlineHtml(String t) {
  final parts = const HtmlEscape().convert(t).split('**');
  final b = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    b.write(i.isOdd ? '<b>${parts[i]}</b>' : parts[i]);
  }
  return b.toString().replaceAll('\n', '<br>');
}

String buildPrintHtml(String doc, String page, Map a) {
  final b = StringBuffer(
      '<!doctype html><html><head><meta charset="utf-8"><title>$doc</title><style>@page{size:$page;margin:18mm}'
      'body{font-family:"Times New Roman",serif;font-size:13px;line-height:1.55;color:#000}'
      'h1{text-align:center;text-decoration:underline;font-size:20px}h2{font-size:15px;margin:16px 0 4px}'
      'p{text-align:justify;margin:6px 0}</style></head><body>');
  for (final bl in docBlocks(doc, a)) {
    final t = _inlineHtml(bl.$2);
    b.write(switch (bl.$1) { 'title' => '<h1>$t</h1>', 'h' => '<h2>$t</h2>', _ => '<p>$t</p>' });
  }
  b.write('<script>window.onload=function(){setTimeout(function(){window.print()},300)}</script></body></html>');
  return b.toString();
}

class DocumentGeneratorPage extends StatefulWidget {
  final Map<String, dynamic> a;
  const DocumentGeneratorPage({super.key, required this.a});
  @override
  State<DocumentGeneratorPage> createState() => _DocumentGeneratorPageState();
}

class _DocumentGeneratorPageState extends State<DocumentGeneratorPage> {
  String _doc = docTypes.first;
  String _page = 'A4';
  late Map<String, dynamic> _a = widget.a; // replaced by the full record (address, PAN, unit, payment) once loaded

  @override
  void initState() {
    super.initState();
    Api.i.get(Ep.one('${widget.a['id']}')).then((r) async {
      final ap = Map<String, dynamic>.from(r['applicant'] ?? {});
      final unit = r['unit'] is Map ? Map<String, dynamic>.from(r['unit']) : <String, dynamic>{};
      final pays = List<Map<String, dynamic>>.from((r['payments'] ?? []).map((e) => Map<String, dynamic>.from(e)));
      final paid = pays.where((p) => p['payment_status'] == 'completed').toList();
      final proj = r['project'] is Map ? Map<String, dynamic>.from(r['project']) : <String, dynamic>{};
      Map<String, dynamic> deed = {}, sched = {};
      try {
        final d = await Api.i.get('/admin/applicants/${widget.a['id']}/mortgage-deed');
        deed = Map<String, dynamic>.from((d['deed'] as Map?) ?? {});
        sched = Map<String, dynamic>.from((d['schedule'] as Map?) ?? {});
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _a = {
          ...widget.a,
          ...ap,
          if (unit.isNotEmpty) ...{
            'flat_no': unit['unit_number'],
            'floor': unit['floor'],
            'wing': unit['wing'],
            'tower': unit['tower'],
            'agreement_value': unit['consideration_amount'],
          },
          if (paid.isNotEmpty) ...{
            'receipt_no': paid.first['receipt_number'],
            'amount_paid': paid.first['amount'],
            'payment_mode': paid.first['payment_method'],
          },
          if (proj['bank_name'] != null) 'bank_name': proj['bank_name'],
          '_deed': deed,
          '_schedule': sched,
          '_unit': unit,
          '_project': proj,
        };
      });
    }).catchError((_) {});
  }

  Widget _preview() {
    const base = TextStyle(fontFamily: 'Times New Roman', fontFamilyFallback: ['Georgia', 'serif'], fontSize: 13.5, height: 1.55, color: Colors.black);
    return Panel(
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_doc, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: kInk)),
        const SizedBox(height: 4),
        Text('Applicant: ${_a['unique_id'] ?? '-'} - ${fullName(_a)}     Page Size: ${pageSizes[_page]}',
            style: const TextStyle(fontSize: 12, color: kMuted)),
        const SizedBox(height: 22),
        for (final bl in docBlocks(_doc, _a))
          switch (bl.$1) {
            'title' => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Center(
                    child: Text(bl.$2,
                        textAlign: TextAlign.center,
                        style: base.copyWith(fontSize: 22, fontWeight: FontWeight.w800, decoration: TextDecoration.underline)))),
            'h' => Padding(padding: const EdgeInsets.only(top: 14, bottom: 4), child: Text(bl.$2, style: base.copyWith(fontSize: 16, fontWeight: FontWeight.w800))),
            _ => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text.rich(TextSpan(children: _spans(bl.$2, base)), textAlign: TextAlign.justify)),
          },
      ]),
    );
  }

  Widget _header(double avail) {
    double w(double m) => avail < m ? avail : m;
    final dd = SizedBox(
      width: w(200),
      child: DropdownButtonFormField<String>(
        initialValue: _doc,
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        items: [for (final d in docTypes) DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() => _doc = v ?? _doc),
      ),
    );
    final ps = SizedBox(
      width: w(200),
      child: DropdownButtonFormField<String>(
        initialValue: _page,
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        items: [for (final e in pageSizes.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() => _page = v ?? _page),
      ),
    );
    final controls = Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
      dd,
      const Text('Page Size:', style: TextStyle(color: kMuted, fontSize: 13)),
      ps,
      FilledButton.icon(
        onPressed: () => openHtml(buildPrintHtml(_doc, _page, _a)),
        icon: const Icon(Icons.print_outlined, size: 18),
        label: const Text('Print / Save PDF'),
      ),
    ]);
    final title = Row(children: [
      TextButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 18, color: kInk),
          label: const Text('Back', style: TextStyle(color: kInk))),
      const SizedBox(width: 6),
      const Icon(Icons.description_outlined, color: kBlue, size: 28),
      const SizedBox(width: 8),
      const Flexible(child: Text('Document Generator', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: kInk))),
    ]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: kLine))),
      child: avail >= 900
          ? Row(children: [Expanded(child: title), const SizedBox(width: 12), controls])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 12), controls]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kBg,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => ListView(children: [
              _header(c.maxWidth - 40),
              Padding(
                padding: EdgeInsets.all(c.maxWidth < 700 ? 12 : 24),
                child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: _preview())),
              ),
            ]),
          ),
        ),
      );
}