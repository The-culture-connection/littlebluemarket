import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/data/repositories/repositories.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/profile_activity.dart';
import 'package:little_blue_market/models/profile_tabs.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/widgets/filter_chips.dart';

/// Phase 9 B2/B3: a profile shows what somebody does in the community, and
/// its owner decides which parts of it other people see.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String at = '/you',
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
  container.read(sessionProvider.notifier).signIn();
  await tester.pumpAndSettle();
  container.read(routerProvider).go(at);
  await tester.pumpAndSettle();
  return container;
}

/// The fixture user starts with no community activity, which is the honest
/// starting state and no use to these tests. One thread and one comment,
/// made the way the app makes them.
Future<void> _sayThings(ProviderContainer container) async {
  final social = container.read(socialRepositoryProvider);
  await social.createThread(
    const NewThread(
      forumId: 'f1',
      title: 'What do you wrap fragile things in?',
      body: 'Tissue keeps arriving torn.',
    ),
  );
  await social.addThreadComment(
    threadId: 't1',
    text: 'Raised mine 20% and said why. Nobody left.',
  );
}

/// The chip row is a horizontal list, so the chips off its right edge are
/// not built until it is dragged. Every test that looks for a late chip has
/// to scroll for it, and a test that asserts one is *absent* has to scroll
/// the whole row before it can say so.
Finder get _chipRow => find.byType(FilterChips).first;

Future<void> _tapChip(WidgetTester tester, String label) async {
  final chip = find.descendant(of: _chipRow, matching: find.text(label));
  for (var i = 0; i < 8 && chip.evaluate().isEmpty; i++) {
    await tester.drag(_chipRow, const Offset(-160, 0));
    await tester.pumpAndSettle();
  }
  await tester.tap(chip.first);
  await tester.pumpAndSettle();
}

Future<Set<String>> _chipLabels(WidgetTester tester) async {
  final labels = <String>{};
  void collect() {
    for (final element
        in find
            .descendant(of: _chipRow, matching: find.byType(Text))
            .evaluate()) {
      final data = (element.widget as Text).data;
      if (data != null) labels.add(data);
    }
  }

  collect();
  for (var i = 0; i < 8; i++) {
    await tester.drag(_chipRow, const Offset(-160, 0));
    await tester.pumpAndSettle();
    collect();
  }
  return labels;
}

void main() {
  group('which sections a viewer gets', () {
    test('your own profile keeps all six, in the fixed order', () {
      final sections = visibleSections(
        const ProfileSections(comments: false, carts: false),
        own: true,
      );

      expect(sections, ProfileSection.values);
    });

    test('somebody else gets only what you left on', () {
      final sections = visibleSections(
        const ProfileSections(comments: false),
        own: false,
      );

      expect(sections, isNot(contains(ProfileSection.comments)));
      expect(sections, contains(ProfileSection.threads));
    });

    test("Bought is never on somebody else's profile", () {
      // users/{uid}/purchases is readable by its owner alone, so there is
      // nothing to draw however the switch is set.
      expect(
        visibleSections(const ProfileSections(), own: false),
        isNot(contains(ProfileSection.bought)),
      );
      expect(
        visibleSections(const ProfileSections(), own: true).first,
        ProfileSection.bought,
      );
    });
  });

  group('community activity on your profile', () {
    testWidgets('Comments lists what you said, and where', (tester) async {
      final container = await _pump(tester);
      await _sayThings(container);
      await tester.pumpAndSettle();

      await _tapChip(tester, 'Comments');

      expect(find.textContaining('Raised mine 20%'), findsOneWidget);
      // The words alone are a fragment; the row says which thread.
      expect(
        find.textContaining('in ${Fx.threads.first.title}'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a comment opens the thread it is in', (tester) async {
      final container = await _pump(tester);
      await _sayThings(container);
      await tester.pumpAndSettle();

      await _tapChip(tester, 'Comments');
      await tester.tap(find.textContaining('Raised mine 20%'));
      await tester.pumpAndSettle();

      expect(
        container.read(routerProvider).state.uri.toString(),
        '/community/thread/t1',
      );
    });

    testWidgets('Threads lists the ones you started', (tester) async {
      final container = await _pump(tester);
      await _sayThings(container);
      await tester.pumpAndSettle();

      await _tapChip(tester, 'Threads');

      expect(
        find.textContaining('What do you wrap fragile things in?'),
        findsOneWidget,
      );
    });
  });

  group('the toggle governs the public view', () {
    testWidgets('your own profile keeps a hidden tab, marked', (tester) async {
      final container = await _pump(tester);
      await container
          .read(profileRepositoryProvider)
          .updateProfile(
            const ProfileEdit(
              profileSections: ProfileSections(comments: false),
            ),
          );
      await tester.pumpAndSettle();

      expect(await _chipLabels(tester), contains('Comments'));
      await _tapChip(tester, 'Comments');

      expect(find.text('(hidden from others)'), findsOneWidget);
      expect(find.text('Edit what shows'), findsOneWidget);
    });

    testWidgets('a visitor to the same profile has no Comments tab', (
      tester,
    ) async {
      final container = await _pump(tester);
      await container
          .read(profileRepositoryProvider)
          .updateProfile(
            const ProfileEdit(
              profileSections: ProfileSections(comments: false),
            ),
          );
      await tester.pumpAndSettle();

      // The public view of the same person, which is what the seller route is
      // even when the person looking is its owner: tapping your own name in
      // a post is how you check what a visitor gets.
      container.read(routerProvider).go('/market/seller/${Fx.meId}');
      await tester.pumpAndSettle();

      final labels = await _chipLabels(tester);
      expect(labels, contains('Threads'));
      expect(labels, isNot(contains('Comments')));
      // And Bought is not a visitor's business either.
      expect(labels, isNot(contains('Bought')));
    });
  });
}
