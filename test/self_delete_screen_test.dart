import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/widgets/primitives.dart';

/// Deleting your own account, at once (Grace, 2026-09-14).
///
/// The guards that matter are the backend's and are tested there. These
/// cover the screen's own promise: it cannot be fired by accident, and the
/// signed-out path is still a request rather than a wipe.
Future<ProviderContainer> _open(
  WidgetTester tester, {
  required bool signedIn,
  bool scroll = true,
}) async {
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
  if (signedIn) {
    container.read(sessionProvider.notifier).signIn();
    await tester.pumpAndSettle();
  }
  container.read(routerProvider).push('/delete-account');
  await tester.pumpAndSettle();
  // The page is a lazy ListView and the buttons are below the fold, so an
  // un-scrolled test finds nothing and reads as a missing feature. The copy
  // near the top is the opposite: scrolled away, it is no longer built.
  if (scroll) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await tester.pumpAndSettle();
  }
  return container;
}

/// Fills in the password and the word. The password is asked for in the
/// screen itself so the backend's recent-sign-in rule can be met without
/// signing out (Grace, 2026-09-14).
Future<void> _fillIn(
  WidgetTester tester, {
  String password = 'a-good-password',
  String confirm = kDeleteConfirmation,
}) async {
  final fields = find.byType(TextField);
  // Password first, then the word: the order they appear on screen.
  await tester.enterText(fields.at(fields.evaluate().length - 2), password);
  await tester.enterText(fields.last, confirm);
  await tester.pumpAndSettle();
}

PillButton _button(WidgetTester tester, String label) =>
    tester.widget<PillButton>(find.widgetWithText(PillButton, label).first);

void main() {
  testWidgets('signed in, it offers to do it now and will not fire early', (
    tester,
  ) async {
    await _open(tester, signedIn: true);

    expect(find.text('Delete my account now'), findsOneWidget);
    // The request path is not offered to somebody who can just do it.
    expect(find.text('Send my request'), findsNothing);

    // Nothing typed: the button is dead.
    expect(_button(tester, 'Delete my account now').onPressed, isNull);

    // The wrong word, including the right word in the wrong case.
    for (final typed in ['delete', 'Delete', 'DELET', 'yes']) {
      await _fillIn(tester, confirm: typed);
      expect(
        _button(tester, 'Delete my account now').onPressed,
        isNull,
        reason: '"\$typed" should not arm an irreversible button',
      );
    }

    await _fillIn(tester);
    expect(_button(tester, 'Delete my account now').onPressed, isNotNull);

    // The word alone is not enough: the password is asked for too.
    await _fillIn(tester, password: '');
    expect(_button(tester, 'Delete my account now').onPressed, isNull);
  });

  testWidgets('it asks once more before doing it', (tester) async {
    await _open(tester, signedIn: true);
    await _fillIn(tester);

    await tester.tap(find.text('Delete my account now'));
    await tester.pumpAndSettle();
    // A dialog, not a deletion.
    expect(find.text('Delete your account?'), findsOneWidget);
    expect(find.text('Keep it'), findsOneWidget);

    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    // Backed out, and the screen is unchanged.
    expect(find.text('Your account is gone'), findsNothing);
    expect(find.text('Delete my account now'), findsOneWidget);
  });

  testWidgets('it leaves the page, and says so where you land', (
    tester,
  ) async {
    final container = await _open(tester, signedIn: true);
    await _fillIn(tester);
    await tester.ensureVisible(find.text('Delete my account now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete my account now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete for ever'));
    await tester.pumpAndSettle();

    // Off the deletion page, with no tap and no waiting. Grace got no
    // reroute at all when this depended on that page surviving the sign-out
    // and a three-second timer (2026-09-14).
    final where = container
        .read(routerProvider)
        .routerDelegate
        .currentConfiguration
        .uri;
    expect(where.path, '/signin');
    expect(where.queryParameters['create'], '1');
    expect(where.queryParameters['deleted'], '1');

    // And the confirmation is here, where it can be read, rather than on
    // the page that has just been replaced.
    expect(
      find.textContaining('Your account has been deleted'),
      findsOneWidget,
    );
    expect(find.textContaining('financial records'), findsOneWidget);
    // Somewhere to go next.
    expect(find.text('Create my profile'), findsOneWidget);
  });

  testWidgets('erasing data only keeps you where you are', (tester) async {
    // Unscrolled: the two scope rows are near the top, and the helper
    // scrolls past them to reach the buttons.
    final container = await _open(tester, signedIn: true, scroll: false);
    // The other scope: the account stays, so there is nothing to sign out
    // of and nowhere to be sent.
    await tester.tap(find.text('My data, but keep my account'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await _fillIn(tester);
    await tester.ensureVisible(find.text('Erase my information now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase my information now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase it'));
    await tester.pumpAndSettle();

    expect(find.text('Your information is erased'), findsOneWidget);
    expect(
      container
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .path,
      isNot('/signin'),
    );
  });

  testWidgets('signed out it is still a request, never a wipe', (tester) async {
    await _open(tester, signedIn: false);

    expect(find.text('Send my request'), findsOneWidget);
    expect(find.text('Delete my account now'), findsNothing);
  });

  // One app per test: pumping a second over the first is not a navigation.
  testWidgets('signed in, the copy says it is instant', (tester) async {
    await _open(tester, signedIn: true, scroll: false);
    expect(find.textContaining('happens straight away'), findsOneWidget);
  });

  testWidgets('signed out, the copy says why it is not', (tester) async {
    await _open(tester, signedIn: false, scroll: false);
    // So it does not read as us dragging our feet.
    expect(find.textContaining('a person checks it first'), findsOneWidget);
  });
}
