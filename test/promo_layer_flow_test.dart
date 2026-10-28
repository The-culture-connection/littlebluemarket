import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/state/promos.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/promo_popup.dart';

void main() {
  setUp(() => PromoLayer.runUnderTest = true);
  tearDown(() => PromoLayer.runUnderTest = false);

  testWidgets('a live promo fades in on its own, with the real timers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/market',
      routes: [GoRoute(path: '/market', builder: (_, _) => const Scaffold())],
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: lbmRetry,
        child: MaterialApp.router(
          theme: buildLbmTheme(Brightness.light),
          routerConfig: router,
          builder: (context, child) =>
              PromoLayer(router: router, child: child!),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PromoCard), findsNothing);
    await tester.pump(PromoLayer.delay);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(PromoCard), findsOneWidget);
    // Let it go so no timer is left pending.
    await tester.pump(PromoLayer.dwell);
    await tester.pumpAndSettle();
  });

  testWidgets('in the whole app, a signed-in member is shown one', (
    tester,
  ) async {
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
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(PromoCard), findsOneWidget);
    await tester.pump(PromoLayer.dwell);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  });

  // Grace, 2026-10-28: "Allow to click on announcements to show pop up
  // version and slide through images".
  testWidgets('one tapped on the banner opens at once and stays put', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(retry: lbmRetry);
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).signIn();
    // This opening's turn already taken, so only the tap can show one.
    container.read(promoTurnTakenProvider.notifier).take();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LittleBlueMarketApp(),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(PromoCard), findsNothing);

    const promo = Promo(
      id: 'tapped',
      kind: PromoKind.announcement,
      title: 'Six new makers',
      caption: 'Say hello.',
      audience: AnnouncementAudience.all,
    );
    container.read(promoOpenedProvider.notifier).open(promo);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(PromoCard), findsOneWidget);
    expect(container.read(promosSeenProvider), contains('tapped'));

    // Well past the twelve seconds an unasked popup gets.
    await tester.pump(PromoLayer.dwell + const Duration(seconds: 3));
    expect(find.byType(PromoCard), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(PromoCard),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(PromoCard), findsNothing);
    expect(container.read(promoOpenedProvider), isNull);
  });
}
