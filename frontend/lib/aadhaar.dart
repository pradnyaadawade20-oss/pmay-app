import 'package:flutter/services.dart';

/// "234567890124" -> "2345 6789 0124" (standard Aadhaar format). Anything that is not 12 digits is returned unchanged.
String formatAadhaar(Object? v) {
  final raw = (v ?? '').toString().trim();
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length != 12) return raw;
  return '${d.substring(0, 4)} ${d.substring(4, 8)} ${d.substring(8)}';
}

/// Digits only, at most 12, shown in groups of 4 while typing ("2345 6789 0124").
class AadhaarInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (d.length > 12) d = d.substring(0, 12);
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i > 0 && i % 4 == 0) b.write(' ');
      b.write(d[i]);
    }
    final t = b.toString();
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}
