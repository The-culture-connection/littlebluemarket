import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/billing/billing_service.dart';
import 'package:little_blue_market/data/fixtures/fixture_billing_service.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/membership.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';

/// The monthly membership.
///
/// The property worth holding still: **the phone never decides whether
/// somebody is a member.** It buys, hands the receipt over, and reads back
/// what the server wrote. A test that let the card set its own state would
/// be testing the bug.

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  FixtureBillingService? billing,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    retry: lbmRetry,
    overrides: [
      if (billing != null) billingServiceProvider.overrideWithValue(billing),
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
  container.read(routerProvider).go('/you/chip-in');
  await tester.pumpAndSettle();
  return container;
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 140, maxScrolls: 20);
  }
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}

void main() {
  group('a person is a member because the server says so', () {
    test('a membership that has run out stops being one on its own', () {
      // No sweeper job, no flag to clear: the date is the answer, so a
      // lapsed member becomes a non-member the moment it passes.
      // A person is only ever a copy of a real one here: Person carries
      // a dozen required fields and none of them is the subject.
      final lapsed = Fx.me.copyWith(
        memberUntil: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final current = Fx.me.copyWith(
        memberUntil: DateTime.now().add(const Duration(days: 3)),
      );

      expect(lapsed.isMember, isFalse);
      expect(current.isMember, isTrue);
      expect(Fx.me.isMember, isFalse);
    });
  });

  group('the Monthly card', () {
    testWidgets('offers the price the store gave, not one we chose', (
      tester,
    ) async {
      await _pump(tester, billing: FixtureBillingService());

      await _scrollTo(tester, find.textContaining('Become a member'));
      // The fixture store charges $3.00 and the button repeats it exactly.
      // An app that reformatted this would be inventing an exchange rate.
      expect(find.textContaining(r'$3.00 a month'), findsOneWidget);
    });

    testWidgets('is not drawn at all when the store has no such product', (
      tester,
    ) async {
      await _pump(
        tester,
        billing: FixtureBillingService(storeHasProduct: false),
      );

      // No card, and no "coming soon" either: a card that cannot be tapped
      // is a card that should not be drawn (Grace, 2026-09-29).
      expect(find.textContaining('Become a member'), findsNothing);
      expect(find.textContaining('coming'), findsNothing);
    });

    testWidgets('buying it makes you a member, through the server', (
      tester,
    ) async {
      final billing = FixtureBillingService();
      final container = await _pump(tester, billing: billing);

      await _scrollTo(tester, find.textContaining('Become a member'));
      await tester.tap(find.textContaining('Become a member'));
      await tester.pumpAndSettle();

      // It bought the id the config gave it, not a guess.
      expect(billing.lastBought, 'lbm_member_monthly2');
      // And the card now reads off what came back, which is the person's
      // own record rather than anything this screen decided.
      expect(container.read(isMemberProvider), isTrue);
      expect(find.text('You are a member'), findsOneWidget);
      expect(find.textContaining('It renews on'), findsOneWidget);
    });

    testWidgets('backing out of the store is not an error', (tester) async {
      final billing = FixtureBillingService()
        ..nextOutcome = PurchaseOutcome.cancelled;
      final container = await _pump(tester, billing: billing);

      await _scrollTo(tester, find.textContaining('Become a member'));
      await tester.tap(find.textContaining('Become a member'));
      await tester.pumpAndSettle();

      // Nothing red, nothing claimed. Changing your mind at the till is a
      // normal thing to do and gets no message.
      expect(container.read(isMemberProvider), isFalse);
      expect(find.textContaining('would not'), findsNothing);
      expect(find.textContaining('Become a member'), findsOneWidget);
    });

    testWidgets('a store that refuses says so, and claims nothing', (
      tester,
    ) async {
      final billing = FixtureBillingService()
        ..nextOutcome = PurchaseOutcome.failed;
      final container = await _pump(tester, billing: billing);

      await _scrollTo(tester, find.textContaining('Become a member'));
      await tester.tap(find.textContaining('Become a member'));
      await tester.pumpAndSettle();

      expect(container.read(isMemberProvider), isFalse);
      expect(find.textContaining('would not take that'), findsOneWidget);
    });

    testWidgets('the copy says whose till it is', (tester) async {
      await _pump(tester, billing: FixtureBillingService());

      // The membership is Apple and Google's to bill and the one-time
      // amounts are the shop's, and the page has to say which is which.
      await _scrollTo(tester, find.textContaining('Billed by the app store'));
      expect(find.textContaining('Cancel any time'), findsOneWidget);
    });
  });
}
