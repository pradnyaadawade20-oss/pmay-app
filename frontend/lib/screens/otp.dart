import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Verify email OR phone (either one is enough, same rule as the website).
/// Step 1: choose method (email / SMS)  ->  Step 2: send OTP + enter OTP.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String? _type; // null = choose screen, 'email' | 'phone' = selected
  bool _sent = false, _busy = false;
  final _otp = TextEditingController();

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _body {
    final a = context.read<AppState>().applicant!;
    return {'type': _type, if (_type == 'email') 'email': a['email'] else 'phone': a['phone']};
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final r = await context.read<AppState>().api.postJson('/otp/send', _body);
      setState(() => _sent = true);
      // devOtp is only returned when backend runs with DEV_MODE=true
      if (mounted) toast(context, r['devOtp'] != null ? 'DEV OTP: ${r['devOtp']}' : 'OTP sent');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_otp.text.trim().length != 6) {
      toast(context, 'Enter the 6-digit OTP', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final s = context.read<AppState>();
      await s.api.postJson('/otp/verify', {..._body, 'otp': _otp.text.trim()});
      s.pendingTab = 1; // land on the Tracking tab after verification
      await s.refresh();
      if (mounted) {
        toast(context, 'Verified successfully');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() => setState(() {
        _type = null;
        _sent = false;
        _otp.clear();
      });

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppState>().applicant!;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 28, 18, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E6EE)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.apartment_rounded, size: 56, color: kBlue),
                const SizedBox(height: 14),
                const Text('Verify Your Contact',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Verify either your email or phone number to complete registration',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 15)),
                const SizedBox(height: 22),
                if (_type == null) ..._chooser(a) else ..._verifyStep(a),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // Screenshot 1 – choose method
  List<Widget> _chooser(Map<String, dynamic> a) => [
        const Text("Choose how you'd like to verify your identity:",
            textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 14),
        _optionCard(Icons.mail_outline, 'Verify via Email', '${a['email']}', () => setState(() => _type = 'email')),
        const SizedBox(height: 12),
        _optionCard(Icons.smartphone, 'Verify via SMS', '${a['phone']}', () => setState(() => _type = 'phone')),
      ];

  Widget _optionCard(IconData icon, String title, String sub, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E6EE)),
          ),
          child: Row(children: [
            CircleAvatar(radius: 20, backgroundColor: const Color(0xFFE3ECFA), child: Icon(icon, size: 20, color: kBlue)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(color: Colors.black54, fontSize: 14), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      );

  // Screenshot 2 – after selecting
  List<Widget> _verifyStep(Map<String, dynamic> a) {
    final isPhone = _type == 'phone';
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy ? null : _back,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back to options', style: TextStyle(fontSize: 16)),
          style: TextButton.styleFrom(foregroundColor: Colors.black87),
        ),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E6EE)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(isPhone ? Icons.phone_outlined : Icons.mail_outline, size: 20, color: Colors.black54),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(TextSpan(
                  style: const TextStyle(color: Colors.black54, fontSize: 15),
                  children: [
                    TextSpan(text: isPhone ? 'Verify your phone number: ' : 'Verify your email: '),
                    TextSpan(
                        text: isPhone ? '${a['phone']}' : '${a['email']}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ])),
            ),
          ]),
          const SizedBox(height: 14),
          if (_sent) ...[
            TextField(
                controller: _otp,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Enter 6-digit OTP', counterText: '')),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _busy ? null : _verify,
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Verify', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            TextButton(onPressed: _busy ? null : _send, child: const Text('Resend OTP')),
          ] else
            FilledButton(
                onPressed: _busy ? null : _send,
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(isPhone ? 'Send OTP to Phone' : 'Send OTP to Email',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        ]),
      ),
    ];
  }
}