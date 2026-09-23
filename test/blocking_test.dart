import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/data/repositories/repositories.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';

/// Blocking abusive people, which both app stores require of an app that
/// carries what people write, and which this app had none of until
/// 2026-09-14.
///
/// The point of these is the second half: a block that is recorded but does
/// not actually take the person off your screen would pass a code review and
/// fail a real one.
Future<ProviderContainer> _signedIn(
  WidgetTester tester, {
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
  // Riverpod disposes a provider nothing listens to, and a stream backed by
  // a controller then never delivers its first value, so reading .future
  // waits for ever. A screen always has a listener; a test has to say so.
  for (final provider in [blockedUidsProvider, feedProvider, chatroomProvider, inboxProvider]) {
    container.listen(provider, (_, _) {});
  }
  return container;
}

void main() {
  testWidgets('a guest has blocked nobody', (tester) async {
    // Pumped, not a bare container: reading the session without the app
    // around it throws, and lbmRetry then retries for ever, which looks
    // exactly like a hang.
    final container = await _signedIn(tester, guest: true);
    expect(container.read(blockedUidsProvider).value ?? const <String>{}, isEmpty);
  });

  testWidgets('blocking takes their posts out of the feed', (tester) async {
    final container = await _signedIn(tester);
    final feedBefore = await container.read(feedProvider.future);
    expect(feedBefore, isNotEmpty);

    // Somebody who has actually posted, so the test cannot pass by accident.
    final victim = feedBefore.first.authorId;
    expect(victim, isNot(Fx.meId));
    final theirsBefore = feedBefore.where((p) => p.authorId == victim);
    expect(theirsBefore, isNotEmpty);

    await container.read(reportRepositoryProvider).blockUser(victim);
    await tester.pumpAndSettle();

    expect(await container.read(blockedUidsProvider.future), contains(victim));
    final feedAfter = await container.read(feedProvider.future);
    expect(
      feedAfter.where((p) => p.authorId == victim),
      isEmpty,
      reason: 'a blocked person is still in the feed',
    );
    // Everyone else is untouched.
    expect(feedAfter, isNotEmpty);
  });

  testWidgets('and their comments, chat and inbox threads', (tester) async {
    final container = await _signedIn(tester);
    final feed = await container.read(feedProvider.future);
    final victim = feed.first.authorId;

    final chatBefore = await container.read(chatroomProvider.future);
    await container.read(reportRepositoryProvider).blockUser(victim);
    await tester.pumpAndSettle();

    // Chat: nothing of theirs is left in the room.
    final chatAfter = await container.read(chatroomProvider.future);
    expect(chatAfter.where((m) => m.authorId == victim), isEmpty);
    expect(chatAfter.length, lessThanOrEqualTo(chatBefore.length));

    // The inbox: a one-to-one thread with them goes.
    final inbox = await container.read(inboxProvider.future);
    expect(
      inbox.where((c) => c.participantIds.contains(victim)),
      isEmpty,
      reason: 'a blocked person is still in the inbox',
    );

    // Comments on somebody else's post: theirs are gone, the rest stay.
    final postId = feed.first.id;
    container.listen(commentsProvider(postId), (_, _) {});
    final comments = await container.read(commentsProvider(postId).future);
    expect(comments.where((c) => c.authorId == victim), isEmpty);
  });

  testWidgets('unblocking puts everything back', (tester) async {
    final container = await _signedIn(tester);
    final feed = await container.read(feedProvider.future);
    final victim = feed.first.authorId;
    final howMany = feed.where((p) => p.authorId == victim).length;

    final repo = container.read(reportRepositoryProvider);
    await repo.blockUser(victim);
    await tester.pumpAndSettle();
    expect((await container.read(feedProvider.future)).length, feed.length - howMany);

    await repo.unblockUser(victim);
    await tester.pumpAndSettle();
    expect(await container.read(blockedUidsProvider.future), isEmpty);
    expect((await container.read(feedProvider.future)).length, feed.length);
  });

  testWidgets('blocking yourself is refused', (tester) async {
    final container = await _signedIn(tester);
    await expectLater(
      container.read(reportRepositoryProvider).blockUser(Fx.meId),
      throwsA(isA<ValidationException>()),
    );
    expect(await container.read(blockedUidsProvider.future), isEmpty);
  });

  testWidgets('the sheet offers Block, and Unblock once it is used', (
    tester,
  ) async {
    final container = await _signedIn(tester);
    // The floating cart now sits over the bottom right of every screen, and
    // the feed's first post header starts just under it behind all the
    // rails. A person scrolls; a test has to say so.
    await tester.dragFrom(const Offset(195, 400), const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Block '), findsOneWidget);
    expect(find.textContaining('Unblock '), findsNothing);

    final feed = await container.read(feedProvider.future);
    await container.read(reportRepositoryProvider).blockUser(feed.first.authorId);
    await tester.pumpAndSettle();
    // The row reads the live set, so it flips without being rebuilt by hand.
    expect(find.textContaining('Unblock '), findsOneWidget);
  });
}
