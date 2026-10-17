import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Login / Sign Up screen (same layout as the website's /auth page).
class AuthScreen extends StatefulWidget {
  final bool startOnSignUp;
  const AuthScreen({super.key, this.startOnSignUp = false});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool _signUp = widget.startOnSignUp;
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false, _hide = true;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (email.isEmpty || pass.isEmpty) {
      toast(context, 'Enter email and password', error: true);
      return;
    }
    if (_signUp) {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
        toast(context, 'Enter a valid email', error: true);
        return;
      }
      if (pass.length < 8) {
        toast(context, 'Password must be at least 8 characters', error: true);
        return;
      }
      setState(() => _busy = true);
      try {
        await context.read<AppState>().signUp(email, pass);
        if (mounted) {
          toast(context, 'Account created successfully');
          Navigator.of(context).popUntil((r) => r.isFirst);
        }
      } catch (e) {
        if (mounted) toast(context, e.toString(), error: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().login(email, pass);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: selected ? Colors.black : Colors.black54)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        leading: const BackButton(),
        title: const Text('Home', style: TextStyle(fontSize: 16)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.apartment_rounded, size: 52, color: kBlue),
                const SizedBox(height: 12),
                const Text('Krutarth',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Access the PMAY registration portal',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: const Color(0xFFE3E8EF), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    _tab('Login', !_signUp, () => setState(() => _signUp = false)),
                    _tab('Sign Up', _signUp, () => setState(() => _signUp = true)),
                  ]),
                ),
                const SizedBox(height: 18),
                const Text('Email', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'your@email.com')),
                const SizedBox(height: 16),
                const Text('Password', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                    controller: _pass,
                    obscureText: _hide,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                        hintText: _signUp ? 'At least 8 characters' : null,
                        suffixIcon: IconButton(
                            icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _hide = !_hide)))),
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: kBlue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_signUp ? 'Create Account' : 'Login',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}