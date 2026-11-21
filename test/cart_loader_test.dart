import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/async.dart';
import 'package:little_blue_market/widgets/cart_loader.dart';

Widget _host(
  Widget child, {
  bool still = false,
  Brightness b = Brightness.light,
}) => MaterialApp(
  theme: buildLbmTheme(b),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Scaffold(body: Center(child: child)),
  ),
);

double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.descendant(
        of: find.byType(CartLoader),
        matching: find.byType(FadeTransition),
      ),
    )
    .opacity
    .value;

/// Grace, 2026-11-21: "provide a loading icon that is the cart pulsing."
void main() {
  testWidgets('a first load with no skeleton shows the pulsing cart', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(LbmAsync<String>(const AsyncValue.loading(), data: Text.new)),
    );
    expect(find.byType(CartLoader), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });

  testWidgets('the cart pulses', (tester) async {
    await tester.pumpWidget(_host(const CartLoader()));
    final first = _opacity(tester);
    await tester.pump(const Duration(milliseconds: 550));
    expect(_opacity(tester), isNot(closeTo(first, 0.01)));
  });

  testWidgets('reduced motion holds the cart still at full strength', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const CartLoader(), still: true));
    expect(_opacity(tester), 1.0);
    await tester.pump(const Duration(milliseconds: 550));
    expect(_opacity(tester), 1.0);
  });

  testWidgets('it draws in dark mode too', (tester) async {
    await tester.pumpWidget(
      _host(const CartLoader(size: 64), b: Brightness.dark),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
