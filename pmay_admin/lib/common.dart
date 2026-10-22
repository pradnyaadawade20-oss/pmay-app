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

/// Messages (success and errors) appear in the bottom-right corner; on narrow screens they span the bottom.
void toast(BuildContext c, String m, {bool error = false}) {
  const boxW = 380.0, gap = 24.0;
  final w = MediaQuery.of(c).size.width;
  final margin = w > boxW + 2 * gap
      ? EdgeInsets.only(left: w - boxW - gap, right: gap, bottom: gap)
      : const EdgeInsets.all(12);
  final sm = ScaffoldMessenger.of(c);
  sm.hideCurrentSnackBar(); // replace the previous message instead of queueing them
  sm.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    margin: margin,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    content: Text(m),
    backgroundColor: error ? kRed : kInk,
  ));
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