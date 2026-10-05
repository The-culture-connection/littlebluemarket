import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/widgets/masonry.dart';

/// The phone the design was drawn for. Everything has to work here.
const _phone = Size(390, 844);

/// The app clamps text scaling to 1.35; 2.0 leaves real headroom.
const _beyondClamp = 2.0;

/// Tiles of deliberately mismatched heights — a masonry grid is only doing its
/// job if the two columns end up uneven.
final _heights = <double>[120, 190, 90, 160, 140, 210, 110];

Widget _tile(int i) => Container(
  key: ValueKey('tile$i'),
  height: _heights[i],
  color: const Color(0xFF9CBFE3),
);

Widget _wide() => Container(
  key: const ValueKey('wide'),
  height: 160,
  color: const Color(0xFFD56ED1),
);

/// Seven tiles with a full-width item in the middle, which is the shape of a
/// real feed page: pins, then the hero or the makers rail, then more pins.
Widget _grid() {
  final children = <Widget>[
    _tile(0),
    _tile(1),
    _tile(2),
    _wide(),
    _tile(3),
    _tile(4),
    _tile(5),
    _tile(6),
  ];
  final wide = [false, false, false, true, false, false, false, false];
  return MaterialApp(
    home: Scaffold(body: LbmMasonry(wide: wide, children: children)),
  );
}

void main() {
  Future<void> pumpPhone(WidgetTester tester, Widget app) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets('lays the tiles out in exactly two columns', (tester) async {
    await pumpPhone(tester, _grid());

    final lefts = <double>{};
    for (var i = 0; i < _heights.length; i++) {
      final tile = find.byKey(ValueKey('tile$i'));
      expect(tile, findsOneWidget, reason: 'tile$i was not built');
      lefts.add(tester.getTopLeft(tile).dx);
    }

    // 390 wide, 10 of padding each side, 10 between the columns, so a column
    // is 180 wide and the two start at 10 and 200.
    expect(lefts, hasLength(2), reason: 'expected two columns, got $lefts');
    expect(lefts, {10.0, 200.0});
  });

  testWidgets('the columns fill independently, not in lockstep', (
    tester,
  ) async {
    await pumpPhone(tester, _grid());

    // Tiles 0 and 1 start level; tile 2 follows the shorter of the two, which
    // is what a masonry grid does and a GridView does not.
    final t0 = tester.getRect(find.byKey(const ValueKey('tile0')));
    final t1 = tester.getRect(find.byKey(const ValueKey('tile1')));
    final t2 = tester.getRect(find.byKey(const ValueKey('tile2')));

    expect(t0.top, t1.top);
    expect(t0.height, isNot(t1.height));
    expect(t2.top, t0.bottom + LbmMasonry.rowGap);
  });

  testWidgets('a wide child spans the full width between the runs', (
    tester,
  ) async {
    await pumpPhone(tester, _grid());

    final wide = tester.getRect(find.byKey(const ValueKey('wide')));
    expect(wide.width, _phone.width - LbmMasonry.gutter * 2);
    expect(wide.left, LbmMasonry.gutter);

    // Both columns start level again underneath it, which is the whole reason
    // a wide item breaks the grid rather than spanning inside it.
    final t3 = tester.getTopLeft(find.byKey(const ValueKey('tile3'))).dy;
    final t4 = tester.getTopLeft(find.byKey(const ValueKey('tile4'))).dy;
    expect(t3, t4);
    expect(t3, greaterThan(wide.bottom));
  });

  testWidgets('does not overflow at twice the clamped text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = _beyondClamp;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpPhone(
      tester,
      MaterialApp(
        home: Scaffold(
          body: LbmMasonry(
            wide: const [
              false,
              false,
              false,
              false,
              false,
              false,
              false,
              true,
            ],
            children: [
              for (var i = 0; i < 7; i++)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Pin number $i with a caption that runs on'),
                ),
              const Text('a wide one, also with words in it'),
            ],
          ),
        ),
      ),
    );

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing rather than throwing when empty', (
    tester,
  ) async {
    await pumpPhone(
      tester,
      const MaterialApp(
        home: Scaffold(body: LbmMasonry(children: <Widget>[])),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
