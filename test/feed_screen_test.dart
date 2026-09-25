import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/widgets/cart_pill.dart';
import 'package:little_blue_market/widgets/filter_chips.dart';
import 'package:little_blue_market/widgets/hero_banner.dart';
import 'package:little_blue_market/widgets/masonry.dart';
import 'package:little_blue_market/widgets/pins/cart_pin.dart';
import 'package:little_blue_market/widgets/pins/chat_pin.dart';
import 'package:little_blue_market/widgets/pins/product_pin.dart';
import 'package:little_blue_market/widgets/pins/review_pin.dart';
import 'package:little_blue_market/widgets/pins/thread_pin.dart';
import 'package:little_blue_market/widgets/primitives.dart';

/// The Market feed, as the app actually builds it.
///
/// `feed_items_test.dart` checks the recipe; this checks that the recipe
/// reaches the screen: that Community content is in the Market grid, that the
/// filter chips narrow it, and that a pin leads where it says it does.
Future<ProviderContainer> _pumpFeed(
  WidgetTester tester, {
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
  return container;
}

/// Scrolls the grid until [finder] appears, or gives up.
///
/// The grid is lazy, so a pin eight items down does not exist until it is
/// nearly on screen. Everything here is about what is *in* the feed, which
/// means scrolling through it the way a person does.
Future<bool> _scrollTo(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 12; i++) {
    if (finder.evaluate().isNotEmpty) return true;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();
  }
  return finder.evaluate().isNotEmpty;
}

/// Taps a filter chip, scrolling the chip row sideways to reach it.
///
/// The row runs off the side of a phone and is lazy, so the later chips do
/// not exist until it has been scrolled; the page's vertical scrollable
/// cannot bring a horizontal one into view.
Future<void> _tapChip(WidgetTester tester, String label) async {
  final row = find
      .descendant(
        of: find.byType(FilterChips),
        matching: find.byType(Scrollable),
      )
      .first;

  // Back to the start first: the row stays where it was left, so a chip
  // earlier than the last one tapped is off the other side.
  await tester.drag(row, const Offset(600, 0));
  await tester.pumpAndSettle();

  if (find.text(label).evaluate().isEmpty) {
    await tester.scrollUntilVisible(find.text(label), 80, scrollable: row);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the feed is a two-column grid, not a list of cards', (
    tester,
  ) async {
    await _pumpFeed(tester);

    expect(find.byType(LbmMasonry), findsNothing, reason: 'built as slivers');

    // Far enough down that both columns have pins in them: the first screen
    // is the hero plus whatever two pins fit under it.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();

    final pins = find.byType(ProductPin);
    expect(pins, findsWidgets);

    // Two columns: every pin starts at one of two x offsets.
    final lefts = <double>{
      for (final pin in pins.evaluate())
        tester.getTopLeft(find.byWidget(pin.widget)).dx,
    };
    expect(lefts, hasLength(2), reason: 'expected two columns, got $lefts');
    expect(lefts, {10.0, 200.0});
  });

  testWidgets('community and commerce are in the same grid', (tester) async {
    await _pumpFeed(tester);

    // The market's own news, in the banner above the grid rather than as a
    // pin in it.
    expect(find.byType(HeroBanner), findsOneWidget);
    expect(find.byType(ProductPin), findsWidgets);

    // And, further down, the things that used to live in the other tab.
    expect(
      await _scrollTo(tester, find.byType(ThreadPin)),
      isTrue,
      reason: 'a forum question should reach the Market feed',
    );
    expect(
      await _scrollTo(tester, find.byType(ChatPin)),
      isTrue,
      reason: 'so should the open chat',
    );
  });

  testWidgets('reviews and posted carts are in it too', (tester) async {
    await _pumpFeed(tester);

    expect(await _scrollTo(tester, find.byType(ReviewPin)), isTrue);
    expect(await _scrollTo(tester, find.byType(CartPin)), isTrue);
  });

  testWidgets('the Forums chip leaves only forum pins', (tester) async {
    await _pumpFeed(tester);
    expect(find.byType(ProductPin), findsWidgets);

    await _tapChip(tester, 'Forums');

    expect(find.byType(ProductPin), findsNothing);
    expect(find.byType(ReviewPin), findsNothing);
    expect(find.byType(CartPin), findsNothing);
    expect(find.byType(ChatPin), findsNothing);
    // The banner is above the grid, so narrowing the grid never takes the
    // market's own news away.
    expect(find.byType(HeroBanner), findsOneWidget);
    expect(await _scrollTo(tester, find.byType(ThreadPin)), isTrue);
  });

  testWidgets('and Products brings the photographs back', (tester) async {
    await _pumpFeed(tester);
    await _tapChip(tester, 'Forums');
    expect(find.byType(ProductPin), findsNothing);

    await _tapChip(tester, 'Products');
    expect(find.byType(ProductPin), findsWidgets);
  });

  testWidgets('a cart pill is on the grid, and Buy is not', (tester) async {
    await _pumpFeed(tester);

    expect(find.byType(CartPill), findsWidgets);
    // Buying is a decision made on the thing's own page now.
    expect(find.text('Buy'), findsNothing);
    // And there is no heart anywhere: carting is the affinity signal.
    expect(find.byIcon(Icons.favorite_border), findsNothing);
    expect(find.byIcon(Icons.favorite), findsNothing);
  });

  testWidgets('there are two ways in, and Following is not one', (
    tester,
  ) async {
    await _pumpFeed(tester);

    expect(find.byType(TopTabs), findsOneWidget);
    expect(find.text('For you'), findsOneWidget);
    expect(find.text('Near me'), findsOneWidget);
    // Removed 2026-09-25: with tags not yet followable it could only filter
    // by people, which on a young market is an empty screen most of the time.
    expect(find.text('Following'), findsNothing);
  });

  testWidgets('the banner is one size and scrolls with the grid', (
    tester,
  ) async {
    await _pumpFeed(tester);

    final banner = find.byType(HeroBanner);
    expect(banner, findsOneWidget);
    expect(tester.getSize(banner).height, HeroBanner.height);

    final before = tester.getTopLeft(banner).dy;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
    await tester.pumpAndSettle();

    // It moved with everything else rather than staying pinned at the top.
    expect(tester.getTopLeft(banner).dy, lessThan(before));
  });

  testWidgets('a CTA that is not a route in this app opens nothing', (
    tester,
  ) async {
    // Admins type these by hand on the website, so they arrive as anything.
    expect(HeroBanner.normaliseRoute('/community'), '/community');
    expect(HeroBanner.normaliseRoute(''), isNull);
    expect(HeroBanner.normaliseRoute('   '), isNull);
    expect(HeroBanner.normaliseRoute('not a url'), isNull);
    expect(HeroBanner.normaliseRoute('https://example.com/sale'), isNull);
    expect(
      HeroBanner.normaliseRoute('https://littlebluecart.com/market/search'),
      '/market/search',
    );
    expect(HeroBanner.normaliseRoute('https://littlebluecart.com'), '/market');
  });

  testWidgets('a guest gets no community pins and a join bar', (tester) async {
    await _pumpFeed(tester, guest: true);

    expect(find.byType(GuestJoinBar), findsOneWidget);
    expect(find.byType(ProductPin), findsWidgets);

    // Every community route bounces a guest, so a pin inviting them in would
    // be an invitation to a locked door.
    expect(await _scrollTo(tester, find.byType(ThreadPin)), isFalse);
    expect(find.byType(ChatPin), findsNothing);
  });

  testWidgets('the tab bar is Market, Community, post, Cart, You', (
    tester,
  ) async {
    await _pumpFeed(tester);

    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    expect(find.bySemanticsLabel('Post something'), findsOneWidget);
    expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
  });
}
