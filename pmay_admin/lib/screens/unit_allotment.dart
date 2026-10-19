import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';

/// Indian-style rupee formatting, e.g. 2550000 -> ₹25,50,000
String inr(Object? v) {
  final n = (v is num ? v : num.tryParse('${v ?? ''}') ?? 0).round();
  final s = n.abs().toString();
  String out;
  if (s.length <= 3) {
    out = s;
  } else {
    var rest = s.substring(0, s.length - 3);
    final last3 = s.substring(s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    out = '${parts.join(',')},$last3';
  }
  return '${n < 0 ? '-' : ''}₹$out';
}

class UnitAllotmentPage extends StatefulWidget {
  const UnitAllotmentPage({super.key});
  @override
  State<UnitAllotmentPage> createState() => _UnitAllotmentPageState();
}

class _UnitAllotmentPageState extends State<UnitAllotmentPage> {
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _eligible = [];
  bool _loading = true;
  String? _err;

  String _q = '';
  String _status = 'all'; // all | available | allotted
  String _wing = 'all';

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
      final r = await Api.i.get(Ep.units);
      final e = await Api.i.get(Ep.eligibleApplicants);
      _units = List<Map<String, dynamic>>.from(r['units'] ?? []);
      _eligible = List<Map<String, dynamic>>.from(e['applicants'] ?? []);
    } catch (e) {
      _err = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _isAvailable(Map u) => '${u['status']}'.toLowerCase() == 'available';

  List<String> get _wings {
    final w = _units.map((u) => '${u['wing'] ?? ''}').where((e) => e.isNotEmpty).toSet().toList()..sort();
    return w;
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _q.trim().toLowerCase();
    return _units.where((u) {
      if (_status == 'available' && !_isAvailable(u)) return false;
      if (_status == 'allotted' && _isAvailable(u)) return false;
      if (_wing != 'all' && '${u['wing']}' != _wing) return false;
      if (q.isEmpty) return true;
      return '${u['unit_number']} ${u['tower']} ${u['wing']}'.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _allot(Map u) async {
    final done = await showDialog<String>(
      context: context,
      builder: (c) => _AllotDialog(unit: u, eligible: _eligible),
    );
    if (done == null || !mounted) return;
    toast(context, done);
    _load();
  }

  // ---------- stats ----------
  Widget _stat(String label, int v, Color c) => Panel(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 13, color: kMuted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Text('$v', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: c, height: 1.1)),
        ]),
      );

  Widget _stats(bool narrow) {
    final total = _units.length;
    final avail = _units.where(_isAvailable).length;
    final cards = [
      _stat('Total Units', total, kInk),
      _stat('Available', avail, kGreen),
      _stat('Allotted', total - avail, kBlue),
      _stat('Eligible Applicants', _eligible.length, kOrange),
    ];
    if (narrow) {
      return Column(children: [
        Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: cards[2]), const SizedBox(width: 12), Expanded(child: cards[3])]),
      ]);
    }
    return Row(children: [
      for (var i = 0; i < cards.length; i++) ...[
        if (i > 0) const SizedBox(width: 16),
        Expanded(child: cards[i]),
      ],
    ]);
  }

  // ---------- filters ----------
  Widget _dropdown(String value, Map<String, String> items, ValueChanged<String> onChanged, double width) => SizedBox(
        width: width,
        child: DropdownButtonFormField<String>(
          initialValue: value,
          isDense: true,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kMuted),
          decoration: const InputDecoration(isDense: true),
          items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 14)))],
          onChanged: (v) => onChanged(v ?? 'all'),
        ),
      );

  Widget _filters(bool narrow) {
    final search = TextField(
      onChanged: (v) => setState(() => _q = v),
      decoration: const InputDecoration(hintText: 'Search by unit number, tower...', prefixIcon: Icon(Icons.search_rounded), isDense: true),
    );
    final status = _dropdown(_status, const {'all': 'All Status', 'available': 'Available', 'allotted': 'Allotted'}, (v) => setState(() => _status = v), 150);
    final wing = _dropdown(_wing, {'all': 'All Wings', for (final w in _wings) w: 'Wing $w'}, (v) => setState(() => _wing = v), 150);
    if (narrow) {
      return Column(children: [
        search,
        const SizedBox(height: 10),
        Row(children: [Expanded(child: status), const SizedBox(width: 10), Expanded(child: wing)]),
      ]);
    }
    return Row(children: [Expanded(child: search), const SizedBox(width: 12), status, const SizedBox(width: 12), wing]);
  }

  // ---------- table ----------
  Widget _table(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 56),
          child: Center(child: Text('No units found', style: TextStyle(fontSize: 16, color: kMuted))));
    }
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth < 860 ? 860 : c.maxWidth),
            child: DataTable(
              dataRowMinHeight: 60,
              dataRowMaxHeight: 60,
              horizontalMargin: 16,
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('UNIT NO.')),
                DataColumn(label: Text('TOWER')),
                DataColumn(label: Text('WING')),
                DataColumn(label: Text('FLOOR')),
                DataColumn(label: Text('CARPET AREA')),
                DataColumn(label: Text('AMOUNT')),
                DataColumn(label: Text('STATUS')),
                DataColumn(label: Text('ACTION')),
              ],
              rows: [
                for (final u in rows)
                  DataRow(cells: [
                    DataCell(Text('${u['unit_number']}', style: const TextStyle(fontWeight: FontWeight.w700, color: kInk))),
                    DataCell(Text('${u['tower'] ?? '-'}')),
                    DataCell(Text('${u['wing'] ?? '-'}')),
                    DataCell(Text('${u['floor'] ?? '-'}')),
                    DataCell(Text('${u['carpet_area'] ?? '-'} Sq.m')),
                    DataCell(Text(inr(u['amount']), style: const TextStyle(fontWeight: FontWeight.w600, color: kInk))),
                    DataCell(_isAvailable(u) ? const Pill('Available', kGreen) : const Pill('Allotted', kBlue)),
                    DataCell(_isAvailable(u)
                        ? OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: kInk, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                            onPressed: () => _allot(u),
                            icon: const Icon(Icons.home_outlined, size: 18),
                            label: const Text('Allot', style: TextStyle(fontWeight: FontWeight.w600)))
                        : Text('${u['allotted_to'] ?? '-'}', style: const TextStyle(color: kMuted, fontSize: 13))),
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
    if (_err != null) return EmptyState(icon: Icons.cloud_off_rounded, title: 'Failed to load data', sub: _err!);
    final narrow = MediaQuery.of(context).size.width < 760;
    final rows = _filtered;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _stats(narrow),
      const SizedBox(height: 20),
      Expanded(
        child: Panel(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Unit Inventory', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
                const SizedBox(height: 2),
                const Text('Manage and allot units to applicants', style: TextStyle(color: kMuted, fontSize: 13.5)),
                const SizedBox(height: 16),
                _filters(narrow),
                const SizedBox(height: 8),
              ]),
            ),
            Expanded(child: _table(rows)),
          ]),
        ),
      ),
    ]);
  }
}

/// "Allot Unit" dialog: unit summary + eligible applicant picker.
class _AllotDialog extends StatefulWidget {
  final Map unit;
  final List<Map<String, dynamic>> eligible;
  const _AllotDialog({required this.unit, required this.eligible});
  @override
  State<_AllotDialog> createState() => _AllotDialogState();
}

class _AllotDialogState extends State<_AllotDialog> {
  String? _sel;
  bool _busy = false;

  String _label(Map a) => '${a['unique_id'] ?? a['id']} - ${fullName(a)}';

  Widget _info(String k, String v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 12.5, color: kMuted)),
          const SizedBox(height: 3),
          Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
        ]),
      );

  Future<void> _confirm() async {
    final a = widget.eligible.firstWhere((e) => '${e['id']}' == _sel);
    setState(() => _busy = true);
    try {
      await Api.i.post(Ep.allot('${widget.unit['id']}'), {'applicant_id': _sel});
      if (mounted) Navigator.pop(context, 'Unit ${widget.unit['unit_number']} allotted to ${fullName(a)}');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, e.toString(), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.unit;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Allot Unit: ${u['unit_number']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk)),
                    const SizedBox(height: 3),
                    const Text('Select an eligible applicant to allot this unit', style: TextStyle(color: kMuted, fontSize: 13.5)),
                  ]),
                ),
                InkWell(
                    onTap: _busy ? null : () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 20, color: kMuted))),
              ]),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Row(children: [_info('Unit Number', '${u['unit_number']}'), _info('Floor', '${u['floor'] ?? '-'}')]),
                  const SizedBox(height: 14),
                  Row(children: [
                    _info('Wing / Tower', '${u['wing'] ?? '-'} / ${u['tower'] ?? '-'}'),
                    _info('Carpet Area', '${u['carpet_area'] ?? '-'} Sq.m'),
                  ]),
                ]),
              ),
              const SizedBox(height: 20),
              const Text('Select Applicant *', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kInk)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _sel,
                isExpanded: true,
                borderRadius: BorderRadius.circular(12),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kMuted),
                hint: Text(widget.eligible.isEmpty ? 'No eligible applicants available' : 'Select an eligible applicant',
                    style: const TextStyle(fontSize: 14, color: kInk)),
                items: [for (final a in widget.eligible) DropdownMenuItem(value: '${a['id']}', child: Text(_label(a), style: const TextStyle(fontSize: 14)))],
                onChanged: _busy || widget.eligible.isEmpty ? null : (v) => setState(() => _sel = v),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sel == null || _busy ? null : _confirm,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('Confirm Allotment', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}