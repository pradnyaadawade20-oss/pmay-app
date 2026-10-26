import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../api.dart';
import '../common.dart';

/// Role keys as defined by the backend. Change them here if they differ.
const roleOptions = <(String, String)>[
  ('super_admin', 'Super Admin'),
  ('admin', 'Admin'),
  ('finance', 'Finance'),
  ('allotment_manager', 'Allotment Manager'),
  ('auditor', 'Auditor'),
];

String roleLabel(Object? k) => roleOptions.firstWhere((e) => e.$1 == '$k', orElse: () => ('$k', '$k')).$2;

Color roleColor(Object? k) => switch ('$k') {
      'super_admin' => kRed,
      'admin' => kBlue,
      'finance' => kGreen,
      'allotment_manager' => kOrange,
      _ => const Color(0xFFD98B00), // auditor
    };

String _date(Object? v) {
  final d = v == null ? null : DateTime.tryParse('$v')?.toLocal();
  if (d == null) return '-';
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.month)}/${p(d.day)}/${d.year}';
}

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});
  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final r = await Api.i.get(Ep.users);
      _users = List<Map<String, dynamic>>.from(r['users'] ?? []);
    } catch (e) {
      _err = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  String _id(Map u) => '${u['user_id'] ?? u['id']}';

  Future<void> _add() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const _AddUserDialog());
    if (ok == true) _load();
  }

  Future<void> _edit(Map u) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _EditNameDialog(id: _id(u), name: '${u['display_name'] ?? ''}'));
    if (ok == true) _load();
  }

  Future<void> _delete(Map u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove role?'),
        content: Text('${u['display_name'] ?? u['email'] ?? _id(u)} will lose their admin access.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: kRed), onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.i.post(Ep.userDelete(_id(u)));
      if (mounted) toast(context, 'User role removed');
      _load();
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Widget _stat(String label, int v, double w) => SizedBox(
        width: w,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kLine), boxShadow: kShadow),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 15)),
                const SizedBox(height: 6),
                Text('$v', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: kInk, height: 1.1)),
              ]),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.shield_outlined, color: kMuted, size: 38),
          ]),
        ),
      );

  Widget _stats() => LayoutBuilder(builder: (context, c) {
        final cols = ((c.maxWidth + 16) / (190 + 16)).floor().clamp(1, 5);
        final w = (c.maxWidth - 16 * (cols - 1)) / cols;
        return Wrap(spacing: 16, runSpacing: 16, children: [
          for (final r in roleOptions)
            _stat(r.$2, _users.where((u) => u['role'] == r.$1).length, w),
        ]);
      });

  Widget _table() => Panel(
        padding: const EdgeInsets.all(0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 22, 24, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('User Roles', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
              SizedBox(height: 4),
              Text('All users with administrative access to the system.', style: TextStyle(color: kMuted, fontSize: 13)),
            ]),
          ),
          LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: math.max(c.maxWidth, 820)),
                child: DataTable(
                  dataRowMinHeight: 82,
                  dataRowMaxHeight: 82,
                  horizontalMargin: 24,
                  columnSpacing: 28,
                  headingRowHeight: 60,
                  headingTextStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: kMuted),
                  headingRowColor: const WidgetStatePropertyAll(Colors.white),
                  columns: const [
                    DataColumn(label: Text('Display Name')),
                    DataColumn(label: Text('Email')),
                    DataColumn(label: Text('User ID')),
                    DataColumn(label: Text('Role')),
                    DataColumn(label: Text('Assigned On')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (final u in _users)
                      DataRow(cells: [
                        DataCell(Text('${u['display_name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w700, color: kInk, fontSize: 15))),
                        DataCell(Text('${u['email'] ?? '-'}', style: const TextStyle(color: kMuted))),
                        DataCell(Text(_id(u).length > 8 ? '${_id(u).substring(0, 8)}...' : _id(u),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 15, color: kMuted))),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(color: roleColor(u['role']), borderRadius: BorderRadius.circular(20)),
                          child: Text(roleLabel(u['role']), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                        )),
                        DataCell(Text(_date(u['assigned_at'] ?? u['created_at']), style: const TextStyle(color: kInk, fontSize: 15))),
                        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: 'Edit name', onPressed: () => _edit(u), icon: const Icon(Icons.edit_outlined, size: 20, color: kInk)),
                          IconButton(tooltip: 'Delete', onPressed: () => _delete(u), icon: const Icon(Icons.delete_outline_rounded, size: 20, color: kRed)),
                        ])),
                      ]),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) return Center(child: EmptyState(icon: Icons.cloud_off_rounded, title: 'Failed to load data', sub: _err!));
    return ListView(children: [
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add User Role')),
      ),
      const SizedBox(height: 16),
      _stats(),
      const SizedBox(height: 16),
      if (_users.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: EmptyState(icon: Icons.manage_accounts_outlined, title: 'No users found', sub: 'Use Add User Role to add the first user'))
      else
        _table(),
      const SizedBox(height: 8),
    ]);
  }
}

// ---------------------------------------------------------------- shared dialog bits
Widget _dlgHead(BuildContext c, String title, String sub) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(color: kMuted, fontSize: 13, height: 1.35)),
        ]),
      ),
      IconButton(onPressed: () => Navigator.pop(c, false), icon: const Icon(Icons.close_rounded, size: 20)),
    ]);

Widget _lbl(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(t, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kInk)),
    );

Widget _hint(String t) => Padding(padding: const EdgeInsets.only(top: 6), child: Text(t, style: const TextStyle(fontSize: 12, color: kMuted)));

Dialog _dlg(double w, Widget child) => Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w),
        child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: child),
      ),
    );

// ---------------------------------------------------------------- edit display name
class _EditNameDialog extends StatefulWidget {
  final String id, name;
  const _EditNameDialog({required this.id, required this.name});
  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final _c = TextEditingController(text: widget.name);
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = _c.text.trim();
    if (n.isEmpty) {
      toast(context, 'Display name cannot be empty', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.i.post(Ep.userName(widget.id), {'display_name': n});
      if (!mounted) return;
      toast(context, 'Display name updated');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, e.toString(), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => _dlg(
        440,
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _dlgHead(context, 'Edit Display Name', 'Update the display name for this user. This name will appear in dropdowns and lists.'),
          _lbl('Display Name'),
          TextField(controller: _c, autofocus: true, onSubmitted: (_) => _save()),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(spacing: 10, children: [
              OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
            ]),
          ),
        ]),
      );
}

// ---------------------------------------------------------------- add user role (Assign / Invite / Create)
class _AddUserDialog extends StatefulWidget {
  const _AddUserDialog();
  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  int _tab = 0;
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _conf = TextEditingController();
  final _name = TextEditingController();
  String _role = 'admin';
  bool _searchAll = false;
  bool _autoConfirm = true;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_email, _pass, _conf, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  void _err(String m) => toast(context, m, error: true);

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) return _err('Enter a valid email address');
    if (_tab == 2) {
      if (_pass.text.length < 8) return _err('Password must be at least 8 characters');
      if (_pass.text != _conf.text) return _err('Passwords do not match');
    }
    final body = <String, dynamic>{'email': email, 'role': _role, 'display_name': _name.text.trim()};
    final path = switch (_tab) {
      0 => () {
          body['search_all'] = _searchAll;
          return Ep.userAssign;
        }(),
      1 => Ep.userInvite,
      _ => () {
          body['password'] = _pass.text;
          body['auto_confirm'] = _autoConfirm;
          return Ep.userCreate;
        }(),
    };
    setState(() => _busy = true);
    try {
      await Api.i.post(path, body);
      if (!mounted) return;
      toast(context, switch (_tab) { 0 => 'Role assigned', 1 => 'Invitation sent', _ => 'User created' });
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _err(e.toString());
      }
    }
  }

  Widget _tabs() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFFEEF1F6), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _tab == i ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: _tab == i ? const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))] : null,
                  ),
                  child: Text(['Assign', 'Invite', 'Create'][i],
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: _tab == i ? kInk : kMuted)),
                ),
              ),
            ),
        ]),
      );

  Widget _roleDrop() => DropdownButtonFormField<String>(
        initialValue: _role,
        isExpanded: true,
        items: [for (final r in roleOptions) DropdownMenuItem(value: r.$1, child: Text(r.$2))],
        onChanged: (v) => setState(() => _role = v ?? _role),
      );

  Widget _check(String t, bool v, ValueChanged<bool> f) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: InkWell(
          onTap: () => f(!v),
          child: Row(children: [
            Checkbox(value: v, onChanged: (x) => f(x ?? false), visualDensity: VisualDensity.compact),
            Expanded(child: Text(t, style: const TextStyle(fontSize: 13, color: kInk))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      _lbl(_tab == 0 ? 'User Email' : 'Email Address'),
      TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(hintText: _tab == 0 ? 'user@example.com' : 'newuser@example.com')),
      if (_tab == 0) _hint('The user must be registered in the system first.'),
      if (_tab == 1) _hint('An invitation email with a magic link will be sent.'),
      if (_tab == 2) ...[
        _lbl('Password'),
        TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(hintText: 'Min. 8 characters')),
        _lbl('Confirm Password'),
        TextField(controller: _conf, obscureText: true, decoration: const InputDecoration(hintText: 'Confirm password')),
      ],
      _lbl('Role'),
      _roleDrop(),
      if (_tab == 0) _check('Search all auth users (not just registered applicants)', _searchAll, (v) => setState(() => _searchAll = v)),
      _lbl('Display Name (Optional)'),
      TextField(controller: _name, decoration: InputDecoration(hintText: ['e.g., Priya Sharma', 'e.g., Rajesh Kumar', 'e.g., Amit Patel'][_tab])),
      if (_tab == 2) _check('Auto-confirm email (user can login immediately)', _autoConfirm, (v) => setState(() => _autoConfirm = v)),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon([Icons.check_rounded, Icons.mail_outline_rounded, Icons.person_add_alt_1_rounded][_tab], size: 18),
          label: Text(['Assign Role', 'Send Invitation', 'Create User'][_tab]),
        ),
      ),
    ];
    return _dlg(
      440,
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _dlgHead(context, 'Add User Role', 'Assign a role to an existing user, invite a new user, or create one directly.'),
        const SizedBox(height: 16),
        _tabs(),
        ...fields,
      ]),
    );
  }
}