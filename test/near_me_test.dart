import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';

/// Near me, asked from both places that ask it.
///
/// Grace, 2026-09-28: "near me search is not working". It was the tab: the
/// feed held which one was showing in its own `setState` field, so the row on
/// the search screen could turn the filter on, send you to the Market, and
/// leave you looking at For you with nothing changed. The tab is derived from
/// the filter now, which is the only arrangement where the two cannot
/// disagree.
Future<ProviderContainer> _pumpApp(WidgetTester tester) =>
    _pump(tester, signedIn: true);

/// The same, stopped at the guest step: nobody with a city on file.
Future<ProviderContainer> _pumpGuest(WidgetTester tester) =>
    _pump(tester, signedIn: false);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool signedIn,
}) async {
  tester.view.physicalSize = const Size(390, 900);
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
  if (signedIn) {
    container.read(sessionProvider.notifier).signIn();
    await tester.pumpAndSettle();
  }
  return container;
}

/// What the Near me grid says above its results, and nothing else does.
final _nearMeHeading = find.textContaining('Within ');

void main() {
  testWidgets('the feed tab turns it on and shows the grid', (tester) async {
    final container = await _pumpApp(tester);
    expect(container.read(searchFiltersProvider).nearMe, isFalse);

    await tester.tap(find.text('Near me'));
    await tester.pumpAndSettle();

    expect(container.read(searchFiltersProvider).nearMe, isTrue);
    expect(_nearMeHeading, findsOneWidget);
  });

  testWidgets('the row on the search screen lands on the same grid', (
    tester,
  ) async {
    // The bug Grace reported: this turned the filter on and then went to the
    // Market, where the tab had not moved and the For you feed was still
    // showing. The filter being true was never the thing anybody could see.
    final container = await _pumpApp(tester);
    await tester.tap(find.text('Search goods, services, #tags'));
    await tester.pumpAndSettle();

    final row = find.text('Makers and listings close to you');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(container.read(searchFiltersProvider).nearMe, isTrue);
    expect(
      _nearMeHeading,
      findsOneWidget,
      reason: 'the search screen turned it on but the feed never showed it',
    );
    // And it is the Market it lands on, not the search screen it left.
    expect(find.text('Search goods, services, #tags'), findsOneWidget);
  });

  testWidgets('turning it off anywhere puts the feed back on For you', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    await tester.tap(find.text('Near me'));
    await tester.pumpAndSettle();
    expect(_nearMeHeading, findsOneWidget);

    await tester.tap(find.text('For you'));
    await tester.pumpAndSettle();

    expect(container.read(searchFiltersProvider).nearMe, isFalse);
    expect(_nearMeHeading, findsNothing);
  });

  testWidgets('with nowhere to measure from it says so and stays off', (
    tester,
  ) async {
    // A guest: no profile, so no city, and under test there is no device
    // location either. The tab must not move — an empty Near me grid
    // explains nothing, and "add your city" is the only thing that gets
    // anybody out of it.
    final container = await _pumpGuest(tester);

    await tester.tap(find.text('Near me'));
    await tester.pumpAndSettle();

    expect(container.read(searchFiltersProvider).nearMe, isFalse);
    expect(_nearMeHeading, findsNothing);
    expect(find.textContaining('Near me needs a place'), findsOneWidget);
  });
}
