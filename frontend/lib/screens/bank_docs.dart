import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../widgets.dart';

/// Documents the bank needs, per profile (from Bnak_Loan_Documents.xlsx).
/// Keep the keys in sync with backend/internal/app/bankdocs.go.
class _Doc {
  final String key, label;
  final bool required;
  const _Doc(this.key, this.label, {this.required = true});
}

const _common = [
  _Doc('pan_card', 'PAN Card'),
  _Doc('identity_proof', 'Identity Proof'),
  _Doc('address_proof', 'Address Proof'),
  _Doc('photographs', 'Photographs'),
];

const _profiles = <String, (String, List<_Doc>)>{
  'salaried': ('Salaried Person', [
    _Doc('salary_slips', 'Salary Slips (6 months)'),
    _Doc('salary_bank_statement', 'Bank Statement (12 months)'),
    _Doc('form16_itr', 'Form 16 / ITR'),
    _Doc('appointment_letter', 'Appointment Letter'),
  ]),
  'business': ('Business Person', [
    _Doc('business_bank_statement', 'Business Bank Statement'),
    _Doc('business_registration', 'GST / Shop License'),
    _Doc('entity_proof', 'Business Entity Proof'),
    _Doc('profit_loss', 'Profit & Loss Account'),
    _Doc('balance_sheet', 'Balance Sheet'),
    _Doc('business_itr', 'ITR (2–3 years)'),
  ]),
  'nip': ('NIP (Non Income Proof)', [
    _Doc('nip_bank_statement', 'Bank Statement (12 months)'),
    _Doc('salary_certificate', 'Salary Certificate'),
    _Doc('employer_certificate', 'Employer Certificate'),
    _Doc('rental_income_proof', 'Rental Income Proof', required: false),
    _Doc('shop_license', 'Shop License'),
    _Doc('business_place_photos', 'Business Place Photos'),
  ]),
};

const _hints = {
  'salaried': 'Identity/Address proof: Aadhaar, Passport, Voter ID or Driving License (address: or Utility Bill / Rent Agreement). Photographs: 2–4 passport size. Bank/ITR: last 12 months / 2–3 years.',
  'business': 'Identity/Address proof: Aadhaar, Passport, Voter ID or Driving License (address: or Utility Bill / Rent Agreement). Entity proof: Partnership Deed / Incorporation / Udyam. Financials: last 2–3 years, CA audited.',
  'nip': 'Identity/Address proof: Aadhaar, Passport, Voter ID or Driving License (address: or Utility Bill / Rent Agreement). Photographs: 2–4 passport size. Rental income proof is optional.',
};

class BankDocsCard extends StatefulWidget {
  const BankDocsCard({super.key});
  @override
  State<BankDocsCard> createState() => _BankDocsCardState();
}

class _BankDocsCardState extends State<BankDocsCard> {
  bool _busy = false;
  String? _profile;

  Future<void> _submit(String profile) async {
    setState(() => _busy = true);
    try {
      final s = context.read<AppState>();
      await s.api.postMultipart('/me/bank-documents',
          fields: {'profile_type': profile}, files: Map<String, String>.from(s.bankDocPicks));
      s.clearBankDocPicks();
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
    final state = context.watch<AppState>();
    final picked = state.bankDocPicks; // survives scrolling and tab switches (see AppState)
    final loan = state.loan;
    final status = loan?['loan_status'];
    final saved = (loan?['docs'] is Map) ? Map<String, dynamic>.from(loan!['docs'] as Map) : <String, dynamic>{};
    final profile = _profile ?? loan?['profile_type'] as String?;
    final docs = profile == null ? <_Doc>[] : [..._common, ..._profiles[profile]!.$2];
    final locked = saved.isNotEmpty && status != 'rejected';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (status == 'rejected')
        InfoCard(
            icon: Icons.error_outline,
            color: Colors.red,
            title: 'Documents rejected',
            message: '${loan?['verification_notes'] ?? 'Please re-upload the correct documents.'}'),
      DropdownButtonFormField<String>(
        value: profile,
        decoration: const InputDecoration(labelText: 'Select your profile', border: OutlineInputBorder()),
        items: [
          for (final e in _profiles.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1)),
        ],
        onChanged: locked
            ? null
            : (v) {
                state.clearBankDocPicks();
                setState(() => _profile = v);
              },
      ),
      const SizedBox(height: 12),
      if (profile != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_hints[profile]!, style: const TextStyle(fontSize: 12, color: Colors.black54))),
      if (profile == null)
        const Text('Choose Salaried, Business or NIP to see the documents the bank needs.')
      else ...[
        for (final d in docs)
          UploadTile(
              label: d.required ? d.label : '${d.label} – optional',
              path: picked[d.key],
              uploaded: saved[d.key] != null && status != 'rejected',
              onPick: () async {
                final f = await pickDoc();
                if (f != null) state.pickBankDoc(d.key, f);
              }),
        const SizedBox(height: 8),
        SizedBox(
            width: double.infinity,
            child: FilledButton(
                onPressed: _busy || picked.isEmpty ? null : () => _submit(profile),
                child: const Text('Upload selected documents'))),
        if (loan != null && status == 'pending')
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Once all ${docs.where((d) => d.required).length} required documents are uploaded, our team will review them.')),
      ],
    ]);
  }
}