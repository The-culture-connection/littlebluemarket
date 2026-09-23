import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/state/tips.dart';
import 'package:little_blue_market/state/tour.dart';
import 'package:little_blue_market/widgets/first_tour.dart';

/// The disclaimer that follows the tour, by Done or by Skip (Stage 17).
const _disclaimer = 'Keeping Little Blue Cart alive';

Future<ProviderContainer> _pumpSignedIn(WidgetTester tester) async {
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
  container.read(sessionProvider.notifier).signIn();
  await tester.pumpAndSettle();
  return container;
}

/// Dismisses the disclaimer and checks it said what it is meant to say.
Future<void> _acknowledge(WidgetTester tester) async {
  expect(find.text(_disclaimer), findsOneWidget);
  expect(
    find.textContaining('keep transactions inside the platform'),
    findsOneWidget,
  );
  expect(
    find.textContaining('Little Blue Cart link to the bio'),
    findsOneWidget,
  );
  await tester.tap(find.text('I understand'));
  await tester.pumpAndSettle();
  expect(find.text(_disclaimer), findsNothing);
}

void main() {
  testWidgets('the tour shows once when requested, pages through, and is remembered', (
    tester,
  ) async {
    final container = await _pumpSignedIn(tester);
    expect(find.text(kTourPages.first.title), findsNothing);

    container.read(tourPendingProvider.notifier).request();
    await tester.pumpAndSettle();
    expect(find.text(kTourPages.first.title), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    for (var i = 1; i < kTourPages.length; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text(kTourPages[i].title), findsOneWidget);
    }
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text(kTourPages.last.title), findsNothing);
    // Stage 17: the platform's ask follows the tour, and the phone only
    // remembers the pair once the ask has been acknowledged.
    await _acknowledge(tester);
    expect(container.read(tipsProvider).contains(Tips.firstTour), isTrue);
    expect(container.read(tourPendingProvider), isFalse);
  });

  testWidgets('Skip closes it on the first page, and the ask still follows', (
    tester,
  ) async {
    final container = await _pumpSignedIn(tester);
    container.read(tourPendingProvider.notifier).request();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text(kTourPages.first.title), findsNothing);
    await _acknowledge(tester);
    expect(container.read(tipsProvider).contains(Tips.firstTour), isTrue);
  });

  testWidgets('the disclaimer cannot be dismissed by tapping outside', (
    tester,
  ) async {
    final container = await _pumpSignedIn(tester);
    container.read(tourPendingProvider.notifier).request();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text(_disclaimer), findsOneWidget);

    // The barrier is the whole screen; a tap near the top edge lands on it.
    await tester.tapAt(const Offset(195, 8));
    await tester.pumpAndSettle();
    expect(find.text(_disclaimer), findsOneWidget);
    expect(container.read(tipsProvider).contains(Tips.firstTour), isFalse);

    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    expect(find.text(_disclaimer), findsNothing);
  });

  testWidgets('the floating cart is on the feed and opens the cart', (
    tester,
  ) async {
    await _pumpSignedIn(tester);
    expect(find.bySemanticsLabel('Your cart'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.shopping_bag_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Your cart'), findsWidgets);
    // And it takes itself off the cart screen rather than floating over it.
    expect(find.byIcon(Icons.shopping_bag_rounded), findsNothing);
  });

  testWidgets('the floating cart stays off the welcome screen', (tester) async {
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
    expect(find.byIcon(Icons.shopping_bag_rounded), findsNothing);
  });
}
