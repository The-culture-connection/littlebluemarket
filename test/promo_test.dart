import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';
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
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: PromoCard(
            promo: promo,
            onDismiss: onDismiss ?? () {},
            onCta: onCta ?? () {},
          ),
        ),
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
}
