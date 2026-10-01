import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/product_art.dart';

/// The product page's Shipping, Pickup and Returns tiles, and its photo
/// swipe hint (Grace, 2026-09-30).
Future<ProviderContainer> _pumpProduct(WidgetTester tester, String id) async {
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
  container.read(routerProvider).go('/market/product/$id');
  await tester.pumpAndSettle();
  return container;
}

void main() {
  swipeHintTests();

  test('each tile opens the chat with its own question', () {
    expect(
      openingQuestion(DmTopic.shipping, 'Lip Balm'),
      'Hi! How does shipping work for the Lip Balm?',
    );
    expect(openingQuestion(DmTopic.pickup, 'Lip Balm'), contains('pick up'));
    expect(openingQuestion(DmTopic.returns, 'Lip Balm'), contains('returns'));
    expect(openingQuestion(null, 'Lip Balm'), contains('still available'));
  });

  testWidgets('tapping Shipping opens the seller chat about this product', (
    tester,
  ) async {
    await _pumpProduct(tester, 'p1');
    final tile = find.text('Shipping');
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();

    // The seller's thread, with the question already in the message box.
    expect(find.text('Kali Brooks'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is EditableText &&
            w.controller.text ==
                'Hi! How does shipping work for the Cocoa Mint Lip Balm?',
      ),
      findsOneWidget,
    );
  });
}

Product _gallery(List<String> imageUrls) => Product(
  id: 'g1',
  title: 'Two photos',
  priceCents: 1000,
  sellerId: 'kali',
  tags: [],
  rating: 0,
  ratingCount: 0,
  type: 'Food',
  description: '',
  cityState: '',
  saveCount: 0,
  commentCount: 0,
  soldCount: 0,
  imageUrls: imageUrls,
);

Future<void> _pumpGallery(WidgetTester tester, Product product) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildLbmTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(width: 390, child: ProductGallery(product: product)),
        ),
      ),
    );

void swipeHintTests() {
  testWidgets('more than one photo: a swipe hint shows, then goes', (
    tester,
  ) async {
    await _pumpGallery(
      tester,
      _gallery(const ['asset://missing-one.png', 'asset://missing-two.png']),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
  });

  testWidgets('one photo: no hint', (tester) async {
    await _pumpGallery(tester, _gallery(const ['asset://missing-one.png']));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
  });
}
