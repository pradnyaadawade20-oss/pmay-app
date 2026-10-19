import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onDone;
  const LoginScreen({super.key, required this.onDone});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _api = TextEditingController(text: Api.i.base);
  final _email = TextEditingController(text: Api.i.email ?? '');
  final _pw = TextEditingController();
  bool _busy = false, _hide = true, _adv = false;
  String? _err;

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    final a = Api.i;
    a.base = _api.text.trim().replaceAll(RegExp(r'/+$'), '');
    a.email = _email.text.trim();
    try {
      final r = await a.post(Ep.login, {'email': a.email, 'password': _pw.text});
      final roles = List.from(r['roles'] ?? []).map((e) => '$e'.toLowerCase());
      if (!roles.any(adminRoles.contains)) throw ApiException('This account does not have admin access');
      a.token = r['token'] as String;
      a.roles = roles.toList();
      await a.save();
      widget.onDone();
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _hero() => Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kNavy, kBlue])),
        padding: const EdgeInsets.all(56),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.apartment_rounded, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 28),
          const Text('Krutarth PMAY', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800)),
          const Text('Admin Console', style: TextStyle(color: kOrange, fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          const Text('Pradhan Mantri Awas Yojana - Urban: manage applicants, documents and payments in one place.',
              style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
          const SizedBox(height: 34),
          for (final t in const ['Document verification', 'Payment confirmation', 'Stage-wise tracking'])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, color: kOrange, size: 20),
                const SizedBox(width: 10),
                Text(t, style: const TextStyle(color: Colors.white, fontSize: 15)),
              ]),
            ),
        ]),
      );

  Widget _form() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Welcome back', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kInk)),
              const SizedBox(height: 4),
              const Text('Sign in with your admin account', style: TextStyle(color: kMuted)),
              const SizedBox(height: 28),
              TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded))),
              const SizedBox(height: 16),
              TextField(
                  controller: _pw,
                  obscureText: _hide,
                  onSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hide = !_hide)))),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: () => setState(() => _adv = !_adv),
                    icon: Icon(_adv ? Icons.expand_less_rounded : Icons.tune_rounded, size: 18),
                    label: const Text('Server settings')),
              ),
              if (_adv) ...[
                TextField(controller: _api, decoration: const InputDecoration(labelText: 'API URL', prefixIcon: Icon(Icons.dns_outlined))),
              ],
              if (_err != null)
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: kRed.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded, color: kRed, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_err!, style: const TextStyle(color: kRed))),
                  ]),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: Colors.white,
      body: wide
          ? Row(children: [Expanded(flex: 5, child: _hero()), Expanded(flex: 4, child: _form())])
          : _form(),
    );
  }
}