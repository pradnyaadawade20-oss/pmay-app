import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../widgets.dart';

class BankDocsCard extends StatefulWidget {
  const BankDocsCard({super.key});
  @override
  State<BankDocsCard> createState() => _BankDocsCardState();
}

class _BankDocsCardState extends State<BankDocsCard> {
  static const _docs = {
    'upi_statement': ('UPI Statement', 'upi_statement_path'),
    'itr_year1': ('ITR Year 1 (Latest)', 'itr_year1_path'),
    'itr_year2': ('ITR Year 2', 'itr_year2_path'),
    'itr_year3': ('ITR Year 3', 'itr_year3_path'),
    'bank_statement': ('Bank Statement (6 months)', 'bank_statement_path'),
  };
  final _picked = <String, String>{};
  bool _busy = false;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final s = context.read<AppState>();
      await s.api.postMultipart('/me/bank-documents', files: _picked);
      _picked.clear();
      await s.refresh();
      if (mounted) toast(context, 'Documents uploaded');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loan = context.watch<AppState>().loan;
    final status = loan?['loan_status'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (status == 'rejected')
        InfoCard(
            icon: Icons.error_outline,
            color: Colors.red,
            title: 'Documents rejected',
            message: '${loan?['verification_notes'] ?? 'Please re-upload the correct documents.'}'),
      for (final e in _docs.entries)
        UploadTile(
            label: e.value.$1,
            path: _picked[e.key],
            uploaded: loan?[e.value.$2] != null && status != 'rejected',
            onPick: () async {
              final f = await pickDoc();
              if (f != null) setState(() => _picked[e.key] = f);
            }),
      const SizedBox(height: 8),
      SizedBox(
          width: double.infinity,
          child: FilledButton(
              onPressed: _busy || _picked.isEmpty ? null : _submit, child: const Text('Upload selected documents'))),
      if (loan != null && status == 'pending')
        const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Once all 5 documents are uploaded, our team will review them.')),
    ]);
  }
}
