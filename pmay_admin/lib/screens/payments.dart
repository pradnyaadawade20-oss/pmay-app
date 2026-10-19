import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});
  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  String? _err;

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
      final r = await Api.i.get(Ep.payments('pending'));
      _list = List<Map<String, dynamic>>.from(r['payments'] ?? []);
    } catch (e) {
      _err = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _act(Map p, String act) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(act == 'confirm' ? 'Confirm payment?' : 'Reject payment?'),
        content: Text('${p['applicant_name'] ?? p['unique_id']}  •  ₹${p['amount']}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: act == 'confirm' ? kGreen : kRed),
              onPressed: () => Navigator.pop(c, true),
              child: Text(act == 'confirm' ? 'Confirm' : 'Reject')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.i.post(Ep.payAct('${p['id']}', act));
      if (mounted) toast(context, act == 'confirm' ? 'Payment confirmed' : 'Payment rejected');
      _load();
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Widget _table() => Panel(
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: c.maxWidth < 760 ? 760 : c.maxWidth),
                child: DataTable(
                  dataRowMinHeight: 66,
                  dataRowMaxHeight: 66,
                  horizontalMargin: 22,
                  columns: const [
                    DataColumn(label: Text('APPLICANT')),
                    DataColumn(label: Text('AMOUNT')),
                    DataColumn(label: Text('MODE')),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('ACTION')),
                  ],
                  rows: [
                    for (final p in _list)
                      DataRow(cells: [
                        DataCell(Row(children: [
                          Avatar('${p['applicant_name'] ?? p['unique_id'] ?? '?'}', size: 38),
                          const SizedBox(width: 12),
                          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${p['applicant_name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
                            Text('${p['unique_id'] ?? ''}', style: const TextStyle(fontSize: 12, color: kMuted)),
                          ]),
                        ])),
                        DataCell(Text('₹${p['amount']}', style: const TextStyle(fontWeight: FontWeight.w800, color: kInk, fontSize: 15))),
                        DataCell(Text('${p['mode'] ?? 'offline'}'.toUpperCase(), style: const TextStyle(color: kMuted, fontSize: 12.5))),
                        DataCell(Pill('${p['payment_status']}', kOrange)),
                        DataCell(Row(children: [
                          FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: kGreen, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                              onPressed: () => _act(p, 'confirm'),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Confirm')),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: kRed, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                              onPressed: () => _act(p, 'reject'),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: const Text('Reject')),
                        ])),
                      ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) return EmptyState(icon: Icons.cloud_off_rounded, title: 'Failed to load data', sub: _err!);
    if (_list.isEmpty) {
      return const EmptyState(icon: Icons.task_alt_rounded, title: 'All caught up', sub: 'There are no pending payments');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${_list.length} pending payment${_list.length == 1 ? '' : 's'}', style: const TextStyle(color: kMuted)),
      const SizedBox(height: 12),
      Expanded(child: _table()),
    ]);
  }
}