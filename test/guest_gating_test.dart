import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/widgets/cart_pill.dart';
import 'package:little_blue_market/widgets/profile_identity.dart';
import 'package:little_blue_market/state/session.dart';

/// Boots the real app straight into the market, so the tab bar and the gate
/// under test are the ones the app actually ships.
Future<ProviderContainer> _pumpApp(WidgetTester tester, {required bool guest}) async {
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
  return container;
}

/// Opens a listing from the grid and taps its Buy button.
///
/// Buy left the feed with the redesign: a pin carries the cart pill and
/// nothing else, and buying something is a decision made on the thing's own
/// page. The gate it runs into is the same gate.
/// Taps the cart pill on the first pin in the grid.
Future<void> _tapFirstCartPill(WidgetTester tester) async {
  final pill = find.byType(CartPill).first;
  await tester.ensureVisible(pill);
  await tester.pumpAndSettle();
  await tester.tap(pill);
  await tester.pumpAndSettle();

  // The very first add explains what the cart means here before it adds
  // anything. A guest never gets this far; a member has to say Got it.
  if (find.text('Got it').evaluate().isNotEmpty) {
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
  }
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

  testWidgets('a guest gets the gate instead of the community', (tester) async {
    await _pumpApp(tester, guest: true);

    await tester.tap(find.text('Sign up to unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Make a profile to do that'), findsOneWidget);
    expect(find.text('Create a profile'), findsOneWidget);
  });

  testWidgets('a guest gets the gate instead of the cart', (tester) async {
    await _pumpApp(tester, guest: true);
    // Straight from the grid: the cart pill is the one commerce action a pin
    // offers, and it is the one a guest is most likely to reach for.
    await _tapFirstCartPill(tester);

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
    final container = await _pumpApp(tester, guest: false);
    await _tapFirstCartPill(tester);

    // The same action that gates a guest goes straight through for a member:
    // the line lands in the cart and nothing asks them to sign up.
    expect(find.text('Make a profile to do that'), findsNothing);
    expect(
      container.read(cartProvider).value?.lines,
      isNotEmpty,
      reason: 'the pill is the commerce action a pin offers',
    );

    // Buy now itself, and its "Finish in checkout" hand-off, is driven in
    // `checkout_sheet_test.dart`. It cannot be reached from here any more:
    // Buy left the feed with the redesign and lives on a product's own page,
    // which does not get past its skeleton in a widget test.
  });

  testWidgets('the cart does not invent a total it cannot know', (
    tester,
  ) async {
    final container = await _pumpApp(tester, guest: false);
    // Buy is buy-now and leaves the cart alone, so put something in the cart
    // the way the cart icon does, then look at the cart screen.
    await container.read(commerceRepositoryProvider).addLine(productId: 'p1');
    container.read(routerProvider).go('/market/cart');
    await tester.pumpAndSettle();

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
    // The stat row is Instagram's, remapped: Posts and Bought, no Follow.
    // Scoped to the identity block, because "Bought" is also a tab below it.
    Finder stat(String label) => find.descendant(
      of: find.byType(ProfileIdentity),
      matching: find.text(label),
    );
    expect(stat('Posts'), findsOneWidget);
    expect(stat('Bought'), findsOneWidget);
    // Sales came off the public profile on 2026-09-24: still counted,
    // no longer printed next to somebody's name.
    expect(find.text('Total sales'), findsNothing);
    expect(find.text('Followers'), findsNothing);
    expect(find.text('Following'), findsNothing);
    expect(find.text('Follow'), findsNothing);
  });
  testWidgets('Notify me on a profile follows and unfollows in one tap', (
    tester,
  ) async {
    final container = await _pumpApp(tester, guest: false);
    container.read(routerProvider).go('/market/seller/kali');
    await tester.pumpAndSettle();

    expect(find.text('Notify me'), findsOneWidget);
    await tester.tap(find.text('Notify me'));
    await tester.pumpAndSettle();
    expect(find.text('Notifying you'), findsOneWidget);
    expect(find.text('You will hear when they post.'), findsOneWidget);

    await tester.tap(find.text('Notifying you'));
    await tester.pumpAndSettle();
    expect(find.text('Notify me'), findsOneWidget);
  });

  testWidgets('a guest tapping Notify me gets the gate', (tester) async {
    final container = await _pumpApp(tester, guest: true);
    container.read(routerProvider).go('/market/seller/kali');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Notify me'));
    await tester.pumpAndSettle();
    expect(find.text('Make a profile to do that'), findsOneWidget);
  });
}
