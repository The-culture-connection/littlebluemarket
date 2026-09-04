// A visual reference, not part of the test suite.
//
// Renders every screen in both themes with the real bundled fonts and writes
// them to test/shots/. Deliberately named without the `_test` suffix so
// `flutter test` never picks it up: these are screenshots for eyeballing, and
// rendering differs enough between machines that asserting on them would just
// produce false failures.
//
// Regenerate with:
//   flutter test test/visual_check.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/screens/onboarding/welcome_screen.dart';

const _fonts = <String, List<String>>{
  'Fraunces': [
    'assets/fonts/Fraunces-500.ttf',
    'assets/fonts/Fraunces-600.ttf',
    'assets/fonts/Fraunces-700.ttf',
    'assets/fonts/Fraunces-500Italic.ttf',
    'assets/fonts/Fraunces-600Italic.ttf',
  ],
  'Nunito': [
    'assets/fonts/Nunito-400.ttf',
    'assets/fonts/Nunito-500.ttf',
    'assets/fonts/Nunito-600.ttf',
    'assets/fonts/Nunito-700.ttf',
    'assets/fonts/Nunito-800.ttf',
    'assets/fonts/Nunito-400Italic.ttf',
  ],
};

/// The icon font, taken from the SDK cache so the captures show real glyphs
/// rather than tofu boxes. `flutter test` sets FLUTTER_ROOT for us.
File? _materialIconsFile() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return null;
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  return file.existsSync() ? file : null;
}

Future<void> _loadFonts() async {
  for (final entry in _fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }

  final iconFile = _materialIconsFile();
  if (iconFile != null) {
    final loader = FontLoader('MaterialIcons');
    loader.addFont(
      Future.value(iconFile.readAsBytesSync().buffer.asByteData()),
    );
    await loader.load();
  }
}

const _shots = <String, String>{
  'feed': '/market',
  'post': '/market/post/p3',
  'product': '/market/product/p1',
  'search': '/market/search',
  'results': '/market/results?q=%23PlasticFree',
  'reviews': '/market/reviews/p1',
  'seller': '/market/seller/kali',
  'chatroom': '/community',
  'forums': '/community/forums',
  'thread': '/community/thread/t1',
  'profile': '/you',
  'shipping': '/you/shipping',
  'messages': '/you/messages',
  'dm': '/you/dm/kali?to=1',
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
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

    // Let the bundled photographs decode.
    await tester.runAsync(() async {
      for (final asset in Fx.demoPhotoAssets) {
        await precacheImage(AssetImage(asset), tester.element(find.byType(MaterialApp)));
      }
      await precacheImage(
        const AssetImage(Fx.cart),
        tester.element(find.byType(MaterialApp)),
      );
    });
    await tester.pumpAndSettle();

    final mode = brightness == Brightness.light ? 'light' : 'dark';
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$mode-$name.png'),
    );
  }

  _shots.forEach((name, location) {
    testWidgets('$name light', (t) => shoot(t, name, location, Brightness.light));
  });
  _shots.forEach((name, location) {
    testWidgets('$name dark', (t) => shoot(t, name, location, Brightness.dark));
  });

  testWidgets('welcome resting frame', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: WelcomeScreen(playIntro: false)),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage(Fx.still),
        tester.element(find.byType(MaterialApp)),
      );
    });
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/welcome.png'),
    );
  });
}

