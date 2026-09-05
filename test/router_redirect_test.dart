import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';

/// Where the app lands on a cold start, by who the phone already knows.
///
/// Firebase remembers the sign-in between launches; the router has to honour
/// that or every launch opens on the Sign in button and reads as "it forgot
/// me".
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required void Function(ProviderContainer) before,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(retry: lbmRetry);
  addTearDown(container.dispose);
  before(container);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const LittleBlueMarketApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
  return container;
}

String _location(ProviderContainer c) =>
    c.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

void main() {
  testWidgets('a signed-in member skips Welcome and opens on the Market', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      before: (c) => c.read(sessionProvider.notifier).signIn(),
    );
    await tester.pumpAndSettle();
    expect(_location(container), '/market');
  });

  testWidgets('a returning guest also skips Welcome', (tester) async {
    final container = await _pump(
      tester,
      before: (c) => c.read(sessionProvider.notifier).continueAsGuest(),
    );
    await tester.pumpAndSettle();
    expect(_location(container), '/market');
  });

  testWidgets('a stranger still gets the Welcome screen', (tester) async {
    final container = await _pump(tester, before: (_) {});
    await tester.pump(const Duration(seconds: 5));
    expect(_location(container), '/');
  });
}
