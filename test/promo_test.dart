import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/state/promos.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/promo_popup.dart';

Promo _promo({
  PromoKind kind = PromoKind.ad,
  String ctaLabel = 'Shop the sale',
  String ctaUrl = 'https://littlebluecart.com',
  AnnouncementAudience audience = AnnouncementAudience.all,
  bool active = true,
  DateTime? startsAt,
  DateTime? endsAt,
  List<String> imageUrls = const [],
}) => Promo(
  id: 'p1',
  kind: kind,
  title: 'Holiday market, December 14',
  caption: 'Forty makers, one room, all day.',
  audience: audience,
  ctaLabel: ctaLabel,
  ctaUrl: ctaUrl,
  active: active,
  startsAt: startsAt,
  endsAt: endsAt,
  imageUrls: imageUrls,
);

Future<void> _pumpCard(
  WidgetTester tester,
  Promo promo, {
  VoidCallback? onDismiss,
  VoidCallback? onCta,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLbmTheme(Brightness.light),
      // Deliberately no Scaffold: the popup is mounted in the MaterialApp
      // builder, so it has no Material above it and must bring its own.
      home: PromoCard(
        promo: promo,
        onDismiss: onDismiss ?? () {},
        onCta: onCta ?? () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the model decides what is live and who sees it', () {
    final now = DateTime(2026, 9, 14, 12);

    test('a paused promo is never live', () {
      expect(_promo(active: false).isLiveAt(now), isFalse);
      expect(_promo().isLiveAt(now), isTrue);
    });

    test('a window is inclusive at the start and exclusive at the end', () {
      final promo = _promo(
        startsAt: DateTime(2026, 9, 14, 12),
        endsAt: DateTime(2026, 9, 20),
      );
      expect(promo.isLiveAt(now), isTrue);
      expect(promo.isLiveAt(now.subtract(const Duration(minutes: 1))), isFalse);
      expect(promo.isLiveAt(DateTime(2026, 9, 20)), isFalse);
      expect(
        promo.isLiveAt(DateTime(2026, 9, 19, 23, 59)),
        isTrue,
      );
    });

    test('one-sided windows and no window at all', () {
      expect(_promo(endsAt: DateTime(2026, 9, 20)).isLiveAt(now), isTrue);
      expect(_promo(startsAt: DateTime(2026, 9, 20)).isLiveAt(now), isFalse);
      expect(_promo().isLiveAt(now), isTrue);
    });

    test('the audience is the announcement audience, reused', () {
      final sellers = _promo(audience: AnnouncementAudience.sellers);
      expect(sellers.showsTo(isSeller: true, directoryLinked: false), isTrue);
      expect(sellers.showsTo(isSeller: false, directoryLinked: true), isFalse);

      final directory = _promo(audience: AnnouncementAudience.directory);
      expect(directory.showsTo(isSeller: false, directoryLinked: true), isTrue);
      expect(directory.showsTo(isSeller: true, directoryLinked: false), isFalse);

      final all = _promo();
      expect(all.showsTo(isSeller: false, directoryLinked: false), isTrue);
    });

    test('a link with no scheme still opens, and rubbish does not', () {
      expect(
        _promo(ctaUrl: 'littlebluecart.com').ctaUri.toString(),
        'https://littlebluecart.com',
      );
      expect(_promo(ctaUrl: '   ').ctaUri, isNull);
      expect(_promo(ctaUrl: 'https://').ctaUri, isNull);
      // No words on the button means no button, however good the link is.
      expect(_promo(ctaLabel: '').hasCta, isFalse);
      expect(_promo(ctaUrl: '').hasCta, isFalse);
      expect(_promo().hasCta, isTrue);
    });
  });

  group('the card', () {
    testWidgets('shows the words, the button and a way out', (tester) async {
      await _pumpCard(tester, _promo());
      expect(find.text('Holiday market, December 14'), findsOneWidget);
      expect(find.text('Forty makers, one room, all day.'), findsOneWidget);
      expect(find.text('Shop the sale'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('an advert says so, and an announcement says who it is from', (
      tester,
    ) async {
      await _pumpCard(tester, _promo());
      expect(find.text('SPONSORED'), findsOneWidget);

      await _pumpCard(tester, _promo(kind: PromoKind.announcement));
      expect(find.text('FROM LITTLE BLUE MARKET'), findsOneWidget);
      expect(find.text('SPONSORED'), findsNothing);
    });

    testWidgets('the X dismisses and the button reports a tap', (tester) async {
      var dismissed = 0;
      var tapped = 0;
      await _pumpCard(
        tester,
        _promo(),
        onDismiss: () => dismissed++,
        onCta: () => tapped++,
      );

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(dismissed, 1);
      expect(tapped, 0);

      await tester.tap(find.text('Shop the sale'));
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });

    testWidgets('no button at all when there is no link', (tester) async {
      await _pumpCard(tester, _promo(ctaLabel: '', ctaUrl: ''));
      expect(find.text('Shop the sale'), findsNothing);
      expect(find.text('Holiday market, December 14'), findsOneWidget);
      // The way out is still there, which is the point.
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('the card brings its own Material', (tester) async {
      // Flutter marks Text with no Material ancestor by underlining it in
      // gold. Grace saw that under the title, the caption and the button
      // (2026-09-14) because the redesign swapped LbmCard, which has a
      // Material, for a bare DecoratedBox.
      await _pumpCard(tester, _promo());
      expect(
        find.ancestor(
          of: find.text('Holiday market, December 14'),
          matching: find.byType(Material),
        ),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('it all fits: nothing to scroll', (tester) async {
      // Grace: "everything should fit in the modal at first glance no
      // scroll view". The picture takes the room the words leave.
      await _pumpCard(tester, _promo(imageUrls: const ['https://x.test/a.png']));
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('a flick downwards pushes it away', (tester) async {
      var dismissed = 0;
      await _pumpCard(tester, _promo(), onDismiss: () => dismissed++);
      await tester.fling(
        find.text('Holiday market, December 14'),
        const Offset(0, 300),
        1200,
      );
      await tester.pumpAndSettle();
      expect(dismissed, 1);
    });
  });

  group('the Diagnostics controls (Grace, 2026-09-14)', () {
    ProviderContainer container() {
      final c = ProviderContainer(retry: lbmRetry);
      addTearDown(c.dispose);
      return c;
    }

    test('an override is what jumps the queue, and clears itself', () {
      final c = container();
      expect(c.read(promoOverrideProvider), isNull);

      final promo = _promo();
      c.read(promoOverrideProvider.notifier).show(promo);
      expect(c.read(promoOverrideProvider)?.id, promo.id);

      c.read(promoOverrideProvider.notifier).clear();
      expect(c.read(promoOverrideProvider), isNull);
    });

    test('forgetting what was seen lets the normal flow offer it again', () async {
      final c = container();
      final seen = c.read(promosSeenProvider.notifier);
      await seen.markSeen('promo_demo_ad');
      expect(seen.seen('promo_demo_ad'), isTrue);

      await seen.forget();
      expect(c.read(promosSeenProvider), isEmpty);
      expect(seen.seen('promo_demo_ad'), isFalse);
    });

    test("releasing the turn undoes one-per-opening without a restart", () {
      final c = container();
      expect(c.read(promoTurnTakenProvider), isFalse);

      c.read(promoTurnTakenProvider.notifier).take();
      expect(c.read(promoTurnTakenProvider), isTrue);
      // With the turn taken, the normal flow offers nothing at all.
      expect(c.read(promoForThisLaunchProvider).value, isNull);

      c.read(promoTurnTakenProvider.notifier).release();
      expect(c.read(promoTurnTakenProvider), isFalse);
    });

    test('every live promo is listed, whoever it is aimed at', () async {
      final c = container();
      final all = await c.read(allPromosProvider.future);
      // The demo data has one advert and one announcement.
      expect(all.length, greaterThanOrEqualTo(2));
      expect(all.map((p) => p.kind), contains(PromoKind.ad));
      expect(all.map((p) => p.kind), contains(PromoKind.announcement));
    });
  });
}
