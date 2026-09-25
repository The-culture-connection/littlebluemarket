import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/widgets/shipturtle.dart';

/// The You hub, the things you bought, and a seller's own shop.
///
/// Grace, 2026-09-25: "make it quieter", and the review entry should open
/// the list of what you bought rather than one product.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String at = '/you',
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
  container.read(sessionProvider.notifier).signIn();
  await tester.pumpAndSettle();
  container.read(routerProvider).go(at);
  await tester.pumpAndSettle();
  return container;
}

/// Every word currently on screen.
List<String> _words(WidgetTester tester) => [
  for (final element in find.byType(Text).evaluate())
    ?(element.widget as Text).data,
];

void main() {
  group('the You hub', () {
    testWidgets('says who you are without shouting', (tester) async {
      await _pump(tester);

      expect(find.text('You'), findsWidgets);
      expect(find.text(Fx.me.name), findsOneWidget);
      // Four numbers, and only ones this system holds.
      expect(find.text('Bought'), findsWidgets);
      expect(find.text('Reviews'), findsWidgets);
      expect(find.text('Posts'), findsWidgets);
    });

    testWidgets('has no points, levels, streaks, shipping or orders', (
      tester,
    ) async {
      await _pump(tester);

      // None of these exist in this product, and the two that do belong to
      // Shipturtle rather than to a screen in here.
      final banned = RegExp(
        r'points|level \d|streak|shipping|orders',
        caseSensitive: false,
      );
      for (final word in _words(tester)) {
        expect(
          banned.hasMatch(word),
          isFalse,
          reason: 'the You hub should not say "$word"',
        );
      }
    });

    testWidgets('one quiet banner when something wants a review', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.textContaining('waiting for a review'), findsOneWidget);
      expect(find.text('Rate'), findsOneWidget);
    });

    testWidgets('the banner opens the list of what you bought', (tester) async {
      await _pump(tester);

      await tester.tap(find.textContaining('waiting for a review'));
      await tester.pumpAndSettle();

      expect(find.text('Things you bought'), findsOneWidget);
      expect(find.textContaining('Waiting for a review'), findsOneWidget);
    });
  });

  group('things you bought', () {
    testWidgets('puts the ones still wanting a review first', (tester) async {
      final container = await _pump(tester, at: '/you/purchases');
      final purchases = await container.read(purchasesProvider.future);
      final waiting = purchases.where((p) => p.canReview).length;

      expect(find.text('Waiting for a review ($waiting)'), findsOneWidget);
      expect(find.text('Rate it'), findsWidgets);
    });

    testWidgets('Rate it opens the review sheet on the stars', (tester) async {
      await _pump(tester, at: '/you/purchases');

      await tester.tap(find.text('Rate it').first);
      await tester.pumpAndSettle();

      // Star-first: the question, the stars, and the words optional.
      expect(find.textContaining('How was the'), findsOneWidget);
      expect(find.text('Tap a star. That on its own counts.'), findsOneWidget);
      expect(find.textContaining('optional'), findsOneWidget);
      expect(find.text('Post review'), findsOneWidget);
    });

    testWidgets('a review with no words at all is allowed', (tester) async {
      final container = await _pump(tester, at: '/you/purchases');
      final before = await container.read(purchasesProvider.future);
      final target = before.firstWhere((p) => p.canReview);

      // Listened to before the write, and pumped after it: awaiting a
      // provider's future inside a widget test hangs, because nothing
      // advances the queue it is waiting on.
      container.listen(
        reviewsProvider(target.productId),
        (_, _) {},
        fireImmediately: true,
      );

      await tester.tap(find.text('Rate it').first);
      await tester.pumpAndSettle();
      // Straight to Post: no chips tapped, nothing typed.
      await tester.tap(find.text('Post review'));
      await tester.pumpAndSettle();

      final reviews =
          container.read(reviewsProvider(target.productId)).value ??
          const <Review>[];
      expect(reviews, isNotEmpty, reason: 'stars on their own are a review');
      expect(reviews.first.text, isEmpty);
      expect(reviews.first.rating, greaterThan(0));

      // Let the "Review posted" toast run out so no timer outlives the test.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });

  group('the seller shop', () {
    testWidgets('hands off to Shipturtle and offers no orders screen', (
      tester,
    ) async {
      await _pump(tester, at: '/you/sell');

      expect(find.text('Your shop'), findsWidgets);
      expect(find.text('Total sales'), findsOneWidget);
      expect(
        find.textContaining('managed in Shipturtle, not here'),
        findsOneWidget,
      );

      // The only place the word appears is the sentence saying where orders
      // actually live. No heading, no tab, no row that opens a list of them.
      for (final word in _words(tester)) {
        if (word.contains('Shipturtle')) continue;
        expect(
          RegExp(r'^\s*orders\b', caseSensitive: false).hasMatch(word),
          isFalse,
          reason: 'the shop should not have an "$word" section',
        );
      }
    });

    test('Shipturtle is where the hand-off goes', () {
      // The app never grew an orders screen and is not going to: Shipturtle
      // owns orders, shipping and payouts. One constant, four call sites.
      expect(kShipturtleFallbackUrl, 'https://app.shipturtle.com/');
    });
  });

  group('notification settings', () {
    testWidgets('carries the switch the tag fan-out will honour', (
      tester,
    ) async {
      final container = await _pump(tester, at: '/you/notification-settings');
      container.listen(
        notificationPrefsProvider,
        (_, _) {},
        fireImmediately: true,
      );

      final row = find.text('New posts under tags you follow');
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(row, findsOneWidget);

      expect(
        container.read(notificationPrefsProvider).value?.tagPosts,
        isTrue,
        reason: 'on by default, like every other switch',
      );
    });

    test('the preference is separate from following a person', () {
      // Following a maker and following a subject are different appetites,
      // and one being too noisy should not silence the other.
      const prefs = NotificationPrefs();
      expect(prefs.tagPosts, isTrue);
      expect(prefs.copyWith(tagPosts: false).tagPosts, isFalse);
      expect(prefs.copyWith(tagPosts: false).newPosts, isTrue);
      expect(prefs.copyWith(tagPosts: false).toMap()['tagPosts'], isFalse);
    });
  });
}
