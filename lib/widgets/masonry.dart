import 'package:flutter/material.dart';

import 'masonry_run.dart';

/// The two-column grid the app is laid out on.
///
/// The photo is the card, so every pin is a different height. That rules out
/// `GridView`, which gives every cell the same aspect ratio and would crop or
/// letterbox the photographs back into uniformity — the flatness the redesign
/// exists to undo. A masonry grid lets the two columns fill independently.
///
/// Some items are not pins at all: the hero announcement and the makers rail
/// are full-width. Rather than stretch them across both columns inside the
/// grid (which strands whichever column is shorter), a wide item **breaks the
/// grid**: the children are cut into runs at each wide item, and each run is
/// laid out on its own with the wide item between them. Both columns
/// therefore start level again after every wide item.
///
/// A run is one box ([MasonryRun]), not a masonry sliver. See the note
/// there: the package's sliver corrupts its own leading-edge cache during
/// ordinary scrolling and reconciles it by correcting the scroll offset,
/// which on the live feed meant the page refusing to scroll down at all.
/// Laziness stays, one level up: the runs are built on demand by a
/// `SliverList`, and a run is only ever a handful of pins.
class LbmMasonry extends StatelessWidget {
  const LbmMasonry({
    super.key,
    required this.children,
    this.wide,
    this.header = const <Widget>[],
    this.footer = const <Widget>[],
    this.controller,
    this.bottom = tabBarClearance,
  });

  /// The pins, in order.
  final List<Widget> children;

  /// Parallel to [children]: `true` where that child spans the full width.
  ///
  /// May be shorter than [children]; a missing entry means not wide.
  final List<bool>? wide;

  /// Slivers above the grid — the search pill, the tabs, the filter row.
  final List<Widget> header;

  /// Slivers below the grid, above [bottom].
  final List<Widget> footer;

  final ScrollController? controller;

  /// Empty space under everything, so the floating tab bar never covers the
  /// last pin.
  final double bottom;

  /// Between a column and the screen edge, and between the two columns.
  static const gutter = 10.0;

  /// Between pins down a column, and between runs.
  static const rowGap = 12.0;

  /// The floating tab bar sits over the bottom of the scroll view.
  static const tabBarClearance = 110.0;

  /// The grid as slivers, for a screen that builds its own [CustomScrollView].
  ///
  /// Prefer this over nesting an [LbmMasonry] inside another scroll view: a
  /// nested scrollable either fights the outer one for the drag or has to be
  /// shrink-wrapped, which builds every child at once.
  static List<Widget> slivers({
    required List<Widget> children,
    List<bool>? wide,
    double horizontal = gutter,
    double bottom = 0,
  }) {
    final run = <Widget>[];
    final pad = EdgeInsets.symmetric(horizontal: horizontal);
    // One entry per run and per wide item, in order, each with a stable
    // key so a re-cut run keeps the element it already had.
    final rows = <Widget>[];

    void flushRun() {
      if (run.isEmpty) return;
      final items = List<Widget>.of(run);
      run.clear();
      final key = items.first.key;
      rows.add(
        Padding(
          key: key == null ? null : ValueKey('run:$key'),
          padding: pad,
          child: MasonryRun(gutter: gutter, rowGap: rowGap, children: items),
        ),
      );
    }

    for (var i = 0; i < children.length; i++) {
      final isWide = wide != null && i < wide.length && wide[i];
      if (!isWide) {
        run.add(children[i]);
        continue;
      }
      flushRun();
      final wideKey = children[i].key;
      rows.add(
        Padding(
          // Derived, never the child's own: a wrapper wearing its child's key
          // makes `find.byKey` ambiguous, and makes the two of them look like
          // one widget to anything that matches by key.
          key: wideKey == null ? null : ValueKey('wide:$wideKey'),
          padding: pad,
          child: children[i],
        ),
      );
    }
    flushRun();

    if (rows.isEmpty) return const <Widget>[];

    return [
      SliverList.separated(
        itemCount: rows.length,
        itemBuilder: (context, i) => rows[i],
        separatorBuilder: (context, i) => const SizedBox(height: rowGap),
      ),
      if (bottom > 0) SliverToBoxAdapter(child: SizedBox(height: bottom)),
    ];
  }

  /// The same two columns, not scrolling, for a capped run of pins inside a
  /// page that already scrolls.
  ///
  /// "Also sold by this maker" and "More reviews" are six pins at most, so
  /// they can be laid out at once. A sliver grid cannot go inside another
  /// scroll view, and nesting one costs either a fight over the drag or a
  /// shrink-wrap that builds everything anyway.
  ///
  /// Each pin goes into the shorter column, the same rule the scrolling
  /// grid uses, so a capped run and a feed run look alike. They used to
  /// alternate left and right, because which column was shorter was not
  /// known until after layout; [MasonryRun] knows, because it lays them
  /// out itself.
  static Widget fixed({
    required List<Widget> children,
    double horizontal = gutter,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontal),
      child: MasonryRun(gutter: gutter, rowGap: rowGap, children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      slivers: [
        ...header,
        ...slivers(children: children, wide: wide),
        ...footer,
        if (bottom > 0) SliverToBoxAdapter(child: SizedBox(height: bottom)),
      ],
    );
  }
}
