import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:image/image.dart' as img;
import 'theme.dart';

/// "Crop & Adjust Image" dialog (same as the website): zoom slider, rotate left/right,
/// optional free crop, Apply / Cancel.
/// Returns the cropped photo as JPG bytes (white background), or null if cancelled.
Future<Uint8List?> showCropDialog(BuildContext context, Uint8List bytes) =>
    showDialog<Uint8List>(context: context, barrierDismissible: false, builder: (_) => _CropDialog(bytes: bytes));

/// Runs in a background isolate (compute): PNG -> JPG so the file stays small (well under 2MB).
Uint8List _pngToJpg(Uint8List png) {
  final im = img.decodePng(png)!;
  return Uint8List.fromList(img.encodeJpg(im, quality: 88));
}

class _CropDialog extends StatefulWidget {
  final Uint8List bytes;
  const _CropDialog({required this.bytes});
  @override
  State<_CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<_CropDialog> {
  static const double _ratio = 7 / 9; // passport photo 35mm x 45mm
  static const double _minScale = 1, _maxScale = 5, _minFrame = 60;

  final _tc = TransformationController();
  final _boundaryKey = GlobalKey();
  Size _vp = Size.zero; // viewport (crop area) size
  Rect _frame = Rect.zero; // crop frame inside the viewport
  Size? _imgSize;
  bool _free = false, _busy = false;
  int _rot = 0; // quarter turns

  @override
  void initState() {
    super.initState();
    _tc.addListener(() {
      if (mounted) setState(() {}); // keeps the zoom slider in sync with pinch zoom
    });
    decodeImageFromList(widget.bytes).then((im) {
      final s = Size(im.width.toDouble(), im.height.toDouble());
      im.dispose();
      if (!mounted) return;
      setState(() => _imgSize = s);
      _fit();
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  // ---------- geometry ----------
  void _resetFrame() {
    const m = 16.0;
    var w = _vp.width - 2 * m;
    var h = w / _ratio;
    if (h > _vp.height - 2 * m) {
      h = _vp.height - 2 * m;
      w = h * _ratio;
    }
    _frame = Rect.fromCenter(center: _vp.center(Offset.zero), width: w, height: h);
  }

  Matrix4 _scaleAbout(Matrix4 m, double f) {
    final c = _vp.center(Offset.zero);
    return Matrix4.translationValues(c.dx, c.dy, 0) *
        Matrix4.diagonal3Values(f, f, 1) *
        Matrix4.translationValues(-c.dx, -c.dy, 0) *
        m;
  }

  /// Starting position: photo zoomed just enough to cover the crop frame.
  void _fit() {
    final s = _imgSize;
    if (s == null || _vp.isEmpty) return;
    final odd = _rot.isOdd;
    final ew = odd ? s.height : s.width, eh = odd ? s.width : s.height;
    final d = math.min(_vp.width / ew, _vp.height / eh);
    final cover = math.max(_frame.width / (ew * d), _frame.height / (eh * d)).clamp(_minScale, _maxScale).toDouble();
    _tc.value = _scaleAbout(Matrix4.identity(), cover);
  }

  void _rotate(int d) {
    setState(() => _rot = (_rot + d + 4) % 4);
    _fit();
  }

  double _c(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  /// Free crop: drag a corner (0 = top-left, 1 = top-right, 2 = bottom-left, 3 = bottom-right).
  void _resize(int corner, Offset d) {
    var l = _frame.left, t = _frame.top, r = _frame.right, b = _frame.bottom;
    if (corner == 0 || corner == 2) {
      l = _c(l + d.dx, 0, r - _minFrame);
    } else {
      r = _c(r + d.dx, l + _minFrame, _vp.width);
    }
    if (corner < 2) {
      t = _c(t + d.dy, 0, b - _minFrame);
    } else {
      b = _c(b + d.dy, t + _minFrame, _vp.height);
    }
    setState(() => _frame = Rect.fromLTRB(l, t, r, b));
  }

  // ---------- apply ----------
  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ratio = (900 / _frame.width).clamp(1.0, 4.0).toDouble(); // output ~900px wide
      final full = await boundary.toImage(pixelRatio: ratio);
      final src = Rect.fromLTWH(_frame.left * ratio, _frame.top * ratio, _frame.width * ratio, _frame.height * ratio);
      final dst = Rect.fromLTWH(0, 0, src.width.roundToDouble(), src.height.roundToDouble());
      final rec = ui.PictureRecorder();
      Canvas(rec).drawImageRect(full, src, dst, Paint()..filterQuality = FilterQuality.high);
      final out = await rec.endRecording().toImage(dst.width.toInt(), dst.height.toInt());
      final png = (await out.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      full.dispose();
      out.dispose();
      final jpg = await compute(_pngToJpg, png);
      if (mounted) Navigator.pop(context, jpg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not crop the image: $e')));
    }
  }

  // ---------- UI ----------
  Widget _handle(int corner, Offset p) => Positioned(
        left: p.dx - 22,
        top: p.dy - 22,
        width: 44,
        height: 44,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (u) => _resize(corner, u.delta),
          child: Center(
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle, border: Border.all(color: kBlue, width: 2.5)),
            ),
          ),
        ),
      );

  Widget _viewport(double w, double h) {
    final size = Size(w, h);
    if (size != _vp) {
      _vp = size;
      _resetFrame();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fit();
      });
    }
    return SizedBox(
      width: w,
      height: h,
      child: Stack(children: [
        // everything inside this boundary is what gets cropped
        RepaintBoundary(
          key: _boundaryKey,
          child: Stack(children: [
            const Positioned.fill(child: ColoredBox(color: Colors.white)),
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _tc,
                minScale: _minScale,
                maxScale: _maxScale,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: SizedBox(
                  width: w,
                  height: h,
                  child: RotatedBox(
                    quarterTurns: _rot,
                    child: Image.memory(widget.bytes, fit: BoxFit.contain, gaplessPlayback: true),
                  ),
                ),
              ),
            ),
          ]),
        ),
        // dark overlay + frame (not part of the saved photo)
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _FramePainter(_frame)))),
        if (_free) ...[
          _handle(0, _frame.topLeft),
          _handle(1, _frame.topRight),
          _handle(2, _frame.bottomLeft),
          _handle(3, _frame.bottomRight),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = _tc.value.getMaxScaleOnAxis().clamp(_minScale, _maxScale).toDouble();
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                  child: Text('Crop & Adjust Image', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
              IconButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  visualDensity: VisualDensity.compact),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LayoutBuilder(builder: (context, c) {
                final w = c.maxWidth;
                final h = math.min(w * 1.15, MediaQuery.sizeOf(context).height * 0.42);
                return _viewport(w, h);
              }),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() {
                _free = !_free;
                if (!_free) _resetFrame();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Checkbox(
                      value: _free,
                      onChanged: (v) => setState(() {
                            _free = v ?? false;
                            if (!_free) _resetFrame();
                          })),
                  const Icon(Icons.open_in_full, size: 16),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('Free Crop (manually resize crop area)', style: TextStyle(fontSize: 14))),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.zoom_out, size: 20, color: Colors.black54),
              Expanded(
                child: Slider(
                  min: _minScale,
                  max: _maxScale,
                  value: scale,
                  onChanged: (v) => _tc.value = _scaleAbout(_tc.value, v / _tc.value.getMaxScaleOnAxis()),
                ),
              ),
              const Icon(Icons.zoom_in, size: 20, color: Colors.black54),
            ]),
            Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, children: [
              OutlinedButton.icon(
                  onPressed: _busy ? null : () => _rotate(-1),
                  icon: const Icon(Icons.rotate_left, size: 18),
                  label: const Text('Rotate Left')),
              Text('${_rot * 90}°', style: const TextStyle(color: Colors.black54)),
              OutlinedButton.icon(
                  onPressed: _busy ? null : () => _rotate(1),
                  icon: const Icon(Icons.rotate_right, size: 18),
                  label: const Text('Rotate Right')),
            ]),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton.icon(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancel')),
              const SizedBox(width: 10),
              FilledButton.icon(
                // app theme gives FilledButton an infinite min width; override it inside a Row
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _busy || _imgSize == null ? null : _apply,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check, size: 18),
                label: const Text('Apply Crop'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Darkens everything outside the crop frame and draws the frame with a rule-of-thirds grid.
class _FramePainter extends CustomPainter {
  final Rect frame;
  _FramePainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRect(frame)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black54);

    final grid = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = frame.left + frame.width * i / 3, y = frame.top + frame.height * i / 3;
      canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), grid);
      canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), grid);
    }
    canvas.drawRect(
        frame,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.frame != frame;
}