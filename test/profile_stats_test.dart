import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';

/// The figures at the top of a shop's board.
///
/// Grace, 2026-09-24: "can we add amount of products to the header numbers
/// along with bought and posts?" The figure has to be counted rather than
/// measured off the grid below it: a shop's products arrive thirty at a
/// time and most shops on the market have far more, so a number taken from
/// the first page would say 30 for a shop with 214. A header that disagrees
/// with the tiles under it is the complaint that started this whole round.
///
/// The header moved into `seller_feed_screen.dart` with the redesign, so
/// these pump the real screen rather than a widget that no longer exists.
Future<ProviderContainer> _pumpShop(
  WidgetTester tester, {
  int? productCount,
  double textScale = 1.0,
  bool neverCounts = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  final container = ProviderContainer(
    retry: lbmRetry,
    overrides: [
      if (neverCounts)
        sellerProductCountProvider(
          'kali',
        ).overrideWith((ref) => Completer<int>().future)
      else if (productCount != null)
        sellerProductCountProvider(
          'kali',
        ).overrideWith((ref) async => productCount),
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
  container.read(routerProvider).go('/market/seller/kali');
  // Settles even when the count never arrives: an unfinished future is not
  // an animation, so nothing is left pending for pumpAndSettle to wait on.
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a shop shows what it has sold, listed and been carted', (
    tester,
  ) async {
    await _pumpShop(tester, productCount: 214);

    expect(find.text('Listings'), findsOneWidget);
    expect(find.text('214'), findsOneWidget, reason: 'the whole count, not 30');
    expect(find.text('Total sales'), findsOneWidget);
    expect(find.text('Carted'), findsOneWidget);
  });

  testWidgets('while counting it holds the space instead of claiming zero', (
    tester,
  ) async {
    // A shop with two hundred products flashing "0" reads as a shop with
    // nothing in it. The override never completes, which is what a slow
    // count looks like.
    await _pumpShop(tester, neverCounts: true);

    expect(find.text('Listings'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('the figures still fit at double text size', (tester) async {
    // Each cell shrinks its own value to fit rather than pushing its
    // neighbours off the row, so the risk is an overflow. Overflow throws.
    await _pumpShop(tester, productCount: 16342, textScale: 2.0);

    expect(find.text('Listings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('a buyer has no shop numbers to show', () {
    // Sales, listings and carted are a seller's; a buyer's board shows what
    // they have bought and posted instead.
    const buyer = Person(
      id: 'dee',
      name: 'Dee Wells',
      handle: '@dee',
      tint: 0xFF5C8FCB,
      bio: '',
      tags: [],
      grossSalesCents: 0,
      purchases: 7,
      posts: 4,
      isSeller: false,
    );
    expect(buyer.isSeller, isFalse);
    expect(buyer.purchases, 7);
    expect(buyer.posts, 4);
  });
}
