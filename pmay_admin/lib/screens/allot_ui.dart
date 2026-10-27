import 'package:flutter/material.dart';
import '../common.dart';

/// Dropdown styled like the allotment-manager screenshots: the selected row is
/// highlighted in orange with a check mark. Used ONLY for the Allotment Manager role.
class AllotSelect extends StatelessWidget {
  final String value;
  final Map<String, String> items; // value -> label (insertion order is kept)
  final ValueChanged<String> onChanged;
  final double width;
  const AllotSelect({super.key, required this.value, required this.items, required this.onChanged, this.width = 170});

  @override
  Widget build(BuildContext context) {
    final label = items[value] ?? items.values.first;
    return SizedBox(
      width: width,
      child: PopupMenuButton<String>(
        tooltip: '',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 4),
        padding: EdgeInsets.zero,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 6,
        constraints: BoxConstraints(minWidth: width),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: kLine)),
        onSelected: onChanged,
        itemBuilder: (_) => [
          for (final e in items.entries)
            PopupMenuItem<String>(
              value: e.key,
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                    color: e.key == value ? kOrange : Colors.transparent, borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  SizedBox(
                      width: 24,
                      child: e.key == value ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null),
                  Expanded(
                    child: Text(e.value,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: e.key == value ? Colors.white : kInk)),
                  ),
                ]),
              ),
            ),
        ],
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kLine)),
          child: Row(children: [
            Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: kInk))),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: kMuted),
          ]),
        ),
      ),
    );
  }
}