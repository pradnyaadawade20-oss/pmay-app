import 'package:flutter/material.dart';
import '../common.dart';
import 'collect_payment_dialog.dart';

String _d(dynamic v) {
  final d = DateTime.tryParse('$v');
  if (d == null) return '-';
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
}

/// "Applicants Awaiting Payment" — validated applicants at the payment stage who haven't
/// completed their booking payment yet. Mirrors the reference admin panel: a Collect Payment
/// button (online Cashfree or offline receipt) and a quick Upload Receipt shortcut per row.
class AwaitingPaymentsPage extends StatefulWidget {
  final List<Map<String, dynamic>> applicants;
  final num totalCost;
  final VoidCallback onChanged;
  const AwaitingPaymentsPage({super.key, required this.applicants, required this.totalCost, required this.onChanged});

  @override
  State<AwaitingPaymentsPage> createState() => _AwaitingPaymentsPageState();
}

class _AwaitingPaymentsPageState extends State<AwaitingPaymentsPage> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return widget.applicants;
    return widget.applicants.where((a) {
      final hay = '${a['unique_id']} ${a['applicant_name']} ${a['email']} ${a['phone']}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _open(Map a, {required bool offline}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => CollectPaymentDialog(applicant: a, totalCost: widget.totalCost, startOffline: offline),
    );
    if (changed == true) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Panel(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Applicants Awaiting Payment', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk)),
        const SizedBox(height: 4),
        const Text('Validated applicants ready to make payment. Upload receipts on their behalf, or collect online.', style: TextStyle(fontSize: 14, color: kMuted)),
        const SizedBox(height: 18),
        TextField(
          controller: _q,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'Search by form no, name, email, or phone...', prefixIcon: Icon(Icons.search_rounded), isDense: true),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: EmptyState(icon: Icons.task_alt_rounded, title: 'All caught up', sub: 'No applicants are awaiting payment'),
          )
        else
          LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: c.maxWidth < 900 ? 900 : c.maxWidth),
                child: DataTable(
                  dataRowMinHeight: 64,
                  dataRowMaxHeight: 64,
                  horizontalMargin: 8,
                  columns: const [
                    DataColumn(label: Text('FORM NO.')),
                    DataColumn(label: Text('NAME')),
                    DataColumn(label: Text('EMAIL')),
                    DataColumn(label: Text('PHONE')),
                    DataColumn(label: Text('DATE')),
                    DataColumn(label: Text('ACTION')),
                  ],
                  rows: [
                    for (final a in rows)
                      DataRow(cells: [
                        DataCell(Text('${a['unique_id'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w700, color: kInk))),
                        DataCell(Text('${a['applicant_name'] ?? '-'}', style: const TextStyle(color: kInk))),
                        DataCell(Text('${a['email'] ?? '-'}', style: const TextStyle(color: kMuted, fontSize: 13))),
                        DataCell(Text('${a['phone'] ?? '-'}', style: const TextStyle(color: kMuted, fontSize: 13))),
                        DataCell(Text(_d(a['created_at']), style: const TextStyle(color: kInk, fontSize: 13))),
                        DataCell(Row(children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                            onPressed: () => _open(a, offline: false),
                            icon: const Icon(Icons.credit_card_rounded, size: 16),
                            label: const Text('Collect Payment'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: kInk, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                            onPressed: () => _open(a, offline: true),
                            icon: const Icon(Icons.upload_file_rounded, size: 16),
                            label: const Text('Upload Receipt'),
                          ),
                        ])),
                      ]),
                  ],
                ),
              ),
            ),
          ),
      ]),
    );
  }
}