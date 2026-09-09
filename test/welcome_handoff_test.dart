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
        path: '/orient',
        builder: (context, state) => const Scaffold(body: Text('orient')),
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

Finder _asset(String asset) => find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName == asset,
);

/// The still and the GIF have to occupy exactly the same box, or the artwork
/// jumps when the animation is taken away.
Rect _rectOf(WidgetTester tester, String asset) {
  final finder = _asset(asset);
  expect(finder, findsOneWidget, reason: 'expected exactly one $asset');
  return tester.getRect(finder);
}

const _labels = ['Create a Profile', 'Sign in', 'Continue as a guest'];

void main() {
  testWidgets('the still and the GIF are laid out identically', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    final box = _rectOf(tester, Fx.still);
    expect(
      box,
      _rectOf(tester, Fx.gif),
      reason:
          'If these ever differ the artwork will jump when the intro ends. '
          'Both must be drawn into the same 540x623 box.',
    );
    expect(box.width / box.height, closeTo(kWelcomeAspect, 0.01));
  });

  testWidgets('the GIF is removed once the intro is over, the still stays', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(_asset(Fx.gif), findsOneWidget);
    final before = _rectOf(tester, Fx.still);
    final buttonsBefore = [
      for (final l in _labels) tester.getRect(find.bySemanticsLabel(l)),
    ];

    await tester.pump(kIntroDuration + const Duration(milliseconds: 50));
    await tester.pump();

    expect(_asset(Fx.gif), findsNothing);
    // Nothing moves: not the artwork, not the buttons under it.
    expect(_rectOf(tester, Fx.still), before);
    expect(
      [for (final l in _labels) tester.getRect(find.bySemanticsLabel(l))],
      buttonsBefore,
    );
  });

  testWidgets('the intro is skipped entirely when it is not requested', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(playIntro: false));
    await tester.pump();
    expect(_asset(Fx.gif), findsNothing);
    expect(_asset(Fx.still), findsOneWidget);
  });

  testWidgets('the three buttons are real widgets below the artwork', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    final art = _rectOf(tester, Fx.still);
    for (final label in _labels) {
      final finder = find.bySemanticsLabel(label);
      expect(finder, findsOneWidget, reason: '$label is missing');
      final rect = tester.getRect(finder);
      expect(
        rect.top,
        greaterThanOrEqualTo(art.bottom),
        reason: '$label must sit under the artwork, never over it',
      );
      expect(
        rect.height,
        greaterThanOrEqualTo(44.0),
        reason: '$label is too small to hit comfortably',
      );
    }
    // The text is drawn by Flutter, not baked into the picture.
    for (final label in _labels) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('the buttons do not overlap each other', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    final rects = [
      for (final l in _labels) tester.getRect(find.bySemanticsLabel(l)),
    ];
    for (var i = 0; i < rects.length - 1; i++) {
      expect(rects[i].bottom, lessThanOrEqualTo(rects[i + 1].top));
    }
  });

  testWidgets('a tap during the animation still works', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('signin'), findsOneWidget);
  });

  testWidgets('Create a Profile opens the doors', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    await tester.tap(find.text('Create a Profile'));
    await tester.pumpAndSettle();
    expect(find.text('orient'), findsOneWidget);
  });

  testWidgets('continuing as a guest lands in the market', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    await tester.tap(find.text('Continue as a guest'));
    await tester.pumpAndSettle();
    expect(find.text('market'), findsOneWidget);
  });
}
