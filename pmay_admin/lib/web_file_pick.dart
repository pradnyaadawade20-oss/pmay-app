import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Opens a browser file picker and returns the chosen file's name and bytes, or null if cancelled.
Future<({String name, Uint8List bytes})?> pickFile({String accept = '.jpg,.jpeg,.png,.pdf'}) async {
  final input = web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.accept = accept;
  final completer = Completer<({String name, Uint8List bytes})?>();

  input.addEventListener(
      'change',
      (web.Event e) {
        final files = input.files;
        if (files == null || files.length == 0) {
          completer.complete(null);
          return;
        }
        final file = files.item(0)!;
        final reader = web.FileReader();
        reader.addEventListener(
            'load',
            (web.Event ev) {
              final buf = (reader.result as JSArrayBuffer).toDart;
              completer.complete((name: file.name, bytes: buf.asUint8List()));
            }.toJS);
        reader.addEventListener(
            'error',
            (web.Event ev) {
              completer.complete(null);
            }.toJS);
        reader.readAsArrayBuffer(file);
      }.toJS);

  input.click();
  return completer.future;
}