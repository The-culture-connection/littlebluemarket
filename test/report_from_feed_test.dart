import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';

/// The "…" on a feed card was an empty callback until Stage 17 (CP-17A).
/// These tests are the reason it cannot quietly become one again.
Future<ProviderContainer> _pumpFeed(
  WidgetTester tester, {
  required bool guest,
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
  if (!guest) {
    container.read(sessionProvider.notifier).signIn();
    await tester.pumpAndSettle();
  }
  return container;
}

Future<void> _tapFirstDots(WidgetTester tester) async {
  final dots = find.byIcon(Icons.more_horiz_rounded).first;
  await tester.ensureVisible(dots);
  await tester.pumpAndSettle();
  await tester.tap(dots);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the three dots on a feed post open the report sheet', (
    tester,
  ) async {
    await _pumpFeed(tester, guest: false);
    await _tapFirstDots(tester);

    expect(find.text('Report this post'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('Report opens the reasons and a send button', (tester) async {
    await _pumpFeed(tester, guest: false);
    await _tapFirstDots(tester);
    await tester.tap(find.text('Report this post'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Only Little Blue Market sees this'), findsOneWidget);
    expect(find.text('Send report'), findsOneWidget);
  });

  testWidgets('a guest is asked to make a profile before reporting', (
    tester,
  ) async {
    await _pumpFeed(tester, guest: true);
    await _tapFirstDots(tester);
    expect(find.text('Report this post'), findsOneWidget);

    await tester.tap(find.text('Report this post'));
    await tester.pumpAndSettle();

    // requireProfile stands between the tap and the report, so the reasons
    // never appear for someone with no account.
    expect(find.text('Send report'), findsNothing);
  });
}
