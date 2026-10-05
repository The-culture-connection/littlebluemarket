import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/seller_sync.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/round_up.dart';
import 'package:little_blue_market/state/session.dart';

/// Rounding up at checkout.
///
/// The two claims worth holding: it is off until somebody turns it on, and
/// the amount the totals show is the amount the checkout is asked for.
/// Change taken quietly is the thing people are right to resent about this
/// pattern, so both are asserted rather than described.
void main() {
  group('the arithmetic the buyer sees', () {
    test('rounds to the next whole dollar, and never to nothing', () {
      expect(roundUpCentsFor(6340), 60);
      expect(roundUpCentsFor(6300), 100);
      expect(roundUpCentsFor(1), 99);
      expect(roundUpCentsFor(0), 0);
      expect(roundUpCentsFor(-100), 0);
    });

    test('agrees with the server for every subtotal it could send', () {
      // `functions/src/donations.ts` carries the same rule and refuses
      // anything outside 1..100. Neither side trusts the other, so the two
      // have to land on the same number for every input.
      for (var subtotal = 1; subtotal <= 3000; subtotal++) {
        final cents = roundUpCentsFor(subtotal);
        expect((subtotal + cents) % 100, 0, reason: 'subtotal $subtotal');
        expect(cents, inInclusiveRange(1, 100), reason: 'subtotal $subtotal');
      }
    });
  });

  group('in the cart', () {
    Future<ProviderContainer> pumpCart(
      WidgetTester tester, {
      bool configured = true,
    }) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        retry: lbmRetry,
        overrides: [
          if (!configured)
            appConfigProvider.overrideWith(
              (ref) async => const AppConfig(
                registrationUrl: '',
                shipturtleUrl: '',
              ),
            ),
        ],
      );
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
      container.read(sessionProvider.notifier).signIn();
      await tester.pumpAndSettle();

      // Something in the cart, so there is a subtotal to round.
      await container
          .read(commerceRepositoryProvider)
          .addLine(productId: 'p1');
      container.read(routerProvider).go('/market/cart');
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('off until it is turned on', (tester) async {
      final container = await pumpCart(tester);

      expect(find.text('Round up for Little Blue Market'), findsOneWidget);
      expect(container.read(roundUpProvider), isFalse);
      // No line in the totals while it is off.
      expect(find.text('Round-up'), findsNothing);
    });

    testWidgets('turning it on shows its own line', (tester) async {
      final container = await pumpCart(tester);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(container.read(roundUpProvider), isTrue);
      expect(find.text('Round-up'), findsOneWidget);
      expect(find.textContaining('keeps the app member-run'), findsOneWidget);
    });

    testWidgets('the checkout is asked for the amount that was shown', (
      tester,
    ) async {
      final container = await pumpCart(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      final cart = container.read(cartProvider).value!;
      final expected = roundUpCentsFor(cart.subtotalCents);

      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();

      expect(container.read(fixtureStoreProvider).lastRoundUpCents, expected);
    });

    testWidgets('nothing is asked for when it was left alone', (tester) async {
      final container = await pumpCart(tester);
      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();

      expect(container.read(fixtureStoreProvider).lastRoundUpCents, isNull);
    });

    testWidgets('the whole card is gone when it is not configured', (
      tester,
    ) async {
      // How the feature ships dark: with no round-up handle in this
      // environment there is nothing to explain and nothing to switch.
      await pumpCart(tester, configured: false);

      expect(find.text('Round up for Little Blue Market'), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });
  });
}
