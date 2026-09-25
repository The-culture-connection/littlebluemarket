import 'package:flutter/material.dart';

import 'primitives.dart';

/// The row of chips that narrows a grid by kind: All · Products · Reviews ·
/// Forums · Chat.
///
/// It scrolls sideways rather than wrapping. A wrapping row changes height
/// when the labels change, which moves the grid underneath it, and the grid
/// is the thing the person is reading.
class FilterChips extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
  });

  /// The chips, as `(key, label)`. The key is what [onSelect] hands back and
  /// what [selected] is compared against; the label is what is drawn.
  final List<(String key, String label)> items;

  final String selected;
  final ValueChanged<String> onSelect;
  final EdgeInsetsGeometry padding;

  /// Tall enough for a chip at the clamped text scale without clipping it.
  static const height = 38.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final (key, label) = items[i];
          final on = key == selected;
          return Center(
            child: LbmChip(
              label,
              style: on ? ChipStyle.on : ChipStyle.quiet,
              fontSize: 12.5,
              onTap: on ? null : () => onSelect(key),
            ),
          );
        },
      ),
    );
  }
}
