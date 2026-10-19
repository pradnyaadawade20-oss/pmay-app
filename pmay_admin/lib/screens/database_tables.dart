import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';

String _title(String k) => k.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

String _cell(Object? v) {
  if (v == null) return '-';
  if (v is Map || v is List) return jsonEncode(v);
  final s = '$v';
  if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s)) {
    final d = DateTime.tryParse(s)?.toLocal();
    if (d != null) {
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      String p(int n) => n.toString().padLeft(2, '0');
      return '${d.month}/${d.day}/${d.year}, $h:${p(d.minute)}:${p(d.second)} ${d.hour >= 12 ? 'PM' : 'AM'}';
    }
  }
  return s.isEmpty ? '-' : s;
}

class DatabaseTablesPage extends StatefulWidget {
  const DatabaseTablesPage({super.key});
  @override
  State<DatabaseTablesPage> createState() => _DatabaseTablesPageState();
}

class _DatabaseTablesPageState extends State<DatabaseTablesPage> {
  List<Map<String, dynamic>> _tables = [];
  String _cur = '';
  List<String> _cols = [];
  List<Map<String, dynamic>> _rows = [];
  final _sel = <String>{};
  final _q = TextEditingController();
  bool _loadingTables = true;
  bool _loadingRows = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  String _tName(Map t) => '${t['name']}';
  String _tLabel(Map t) => '${t['label'] ?? _title(_tName(t))}';
  String _id(Map r) => '${r['id'] ?? r['user_id'] ?? r['unique_id'] ?? r.values.first}';
  String get _curLabel {
    final t = _tables.where((t) => _tName(t) == _cur);
    return t.isEmpty ? _title(_cur) : _tLabel(t.first);
  }

  Future<void> _loadTables({bool keepRows = false}) async {
    if (!keepRows) setState(() => _loadingTables = true);
    try {
      final r = await Api.i.get(Ep.dbTables);
      _tables = List<Map<String, dynamic>>.from(r['tables'] ?? []);
      if (_cur.isEmpty && _tables.isNotEmpty) {
        _cur = _tables.any((t) => _tName(t) == 'applicants') ? 'applicants' : _tName(_tables.first);
      }
      _err = null;
    } catch (e) {
      _err = e.toString();
    }
    if (mounted) setState(() => _loadingTables = false);
    if (_err == null && !keepRows) _loadRows();
  }

  Future<void> _loadRows() async {
    if (_cur.isEmpty) return;
    setState(() {
      _loadingRows = true;
      _sel.clear();
    });
    try {
      final r = await Api.i.get(Ep.dbRows(_cur, _q.text.trim()));
      _rows = List<Map<String, dynamic>>.from(r['rows'] ?? []);
      _cols = r['columns'] is List
          ? List<String>.from((r['columns'] as List).map((e) => '$e'))
          : (_rows.isEmpty ? <String>[] : _rows.first.keys.toList());
      _err = null;
    } catch (e) {
      _err = e.toString();
    }
    if (mounted) setState(() => _loadingRows = false);
  }

  void _pick(String name) {
    if (name == _cur) return;
    setState(() {
      _cur = name;
      _q.clear();
      _rows = [];
      _cols = [];
    });
    _loadRows();
  }

  Future<void> _refresh() async {
    await _loadTables(keepRows: true);
    await _loadRows();
  }

  Future<void> _view(Map<String, dynamic> r) => showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('$_curLabel record'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final e in r.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: SelectableText.rich(TextSpan(children: [
                      TextSpan(text: '${_title(e.key)}: ', style: const TextStyle(color: kMuted, fontSize: 13)),
                      TextSpan(text: _cell(e.value), style: const TextStyle(color: kInk, fontWeight: FontWeight.w600, fontSize: 13.5)),
                    ])),
                  ),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
        ),
      );

  Future<void> _edit(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _EditRowDialog(table: _cur, id: _id(r), row: r));
    if (ok == true) _refresh();
  }

  Future<void> _delete(List<String> ids) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(ids.length == 1 ? 'Delete record?' : 'Delete ${ids.length} records?'),
        content: Text('This will permanently remove the selected record(s) from the "$_curLabel" table. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: kRed), onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      for (final id in ids) {
        await Api.i.post(Ep.dbDelete(_cur, id));
      }
      if (mounted) toast(context, '${ids.length} record(s) deleted');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
    _refresh();
  }

  // ---------- left list ----------
  Widget _badge(String t, bool on) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        decoration: BoxDecoration(
          color: on ? Colors.white.withValues(alpha: 0.2) : kBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? Colors.white54 : kLine),
        ),
        child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Colors.white : kInk)),
      );

  Widget _item(Map t, {bool auth = false}) {
    final on = _tName(t) == _cur;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: on ? kBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _pick(_tName(t)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(children: [
              Icon(auth ? Icons.people_alt_outlined : Icons.grid_on_rounded, size: 17, color: on ? Colors.white : kInk),
              const SizedBox(width: 10),
              Expanded(child: Text(_tLabel(t), style: TextStyle(fontSize: 15, color: on ? Colors.white : kInk, fontWeight: on ? FontWeight.w600 : FontWeight.w400))),
              _badge(auth ? 'Auth' : '${t['count'] ?? 0}', on),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sidebar() {
    final auth = _tables.where((t) => _tName(t) == 'auth_users').toList();
    final rest = _tables.where((t) => _tName(t) != 'auth_users').toList();
    return Panel(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text('TABLES', style: TextStyle(fontSize: 14, color: kMuted, fontWeight: FontWeight.w500, letterSpacing: 0.4)),
        ),
        for (final t in auth) ...[_item(t, auth: true), const Divider(height: 18, color: kLine)],
        for (final t in rest) _item(t),
      ]),
    );
  }

  Widget _picker() => Panel(
        padding: const EdgeInsets.all(12),
        child: DropdownButtonFormField<String>(
          initialValue: _tables.any((t) => _tName(t) == _cur) ? _cur : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Table', isDense: true),
          items: [
            for (final t in _tables)
              DropdownMenuItem(value: _tName(t), child: Text('${_tLabel(t)}  (${_tName(t) == 'auth_users' ? 'Auth' : t['count'] ?? 0})', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => _pick(v ?? _cur),
        ),
      );

  // ---------- content ----------
  Widget _dataTable() {
    final ids = [for (final r in _rows) _id(r)];
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: math.max(c.maxWidth, 700)),
          child: DataTable(
            showCheckboxColumn: true,
            onSelectAll: (v) => setState(() {
              _sel.clear();
              if (v == true) _sel.addAll(ids);
            }),
            dataRowMinHeight: 72,
            dataRowMaxHeight: 72,
            horizontalMargin: 12,
            columnSpacing: 26,
            headingRowHeight: 64,
            headingTextStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: kMuted),
            headingRowColor: const WidgetStatePropertyAll(Colors.white),
            columns: [
              for (final c in _cols) DataColumn(label: Text(_title(c))),
              const DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (var i = 0; i < _rows.length; i++)
                DataRow(
                  selected: _sel.contains(ids[i]),
                  onSelectChanged: (v) => setState(() => v == true ? _sel.add(ids[i]) : _sel.remove(ids[i])),
                  cells: [
                    for (final c in _cols)
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Text(_cell(_rows[i][c]), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kInk, fontSize: 14.5)),
                      )),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(tooltip: 'View', onPressed: () => _view(_rows[i]), icon: const Icon(Icons.visibility_outlined, size: 18, color: kInk)),
                      IconButton(tooltip: 'Edit', onPressed: () => _edit(_rows[i]), icon: const Icon(Icons.edit_outlined, size: 18, color: kInk)),
                      IconButton(tooltip: 'Delete', onPressed: () => _delete([ids[i]]), icon: const Icon(Icons.delete_outline_rounded, size: 18, color: kRed)),
                    ])),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() => Panel(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.grid_on_rounded, size: 20, color: kInk),
            const SizedBox(width: 10),
            Expanded(
              child: Text('$_curLabel (${_rows.length} records)', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: kInk)),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
          ]),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth < 380 ? c.maxWidth : 380.0;
            return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: w,
                child: TextField(
                  controller: _q,
                  onSubmitted: (_) => _loadRows(),
                  decoration: InputDecoration(
                    hintText: 'Search by ${_cols.where((c) => c != 'id').take(2).join(', ')}...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
              ),
              FilledButton(onPressed: _loadRows, child: const Text('Search')),
              if (_sel.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: kRed),
                  onPressed: () => _delete(_sel.toList()),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text('Delete (${_sel.length})'),
                ),
            ]);
          }),
          const SizedBox(height: 14),
          if (_loadingRows)
            const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator()))
          else if (_rows.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: EmptyState(icon: Icons.table_rows_outlined, title: 'No records found', sub: 'This table has no data yet'))
          else
            _dataTable(),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (_loadingTables) return const Center(child: CircularProgressIndicator());
    if (_err != null && _tables.isEmpty) {
      return Center(child: EmptyState(icon: Icons.cloud_off_rounded, title: 'Failed to load data', sub: _err!));
    }
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 820;
      return ListView(children: [
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 250, child: _sidebar()),
            const SizedBox(width: 20),
            Expanded(child: _content()),
          ])
        else ...[
          _picker(),
          const SizedBox(height: 16),
          _content(),
        ],
        const SizedBox(height: 8),
      ]);
    });
  }
}

// ---------------------------------------------------------------- edit row
class _EditRowDialog extends StatefulWidget {
  final String table, id;
  final Map<String, dynamic> row;
  const _EditRowDialog({required this.table, required this.id, required this.row});
  @override
  State<_EditRowDialog> createState() => _EditRowDialogState();
}

class _EditRowDialogState extends State<_EditRowDialog> {
  static const _locked = {'id', 'user_id', 'created_at', 'updated_at'};
  final _c = <String, TextEditingController>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.row.forEach((k, v) {
      if (!_locked.contains(k) && v is! Map && v is! List) _c[k] = TextEditingController(text: v == null ? '' : '$v');
    });
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Object? _typed(Object? old, String s) {
    if (old is bool) return s.toLowerCase() == 'true';
    if (old is int) return int.tryParse(s) ?? s;
    if (old is double) return double.tryParse(s) ?? s;
    return s;
  }

  Future<void> _save() async {
    final data = <String, dynamic>{};
    _c.forEach((k, c) {
      final old = widget.row[k];
      if (c.text != (old == null ? '' : '$old')) data[k] = _typed(old, c.text);
    });
    if (data.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.i.post(Ep.dbUpdate(widget.table, widget.id), {'data': data});
      if (!mounted) return;
      toast(context, 'Record updated');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, e.toString(), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Edit Record', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk)),
              const SizedBox(height: 4),
              Text('ID: ${widget.id}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
              for (final e in _c.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                  child: Text(_title(e.key), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kInk)),
                ),
                TextField(controller: e.value, decoration: const InputDecoration(isDense: true)),
              ],
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 10, children: [
                  OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
                ]),
              ),
            ]),
          ),
        ),
      );
}