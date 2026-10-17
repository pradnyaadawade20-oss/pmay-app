import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'apply.dart';
import 'auth.dart';

// Leader card ka text yahan badlo. Quote sirf wahi daalo jo verified ho.
const _leaderName = 'Shri Narendra Modi';
const _leaderRole = "Hon'ble Prime Minister of India";
const _leaderQuote = ''; // khaali = neeche wali neutral line dikhegi

// Maharashtra ke Chief Minister ka card. Photo ke liye assets/images/fadnavis.jpg daalo
// aur pubspec.yaml ke assets mein us file ki line jodo. Tab tak gol placeholder dikhega.
const _cmName = 'Shri Devendra Fadnavis';
const _cmRole = "Hon'ble Chief Minister of Maharashtra";
const _cmQuote = ''; // khaali = neeche wali neutral line dikhegi. Quote sirf wahi daalo jo verified ho.
const _cmPhoto = 'assets/images/fadnavis.jpg';

class HomeScreen extends StatelessWidget {
  final void Function(int) onTab;
  const HomeScreen({super.key, required this.onTab});

  void _openApplication(BuildContext c) {
    final s = c.read<AppState>();
    if (!s.loggedIn) {
      Navigator.push(c, MaterialPageRoute(builder: (_) => const AuthScreen()));
      return;
    }
    if (s.applicant == null) {
      Navigator.push(c, MaterialPageRoute(builder: (_) => const ApplyScreen()));
      return;
    }
    onTab(1); // Tracking tab
  }

  Widget _stat(IconData icon, String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(children: [
            Icon(icon, color: kOrange, size: 22),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(color: kOrange, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );

  Widget _stats() => Row(children: [
        _stat(Icons.apartment, '12,132', 'Total flats'),
        const SizedBox(width: 10),
        _stat(Icons.currency_rupee, '\u20b925.5L', 'Starting price'),
        const SizedBox(width: 10),
        _stat(Icons.domain, '8', 'Towers'),
      ]);

  /// Banner: dark + halka blur building image, upar Dream Home text + Apply button.
  Widget _hero(BuildContext c, bool loggedIn) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
              child: Image.asset('assets/images/home_banner.jpg', fit: BoxFit.cover, alignment: Alignment.centerRight),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.55), Colors.black.withValues(alpha: 0.75)]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: kOrange, borderRadius: BorderRadius.circular(20)),
                child: const Text('PMAY Urban',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 14),
              const Text('Your Dream Home Awaits You',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, height: 1.2)),
              const SizedBox(height: 8),
              const Text('Affordable housing opportunities for eligible families.',
                  style: TextStyle(color: Colors.white, fontSize: 14, height: 1.3)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kOrange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _openApplication(c),
                  child: Text(loggedIn ? 'My Application \u2192' : 'Apply Now \u2192',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ]),
      );

  /// Banner ke neeche dono leaders ke cards.
  Widget _leaders() => Column(children: [
        _leaderCard(
          name: _leaderName,
          role: _leaderRole,
          quote: _leaderQuote.isEmpty
              ? 'Housing for All: an affordable, safe and dignified home for every eligible family.'
              : _leaderQuote,
          photo: 'assets/images/leader.jpg',
          ring: const Color(0xFFFBCBA2),
          bar: kOrange,
          tint: const Color(0xFFFFF1E6),
        ),
        const SizedBox(height: 12),
        _leaderCard(
          name: _cmName,
          role: _cmRole,
          quote: _cmQuote.isEmpty ? 'Affordable housing for every deserving family.' : _cmQuote,
          photo: _cmPhoto,
          ring: const Color(0xFFBFDCCB),
          bar: const Color(0xFF1E8E4E),
          tint: const Color(0xFFEAF6EF),
        ),
      ]);

  Widget _leaderCard({
    required String name,
    required String role,
    required String quote,
    required String photo,
    required Color ring,
    required Color bar,
    required Color tint,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint, Colors.white], stops: const [0, 0.6]),
          border: Border.all(color: ring.withValues(alpha: 0.6)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              photo,
              width: 74,
              height: 74,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 74,
                height: 74,
                color: const Color(0xFFE6E9EF),
                child: const Icon(Icons.person, size: 30, color: Colors.black38),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B1B1B))),
              const SizedBox(height: 3),
              Text(role, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.format_quote, size: 18, color: bar),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(quote,
                      style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.black87, height: 1.4)),
                ),
              ]),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return ListView(padding: const EdgeInsets.all(16), children: [
      _hero(context, s.loggedIn && s.applicant != null),
      const SizedBox(height: 12),
      _leaders(),
      const SizedBox(height: 12),
      _stats(),
      const SizedBox(height: 24),
      const RegistrationProcess(), // info only, no per-user progress here
      const SizedBox(height: 8),
    ]);
  }
}