import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/screens/onboarding/welcome_screen.dart';
import 'package:little_blue_market/theme/app_theme.dart';

/// Builds the welcome screen with just enough routing for its taps to resolve.
Widget _harness({bool playIntro = true}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => WelcomeScreen(playIntro: playIntro),
      ),
      GoRoute(
        path: '/signin',
        builder: (context, state) => const Scaffold(body: Text('signin')),
      ),
      GoRoute(
        path: '/market',
        builder: (context, state) => const Scaffold(body: Text('market')),
      ),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      theme: buildLbmTheme(Brightness.light),
    ),
  );
}

/// The still and the GIF have to occupy exactly the same box, or the handoff
/// moves when the animation is taken away.
Rect _rectOf(WidgetTester tester, String asset) {
  final finder = find.byWidgetPredicate(
    (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == asset,
  );
  expect(finder, findsOneWidget, reason: 'expected exactly one $asset');
  return tester.getRect(finder);
}

void main() {
  testWidgets('the still and the GIF are laid out identically', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(
      _rectOf(tester, Fx.still),
      _rectOf(tester, Fx.gif),
      reason:
          'If these ever differ the buttons will jump when the intro ends. '
          'Both must be drawn into the same 540x960 box.',
    );
  });

  testWidgets('the GIF is removed once the intro is over, the still stays', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    final gif = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == Fx.gif,
    );
    expect(gif, findsOneWidget);

    final before = _rectOf(tester, Fx.still);

    await tester.pump(kIntroDuration + const Duration(milliseconds: 50));
    await tester.pump();

    expect(gif, findsNothing);
    // Nothing moves — that is the whole point of the handoff.
    expect(_rectOf(tester, Fx.still), before);
  });

  testWidgets('the intro is skipped entirely when it is not requested', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(playIntro: false));
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == Fx.gif,
      ),
      findsNothing,
    );
  });

  testWidgets('all three hotspots are present and tappable', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    for (final label in [
      'Sign in',
      'Create a Profile',
      'Continue as a guest',
    ]) {
      expect(
        find.bySemanticsLabel(label),
        findsOneWidget,
        reason: '$label hotspot is missing',
      );
    }
  });

  testWidgets('the hotspots sit where the artwork draws its buttons', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    final box = _rectOf(tester, Fx.still);
    final signIn = tester.getRect(find.bySemanticsLabel('Sign in'));

    // 18.4% from the left, 65.1% wide, 66.9% down.
    expect(signIn.left - box.left, closeTo(box.width * 0.184, 0.5));
    expect(signIn.width, closeTo(box.width * 0.651, 0.5));
    expect(signIn.top - box.top, closeTo(box.height * 0.669, 0.5));
  });

  testWidgets('every hotspot meets the minimum touch height', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    for (final label in [
      'Sign in',
      'Create a Profile',
      'Continue as a guest',
    ]) {
      expect(
        tester.getRect(find.bySemanticsLabel(label)).height,
        greaterThanOrEqualTo(44.0),
        reason: '$label is too small to hit comfortably',
      );
    }
  });

  testWidgets('hotspots do not overlap each other', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    final rects = [
      tester.getRect(find.bySemanticsLabel('Sign in')),
      tester.getRect(find.bySemanticsLabel('Create a Profile')),
      tester.getRect(find.bySemanticsLabel('Continue as a guest')),
    ];
    for (var i = 0; i < rects.length - 1; i++) {
      expect(
        rects[i].bottom,
        lessThanOrEqualTo(rects[i + 1].top),
        reason: 'growing a touch target must not collide with its neighbour',
      );
    }
  });

  testWidgets('a tap during the animation still works', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    // The hotspots sit above the GIF, so an impatient tap is not swallowed.
    await tester.tap(find.bySemanticsLabel('Sign in'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('signin'), findsOneWidget);
  });

  testWidgets('continuing as a guest lands in the market', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    await tester.tap(
      find.bySemanticsLabel('Continue as a guest'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('market'), findsOneWidget);
  });
}
