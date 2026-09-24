import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/profile_identity.dart';

/// The three figures at the top of a shop's profile.
///
/// Grace, 2026-09-24: "can we add amount of products to the header numbers
/// along with bought and posts?" The figure has to be counted rather than
/// measured off the grid below it: a shop's products arrive thirty at a
/// time and most shops on the market have far more, so a number taken from
/// the first page would say 30 for a shop with 214. A header that disagrees
/// with the tiles under it is the complaint that started this whole round.
Person _person({required bool isSeller, int posts = 4, int purchases = 7}) =>
    Person(
      id: 'polly',
      name: 'Polly Politics',
      handle: '@polly-politics',
      tint: 0xFF5C8FCB,
      bio: 'Buttons and banners.',
      tags: const [],
      grossSalesCents: 125000,
      purchases: purchases,
      posts: posts,
      isSeller: isSeller,
    );

Future<void> _pump(
  WidgetTester tester,
  Person person, {
  int? productCount,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (productCount != null)
          sellerProductCountProvider(
            person.id,
          ).overrideWith((ref) async => productCount),
      ],
      child: MaterialApp(
        theme: buildLbmTheme(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: ProfileIdentity(person: person, actions: const []),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a shop shows Products, Posts and Bought', (tester) async {
    await _pump(tester, _person(isSeller: true), productCount: 214);

    expect(find.text('Products'), findsOneWidget);
    expect(find.text('214'), findsOneWidget, reason: 'the whole count, not 30');
    expect(find.text('Posts'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Bought'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('Products leads: it is the one fact about the shop', (
    tester,
  ) async {
    await _pump(tester, _person(isSeller: true), productCount: 214);
    final products = tester.getCenter(find.text('Products')).dx;
    final posts = tester.getCenter(find.text('Posts')).dx;
    final bought = tester.getCenter(find.text('Bought')).dx;
    expect(products, lessThan(posts));
    expect(posts, lessThan(bought));
  });

  testWidgets('a buyer has no products, and no empty cell where they would be', (
    tester,
  ) async {
    await _pump(tester, _person(isSeller: false));
    expect(find.text('Products'), findsNothing);
    expect(find.text('Posts'), findsOneWidget);
    expect(find.text('Bought'), findsOneWidget);
  });

  testWidgets('while counting it holds the space instead of claiming zero', (
    tester,
  ) async {
    // A shop with two hundred products flashing "0" reads as a shop with
    // nothing in it. The override never completes, which is what a slow
    // count looks like.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sellerProductCountProvider(
            'polly',
          ).overrideWith((ref) => Completer<int>().future),
        ],
        child: MaterialApp(
          theme: buildLbmTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileIdentity(
                person: _person(isSeller: true),
                actions: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Products'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.text('-'), findsOneWidget);
  });

  testWidgets('three figures still fit at double text size', (tester) async {
    // The row is fixed thirds and each cell shrinks its own value, so the
    // risk is an overflow rather than a wrap. Overflow throws in tests.
    await _pump(
      tester,
      _person(isSeller: true, posts: 1200, purchases: 340),
      productCount: 16342,
      textScale: 2.0,
    );
    expect(find.text('Products'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
