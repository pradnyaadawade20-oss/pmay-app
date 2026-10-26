import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';
import '../secugen.dart';

/// Office flow: staff scans the applicant's thumb on the SecuGen scanner and saves it.
/// Returns true if a thumb impression was saved.
Future<bool?> showThumbCaptureDialog(BuildContext context, String applicantId) =>
    showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _ThumbDialog(applicantId));

class _ThumbDialog extends StatefulWidget {
  final String applicantId;
  const _ThumbDialog(this.applicantId);
  @override
  State<_ThumbDialog> createState() => _ThumbDialogState();
}

class _ThumbDialogState extends State<_ThumbDialog> {
  Uint8List? _png;
  bool _scanning = false, _saving = false, _consent = false;
  String _hand = 'right';
  String? _err;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _err = null;
    });
    try {
      final b = await captureThumbPng();
      if (mounted) setState(() => _png = b);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.i.post('/admin/applicants/${widget.applicantId}/thumb', {'image': base64Encode(_png!), 'hand': _hand});
      if (!mounted) return;
      toast(context, 'Thumb impression saved');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        toast(context, '$e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Capture thumb impression'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Thumb: '),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _hand,
                items: const [
                  DropdownMenuItem(value: 'right', child: Text('Right thumb')),
                  DropdownMenuItem(value: 'left', child: Text('Left thumb')),
                ],
                onChanged: (_scanning || _saving) ? null : (v) => setState(() => _hand = v ?? 'right'),
              ),
            ]),
            const SizedBox(height: 12),
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: kLine), borderRadius: BorderRadius.circular(8)),
              child: _scanning
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 10), Text('Thumb scanner par rakhein...')]))
                  : _png == null
                      ? const Center(child: Text('Abhi scan nahi hua', style: TextStyle(color: kMuted)))
                      : Padding(padding: const EdgeInsets.all(6), child: Image.memory(_png!, fit: BoxFit.contain)),
            ),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: kRed, fontSize: 13))),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _consent,
              onChanged: (_scanning || _saving) ? null : (v) => setState(() => _consent = v ?? false),
              title: const Text('Applicant ne is thumb impression ko agreement par lagane ki sahmati di hai.', style: TextStyle(fontSize: 13)),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: (_scanning || _saving) ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          OutlinedButton.icon(onPressed: (_scanning || _saving) ? null : _scan, icon: const Icon(Icons.fingerprint), label: Text(_png == null ? 'Scan' : 'Rescan')),
          FilledButton(onPressed: (_png != null && _consent && !_scanning && !_saving) ? _save : null, child: Text(_saving ? 'Saving...' : 'Save')),
        ],
      );
}