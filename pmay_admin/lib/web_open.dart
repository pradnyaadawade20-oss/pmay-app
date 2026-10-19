import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Opens bytes in a new browser tab (image / PDF).
void openBytes(Uint8List b) {
  var mime = 'application/octet-stream';
  if (b.length > 3 && b[0] == 0x25 && b[1] == 0x50) {
    mime = 'application/pdf';
  } else if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) {
    mime = 'image/jpeg';
  } else if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) {
    mime = 'image/png';
  }
  if (b.length > 4 && b[0] == 0x3C && b[1] == 0x73 && b[2] == 0x76 && b[3] == 0x67) {
    mime = 'image/svg+xml'; // "<svg"
  }
  final blob = web.Blob([b.toJS].toJS, web.BlobPropertyBag(type: mime));
  web.window.open(web.URL.createObjectURL(blob), '_blank');
}

/// Opens HTML in a new tab (the print dialog opens automatically if the HTML contains a script).
void openHtml(String html) {
  final blob = web.Blob([html.toJS].toJS, web.BlobPropertyBag(type: 'text/html;charset=utf-8'));
  web.window.open(web.URL.createObjectURL(blob), '_blank');
}

/// Downloads a text file (CSV export).
void downloadText(String name, String text, {String mime = 'text/csv;charset=utf-8'}) {
  final blob = web.Blob(['\uFEFF$text'.toJS].toJS, web.BlobPropertyBag(type: mime));
  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = web.URL.createObjectURL(blob);
  a.download = name;
  a.click();
}
/// Saves bytes as a file download (used for CSV export).
void downloadBytes(String name, Uint8List b, String mime) {
  final blob = web.Blob([b.toJS].toJS, web.BlobPropertyBag(type: mime));
  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = web.URL.createObjectURL(blob);
  a.download = name;
  a.click();
}