import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/widgets/masonry.dart';

/// The For you feed jumping backwards mid-drag (Grace, 2026-09-29, two screen
/// recordings; `Planning/bug-feed-scroll-snapback.md` round 2).
///
/// The drag survives the jump, so nothing is being remounted: this is a
/// `scrollOffsetCorrection` applied by `RenderSliverMasonryGrid` during
/// layout. When the leading laid-out child of a masonry run loses its
/// `layoutOffset` — which happens when the children above the viewport are
/// reindexed — the sliver restarts from index 0, cannot climb back to where
/// the viewport is, and corrects the offset to the start of that run.
///
/// That was measured here, at 430 px, while `SliverMasonryGrid` still laid
/// the runs out. It is now 0: a run is one box ([MasonryRun]) inside a
/// `SliverList`, and a box takes no part in scroll geometry, so it has no
/// leading-edge cache to corrupt and no way to emit a correction.
///
/// The tests stayed, with their expectations turned round. They are the
/// regression on the whole class of bug: if anything ever puts a lazy grid
/// back under the feed, the first one goes red.

Widget _tile(String key, {double height = 160}) =>
    SizedBox(key: ValueKey(key), height: height);

Widget _grid(List<Widget> children, {List<bool>? wide, ScrollController? c}) =>
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          controller: c,
          slivers: LbmMasonry.slivers(children: children, wide: wide),
        ),
      ),
    );

/// Twenty pins with a full-width one part way down, which is what cuts the
/// grid into separate masonry runs. The recordings all snap to a run's start.
({List<Widget> children, List<bool> wide}) _page({String? without}) {
  final children = <Widget>[];
  final wide = <bool>[];
  for (var i = 0; i < 20; i++) {
    final key = 'pin$i';
    if (key == without) continue;
    final isWide = i == 6;
    children.add(_tile(key, height: isWide ? 120 : 160));
    wide.add(isWide);
  }
  return (children: children, wide: wide);
}

Future<double> _dropOneMidDrag(
  WidgetTester tester, {
  required bool reindex,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final controller = ScrollController();
  addTearDown(controller.dispose);

  final first = _page();
  await tester.pumpWidget(
    _grid(first.children, wide: first.wide, c: controller),
  );
  await tester.pumpAndSettle();

  // Sit well past the wide item, inside the second run, and put a finger
  // down: the recordings are of a drag in progress, not of a fling.
  controller.jumpTo(600);
  await tester.pumpAndSettle();

  final gesture = await tester.startGesture(const Offset(195, 700));
  for (var i = 0; i < 4; i++) {
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
  }
  final before = controller.offset;

  // One pin above the viewport goes away, as an item does when assembly
  // re-runs and no longer includes it. The keys are unchanged; the indexes
  // after it all shift by one.
  final second = reindex ? _page(without: 'pin2') : _page();
  await tester.pumpWidget(
    _grid(second.children, wide: second.wide, c: controller),
  );
  await tester.pump();

  final after = controller.offset;
  await gesture.up();
  await tester.pumpAndSettle();
  return before - after;
}

void main() {
  testWidgets('reindexing a run under a finger does not move the scroll', (
    tester,
  ) async {
    // This asserted the opposite until the runs stopped being lazy slivers:
    // removing one pin from above the viewport threw the scroll back 430 px
    // in a single frame, which is the whole bug. A box cannot do that.
    final jump = await _dropOneMidDrag(tester, reindex: true);

    expect(
      jump.abs(),
      lessThan(1),
      reason:
          'the grid moved $jump px when one pin above the viewport was '
          'removed; something under the feed is correcting the scroll offset '
          'again, which means a lazy grid is back',
    );
  });

  testWidgets('leaving the children alone leaves the scroll alone', (
    tester,
  ) async {
    // The control. Same drag, same rebuild, nothing reindexed: no jump. That
    // is what says the rebuild is innocent and the reindexing is the cause.
    final jump = await _dropOneMidDrag(tester, reindex: false);

    expect(jump.abs(), lessThan(1));
  });
}
