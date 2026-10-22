import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

const kBlue = Color(0xFF1649A8);
const kNavy = Color(0xFF0B2559);
const kOrange = Color(0xFFF57C20);
const kBg = Color(0xFFF4F6FB);
const kGreen = Color(0xFF1E8E4E);
const kRed = Color(0xFFD93025);
const kInk = Color(0xFF1B2433);
const kMuted = Color(0xFF6B7585);
const kLine = Color(0xFFE6EAF2);
const kShadow = [BoxShadow(color: Color(0x12101828), blurRadius: 18, offset: Offset(0, 6))];

const stages = {
  'stage_1_registered': 'Registered / Under review',
  'stage_3_payment': 'Payment',
  'stage_4_allotment': 'Allotment',
  'stage_5_agreement': 'Agreement',
  'stage_6_agreement_receipt': 'Agreement review',
  'stage_7_bank_document': 'Bank documents',
  'stage_8_bank_loan': 'Bank loan',
  'stage_9_mortgage': 'Mortgage',
  'stage_10_completed': 'Completed',
};

const docKinds = {
  'passport_photo': 'Passport Photo',
  'membership_proof': 'Membership Proof',
  'aadhar_front': 'Aadhaar Front',
  'aadhar_back': 'Aadhaar Back',
  'pan_front': 'PAN Card',
};

String fullName(Map a) {
  final n = '${a['first_name'] ?? ''} ${a['last_name'] ?? ''}'.trim();
  return n.isEmpty ? '-' : n;
}

OverlayEntry? _toastEntry;
Timer? _toastTimer;

void _removeToast() {
  _toastTimer?.cancel();
  _toastTimer = null;
  _toastEntry?.remove();
  _toastEntry = null;
}

/// Messages (success and errors) appear in the bottom-right corner, ABOVE dialogs and popups
/// (a normal SnackBar is drawn under the dialog's dark barrier and is hard to read). On narrow
/// screens the message spans the bottom. It disappears by itself, or when its X is tapped.
void toast(BuildContext c, String m, {bool error = false}) {
  final overlay = Overlay.maybeOf(c, rootOverlay: true);
  if (overlay == null) {
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? kRed : kInk));
    return;
  }
  _removeToast(); // replace the previous message instead of stacking them
  final w = MediaQuery.of(c).size.width;
  final boxW = math.min(420.0, w - 24);
  final bg = error ? const Color(0xFFB3261E) : kInk;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      right: 16,
      bottom: 16,
      width: boxW,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 180),
        builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child)),
        child: Material(
          color: bg,
          elevation: 12,
          borderRadius: BorderRadius.circular(12),
          shadowColor: Colors.black,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(m, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, height: 1.35, decoration: TextDecoration.none)),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  if (identical(_toastEntry, entry)) _removeToast();
                },
                child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.close_rounded, color: Colors.white70, size: 18)),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  _toastEntry = entry;
  _toastTimer = Timer(Duration(seconds: error ? 7 : 4), () {
    if (identical(_toastEntry, entry)) _removeToast();
  });
}

/// Status pill with a small dot.
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

Widget stagePill(Map a) {
  if (a['stage_2_status'] == 'rejected') return const Pill('Rejected', kRed);
  final st = '${a['registration_stage']}';
  final color = st == 'stage_1_registered' ? kOrange : (st == 'stage_10_completed' ? kGreen : kBlue);
  return Pill(stages[st] ?? st, color);
}

/// Initials avatar.
class Avatar extends StatelessWidget {
  final String name;
  final double size;
  const Avatar(this.name, {super.key, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final ini = name.trim().split(RegExp(r'[\s@._]+')).where((e) => e.isNotEmpty).take(2).map((e) => e[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
          shape: BoxShape.circle, gradient: LinearGradient(colors: [kBlue, Color(0xFF3B7DDD)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Text(ini.isEmpty ? '?' : ini, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: size * 0.36)),
    );
  }
}

/// White rounded card used everywhere.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        padding: padding,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine), boxShadow: kShadow),
        child: child,
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  const EmptyState({super.key, required this.icon, required this.title, required this.sub});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: kBlue.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Icon(icon, size: 38, color: kBlue),
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kInk)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(color: kMuted)),
        ]),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final IconData icon;
  const SectionTitle(this.text, this.icon, {super.key});
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18, color: kBlue),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
      ]);
}

ThemeData appTheme() => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: kBg,
      colorScheme: ColorScheme.fromSeed(seedColor: kBlue, primary: kBlue, secondary: kOrange),
      dialogTheme: DialogThemeData(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(Color(0xFFF7F9FC)),
        headingTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.6),
        dividerThickness: 0.6,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kLine)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kLine)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBlue, width: 1.6)),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: kBlue,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: kBlue,
              side: const BorderSide(color: kLine),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
    );