import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/widgets/masonry_run.dart';

/// The two-column layout, now that we do it ourselves.
///
/// `SliverMasonryGrid` was retired because it corrupts its own leading-edge
/// cache during ordinary scrolling and reconciles it by correcting the scroll
/// offset, which on the live feed meant the page refusing to scroll down at
/// all (Grace, 2026-09-29, round 3, reproduced on the production web build as
/// a guest with synthetic wheel events).
///
/// So the rule it used has to be written down somewhere, and this is it: each
/// pin goes into the column that is currently shorter, ties to the left. The
/// numbers below are worked by hand in the bug note, not read off the
/// implementation, which is the only way this test is worth anything.

const _gutter = 10.0;
const _rowGap = 12.0;
const _width = 400.0;
const _columnWidth = (_width - _gutter) / 2;

Future<List<Offset>> _layout(WidgetTester tester, List<double> heights) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: _width,
          child: MasonryRun(
            gutter: _gutter,
            rowGap: _rowGap,
            children: [
              for (final (i, h) in heights.indexed)
                SizedBox(key: ValueKey('pin$i'), height: h),
            ],
          ),
        ),
      ),
    ),
  );

  return [
    for (var i = 0; i < heights.length; i++)
      (tester.renderObject<RenderBox>(find.byKey(ValueKey('pin$i'))).parentData!
              as BoxParentData)
          .offset,
  ];
}

double _runHeight(WidgetTester tester) =>
    tester.renderObject<RenderBox>(find.byType(MasonryRun)).size.height;

void main() {
  testWidgets('each pin goes into the shorter column, ties to the left', (
    tester,
  ) async {
    // Worked by hand: after 300 and 80 the columns stand at 312 and 92, so
    // the 200 goes right and leaves it at 304; the 120 goes right again
    // because 304 is still under 312; then the 90 goes left.
    final offsets = await _layout(tester, [300, 80, 200, 120, 90]);

    const right = _columnWidth + _gutter;
    expect(offsets, const [
      Offset(0, 0),
      Offset(right, 0),
      Offset(right, 92),
      Offset(right, 304),
      Offset(0, 312),
    ]);

    // The tallest column is 436 with its trailing gap; the run is that gap
    // shorter, because the gap after the last pin is not part of the run.
    expect(_runHeight(tester), 424);
  });

  testWidgets('a single pin sits in the left column and sets the height', (
    tester,
  ) async {
    final offsets = await _layout(tester, [180]);

    expect(offsets, const [Offset(0, 0)]);
    expect(_runHeight(tester), 180);
  });

  testWidgets('an empty run takes no room at all', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: _width,
            child: MasonryRun(gutter: _gutter, rowGap: _rowGap, children: []),
          ),
        ),
      ),
    );

    expect(_runHeight(tester), 0);
  });

  testWidgets('every pin is a column wide, whatever it asked for', (
    tester,
  ) async {
    await _layout(tester, [300, 80]);

    for (final key in ['pin0', 'pin1']) {
      expect(
        tester.getSize(find.byKey(ValueKey(key))).width,
        _columnWidth,
        reason: 'a pin that sized itself would break the columns',
      );
    }
  });

  testWidgets('measuring dry agrees with laying out', (tester) async {
    // Two ways to work out a height is two chances to draw the grid one way
    // and measure it another, so they share the arithmetic. This proves it.
    await _layout(tester, [300, 80, 200, 120, 90]);
    final run = tester.renderObject<RenderMasonryRun>(find.byType(MasonryRun));

    expect(
      run.computeDryLayout(const BoxConstraints(maxWidth: _width)).height,
      run.size.height,
    );
  });
}
