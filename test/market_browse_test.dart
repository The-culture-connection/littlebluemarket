import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/market_taxonomy.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/screens/market/collection_screen.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/widgets/pins/review_pin.dart';
import 'package:little_blue_market/widgets/primitives.dart';
import 'package:little_blue_market/widgets/screen.dart';

/// Grace's list of 2026-09-14: the rail is the Market's seven headings, a
/// post opens when tapped, the bug button keeps off the Send button, and the
/// search pill is not decoration.
Future<ProviderContainer> _pumpFeed(
  WidgetTester tester, {
  bool guest = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(retry: lbmRetry);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const LittleBlueMarketApp(),
    ),
  );
  await tester.pump();
  await tester.tap(
    find.bySemanticsLabel('Continue as a guest'),
    warnIfMissed: false,
  );
  await tester.pumpAndSettle();
  if (!guest) {
    container.read(sessionProvider.notifier).signIn();
    await tester.pumpAndSettle();
  }
  return container;
}

/// The browse hub.
///
/// The shop rail and the directory rail moved here from the top of the feed
/// in the redesign (plan T2.2): browsing by category is something you go
/// looking for, and on the feed the rails pushed the first photograph below
/// the fold. Everything these tests assert about the rails is unchanged; only
/// the screen they are on is.
Future<ProviderContainer> _pumpSearch(WidgetTester tester) async {
  final container = await _pumpFeed(tester);
  container.read(routerProvider).go('/market/search');
  await tester.pumpAndSettle();
  return container;
}

/// Opens a post's own screen from the grid.
///
/// A review pin, deliberately: the whole pin is the tap target either way,
/// but a listing pin leads to the product, which is where a listing's detail
/// lives now. The post screen is the one with a composer on it.
Future<void> _openFirstPost(WidgetTester tester) async {
  final pin = find.byType(ReviewPin).first;
  await tester.ensureVisible(pin);
  await tester.pumpAndSettle();
  await tester.tap(pin);
  await tester.pumpAndSettle();
}

void main() {
  group('the rail is the seven headings', () {
    test('the taxonomy is internally consistent', () {
      expect(kMarketCategories.length, 7);
      expect(kMarketCategoryHandles.length, 7);
      // The two lists must not drift apart.
      expect(
        kMarketCategories.map((c) => c.handle).toList(),
        kMarketCategoryHandles,
      );
      // No heading is its own child, and no duplicates inside one heading.
      for (final category in kMarketCategories) {
        expect(category.children, isNot(contains(category.handle)));
        expect(category.children.toSet().length, category.children.length);
        expect(category.children, isNotEmpty);
      }
      // The Coffee handle really does carry a Cyrillic ie; if somebody
      // "tidies" it to ASCII the chip silently disappears from the store.
      expect(marketChildrenOf('food-drink'), contains('coffeе'));
    });

    test('children are looked up by heading, and nothing else has any', () {
      expect(marketChildrenOf('apparel-accessories'), contains('jewelry'));
      expect(marketChildrenOf('woman-owned'), isEmpty);
      expect(marketChildrenOf(''), isEmpty);
    });

    testWidgets('it says Browse the Market, not Browse the shop', (
      tester,
    ) async {
      await _pumpSearch(tester);
      expect(find.text('Browse the Market'), findsOneWidget);
      expect(find.text('Browse the shop'), findsNothing);
    });

    testWidgets('only headings are on it, not every collection', (
      tester,
    ) async {
      await _pumpSearch(tester);
      // The demo store carries three of the seven, plus initiatives and
      // subcategories that must not be on the rail. The rail is a lazy
      // horizontal list, so the third chip is only built once scrolled to.
      final railScroll = find.descendant(
        of: find.byType(CollectionRail),
        matching: find.byType(Scrollable),
      );
      expect(find.text('Apparel & Accessories'), findsOneWidget);
      expect(find.text('Art & Creative Goods'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Bath, Beauty & Wellness'),
        80,
        scrollable: railScroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('Bath, Beauty & Wellness'), findsOneWidget);
      // Initiatives are collections too, and used to fill the rail.
      expect(find.text('Woman Owned'), findsNothing);
      expect(find.text('BIPOC Owned'), findsNothing);
      // A subcategory belongs inside its heading, not on the rail.
      expect(find.text('Jewelry'), findsNothing);
    });

    testWidgets('a heading offers the narrower ones inside it', (tester) async {
      await _pumpSearch(tester);
      await tester.tap(find.text('Apparel & Accessories'));
      await tester.pumpAndSettle();

      // Its subcategories, as chips, and only the ones the store has.
      expect(find.text('Jewelry'), findsOneWidget);
      expect(find.text('Bags'), findsOneWidget);
      // Under Art & Creative Goods, so not here.
      expect(find.text('Stickers'), findsNothing);

      await tester.tap(find.text('Jewelry'));
      await tester.pumpAndSettle();
      expect(find.text('Jewelry'), findsWidgets);
    });
  });

  group('the other three', () {
    testWidgets('tapping a post opens it, where the comments are', (
      tester,
    ) async {
      await _pumpFeed(tester, guest: false);
      expect(find.text('Post'), findsNothing);

      // The whole pin is the tap target, as the whole card was: the original
      // bug here was a feed card with no tap at all, where the only way to a
      // post was the speech bubble. A review pin is the one that still leads
      // to the post screen; a listing pin leads to the product, which is
      // where a listing's own detail lives.
      final pin = find.byType(ReviewPin).first;
      await tester.ensureVisible(pin);
      await tester.pumpAndSettle();
      await tester.tap(pin);
      await tester.pumpAndSettle();

      // The post screen, which is where the comments are.
      expect(find.text('Post'), findsOneWidget);
    });

    testWidgets('the cart never lands on a Send button', (tester) async {
      // Reported twice against the bug button, "fixed" once against a route
      // that does not exist, and still wrong on the post screen, where the
      // cart sat squarely on Send (Grace, 2026-09-23, with a photograph).
      //
      // The cart floated over the bottom right of every screen then, and
      // keeping it clear of whatever was underneath was a running battle. It
      // is in the tab bar now, which is a row the layout makes room for
      // rather than a thing on top of the layout, so it cannot cover
      // anything. The test still asserts the pixels, because that is the part
      // that was wrong twice.
      await _pumpFeed(tester, guest: false);
      await _openFirstPost(tester);

      final composer = find.byType(Composer);
      expect(composer, findsOneWidget, reason: 'the post screen has one');
      final cart = find.byIcon(Icons.shopping_bag_outlined);
      expect(cart, findsOneWidget, reason: 'the cart is still reachable');

      final send = tester.getRect(
        find.descendant(of: composer, matching: find.byType(CircleIconButton)),
      );
      final button = tester.getRect(cart);
      expect(
        button.overlaps(send),
        isFalse,
        reason: 'the cart is on the Send button: $button over $send',
      );
    });

    testWidgets('and gets out of the way of the keyboard', (tester) async {
      await _pumpFeed(tester, guest: false);
      await _openFirstPost(tester);
      expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);

      // The whole bar goes when the keyboard is up, so a composer sits
      // directly above the keys with nothing over it.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.shopping_bag_outlined), findsNothing);
      expect(find.byType(Composer), findsOneWidget);
    });

    testWidgets('the search pill on the results screen reopens search', (
      tester,
    ) async {
      await _pumpFeed(tester);
      await tester.tap(find.text('Search goods, services, #tags'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'candle');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      // On the results screen the query is the pill.
      expect(find.text('candle'), findsWidgets);

      // Tapping it used to do nothing at all: a second search meant going
      // back first.
      await tester.tap(find.text('candle').first);
      await tester.pumpAndSettle();

      // The field is open again, carrying what was searched for.
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, 'candle');
    });


    testWidgets('a hashtag tapped on the search screen opens its page', (
      tester,
    ) async {
      final container = await _pumpFeed(tester);
      await tester.tap(find.text('Search goods, services, #tags'));
      await tester.pumpAndSettle();

      // A hashtag is a place now rather than a search: it has its own page,
      // which you can follow and come back from. Keyword searches still
      // replace each other; that is the next test.
      final tags = await container.read(popularTagsProvider.future);
      final tile = find.text(tags.first.tag).first;
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(find.text('COLLECTION'), findsOneWidget);
      expect(find.text(tagLabel(tags.first.tag)), findsWidgets);
      expect(find.text('Follow'), findsOneWidget);
    });
  });
}
