import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'theme.dart';

/// Tour ke targets. Shell/Home inhe apne widgets par lagate hain.
class TourKeys {
  static final apply = GlobalKey(debugLabel: 'tour_apply');
  static final bell = GlobalKey(debugLabel: 'tour_bell');
  static final tracking = GlobalKey(debugLabel: 'tour_tracking');
  static final projects = GlobalKey(debugLabel: 'tour_projects');
  static final profile = GlobalKey(debugLabel: 'tour_profile');
}

class _Step {
  final GlobalKey? target; // null = centered welcome card
  final String title;
  final String body;
  final IconData icon;
  const _Step(this.target, this.title, this.body, this.icon);
}

final _steps = <_Step>[
  const _Step(null, 'Welcome to Krutarth - PMAY',
      'A quick tour of the app. It takes less than a minute.', Icons.waving_hand_outlined),
  _Step(TourKeys.apply, 'Apply for your home',
      'Start or continue your PMAY application from here. Logged-in users see My Application.', Icons.home_work_outlined),
  _Step(TourKeys.bell, 'Notifications',
      'Updates about your application and verification show up here.', Icons.notifications_none),
  _Step(TourKeys.tracking, 'Tracking',
      'Follow every stage of your application, from registration to allotment.', Icons.route),
  _Step(TourKeys.projects, 'Projects',
      'Browse available housing projects, towers and flat details.', Icons.location_city),
  _Step(TourKeys.profile, 'Profile',
      'Personal details, language, help & support. You can replay this tour from here anytime.', Icons.person),
];

class AppTour {
  static const _store = FlutterSecureStorage();
  static const _key = 'tour_seen_v1';
  static OverlayEntry? _entry;

  static Future<bool> seen() async {
    try {
      return (await _store.read(key: _key)) == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> _markSeen() async {
    try {
      await _store.write(key: _key, value: '1');
    } catch (_) {}
  }

  /// Pehli baar ke liye: seen nahi hai to hi chalao.
  static Future<void> startIfFirstTime(BuildContext context) async {
    if (await seen()) return;
    if (!context.mounted) return;
    start(context);
  }

  static void start(BuildContext context) => startOn(Overlay.of(context, rootOverlay: true));

  /// Context unmount ho sakta hai (tab switch) to overlay pehle se pakad kar yahan do.
  static void startOn(OverlayState overlay) {
    if (_entry != null) return;
    _entry = OverlayEntry(builder: (_) => const _TourOverlay(onClose: _close));
    overlay.insert(_entry!);
  }

  static void _close() {
    _entry?.remove();
    _entry = null;
    _markSeen();
  }
}

class _TourOverlay extends StatefulWidget {
  final VoidCallback onClose;
  const _TourOverlay({required this.onClose});
  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  int _i = 0;

  Rect? _rectOf(GlobalKey? k) {
    final ctx = k?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _next() {
    if (_i >= _steps.length - 1) {
      widget.onClose();
    } else {
      setState(() => _i++);
    }
  }

  void _back() {
    if (_i > 0) setState(() => _i--);
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_i];
    final size = MediaQuery.of(context).size;
    final pad = MediaQuery.of(context).padding;
    final hole = _rectOf(step.target)?.inflate(6);
    final last = _i == _steps.length - 1;

    // Card hole ke upar ya neeche (jahan jagah ho). Hole nahi to beech mein.
    double? top, bottom;
    if (hole == null) {
      top = size.height * 0.3;
    } else if (hole.center.dy > size.height / 2) {
      bottom = size.height - hole.top + 14;
    } else {
      top = hole.bottom + 14;
    }

    final card = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 18, backgroundColor: kOrange.withValues(alpha: 0.15), child: Icon(step.icon, color: kOrange, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text(step.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 10),
          Text(step.body, style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87)),
          const SizedBox(height: 14),
          Row(children: [
            for (var d = 0; d < _steps.length; d++)
              Container(
                margin: const EdgeInsets.only(right: 5),
                width: d == _i ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(color: d == _i ? kBlue : Colors.black12, borderRadius: BorderRadius.circular(3)),
              ),
            const Spacer(),
            if (!last) TextButton(onPressed: widget.onClose, child: const Text('Skip')),
            if (_i > 0) TextButton(onPressed: _back, child: const Text('Back')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(80, 38), backgroundColor: kOrange),
              onPressed: _next,
              child: Text(last ? 'Done' : 'Next'),
            ),
          ]),
        ]),
      ),
    );

    return Stack(children: [
      // Scrim + spotlight hole. Tap absorb hota hai taaki neeche ka UI na chale.
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: CustomPaint(painter: _ScrimPainter(hole)),
        ),
      ),
      Positioned(left: 16, right: 16, top: top?.clamp(pad.top + 8, size.height), bottom: bottom, child: card),
    ]);
  }
}

class _ScrimPainter extends CustomPainter {
  final Rect? hole;
  _ScrimPainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final path = hole == null
        ? full
        : Path.combine(PathOperation.difference, full, Path()..addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(12))));
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.72));
    if (hole != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole!, const Radius.circular(12)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = kOrange,
      );
    }
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole;
}