import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';
import 'sheets.dart';

/// How many listings are on the screen, and the way to reorder them.
///
/// One row above every grid of listings. The count is a fact about the list
/// below it, never about the store: a category that had loaded its first
/// thirty read as the whole category, and a tester counted twenty-seven and
/// stopped looking (Grace, 2026-09-23).
///
/// The choices open in a sheet rather than sitting in a chip rail. There are
/// seven of them, they are words rather than one-word labels ("Price: high to
/// low"), and a rail of seven pills either scrolls sideways out of sight or
/// wraps into three lines above the thing people came to look at.
class SortBar extends StatelessWidget {
  const SortBar({
    super.key,
    required this.sort,
    required this.onChanged,
    this.count,
  });

  final SortOrder sort;
  final ValueChanged<SortOrder> onChanged;

  /// Null leaves the count off, for a list whose length says nothing useful.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        if (count != null)
          Expanded(
            child: Text(
              count == 1 ? '1 listing' : '${Fmt.count(count!)} listings',
              style: LbmText.tiny.copyWith(
                color: c.ink2,
                fontWeight: FontWeight.w700,
                fontFeatures: kTabularFigures,
              ),
            ),
          )
        else
          const Spacer(),
        LbmChip(
          sort == SortOrder.relevance ? 'Sort' : sort.label,
          style: sort == SortOrder.relevance ? ChipStyle.quiet : ChipStyle.on,
          fontSize: 11.5,
          trailingIcon: Icons.expand_more_rounded,
          onTap: () async {
            final picked = await showSortSheet(context, sort);
            if (picked != null) onChanged(picked);
          },
        ),
      ],
    );
  }
}

/// The sort choices, one per row, the current one ticked.
Future<SortOrder?> showSortSheet(BuildContext context, SortOrder current) {
  return showLbmSheet<SortOrder>(context, (sheetContext) {
    final c = sheetContext.c;
    return LbmSheet(
      children: [
        Text(
          'Sort by',
          style: LbmText.display.copyWith(fontSize: 20, color: c.ink),
        ),
        const SizedBox(height: 4),
        Text(
          'Best sellers counts what people have bought. Most popular counts '
          'what people have added to their cart.',
          style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
        ),
        const SizedBox(height: 10),
        LbmCard(
          padding: EdgeInsets.zero,
          child: RowStack(
            children: [
              for (final option in SortOrder.offered)
                ListRow(
                  title: Text(option.label),
                  trailing: option == current
                      ? Icon(Icons.check_rounded, size: 20, color: c.accentText)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(option),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  });
}
