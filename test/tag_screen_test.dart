import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/state/tags.dart';
import 'package:little_blue_market/widgets/pins/product_pin.dart';

/// A hashtag is a place you can follow, not a search you have to run again.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String at = '/market/tag/plasticfree',
  bool guest = false,
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
  container.read(routerProvider).go(at);
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('the key', () {
    test('is the hash stripped and lowercased, like the backend', () {
      // Must match `keyOf` in functions/src/index.ts exactly, or the page
      // somebody follows and the page the fan-out notifies them about are
      // two different pages.
      expect(tagKey('#PlasticFree'), 'plasticfree');
      expect(tagKey('plasticfree'), 'plasticfree');
      expect(tagKey('  #MadeInDetroit '), 'madeindetroit');
      expect(tagKey(''), '');
      expect(tagLabel('PlasticFree'), '#plasticfree');
    });
  });

  testWidgets('a tag page shows what was posted under it', (tester) async {
    await _pump(tester);

    expect(find.text('COLLECTION'), findsOneWidget);
    expect(find.text('#plasticfree'), findsOneWidget);
    expect(find.byType(ProductPin), findsWidgets);
    // Counted from what is on the page, and the copy says so.
    expect(find.textContaining('posts here'), findsOneWidget);
  });

  testWidgets('a tag nobody has used says so rather than breaking', (
    tester,
  ) async {
    await _pump(tester, at: '/market/tag/nobodyhasusedthis');

    expect(find.text('#nobodyhasusedthis'), findsOneWidget);
    expect(
      find.textContaining('Nothing under #nobodyhasusedthis yet'),
      findsOneWidget,
    );
    expect(find.byType(ProductPin), findsNothing);
  });

  testWidgets('Follow sticks, and Notify follows with it', (tester) async {
    final container = await _pump(tester);
    container.listen(followedTagsProvider, (_, _) {}, fireImmediately: true);
    container.listen(notifiedTagsProvider, (_, _) {}, fireImmediately: true);

    expect(find.text('Follow'), findsOneWidget);
    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();

    expect(container.read(followedTagsProvider).value, contains('plasticfree'));
    expect(find.text('Following'), findsOneWidget);
    // Following is not the same as wanting to be interrupted.
    expect(
      container.read(notifiedTagsProvider).value ?? const {},
      isNot(contains('plasticfree')),
    );

    await tester.tap(find.text('Notify me'));
    await tester.pumpAndSettle();

    expect(container.read(notifiedTagsProvider).value, contains('plasticfree'));
    // Asking to be told about it also follows it: there is no state where
    // you are notified about something you do not follow.
    expect(container.read(followedTagsProvider).value, contains('plasticfree'));
    expect(find.text('Notifying you'), findsOneWidget);
  });

  testWidgets('unfollowing takes the notification with it', (tester) async {
    final container = await _pump(tester);
    container.listen(followedTagsProvider, (_, _) {}, fireImmediately: true);
    container.listen(notifiedTagsProvider, (_, _) {}, fireImmediately: true);

    await tester.tap(find.text('Notify me'));
    await tester.pumpAndSettle();
    expect(container.read(notifiedTagsProvider).value, contains('plasticfree'));

    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();

    expect(container.read(followedTagsProvider).value, isEmpty);
    expect(container.read(notifiedTagsProvider).value, isEmpty);
  });

  testWidgets('the chips narrow it to one kind', (tester) async {
    await _pump(tester);
    expect(find.byType(ProductPin), findsWidgets);

    await tester.tap(find.text('Reviews'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductPin), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductPin), findsWidgets);
  });

  testWidgets('a guest is asked to make a profile before following', (
    tester,
  ) async {
    final container = await _pump(tester, guest: true);
    container.listen(followedTagsProvider, (_, _) {}, fireImmediately: true);

    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();

    expect(find.text('Make a profile to do that'), findsOneWidget);
    expect(container.read(followedTagsProvider).value ?? const {}, isEmpty);
  });

  testWidgets('tapping a hashtag anywhere lands on its page', (tester) async {
    // From a maker's board, where the tags are their own. A product page
    // would do as well but does not get past its skeleton in a widget test.
    await _pump(tester, at: '/market/seller/kali');

    final chip = find.textContaining('#').first;
    final label = (tester.widget<Text>(chip)).data!;
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(find.text('COLLECTION'), findsOneWidget);
    expect(find.text(tagLabel(label)), findsWidgets);
  });
}
