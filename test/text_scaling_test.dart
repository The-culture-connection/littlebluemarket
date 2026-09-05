import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';

/// The app clamps text scaling to 1.35, so anything that survives 2.0 here has
/// real headroom. This is the design's weak spot: it came from a fixed 390-wide
/// mockup, where a row of text either fits or it does not.
const _kBeyondClamp = 2.0;

const _routes = <String, String>{
  'marketplace feed': '/market',
  'search': '/market/search',
  'search results': '/market/results?q=%23PlasticFree',
  'collection': '/market/collection/ally-owned',
  'collection (empty)': '/market/collection/gift-guide',
  'post detail': '/market/post/post_p3',
  'post detail (review)': '/market/post/post_review_1',
  'product details': '/market/product/p3',
  'product details (service)': '/market/product/p6',
  'all reviews': '/market/reviews/p1',
  'seller feed': '/market/seller/kali',
  'open chatroom': '/community',
  'forums': '/community/forums',
  'forum threads': '/community/forums/f1',
  'thread detail': '/community/thread/t1',
  'create a forum': '/community/new-forum',
  'your profile': '/you',
  'edit profile': '/you/edit',
  'add a product': '/you/add-product',
  'edit product (missing)': '/you/edit-product/nope',
  'diagnostics (dev)': '/you/diagnostics',
  'shipping': '/you/shipping',
  'messages': '/you/messages',
  'direct message': '/you/dm/kali?to=1',
};

void main() {
  _routes.forEach((name, location) {
    testWidgets('$name survives oversized text', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = _kBeyondClamp;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      final container = ProviderContainer(retry: lbmRetry);
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

      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isNotEmpty) {
        await tester.drag(scrollable.first, const Offset(0, -3000));
        await tester.pumpAndSettle();
      }

      expect(
        tester.takeException(),
        isNull,
        reason: 'text at $_kBeyondClamp made $name overflow',
      );
    });
  });
}
