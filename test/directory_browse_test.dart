import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/screens/market/directory_browse_screen.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';

/// Stage 17 (CP-17F): the whole littlebluecart.com directory, browsable by
/// category and searchable, with unclaimed listings offering to be claimed.
Future<ProviderContainer> _pumpFeed(
  WidgetTester tester, {
  bool guest = true,
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

/// Taps a chip on the directory rail, scrolling the rail itself to reach
/// it: the chips run off the side of a phone, and the page's own vertical
/// scrollable cannot bring a horizontal one into view.
Future<void> _openCategory(WidgetTester tester, String chip) async {
  await tester.ensureVisible(find.text('Browse the directory'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text(chip),
    80,
    scrollable: find.descendant(
      of: find.byType(DirectoryRail),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(chip));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the directory rail sits on the feed, next to the shop rail', (
    tester,
  ) async {
    await _pumpFeed(tester);
    expect(find.text('Browse the directory'), findsOneWidget);
    expect(find.text('littlebluecart.com'), findsOneWidget);
  });

  testWidgets('the rail is built from the categories the directory has', (
    tester,
  ) async {
    final container = await _pumpFeed(tester);
    final categories = await container.read(
      directoryCategoriesProvider.future,
    );
    final names = categories.map((c) => c.name).toSet();

    // The demo directory files businesses under these; the biggest category
    // sorts first, which is the order the rail draws them in.
    expect(names, contains('Home & Garden'));
    expect(names, contains('Bath, Beauty & Wellness'));
    expect(categories.first.count >= categories.last.count, isTrue);

    // The slug is the address, and it has to match what the backend writes.
    final home = categories.firstWhere((c) => c.name == 'Home & Garden');
    expect(home.slug, 'home-and-garden');
    expect(home.count, 2);
    expect(home.countLabel, '2 businesses');
  });

  testWidgets('a category shows its businesses, with a way to claim one', (
    tester,
  ) async {
    await _pumpFeed(tester);
    await _openCategory(tester, 'Home & Garden');

    // The screen is titled in the directory's own words.
    expect(find.text('Home & Garden'), findsWidgets);
    expect(find.text('Found House Ceramics'), findsOneWidget);
    expect(find.text('The Mend Shop'), findsOneWidget);

    // Nobody owns these yet, so each one offers to be claimed.
    expect(find.text('Is this your business?'), findsNWidgets(2));
    expect(find.text('Claim this listing'), findsNWidgets(2));
  });

  testWidgets('a claimed listing does not offer to be claimed', (
    tester,
  ) async {
    await _pumpFeed(tester);
    await _openCategory(tester, 'Travel');

    // Field Trips belongs to dee in the demo data.
    expect(find.text('Field Trips Travel & Vacations'), findsOneWidget);
    expect(find.text('Is this your business?'), findsNothing);
  });

  testWidgets('a guest tapping Claim is asked to make a profile first', (
    tester,
  ) async {
    await _pumpFeed(tester);
    await _openCategory(tester, 'Bath, Beauty & Wellness');
    expect(find.text('Cedar & Salt Bath Co.'), findsOneWidget);

    await tester.tap(find.text('Claim this listing'));
    await tester.pumpAndSettle();
    // requireProfile stands in the way; the directory screen is never reached.
    expect(find.text('Your directory listings'), findsNothing);
  });

  testWidgets('search finds a directory business by name and by city', (
    tester,
  ) async {
    final container = await _pumpFeed(tester);
    final repo = container.read(directoryRepositoryProvider);

    final byName = await repo.searchDirectory('found house');
    expect(byName.map((l) => l.title), contains('Found House Ceramics'));

    final byCity = await repo.searchDirectory('portland');
    expect(byCity.map((l) => l.title), contains('Cedar & Salt Bath Co.'));

    final byCategory = await repo.searchDirectory('bookkeeping');
    expect(byCategory.map((l) => l.title), contains('Brightside Bookkeeping'));

    expect(await repo.searchDirectory('   '), isEmpty);
    expect(await repo.searchDirectory('nothingmatchesthis'), isEmpty);
  });

  testWidgets('the search screen folds directory hits away at the bottom', (
    tester,
  ) async {
    await _pumpFeed(tester);
    await tester.tap(find.text('Search goods, services, #tags'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Found House');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // A business that sells on its own website is the answer of last
    // resort, so it is named and folded rather than laid out in full.
    expect(find.text('Also 1 business on littlebluecart.com'), findsOneWidget);
    expect(find.text('Found House Ceramics'), findsNothing);

    await tester.tap(find.text('Also 1 business on littlebluecart.com'));
    await tester.pumpAndSettle();
    expect(find.text('Found House Ceramics'), findsOneWidget);
  });

  test('a category with one business says so in the singular', () {
    const one = DirectoryCategory(slug: 'travel', name: 'Travel', count: 1);
    expect(one.countLabel, '1 business');
  });
}
