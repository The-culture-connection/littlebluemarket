import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

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
/// its own masonry sliver with the wide item laid between them. Both columns
/// therefore start level again after every wide item.
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
    final slivers = <Widget>[];
    final run = <Widget>[];
    final pad = EdgeInsets.symmetric(horizontal: horizontal);

    void flushRun() {
      if (run.isEmpty) return;
      final items = List<Widget>.of(run);
      run.clear();
      if (slivers.isNotEmpty) slivers.add(_gap);
      slivers.add(
        SliverPadding(
          padding: pad,
          sliver: SliverMasonryGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: rowGap,
            crossAxisSpacing: gutter,
            childCount: items.length,
            itemBuilder: (context, i) => items[i],
          ),
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
      if (slivers.isNotEmpty) slivers.add(_gap);
      slivers.add(
        SliverPadding(
          padding: pad,
          sliver: SliverToBoxAdapter(child: children[i]),
        ),
      );
    }
    flushRun();

    if (bottom > 0) {
      slivers.add(SliverToBoxAdapter(child: SizedBox(height: bottom)));
    }
    return slivers;
  }

  static const _gap = SliverToBoxAdapter(child: SizedBox(height: rowGap));

  /// The same two columns, not scrolling, for a capped run of pins inside a
  /// page that already scrolls.
  ///
  /// "Also sold by this maker" and "More reviews" are six pins at most, so
  /// they can be laid out at once. A sliver grid cannot go inside another
  /// scroll view, and nesting one costs either a fight over the drag or a
  /// shrink-wrap that builds everything anyway.
  ///
  /// Children alternate between the columns rather than filling the shorter
  /// one, because which is shorter is not known until after layout. With a
  /// handful of pins the difference is not visible.
  static Widget fixed({
    required List<Widget> children,
    double horizontal = gutter,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();

    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      (i.isEven ? left : right).add(children[i]);
    }

    Widget column(List<Widget> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: rowGap),
          items[i],
        ],
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontal),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: column(left)),
          const SizedBox(width: gutter),
          Expanded(child: right.isEmpty ? const SizedBox() : column(right)),
        ],
      ),
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
