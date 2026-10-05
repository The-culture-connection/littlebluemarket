import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/repositories/funding_repository.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/funding.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';

/// The page that asks for money.
///
/// Two things are worth holding still here. The figures are read or they are
/// dashes — never invented, because a made-up bill on a page asking for
/// money earns the cynicism the page exists to answer. And the ask ends at
/// the store's checkout, which is what keeps it out of in-app purchase
/// territory rather than a claim in the copy.

/// A funding repository that answers with exactly what a test says.
class _StubFunding implements FundingRepository {
  _StubFunding(this._months);

  final Map<String, Funding?> _months;
  final asked = <String>[];

  @override
  Future<Funding?> month(String month) async {
    asked.add(month);
    return _months[month];
  }
}

String get _lastMonth =>
    Funding.previousMonthOf(Funding.monthOf(DateTime.now()));

Future<ProviderContainer> _pumpChipIn(
  WidgetTester tester, {
  FundingRepository? funding,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    retry: lbmRetry,
    overrides: [
      if (funding != null) fundingRepositoryProvider.overrideWithValue(funding),
    ],
  );
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
  container.read(sessionProvider.notifier).signIn();
  await tester.pumpAndSettle();
  container.read(routerProvider).go('/you/chip-in');
  await tester.pumpAndSettle();
  return container;
}

/// Scrolls the page until [target] is on it.
///
/// The page is a ListView and a ListView does not build what is off the
/// bottom, so `find.text` on the one-time card finds nothing at all until
/// the Monthly card above it has been scrolled past. Not a failure worth
/// asserting on: a phone scrolls too.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 140, maxScrolls: 20);
  }
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the bill comes from the funding document', (tester) async {
    final funding = _StubFunding({
      _lastMonth: Funding(
        month: _lastMonth,
        raisedCents: 41800,
        budgetCents: 62000,
        donors: 212,
        costs: const {
          'Hosting & push': 28400,
          'Directory sync': 19600,
          'Town halls': 14000,
        },
      ),
    });
    await _pumpChipIn(tester, funding: funding);

    // It asks for last month, not this one: this month's bill is not in yet.
    expect(funding.asked, contains(_lastMonth));

    expect(find.text("Last month's bill"), findsOneWidget);
    expect(find.text(r'$284'), findsOneWidget);
    expect(find.text('Hosting & push'), findsOneWidget);
    expect(find.textContaining('212 members'), findsOneWidget);
    expect(find.textContaining(r'$418 of $620'), findsOneWidget);
    expect(find.textContaining('No ads, no investors'), findsWidgets);
  });

  testWidgets('no document means dashes, not invented numbers', (tester) async {
    // The state a fresh project is in, and the one where the temptation to
    // put a plausible number on screen is strongest.
    await _pumpChipIn(tester, funding: _StubFunding({}));

    expect(find.text('—'), findsNWidgets(3));
    expect(find.textContaining('not published yet'), findsOneWidget);
    // Nothing that looks like a figure.
    expect(find.textContaining('members covered'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the amount chosen is the amount on the button', (tester) async {
    await _pumpChipIn(tester, funding: _StubFunding({}));

    // $5 is the one it opens on: the middle of the four, not the largest.
    await _scrollTo(tester, find.text(r'Chip in $5'));
    expect(find.text(r'Chip in $5'), findsOneWidget);

    await _scrollTo(tester, find.text(r'$20'));
    await tester.tap(find.text(r'$20').first);
    await tester.pumpAndSettle();
    expect(find.text(r'Chip in $20'), findsOneWidget);
  });

  testWidgets('chipping in opens the store checkout with that amount', (
    tester,
  ) async {
    final container = await _pumpChipIn(tester, funding: _StubFunding({}));

    await _scrollTo(tester, find.text(r'$10'));
    await tester.tap(find.text(r'$10').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'Chip in $10'));
    await tester.pumpAndSettle();

    // The checkout was asked for ten dollars, and it is the same hand-off
    // sheet buying something uses — which is the whole store-compliance
    // argument, so it is asserted rather than described.
    expect(container.read(fixtureStoreProvider).lastChipInCents, 1000);
    expect(find.text('Finish in checkout'), findsOneWidget);
  });

  testWidgets('the copy says what it is and what it is not', (tester) async {
    await _pumpChipIn(tester, funding: _StubFunding({}));

    // The membership is billed by the app store and the one-time amounts
    // are not, and the page has to say which is which: that distinction is
    // the whole reason one is a subscription and the other is a product.
    await _scrollTo(tester, find.textContaining('Billed by the app store'));
    expect(find.textContaining('until you cancel it'), findsOneWidget);

    await _scrollTo(
      tester,
      find.textContaining('same in-app checkout you buy with'),
    );
    expect(find.textContaining('Not tax-deductible'), findsWidgets);
    // Still no "coming soon" anywhere: a card that cannot be tapped is a
    // card that should not be drawn (Grace, 2026-09-29).
    expect(find.textContaining('coming'), findsNothing);
  });
}
