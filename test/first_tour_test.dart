import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/state/tips.dart';
import 'package:little_blue_market/state/tour.dart';
import 'package:little_blue_market/widgets/first_tour.dart';

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
    expect(container.read(tipsProvider).contains(Tips.firstTour), isTrue);
    expect(container.read(tourPendingProvider), isFalse);
  });

  testWidgets('Skip closes it on the first page', (tester) async {
    final container = await _pumpSignedIn(tester);
    container.read(tourPendingProvider.notifier).request();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text(kTourPages.first.title), findsNothing);
    expect(container.read(tipsProvider).contains(Tips.firstTour), isTrue);
  });

  testWidgets('the bug button is on the feed and opens the sheet', (
    tester,
  ) async {
    await _pumpSignedIn(tester);
    expect(
      find.bySemanticsLabel('Report a bug or send a critique'),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.bug_report_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Tell us what happened'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);

    // Sending needs words; then it lands in the store for the Admin screen.
    await tester.enterText(
      find.widgetWithText(TextField, 'What were you doing, and what went wrong?'),
      'The cart spins forever',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Tell us what happened'), findsNothing);
    expect(find.text('Sent. Thank you for telling us.'), findsOneWidget);
  });

  testWidgets('the bug button stays off the welcome screen', (tester) async {
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
    expect(find.byIcon(Icons.bug_report_outlined), findsNothing);
  });
}
