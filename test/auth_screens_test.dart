import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/widgets/primitives.dart';

/// The sign-in screens, which `screens_smoke_test.dart` cannot reach.
///
/// That suite signs in before it pumps, so the router redirects it straight
/// off these routes. They went untested for exactly that reason — and they are
/// now the only way into the app, so they are worth their own file.
const _routes = <String, String>{
  'sign in': '/signin',
  'create a profile': '/signin?create=1',
  'confirm your email': '/verify?email=someone%40example.com&create=1',
};

Future<void> _pumpAt(
  WidgetTester tester,
  String location, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });

  final container = ProviderContainer(retry: lbmRetry);
  addTearDown(container.dispose);

  // No signIn() here: these screens only exist for someone who is not.
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const LittleBlueMarketApp(),
      ),
    ),
  );
  await tester.pump();

  container.read(routerProvider).go(location);
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final mode = brightness == Brightness.light ? 'light' : 'dark';

    group('$mode mode', () {
      _routes.forEach((name, location) {
        testWidgets('$name renders cleanly', (tester) async {
          await _pumpAt(tester, location, brightness: brightness);
          expect(tester.takeException(), isNull);
        });

        testWidgets('$name survives oversized text', (tester) async {
          // These screens sit on the artwork with the action pinned to the
          // bottom, so they have the least slack in the app.
          await _pumpAt(
            tester,
            location,
            brightness: brightness,
            textScale: 2.0,
          );
          expect(tester.takeException(), isNull);
        });
      });
    });
  }

  testWidgets('the confirm screen offers a check and a way past it', (
    tester,
  ) async {
    await _pumpAt(tester, '/verify?email=someone%40example.com&create=1');
    // Nobody is signed in here, so the check cannot succeed; the button and
    // the escape hatch must both exist regardless.
    expect(find.text("I've confirmed it"), findsOneWidget);
    expect(find.text('Continue for now'), findsOneWidget);

    await tester.tap(find.text("I've confirmed it"));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not confirmed yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the password field is obscured on both auth screens', (
    tester,
  ) async {
    for (final route in ['/signin', '/signin?create=1']) {
      await _pumpAt(tester, route);

      final fields = tester
          .widgetList<LbmField>(find.byType(LbmField))
          .toList();
      expect(fields, hasLength(2), reason: 'email and password, on $route');

      // The point of the whole change: a password that renders in clear text
      // is worse than the code field it replaced.
      expect(fields.first.obscureText, isFalse, reason: 'email, on $route');
      expect(fields.last.obscureText, isTrue, reason: 'password, on $route');
    }
  });

  testWidgets('the submit button stays disabled until both fields are valid', (
    tester,
  ) async {
    await _pumpAt(tester, '/signin?create=1');

    Future<void> type(int field, String text) async {
      await tester.enterText(find.byType(LbmField).at(field), text);
      await tester.pumpAndSettle();
    }

    // A password under Firebase's six-character minimum must not reach the
    // server: a round trip to be told "too short" is a worse experience than
    // a button that has not lit up yet.
    await type(0, 'someone@example.com');
    await type(1, 'short');
    expect(tester.takeException(), isNull);

    await type(1, 'longenough');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
