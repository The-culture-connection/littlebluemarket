import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/market_taxonomy.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/screens/market/collection_screen.dart';
import 'package:little_blue_market/widgets/floating_cart_button.dart';
import 'package:little_blue_market/widgets/post_card.dart';
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

/// Scrolls the feed until a post card is reachable and opens it. The feed
/// leads with rails, banners and tip cards, so the first card starts below
/// the fold.
Future<void> _openFirstPost(WidgetTester tester) async {
  await tester.dragFrom(const Offset(195, 400), const Offset(0, -420));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(PostCard).first);
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
      await _pumpFeed(tester);
      expect(find.text('Browse the Market'), findsOneWidget);
      expect(find.text('Browse the shop'), findsNothing);
    });

    testWidgets('only headings are on it, not every collection', (
      tester,
    ) async {
      await _pumpFeed(tester);
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
      await _pumpFeed(tester);
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

      final card = tester.widget<LbmCard>(
        find
            .descendant(
              of: find.byType(PostCard).first,
              matching: find.byType(LbmCard),
            )
            .first,
      );
      // It had no tap at all: the only way to a post was the speech bubble.
      expect(card.onTap, isNotNull);

      card.onTap!();
      await tester.pumpAndSettle();
      // The post screen, which is where the comments are.
      expect(find.text('Post'), findsOneWidget);
    });

    testWidgets('the floating cart never lands on a Send button', (
      tester,
    ) async {
      // Reported twice against the bug button, "fixed" once against a route
      // that does not exist, and still wrong on the post screen, where the
      // cart sat squarely on Send (Grace, 2026-09-23, with a photograph).
      // The old test asserted a list of route prefixes, which is precisely
      // the thing that was wrong; this one asserts the pixels.
      await _pumpFeed(tester, guest: false);
      await _openFirstPost(tester);

      final composer = find.byType(Composer);
      expect(composer, findsOneWidget, reason: 'the post screen has one');
      final cart = find.byIcon(Icons.shopping_bag_rounded);
      expect(cart, findsOneWidget);

      final send = tester.getRect(
        find.descendant(of: composer, matching: find.byType(CircleIconButton)),
      );
      final button = tester.getRect(cart);
      expect(
        button.overlaps(send),
        isFalse,
        reason: 'the cart is on the Send button: $button over $send',
      );
      expect(
        button.bottom,
        lessThanOrEqualTo(tester.getRect(composer).top),
        reason: 'the cart should sit above the composer, not beside it',
      );
    });

    testWidgets('and sits low again on a screen with no composer', (
      tester,
    ) async {
      await _pumpFeed(tester, guest: false);
      final low = tester.getRect(find.byIcon(Icons.shopping_bag_rounded));
      await _openFirstPost(tester);
      final high = tester.getRect(find.byIcon(Icons.shopping_bag_rounded));
      expect(high.top, lessThan(low.top), reason: 'lifted for the composer');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byIcon(Icons.shopping_bag_rounded)).top,
        low.top,
        reason: 'and back down once the composer has gone',
      );
    });

    test('the offset leaves room only when a composer asks for it', () {
      expect(
        CartLayer.bottomOffset(viewPaddingBottom: 0, composerInset: 0),
        96,
      );
      expect(
        CartLayer.bottomOffset(viewPaddingBottom: 24, composerInset: 66),
        24 + 96 + 66 + 8,
      );
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


    testWidgets('a hashtag tapped on the search screen replaces it', (
      tester,
    ) async {
      await _pumpFeed(tester);
      await tester.tap(find.text('Search goods, services, #tags'));
      await tester.pumpAndSettle();
      // The popular-tag tiles: tapping one used to push results on top of
      // the search field, so Back went to the field and not to the Market.
      await tester.tap(find.byType(LbmCard).first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Browse the Market'), findsOneWidget);
    });
  });
}
