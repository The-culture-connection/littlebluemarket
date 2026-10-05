import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/models/feed_item.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/state/session.dart';
import 'package:little_blue_market/state/tips.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/theme/tokens.dart';
import 'package:little_blue_market/widgets/cart_pill.dart';
import 'package:little_blue_market/widgets/filter_chips.dart';
import 'package:little_blue_market/widgets/lbm_toast.dart';
import 'package:little_blue_market/widgets/pins/announcement_pin.dart';
import 'package:little_blue_market/widgets/pins/cart_pin.dart';
import 'package:little_blue_market/widgets/pins/chat_pin.dart';
import 'package:little_blue_market/widgets/pins/makers_rail.dart';
import 'package:little_blue_market/widgets/pins/nudge_pin.dart';
import 'package:little_blue_market/widgets/pins/product_pin.dart';
import 'package:little_blue_market/widgets/pins/review_pin.dart';
import 'package:little_blue_market/widgets/pins/shoutout_pin.dart';
import 'package:little_blue_market/widgets/pins/thread_pin.dart';
import 'package:little_blue_market/widgets/primitives.dart';
import 'package:little_blue_market/widgets/product_art.dart';

/// The tip shown in front of the very first add to cart.
const kCartTip = Tips.cartIsTheLike;

/// A column in the two-column grid on a 390-wide phone.
const _pinWidth = 180.0;

/// One of the bundled demo photographs, as a listing carries it.
const _photo = 'asset://assets/images/product-lipbalm.jpg';

Widget _framed(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: buildLbmTheme(brightness),
    home: Scaffold(
      body: Center(child: SizedBox(width: _pinWidth, child: child)),
    ),
  );
}

/// Pumps [child] and lets the bundled photographs actually decode, which is
/// the only way the natural aspect is ever known.
Future<void> pumpDecoded(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(child);
  await tester.runAsync(() async {
    for (final asset in Fx.demoPhotoAssets) {
      await precacheImage(
        AssetImage(asset),
        tester.element(find.byType(MaterialApp)),
      );
    }
  });
  await tester.pumpAndSettle();
}

double _aspectOf(WidgetTester tester) {
  final r = tester.getRect(find.byType(NaturalPhoto));
  return r.width / r.height;
}

/// A screen whose only job is to have a button that raises a toast.
Widget _toastHost({
  String title = 'In your little blue cart',
  String? subtitle,
  String? thumbnailUrl,
  (String, VoidCallback)? action,
}) {
  return MaterialApp(
    theme: buildLbmTheme(Brightness.light),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => LbmToast.show(
              context,
              title: title,
              subtitle: subtitle,
              thumbnailUrl: thumbnailUrl,
              action: action,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
}

/// Puts one [CartPill] on screen against the fixture backend.
///
/// A member by default; pass `guest: true` to leave the session without a
/// profile, which is what the gate keys off.
Future<ProviderContainer> _pumpPill(
  WidgetTester tester, {
  required String productId,
  bool guest = false,
  bool tipSeen = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(retry: lbmRetry);
  addTearDown(container.dispose);
  // Something has to hold the session open. In the running app the router
  // watches it; here nothing does, and an unwatched provider is disposed the
  // moment it is read, taking the signed-in fixture user with it.
  container.listen(sessionProvider, (_, _) {}, fireImmediately: true);
  if (!guest) container.read(sessionProvider.notifier).signIn();
  // The cart tip is a one-time dialog in front of the first add; most of
  // these tests are about what happens after it.
  if (tipSeen) await container.read(tipsProvider.notifier).markSeen(kCartTip);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLbmTheme(Brightness.light),
        home: Scaffold(
          body: Center(child: CartPill(productId: productId)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Lets a raised toast run out, so no timer outlives the test.
Future<void> _letToastGo(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

List<CartLine> _lines(ProviderContainer container) =>
    container.read(cartProvider).value?.lines ?? const [];

/// Puts one pin on screen at the width of a real column, with the fixture
/// backend behind it so avatars and prices resolve.
///
/// The height is unbounded, exactly as the masonry grid leaves it: a pin that
/// only fits because the test gave it 844 pixels is not a pin that fits.
Future<ProviderContainer> _pumpPin(
  WidgetTester tester,
  Widget pin, {
  Brightness brightness = Brightness.light,
  double width = _pinWidth,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(retry: lbmRetry);
  addTearDown(container.dispose);
  container.listen(sessionProvider, (_, _) {}, fireImmediately: true);
  container.read(sessionProvider.notifier).signIn();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLbmTheme(brightness),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: width, child: pin),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Renders [build]'s pin at twice the clamped text scale, in both themes, and
/// fails if anything overflows.
Future<void> _survivesBigText(
  WidgetTester tester,
  Widget Function() build, {
  double width = _pinWidth,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = 2.0;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  for (final brightness in Brightness.values) {
    await _pumpPin(tester, build(), brightness: brightness, width: width);
    expect(
      tester.takeException(),
      isNull,
      reason: 'overflowed at 2.0 in $brightness',
    );
  }
}

ListingPost _listing(Product product, {int comments = 2}) => ListingPost(
  id: 'post_${product.id}',
  authorId: product.sellerId,
  createdAt: DateTime(2026, 9, 1),
  tags: const ['#Handmade'],
  likeCount: 0,
  commentCount: comments,
  likedByMe: false,
  product: product,
);

void main() {
  final withPhoto = Fx.products.values.firstWhere((p) => p.hasPhoto);
  final seller = Fx.people[withPhoto.sellerId]!;

  group('ProductPin', () {
    testWidgets('the photo is the card, with a price and a cart pill', (
      tester,
    ) async {
      await _pumpPin(tester, ProductPin.of(_listing(withPhoto)));

      expect(find.text(withPhoto.title), findsOneWidget);
      expect(find.text(Fmt.money(withPhoto.priceCents)), findsOneWidget);
      expect(find.byType(CartPill), findsOneWidget);
      expect(find.byType(NaturalPhoto), findsOneWidget);
      // The maker, by the name people recognise at 180 wide.
      expect(
        find.text(seller.name.split(RegExp(r'\s+')).first),
        findsOneWidget,
      );
    });

    testWidgets('says how many carted it only when asked to', (tester) async {
      await _pumpPin(tester, ProductPin.of(_listing(withPhoto)));
      expect(find.textContaining('carted'), findsNothing);

      await _pumpPin(tester, ProductPin.of(_listing(withPhoto), proof: true));
      expect(
        find.text('${withPhoto.saveCount} carted'),
        findsOneWidget,
        reason: 'the count comes from saveCount, not from a guess',
      );
    });

    testWidgets('survives 2.0 text in both themes', (tester) async {
      await _survivesBigText(
        tester,
        () => ProductPin.of(_listing(withPhoto), proof: true),
      );
    });
  });

  group('ReviewPin', () {
    ReviewPost review() => ReviewPost(
      id: 'r1',
      authorId: Fx.meId,
      createdAt: DateTime(2026, 9, 2),
      tags: const [],
      likeCount: 0,
      commentCount: 0,
      likedByMe: false,
      productId: withPhoto.id,
      rating: 5,
      text: 'Smells like July. My skin stopped fighting me.',
      purchaseId: 'o1',
    );

    testWidgets('quotes the review and shows its stars', (tester) async {
      await _pumpPin(tester, ReviewPin.of(review()));

      expect(
        find.textContaining('Smells like July'),
        findsOneWidget,
      );
      expect(find.byType(Stars), findsOneWidget);
      // A review only exists for a recorded purchase, so it can say so.
      expect(find.textContaining('bought it'), findsOneWidget);
    });

    testWidgets('survives 2.0 text in both themes', (tester) async {
      await _survivesBigText(tester, () => ReviewPin.of(review()));
    });
  });

  group('CartPin', () {
    CartPost cart({required int items}) => CartPost(
      id: 'c1',
      authorId: Fx.meId,
      createdAt: DateTime(2026, 9, 3),
      tags: const [],
      likeCount: 0,
      commentCount: 0,
      likedByMe: false,
      caption: 'Gift run for my sister',
      items: [
        for (var i = 0; i < items; i++)
          CartPostItem(
            productId: 'p$i',
            title: 'Thing $i',
            sellerId: seller.id,
            priceCents: 1200,
            imageUrl: withPhoto.imageUrls.firstOrNull,
          ),
      ],
    );

    testWidgets('shows the snapshot, and counts the ones it cannot fit', (
      tester,
    ) async {
      await _pumpPin(tester, CartPin.of(cart(items: 7)));

      expect(find.text('Gift run for my sister'), findsOneWidget);
      expect(find.text('7 things'), findsOneWidget);
      // Three tiles and a "+4", never seven tiles in a 180-wide column.
      expect(find.text('+4'), findsOneWidget);
    });

    testWidgets('four or fewer items need no overflow tile', (tester) async {
      await _pumpPin(tester, CartPin.of(cart(items: 4)));
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('offers Add all only when the feed wires it', (tester) async {
      await _pumpPin(tester, CartPin.of(cart(items: 3)));
      expect(find.text('Add all'), findsNothing);

      var added = 0;
      await _pumpPin(
        tester,
        CartPin.of(cart(items: 3), onAddAll: () => added++),
      );
      expect(find.text('Add all'), findsOneWidget);
      await tester.tap(find.text('Add all'));
      expect(added, 1);
    });

    testWidgets('survives 2.0 text in both themes', (tester) async {
      await _survivesBigText(tester, () => CartPin.of(cart(items: 7)));
    });
  });

  group('ShoutoutPin', () {
    ShoutoutPost shoutout() => ShoutoutPost(
      id: 's1',
      authorId: Fx.meId,
      createdAt: DateTime(2026, 9, 4),
      tags: const [],
      likeCount: 0,
      commentCount: 0,
      likedByMe: false,
      text: 'Everything this shop makes smells like a good memory.',
      aboutSellerId: seller.id,
    );

    testWidgets('is type on a gradient, credited to whoever said it', (
      tester,
    ) async {
      await _pumpPin(tester, ShoutoutPin.of(shoutout()));

      expect(find.textContaining('a good memory'), findsOneWidget);
      expect(find.text('by ${Fx.me.name}'), findsOneWidget);
      expect(find.text('SHOUTOUT'), findsOneWidget);
    });

    testWidgets('survives 2.0 text in both themes', (tester) async {
      await _survivesBigText(tester, () => ShoutoutPin.of(shoutout()));
    });
  });

  group('ThreadPin', () {
    final thread = Fx.threads.first;
    ThreadItem item({bool joined = false, bool reply = true}) => ThreadItem(
      thread,
      forumName: 'Packaging',
      topReply: reply ? Fx.comments.first : null,
      repliers: Fx.people.values.take(3).toList(),
      joined: joined,
    );

    testWidgets('asks the question and shows who is in it', (tester) async {
      await _pumpPin(tester, ThreadPin(item: item()));

      expect(find.text(thread.title), findsOneWidget);
      expect(find.text('FORUM · PACKAGING'), findsOneWidget);
      expect(
        find.text(
          '${thread.commentCount} '
          '${thread.commentCount == 1 ? 'reply' : 'replies'}',
        ),
        findsOneWidget,
      );
      expect(find.text('Join in'), findsOneWidget);
    });

    testWidgets('says Joined once you are in', (tester) async {
      await _pumpPin(tester, ThreadPin(item: item(joined: true)));
      expect(find.text('Joined'), findsOneWidget);
      expect(find.text('Join in'), findsNothing);
    });

    testWidgets('survives 2.0 text in both themes', (tester) async {
      await _survivesBigText(tester, () => ThreadPin(item: item()));
    });
  });

  group('ChatPin', () {
    ChatItem moment({int lastHour = 14, int messages = 2}) => ChatItem(
      ChatMoment(
        latest: [
          for (var i = 0; i < messages; i++)
            Message(
              id: 'm$i',
              conversationId: Message.chatroomId,
              authorId: Fx.meId,
              createdAt: DateTime(2026, 9, 5, 9, i),
              text: 'Message number $i in the open room',
            ),
        ],
        lastHourCount: lastHour,
      ),
    );

    testWidgets('carries the last messages and how busy the hour was', (
      tester,
    ) async {
      await _pumpPin(tester, ChatPin(item: moment()));

      expect(find.textContaining('Message number 0'), findsOneWidget);
      expect(find.textContaining('Message number 1'), findsOneWidget);
      expect(find.text('14 in the last hour'), findsOneWidget);
      expect(find.text('Jump in'), findsOneWidget);
    });

    testWidgets('never claims how many people are here', (tester) async {
      await _pumpPin(tester, ChatPin(item: moment()));

      // There is no presence data anywhere in this system. The mockup's
      // "23 here now" is a drawing, and a pin must not print it.
      expect(find.textContaining('here now'), findsNothing);
      expect(find.textContaining('here'), findsNothing);
    });

    testWidgets('a quiet room says so instead of inventing activity', (
      tester,
    ) async {
      await _pumpPin(tester, ChatPin(item: moment(lastHour: 0, messages: 0)));

      expect(find.text('Quiet in here'), findsOneWidget);
      expect(find.textContaining('in the last hour'), findsNothing);
    });

    testWidgets('stays a dark tile in dark mode', (tester) async {
      // It used to take `context.c.ink`, which inverts: in dark mode the tile
      // came out near-white and its white type disappeared.
      for (final brightness in Brightness.values) {
        await _pumpPin(tester, ChatPin(item: moment()), brightness: brightness);

        final box = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(ChatPin),
                matching: find.byType(Container),
              )
              .first,
        );
        final fill = (box.decoration! as BoxDecoration).color;

        expect(fill, LbmConst.chatInk, reason: 'fixed, not themed');
        expect(
          fill,
          isNot(LbmColors.dark.ink),
          reason: 'the dark palette ink is nearly white',
        );
        expect(
          tester.widget<Text>(find.text('Jump in')).style?.color,
          LbmConst.chatInk,
          reason: 'a white pill needs dark type in both themes',
        );
      }
    });

    testWidgets('survives 2.0 text in both themes', (tester) async {
      await _survivesBigText(tester, () => ChatPin(item: moment()));
    });
  });

  group('AnnouncementPin', () {
    final announcement = Announcement(
      id: 'a1',
      title: 'Six new makers joined this week',
      body: 'Ceramics, two bakers and a bookbinder.',
      audience: AnnouncementAudience.all,
      route: '/market',
      createdAt: DateTime(2026, 9, 6),
    );

    testWidgets('the hero is the one headline on the screen', (tester) async {
      await _pumpPin(
        tester,
        AnnouncementPin(
          item: AnnouncementItem(announcement, hero: true),
        ),
        width: 370,
      );

      expect(find.text(announcement.title), findsOneWidget);
      expect(find.text(announcement.body), findsOneWidget);
      expect(find.text('LITTLE BLUE MARKET'), findsOneWidget);

      final title = tester.widget<Text>(find.text(announcement.title));
      expect(title.style?.fontSize, LbmText.headline.fontSize);
    });

    testWidgets('a later one is smaller and fits a column', (tester) async {
      await _pumpPin(
        tester,
        AnnouncementPin(item: AnnouncementItem(announcement)),
      );

      final title = tester.widget<Text>(find.text(announcement.title));
      expect(title.style?.fontSize, lessThan(LbmText.headline.fontSize!));
    });

    testWidgets('only the hero spans both columns', (tester) async {
      expect(AnnouncementItem(announcement, hero: true).isWide, isTrue);
      expect(AnnouncementItem(announcement).isWide, isFalse);
    });

    testWidgets('survives 2.0 text in both themes', (tester) async {
      await _survivesBigText(
        tester,
        () => AnnouncementPin(item: AnnouncementItem(announcement)),
      );
    });
  });

  group('NudgePin', () {
    testWidgets('each kind says its own thing', (tester) async {
      for (final kind in NudgeKind.values) {
        await _pumpPin(tester, NudgePin(item: NudgeItem(kind)));
        expect(find.text(NudgePin.copyFor(kind).title), findsOneWidget);
        expect(find.text(NudgePin.copyFor(kind).cta), findsOneWidget);
      }
    });

    testWidgets('can be sent away', (tester) async {
      var dismissed = 0;
      await _pumpPin(
        tester,
        NudgePin(
          item: const NudgeItem(NudgeKind.reviewDelivered, id: 'o1'),
          onDismiss: () => dismissed++,
        ),
      );

      await tester.tap(find.bySemanticsLabel('Dismiss'));
      expect(dismissed, 1);
    });

    testWidgets('a dismissal is remembered per thing, not per kind', (
      tester,
    ) async {
      const a = NudgeItem(NudgeKind.reviewDelivered, id: 'o1');
      const b = NudgeItem(NudgeKind.reviewDelivered, id: 'o2');
      expect(a.dismissKey, isNot(b.dismissKey));
      expect(a.dismissKey, 'nudge_dismissed_reviewDelivered_o1');
    });

    testWidgets('survives 2.0 text in both themes', (tester) async {
      await _survivesBigText(
        tester,
        () => const NudgePin(item: NudgeItem(NudgeKind.sayHi)),
      );
    });
  });

  group('MakersRail', () {
    final sellers = Fx.people.values.where((p) => p.isSeller).take(4).toList();

    testWidgets('names the makers and spans the grid', (tester) async {
      await _pumpPin(
        tester,
        MakersRail(item: MakersRailItem(sellers)),
        width: 370,
      );

      expect(find.text('Makers near you'), findsOneWidget);
      expect(find.text(sellers.first.name), findsOneWidget);
      expect(MakersRailItem(sellers).isWide, isTrue);
    });

    testWidgets('survives 2.0 text in both themes', (tester) async {
      await _survivesBigText(
        tester,
        () => MakersRail(item: MakersRailItem(sellers)),
        width: 370,
      );
    });
  });

  group('CartPill', () {
    final productId = Fx.products.keys.first;

    testWidgets('a tap carts it, without leaving the screen', (tester) async {
      final container = await _pumpPill(tester, productId: productId);
      expect(find.text('Cart'), findsOneWidget);
      expect(_lines(container), isEmpty);

      await tester.tap(find.byType(CartPill));
      await tester.pumpAndSettle();

      expect(_lines(container).single.productId, productId);
      expect(find.text('Carted'), findsOneWidget);
      expect(find.text('Cart'), findsNothing);
      // The toast is the whole point: feedback that does not navigate.
      expect(find.text('In your little blue cart'), findsOneWidget);
      expect(find.byType(CartPill), findsOneWidget);

      await _letToastGo(tester);
    });

    testWidgets('a second tap takes it back out', (tester) async {
      final container = await _pumpPill(tester, productId: productId);

      await tester.tap(find.byType(CartPill));
      await tester.pumpAndSettle();
      expect(_lines(container), hasLength(1));
      await _letToastGo(tester);

      await tester.tap(find.byType(CartPill));
      await tester.pumpAndSettle();

      expect(_lines(container), isEmpty);
      expect(find.text('Cart'), findsOneWidget);
    });

    testWidgets('a guest gets the gate, and nothing is carted', (tester) async {
      final container = await _pumpPill(
        tester,
        productId: productId,
        guest: true,
      );

      await tester.tap(find.byType(CartPill));
      await tester.pumpAndSettle();

      expect(_lines(container), isEmpty);
      expect(find.text('Carted'), findsNothing);
      // The gate sheet, not a cart line.
      expect(find.text('Keep looking around'), findsOneWidget);
    });

    testWidgets('the first ever tap explains what the cart means here', (
      tester,
    ) async {
      final container = await _pumpPill(
        tester,
        productId: productId,
        tipSeen: false,
      );

      await tester.tap(find.byType(CartPill));
      await tester.pumpAndSettle();

      // Nothing is carted until the tip is acknowledged.
      expect(_lines(container), isEmpty);
      expect(find.text('Got it'), findsOneWidget);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      expect(_lines(container), hasLength(1));
      await _letToastGo(tester);
    });

    testWidgets('orchid means "cart me", ink means "done"', (tester) async {
      await _pumpPill(tester, productId: productId);
      final c = LbmColors.light;

      Color? pillFill() {
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(CartPill),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        return (box.decoration as BoxDecoration).color;
      }

      expect(pillFill(), c.accentDeep);

      await tester.tap(find.byType(CartPill));
      await tester.pumpAndSettle();

      expect(pillFill(), c.ink);
      await _letToastGo(tester);
    });

    testWidgets('survives 2.0 text in both themes', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pumpPill(tester, productId: productId);
      expect(tester.takeException(), isNull);
    });
  });

  group('chips', () {
    Color? fillOf(WidgetTester tester, String label) {
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).color;
    }

    Color? textOf(WidgetTester tester, String label) =>
        tester.widget<Text>(find.text(label)).style?.color;

    testWidgets('a hashtag is sky, never orchid', (tester) async {
      final c = LbmColors.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLbmTheme(Brightness.light),
          home: const Scaffold(
            body: Center(child: LbmChip('#Handmade', style: ChipStyle.initiative)),
          ),
        ),
      );

      // Orchid is the cart's, and only the cart's.
      expect(fillOf(tester, '#Handmade'), c.skyMist);
      expect(textOf(tester, '#Handmade'), c.skyDeep);
      expect(fillOf(tester, '#Handmade'), isNot(c.accentMist));
      expect(fillOf(tester, '#Handmade'), isNot(c.accentDeep));
    });

    testWidgets('the selected chip is ink, not orchid', (tester) async {
      final c = LbmColors.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLbmTheme(Brightness.light),
          home: const Scaffold(
            body: Center(child: LbmChip('Forums', style: ChipStyle.on)),
          ),
        ),
      );

      expect(fillOf(tester, 'Forums'), c.ink);
      expect(textOf(tester, 'Forums'), c.surface);
    });

    testWidgets('the selected chip stays legible in the dark', (tester) async {
      final c = LbmColors.dark;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLbmTheme(Brightness.dark),
          home: const Scaffold(
            body: Center(child: LbmChip('Forums', style: ChipStyle.on)),
          ),
        ),
      );

      // Inverted by the tokens themselves: pale pill, dark label.
      expect(fillOf(tester, 'Forums'), c.ink);
      expect(textOf(tester, 'Forums'), c.surface);
      expect(fillOf(tester, 'Forums'), isNot(c.paper));
    });

    testWidgets('only an accent-flagged plain chip is still pink', (
      tester,
    ) async {
      final c = LbmColors.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLbmTheme(Brightness.light),
          home: const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LbmChip('Ask', accent: true),
                  LbmChip('Pickup'),
                ],
              ),
            ),
          ),
        ),
      );

      expect(fillOf(tester, 'Ask'), c.accentMist);
      expect(textOf(tester, 'Ask'), c.accentText);
      expect(fillOf(tester, 'Pickup'), c.skyMist);
    });

    testWidgets('FilterChips marks one and reports the others', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLbmTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: FilterChips(
                items: const [
                  ('all', 'All'),
                  ('product', 'Products'),
                  ('forum', 'Forums'),
                ],
                selected: 'all',
                onSelect: picked.add,
              ),
            ),
          ),
        ),
      );

      final c = LbmColors.light;
      expect(fillOf(tester, 'All'), c.ink, reason: 'the selected one');
      expect(fillOf(tester, 'Forums'), c.skyWash, reason: 'the rest are quiet');

      await tester.tap(find.text('Forums'));
      await tester.pumpAndSettle();
      expect(picked, ['forum']);

      // Tapping the one already on is not a change to report.
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(picked, ['forum']);
    });
  });

  group('LbmToast', () {
    testWidgets('slides in, then takes itself away', (tester) async {
      await tester.pumpWidget(_toastHost(subtitle: 'Wild Plum Jam'));
      await tester.tap(find.text('go'));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('In your little blue cart'), findsOneWidget);
      expect(find.text('Wild Plum Jam'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('In your little blue cart'), findsNothing);
    });

    testWidgets('a swipe up gets rid of it early', (tester) async {
      await tester.pumpWidget(_toastHost());
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.fling(
        find.text('In your little blue cart'),
        const Offset(0, -80),
        800,
      );
      await tester.pumpAndSettle();

      expect(find.text('In your little blue cart'), findsNothing);
    });

    testWidgets('the action runs and closes it', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _toastHost(action: ('View', () => tapped++)),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(tapped, 1);
      expect(find.text('In your little blue cart'), findsNothing);
    });

    testWidgets('a second toast replaces the first rather than stacking', (
      tester,
    ) async {
      await tester.pumpWidget(_toastHost());
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('In your little blue cart'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('In your little blue cart'), findsNothing);
    });

    testWidgets('carries a thumbnail without overflowing at 2.0 text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      await tester.pumpWidget(
        _toastHost(
          subtitle: 'Untamed Alchemy · Marquette, MI',
          thumbnailUrl: _photo,
          action: ('View', () {}),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });

  group('NaturalPhoto', () {
    testWidgets('takes the photograph its own shape, within the pin clamp', (
      tester,
    ) async {
      await pumpDecoded(tester, _framed(const NaturalPhoto(url: _photo)));

      final aspect = _aspectOf(tester);
      expect(aspect, greaterThanOrEqualTo(3 / 4));
      expect(aspect, lessThanOrEqualTo(5 / 4));
    });

    testWidgets('the clamp is what decides, not the file', (tester) async {
      // Squeezing the allowed range to a single value proves the clamp is
      // applied to the decoded pixels rather than ignored when they arrive.
      await pumpDecoded(
        tester,
        _framed(
          const NaturalPhoto(url: _photo, minAspect: 1, maxAspect: 1),
        ),
      );
      expect(_aspectOf(tester), closeTo(1, 0.001));

      await pumpDecoded(
        tester,
        _framed(
          const NaturalPhoto(url: _photo, minAspect: 0.5, maxAspect: 0.5),
        ),
      );
      expect(_aspectOf(tester), closeTo(0.5, 0.001));
    });

    testWidgets('no photograph falls back at 4:5 rather than collapsing', (
      tester,
    ) async {
      await pumpDecoded(
        tester,
        _framed(
          const NaturalPhoto(
            url: '',
            fallback: ColoredBox(color: Color(0xFFDCE9F7)),
          ),
        ),
      );

      expect(_aspectOf(tester), closeTo(NaturalPhoto.fallbackAspect, 0.001));
      expect(tester.getSize(find.byType(NaturalPhoto)).height, greaterThan(0));
    });

    testWidgets('a photograph that will not load shows the fallback', (
      tester,
    ) async {
      await pumpDecoded(
        tester,
        _framed(
          const NaturalPhoto(
            url: 'asset://assets/images/does-not-exist.jpg',
            fallback: Text('pastel tile'),
          ),
        ),
      );

      expect(find.text('pastel tile'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('draws no frame around the photograph', (tester) async {
      await pumpDecoded(tester, _framed(const NaturalPhoto(url: _photo)));

      // The photo is the card: it fills the column edge to edge, with the
      // corners rounded and nothing else drawn around it.
      expect(tester.getSize(find.byType(NaturalPhoto)).width, _pinWidth);
      final clip = tester.widget<ClipRRect>(
        find
            .descendant(
              of: find.byType(NaturalPhoto),
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      expect(clip.borderRadius, isNotNull);
    });

    testWidgets('renders in both themes without overflowing', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      for (final brightness in Brightness.values) {
        await pumpDecoded(
          tester,
          _framed(const NaturalPhoto(url: _photo), brightness: brightness),
        );
        expect(tester.takeException(), isNull);
      }
    });
  });
}
