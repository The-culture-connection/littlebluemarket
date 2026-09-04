import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/session.dart';

/// Every screen in the app, by route.
///
/// Rendering each one in both themes catches the failure this design is most
/// prone to: a row of text that fits at one size and overflows at another.
/// Overflow is an exception in a test, so these fail loudly rather than
/// shipping a striped banner.
const _routes = <String, String>{
  'marketplace feed': '/market',
  'search': '/market/search',
  'search results': '/market/results?q=%23PlasticFree',
  'search results (keyword)': '/market/results?q=lip%20balm',
  'post detail': '/market/post/p1',
  'post detail (service)': '/market/post/p6',
  'product details': '/market/product/p3',
  'product details (service)': '/market/product/p6',
  'all reviews': '/market/reviews/p1',
  'all reviews (single)': '/market/reviews/p5',
  'seller feed': '/market/seller/kali',
  'seller feed (buyer)': '/market/seller/dee',
  'open chatroom': '/community',
  'forums': '/community/forums',
  'forum threads': '/community/forums/f1',
  'forum threads (empty)': '/community/forums/f3',
  'thread detail': '/community/thread/t1',
  'create a forum': '/community/new-forum',
  'your profile': '/you',
  'edit profile': '/you/edit',
  'shipping': '/you/shipping',
  'messages': '/you/messages',
  'direct message': '/you/dm/kali',
};

Future<void> _pumpAt(
  WidgetTester tester,
  String location,
  Brightness brightness,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });

  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(sessionProvider.notifier).signIn();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const LittleBlueMarketApp(),
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
          await _pumpAt(tester, location, brightness);
          expect(tester.takeException(), isNull);
        });

        testWidgets('$name scrolls to the end cleanly', (tester) async {
          await _pumpAt(tester, location, brightness);

          // Content further down a screen can overflow where the top does not.
          final scrollable = find.byType(Scrollable);
          if (scrollable.evaluate().isNotEmpty) {
            await tester.drag(scrollable.first, const Offset(0, -2000));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        });
      });
    });
  }
}
