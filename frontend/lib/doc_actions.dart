import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

/// Android-native file actions (see MainActivity.kt):
///  * [download]  – saves the PDF into the phone's Downloads folder
///  * [open]      – opens a saved file in the PDF viewer
///  * [shareWhatsApp] – sends the PDF straight to WhatsApp (falls back to the share sheet)
class DocActions {
  static const _ch = MethodChannel('pmay/files');

  /// Returns the saved file's uri, or null when it fell back to the share sheet.
  static Future<String?> download(Uint8List bytes, String filename) async {
    if (Platform.isAndroid) {
      try {
        return await _ch.invokeMethod<String>('saveToDownloads', {'name': filename, 'bytes': bytes});
      } on PlatformException {
        // storage not writable on this device -> let the user save it from the share sheet
      }
    }
    await Printing.sharePdf(bytes: bytes, filename: filename);
    return null;
  }

  static Future<void> open(String uri) => _ch.invokeMethod('openFile', {'uri': uri});

  static Future<void> shareWhatsApp(Uint8List bytes, String filename, {String? text}) async {
    if (Platform.isAndroid) {
      try {
        await _ch.invokeMethod('shareWhatsApp', {'name': filename, 'bytes': bytes, 'text': text ?? ''});
        return;
      } on PlatformException {
        // fall through to the generic share sheet
      }
    }
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}