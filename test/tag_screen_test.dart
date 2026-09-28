import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/state/tags.dart';
import 'package:little_blue_market/widgets/filter_chips.dart';
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

    test('#This and #this are one tag, and one page', () {
      // Grace, 2026-09-28: "Is there a way to make hashtags case agnostic so
      // #This is the same as #this?" This is what makes it so. Every place
      // that stores, matches, routes or follows a hashtag goes through this
      // one function, so capitals decide nothing anywhere.
      expect(tagKey('#This'), tagKey('#this'));
      expect(tagKey('#CanTEditHistory'), tagKey('#cantedithistory'));
      expect(tagKey('#CanTEditHistory'), tagKey('#CANTEDITHISTORY'));
      // Including the two ways a person might type the same one.
      expect(tagKey('#WomanOwned'), tagKey('womanowned'));
      expect(tagKey('  #WomanOwned  '), tagKey('#womanowned'));
    });
  });

  testWidgets('a tag page shows what was posted under it', (tester) async {
    await _pump(tester);

    expect(find.text('COLLECTION'), findsOneWidget);
    // The spelling the market uses, not the key the route carries: a tag
    // is matched case agnostically and shown as somebody wrote it.
    expect(find.text('#PlasticFree'), findsOneWidget);
    expect(find.byType(ProductPin), findsWidgets);
    // Counted from what is on the page, and the copy says so. "Things"
    // rather than "posts" since 2026-09-28: a tag page counts the listings
    // under the tag as well, and on the live market those are nearly all of
    // it — a product's hashtags live on the product, and nothing in
    // production had ever tagged a post.
    expect(find.textContaining('things here'), findsOneWidget);
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
    // The page shows the spelling, and the chip that opened it was that
    // spelling, so they read the same. What made them one page is the key:
    // `tagKey` of both is equal whatever the capitals did.
    expect(find.text(label), findsWidgets);
    expect(tagKey(label), tagKey(label.toUpperCase()));
  });

  group('the thing production actually had', () {
    testWidgets('a listing with the tag shows even when no post carries it', (
      tester,
    ) async {
      // Grace, 2026-09-28: "Items or people that have tags are not showing
      // up in that tag's detail page on prod."
      //
      // A product's hashtags live on the product. In production nothing had
      // ever tagged a *post*, so a page that asked only the post stream was
      // empty of everything, and no test saw it because in fixtures every
      // product also has a listing post carrying the same tags.
      //
      // p4 is the exception: it carries #PlasticFree and is not in
      // `feedOrder`, so it has no post anywhere. If it is on the page, the
      // page asked the catalogue.
      await _pump(tester);

      expect(
        find.textContaining('Lip Balm Flight'),
        findsWidgets,
        reason: 'a tagged listing with no post of its own never appeared',
      );
    });

    testWidgets('its maker counts as somebody posting under the tag', (
      tester,
    ) async {
      // The makers rail was built from post authors alone, so a tag whose
      // only presence is listings said "Nobody yet" under a market full of
      // people selling under it.
      await _pump(tester);
      // Makers is the fifth chip in a row that scrolls sideways, so on a
      // 390-wide phone it starts off the right-hand edge.
      final makers = find.text('Makers');
      await tester.scrollUntilVisible(
        makers,
        90,
        scrollable: find
            .descendant(
              of: find.byType(FilterChips),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(makers);
      await tester.pumpAndSettle();

      expect(find.text('Nobody yet'), findsNothing);
      expect(find.textContaining('Posting under #PlasticFree'), findsOneWidget);
    });
  });
}
