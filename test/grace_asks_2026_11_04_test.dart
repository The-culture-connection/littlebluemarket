import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:little_blue_market/analytics/analytics.dart';
import 'package:little_blue_market/data/fixtures/fixture_repositories.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/screens/market/directory_near_me.dart';
import 'package:little_blue_market/screens/market/store_page_screen.dart';
import 'package:little_blue_market/state/promos.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/directory_listing_card.dart';
import 'package:little_blue_market/widgets/reactions.dart';

/// Grace's four asks of 2026-11-04: analytics, store pages that match the
/// original, Near me for the directory, and emoji reactions.

Future<ProviderContainer> _pumpMember(
  WidgetTester tester, {
  List overrides = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    retry: lbmRetry,
    overrides: [...overrides],
  );
  addTearDown(container.dispose);
  container.read(sessionProvider.notifier).signIn();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const LittleBlueMarketApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Widget _themed(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: buildLbmTheme(Brightness.light),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  group('analytics', () {
    setUp(Analytics.reset);

    test('an event keeps its name, facts and when, and drops empty facts', () {
      Analytics.track('add_to_cart', {'productId': 'p1', 'variantId': null});
      final e = Analytics.recent.last;
      expect(e.name, 'add_to_cart');
      expect(e.props, {'productId': 'p1'});
      expect(e.toJson()['at'], isA<String>());
      expect(e.toJson().containsKey('uid'), isFalse);
    });

    testWidgets('every screen opened is recorded, once each', (tester) async {
      final c = await _pumpMember(tester);
      c.read(routerProvider).go('/community');
      await tester.pumpAndSettle();
      c.read(routerProvider).go('/community');
      await tester.pumpAndSettle();
      final screens = [
        for (final e in Analytics.recent)
          if (e.name == 'screen_view') e.props['screen'],
      ];
      expect(screens, contains('/market'));
      expect(screens.where((s) => s == '/community').length, 1);

      // A screen pushed on top, which the address alone would miss.
      c.read(routerProvider).push('/market/search');
      await tester.pumpAndSettle();
      expect(
        Analytics.recent.last.props['screen'],
        '/market/search',
        reason: 'pushed screens count too',
      );
    });
  });

  group('store pages', () {
    testWidgets('a page that will not load says so, never "a form"', (
      tester,
    ) async {
      // 2026-11-04: the live backend lacked storePageRead, so every page
      // said it was a form or a tool.
      const page = StorePage(
        id: 'gg',
        url: 'https://littlebluemarket.com/pages/holiday-gift-guide',
        title: 'Progressive Holiday Gift Guide 2026',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storePagesProvider.overrideWith((ref) => Stream.value([page])),
            storePageReadProvider.overrideWith(
              (ref, id) => Future<int>.error(Exception('not-found')),
            ),
          ],
          child: MaterialApp.router(
            theme: buildLbmTheme(Brightness.light),
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) =>
                      const Scaffold(body: StorePageScreen(pageId: 'gg')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('This page did not load'), findsOneWidget);
      expect(find.text('This page is best seen on the website'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Near me for the directory', () {
    DirectoryListing listing(
      String id, {
      double? lat,
      double? lng,
      List<String> categories = const [],
      String zip = '',
      String phone = '',
    }) => DirectoryListing(
      id: id,
      ownerUid: 'unclaimed',
      title: 'Shop $id',
      status: 'publish',
      link: 'https://littlebluecart.com/listing/$id',
      lat: lat,
      lng: lng,
      categories: categories,
      zip: zip,
      phone: phone,
    );

    test('nearest first, and a listing with no town is left out', () {
      final out = nearestFirst(
        [
          listing('far', lat: 29.0, lng: -81.0),
          listing('none'),
          listing('near', lat: 28.55, lng: -81.38),
        ],
        28.54,
        -81.38,
      );
      expect(out.map((e) => e.$1.id), ['near', 'far']);
      expect(out.first.$2, lessThan(1));
    });

    test('a category matches however the site escaped its name', () {
      final l = listing('a', categories: ['Arts &amp; Crafts']);
      expect(inCategory(l, 'Arts & Crafts'), isTrue);
      expect(inCategory(l, 'Food'), isFalse);
    });

    testWidgets('a card shows how far and the zip code, never the street, '
        'and calls for directions', (tester) async {
      await tester.pumpWidget(
        _themed(
          DirectoryListingCard(
            listing: listing('a', zip: '32801', phone: '407-555-0100'),
            milesAway: 3.4,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('3.4 mi away · Zip code 32801'), findsOneWidget);
      expect(find.text('Call for directions'), findsOneWidget);
    });
  });

  group('reactions', () {
    test('the blue heart leads the quick row', () {
      expect(quickReactions.first, '💙');
      expect(quickReactions, isNot(contains('❤️')));
    });

    test('counts, most used first, with yours marked', () {
      final summary = reactionSummary({
        'a': '👍',
        'b': '💙',
        'me': '💙',
        'c': '🦄',
      }, 'me');
      expect(summary.first, (emoji: '💙', count: 2, mine: true));
      expect(summary.map((r) => r.emoji), ['💙', '👍', '🦄']);
    });

    test('the same emoji again takes it back; another replaces it', () {
      expect(toggledReaction('💙', '💙'), isNull);
      expect(toggledReaction('💙', '😂'), '😂');
      expect(toggledReaction(null, '🙏'), '🙏');
    });

    testWidgets('long press a chat message, pick the blue heart', (
      tester,
    ) async {
      final c = await _pumpMember(tester);
      c.read(routerProvider).go('/community');
      await tester.pumpAndSettle();

      final message = find.byType(Reactable).first;
      expect(message, findsOneWidget);
      await tester.longPress(message);
      await tester.pumpAndSettle();
      expect(find.text('React'), findsOneWidget);

      await tester.tap(find.text('💙'));
      await tester.pumpAndSettle();
      final repo =
          c.read(messagingRepositoryProvider) as FixtureMessagingRepository;
      expect(repo.reactionsSet.single.$1, isA<ChatReactionTarget>());
      expect(repo.reactionsSet.single.$2, '💙');
    });

    testWidgets('the + opens every emoji', (tester) async {
      final c = await _pumpMember(tester);
      c.read(routerProvider).go('/community');
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(Reactable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded).last);
      await tester.pumpAndSettle();
      expect(find.byType(ReactionChips), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chips under a message toggle yours', (tester) async {
      final c = await _pumpMember(tester);
      const target = ChatReactionTarget('m1');
      final me = c.read(currentUidProvider)!;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: _themedBare(
            ReactionChips(
              target: target,
              reactions: {me: '💙', 'other': '💙', 'x': '😂'},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('💙 2'), findsOneWidget);
      expect(find.text('😂 1'), findsOneWidget);
      await tester.tap(find.text('💙 2'));
      await tester.pumpAndSettle();
      final repo =
          c.read(messagingRepositoryProvider) as FixtureMessagingRepository;
      // Yours already: tapping takes it back.
      expect(repo.reactionsSet.last.$2, isNull);
    });
  });
}

Widget _themedBare(Widget child) => MaterialApp(
  theme: buildLbmTheme(Brightness.light),
  home: Scaffold(body: child),
);
