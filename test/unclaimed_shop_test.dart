import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/primitives.dart';
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
  group('the badge on a shop profile and a listing', () {
    // It was a card with four lines and a button, and on a shell profile it
    // was the biggest thing on the screen. Grace, 2026-09-24: "I want it to
    // not be so large and I want it to only let others know that this
    // seller is not active on the app... maybe make it a small badge of
    // some kind that is clickable."
    testWidgets('says the one thing, and nothing else, until it is tapped', (
      tester,
    ) async {
      await _pump(tester, UnclaimedShopBadge(person: _shop()));
      expect(find.text('Not active on the app yet'), findsOneWidget);
      // The explanation is behind the tap. This is the whole point: none of
      // it is on the profile taking up room.
      expect(find.textContaining('you can buy it as normal'), findsNothing);
      expect(find.text('Is this your shop?'), findsNothing);
    });

    testWidgets('tapping it explains, and offers the way in', (tester) async {
      await _pump(tester, UnclaimedShopBadge(person: _shop()));
      await tester.tap(find.text('Not active on the app yet'));
      await tester.pumpAndSettle();

      // Nothing was cut in the move: the two facts a buyer needs are both
      // here, in words, plus the door for whoever owns the shop.
      expect(find.textContaining('you can buy it as normal'), findsOneWidget);
      expect(find.textContaining('message will wait'), findsOneWidget);
      expect(find.text('Is this your shop?'), findsOneWidget);
    });

    testWidgets('on a listing the sheet leaves the claim door off', (
      tester,
    ) async {
      // There the shop is not the subject of the screen, and the door
      // belongs on the shop's own page.
      await _pump(
        tester,
        UnclaimedShopBadge(person: _shop(), offerClaim: false),
      );
      await tester.tap(find.text('Not active on the app yet'));
      await tester.pumpAndSettle();
      expect(find.textContaining('you can buy it as normal'), findsOneWidget);
      expect(find.text('Is this your shop?'), findsNothing);
    });

    testWidgets('a claimed shop gets no badge at all', (tester) async {
      await _pump(tester, UnclaimedShopBadge(person: _shop(unclaimed: false)));
      expect(find.text('Not active on the app yet'), findsNothing);
      // Drawn as nothing, not as an empty chip with padding round it.
      expect(find.byType(LbmChip), findsNothing);
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
