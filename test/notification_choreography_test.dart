import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/firebase/mappers.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/notifications_ui.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/widgets/pins/thread_pin.dart';
import 'package:little_blue_market/widgets/primitives.dart';

/// The notification choreography from the mockup (2026-09-28): for each kind
/// of event, which surface shows it, and only that one.
///
/// "decide" is the matrix itself, one row per test. "surfaces" is the app
/// drawing what the matrix says, on the fixture backend.

const _now = DecideContext();

void main() {
  group('decide', () {
    test('announcement: bell and hero, never a toast', () {
      expect(decide(UiEvent.announcement, _now), {
        Surface.bellRing,
        Surface.bellBadge,
        Surface.heroPin,
      });
    });

    test('promo: the hero, labelled, and nothing else', () {
      expect(decide(UiEvent.promo, _now), {Surface.heroPin});
    });

    test('DM: the banner and the You mail badge, no bell', () {
      expect(decide(UiEvent.dm, _now), {Surface.banner, Surface.youMail});
    });

    test('mention: toast and bell', () {
      expect(decide(UiEvent.mention, _now), {
        Surface.toast,
        Surface.bellRing,
        Surface.bellBadge,
      });
    });

    test('a reply to you: toast and bell', () {
      expect(decide(UiEvent.comment, _now), {
        Surface.toast,
        Surface.bellRing,
        Surface.bellBadge,
      });
    });

    test(
      'forum reply: no toast, no ring; badge, "N new" and Community dot',
      () {
        expect(decide(UiEvent.forumReply, _now), {
          Surface.bellBadge,
          Surface.threadPill,
          Surface.communityDot,
        });
      },
    );

    test('chat: the live pin only, until there are five unseen', () {
      expect(decide(UiEvent.chat, const DecideContext(chatUnseen: 1)), {
        Surface.chatPin,
      });
      expect(
        decide(UiEvent.chat, const DecideContext(chatUnseen: chatDotAfter)),
        {Surface.chatPin, Surface.communityDot},
      );
    });

    test('chat, in the room: the pin and the "N new" pill, no dot', () {
      expect(
        decide(
          UiEvent.chat,
          const DecideContext(inChatroom: true, chatUnseen: 9),
        ),
        {Surface.chatPin, Surface.chatPill},
      );
    });

    test('tag post: toast and bell', () {
      expect(decide(UiEvent.tagPost, _now), {
        Surface.toast,
        Surface.bellRing,
        Surface.bellBadge,
      });
    });

    test('drop from a maker you follow: the pin grows in, and the bell', () {
      final surfaces = decide(UiEvent.drop, _now);
      expect(surfaces, {Surface.bellRing, Surface.bellBadge, Surface.dropPin});
      expect(surfaces, isNot(contains(Surface.toast)));
    });

    test('delivered: the review nudge, the bell, and a dot on You', () {
      expect(decide(UiEvent.delivered, _now), {
        Surface.bellRing,
        Surface.bellBadge,
        Surface.nudgePin,
        Surface.youDot,
      });
    });

    test('your own action: a toast, never the bell', () {
      expect(decide(UiEvent.ownAction, _now), {Surface.toast});
    });

    test('no event pushes a toast and a banner at once', () {
      for (final event in UiEvent.values) {
        final s = decide(event, _now);
        expect(
          s.contains(Surface.toast) && s.contains(Surface.banner),
          isFalse,
          reason: '$event',
        );
      }
    });

    group('dedupe', () {
      test('already on the thread or the DM: no toast, no banner', () {
        const looking = DecideContext(viewingSubject: true);
        expect(decide(UiEvent.dm, looking), {Surface.youMail});
        expect(decide(UiEvent.mention, looking), {
          Surface.bellRing,
          Surface.bellBadge,
        });
      });
    });

    group('quiet hours', () {
      const night = DecideContext(quiet: true);

      test('a reply and a tag post wait for the morning', () {
        for (final event in [UiEvent.comment, UiEvent.tagPost]) {
          final s = decide(event, night);
          expect(s, isNot(contains(Surface.toast)), reason: '$event');
          expect(s, contains(Surface.quietQueue), reason: '$event');
          // Badges still count.
          expect(s, contains(Surface.bellBadge), reason: '$event');
        }
      });

      test('a person talking to you still gets through', () {
        expect(decide(UiEvent.mention, night), contains(Surface.toast));
        expect(decide(UiEvent.dm, night), contains(Surface.banner));
      });

      test('your own actions are not notifications', () {
        expect(decide(UiEvent.ownAction, night), {Surface.toast});
      });

      test('the default window is 10 pm to 8 am, across midnight', () {
        expect(isQuietAt(DateTime(2026, 9, 28, 22, 30)), isTrue);
        expect(isQuietAt(DateTime(2026, 9, 29, 3)), isTrue);
        expect(isQuietAt(DateTime(2026, 9, 29, 7, 59)), isTrue);
        expect(isQuietAt(DateTime(2026, 9, 29, 8)), isFalse);
        expect(isQuietAt(DateTime(2026, 9, 28, 21, 59)), isFalse);
      });
    });
  });

  group('the state machine', () {
    ProviderContainer container({DateTime? at}) {
      final c = ProviderContainer(
        overrides: [
          nowProvider.overrideWithValue(() => at ?? DateTime(2026, 9, 28, 14)),
          currentPathProvider.overrideWithValue(() => '/market'),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('one toast slot: a newer one replaces the old', () {
      final c = container();
      final ui = c.read(notificationsUiProvider.notifier);
      ui.handle(UiEvent.mention, title: 'first');
      ui.handle(UiEvent.comment, title: 'second');
      expect(c.read(notificationsUiProvider).toast?.title, 'second');
    });

    test('forum replies count per thread, and opening one clears it', () {
      final c = container();
      final ui = c.read(notificationsUiProvider.notifier);
      ui.handle(UiEvent.forumReply, threadId: 't1');
      ui.handle(UiEvent.forumReply, threadId: 't1');
      ui.handle(UiEvent.forumReply, threadId: 't2');
      expect(c.read(notificationsUiProvider).threadNew, {'t1': 2, 't2': 1});
      ui.seenThread('t1');
      expect(c.read(notificationsUiProvider).threadNew, {'t2': 1});
    });

    test('the fifth unseen chat message lights Community', () {
      final c = container();
      final ui = c.read(notificationsUiProvider.notifier);
      for (var i = 0; i < chatDotAfter - 1; i++) {
        ui.handle(UiEvent.chat);
      }
      expect(c.read(notificationsUiProvider).communityDot, isFalse);
      ui.handle(UiEvent.chat);
      expect(c.read(notificationsUiProvider).communityDot, isTrue);
      ui.seenCommunity();
      expect(c.read(notificationsUiProvider).communityDot, isFalse);
    });
  });

  group('surfaces', () {
    Future<ProviderContainer> pumpApp(
      WidgetTester tester, {
      DateTime Function()? now,
      List<Override> overrides = const [],
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        retry: lbmRetry,
        overrides: [
          nowProvider.overrideWithValue(now ?? () => DateTime(2026, 9, 28, 14)),
          ...overrides,
        ],
      );
      addTearDown(container.dispose);
      container.read(sessionProvider.notifier).signIn();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const LittleBlueMarketApp(),
        ),
      );
      await tester.pump();
      container.read(routerProvider).go('/market');
      await tester.pumpAndSettle();
      return container;
    }

    /// Lets any toast run out, so no timer outlives the test.
    Future<void> letItGo(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    NotificationsUi ui(ProviderContainer c) =>
        c.read(notificationsUiProvider.notifier);

    testWidgets('DM: a banner with Reply, which opens the conversation', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      final kali = Conversation.idFor('maya', 'kali');

      ui(c).handle(
        UiEvent.dm,
        title: 'Kali Brooks',
        subtitle: "Pawpaw's in through mid-October, want me to hold two?",
        route: '/you/dm/$kali',
        personId: 'kali',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Kali Brooks'), findsWidgets);
      expect(find.text('Reply'), findsOneWidget);

      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(c.read(routerProvider).state.uri.path, '/you/dm/$kali');
      await letItGo(tester);
    });

    testWidgets('a mention: a toast, and the bell rings on You', (
      tester,
    ) async {
      final c = await pumpApp(tester);

      ui(c).handle(
        UiEvent.mention,
        kicker: 'Mention',
        title: 'Ama Mensah mentioned you',
        subtitle: "@maya Kali's in Ypsi too",
        route: '/community',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Ama Mensah mentioned you'), findsOneWidget);
      expect(c.read(notificationsUiProvider).bellRingPending, isTrue);

      await letItGo(tester);
      expect(find.text('Ama Mensah mentioned you'), findsNothing);

      c.read(routerProvider).go('/you');
      await tester.pump();
      final bell = tester.widget<CircleIconButton>(
        find.byWidgetPredicate(
          (w) => w is CircleIconButton && w.tooltip == 'Notifications',
        ),
      );
      expect(bell.ring, isTrue);
      await tester.pumpAndSettle();
      // Rung once, then done.
      expect(c.read(notificationsUiProvider).bellRingPending, isFalse);
    });

    testWidgets('a forum reply: no toast, "1 new" on the pin, Community dot', (
      tester,
    ) async {
      final c = await pumpApp(tester);

      final surfaces = ui(c).handle(
        UiEvent.forumReply,
        route: '/community/thread/t1',
        threadId: 't1',
      );
      await tester.pumpAndSettle();

      expect(surfaces, isNot(contains(Surface.toast)));
      expect(c.read(notificationsUiProvider).toast, isNull);
      expect(c.read(notificationsUiProvider).communityDot, isTrue);

      await tester.scrollUntilVisible(
        find.text('1 new'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final pin = tester.widget<ThreadPin>(
        find.ancestor(of: find.text('1 new'), matching: find.byType(ThreadPin)),
      );
      expect(pin.item.thread.id, 't1');
      expect(pin.newCount, 1);
    });

    testWidgets('quiet hours: no toast, then the strip on the next open', (
      tester,
    ) async {
      var now = DateTime(2026, 9, 28, 22, 30);
      final c = await pumpApp(tester, now: () => now);

      ui(c).handle(
        UiEvent.tagPost,
        kicker: 'New under #handmade',
        title: 'Madi posted',
        route: '/market/tag/handmade',
      );
      await tester.pumpAndSettle();
      expect(find.text('Madi posted'), findsNothing);
      expect(c.read(notificationsUiProvider).pendingWhileQuiet, 1);

      // Still night when the app comes back: keep holding.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('waiting'), findsNothing);

      // Morning.
      now = DateTime(2026, 9, 29, 8, 30);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Quiet hours · 1 notification waiting'), findsOneWidget);
      await letItGo(tester);
    });

    testWidgets('quiet hours: a mention still gets through', (tester) async {
      final c = await pumpApp(tester, now: () => DateTime(2026, 9, 28, 22, 30));
      ui(c).handle(UiEvent.mention, title: 'Ama Mensah mentioned you');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Ama Mensah mentioned you'), findsOneWidget);
      await letItGo(tester);
    });

    testWidgets('dedupe: a DM from the conversation already open is quiet', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      c.read(routerProvider).go('/you/dm/kali?to=1');
      await tester.pumpAndSettle();

      ui(c).handle(
        UiEvent.dm,
        title: 'Kali Brooks',
        subtitle: 'hello',
        route: '/you/dm/${Conversation.idFor('maya', 'kali')}',
        personId: 'kali',
        viewing: ['/dm/kali'],
      );
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsNothing);
    });

    testWidgets('the bell stream: a new mention row becomes a toast', (
      tester,
    ) async {
      final bell = StreamController<List<AppNotification>>.broadcast();
      addTearDown(bell.close);
      final c = await pumpApp(
        tester,
        overrides: [notificationsProvider.overrideWith((ref) => bell.stream)],
      );

      // The first value is the baseline: nothing in it is news.
      final old = AppNotification(
        id: 'n0',
        kind: NotificationKind.mention,
        postId: 'post_p3',
        fromUid: 'kali',
        text: 'from yesterday',
        createdAt: DateTime(2026, 9, 27),
      );
      bell.add([old]);
      await tester.pumpAndSettle();
      expect(c.read(notificationsUiProvider).toast, isNull);

      bell.add([
        AppNotification(
          id: 'n1',
          kind: NotificationKind.mention,
          postId: 'post_p3',
          fromUid: 'kali',
          text: '@maya look at this',
          createdAt: DateTime(2026, 9, 28, 14),
          route: '/community',
        ),
        old,
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.textContaining('mentioned you'), findsOneWidget);
      expect(find.text('@maya look at this'), findsOneWidget);
      await letItGo(tester);
    });

    testWidgets('the room: scrolled up, a new message shows "1 new"', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      // Enough of a room to scroll back through.
      for (var i = 0; i < 20; i++) {
        await c
            .read(messagingRepositoryProvider)
            .sendToChatroom('Message number $i');
      }
      c.read(routerProvider).go('/community');
      await tester.pumpAndSettle();

      // Read back up the room.
      await tester.drag(find.text('Message number 19'), const Offset(0, 400));
      await tester.pumpAndSettle();

      ui(c).handle(UiEvent.chat);
      await tester.pumpAndSettle();
      expect(find.text('1 new'), findsOneWidget);

      await tester.tap(find.text('1 new'));
      await tester.pumpAndSettle();
      expect(c.read(notificationsUiProvider).chatPillCount, 0);
    });
  });

  group('quiet hours, set by the person (C3)', () {
    test('default 10 pm to 8 am; anything unreadable falls back', () {
      expect(const NotificationPrefs().quietMinutes, (
        start: 22 * 60,
        end: 8 * 60,
      ));
      expect(
        const NotificationPrefs(
          quietStart: '23:30',
          quietEnd: 'later',
        ).quietMinutes,
        (start: 23 * 60 + 30, end: 8 * 60),
      );
    });

    test('saved as the two strings the backend reads', () {
      final map = const NotificationPrefs(quietStart: '21:00').toMap();
      expect(map['quietStart'], '21:00');
      expect(map['quietEnd'], '08:00');
      final back = FirestoreMappers.notificationPrefs({'quietStart': '21:00'});
      expect(back.quietStart, '21:00');
      expect(back.quietEnd, NotificationPrefs.defaultQuietEnd);
      expect(FirestoreMappers.notificationPrefs(null).quietStart, '22:00');
      // Direct messages: on unless switched off.
      expect(const NotificationPrefs().messages, isTrue);
      expect(
        FirestoreMappers.notificationPrefs({'messages': false}).messages,
        isFalse,
      );
      expect(
        const NotificationPrefs(messages: false).toMap()['messages'],
        false,
      );
    });

    testWidgets('the settings screen shows the window, 10 pm to 8 am', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(retry: lbmRetry);
      addTearDown(c.dispose);
      c.read(sessionProvider.notifier).signIn();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const LittleBlueMarketApp(),
        ),
      );
      await tester.pump();
      c.read(routerProvider).go('/you/notification-settings');
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Until'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('10:00 PM'), findsOneWidget);
      expect(find.text('8:00 AM'), findsOneWidget);
      expect(
        find.textContaining('Forum replies: digest every 30 min'),
        findsOneWidget,
      );
    });

    test('the app follows the saved window, not a fixed one', () async {
      final c = ProviderContainer(
        overrides: [
          nowProvider.overrideWithValue(() => DateTime(2026, 9, 28, 14)),
          currentPathProvider.overrideWithValue(() => '/market'),
          notificationPrefsProvider.overrideWith(
            (ref) => Stream.value(
              const NotificationPrefs(quietStart: '13:00', quietEnd: '15:00'),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(notificationPrefsProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      final surfaces = c
          .read(notificationsUiProvider.notifier)
          .handle(UiEvent.tagPost, title: 'Held', route: '/market/tag/x');
      expect(surfaces, contains(Surface.quietQueue));
    });
  });
}
