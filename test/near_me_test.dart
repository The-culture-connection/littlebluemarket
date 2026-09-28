import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/widgets/primitives.dart';

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

/// Opens the search screen from the Market's search pill.
Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.text('Search goods, services, #tags'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the feed tab turns it on and shows the grid', (tester) async {
    final container = await _pumpApp(tester);
    expect(container.read(searchFiltersProvider).nearMe, isFalse);

    await tester.tap(find.text('Near me'));
    await tester.pumpAndSettle();

    expect(container.read(searchFiltersProvider).nearMe, isTrue);
    expect(_nearMeHeading, findsOneWidget);
  });

  testWidgets('on the search screen it is a toggle, and it stays put', (
    tester,
  ) async {
    // Grace, 2026-09-28: "there should be a near me toggle for the search".
    // It used to be a way into the feed's Near me tab, which left the screen
    // you were searching on and never narrowed a search at all.
    final container = await _pumpApp(tester);
    await _openSearch(tester);

    await tester.tap(find.byType(NearMeButton));
    await tester.pumpAndSettle();

    expect(container.read(searchFiltersProvider).nearMe, isTrue);
    // Still on the search screen, with the field still open.
    expect(find.byType(NearMeButton), findsOneWidget);
    expect(_nearMeHeading, findsNothing, reason: 'it did not go to the feed');
    // And it says what "near" now means, so a narrowed search is not a
    // silent one.
    expect(find.textContaining('Searching within'), findsOneWidget);
  });

  testWidgets('a search run with it on is constrained to the radius', (
    tester,
  ) async {
    // The whole point of the toggle: the results are the nearby ones.
    // #WomanOwned is carried by listings in Detroit and by Holler's hat in
    // Nashville, so at twenty miles from Detroit the hat drops out.
    final container = await _pumpApp(tester);
    await _openSearch(tester);
    await tester.tap(find.byType(NearMeButton));
    await tester.pumpAndSettle();

    final filters = container.read(searchFiltersProvider);
    expect(filters.isGeoConstrained, isTrue);

    final search = container.read(searchRepositoryProvider);
    final near = await search.search(filters.copyWith(query: '#WomanOwned'));
    final everywhere = await search.search(
      filters.copyWith(query: '#WomanOwned', nearMe: false),
    );

    expect(everywhere.products.map((p) => p.id), contains('p3'));
    expect(
      near.products.map((p) => p.id),
      isNot(contains('p3')),
      reason: 'the Nashville listing is not within 20 miles of Detroit',
    );
    expect(near.products, isNotEmpty, reason: 'it narrowed to nothing');
    // A listing with no coordinates is left out of a radius search rather
    // than silently swept in.
    for (final product in near.products) {
      expect(product.lat, isNotNull);
    }
  });

  testWidgets('the turned-on search screen survives 2.0 text', (tester) async {
    // The line and the radius chips only exist while Near me is on, so the
    // smoke and text-scaling sweeps never draw them. Overflow throws.
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpApp(tester);
    await _openSearch(tester);
    await tester.tap(find.byType(NearMeButton));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('widening the radius widens the search', (tester) async {
    final container = await _pumpApp(tester);
    await _openSearch(tester);
    await tester.tap(find.byType(NearMeButton));
    await tester.pumpAndSettle();

    // The chips only exist while it is on, which is the point of showing
    // them there: a search stuck at twenty miles with no way to widen it
    // from the screen you are on reads as "search is broken".
    expect(find.text('50 mi'), findsOneWidget);
    await tester.tap(find.text('50 mi'));
    await tester.pumpAndSettle();

    expect(container.read(searchFiltersProvider).radiusMiles, 50);
    expect(find.textContaining('Searching within 50 mi'), findsOneWidget);
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
