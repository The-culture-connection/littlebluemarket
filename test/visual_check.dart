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
import 'package:little_blue_market/models/feed_item.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/screens/onboarding/welcome_screen.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/theme/tokens.dart';
import 'package:little_blue_market/widgets/masonry.dart';
import 'package:little_blue_market/widgets/pins/announcement_pin.dart';
import 'package:little_blue_market/widgets/pins/cart_pin.dart';
import 'package:little_blue_market/widgets/pins/chat_pin.dart';
import 'package:little_blue_market/widgets/pins/makers_rail.dart';
import 'package:little_blue_market/widgets/pins/nudge_pin.dart';
import 'package:little_blue_market/widgets/pins/product_pin.dart';
import 'package:little_blue_market/widgets/pins/review_pin.dart';
import 'package:little_blue_market/widgets/pins/shoutout_pin.dart';
import 'package:little_blue_market/widgets/pins/thread_pin.dart';

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
        await precacheImage(
          AssetImage(asset),
          tester.element(find.byType(MaterialApp)),
        );
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
    testWidgets(
      '$name light',
      (t) => shoot(t, name, location, Brightness.light),
    );
  });
  _shots.forEach((name, location) {
    testWidgets('$name dark', (t) => shoot(t, name, location, Brightness.dark));
  });

  /// Every pin kind in one grid, which is the redesign's whole vocabulary on
  /// one page.
  ///
  /// This is what the build plan asks for as a "debug page": the plan wanted
  /// an unrouted screen behind `kDebugMode`, and this file is the project's
  /// existing way of putting a thing in front of human eyes without adding a
  /// screen nobody ships. The grid itself lands in `feed` at Phase 2.
  Future<void> shootPins(WidgetTester tester, Brightness brightness) async {
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(retry: lbmRetry);
    addTearDown(container.dispose);
    container.listen(sessionProvider, (_, _) {}, fireImmediately: true);
    container.read(sessionProvider.notifier).signIn();

    final withPhoto = Fx.products.values.where((p) => p.hasPhoto).toList();
    final sellers = Fx.people.values.where((p) => p.isSeller).toList();
    final me = Fx.me;

    ListingPost listing(Product p) => ListingPost(
      id: 'post_${p.id}',
      authorId: p.sellerId,
      createdAt: DateTime(2026, 9, 1),
      tags: const ['#Handmade'],
      likeCount: 0,
      commentCount: 3,
      likedByMe: false,
      product: p,
    );

    final items = <Widget>[
      AnnouncementPin(
        item: AnnouncementItem(
          Announcement(
            id: 'a1',
            title: 'Six new makers joined this week',
            body: 'Ceramics, two bakers and a bookbinder.',
            audience: AnnouncementAudience.all,
            route: '/market',
            createdAt: DateTime(2026, 9, 6),
          ),
          hero: true,
        ),
      ),
      ProductPin.of(listing(withPhoto[0]), proof: true),
      ReviewPin.of(
        ReviewPost(
          id: 'r1',
          authorId: me.id,
          createdAt: DateTime(2026, 9, 2),
          tags: const [],
          likeCount: 0,
          commentCount: 0,
          likedByMe: false,
          productId: withPhoto[0].id,
          rating: 5,
          text: 'Smells like July. My skin stopped fighting me.',
          purchaseId: 'o1',
        ),
      ),
      ProductPin.of(listing(withPhoto[1 % withPhoto.length])),
      ThreadPin(
        item: ThreadItem(
          Fx.threads.first,
          forumName: 'Packaging',
          topReply: Fx.comments.first,
          repliers: Fx.people.values.take(3).toList(),
        ),
      ),
      ChatPin(
        item: ChatItem(
          ChatMoment(
            latest: [
              Message(
                id: 'm1',
                conversationId: Message.chatroomId,
                authorId: me.id,
                createdAt: DateTime(2026, 9, 5, 9),
                text: 'Anyone doing the Ypsi market on Saturday?',
              ),
              Message(
                id: 'm2',
                conversationId: Message.chatroomId,
                authorId: sellers.first.id,
                createdAt: DateTime(2026, 9, 5, 9, 4),
                text: "I'll be there, two tables down from the bakery.",
              ),
            ],
            lastHourCount: 14,
          ),
        ),
      ),
      CartPin.of(
        CartPost(
          id: 'c1',
          authorId: me.id,
          createdAt: DateTime(2026, 9, 3),
          tags: const [],
          likeCount: 0,
          commentCount: 0,
          likedByMe: false,
          caption: 'Gift run for my sister',
          items: [
            for (var i = 0; i < 7; i++)
              CartPostItem(
                productId: 'p$i',
                title: 'Thing $i',
                sellerId: sellers.first.id,
                priceCents: 1200,
                imageUrl: withPhoto[i % withPhoto.length].imageUrls.firstOrNull,
              ),
          ],
        ),
        onAddAll: () {},
      ),
      const NudgePin(item: NudgeItem(NudgeKind.reviewDelivered, id: 'o1')),
      ShoutoutPin.of(
        ShoutoutPost(
          id: 's1',
          authorId: me.id,
          createdAt: DateTime(2026, 9, 4),
          tags: const [],
          likeCount: 0,
          commentCount: 0,
          likedByMe: false,
          text: 'Everything this shop makes smells like a good memory.',
          aboutSellerId: sellers.first.id,
        ),
      ),
      MakersRail(item: MakersRailItem(sellers.take(5).toList())),
      ProductPin.of(listing(withPhoto[2 % withPhoto.length])),
      const NudgePin(item: NudgeItem(NudgeKind.sayHi)),
    ];
    final wide = [
      for (final item in items)
        item is MakersRail ||
            (item is AnnouncementPin && item.item.hero),
    ];

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildLbmTheme(brightness),
          home: Scaffold(
            backgroundColor: (brightness == Brightness.light
                    ? LbmColors.light
                    : LbmColors.dark)
                .paper,
            body: SafeArea(
              child: LbmMasonry(wide: wide, bottom: 20, children: items),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      for (final asset in Fx.demoPhotoAssets) {
        await precacheImage(
          AssetImage(asset),
          tester.element(find.byType(MaterialApp)),
        );
      }
    });
    await tester.pumpAndSettle();

    final mode = brightness == Brightness.light ? 'light' : 'dark';
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$mode-pins.png'),
    );
  }

  testWidgets('pins light', (t) => shootPins(t, Brightness.light));
  testWidgets('pins dark', (t) => shootPins(t, Brightness.dark));

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
