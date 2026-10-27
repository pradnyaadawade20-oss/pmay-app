import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';

/// Simple Mortgage Deed details (the numbered blanks of the approved draft that are not stored elsewhere).
/// Saved through /admin/applicants/{id}/mortgage-deed and /admin/mortgage-schedule.
/// The customer app prints the full deed from this data.

String _deedEp(String id) => '/admin/applicants/$id/mortgage-deed';
const _scheduleEp = '/admin/mortgage-schedule';

class _F {
  final String k, label;
  final String? hint;
  final bool req, date, number;
  final int lines;
  final int? max;
  final List<String>? options;
  const _F(this.k, this.label, {this.hint, this.req = false, this.date = false, this.number = false, this.lines = 1, this.max, this.options});
}

/// Holds one TextEditingController per field key.
class _Values {
  final Map<String, TextEditingController> c = {};
  void init(List<_F> specs, Map src) {
    for (final f in specs) {
      c[f.k] = TextEditingController(text: '${src[f.k] ?? ''}');
    }
  }

  String get(String k) => (c[k]?.text ?? '').trim();
  void dispose() {
    for (final e in c.values) {
      e.dispose();
    }
  }
}

Widget _section(String t, {String? sub}) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kInk)),
        if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub, style: const TextStyle(fontSize: 12.5, color: kMuted))),
      ]),
    );

Widget _fieldW(BuildContext context, _F f, _Values v, double w, VoidCallback rebuild) {
  final ctrl = v.c[f.k]!;
  Widget input;
  if (f.options != null) {
    final cur = f.options!.contains(ctrl.text) ? ctrl.text : null;
    input = DropdownButtonFormField<String>(
      initialValue: cur,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(hintText: f.hint ?? 'Select', isDense: true),
      items: [for (final o in f.options!) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
      onChanged: (x) {
        ctrl.text = x ?? '';
        rebuild();
      },
    );
  } else if (f.date) {
    input = TextField(
      controller: ctrl,
      readOnly: true,
      decoration: InputDecoration(hintText: f.hint ?? 'Select date', isDense: true, suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18)),
      onTap: () async {
        final now = DateTime.now();
        final init = DateTime.tryParse(ctrl.text) ?? now;
        final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(now.year - 2), lastDate: DateTime(now.year + 5));
        if (d != null) {
          ctrl.text = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          rebuild();
        }
      },
    );
  } else {
    input = TextField(
      controller: ctrl,
      minLines: f.lines,
      maxLines: f.lines,
      maxLength: f.max,
      keyboardType: f.number ? const TextInputType.numberWithOptions(decimal: true) : (f.lines > 1 ? TextInputType.multiline : null),
      decoration: InputDecoration(hintText: f.hint, isDense: true),
    );
  }
  return SizedBox(
    width: w,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(TextSpan(children: [
        TextSpan(text: f.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kInk)),
        if (f.req) const TextSpan(text: ' *', style: TextStyle(color: kRed)),
      ])),
      const SizedBox(height: 6),
      input,
    ]),
  );
}

Widget _grid(BuildContext context, List<_F> fs, _Values v, VoidCallback rebuild, {bool full = false}) => LayoutBuilder(builder: (context, c) {
      final cols = (!full && c.maxWidth >= 600) ? 2 : 1;
      final w = (c.maxWidth - 16 * (cols - 1)) / cols;
      return Wrap(spacing: 16, runSpacing: 14, children: [for (final f in fs) _fieldW(context, f, v, w, rebuild)]);
    });

Widget _shell(BuildContext context, {required String title, required String sub, required Widget body, required Widget footer}) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 780),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk)),
                  const SizedBox(height: 3),
                  Text(sub, style: const TextStyle(fontSize: 13, color: kMuted)),
                ]),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: kMuted)),
            ]),
          ),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: body)),
          Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 18), child: footer),
        ]),
      ),
    );

// ------------------------------------------------------------------ project-level property schedule
const _scheduleFields = <_F>[
  _F('district', 'District', hint: 'e.g. Thane', req: true),
  _F('taluka', 'Sub-Division / Taluka', hint: 'e.g. Kalyan', req: true),
  _F('authority_type', 'Local body type', options: ['Municipal Corporation', 'Municipal Council', 'Cantonment Board', 'Grampanchayat']),
  _F('authority_name', 'Local body name', hint: 'e.g. Kalyan Dombivli Municipal Corporation', req: true),
  _F('village', 'Village', hint: 'e.g. Ambivali', req: true),
  _F('survey_type', 'Survey type', options: ['City Survey No.', 'Gat No.', 'Final Plot No.', 'Survey No.', 'Nazul Sheet No.', 'Khasra No.']),
  _F('survey_no', 'Survey number', hint: 'e.g. 65', req: true),
  _F('plot_no', 'Hissa / Plot No.', hint: 'e.g. 4'),
];
const _boundaryFields = <_F>[
  _F('east', 'East boundary', hint: 'Property No. / Name'),
  _F('south', 'South boundary', hint: 'Property No. / Name'),
  _F('west', 'West boundary', hint: 'Property No. / Name'),
  _F('north', 'North boundary', hint: 'Property No. / Name'),
];

/// One-time details of the land that are the same for every flat in the project.
class MortgageScheduleDialog extends StatefulWidget {
  const MortgageScheduleDialog({super.key});
  @override
  State<MortgageScheduleDialog> createState() => _MortgageScheduleDialogState();
}

class _MortgageScheduleDialogState extends State<MortgageScheduleDialog> {
  final _v = _Values();
  bool _loading = true, _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.get(_scheduleEp);
      _v.init([..._scheduleFields, ..._boundaryFields], Map<String, dynamic>.from((r['schedule'] as Map?) ?? {}));
    } catch (e) {
      _v.init([..._scheduleFields, ..._boundaryFields], {});
      _err = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    for (final f in _scheduleFields) {
      if (f.req && _v.get(f.k).isEmpty) {
        setState(() => _err = '${f.label} is required');
        return;
      }
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Api.i.post(_scheduleEp, {
        'data': {for (final f in [..._scheduleFields, ..._boundaryFields]) f.k: _v.get(f.k)}
      });
      if (!mounted) return;
      toast(context, 'Property schedule saved');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _shell(
        context,
        title: 'Property Schedule (Project)',
        sub: 'Same land details for every flat. Filled once, used in all mortgage deeds.',
        body: _loading
            ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _section('Land details'),
                _grid(context, _scheduleFields, _v, () => setState(() {})),
                _section('Property boundaries', sub: 'Default boundaries. A flat can override them in its own deed form.'),
                _grid(context, _boundaryFields, _v, () => setState(() {})),
                if (_err != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_err!, style: const TextStyle(color: kRed, fontWeight: FontWeight.w600))),
              ]),
        footer: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          const SizedBox(width: 10),
          FilledButton(
              onPressed: _busy || _loading ? null : _save,
              child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save')),
        ]),
      );
}

// ------------------------------------------------------------------ per-applicant deed details
const _execFields = <_F>[
  _F('exec_date', 'Date of execution (1)', date: true, req: true),
  _F('exec_place', 'Location (2)', hint: 'e.g. Kalyan', req: true),
];
const _bankFields = <_F>[
  _F('bank_name', 'Bank name (7)', req: true),
  _F('bank_branch', 'Branch at (10)', req: true),
  _F('bank_address', 'Bank address (9)', req: true, lines: 2),
  _F('signatory_name', 'Authorized signatory name (36)', req: true),
  _F('signatory_designation', 'Designation of authorized signatory (8)', hint: 'e.g. Branch Manager', req: true),
  _F('bank_tan', 'TAN number (11)', req: true),
  _F('bank_uid', 'UID (12A)'),
  _F('bank_mobile', 'Bank mobile no. (12B)'),
  _F('bank_email', 'Bank email id (12C)'),
];
const _loanFields = <_F>[
  _F('ownership_by', 'How the property was acquired (13)',
      hint: 'e.g. Agreement for Sale registered as document No. ___ year ___ in the office of the Sub-Registrar ___', req: true, lines: 3),
  _F('loan_purpose', 'Purpose of loan (14)', hint: 'Purchase of flat'),
  _F('loan_amount', 'Loan amount, as per sanction letter (15, 16)', hint: 'e.g. 2000000', req: true, number: true),
  _F('loan_period_years', 'Loan period in years (17)', hint: 'e.g. 20', req: true, number: true),
  _F('interest_rate', 'Rate of interest % per annum (18)', hint: 'e.g. 8.5', req: true, number: true),
  _F('installment_amount', 'Installment amount (19, optional)', number: true),
  _F('installment_type', 'Installment type', options: ['monthly', 'quarterly']),
  _F('insurance_amount', 'Insurance amount, as per bank requirement (20)', req: true, number: true),
];
const _extraFields = <_F>[
  _F('extra_terms', 'Other terms and conditions (11A, optional, up to 1000 characters)', lines: 4, max: 1000),
];
const _witnessFields = <_F>[
  _F('witness1_name', 'Witness 1 name (37)', req: true),
  _F('witness1_address', 'Witness 1 address (37)', req: true),
  _F('witness2_name', 'Witness 2 name (38)', req: true),
  _F('witness2_address', 'Witness 2 address (38)', req: true),
];

List<_F> get _allDeedFields => [..._execFields, ..._bankFields, ..._loanFields, ..._extraFields, ..._witnessFields, ..._boundaryFields];

class MortgageDeedDialog extends StatefulWidget {
  final String id;
  const MortgageDeedDialog({super.key, required this.id});
  @override
  State<MortgageDeedDialog> createState() => _MortgageDeedDialogState();
}

class _MortgageDeedDialogState extends State<MortgageDeedDialog> {
  final _v = _Values();
  Map<String, dynamic> _a = {}, _unit = {};
  bool _scheduleSet = false, _saved = false;
  bool _loading = true, _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final init = <String, dynamic>{};
    try {
      final r = await Api.i.get(Ep.one(widget.id));
      _a = Map<String, dynamic>.from((r['applicant'] as Map?) ?? {});
      _unit = Map<String, dynamic>.from((r['unit'] as Map?) ?? {});
      final p = Map<String, dynamic>.from((r['project'] as Map?) ?? {});
      init['bank_name'] = p['bank_name'] ?? '';
      init['bank_branch'] = p['bank_branch'] ?? '';
      init['loan_purpose'] = 'Purchase of flat';
      init['installment_type'] = 'monthly';
      final d = await Api.i.get(_deedEp(widget.id));
      final saved = Map<String, dynamic>.from((d['deed'] as Map?) ?? {});
      final sc = Map<String, dynamic>.from((d['schedule'] as Map?) ?? {});
      _saved = saved.isNotEmpty;
      _scheduleSet = '${sc['district'] ?? ''}'.isNotEmpty && '${sc['survey_no'] ?? ''}'.isNotEmpty;
      init.addAll(saved);
    } catch (e) {
      _err = e.toString();
    }
    _v.init(_allDeedFields, init);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    for (final f in _allDeedFields) {
      if (f.req && _v.get(f.k).isEmpty) {
        setState(() => _err = '${f.label} is required');
        return;
      }
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Api.i.post(_deedEp(widget.id), {
        'data': {for (final f in _allDeedFields) f.k: _v.get(f.k)}
      });
      if (!mounted) return;
      toast(context, 'Mortgage deed details saved. The applicant can now download the deed in the app.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = e.toString();
        });
      }
    }
  }

  Widget _kv(String k, Object? v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
          TextSpan(text: (v == null || '$v'.isEmpty) ? '-' : '$v', style: const TextStyle(color: kInk)),
        ]), style: const TextStyle(fontSize: 13)),
      );

  Widget _auto() {
    final unitTxt = _unit.isEmpty
        ? 'Unit not allotted yet'
        : 'Unit ${_unit['unit_number'] ?? '-'}, Floor ${_unit['floor'] ?? '-'}, ${_unit['building_name'] ?? ''}, Carpet ${_unit['carpet_area_sqm'] ?? '-'} sq.m';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: kLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _kv('Mortgagor', fullName(_a)),
        _kv('Age / Occupation', '${_a['age'] ?? '-'} / ${_a['occupation'] ?? '-'}'),
        _kv('Address', _a['full_address']),
        _kv('PAN / Aadhaar', '${_a['pan_number'] ?? '-'} / ${_a['aadhar_number'] ?? '-'}'),
        _kv('Mobile / Email', '${_a['phone'] ?? '-'} / ${_a['email'] ?? '-'}'),
        _kv('Property', unitTxt),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    void rb() => setState(() {});
    return _shell(
      context,
      title: 'Prepare Mortgage Deed: ${_a['unique_id'] ?? ''}',
      sub: 'Fill the details that are not already in the system. Numbers in brackets match the approved draft.',
      body: _loading
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _section('Filled automatically', sub: 'Taken from the applicant and unit records (items 3 to 6D, 27 to 30).'),
              _auto(),
              if (!_scheduleSet)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('Project Property Schedule is not set yet. Open "Property Schedule" on the Mortgage page, otherwise district, village and survey number stay blank in the deed.',
                      style: const TextStyle(color: kOrange, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              _section('Execution'),
              _grid(context, _execFields, _v, rb),
              _section('Mortgagee (Bank)'),
              _grid(context, _bankFields, _v, rb),
              _section('Ownership and loan terms'),
              _grid(context, _loanFields, _v, rb),
              _section('Other terms'),
              _grid(context, _extraFields, _v, rb, full: true),
              _section('Witnesses'),
              _grid(context, _witnessFields, _v, rb),
              _section('Boundaries for this flat (optional)', sub: 'Leave blank to use the project default boundaries.'),
              _grid(context, _boundaryFields, _v, rb),
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_err!, style: const TextStyle(color: kRed, fontWeight: FontWeight.w600))),
            ]),
      footer: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        if (_saved) const Expanded(child: Text('Details already saved. Saving again updates them.', style: TextStyle(color: kMuted, fontSize: 12.5))),
        OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        const SizedBox(width: 10),
        FilledButton(
            onPressed: _busy || _loading ? null : _save,
            child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Deed Details')),
      ]),
    );
  }
}