import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../common.dart';

/// "Add Allotment": adds a new unit (house) to the inventory.
/// Shown on the dashboard of the Allotment Manager role.
class AddUnitPage extends StatefulWidget {
  const AddUnitPage({super.key});
  @override
  State<AddUnitPage> createState() => _AddUnitPageState();
}

class _AddUnitPageState extends State<AddUnitPage> {
  final _unit = TextEditingController();
  final _building = TextEditingController();
  final _tower = TextEditingController();
  final _wing = TextEditingController();
  final _floor = TextEditingController();
  final _area = TextEditingController();
  final _price = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    for (final c in [_unit, _building, _tower, _wing, _floor, _area, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  void _clear() {
    for (final c in [_unit, _building, _tower, _wing, _floor, _area, _price]) {
      c.clear();
    }
  }

  Future<void> _save() async {
    final unit = _unit.text.trim();
    final tower = _tower.text.trim();
    final wing = _wing.text.trim();
    final floor = int.tryParse(_floor.text.trim());
    final price = double.tryParse(_price.text.trim());
    final area = _area.text.trim().isEmpty ? 0.0 : double.tryParse(_area.text.trim());
    String? e;
    if (unit.isEmpty) {
      e = 'Unit number is required';
    } else if (tower.isEmpty) {
      e = 'Tower is required';
    } else if (wing.isEmpty) {
      e = 'Wing is required';
    } else if (floor == null || floor < 0) {
      e = 'Enter a valid floor number';
    } else if (area == null) {
      e = 'Enter a valid carpet area';
    } else if (price == null || price <= 0) {
      e = 'Enter a valid price';
    }
    if (e != null) {
      setState(() => _err = e);
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Api.i.post(Ep.units, {
        'unit_number': unit,
        'building_name': _building.text.trim(),
        'tower': tower,
        'wing': wing,
        'floor': floor,
        'carpet_area': area,
        'amount': price,
      });
      if (!mounted) return;
      toast(context, 'Unit $unit added');
      _clear();
      setState(() => _busy = false);
    } catch (ex) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = ex.toString();
        });
      }
    }
  }

  Widget _field(String label, TextEditingController c, double w,
      {String? hint, bool required = false, TextInputType? type, List<TextInputFormatter>? fmt}) {
    return SizedBox(
      width: w,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kInk)),
          if (required) const TextSpan(text: ' *', style: TextStyle(color: kRed)),
        ])),
        const SizedBox(height: 8),
        TextField(
          controller: c,
          keyboardType: type,
          inputFormatters: fmt,
          enabled: !_busy,
          decoration: InputDecoration(hintText: hint, isDense: true),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return SingleChildScrollView(
      child: Panel(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
          final w = (c.maxWidth - 20 * (cols - 1)) / cols;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Add Allotment', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
            const SizedBox(height: 2),
            const Text('Add a new unit to the inventory. It will show up as Available in Unit Allotment.',
                style: TextStyle(color: kMuted, fontSize: 13.5)),
            const SizedBox(height: 22),
            Wrap(spacing: 20, runSpacing: 18, children: [
              _field('Unit Number', _unit, w, hint: 'e.g. 1203', required: true),
              _field('Building Name', _building, w, hint: 'e.g. Krutarth Heights'),
              _field('Tower', _tower, w, hint: 'e.g. Tower A', required: true),
              _field('Wing', _wing, w, hint: 'e.g. A', required: true),
              _field('Floor', _floor, w, hint: 'e.g. 12', required: true, type: TextInputType.number, fmt: digits),
              _field('Carpet Area (Sq.m)', _area, w, hint: 'e.g. 26.94', type: const TextInputType.numberWithOptions(decimal: true), fmt: decimal),
              _field('Price (₹)', _price, w, hint: 'e.g. 2550000', required: true, type: const TextInputType.numberWithOptions(decimal: true), fmt: decimal),
            ]),
            if (_err != null) ...[
              const SizedBox(height: 16),
              Text(_err!, style: const TextStyle(color: kRed, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 24),
            Row(children: [
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_home_work_rounded, size: 18),
                label: const Text('Add Unit', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: _busy ? null : _clear, child: const Text('Clear')),
            ]),
          ]);
        }),
      ),
    );
  }
}