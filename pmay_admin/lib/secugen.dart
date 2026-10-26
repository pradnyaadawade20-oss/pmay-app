import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// Talks to the SecuGen WebAPI Client (SgiBioSrv) running on THIS Windows PC.
/// The client listens on https://localhost:<port>/SGIFPCapture (port depends on the client version).
const _ports = ['8000', '8443'];

class ThumbScanException implements Exception {
  final String message;
  ThumbScanException(this.message);
  @override
  String toString() => message;
}

/// Captures one fingerprint and returns it as PNG bytes.
Future<Uint8List> captureThumbPng({int quality = 60, int timeoutMs = 10000}) async {
  Object? lastErr;
  for (final port in _ports) {
    http.Response r;
    try {
      r = await http
          .post(Uri.parse('https://localhost:$port/SGIFPCapture'),
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: 'Timeout=$timeoutMs&Quality=$quality&licstr=&templateFormat=ISO&imageWSQRate=0.75')
          .timeout(Duration(milliseconds: timeoutMs + 8000));
    } catch (e) {
      lastErr = e; // service not on this port, try the next one
      continue;
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      throw ThumbScanException('Scanner ka jawab samajh nahi aaya (HTTP ${r.statusCode}).');
    }
    final code = j['ErrorCode'];
    if (code != 0) {
      throw ThumbScanException('Capture nahi hua (scanner error code $code). Thumb sahi se rakhke dobara try karein, aur scanner connected hai ya nahi dekhein.');
    }
    final b64 = '${j['BMPBase64'] ?? ''}';
    if (b64.isEmpty) throw ThumbScanException('Scanner ne image nahi di.');
    return _bmpToPng(b64);
  }
  throw ThumbScanException('SecuGen WebAPI Client nahi mila. Is PC par client install aur running hai? ($lastErr)');
}

/// The scanner returns a BMP; browsers can draw it, so convert to PNG through a canvas.
Future<Uint8List> _bmpToPng(String b64) {
  final done = Completer<Uint8List>();
  final img = web.HTMLImageElement();
  img.addEventListener(
      'load',
      ((web.Event _) {
        try {
          final canvas = web.HTMLCanvasElement()
            ..width = img.naturalWidth
            ..height = img.naturalHeight;
          final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
          ctx.drawImage(img, 0, 0);
          final url = canvas.toDataURL('image/png');
          done.complete(base64Decode(url.substring(url.indexOf(',') + 1)));
        } catch (e) {
          done.completeError(ThumbScanException('Image convert nahi hui: $e'));
        }
      }).toJS);
  img.addEventListener('error', ((web.Event _) => done.completeError(ThumbScanException('Scanner ki image padh nahi payi.'))).toJS);
  img.src = 'data:image/bmp;base64,$b64';
  return done.future;
}