import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';
import '../web_open.dart';
import 'verify_contact_dialog.dart';

/// Daily approval limit shown in the "Remaining Today" card. Change if your limit differs.
const kDailyApprovalLimit = 1000;

/// ---------- helpers (defensive: list API may use slightly different keys) ----------
bool _isRejected(Map a) => a['stage_2_status'] == 'rejected';
bool _isPending(Map a) => a['registration_stage'] == 'stage_1_registered' && !_isRejected(a);
bool _isApproved(Map a) => a['registration_stage'] != 'stage_1_registered';

bool _flag(Map a, List<String> keys) {
  for (final k in keys) {
    final v = a[k];
    if (v == true || v == 1 || '$v'.toLowerCase() == 'true') return true;
  }
  return false;
}

bool _emailOk(Map a) => _flag(a, ['email_verified', 'is_email_verified']);
bool _phoneOk(Map a) => _flag(a, ['phone_verified', 'is_phone_verified', 'mobile_verified']);

DateTime? _date(Map a, [List<String> keys = const ['created_at', 'submitted_at', 'registered_at']]) {
  for (final k in keys) {
    final d = DateTime.tryParse('${a[k] ?? ''}');
    if (d != null) return d.toLocal();
  }
  return null;
}

String _fmt(DateTime? d) =>
    d == null ? '-' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

bool _today(DateTime? d) {
  final n = DateTime.now();
  return d != null && d.year == n.year && d.month == n.month && d.day == n.day;
}

String _s(Object? v) => (v == null || '$v'.isEmpty) ? '-' : '$v';

/// =====================================================================
///  VALIDATION QUEUE PAGE
/// =====================================================================
class ValidationQueuePage extends StatefulWidget {
  const ValidationQueuePage({super.key});
  @override
  State<ValidationQueuePage> createState() => _ValidationQueuePageState();
}

class _ValidationQueuePageState extends State<ValidationQueuePage> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _err;
  int _tab = 0; // 0 pending, 1 approved, 2 rejected
  String _verif = 'all';
  bool _dateAsc = false;

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

  int get _pending => _all.where(_isPending).length;
  int get _approved => _all.where(_isApproved).length;
  int get _rejected => _all.where(_isRejected).length;
  int get _approvedToday => _all
      .where((a) => _isApproved(a) && _today(_date(a, const ['stage_2_reviewed_at', 'stage_2_at', 'approved_at', 'updated_at'])))
      .length;

  List<Map<String, dynamic>> get _rows {
    final q = _q.text.trim().toLowerCase();
    final base = _all.where(switch (_tab) {
      0 => _isPending,
      1 => _isApproved,
      _ => _isRejected,
    });
    final out = base.where((a) {
      if (q.isNotEmpty) {
        final hay = [fullName(a), a['unique_id'], a['email'], a['phone'], a['aadhar_number'], a['pan_number']]
            .map((e) => '${e ?? ''}'.toLowerCase())
            .join(' ');
        if (!hay.contains(q)) return false;
      }
      return switch (_verif) {
        'email' => _emailOk(a),
        'phone' => _phoneOk(a),
        'both' => _emailOk(a) && _phoneOk(a),
        'none' => !_emailOk(a) && !_phoneOk(a),
        _ => true,
      };
    }).toList();
    out.sort((x, y) {
      final dx = _date(x) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dy = _date(y) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return _dateAsc ? dx.compareTo(dy) : dy.compareTo(dx);
    });
    return out;
  }

  Future<void> _review(Map a) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => ReviewApplicantDialog(id: '${a['id']}'));
    if (changed == true) _load();
  }

  // ---------- stat cards ----------
  Widget _stat(String label, String v, Color c) => Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kLine), boxShadow: kShadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: kMuted)),
          const SizedBox(height: 6),
          Text(v, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: c)),
        ]),
      );

  Widget _stats(double w) {
    final remaining = (kDailyApprovalLimit - _approvedToday).clamp(0, kDailyApprovalLimit);
    final cards = [
      _stat('Pending Review', '$_pending', kOrange),
      _stat('Total Approved', '$_approved', kGreen),
      _stat('Total Rejected', '$_rejected', kRed),
      _stat('Approved Today', '$_approvedToday', kBlue),
      _stat('Remaining Today', '$remaining', kBlue),
    ];
    final cols = w >= 900 ? 5 : (w >= 560 ? 3 : 2);
    final cw = (w - 12 * (cols - 1)) / cols;
    return Wrap(spacing: 12, runSpacing: 12, children: [for (final c in cards) SizedBox(width: cw, child: c)]);
  }

  // ---------- tabs ----------
  Widget _tabBtn(int i, String label, int n, Color badge) {
    final on = _tab == i;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _tab = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: on ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(8), boxShadow: on ? kShadow : null),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? kInk : kMuted)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(color: badge.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Text('$n', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: badge)),
          ),
        ]),
      ),
    );
  }

  Widget _tabs() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _tabBtn(0, 'Pending', _pending, kOrange),
          _tabBtn(1, 'Approved', _approved, kGreen),
          _tabBtn(2, 'Rejected', _rejected, kRed),
        ]),
      );

  // ---------- verified badges ----------
  Future<void> _verifyContact(Map a, bool isEmail) async {
    final ok = await showVerifyContactDialog(context, applicant: a, isEmail: isEmail);
    if (ok == true && mounted) {
      setState(() {
        if (isEmail) {
          a['email_verified'] = true;
          a['is_email_verified'] = true;
        } else {
          a['phone_verified'] = true;
          a['is_phone_verified'] = true;
          a['mobile_verified'] = true;
        }
      });
    }
  }

  Widget _vBadge(String t, bool ok, {VoidCallback? onTap}) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: ok ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: ok ? kGreen.withValues(alpha: 0.10) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ok ? kGreen.withValues(alpha: 0.4) : kLine)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ok ? Icons.check_circle_outline_rounded : Icons.radio_button_unchecked_rounded, size: 13, color: ok ? kGreen : kMuted),
            const SizedBox(width: 4),
            Text(ok ? t : 'Verify $t', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: ok ? kGreen : kMuted)),
          ]),
        ),
      );

  Widget _table(List<Map<String, dynamic>> rows) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth < 900 ? 900 : c.maxWidth),
            child: DataTable(
              showCheckboxColumn: false,
              sortColumnIndex: 6,
              sortAscending: _dateAsc,
              dataRowMinHeight: 62,
              dataRowMaxHeight: 62,
              horizontalMargin: 16,
              columnSpacing: 24,
              columns: [
                const DataColumn(label: Text('ID')),
                const DataColumn(label: Text('NAME')),
                const DataColumn(label: Text('CONTACT')),
                const DataColumn(label: Text('AADHAR')),
                const DataColumn(label: Text('PAN')),
                const DataColumn(label: Text('VERIFIED')),
                DataColumn(label: const Text('DATE'), onSort: (_, asc) => setState(() => _dateAsc = asc)),
                const DataColumn(label: Text('ACTION')),
              ],
              rows: [
                for (final a in rows)
                  DataRow(cells: [
                    DataCell(Text(_s(a['unique_id']), style: const TextStyle(fontWeight: FontWeight.w700, color: kInk))),
                    DataCell(Text(fullName(a), style: const TextStyle(fontWeight: FontWeight.w600, color: kInk))),
                    DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_s(a['email']), style: const TextStyle(fontSize: 12.5, color: kInk)),
                      Text(_s(a['phone']), style: const TextStyle(fontSize: 12, color: kMuted)),
                    ])),
                    DataCell(Text(_s(a['aadhar_number']), style: const TextStyle(fontSize: 12.5))),
                    DataCell(Text(_s(a['pan_number']), style: const TextStyle(fontSize: 12.5))),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      _vBadge('Email', _emailOk(a), onTap: () => _verifyContact(a, true)),
                      const SizedBox(width: 6),
                      _vBadge('Phone', _phoneOk(a), onTap: () => _verifyContact(a, false)),
                    ])),
                    DataCell(Text(_fmt(_date(a)), style: const TextStyle(fontSize: 12.5))),
                    DataCell(OutlinedButton.icon(
                      onPressed: () => _review(a),
                      icon: const Icon(Icons.visibility_outlined, size: 15),
                      label: const Text('Review'),
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12.5)),
                    )),
                  ]),
              ],
            ),
          ),
        ),
      );

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
    final rows = _rows;
    return LayoutBuilder(
      builder: (context, c) => ListView(children: [
        _stats(c.maxWidth),
        const SizedBox(height: 16),
        Panel(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Applicant Validation', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk))),
              OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Refresh')),
            ]),
            const SizedBox(height: 2),
            Text('Review and verify applicant documents (${rows.length} results)', style: const TextStyle(fontSize: 12.5, color: kMuted)),
            const SizedBox(height: 14),
            _tabs(),
            const SizedBox(height: 14),
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: c.maxWidth < 700 ? c.maxWidth - 36 : c.maxWidth - 36 - 12 - 200,
                child: TextField(
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'Search by ID, name, email, phone, Aadhar, or PAN...', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _verif,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Verification')),
                    DropdownMenuItem(value: 'email', child: Text('Email verified')),
                    DropdownMenuItem(value: 'phone', child: Text('Phone verified')),
                    DropdownMenuItem(value: 'both', child: Text('Both verified')),
                    DropdownMenuItem(value: 'none', child: Text('Not verified')),
                  ],
                  onChanged: (v) => setState(() => _verif = v ?? 'all'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: EmptyState(icon: Icons.search_off_rounded, title: 'No applicants found', sub: 'Try changing your search or filters'))
            else
              _table(rows),
          ]),
        ),
      ]),
    );
  }
}

/// =====================================================================
///  REVIEW MODAL  (personal details + documents + checklist + approve/reject)
/// =====================================================================
class ReviewApplicantDialog extends StatefulWidget {
  final String id;
  const ReviewApplicantDialog({super.key, required this.id});
  @override
  State<ReviewApplicantDialog> createState() => _ReviewApplicantDialogState();
}

class _ReviewApplicantDialogState extends State<ReviewApplicantDialog> {
  static const _checks = [
    'Name matches Aadhar card',
    'Aadhar number verified',
    'Aadhar front image is clear',
    'Aadhar back image is clear',
    'PAN card is valid and clear',
  ];

  Map<String, dynamic>? _a;
  String? _err;
  bool _busy = false;
  final _done = <int>{};
  final _reason = TextEditingController();
  final _docs = <String, Future<Uint8List>>{};

  @override
  void initState() {
    super.initState();
    Api.i.get(Ep.one(widget.id)).then((r) {
      if (!mounted) return;
      setState(() => _a = Map<String, dynamic>.from(r['applicant'] ?? {}));
    }).catchError((e) {
      if (mounted) setState(() => _err = e.toString());
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _open(String kind, String label) async {
    final f = _docs.putIfAbsent(kind, () => Api.i.fileBytes(Ep.doc(widget.id, kind)));
    try {
      final bytes = await f;
      if (!mounted) return;
      final pdf = bytes.length > 3 && bytes[0] == 0x25 && bytes[1] == 0x50;
      if (pdf) {
        openBytes(bytes);
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
                  TextButton.icon(onPressed: () => openBytes(bytes), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Open in new tab')),
                  IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close_rounded, color: kMuted)),
                ]),
                const SizedBox(height: 10),
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(color: kBg, width: double.infinity, child: InteractiveViewer(maxScale: 5, child: Image.memory(bytes, fit: BoxFit.contain))),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    } catch (e) {
      _docs.remove(kind);
      if (mounted) toast(context, 'Document not available', error: true);
    }
  }

  Future<void> _decide(String decision) async {
    final reason = _reason.text.trim();
    if (decision == 'approve' && _done.length < _checks.length) {
      toast(context, 'Complete all checklist items before approving', error: true);
      return;
    }
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

  Widget _card(String title, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kLine)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _kv(String k, Object? v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
          TextSpan(text: _s(v), style: const TextStyle(color: kInk)),
        ]), style: const TextStyle(fontSize: 13)),
      );

  Widget _docRow(String kind, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _open(kind, label),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              const Icon(Icons.description_outlined, size: 16, color: kBlue),
              const SizedBox(width: 10),
              Expanded(child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kInk))),
              const Icon(Icons.open_in_new_rounded, size: 14, color: kMuted),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final a = _a;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
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
                            Text('Review Applicant: ${_s(a['unique_id'])}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
                            stagePill(a),
                          ]),
                        ),
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: kMuted)),
                      ]),
                      const Text('Verify all documents and complete the checklist', style: TextStyle(fontSize: 12.5, color: kMuted)),
                      const SizedBox(height: 16),
                      LayoutBuilder(builder: (context, c) {
                        final details = _card(
                            'Personal Details',
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              _kv('Name', fullName(a)),
                              _kv('Email', a['email']),
                              _kv('Phone', a['phone']),
                              _kv('Aadhar', a['aadhar_number']),
                              _kv('PAN', a['pan_number']),
                            ]));
                        final docs = _card('Uploaded Documents', Column(children: [for (final e in docKinds.entries.toList()..sort((x, y) => 0)) _docRow(e.key, e.value)]));
                        return c.maxWidth < 520
                            ? Column(children: [details, const SizedBox(height: 14), docs])
                            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(child: details),
                                const SizedBox(width: 14),
                                Expanded(child: docs),
                              ]);
                      }),
                      const SizedBox(height: 14),
                      _card(
                          'Verification Checklist',
                          Column(children: [
                            for (var i = 0; i < _checks.length; i++)
                              InkWell(
                                onTap: () => setState(() => _done.contains(i) ? _done.remove(i) : _done.add(i)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(children: [
                                    SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Checkbox(value: _done.contains(i), onChanged: (v) => setState(() => v == true ? _done.add(i) : _done.remove(i)))),
                                    const SizedBox(width: 8),
                                    Text(_checks[i], style: const TextStyle(fontSize: 13, color: kInk)),
                                  ]),
                                ),
                              ),
                          ])),
                      const SizedBox(height: 16),
                      const Text('Rejection Reason (if rejecting)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kInk)),
                      const SizedBox(height: 6),
                      TextField(controller: _reason, maxLines: 3, decoration: const InputDecoration(hintText: 'Enter reason for rejection...')),
                      const SizedBox(height: 16),
                      if (Api.i.canReview)
                        Row(children: [
                          Expanded(
                              child: FilledButton.icon(
                                  onPressed: _busy ? null : () => _decide('approve'),
                                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                  label: const Text('Approve'))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: kRed),
                                  onPressed: _busy ? null : () => _decide('reject'),
                                  icon: const Icon(Icons.cancel_outlined, size: 18),
                                  label: const Text('Reject'))),
                        ])
                      else
                        const Text('You do not have permission to approve or reject.', style: TextStyle(color: kMuted)),
                    ]),
                  ),
      ),
    );
  }
}