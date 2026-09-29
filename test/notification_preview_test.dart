import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/notifications_ui.dart';
import 'package:little_blue_market/state/promos.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';

/// Diagnostics -> Notification preview: each button puts up what the real
/// event would, on this phone, now. Checked on the fixture app, at night,
/// because a preview must not be hidden by quiet hours.

Future<ProviderContainer> _diagnostics(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    retry: lbmRetry,
    // 10:30 pm: inside the default quiet hours on purpose.
    overrides: [
      nowProvider.overrideWithValue(() => DateTime(2026, 9, 28, 22, 30)),
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
  await tester.pump();
  // The feed first, so the previews that point at a pin have one to find.
  container.read(routerProvider).go('/market');
  await tester.pumpAndSettle();
  container.read(routerProvider).go('/you/diagnostics');
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, String row) async {
  await tester.scrollUntilVisible(
    find.text(row),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.text(row));
  await tester.pumpAndSettle();
  await tester.tap(find.text(row));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

Future<void> _letItGo(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('DM: the banner with Reply, even in quiet hours', (tester) async {
    await _diagnostics(tester);
    await _tap(tester, 'Direct message');
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Kali Brooks'), findsOneWidget);
    await _letItGo(tester);
  });

  testWidgets('mention: the toast, and the bell is set to ring', (
    tester,
  ) async {
    final c = await _diagnostics(tester);
    await _tap(tester, 'Mention');
    expect(find.text('Ama Mensah mentioned you'), findsOneWidget);
    expect(c.read(notificationsUiProvider).bellRingPending, isTrue);
    await _letItGo(tester);
  });

  // The popup layer stands itself down under widget tests (its timers would
  // hold every test open), so what is checked here is that the preview hands
  // it this announcement through the same override "Show it now" uses, and
  // sets the bell to ring. The popup itself is seen on a phone.
  testWidgets(
    'announcement: the popup is asked for, and the bell set to ring',
    (tester) async {
      final c = await _diagnostics(tester);
      await _tap(tester, 'Announcement');
      final forced = c.read(promoOverrideProvider);
      expect(forced?.title, 'Town hall tonight at 7');
      expect(forced?.kind, PromoKind.announcement);
      expect(c.read(notificationsUiProvider).bellRingPending, isTrue);
    },
  );

  testWidgets('after quiet hours: the waiting strip', (tester) async {
    await _diagnostics(tester);
    await _tap(tester, 'After quiet hours');
    expect(find.text('Quiet hours · 3 waiting'), findsOneWidget);
    await _letItGo(tester);
  });

  testWidgets('forum reply: "1 new" on a thread pin, and the Community dot', (
    tester,
  ) async {
    final c = await _diagnostics(tester);
    await _tap(tester, 'Forum reply');
    final ui = c.read(notificationsUiProvider);
    expect(ui.communityDot, isTrue);
    expect(ui.threadNew.values, contains(1));

    c.read(routerProvider).go('/market');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('1 new'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('1 new'), findsOneWidget);
  });
}
