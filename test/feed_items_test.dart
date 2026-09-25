import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/models/feed_item.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/state/feed_items.dart';

/// The feed's recipe, checked by handing it fixed inputs.
///
/// These are rules about *order*, which is the one thing you cannot ask a
/// screen about without reading it. A passing test here is not proof the feed
/// looks right; it is proof that the rules Grace asked for are the rules that
/// ran.

final _products = Fx.products.values.toList();
final _people = Fx.people.values.toList();

ListingPost _listing(int i) {
  final product = _products[i % _products.length];
  return ListingPost(
    id: 'listing$i',
    authorId: product.sellerId,
    createdAt: DateTime(2026, 9, 20).subtract(Duration(hours: i)),
    tags: const ['#Handmade'],
    likeCount: 0,
    commentCount: 0,
    likedByMe: false,
    product: product,
  );
}

ReviewPost _review(int i) => ReviewPost(
  id: 'review$i',
  authorId: Fx.meId,
  createdAt: DateTime(2026, 9, 19).subtract(Duration(hours: i)),
  tags: const [],
  likeCount: 0,
  commentCount: 0,
  likedByMe: false,
  productId: _products.first.id,
  rating: 5,
  text: 'Review number $i',
);

ShoutoutPost _shoutout(int i) => ShoutoutPost(
  id: 'shout$i',
  authorId: Fx.meId,
  createdAt: DateTime(2026, 9, 18).subtract(Duration(hours: i)),
  tags: const [],
  likeCount: 0,
  commentCount: 0,
  likedByMe: false,
  text: 'Shoutout number $i',
);

CartPost _cartPost(int i) => CartPost(
  id: 'cartpost$i',
  authorId: Fx.meId,
  createdAt: DateTime(2026, 9, 17).subtract(Duration(hours: i)),
  tags: const [],
  likeCount: 0,
  commentCount: 0,
  likedByMe: false,
  items: [
    CartPostItem(
      productId: _products.first.id,
      title: _products.first.title,
      sellerId: _products.first.sellerId,
      priceCents: 1000,
    ),
  ],
);

Announcement _announcement({DateTime? at}) => Announcement(
  id: 'a1',
  title: 'Six new makers joined this week',
  body: 'Ceramics, two bakers and a bookbinder.',
  audience: AnnouncementAudience.all,
  route: '/market',
  createdAt: at ?? DateTime(2026, 9, 21),
);

ForumThread _thread(int i, {int comments = 10}) => ForumThread(
  id: 'thread$i',
  forumId: 'f1',
  authorId: Fx.meId,
  title: 'Question number $i',
  body: 'Body $i',
  commentCount: comments,
  createdAt: DateTime(2026, 9, 16).subtract(Duration(hours: i)),
);

ChatMoment _moment() => ChatMoment(
  latest: [
    Message(
      id: 'm1',
      conversationId: Message.chatroomId,
      authorId: Fx.meId,
      createdAt: DateTime(2026, 9, 21, 9),
      text: 'Anyone at the Ypsi market?',
    ),
  ],
  lastHourCount: 14,
);

Purchase _purchase({
  String id = 'o1',
  bool delivered = true,
  bool reviewed = false,
}) => Purchase(
  id: id,
  orderId: 'order1',
  productId: _products.first.id,
  title: _products.first.title,
  purchasedAt: DateTime(2026, 9, 10),
  sellerId: _products.first.sellerId,
  delivered: delivered,
  reviewed: reviewed,
);

/// A full page: enough posts that every interleave rule gets a chance to run.
FeedInputs _member({
  String filter = FeedFilter.all,
  bool announcementSeen = false,
  List<Purchase> purchases = const [],
  Set<String> dismissed = const {},
  bool isNewMember = false,
}) => FeedInputs(
  posts: [
    for (var i = 0; i < 6; i++) _listing(i),
    _review(0),
    _review(1),
    _cartPost(0),
    _shoutout(0),
    for (var i = 6; i < 10; i++) _listing(i),
  ],
  hotThreads: [_thread(0), _thread(1, comments: 5), _thread(2, comments: 2)],
  forumNames: const {'f1': 'Packaging'},
  chatMoment: _moment(),
  announcement: _announcement(),
  announcementSeen: announcementSeen,
  nearbySellers: _people.where((p) => p.isSeller).take(4).toList(),
  purchases: purchases,
  dismissedNudges: dismissed,
  isNewMember: isNewMember,
  filter: filter,
);

void main() {
  group('announcements', () {
    test('are not pins in the grid', () {
      // They are the rotating banner above it (`widgets/hero_banner.dart`).
      // As a pin the announcement took a column's width, came out square, and
      // changed shape once it had been read (Grace, with a screenshot).
      expect(
        assembleFeed(_member()).whereType<AnnouncementItem>(),
        isEmpty,
      );
      expect(
        assembleFeed(_member(announcementSeen: true))
            .whereType<AnnouncementItem>(),
        isEmpty,
      );
    });

    test('the grid starts with something to look at', () {
      final items = assembleFeed(_member());
      expect(items.first, isA<ProductItem>());
    });
  });

  group('guests', () {
    test('get photographs, and nothing to join', () {
      final items = assembleFeed(
        FeedInputs(
          posts: [for (var i = 0; i < 6; i++) _listing(i)],
          hotThreads: [_thread(0)],
          chatMoment: _moment(),
          isGuest: true,
        ),
      );

      expect(items.whereType<ProductItem>(), isNotEmpty);

      // Every community route bounces a guest, so a pin inviting them in
      // would be an invitation to a locked door.
      expect(items.whereType<ThreadItem>(), isEmpty);
      expect(items.whereType<ChatItem>(), isEmpty);
      expect(items.whereType<NudgeItem>(), isEmpty);
    });
  });

  group('the mix', () {
    test('community and commerce are in the same grid', () {
      final items = assembleFeed(_member());

      expect(items.whereType<ProductItem>(), isNotEmpty);
      expect(items.whereType<ReviewItem>(), isNotEmpty);
      expect(items.whereType<CartItem>(), isNotEmpty);
      expect(items.whereType<ThreadItem>(), isNotEmpty);
      expect(items.whereType<ChatItem>(), isNotEmpty);
      expect(items.whereType<MakersRailItem>(), isNotEmpty);
    });

    test('never two of a kind in a row, except products', () {
      final items = assembleFeed(_member());

      for (var i = 1; i < items.length; i++) {
        final a = items[i - 1];
        final b = items[i];
        if (a is ProductItem && b is ProductItem) continue;
        expect(
          a.runtimeType,
          isNot(b.runtimeType),
          reason:
              'two ${a.runtimeType} in a row at $i: '
              '${items.map((e) => e.runtimeType).toList()}',
        );
      }
    });

    test('a run of photographs is left alone', () {
      // Products are the exception on purpose: spacing them out would mean
      // shuffling the newest listings out of order for no visible reason.
      final items = assembleFeed(
        FeedInputs(posts: [for (var i = 0; i < 3; i++) _listing(i)]),
      );
      expect(items.whereType<ProductItem>(), hasLength(3));
      expect(items.map((e) => (e as ProductItem).post.id), [
        'listing0',
        'listing1',
        'listing2',
      ]);
    });

    test('no more than three threads on a page', () {
      final items = assembleFeed(
        _member().copyThreads([
          for (var i = 0; i < 8; i++) _thread(i, comments: 10 - i),
        ]),
      );
      expect(items.whereType<ThreadItem>().length, lessThanOrEqualTo(3));
    });

    test('a thread pin carries its forum name and joined state', () {
      final items = assembleFeed(_member());
      final thread = items.whereType<ThreadItem>().first;
      expect(thread.forumName, 'Packaging');
      expect(thread.joined, isFalse);
    });

    test('nothing from the sources is silently dropped', () {
      final items = assembleFeed(_member());
      // Ten listings, two reviews, one cart post, one shoutout.
      expect(items.whereType<ProductItem>(), hasLength(10));
      expect(items.whereType<ReviewItem>(), hasLength(2));
      expect(items.whereType<CartItem>(), hasLength(1));
      expect(items.whereType<ShoutoutItem>(), hasLength(1));
    });
  });

  group('proof', () {
    test('a listing says how many carted it only once that means something', () {
      final loud = _products.firstWhere(
        (p) => p.saveCount >= ProductItem.proofThreshold,
        orElse: () => _products.first,
      );
      final quiet = _products.firstWhere(
        (p) => p.saveCount < ProductItem.proofThreshold,
        orElse: () => _products.first,
      );

      ListingPost postOf(Product p) => ListingPost(
        id: 'l_${p.id}',
        authorId: p.sellerId,
        createdAt: DateTime(2026, 9, 20),
        tags: const [],
        likeCount: 0,
        commentCount: 0,
        likedByMe: false,
        product: p,
      );

      final items = assembleFeed(FeedInputs(posts: [postOf(loud), postOf(quiet)]));
      final byId = {
        for (final item in items.whereType<ProductItem>())
          item.product.id: item.proof,
      };

      if (loud.saveCount >= ProductItem.proofThreshold) {
        expect(byId[loud.id], isTrue);
      }
      if (quiet.saveCount < ProductItem.proofThreshold) {
        expect(byId[quiet.id], isFalse);
      }
    });
  });

  group('nudges', () {
    test('something delivered and unreviewed earns one', () {
      final items = assembleFeed(_member(purchases: [_purchase()]));
      final nudges = items.whereType<NudgeItem>();

      expect(nudges, hasLength(1));
      expect(nudges.first.nudge, NudgeKind.reviewDelivered);
      expect(nudges.first.id, 'o1');
    });

    test('a dismissed one does not come back on the next assembly', () {
      const dismissedKey = 'nudge_dismissed_reviewDelivered_o1';
      final items = assembleFeed(
        _member(purchases: [_purchase()], dismissed: {dismissedKey}),
      );
      expect(items.whereType<NudgeItem>(), isEmpty);
    });

    test('a reviewed purchase is not nagged about', () {
      final items = assembleFeed(
        _member(purchases: [_purchase(reviewed: true)]),
      );
      expect(items.whereType<NudgeItem>(), isEmpty);
    });

    test('somebody who has done nothing yet is asked to say hello', () {
      final items = assembleFeed(_member(isNewMember: true));
      final nudges = items.whereType<NudgeItem>();

      expect(nudges, hasLength(1));
      expect(nudges.first.nudge, NudgeKind.sayHi);
    });

    test('at most one nudge, however many things are waiting', () {
      final items = assembleFeed(
        _member(
          isNewMember: true,
          purchases: [
            _purchase(id: 'o1'),
            _purchase(id: 'o2'),
            _purchase(id: 'o3'),
          ],
        ),
      );
      expect(items.whereType<NudgeItem>(), hasLength(1));
    });
  });

  group('the filter chips', () {
    test('Forums leaves forum pins and the announcement', () {
      final items = assembleFeed(_member(filter: FeedFilter.forum));

      expect(items.whereType<ThreadItem>(), isNotEmpty);
      expect(items.whereType<ProductItem>(), isEmpty);
      expect(items.whereType<ReviewItem>(), isEmpty);
      expect(items.whereType<ChatItem>(), isEmpty);
    });

    test('Community is threads, chat and shoutouts', () {
      final items = assembleFeed(_member(filter: FeedFilter.community));

      expect(items.whereType<ThreadItem>(), isNotEmpty);
      expect(items.whereType<ChatItem>(), isNotEmpty);
      expect(items.whereType<ShoutoutItem>(), isNotEmpty);
      expect(items.whereType<ProductItem>(), isEmpty);
      expect(items.whereType<ReviewItem>(), isEmpty);
      expect(items.whereType<CartItem>(), isEmpty);
    });

    test('Products keeps directory listings with the listings', () {
      final items = assembleFeed(_member(filter: FeedFilter.product));

      expect(items.whereType<ProductItem>(), isNotEmpty);
      expect(items.whereType<ThreadItem>(), isEmpty);
      expect(items.whereType<ChatItem>(), isEmpty);
    });

    test('every filter leaves something, and never an announcement', () {
      for (final (filter, _) in FeedFilter.chips) {
        final items = assembleFeed(_member(filter: filter));
        expect(
          items.whereType<AnnouncementItem>(),
          isEmpty,
          reason: 'the market\'s own news is the banner, not a pin',
        );
        expect(
          items,
          isNotEmpty,
          reason: 'the chip "$filter" should leave the grid with something',
        );
      }
    });

    test('Reviews and Carts each keep only their own', () {
      expect(
        assembleFeed(
          _member(filter: FeedFilter.review),
        ).whereType<CartItem>(),
        isEmpty,
      );
      expect(
        assembleFeed(
          _member(filter: FeedFilter.cart),
        ).whereType<ReviewItem>(),
        isEmpty,
      );
    });
  });

  group('an empty market', () {
    test('assembles to nothing rather than throwing', () {
      expect(assembleFeed(const FeedInputs()), isEmpty);
    });

    test('a market with only news in it has an empty grid', () {
      // And the banner above it still has something to say, which is the
      // point of it not being a pin.
      expect(assembleFeed(FeedInputs(announcement: _announcement())), isEmpty);
    });
  });
}

/// Small helpers so a case can vary one input without restating the rest.
extension on FeedInputs {
  FeedInputs copyThreads(List<ForumThread> threads) => FeedInputs(
    posts: posts,
    hotThreads: threads,
    forumNames: forumNames,
    joinedForums: joinedForums,
    chatMoment: chatMoment,
    announcement: announcement,
    promo: promo,
    announcementSeen: announcementSeen,
    nearbySellers: nearbySellers,
    purchases: purchases,
    isGuest: isGuest,
    cartTipSeen: cartTipSeen,
    isNewMember: isNewMember,
    dismissedNudges: dismissedNudges,
    filter: filter,
  );
}
