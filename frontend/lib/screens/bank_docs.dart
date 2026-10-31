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
  _Doc('pan_card', 'PAN Card (mandatory)'),
  _Doc('identity_proof', 'Identity Proof (Aadhaar / Passport / Voter ID / Driving License)'),
  _Doc('address_proof', 'Address Proof (Aadhaar / Passport / Voter ID / Driving License / Utility Bill / Rent Agreement)'),
  _Doc('photographs', 'Passport-size Photographs (2–4)'),
];

const _profiles = <String, (String, List<_Doc>)>{
  'salaried': ('Salaried Person', [
    _Doc('salary_slips', 'Last 6 months\' salary slips'),
    _Doc('salary_bank_statement', 'Last 12 months\' bank statements (salary account)'),
    _Doc('form16_itr', 'Form 16 or ITR (last 2/3 years)'),
    _Doc('appointment_letter', 'Appointment / Confirmation Letter'),
  ]),
  'business': ('Business Person', [
    _Doc('business_bank_statement', 'Last 12 months current account statements (business)'),
    _Doc('business_registration', 'GST Registration / Shop & Establishment License'),
    _Doc('entity_proof', 'Partnership Deed / Incorporation Certificate / Udyam Registration'),
    _Doc('profit_loss', 'Profit & Loss Account (last 2–3 years, CA audited)'),
    _Doc('balance_sheet', 'Balance Sheet (last 2–3 years, CA audited)'),
    _Doc('business_itr', 'Income Tax Returns (last 2–3 years)'),
  ]),
  'nip': ('NIP (Non Income Proof)', [
    _Doc('nip_bank_statement', 'Bank statements (last 12 months) showing regular transactions'),
    _Doc('salary_certificate', 'Salary Certificate'),
    _Doc('employer_certificate', 'Employer\'s certificate confirming monthly payment (signed)'),
    _Doc('rental_income_proof', 'Rental / other income proof (if any)', required: false),
    _Doc('shop_license', 'Shop & Establishment License'),
    _Doc('business_place_photos', 'Photos of business proof / business place'),
  ]),
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