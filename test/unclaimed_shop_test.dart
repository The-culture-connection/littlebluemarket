import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/unclaimed_shop.dart';

/// A shop that is on the market but that nobody has signed up for (Grace,
/// 2026-09-24). It looks like any other shop, and it says the one thing
/// that is different about it: nobody is reading.
Person _shop({bool unclaimed = true}) => Person(
  id: unclaimed ? 'shop_found-house' : 'kali',
  name: 'Found House Ceramics',
  handle: unclaimed ? '@found-house' : '@foundhouse',
  tint: 0xFF5C8FCB,
  bio: '',
  tags: const [],
  grossSalesCents: 0,
  purchases: 0,
  posts: 0,
  unclaimed: unclaimed,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildLbmTheme(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the card on a shop profile and a listing', () {
    testWidgets('says the shop is not on the app, and offers the way in', (
      tester,
    ) async {
      await _pump(tester, UnclaimedShopCard(person: _shop()));
      expect(find.text('Not on the app yet'), findsOneWidget);
      expect(find.textContaining('you can buy it as normal'), findsOneWidget);
      expect(find.text('Is this your shop?'), findsOneWidget);
    });

    testWidgets('the compact one leaves the claim door off', (tester) async {
      // On a listing the shop is not the subject of the screen, and the
      // door belongs on the shop's own page.
      await _pump(tester, UnclaimedShopCard(person: _shop(), compact: true));
      expect(find.text('Not on the app yet'), findsOneWidget);
      expect(find.text('Is this your shop?'), findsNothing);
    });

    testWidgets('a claimed shop gets no card at all', (tester) async {
      await _pump(tester, UnclaimedShopCard(person: _shop(unclaimed: false)));
      expect(find.text('Not on the app yet'), findsNothing);
      // Drawn as nothing, not as an empty box with padding round it.
      expect(find.byType(Container), findsNothing);
    });
  });

  group('the strip above a message thread', () {
    testWidgets('warns that nobody is reading, before anything is typed', (
      tester,
    ) async {
      await _pump(tester, UnclaimedShopStrip(person: _shop()));
      expect(
        find.textContaining('has not claimed their shop on the app yet'),
        findsOneWidget,
      );
      // And says what happens to the message, which is the part that
      // decides whether somebody bothers writing it.
      expect(find.textContaining('reaches them when they sign up'), findsOneWidget);
    });

    testWidgets('a real person gets no strip', (tester) async {
      await _pump(tester, UnclaimedShopStrip(person: _shop(unclaimed: false)));
      expect(find.byType(Container), findsNothing);
    });
  });

  group('the model', () {
    test('a profile is claimed unless it says otherwise', () {
      expect(_shop(unclaimed: false).unclaimed, isFalse);
      expect(_shop().unclaimed, isTrue);
    });
  });
}
