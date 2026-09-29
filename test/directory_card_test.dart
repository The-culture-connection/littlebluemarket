import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/screens/market/directory_listing_screen.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/pins/directory_card.dart';
import 'package:little_blue_market/widgets/product_art.dart';

/// Grace's five requirements for the directory business card (2026-09-28):
/// the photo on the left, two lines of description, then the tags, then the
/// town, one Visit button to the business's own website, and a tap anywhere
/// else opening the listing's page in the app.

const _listing = DirectoryListing(
  id: '9001',
  ownerUid: 'dee',
  title: 'Sticker Punks Print Shop',
  status: 'publish',
  link: 'https://example.com/directory-vendors/listing/sticker-punks/',
  website: 'stickerpunks.example.com',
  city: 'Ellington',
  state: 'CT',
  locationLabel: 'Ellington, CT',
  categories: ['Print shop'],
  // Two identity tags out of order, so the card has to put them first.
  tags: ['Stickers', 'BIPOC-Owned', 'Books', 'LGBTQ+ Owned', 'Connecticut'],
  imageUrl: 'asset://assets/images/product-lipbalm.jpg',
  description:
      'Small, queer, interracial owned printshop specializing in custom '
      'stickers, posters, bookmarks, keychains, notepads and more. We focus '
      'on producing high-quality custom products with top-notch customer '
      'service and fast turnaround.',
);

/// The card as it sits in the feed: a 390 phone, 10 of gutter each side.
Widget _host(
  Widget child, {
  List<Uri>? opened,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      externalLauncherProvider.overrideWithValue((uri) async {
        opened?.add(uri);
        return true;
      }),
    ],
    child: MaterialApp(
      theme: buildLbmTheme(brightness),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 40),
            child: child,
          ),
        ),
      ),
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('what the card shows', () {
    testWidgets('title, a description clamped to two lines, two tags and +N', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _host(const DirectoryBusinessCard(listing: _listing)),
      );

      expect(find.text('Sticker Punks Print Shop'), findsOneWidget);

      final description = tester.widget<Text>(
        find.byKey(const ValueKey('directory-card-description')),
      );
      expect(description.maxLines, 2);
      expect(description.overflow, TextOverflow.ellipsis);

      // Identity first, in the order the listing has them, then "+N" for
      // everything else.
      expect(find.text('BIPOC-Owned'), findsOneWidget);
      expect(find.text('LGBTQ+ Owned'), findsOneWidget);
      expect(find.text('Stickers'), findsNothing);
      expect(find.text('+3'), findsOneWidget);

      expect(find.text('Ellington, CT'), findsOneWidget);
      expect(find.text('Visit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the left circle is the listing photo', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _host(const DirectoryBusinessCard(listing: _listing)),
      );

      final photo = tester.widget<ProductPhoto>(find.byType(ProductPhoto));
      expect(photo.url, _listing.imageUrl);
    });

    testWidgets('no photo: the initials on a tint instead', (tester) async {
      _phone(tester);
      const bare = DirectoryListing(
        id: '9002',
        ownerUid: '',
        title: 'Found House Ceramics',
        status: 'publish',
        link: '',
      );
      await tester.pumpWidget(
        _host(const DirectoryBusinessCard(listing: bare)),
      );

      expect(find.byType(ProductPhoto), findsNothing);
      expect(find.text('FH'), findsOneWidget);
    });

    test('initials skip punctuation words', () {
      expect(ListingInitials.of('Cedar & Salt Bath Co.'), 'CS');
      expect(ListingInitials.of(''), '?');
    });

    testWidgets('location falls back to city, state', (tester) async {
      _phone(tester);
      const noLabel = DirectoryListing(
        id: '9003',
        ownerUid: '',
        title: 'Brightside Bookkeeping',
        status: 'publish',
        link: '',
        city: 'Nashville',
        state: 'TN',
      );
      await tester.pumpWidget(
        _host(const DirectoryBusinessCard(listing: noLabel)),
      );
      expect(find.text('Nashville, TN'), findsOneWidget);
    });
  });

  group('the one button', () {
    testWidgets('Visit opens the business website, not the listing', (
      tester,
    ) async {
      _phone(tester);
      final opened = <Uri>[];
      await tester.pumpWidget(
        _host(const DirectoryBusinessCard(listing: _listing), opened: opened),
      );

      await tester.tap(find.text('Visit'));
      await tester.pumpAndSettle();

      expect(opened, [_listing.websiteUri]);
      expect(opened.single.toString(), 'https://stickerpunks.example.com');
    });

    testWidgets('no website: "Listing" opens the littlebluecart.com page', (
      tester,
    ) async {
      _phone(tester);
      final opened = <Uri>[];
      const noSite = DirectoryListing(
        id: '9004',
        ownerUid: '',
        title: 'The Mend Shop',
        status: 'publish',
        link: 'https://example.com/directory-vendors/listing/the-mend-shop/',
      );
      await tester.pumpWidget(
        _host(const DirectoryBusinessCard(listing: noSite), opened: opened),
      );

      expect(find.text('Visit'), findsNothing);
      expect(find.text('Listing'), findsOneWidget);
      expect(find.byIcon(Icons.north_east_rounded), findsOneWidget);

      await tester.tap(find.text('Listing'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), noSite.link);
    });

    testWidgets('neither: no button at all', (tester) async {
      _phone(tester);
      const nothing = DirectoryListing(
        id: '9005',
        ownerUid: '',
        title: 'Nowhere Yet',
        status: 'publish',
        link: '',
      );
      await tester.pumpWidget(
        _host(const DirectoryBusinessCard(listing: nothing)),
      );

      expect(find.text('Visit'), findsNothing);
      expect(find.text('Listing'), findsNothing);
    });
  });

  group('tapping the card', () {
    testWidgets('opens /market/directory-listing/<id>', (tester) async {
      _phone(tester);
      final opened = <Uri>[];
      final router = GoRouter(
        initialLocation: '/market',
        routes: [
          GoRoute(
            path: '/market',
            builder: (context, state) => const Scaffold(
              body: Center(child: DirectoryBusinessCard(listing: _listing)),
            ),
            routes: [
              GoRoute(
                path: 'directory-listing/:id',
                builder: (context, state) => Text(
                  'listing ${state.pathParameters['id']} at ${state.uri.path}',
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            externalLauncherProvider.overrideWithValue((uri) async {
              opened.add(uri);
              return true;
            }),
          ],
          child: MaterialApp.router(
            theme: buildLbmTheme(Brightness.light),
            routerConfig: router,
          ),
        ),
      );

      await tester.tap(find.text('Sticker Punks Print Shop'));
      await tester.pumpAndSettle();

      // Read off the pushed page's own state: a push does not change the
      // delegate's current configuration.
      expect(
        find.text('listing 9001 at /market/directory-listing/9001'),
        findsOneWidget,
      );
      // The card is not the website.
      expect(opened, isEmpty);
    });

    testWidgets('in the real app, the feed card opens the listing page', (
      tester,
    ) async {
      _phone(tester);
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
      container.read(routerProvider).go('/market');
      await tester.pumpAndSettle();

      final card = find.byType(DirectoryBusinessCard);
      await tester.scrollUntilVisible(
        card,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Field Trips Travel & Vacations').first);
      await tester.pumpAndSettle();

      final screen = find.byType(DirectoryListingScreen);
      expect(screen, findsOneWidget);
      expect(
        GoRouterState.of(tester.element(screen)).uri.path,
        '/market/directory-listing/47494',
      );
      expect(find.text('Visit website'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('text scale 2.0', () {
    for (final brightness in Brightness.values) {
      testWidgets('no overflow in ${brightness.name} mode', (tester) async {
        _phone(tester);
        await tester.pumpWidget(
          _host(
            const DirectoryBusinessCard(listing: _listing),
            brightness: brightness,
            textScale: 2,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // What gives way first: the second line of blurb and the "+N".
        final description = tester.widget<Text>(
          find.byKey(const ValueKey('directory-card-description')),
        );
        expect(description.maxLines, 1);
        expect(find.text('+3'), findsNothing);
      });
    }
  });

  group('pressing', () {
    testWidgets('press and hold wiggles, and settles back', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _host(const DirectoryBusinessCard(listing: _listing)),
      );

      Matrix4 lean() => tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(DirectoryBusinessCard),
              matching: find.byType(Transform),
            ),
          )
          .map((t) => t.transform)
          .firstWhere((m) => m.entry(0, 1) != 0);

      final rest = lean().entry(0, 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Sticker Punks Print Shop')),
      );
      // The first frame only starts the animation's clock.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(lean().entry(0, 1), isNot(closeTo(rest, 1e-6)));

      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(lean().entry(0, 1), closeTo(rest, 1e-6));
    });
  });
}
