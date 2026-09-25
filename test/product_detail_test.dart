import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/widgets/cart_pill.dart';
import 'package:little_blue_market/widgets/detail_sheet.dart';
import 'package:little_blue_market/widgets/pins/product_pin.dart';
import 'package:little_blue_market/widgets/skeleton.dart';

/// The product page, which is where a listing's own detail lives now.
///
/// These could not be written until `fixture_store.dart` stopped handing
/// `Stream.first` a cancellation to await: `productDetailProvider` ends on
/// `watchRating(id).first`, so the page sat on [ProductDetailSkeleton] for
/// ever under a widget test's fake clock and nothing below could be asserted.
Future<ProviderContainer> _pumpProduct(
  WidgetTester tester,
  String id, {
  bool guest = false,
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
  container.read(routerProvider).go('/market/product/$id');
  await tester.pumpAndSettle();
  return container;
}

/// Scrolls the page until [finder] is on screen, then settles.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// The first cart tip explains what the cart means before it adds anything.
Future<void> _dismissCartTip(WidgetTester tester) async {
  if (find.text('Got it').evaluate().isNotEmpty) {
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('the product page contract', () {
    testWidgets('it leaves the skeleton and shows the listing', (tester) async {
      await _pumpProduct(tester, 'p1');

      expect(find.byType(ProductDetailSkeleton), findsNothing);
      expect(find.text('Cocoa Mint Lip Balm'), findsWidgets);
      // The variant's price, and there are four variants, three at $8.
      expect(find.text(r'$8'), findsWidgets);
    });

    testWidgets('the proof line counts carts rather than inventing faces', (
      tester,
    ) async {
      // p1 carries saveCount 214. The prototype drew a row of avatars here
      // that belonged to nobody; a count is the only thing on record.
      await _pumpProduct(tester, 'p1');

      expect(
        find.textContaining('214 people have this in their cart'),
        findsOneWidget,
      );
    });

    testWidgets('choosing a variant changes the price', (tester) async {
      // The bug this guards: the buy sheet charged the product's price while
      // the page showed the variant's. Plain (unflavoured) is $7, the other
      // three are $8.
      //
      // Scoped to the sheet on purpose: the Options section further down
      // prints every variant's own price, so an unscoped `$7` is there from
      // the start and would pass whatever the headline said.
      await _pumpProduct(tester, 'p1');
      Finder headline(String price) => find.descendant(
        of: find.byType(DetailSheet),
        matching: find.text(price),
      );
      expect(headline(r'$8'), findsOneWidget);
      expect(headline(r'$7'), findsNothing);

      await tester.tap(find.text('Plain (unflavoured)').first);
      await tester.pumpAndSettle();

      expect(headline(r'$7'), findsOneWidget);
      expect(headline(r'$8'), findsNothing);
    });

    testWidgets('the big button is Add to cart, and says so once added', (
      tester,
    ) async {
      final container = await _pumpProduct(tester, 'p1');

      final add = find.text('Add to cart');
      await _reveal(tester, add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await _dismissCartTip(tester);

      expect(container.read(cartProvider).value?.lines, hasLength(1));
      expect(find.text('In your cart'), findsOneWidget);
    });

    testWidgets('a guest is gated at the button, not after it', (tester) async {
      final container = await _pumpProduct(tester, 'p1', guest: true);

      final add = find.text('Add to cart');
      await _reveal(tester, add);
      await tester.tap(add);
      await tester.pumpAndSettle();

      expect(find.text('Make a profile to do that'), findsOneWidget);
      expect(container.read(cartProvider).value?.lines ?? const [], isEmpty);
    });
  });

  group('Also sold by this seller', () {
    testWidgets('it carries the seller\'s other products, never this one', (
      tester,
    ) async {
      await _pumpProduct(tester, 'p1');

      final section = find.textContaining('Also sold by');
      await _reveal(tester, section);

      expect(section, findsOneWidget);
      // At least one other product of Kali's, and not p1 itself: the pins
      // there are keyed `also_<id>`.
      final pins = find.byWidgetPredicate(
        (w) => w is ProductPin && (w.key as ValueKey<String>?)?.value != null,
      );
      final keys = <String>[
        for (final element in pins.evaluate())
          ((element.widget as ProductPin).key as ValueKey<String>).value,
      ].where((k) => k.startsWith('also_')).toList();

      expect(keys, isNotEmpty, reason: 'the cross-sell section is empty');
      expect(keys, isNot(contains('also_p1')));
    });

    testWidgets('"Their shop" lands on the seller, not back here', (
      tester,
    ) async {
      await _pumpProduct(tester, 'p1');

      final link = find.text('Their shop');
      await _reveal(tester, link);
      await tester.tap(link);
      await tester.pumpAndSettle();

      // Asserted on the screen rather than the address: the section link
      // pushes, and an imperative push does not move the router's reported
      // configuration off the page it was called from.
      expect(find.text('Listings'), findsOneWidget);
      expect(find.text('Total sales'), findsOneWidget);
    });

    testWidgets(
      'the pill in the cross-sell and the big button write one line each',
      (tester) async {
        // Plan §7, pair T1.3 × T3.1: two surfaces, one cart. The risk is a
        // second line for the same product rather than a quantity, which is
        // what a hand-rolled add on either side would have produced.
        final container = await _pumpProduct(tester, 'p1');

        final add = find.text('Add to cart');
        await _reveal(tester, add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        await _dismissCartTip(tester);
        expect(container.read(cartProvider).value?.lines, hasLength(1));

        final section = find.textContaining('Also sold by');
        await _reveal(tester, section);
        final pill = find
            .descendant(
              of: find.byWidgetPredicate(
                (w) =>
                    w is ProductPin &&
                    ((w.key as ValueKey<String>?)?.value ?? '').startsWith(
                      'also_',
                    ),
              ),
              matching: find.byType(CartPill),
            )
            .first;
        await tester.ensureVisible(pill);
        await tester.pumpAndSettle();
        await tester.tap(pill);
        await tester.pumpAndSettle();
        await _dismissCartTip(tester);

        final lines = container.read(cartProvider).value?.lines ?? const [];
        expect(lines, hasLength(2));
        expect(
          lines.map((l) => l.productId).toSet(),
          hasLength(2),
          reason: 'two products, not the same one twice',
        );
      },
    );
  });

  group('a post of a kind that is not a listing', () {
    testWidgets('a review post shows its words and a way to buy the thing', (
      tester,
    ) async {
      final container = await _pumpProduct(tester, 'p1');
      container.read(routerProvider).go('/market/post/post_review_1');
      await tester.pumpAndSettle();

      expect(find.textContaining('It survives a Michigan February'), findsOne);
      // The review sells the product; the row under it is how you act on it.
      expect(find.byType(CartPill), findsWidgets);
    });

    testWidgets('a cart post offers all of it at once, frozen as posted', (
      tester,
    ) async {
      // post_cart_1 holds p1, p2 and p5: $8 + $12 + $5.
      final container = await _pumpProduct(tester, 'p1');
      container.read(routerProvider).go('/market/post/post_cart_1');
      await tester.pumpAndSettle();

      expect(find.textContaining('Add all 3'), findsOneWidget);
      expect(find.byType(CartPill), findsNWidgets(3));
    });

    testWidgets('a listing post sends you to the product instead', (
      tester,
    ) async {
      // A listing's own detail is the product page, so the post route is a
      // redirect rather than a second, thinner copy of it.
      final container = await _pumpProduct(tester, 'p2');
      container.read(routerProvider).go('/market/post/post_p1');
      await tester.pumpAndSettle();

      // The product page, not the skeleton the redirect holds up while it
      // gets out of the way, and not a post screen with a composer on it.
      expect(find.byType(ProductDetailSkeleton), findsNothing);
      expect(find.text('Cocoa Mint Lip Balm'), findsWidgets);
      expect(find.text('Add to cart'), findsOneWidget);
    });
  });
}
