import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/screens/market/cart_screen.dart';
import 'package:little_blue_market/screens/market/feed_screen.dart';
import 'package:little_blue_market/screens/market/market_screen.dart';
import 'package:little_blue_market/router/nav.dart';
import 'package:little_blue_market/state/providers.dart';
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

Promo _promo({
  PromoKind kind = PromoKind.ad,
  List<String> imageUrls = const [],
  String ctaLabel = '',
  String ctaUrl = '',
  PromoButtonColor? ctaColor,
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
      expect(promoButtonTint(null), isNull);
      for (final color in PromoButtonColor.values) {
        final (bg, fg) = promoButtonTint(color)!;
        expect(LbmPalette.brand, contains(bg));
        expect([LbmPalette.navy, LbmPalette.white], contains(fg));
        expect(bg == fg, isFalse);
      }
      // White on orchid is 3:1, so orchid carries navy.
      expect(promoButtonTint(PromoButtonColor.orchid)!.$2, LbmPalette.navy);
    });

    test(
      'an advert with a photo is only its photo; without one, its words',
      () {
        expect(_promo(imageUrls: const ['a.jpg']).photoOnly, isTrue);
        expect(_promo().photoOnly, isFalse);
        expect(
          _promo(
            kind: PromoKind.announcement,
            imageUrls: const ['a.jpg'],
          ).photoOnly,
          isFalse,
        );
      },
    );

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
                ctaColor: PromoButtonColor.orchid,
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
}
