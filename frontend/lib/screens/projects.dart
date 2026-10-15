import 'package:flutter/material.dart';
import '../theme.dart';

/// Projects tab: website ke "Project Details" + "For Our Communities" sections.
class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  static const _green = Color(0xFF1E8E4E);
  static const _navy = Color(0xFF1A2F6B);

  Widget _pair(Widget a, Widget b) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 28),
      children: [
        // ---------- Project Details ----------
        const _SectionHeader(
          tag: 'PMAY URBAN',
          title: 'Project Details',
          subtitle: "Dabbewala & Charmakar Building - A flagship PMAY project bringing affordable housing to "
              "deserving families of Mumbai's iconic Dabbewala community and skilled Charmakar artisans",
        ),
        const SizedBox(height: 22),
        _pair(
          const _DetailCard(
              icon: Icons.apartment_rounded,
              color: kOrange,
              label: 'Project Name',
              value: 'Dabbewala & Charmakar Building',
              sub: 'PMAY Urban Housing'),
          const _DetailCard(
              icon: Icons.location_on_outlined,
              color: kBlue,
              label: 'Location',
              value: 'Maharashtra',
              sub: 'Ambivali, Kalyan, Thane'),
        ),
        const SizedBox(height: 12),
        _pair(
          const _DetailCard(
              icon: Icons.home_outlined,
              color: _green,
              label: 'Total Units',
              value: '12,132 Flats',
              sub: 'Multiple configurations'),
          const _DetailCard(
              icon: Icons.credit_card,
              color: _navy,
              label: 'Price Range',
              value: '\u20b925.5 Lakhs',
              sub: 'Affordable EMI options'),
        ),

        // ---------- For Our Communities ----------
        const SizedBox(height: 40),
        const _SectionHeader(
          title: 'For Our Communities',
          subtitle: "Exclusively for members of Mumbai's legendary Dabbewala Association and skilled Charmakar Samaj artisans",
        ),
        const SizedBox(height: 22),
        const _CommunityCard(
          icon: Icons.delivery_dining,
          color: kOrange,
          title: 'Mumbai Dabbewala',
          subtitle: 'The world-famous lunch delivery network',
          body: "Mumbai's Dabbawalas have been serving the city for over 130 years with their remarkable efficiency. "
              "This housing project honors their dedication by providing quality homes for association members and their families.",
        ),
        const SizedBox(height: 14),
        const _CommunityCard(
          icon: Icons.handyman,
          color: _green,
          title: 'Charmakar Samaj',
          subtitle: 'Skilled leather artisans and craftsmen',
          body: "The Charmakar community has contributed significantly to India's leather industry with their exceptional "
              "craftsmanship. This project aims to provide dignified housing for these skilled artisans and their families.",
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String? tag;
  final String title, subtitle;
  const _SectionHeader({this.tag, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(children: [
        if (tag != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: kOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(tag!,
                style: const TextStyle(color: kOrange, fontSize: 11.5, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
          const SizedBox(height: 10),
        ],
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold, color: Color(0xFF1B1B1B))),
        const SizedBox(height: 8),
        Container(
            width: 52,
            height: 4,
            decoration: BoxDecoration(color: kOrange, borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 14),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14.5, color: Colors.black54, height: 1.5)),
      ]);
}

class _DetailCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value, sub;
  const _DetailCard({required this.icon, required this.color, required this.label, required this.value, required this.sub});

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: 0.09), Colors.white],
              stops: const [0, 0.6]),
          border: Border.all(color: color.withValues(alpha: 0.18)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.16), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 5, color: color),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 27),
              ),
              const SizedBox(height: 14),
              Text(label.toUpperCase(),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: color)),
              const SizedBox(height: 5),
              Text(value,
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, height: 1.25, color: Color(0xFF1B1B1B))),
              const SizedBox(height: 5),
              Text(sub, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
            ]),
          ),
        ]),
      );
}

class _CommunityCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle, body;
  const _CommunityCard({required this.icon, required this.color, required this.title, required this.subtitle, required this.body});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: 0.10), Colors.white],
              stops: const [0, 0.65]),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 1.4),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.14), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: color))),
          ]),
          const SizedBox(height: 14),
          Text(subtitle, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 12),
          Divider(height: 1, color: color.withValues(alpha: 0.25)),
          const SizedBox(height: 12),
          Text(body, style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.55)),
        ]),
      );
}