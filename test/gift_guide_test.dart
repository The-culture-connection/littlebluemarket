import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/router/nav.dart';
import 'package:little_blue_market/screens/market/gift_guide_screen.dart';
import 'package:little_blue_market/screens/market/market_screen.dart';
import 'package:little_blue_market/screens/market/market_shelves.dart';
import 'package:little_blue_market/screens/market/vendors_screen.dart';
import 'package:little_blue_market/screens/market/collection_screen.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';

/// Grace, 2026-11-16: the Holiday Gift Guide in the app, browse by vendor,
/// a livelier Market, the ownership collections in search, and categories
/// in one sliding row.

Future<ProviderContainer> _pump(WidgetTester tester, String path) async {
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
  container.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return container;
}

/// The screen's own downward list, not one of the rows that slide.
Future<void> _scrollTo(WidgetTester tester, Finder target) =>
    tester.scrollUntilVisible(
      target,
      200,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );

Promo _promo(String link) => Promo(
  id: 'gg',
  kind: PromoKind.ad,
  title: 'Holiday Gift Guide',
  caption: '',
  audience: AnnouncementAudience.all,
  imageUrls: const ['https://example.com/cover.jpg'],
  ctaLabel: 'Shop the guide',
  ctaUrl: link,
);

void main() {
  group('the guide and the store agree', () {
    test('every collection the app opens by name is kept in sync', () {
      // functions/src/collections.ts re-reads these from the store, because
      // adding a product to a collection sends no webhook. A handle missing
      // there is a gift guide tile that slowly goes stale.
      final source = File('functions/src/collections.ts').readAsStringSync();
      final start = source.indexOf('CURATED_COLLECTIONS = [');
      final end = source.indexOf('] as const', start);
      final synced = RegExp(
        "'([^']+)'",
      ).allMatches(source.substring(start, end)).map((m) => m.group(1)).toSet();
      for (final handle in [...kGiftGuide.handles, ...kMarketShelves]) {
        expect(synced, contains(handle), reason: handle);
      }
    });

    test('every tile has a name, a handle and an address of its own', () {
      final ids = <String>{};
      for (final section in kGiftGuide.sections) {
        expect(section.entries, isNotEmpty, reason: section.title);
        for (final entry in section.entries) {
          expect(entry.title.trim(), isNotEmpty);
          expect(entry.handles, isNotEmpty, reason: entry.title);
          expect(ids.add(entry.id), isTrue, reason: 'two tiles ${entry.id}');
          expect(kGiftGuide.entry(entry.id), same(entry));
        }
      }
      expect(kGiftGuide.handles.toSet().length, kGiftGuide.handles.length);
    });

    test('the advert screens match the backend and the admin website', () {
      final backend = File('functions/src/promos.ts').readAsStringSync();
      final admin = File('admin-web/public/index.html').readAsStringSync();
      for (final screen in PromoScreen.values) {
        expect(backend, contains("'${screen.value}'"), reason: screen.value);
        expect(admin, contains('value="${screen.value}"'), reason: screen.value);
      }
    });
  });

  group('a link to the website opens the app', () {
    test('the gift guide, whatever is stuck on the end of it', () {
      expect(
        storeLinkInApp(
          Uri.parse(
            'https://littlebluemarket.com/pages/holiday-gift-guide'
            '?_su_rec=abc&_su_rec_id=b0a0',
          ),
        ),
        '/gift-guide',
      );
      expect(
        storeLinkInApp(
          Uri.parse('https://www.littlebluemarket.com/pages/holiday-gift-guide/'),
        ),
        '/gift-guide',
      );
    });

    test('a collection opens the collection; anything else stays the web', () {
      expect(
        storeLinkInApp(
          Uri.parse('https://littlebluemarket.com/collections/for-the-host'),
        ),
        '/collection/for-the-host',
      );
      expect(
        storeLinkInApp(Uri.parse('https://littlebluemarket.com/collections/all')),
        isNull,
      );
      expect(
        storeLinkInApp(Uri.parse('https://littlebluemarket.com/pages/about')),
        isNull,
      );
      expect(
        storeLinkInApp(Uri.parse('https://example.com/pages/holiday-gift-guide')),
        isNull,
      );
    });

    test('an advert knows when it is the gift guide', () {
      final web = _promo(
        'littlebluemarket.com/pages/holiday-gift-guide?_su_rec=x',
      );
      expect(web.ctaAppPath, '/gift-guide');
      expect(web.opensGiftGuide, isTrue);
      expect(web.hasCta, isTrue);

      final app = _promo('app:gift-guide');
      expect(app.ctaScreen, PromoScreen.giftGuide);
      expect(app.opensGiftGuide, isTrue);

      expect(_promo('https://example.com').opensGiftGuide, isFalse);
      expect(_promo('app:vendors').ctaScreen, PromoScreen.vendors);
      expect(
        promoScreenTarget(PromoScreen.giftGuide, '/market').path,
        '/market/gift-guide',
      );
    });
  });

  group('searching for who runs it', () {
    test('the ways people type it find the shelf', () {
      expect(ownershipMatch('woman owned'), 'woman-owned');
      expect(ownershipMatch('Women-Owned'), 'woman-owned');
      expect(ownershipMatch('#WomanOwned'), 'woman-owned');
      expect(ownershipMatch('black owned'), 'bipoc-owned');
      expect(ownershipMatch('BIPOC'), 'bipoc-owned');
      expect(ownershipMatch('veteran'), 'veteran-military-spouse-owned');
      expect(ownershipMatch('LGBTQ+ owned'), 'lgbtq-owned');
      expect(ownershipMatch('disabled owned'), 'disabled-owned-employer');
    });

    test('and nothing else does', () {
      expect(ownershipMatch('candles'), isNull);
      expect(ownershipMatch('black mug'), isNull);
      expect(ownershipMatch('totally'), isNull);
      expect(ownershipMatch(''), isNull);
    });
  });

  group('vendors A to Z', () {
    Person p(String id, String name, {bool seller = true}) => Person(
      id: id,
      name: name,
      handle: '@$id',
      tint: 0xFF70A0D2,
      bio: '',
      tags: const [],
      grossSalesCents: 0,
      purchases: 0,
      posts: 0,
      isSeller: seller,
    );

    test('by name, The set aside, each shop once, buyers left out', () {
      final sorted = sortVendors([
        p('b', 'The Note House'),
        p('a', 'apple Tree'),
        p('c', 'Zinnia'),
        p('a', 'apple Tree'),
        p('d', 'Buyer', seller: false),
        p('e', '  '),
        p('f', '3 Sisters'),
      ]);
      expect(sorted.map((v) => v.name), [
        '3 Sisters',
        'apple Tree',
        'The Note House',
        'Zinnia',
      ]);
      expect(vendorLetter('The Note House'), 'N');
      expect(vendorLetter('3 Sisters'), '#');
      expect(filterVendors(sorted, 'note').single.id, 'b');
      expect(filterVendors(sorted, '@c').single.id, 'c');
      expect(filterVendors(sorted, ''), sorted);
    });
  });

  group('the Market screen', () {
    testWidgets('a shop window: the guide, then rows that slide', (
      tester,
    ) async {
      await _pump(tester, '/market/shop');
      expect(find.byType(MarketScreen), findsOneWidget);
      expect(find.byType(GiftGuideCover), findsOneWidget);
      expect(find.text('Shop by category'), findsOneWidget);
      expect(find.text('Apparel & Accessories'), findsOneWidget);

      // The categories are one row now, not a grid: same top for all.
      final tiles = find.descendant(
        of: find.byType(CollectionTiles),
        matching: find.byType(PhotoTile),
      );
      expect(tiles, findsNWidgets(3));
      final tops = {
        for (final e in tiles.evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dy,
      };
      expect(tops.length, 1);
      // Larger than the third of the width they used to be.
      expect(
        tester.getSize(tiles.first).width,
        CollectionTiles.tileSize,
      );

      await _scrollTo(tester, find.text('Shop by values'));
      expect(find.text('Woman Owned'), findsOneWidget);
      await _scrollTo(tester, find.text('New arrivals'));
      await _scrollTo(tester, find.text('Shop by vendor'));
      expect(find.byType(ShelfProductCard), findsWidgets);
    });

    testWidgets('the cover opens the guide, and a tile its collection', (
      tester,
    ) async {
      await _pump(tester, '/market/shop');
      await tester.tap(find.byType(GiftGuideCover));
      await tester.pumpAndSettle();
      expect(find.byType(GiftGuideScreen), findsOneWidget);

      // Only tiles whose collections the store has: the demo has For the
      // Host, not For the Book Lover.
      expect(find.text('For the Host'), findsOneWidget);
      expect(find.text('For the Book Lover'), findsNothing);

      await tester.tap(find.text('For the Host'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CollectionScreen>(find.byType(CollectionScreen)).handle,
        'for-the-host',
      );
    });

    testWidgets("a person's picks are their collections on one screen", (
      tester,
    ) async {
      await _pump(tester, '/market/gift-guide');
      await _scrollTo(tester, find.text("Sandee's Market Picks"));
      await tester.tap(find.text("Sandee's Market Picks"));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GiftGuideEntryScreen>(find.byType(GiftGuideEntryScreen))
            .entryId,
        'sandee',
      );
      // "Sandee's Picks - Home" reads as "Home" under her name.
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Wear'), findsOneWidget);
    });

    testWidgets('every shop, A to Z, and a box to narrow them', (tester) async {
      final container = await _pump(tester, '/market/vendors');
      expect(find.byType(VendorsScreen), findsOneWidget);
      final all = container.read(allVendorsProvider).value!;
      expect(all, isNotEmpty);
      expect(find.text(all.first.name), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzzz-nobody');
      await tester.pumpAndSettle();
      expect(find.text('No shop called "zzzz-nobody"'), findsOneWidget);

      await tester.enterText(find.byType(TextField), all.first.name);
      await tester.pumpAndSettle();
      await tester.tap(find.text(all.first.name).last);
      await tester.pumpAndSettle();
      expect(find.byType(VendorsScreen), findsNothing);
    });

    testWidgets('a search for "black owned" offers the shelf', (tester) async {
      await _pump(tester, '/market/results?q=black%20owned');
      expect(find.text('Shop everything BIPOC Owned'), findsOneWidget);
      await tester.tap(find.text('Shop everything BIPOC Owned'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CollectionScreen>(find.byType(CollectionScreen)).handle,
        'bipoc-owned',
      );
    });
  });
}
