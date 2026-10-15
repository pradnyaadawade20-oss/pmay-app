import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import 'login.dart';

const _navy = Color(0xFF0B3C9A);
const _orange = Color(0xFFF57C20);

/// Onboarding: native layout, har mobile size par fit hota hai.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF66C3FE), Color(0xFFBFE3FB), Colors.white],
            stops: [0.0, 0.35, 0.75],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: IntrinsicHeight(
                  child: Column(children: [
                    const Spacer(flex: 2),
                    _logo(),
                    const SizedBox(height: 12),
                    const Text('Krutarth - PMAY',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _navy)),
                    const Text('Pradhan Mantri Awas Yojana - Urban',
                        style: TextStyle(fontSize: 14, color: _navy)),
                    const SizedBox(height: 10),
                    _divider(),
                    const Spacer(flex: 2),
                    const Text('Your Dream Home',
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _navy)),
                    const Text('Awaits You',
                        style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: _orange, height: 1.1)),
                    SizedBox(width: 160, height: 10, child: CustomPaint(painter: _SwooshPainter())),
                    const SizedBox(height: 12),
                    const Text('Affordable Housing for a Brighter\nand Better Tomorrow',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.black54)),
                    const Spacer(flex: 2),
                    _photo(w),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _getStarted(context),
                    ),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('Already have an account?'),
                      TextButton(
                          onPressed: () =>
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                          child: const Text('Login', style: TextStyle(fontWeight: FontWeight.bold))),
                    ]),
                    const SizedBox(height: 4),
                    _features(),
                    const Spacer(),
                    Image.asset('assets/images/onboarding_bottom.png', width: w, fit: BoxFit.fitWidth),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo() => Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
            color: _navy,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6))]),
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.apartment_rounded, color: _navy, size: 34),
          ),
        ),
      );

  Widget _divider() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 80, height: 1.5, color: _navy),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.home_rounded, color: _navy, size: 18)),
        Container(width: 80, height: 1.5, color: _navy),
      ]);

  Widget _photo(double w) => SizedBox(
        width: w,
        height: w * 0.42,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
            stops: [0.0, 0.25, 0.9, 1.0],
          ).createShader(r),
          child: Image.asset('assets/images/onboarding_photo.png', fit: BoxFit.cover),
        ),
      );

  Widget _getStarted(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: () => context.read<AppState>().enterGuest(), // Get Started -> home screen
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            gradient: const LinearGradient(colors: [Color(0xFFFF6A00), Color(0xFFFF9A1F)]),
            boxShadow: [BoxShadow(color: _orange.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.home_rounded, color: Colors.white, size: 26),
            SizedBox(width: 12),
            Text('Get Started', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            SizedBox(width: 12),
            Icon(Icons.arrow_forward, color: Colors.white),
          ]),
        ),
      );

  Widget _feature(IconData icon, Color bg, Color fg, String label) => Expanded(
        child: Column(children: [
          CircleAvatar(radius: 26, backgroundColor: bg, child: Icon(icon, color: fg, size: 28)),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navy)),
        ]),
      );

  Widget _features() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _feature(Icons.verified_user_rounded, const Color(0xFFFFE6C7), _orange, 'Safe &\nTransparent'),
          _feature(Icons.schedule_rounded, const Color(0xFFCDE6FF), const Color(0xFF1E7BE0), 'Easy &\nFast Process'),
          _feature(Icons.groups_rounded, const Color(0xFFD3F3DC), const Color(0xFF2E9E5B), 'For a Better\nTomorrow'),
          _feature(Icons.apartment_rounded, const Color(0xFFE7D8FA), const Color(0xFF7B3FE4), 'Housing for All\nby 2025'),
        ]),
      );
}

class _SwooshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = _orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(0, s.height * 0.7)
      ..quadraticBezierTo(s.width * 0.5, s.height * 1.3, s.width, s.height * 0.1);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}