import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';
import 'agreement_receipts.dart';
import 'bank_documents.dart';
import 'banking_loans.dart';
import 'applicant_detail.dart';
import 'payment_management.dart';
import 'unit_allotment.dart';
import 'validation_queue.dart';

/// Opens the screen that belongs to a stage (used by the stage dropdown).
/// [onOpen] is the shell's sub-screen opener (title, page).
void openStageScreen(void Function(String title, Widget page) onOpen, String stage) {
  final list = ApplicantsPage(initialStage: stage, onOpen: onOpen);
  switch (stage) {
    case '':
      onOpen('All Applicants', list);
    case 'stage_1_registered':
    case 'stage_2_validation': // stage 2 (validation) lives inside stage 1 in the backend
      onOpen('Validation Queue', const ValidationQueuePage());
    case 'stage_3_payment':
      onOpen('Payment Management', const PaymentManagementPage());
    case 'stage_4_allotment':
      onOpen('Unit Allotment', const UnitAllotmentPage());
    case 'stage_6_agreement_receipt':
      onOpen('Agreement Receipts', const AgreementReceiptsPage());
    case 'stage_7_bank_document':
      onOpen('Bank Documents', const BankDocumentsPage());
    case 'stage_8_bank_loan':
      onOpen('Banking / Loans', const BankingLoansPage());
    default:
      onOpen(stages[stage] ?? 'Applicants', list);
  }
}

class ApplicantsPage extends StatefulWidget {
  final String initialStage;

  /// When set (page opened as a sub-screen), choosing a stage in the dropdown
  /// switches to that stage's screen instead of only filtering this list.
  final void Function(String title, Widget page)? onOpen;
  const ApplicantsPage({super.key, this.initialStage = '', this.onOpen});
  @override
  State<ApplicantsPage> createState() => _ApplicantsPageState();
}

class _ApplicantsPageState extends State<ApplicantsPage> {
  final _q = TextEditingController();
  late String _stage = widget.initialStage;
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  String? _err;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _t?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final r = await Api.i.get(Ep.list(_q.text.trim(), _stage));
      _list = List<Map<String, dynamic>>.from(r['applicants'] ?? []);
    } catch (e) {
      _err = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  void _debounce() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _open(Map a) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => ApplicantDetail(id: '${a['id']}'));
    if (changed == true) _load();
  }

  Widget _toolbar() => Panel(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(builder: (context, c) {
          final avail = c.maxWidth.isFinite ? c.maxWidth : 600.0;
          return Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
                width: avail < 360 ? avail : 360,
                child: TextField(
                    controller: _q,
                    onChanged: (_) => _debounce(),
                    decoration: const InputDecoration(hintText: 'Search name, phone, ID or email', prefixIcon: Icon(Icons.search_rounded), isDense: true))),
            SizedBox(
              width: avail < 250 ? avail : 250,
              child: DropdownButtonFormField<String>(
                initialValue: (_stage.isEmpty || stages.containsKey(_stage)) ? _stage : '',
                isExpanded: true,
                decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.filter_list_rounded)),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All stages')),
                  for (final e in stages.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  final next = v ?? '';
                  if (next == _stage) return;
                  if (widget.onOpen != null) {
                    openStageScreen(widget.onOpen!, next);
                    return;
                  }
                  _stage = next;
                  _load();
                },
              ),
            ),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
            if (!_loading && _err == null) Text('${_list.length} applicants', style: const TextStyle(color: kMuted)),
          ]);
        }),
      );

  Widget _table() => Panel(
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: c.maxWidth < 820 ? 820 : c.maxWidth),
                child: DataTable(
                  showCheckboxColumn: false,
                  dataRowMinHeight: 66,
                  dataRowMaxHeight: 66,
                  horizontalMargin: 22,
                  columnSpacing: 28,
                  columns: const [
                    DataColumn(label: Text('APPLICANT')),
                    DataColumn(label: Text('CONTACT')),
                    DataColumn(label: Text('STAGE')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final a in _list)
                      DataRow(onSelectChanged: (_) => _open(a), cells: [
                        DataCell(Row(children: [
                          Avatar(fullName(a), size: 40),
                          const SizedBox(width: 12),
                          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(fullName(a), style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
                            Text('${a['unique_id'] ?? '-'}', style: const TextStyle(fontSize: 12, color: kMuted)),
                          ]),
                        ])),
                        DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${a['phone'] ?? '-'}', style: const TextStyle(color: kInk)),
                          Text('${a['email'] ?? '-'}', style: const TextStyle(fontSize: 12, color: kMuted)),
                        ])),
                        DataCell(stagePill(a)),
                        const DataCell(Icon(Icons.chevron_right_rounded, color: kMuted)),
                      ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _toolbar(),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _err != null
                  ? EmptyState(icon: Icons.cloud_off_rounded, title: 'Failed to load data', sub: _err!)
                  : _list.isEmpty
                      ? const EmptyState(icon: Icons.search_off_rounded, title: 'No applicants found', sub: 'Try changing your search or filters')
                      : _table(),
        ),
      ]);
}