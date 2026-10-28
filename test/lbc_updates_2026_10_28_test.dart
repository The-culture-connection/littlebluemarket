import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/screens/market/cart_screen.dart';
import 'package:little_blue_market/screens/market/feed_screen.dart';
import 'package:little_blue_market/screens/market/market_screen.dart';
import 'package:little_blue_market/router/nav.dart';
import 'package:little_blue_market/models/feed_item.dart';
import 'package:little_blue_market/screens/market/search_screen.dart';
import 'package:little_blue_market/screens/market/store_page_screen.dart';
import 'package:little_blue_market/data/firebase/mappers.dart';
import 'package:little_blue_market/state/promos.dart';
import 'package:little_blue_market/state/feed_items.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/widgets/pins/store_page_pin.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/theme/tokens.dart';
import 'package:little_blue_market/widgets/app_shell.dart' show LbmTabBar;
import 'package:little_blue_market/widgets/hero_banner.dart';
import 'package:little_blue_market/widgets/primitives.dart';
import 'package:little_blue_market/widgets/promo_popup.dart';

/// Grace's list of 2026-10-28, "Running LBC Updates".

Future<ProviderContainer> _pumpMember(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(retry: lbmRetry);
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

String _path(ProviderContainer c) =>
    c.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

Finder _inBar(Finder f) =>
    find.descendant(of: find.byType(LbmTabBar), matching: f);

GoRouter _pageRouter(String id) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(body: StorePageScreen(pageId: id)),
    ),
  ],
);

Promo _promo({
  PromoKind kind = PromoKind.ad,
  List<String> imageUrls = const [],
  String ctaLabel = '',
  String ctaUrl = '',
  String ctaColor = '',
}) => Promo(
  id: 'p28',
  kind: kind,
  title: 'Holiday market',
  caption: 'Forty makers, one room.',
  audience: AnnouncementAudience.all,
  imageUrls: imageUrls,
  ctaLabel: ctaLabel,
  ctaUrl: ctaUrl,
  ctaColor: ctaColor,
);

void main() {
  group('the bottom menu and HOME', () {
    testWidgets(
      'Market opens the categories, and HOME comes back to the feed',
      (tester) async {
        final c = await _pumpMember(tester);
        expect(_path(c), '/market');

        await tester.tap(_inBar(find.text('Market')));
        await tester.pumpAndSettle();
        expect(find.byType(MarketScreen), findsOneWidget);

        await tester.tap(find.byIcon(Icons.home_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(MarketScreen), findsNothing);
        expect(find.byType(FeedScreen).hitTestable(), findsOneWidget);
      },
    );

    testWidgets('tapping Market twice does not stack a second one', (
      tester,
    ) async {
      final c = await _pumpMember(tester);
      await tester.tap(_inBar(find.text('Market')));
      await tester.pumpAndSettle();
      await tester.tap(_inBar(find.text('Market')));
      await tester.pumpAndSettle();
      expect(find.byType(MarketScreen), findsOneWidget);
      // One Back is all it takes to leave.
      c.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(find.byType(MarketScreen), findsNothing);
    });

    testWidgets('Check Out has a HOME button too', (tester) async {
      await _pumpMember(tester);
      await tester.tap(_inBar(find.text('Check Out')));
      await tester.pumpAndSettle();
      expect(find.byType(CartScreen), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    });

    testWidgets('Community has HOME and the welcome line, not a cut-off pin', (
      tester,
    ) async {
      await _pumpMember(tester);
      await tester.tap(_inBar(find.text('Community')));
      await tester.pumpAndSettle();
      expect(find.text("Welcome! What's on your mind?"), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);

      await tester.tap(find.byIcon(Icons.home_rounded).hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(FeedScreen).hitTestable(), findsOneWidget);
    });
  });

  group('advert buttons and colours', () {
    test('app: names a screen, and is never mistaken for a web address', () {
      final p = _promo(ctaLabel: 'Search', ctaUrl: 'app:search');
      expect(p.ctaScreen, PromoScreen.search);
      expect(p.ctaUri, isNull);
      expect(p.hasCta, isTrue);
      expect(_promo(ctaLabel: 'Go', ctaUrl: 'app:nowhere').hasCta, isFalse);
    });

    test('every screen has somewhere to go, from every tab', () {
      for (final screen in PromoScreen.values) {
        for (final prefix in ['/market', '/community', '/you']) {
          expect(promoScreenTarget(screen, prefix).path, startsWith('/'));
        }
      }
      expect(
        promoScreenTarget(PromoScreen.search, '/community').path,
        '/community/search',
      );
    });

    test('a colour is a brand colour, and the label always reads on it', () {
      expect(promoButtonTint(''), isNull);
      expect(promoButtonTint('red'), isNull);
      for (final color in PromoButtonColor.values) {
        final (bg, fg) = promoButtonTint(color.value)!;
        expect(LbmPalette.brand, contains(bg));
        expect([LbmPalette.navy, LbmPalette.white], contains(fg));
        expect(bg == fg, isFalse);
      }
      // White on orchid is 3:1, so orchid carries navy.
      expect(promoButtonTint('orchid')!.$2, LbmPalette.navy);
    });

    // Grace, 2026-10-28 (QA suite): hex codes for the button.
    test('a colour code works, and the words pick the side that reads', () {
      expect(promoButtonHex('#1A7F5A'), 0x1A7F5A);
      expect(promoButtonHex('fff'), 0xFFFFFF);
      expect(promoButtonHex('#12345'), isNull);
      expect(promoButtonHex('orchid'), isNull);
      final (darkFill, onDark) = promoButtonTint('#102030')!;
      expect(darkFill.toARGB32() & 0xFFFFFF, 0x102030);
      expect(onDark, LbmPalette.white);
      expect(promoButtonTint('#FFE680')!.$2, LbmPalette.navy);
    });

    test('anything with a photo is only its photo; without one, its words', () {
      expect(_promo(imageUrls: const ['a.jpg']).photoOnly, isTrue);
      expect(_promo().photoOnly, isFalse);
      expect(
        _promo(
          kind: PromoKind.announcement,
          imageUrls: const ['a.jpg'],
        ).photoOnly,
        // An announcement with a photo too (QA suite, 2026-10-28).
        isTrue,
      );
    });

    test('a photo advert needs no caption to be posted', () {
      const base = NewPromo(
        kind: PromoKind.ad,
        title: 'Holiday market',
        caption: '',
        audience: AnnouncementAudience.all,
      );
      expect(base.isValid, isFalse);
      const withPhoto = NewPromo(
        kind: PromoKind.ad,
        title: 'Holiday market',
        caption: '',
        audience: AnnouncementAudience.all,
        imageUrls: ['https://example.com/a.jpg'],
      );
      expect(withPhoto.isValid, isTrue);
    });

    testWidgets('the popup of a photo advert draws no title and no caption', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildLbmTheme(Brightness.light),
            home: PromoCard(
              promo: _promo(
                imageUrls: const ['https://example.com/a.jpg'],
                ctaLabel: 'Shop now',
                ctaUrl: 'app:search',
                ctaColor: 'orchid',
              ),
              onDismiss: () {},
              onCta: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Holiday market'), findsNothing);
      expect(find.text('Forty makers, one room.'), findsNothing);
      expect(find.text('SPONSORED'), findsNothing);
      final label = tester.widget<Text>(find.text('Shop now'));
      expect(label.style?.color, LbmPalette.navy);
      expect(
        tester.widget<PillButton>(find.byType(PillButton)).tint?.$1,
        LbmPalette.orchid,
      );
    });
  });

  testWidgets('the banner button has words on it in dark mode', (tester) async {
    // Grace, 2026-10-28: "Dark mode announcement buttons are not showing the
    // text". White words on a white pill.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLbmTheme(Brightness.dark),
          home: const Scaffold(
            body: SizedBox(
              height: HeroBanner.height,
              child: HeroCardPreview(title: 'Six new makers'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final label = tester.widget<Text>(find.text('Take a look'));
    expect(label.style?.color, LbmPalette.navy);
  });

  // From the QA suite, 2026-10-28.
  group('QA suite fixes', () {
    testWidgets('Search has a HOME button', (tester) async {
      await _pumpMember(tester);
      await tester.tap(find.text('DISCOVER. SHOP. SUPPORT.'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
      await tester.tap(find.byIcon(Icons.home_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsNothing);
    });

    test('the grid gets the next two store pages, the newest is above it', () {
      StorePage page(String id) => StorePage(
        id: id,
        url: 'https://littlebluemarket.com/pages/$id',
        title: id,
      );
      final items = assembleFeed(
        FeedInputs(storePages: [page('a'), page('b'), page('c'), page('d')]),
      );
      final pages = items.whereType<StorePageItem>().toList();
      // 'a' is the newest: it is drawn full width above the grid, by the
      // feed screen, so it is not in the grid as well.
      expect(pages.map((i) => i.page.id), ['b', 'c']);
      // Only under All: a filter for products is a filter for products.
      final products = assembleFeed(
        FeedInputs(
          storePages: [page('a'), page('b')],
          filter: FeedFilter.product,
        ),
      );
      expect(products.whereType<StorePageItem>(), isEmpty);
    });

    testWidgets('a store page card fits a narrow column', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLbmTheme(Brightness.light),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 170,
                child: StorePagePin(
                  item: StorePageItem(
                    StorePage(
                      id: 'p',
                      url:
                          'https://littlebluemarket.com/pages/holiday-gift-guide',
                      title: 'Holiday gift guide for everyone on your list',
                      blurb:
                          'Forty makers, one guide, and something for the '
                          'person who has everything.',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('LITTLE BLUE MARKET'), findsOneWidget);
    });
  });

  group('store pages open on the app\'s own screen', () {
    // Grace, 2026-10-28 (QA suite): "When posted should go to the top of the
    // feed. I wanted the pages to be posted and able to be opened natively
    // in the app".
    const about = StorePage(
      id: 'about1',
      url: 'https://littlebluemarket.com/pages/about',
      title: 'About',
      blurb: 'A curated marketplace for conscious shoppers.',
      blocks: [
        PageBlock(kind: PageBlockKind.heading, text: 'Our Mission'),
        PageBlock(
          kind: PageBlockKind.text,
          text: 'Little Blue Market exists to empower conscious shoppers.',
        ),
        PageBlock(kind: PageBlockKind.bullet, text: 'Support makers'),
        PageBlock(
          kind: PageBlockKind.button,
          text: 'Shop Personalized Gifts',
          url: 'https://littlebluemarket.com/collections/custom-gifts',
        ),
      ],
    );

    testWidgets('the newest is first under the banner and opens natively', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        retry: lbmRetry,
        overrides: [
          storePagesProvider.overrideWith((ref) => Stream.value([about])),
        ],
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

      final top = find.byWidgetPredicate(
        (w) => w is StorePagePin && w.wide && w.item.page.id == 'about1',
      );
      expect(top, findsOneWidget);
      // Above the grid, so the grid does not carry it as well.
      expect(find.byType(StorePagePin), findsOneWidget);

      await tester.tap(top);
      await tester.pumpAndSettle();
      expect(find.byType(StorePageScreen), findsOneWidget);
      expect(find.text('Our Mission'), findsOneWidget);
      expect(find.text('Support makers'), findsOneWidget);
      expect(find.text('Shop Personalized Gifts'), findsOneWidget);
      expect(find.text('See it on littlebluemarket.com'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the page screen draws in dark mode without overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storePagesProvider.overrideWith((ref) => Stream.value([about])),
          ],
          child: MaterialApp.router(
            theme: buildLbmTheme(Brightness.dark),
            routerConfig: _pageRouter('about1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Little Blue Market exists to empower conscious shoppers.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a page taken down says so', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storePagesProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: MaterialApp.router(
            theme: buildLbmTheme(Brightness.light),
            routerConfig: _pageRouter('gone'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('This page is no longer posted'), findsOneWidget);
    });

    test(
      'the blocks are read, and a kind the app does not know is skipped',
      () {
        final page = FirestoreMappers.storePage('p', {
          'url': 'https://littlebluemarket.com/pages/about',
          'title': 'About',
          'blocks': [
            {
              'kind': 'heading',
              'text': 'Our Vision',
              'link': 'https://x.test/a',
            },
            {'kind': 'image', 'url': 'https://littlebluemarket.com/cdn/a.jpg'},
            {'kind': 'button', 'label': 'Apply', 'url': 'https://x.test/b'},
            {'kind': 'carousel', 'text': 'from a newer backend'},
            'not a block',
          ],
        });
        expect(page.blocks.map((b) => b.kind), [
          PageBlockKind.heading,
          PageBlockKind.image,
          PageBlockKind.button,
        ]);
        expect(page.blocks[0].link, 'https://x.test/a');
        expect(page.blocks[2].text, 'Apply');
        expect(page.readsInApp, isTrue);
        // Posted before pages were read: opens as the web page.
        expect(
          FirestoreMappers.storePage('q', {'url': 'u'}).readsInApp,
          isFalse,
        );
      },
    );

    test('links on a page go to the app\'s own screens where it has one', () {
      expect(
        storePageLinkTarget(
          'https://littlebluemarket.com/collections/for-the-host',
        ),
        (kind: StoreLinkKind.collection, value: 'for-the-host'),
      );
      expect(
        storePageLinkTarget(
          'https://littlebluemarket.com/pages/about',
          posted: const [about],
        ),
        (kind: StoreLinkKind.page, value: 'about1'),
      );
      // Not posted, a product, or another site: the in-app browser.
      for (final url in [
        'https://littlebluemarket.com/pages/sell-with-us',
        'https://littlebluemarket.com/products/mug',
        'https://littlebluemarket.com/collections/all',
        'https://example.com/collections/x',
      ]) {
        expect(
          storePageLinkTarget(url, posted: const [about]).kind,
          StoreLinkKind.web,
        );
      }
    });
  });
}
