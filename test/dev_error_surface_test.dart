import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/repositories/dev_error_sink.dart';
import 'package:little_blue_market/data/repositories/repositories.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/state/dev_errors.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/widgets/dev_error_surface.dart';

/// The strip is off under test by default. These opt in.
Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });

  final container = ProviderContainer(
    retry: lbmRetry,
    overrides: [devSurfaceEnabledProvider.overrideWithValue(true)],
  );
  addTearDown(container.dispose);
  container.read(sessionProvider.notifier).signIn();
  // Subscribe the notifier before anything is reported.
  container.listen(devErrorsProvider, (_, _) {});

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const LittleBlueMarketApp(),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  setUp(() {
    DevErrorSink.enabled = true;
    DevErrorSink.clear();
  });
  tearDown(() {
    DevErrorSink.enabled = false;
    DevErrorSink.clear();
  });

  testWidgets('nothing is drawn until something fails', (tester) async {
    await _pumpApp(tester);
    expect(find.textContaining('DEV · '), findsOneWidget); // the badge only
    expect(find.text('Copy for Claude'), findsNothing);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('a reported failure shows the strip without overflow '
        '(${brightness.name})', (tester) async {
      await _pumpApp(tester, brightness: brightness);

      DevErrorSink.report(
        const BackendException(
          'diagnosticsHealthCheck failed: Admin token mint failed with 401 for a-very-long-store-domain.myshopify.com',
          code: 'internal',
        ),
        StackTrace.current,
        'callable diagnosticsHealthCheck',
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Copy for Claude'), findsOneWidget);
      expect(find.textContaining('BackendException · internal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Copy for Claude puts a report on the clipboard', (tester) async {
    await _pumpApp(tester);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    DevErrorSink.report(
      const ValidationException('Enter your claim code.'),
      null,
      'callable sellerClaimVendor',
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Copy for Claude'));
    await tester.pump();

    expect(copied, isNotNull);
    expect(copied, contains('LBM dev error'));
    expect(copied, contains('operation: callable sellerClaimVendor'));
    expect(copied, contains('type:      ValidationException'));
    expect(copied, contains('message:   Enter your claim code.'));
    expect(copied, contains('backend:   fixtures'));
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('Dismiss clears the strip', (tester) async {
    await _pumpApp(tester);
    DevErrorSink.report(const OfflineException(), null, 'firestore carts');
    await tester.pump();
    await tester.pump();
    expect(find.text('Dismiss'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(find.text('Dismiss'), findsNothing);
    expect(find.byType(DevErrorSurface), findsOneWidget);
  });

  test('formatForClaude carries every field a bug report needs', () {
    final entry = DevErrorEntry(
      report: DevErrorReport(
        error: const BackendException('boom', code: 'x'),
        operation: 'callable y',
      ),
      route: '/you/claim-shop',
      backend: 'live · little-blue-610e5',
    );
    final text = formatForClaude(entry);
    expect(text, contains('route:     /you/claim-shop'));
    expect(text, contains('backend:   live · little-blue-610e5'));
    expect(text, contains('code:      x'));
    expect(text, contains('operation: callable y'));
  });
}
