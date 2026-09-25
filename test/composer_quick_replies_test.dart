import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/widgets/cart_pill.dart';
import 'package:little_blue_market/widgets/message_product_card.dart';
import 'package:little_blue_market/widgets/screen.dart';

/// Ready-made words, in the two places writing from nothing stops people.
///
/// The review sheet and the message field both open on an empty box that most
/// people close again. A chip is not a canned message: tapping one fills the
/// field so it can be added to, which is why neither of these tests asserts
/// that a chip sends anything by itself.
Future<ProviderContainer> _pumpApp(WidgetTester tester) async {
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
  container.read(sessionProvider.notifier).signIn();
  await tester.pumpAndSettle();
  return container;
}

/// The text in the composer's own field.
String _composerText(WidgetTester tester) {
  final field = tester.widget<TextField>(
    find.descendant(
      of: find.byType(Composer),
      matching: find.byType(TextField),
    ),
  );
  return field.controller?.text ?? '';
}

void main() {
  group('the review sheet', () {
    /// Opens it the way Grace asked for: from the things you bought, on the
    /// edit-profile side, with Rate it on the one that is waiting.
    ///
    /// Through the real route rather than a bare `MaterialApp` on purpose:
    /// the sheet reads its colours from the app's theme extension, so a
    /// hand-built host throws before it draws a star.
    Future<Purchase> openReviewSheet(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      container.listen(purchasesProvider, (_, _) {}, fireImmediately: true);
      await tester.pumpAndSettle();

      container.read(routerProvider).go('/you/purchases');
      await tester.pumpAndSettle();

      final rate = find.text('Rate it').first;
      await tester.ensureVisible(rate);
      await tester.pumpAndSettle();
      await tester.tap(rate);
      await tester.pumpAndSettle();

      // Which one it opened on is the screen's business, not the test's: the
      // sheet names it, so read it back rather than guessing the order.
      final heading = tester
          .widgetList<Text>(find.textContaining('How was the '))
          .first
          .data!;
      final title = heading.substring(
        'How was the '.length,
        heading.length - 1,
      );
      return container
          .read(purchasesProvider)
          .value!
          .firstWhere((p) => p.title == title);
    }

    testWidgets('a star on its own is a review', (tester) async {
      // Words used to be required, which is how a review count stays at zero.
      // The rules ask for a rating between one and five and nothing else.
      final container = await _pumpApp(tester);
      final waiting = await openReviewSheet(tester, container);

      expect(find.text('Tap a star. That on its own counts.'), findsOneWidget);
      await tester.tap(find.text('Post review'));
      await tester.pumpAndSettle();

      final reviews = await container
          .read(socialRepositoryProvider)
          .watchReviews(waiting.productId)
          .first;
      expect(reviews.first.rating, 5);
      expect(reviews.first.text, isEmpty);
    });

    testWidgets('a chip writes the words, and the stars still decide', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      final waiting = await openReviewSheet(tester, container);

      // Four stars, not five: the stars are the review, and a chip must not
      // quietly reset them.
      await tester.tap(find.byIcon(Icons.star_rounded).at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Would buy again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post review'));
      await tester.pumpAndSettle();

      final reviews = await container
          .read(socialRepositoryProvider)
          .watchReviews(waiting.productId)
          .first;
      expect(reviews.first.rating, 4);
      expect(reviews.first.text, contains('Would buy again'));
    });

    testWidgets('two chips read as a sentence rather than a pile', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      final waiting = await openReviewSheet(tester, container);

      await tester.tap(find.text('Would buy again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arrived quickly'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post review'));
      await tester.pumpAndSettle();

      final reviews = await container
          .read(socialRepositoryProvider)
          .watchReviews(waiting.productId)
          .first;
      expect(reviews.first.text, 'Would buy again. Arrived quickly');
    });
  });

  group('a message about a listing', () {
    /// The address Ask on a product page builds: the maker, and the thing.
    Future<void> openAsk(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      container
          .read(routerProvider)
          .go('/you/dm/kali?to=1&about=${Uri.encodeComponent('p1')}');
      await tester.pumpAndSettle();
    }

    testWidgets('it opens with the question already written', (tester) async {
      // "Is this still available?" with no way to tell which "this" was the
      // commonest thing makers had to ask back.
      final container = await _pumpApp(tester);
      await openAsk(tester, container);

      expect(
        _composerText(tester),
        'Hi! Is the Cocoa Mint Lip Balm still available?',
      );
      // And the listing is visible above the thread, so the question has
      // something attached to it before anything is sent.
      expect(find.byType(MessageProductCard), findsWidgets);
    });

    testWidgets('a chip replaces the field rather than sending itself', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      container.read(routerProvider).go('/you/dm/kali?to=1');
      await tester.pumpAndSettle();

      expect(_composerText(tester), isEmpty);
      // The rail scrolls sideways and the second chip hangs off the right of
      // a 390-wide phone, so a tap at its centre would land on nothing.
      final chip = find.text('Do you do pickup?');
      await tester.scrollUntilVisible(
        chip,
        60,
        // `.first` because the field itself is scrollable too; the rail is
        // built above it.
        scrollable: find
            .descendant(
              of: find.byType(Composer),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(_composerText(tester), 'Do you do pickup?');
      // Nothing was sent: the point is to get past the empty box, not to put
      // words in somebody's mouth. Asked of the conversation rather than the
      // screen, because the chip carrying those words is on the screen too.
      final messaging = container.read(messagingRepositoryProvider);
      final inbox = await messaging.watchInbox().first;
      for (final conversation in inbox) {
        final messages = await messaging
            .watchConversation(conversation.id)
            .first;
        expect(
          messages.map((m) => m.text),
          isNot(contains('Do you do pickup?')),
        );
      }
    });

    testWidgets('sending it puts the listing in the bubble, cartable', (
      tester,
    ) async {
      // The bridge the redesign is for: talking to people and buying from
      // them stop being two apps that share a tab bar.
      final container = await _pumpApp(tester);
      await openAsk(tester, container);

      final before = find.byType(MessageProductCard).evaluate().length;
      await tester.tap(
        find.descendant(
          of: find.byType(Composer),
          matching: find.byIcon(Icons.send_rounded),
        ),
      );
      await tester.pumpAndSettle();

      // One more card than before: the one in the message just sent.
      expect(
        find.byType(MessageProductCard).evaluate().length,
        greaterThan(before),
      );
      expect(find.textContaining('Cocoa Mint Lip Balm'), findsWidgets);
      expect(find.byType(CartPill), findsWidgets);
      // The field is empty again, so the next message is not the same one.
      expect(_composerText(tester), isEmpty);
    });
  });
}
