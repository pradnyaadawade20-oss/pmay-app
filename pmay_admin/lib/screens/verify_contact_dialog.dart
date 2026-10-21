import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../common.dart';

/// Opens the Verify Email / Verify Phone popup. Returns true when verification succeeded.
Future<bool?> showVerifyContactDialog(BuildContext context, {required Map applicant, required bool isEmail}) =>
    showDialog<bool>(context: context, builder: (_) => VerifyContactDialog(applicant: applicant, isEmail: isEmail));

class VerifyContactDialog extends StatefulWidget {
  final Map applicant;
  final bool isEmail;
  const VerifyContactDialog({super.key, required this.applicant, required this.isEmail});
  @override
  State<VerifyContactDialog> createState() => _VerifyContactDialogState();
}

class _VerifyContactDialogState extends State<VerifyContactDialog> {
  static const _resendSeconds = 30;
  final _otp = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _err;
  int _left = 0;
  Timer? _timer;

  String get _channel => widget.isEmail ? 'email' : 'phone';
  String get _value => '${widget.applicant[widget.isEmail ? 'email' : 'phone'] ?? ''}';
  String get _shown => widget.isEmail ? _value : (_value.startsWith('+') ? _value : '+91 $_value');
  String get _id => '${widget.applicant['id']}';

  @override
  void dispose() {
    _timer?.cancel();
    _note.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _left = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Api.i.post(Ep.sendContactOtp(_id), {'channel': _channel});
      if (!mounted) return;
      _otp.clear();
      setState(() {
        _sent = true;
        _busy = false;
      });
      _startTimer();
      toast(context, 'OTP has been sent to $_value');
    } catch (e) {
      if (mounted) {
        setState(() {
        _busy = false;
        _err = e.toString();
      });
      }
    }
  }

  final _note = TextEditingController();
  bool _confirmed = false;

  /// Manual verification: used when OTP email/SMS cannot be delivered. The admin confirms the contact
  /// (e.g. by calling the applicant) and the server marks it verified and records who did it.
  Future<void> _verifyManually() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Api.i.post(Ep.manualVerify(_id), {'channel': _channel, 'note': _note.text.trim()});
      if (!mounted) return;
      toast(context, widget.isEmail ? 'Email marked as verified' : 'Phone marked as verified');
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

  Widget _manualBox() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 18),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kOrange.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: kOrange.withValues(alpha: 0.4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Verify manually (no OTP)', style: TextStyle(fontWeight: FontWeight.w700, color: kInk)),
          const SizedBox(height: 4),
          Text('Use this when the OTP cannot be delivered. Confirm the ${widget.isEmail ? 'email' : 'phone number'} with the applicant first, for example by calling them.',
              style: const TextStyle(fontSize: 12.5, color: kMuted)),
          const SizedBox(height: 10),
          TextField(controller: _note, maxLength: 200, decoration: const InputDecoration(hintText: 'Note (optional), e.g. confirmed by phone call', counterText: '', isDense: true)),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            value: _confirmed,
            onChanged: _busy ? null : (v) => setState(() => _confirmed = v ?? false),
            title: Text('I confirm this ${widget.isEmail ? 'email' : 'phone number'} belongs to the applicant', style: const TextStyle(fontSize: 13)),
          ),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kOrange),
              onPressed: (_busy || !_confirmed) ? null : _verifyManually,
              icon: const Icon(Icons.verified_user_outlined, size: 18),
              label: const Text('Mark as Verified', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      );

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Api.i.post(Ep.verifyContactOtp(_id), {'channel': _channel, 'otp': _otp.text.trim()});
      if (!mounted) return;
      toast(context, widget.isEmail ? 'Email verified' : 'Phone verified');
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
  Widget build(BuildContext context) {
    final title = widget.isEmail ? 'Verify Email' : 'Verify Phone';
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(widget.isEmail ? Icons.mail_outline_rounded : Icons.phone_outlined, color: kBlue, size: 24),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk))),
              InkWell(onTap: () => Navigator.pop(context, false), child: const Icon(Icons.close_rounded, color: kMuted, size: 20)),
            ]),
            const SizedBox(height: 4),
            Text('Send OTP to $_value and verify', style: const TextStyle(fontSize: 14, color: kMuted)),
            const SizedBox(height: 16),
            if (!_sent) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFE6EAF2), borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.isEmail ? 'Email Address' : 'Phone Number', style: const TextStyle(fontSize: 14, color: kMuted)),
                  const SizedBox(height: 4),
                  Text(_shown, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: kInk)),
                ]),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _send,
                  icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Send OTP', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: kGreen.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: kGreen.withValues(alpha: 0.35))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('OTP sent to $_shown', style: const TextStyle(fontSize: 15, color: kGreen)),
                  const SizedBox(height: 4),
                  const Text('OTP is valid for 10 minutes. Enter the latest code received.', style: TextStyle(fontSize: 12.5, color: kGreen)),
                ]),
              ),
              const SizedBox(height: 18),
              const Text('Enter OTP', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kInk)),
              const SizedBox(height: 8),
              TextField(
                controller: _otp,
                autofocus: true,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 18, letterSpacing: 4, fontWeight: FontWeight.w600),
                onChanged: (_) => setState(() => _err = null),
                onSubmitted: (_) => _otp.text.length == 6 && !_busy ? _verify() : null,
                decoration: const InputDecoration(hintText: 'Enter 6-digit OTP', counterText: ''),
              ),
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: kRed, fontSize: 12.5))),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: (_left > 0 || _busy) ? null : _send,
                      child: Text(_left > 0 ? 'Resend (${_left}s)' : 'Resend OTP'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: (_busy || _otp.text.length != 6) ? null : _verify,
                      icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle_outline_rounded, size: 18),
                      label: const Text('Verify', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ]),
            ],
            if (!_sent && _err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: kRed, fontSize: 12.5))),
            _manualBox(),
          ]),
        ),
      ),
    );
  }
}