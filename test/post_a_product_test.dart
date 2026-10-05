import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/screens/market/results_screen.dart';
import 'package:little_blue_market/theme/app_theme.dart';

/// Posting a product is now something a seller does, not something a
/// product does to itself.
///
/// Grace, 2026-09-24: "the app is showing products of sellers that are not
/// on the app as posted... allow sellers to post their own products from
/// there." Mirroring stopped writing a post (see `catalog.ts`), so the only
/// way a product reaches the feed is this button, on the seller's own
/// Products tab.
///
/// The tile has two jobs now and they must not be confused: the tap opens
/// the product, exactly as before, and posting has a target of its own.
/// That is the whole reason this is a button rather than a long press.
void main() {
  final product = Fx.products.values.first;

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLbmTheme(Brightness.light),
          home: Scaffold(body: SizedBox(width: 120, height: 120, child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a visitor sees no way to post somebody else\'s product', (
    tester,
  ) async {
    var opened = 0;
    await pump(
      tester,
      GridCell(product: product, onTap: () => opened++),
    );
    expect(find.bySemanticsLabel('Post this to the feed'), findsNothing);

    await tester.tap(find.byType(GridCell));
    expect(opened, 1, reason: 'the tap still opens the product');
  });

  testWidgets('the seller gets a button of its own, named as an action', (
    tester,
  ) async {
    var opened = 0;
    var posted = 0;
    await pump(
      tester,
      GridCell(
        product: product,
        onTap: () => opened++,
        actionIcon: Icons.campaign_outlined,
        actionLabel: 'Post this to the feed',
        onAction: () => posted++,
      ),
    );

    // Named for a screen reader, not only shown as a tooltip: a Tooltip is
    // not a semantics label, which has caught us before.
    final button = find.bySemanticsLabel('Post this to the feed');
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(posted, 1);
    expect(opened, 0, reason: 'posting is not opening');
  });

  testWidgets('tapping the picture still opens the product, not the composer', (
    tester,
  ) async {
    var opened = 0;
    var posted = 0;
    await pump(
      tester,
      GridCell(
        product: product,
        onTap: () => opened++,
        actionIcon: Icons.campaign_outlined,
        actionLabel: 'Post this to the feed',
        onAction: () => posted++,
      ),
    );

    // The top-left corner is picture, as far from the button as the tile
    // allows. Grace was explicit that the tap must keep its old meaning:
    // "the products will open their product detail page as normal".
    await tester.tapAt(tester.getTopLeft(find.byType(GridCell)) + const Offset(8, 8));
    await tester.pump();
    expect(opened, 1);
    expect(posted, 0);
  });

  testWidgets('a price badge and the post button share the tile', (
    tester,
  ) async {
    // Both live in corners, and an earlier version put them in the same one.
    await pump(
      tester,
      GridCell(
        product: product,
        badge: product.price,
        onTap: () {},
        actionIcon: Icons.campaign_outlined,
        actionLabel: 'Post this to the feed',
        onAction: () {},
      ),
    );
    expect(find.text(product.price), findsOneWidget);
    final badge = tester.getCenter(find.text(product.price));
    final button = tester.getCenter(
      find.bySemanticsLabel('Post this to the feed'),
    );
    expect(button.dy, greaterThan(badge.dy), reason: 'not on top of it');
  });
}
