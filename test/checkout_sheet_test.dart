import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/checkout_launcher.dart';
import 'package:little_blue_market/widgets/sheets.dart';

/// The last hop of buying: the sheet hands the checkout URL to a launcher.
/// A widget test cannot open a browser, so the launcher is a recorder.
final _handoff = CheckoutHandoff(
  cartId: 'gid://shopify/Cart/abc',
  webUrl: Uri.parse('https://example.myshopify.com/checkouts/abc'),
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  CheckoutLauncher launcher,
) async {
  // A phone-sized surface. The default 800x600 test screen is shorter than
  // the sheet, so the buttons land below the bottom edge and a tap on them
  // hits nothing.
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [checkoutLauncherProvider.overrideWithValue(launcher)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLbmTheme(Brightness.light),
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showCheckoutSheet(context, ref, _handoff),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('Open checkout hands the URL to the launcher and marks pending', (
    tester,
  ) async {
    final launcher = RecordingCheckoutLauncher();
    final container = await _pump(tester, launcher);

    expect(find.text('Finish in checkout'), findsOneWidget);
    await tester.tap(find.text('Open checkout'));
    await tester.pumpAndSettle();

    expect(launcher.opened, [_handoff.webUrl]);
    expect(container.read(checkoutPendingProvider), isTrue);
    expect(
      find.text('Finish in checkout'),
      findsNothing,
      reason: 'sheet closed',
    );
  });

  testWidgets('a launcher that cannot open offers the link instead', (
    tester,
  ) async {
    final launcher = RecordingCheckoutLauncher(succeeds: false);
    final container = await _pump(tester, launcher);

    await tester.tap(find.text('Open checkout'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open checkout on this phone.'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(container.read(checkoutPendingProvider), isFalse);
  });

  testWidgets('Keep shopping opens nothing', (tester) async {
    final launcher = RecordingCheckoutLauncher();
    await _pump(tester, launcher);
    await tester.tap(find.text('Keep shopping'));
    await tester.pumpAndSettle();
    expect(launcher.opened, isEmpty);
  });
}
