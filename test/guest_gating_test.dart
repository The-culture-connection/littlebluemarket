import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';

/// Boots the real app straight into the market, so the tab bar and the gate
/// under test are the ones the app actually ships.
Future<void> _pumpApp(WidgetTester tester, {required bool guest}) async {
  // The design targets a phone; the default 800x600 test surface would put
  // half the feed off-screen.
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
  // Step past the welcome handoff into the market.
  await tester.pump();
  await tester.tap(
    find.bySemanticsLabel('Continue as a guest'),
    warnIfMissed: false,
  );
  await tester.pumpAndSettle();

  // Signing in from here also exercises the guest-to-member transition, which
  // is what unlocks the two hidden tabs.
  if (!guest) {
    container.read(sessionProvider.notifier).signIn();
    await tester.pumpAndSettle();
  }
}

/// Scrolls the feed until the first Buy button is on screen, then taps it.
Future<void> _tapFirstBuy(WidgetTester tester) async {
  final buy = find.text('Buy').first;
  await tester.ensureVisible(buy);
  await tester.pumpAndSettle();
  await tester.tap(buy);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a guest sees Market and a locked slot, not three tabs', (
    tester,
  ) async {
    await _pumpApp(tester, guest: true);

    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Sign up to unlock'), findsOneWidget);
    expect(find.text('Community'), findsNothing);
    expect(find.text('You'), findsNothing);
  });

  testWidgets('a guest gets the gate instead of the community', (
    tester,
  ) async {
    await _pumpApp(tester, guest: true);

    await tester.tap(find.text('Sign up to unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Make a profile to do that'), findsOneWidget);
    expect(find.text('Create a profile'), findsOneWidget);
  });

  testWidgets('a guest gets the gate instead of the cart', (tester) async {
    await _pumpApp(tester, guest: true);
    await _tapFirstBuy(tester);

    expect(find.text('Make a profile to do that'), findsOneWidget);
    expect(find.text('Your cart'), findsNothing);
  });

  testWidgets('a guest sees the browsing banner', (tester) async {
    await _pumpApp(tester, guest: true);

    expect(find.textContaining('Looking around as a guest'), findsOneWidget);
  });

  testWidgets('signing in reveals all three tabs and hides the banner', (
    tester,
  ) async {
    await _pumpApp(tester, guest: false);

    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Sign up to unlock'), findsNothing);
    expect(find.textContaining('Looking around as a guest'), findsNothing);
  });

  testWidgets('a signed-in buyer reaches the cart, not the gate', (
    tester,
  ) async {
    await _pumpApp(tester, guest: false);
    await _tapFirstBuy(tester);

    // Buy adds to the cart and opens it. The prototype's sheet confirmed an
    // order against a hardcoded address and an invented flat shipping rate,
    // then navigated as though an order had been placed.
    expect(find.text('Your cart'), findsOneWidget);
    expect(find.text('Make a profile to do that'), findsNothing);
  });

  testWidgets('the cart does not invent a total it cannot know', (
    tester,
  ) async {
    await _pumpApp(tester, guest: false);
    await _tapFirstBuy(tester);

    expect(find.text('Calculated at checkout'), findsOneWidget);
    expect(find.text('Total so far'), findsOneWidget);
  });

  testWidgets('the community tab is reachable once signed in', (tester) async {
    await _pumpApp(tester, guest: false);

    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();

    expect(find.text('Open chat'), findsOneWidget);
  });

  testWidgets('the You tab shows your own profile', (tester) async {
    await _pumpApp(tester, guest: false);

    await tester.tap(find.text('You'));
    await tester.pumpAndSettle();

    expect(find.text(Fx.me.handle), findsOneWidget);
    // The stat row is Instagram's, remapped.
    expect(find.text('Revenue'), findsOneWidget);
    expect(find.text('Purchases'), findsOneWidget);
    expect(find.text('Followers'), findsNothing);
    expect(find.text('Following'), findsNothing);
    expect(find.text('Follow'), findsNothing);
  });
}
