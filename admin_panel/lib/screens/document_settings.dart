import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';

class DocumentSettingsPage extends StatefulWidget {
  const DocumentSettingsPage({super.key});
  @override
  State<DocumentSettingsPage> createState() => _DocumentSettingsPageState();
}

class _DocumentSettingsPageState extends State<DocumentSettingsPage> {
  List<Map<String, dynamic>> _rows = [];
  final _ctl = <String, TextEditingController>{};
  final _ai = <String, bool>{};
  final _orig = <String, ({double size, bool ai})>{};
  final _saving = <String>{};
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _k(Map r) => '${r['kind'] ?? r['document_type']}';
  String _label(Map r) => '${r['label'] ?? docKinds[_k(r)] ?? _k(r)}';
  double _num(Object? v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
  String _fmt(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final r = await Api.i.get(Ep.docSettings);
      _rows = List<Map<String, dynamic>>.from(r['settings'] ?? []);
      for (final c in _ctl.values) {
        c.dispose();
      }
      _ctl.clear();
      for (final x in _rows) {
        final k = _k(x);
        final size = _num(x['max_size_mb']);
        final ai = x['ai_validation'] == true;
        _ctl[k] = TextEditingController(text: _fmt(size));
        _ai[k] = ai;
        _orig[k] = (size: size, ai: ai);
      }
    } catch (e) {
      _err = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _dirty(String k) {
    final o = _orig[k]!;
    return _num(_ctl[k]!.text) != o.size || _ai[k] != o.ai;
  }

  Future<void> _save(String k) async {
    final size = double.tryParse(_ctl[k]!.text.trim());
    if (size == null || size <= 0) {
      toast(context, 'Enter a valid number for max size', error: true);
      return;
    }
    setState(() => _saving.add(k));
    try {
      await Api.i.post(Ep.docSettingSave(k), {'max_size_mb': size, 'ai_validation': _ai[k]});
      _orig[k] = (size: size, ai: _ai[k] == true);
      if (mounted) toast(context, 'Settings saved');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
    if (mounted) setState(() => _saving.remove(k));
  }

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine)),
        child: Text(t.startsWith('.') ? t : '.$t', style: const TextStyle(fontSize: 12, color: kInk)),
      );

  Widget _intro() => const Panel(
        padding: EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Document Upload Configuration', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk)),
          SizedBox(height: 6),
          Text('Configure maximum file sizes and validation settings for each document type. Changes take effect immediately for new uploads.',
              style: TextStyle(color: kMuted, fontSize: 13.5, height: 1.4)),
        ]),
      );

  Widget _table() => Panel(
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: math.max(c.maxWidth, 840)),
              child: DataTable(
                dataRowMinHeight: 68,
                dataRowMaxHeight: 68,
                horizontalMargin: 22,
                columnSpacing: 32,
                columns: const [
                  DataColumn(label: Text('DOCUMENT TYPE')),
                  DataColumn(label: Text('MAX SIZE (MB)')),
                  DataColumn(label: Text('ALLOWED EXTENSIONS')),
                  DataColumn(label: Text('AI VALIDATION')),
                  DataColumn(label: Text('ACTIONS')),
                ],
                rows: [
                  for (final r in _rows)
                    DataRow(cells: [
                      DataCell(Text(_label(r), style: const TextStyle(fontWeight: FontWeight.w700, color: kInk))),
                      DataCell(SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _ctl[_k(r)],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(isDense: true),
                        ),
                      )),
                      DataCell(Wrap(spacing: 6, children: [
                        for (final e in (r['allowed_extensions'] is List ? r['allowed_extensions'] as List : ['jpg', 'jpeg', 'png', 'pdf'])) _chip('$e'),
                      ])),
                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                        Switch(value: _ai[_k(r)] == true, onChanged: (v) => setState(() => _ai[_k(r)] = v)),
                        const SizedBox(width: 6),
                        Text(_ai[_k(r)] == true ? 'Enabled' : 'Disabled', style: const TextStyle(color: kMuted, fontSize: 13)),
                      ])),
                      DataCell(_dirty(_k(r))
                          ? FilledButton(
                              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                              onPressed: _saving.contains(_k(r)) ? null : () => _save(_k(r)),
                              child: _saving.contains(_k(r))
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('Save'))
                          : const SizedBox.shrink()),
                    ]),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) return Center(child: EmptyState(icon: Icons.cloud_off_rounded, title: 'Failed to load data', sub: _err!));
    return ListView(children: [
      _intro(),
      const SizedBox(height: 16),
      if (_rows.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: EmptyState(icon: Icons.settings_rounded, title: 'No settings found', sub: 'Document settings were not returned by the backend'))
      else
        _table(),
      const SizedBox(height: 8),
    ]);
  }
}