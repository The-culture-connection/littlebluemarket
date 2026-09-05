import 'dart:async';

import '../../models/models.dart';
import 'fixture_data.dart';

/// A value you can watch: every listener gets the current value immediately,
/// then each change.
///
/// Small enough to hand-roll, and hand-rolling it keeps the demo build free of
/// a streams dependency it would otherwise carry forever.
class Watchable<T> {
  Watchable(this._value);

  T _value;
  final _controller = StreamController<T>.broadcast();

  T get value => _value;

  set value(T next) {
    _value = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  /// Re-emit on a mutation the setter cannot see, e.g. a list edited in place.
  void touch() => value = _value;

  /// Current value first, then every change.
  ///
  /// Deliberately not `async* { yield _value; yield* _controller.stream; }`:
  /// that leaves an asynchronous gap between emitting the current value and
  /// subscribing to changes, and a write landing inside that gap is dropped
  /// with no trace. Here the seed and the subscription happen in the same
  /// synchronous turn, so nothing can slip between them.
  Stream<T> get stream {
    late StreamController<T> out;
    StreamSubscription<T>? subscription;
    out = StreamController<T>(
      onListen: () {
        out.add(_value);
        subscription = _controller.stream.listen(
          out.add,
          onError: out.addError,
        );
      },
      onCancel: () => subscription?.cancel(),
    );
    return out.stream;
  }

  void dispose() => _controller.close();
}

/// The demo backend's memory.
///
/// This exists so the fixture repositories can honour writes. In the prototype
/// a sent message, an edited bio and a created forum were all discarded on pop,
/// because the screens held them in `setState` over `const` data. Here a write
/// lands in the store and comes back out through the same stream the screen is
/// already watching — which means the screen code written against it is final.
/// Swapping in Firestore changes nothing above the repository line.
class FixtureStore {
  FixtureStore({this.currentUid = Fx.meId}) {
    _seed();
  }

  final String currentUid;

  // Reads that never change keep their fixture form; anything writable lives
  // in a Watchable so a screen can observe the write it just made.
  late final people = Watchable<Map<String, Person>>({...Fx.people});
  final posts = Watchable<List<Post>>([]);
  final comments = Watchable<Map<String, List<Comment>>>({});
  late final reviews = Watchable<Map<String, List<Review>>>({
    for (final entry in Fx.reviews.entries) entry.key: [...entry.value],
  });
  late final forums = Watchable<List<Forum>>([...Fx.forums]);
  final joinedForums = Watchable<Set<String>>({'f1'});
  late final threads = Watchable<List<ForumThread>>([...Fx.threads]);
  final threadComments = Watchable<Map<String, List<ThreadComment>>>({});
  final chatroom = Watchable<List<Message>>([]);
  final conversations = Watchable<Map<String, List<Message>>>({});
  final inbox = Watchable<List<Conversation>>([]);
  final cart = Watchable<Cart>(const Cart(id: 'fixture-cart', lines: []));
  final purchases = Watchable<List<Purchase>>([]);
  late final recentSearches = Watchable<List<String>>([...Fx.recentSearches]);
  final addresses = Watchable<List<Address>>([]);
  late final sending = Watchable<List<Shipment>>([...Fx.sending]);
  late final receiving = Watchable<List<Shipment>>([...Fx.receiving]);

  /// Post ids this viewer has liked.
  final likedPosts = <String>{};
  final likedComments = <String>{};

  var _nextId = 1;
  String newId(String prefix) => '$prefix${_nextId++}';

  void _seed() {
    posts.value = _seedPosts();
    comments.value = _seedComments();
    threadComments.value = {
      // The prototype rendered one global comment list under every thread.
      // Here they belong to the thread that actually has them.
      't1': [...Fx.comments],
    };
    chatroom.value = [
      for (final (i, m) in Fx.chatroom.indexed)
        Message(
          id: 'chat$i',
          conversationId: Message.chatroomId,
          authorId: m.authorId,
          createdAt: m.createdAt,
          text: m.text,
        ),
    ];
    inbox.value = [
      for (final dm in Fx.dms)
        Conversation(
          id: Conversation.idFor(currentUid, dm.personId),
          participantIds: [currentUid, dm.personId],
          lastMessageAt: dm.lastMessageAt,
          preview: dm.preview,
          unread: dm.unread,
        ),
    ];
    conversations.value = {
      for (final dm in Fx.dms)
        Conversation.idFor(currentUid, dm.personId): [
          for (final (i, m) in Fx.dmThreadWith(dm.personId).indexed)
            Message(
              id: '${dm.personId}$i',
              conversationId: Conversation.idFor(currentUid, dm.personId),
              authorId: m.authorId,
              createdAt: m.createdAt,
              text: m.text,
            ),
        ],
    };
    purchases.value = _seedPurchases();
    addresses.value = const [
      Address(
        id: 'a1',
        name: 'Maya Ellison',
        line1: '2745 Bagley St',
        city: 'Detroit',
        region: 'MI',
        postalCode: '48216',
        isDefault: true,
        lat: 42.3314,
        lng: -83.0458,
      ),
      Address(
        id: 'a2',
        name: 'Maya Ellison',
        line1: '1401 Vermont St',
        line2: 'Apt 3',
        city: 'Detroit',
        region: 'MI',
        postalCode: '48216',
      ),
    ];
  }

  /// The feed: the listings the prototype had, plus one review and one shoutout
  /// so those two branches of the sealed [Post] are exercised offline.
  List<Post> _seedPosts() {
    final now = DateTime.now();
    final listings = <Post>[
      for (final (i, id) in Fx.feedOrder.indexed)
        ListingPost(
          id: 'post_$id',
          authorId: Fx.product(id).sellerId,
          createdAt: now.subtract(Duration(hours: 3 * (i + 1))),
          tags: Fx.product(id).tags,
          likeCount: Fx.product(id).likes,
          commentCount: Fx.product(id).commentCount,
          likedByMe: false,
          product: Fx.product(id),
        ),
    ];

    return [
      listings.first,
      ReviewPost(
        id: 'post_review_1',
        authorId: 'dee',
        createdAt: now.subtract(const Duration(hours: 5)),
        tags: const ['#PlasticFree'],
        likeCount: 46,
        commentCount: 3,
        likedByMe: false,
        productId: 'p1',
        rating: 5,
        text:
            'Fourth tube. It survives a Michigan February and the paper tube '
            'composts with my coffee grounds.',
      ),
      ...listings.skip(1).take(2),
      ShoutoutPost(
        id: 'post_shoutout_1',
        authorId: 'juniper',
        createdAt: now.subtract(const Duration(hours: 14)),
        tags: const ['#BIPOCOwned', '#Services'],
        likeCount: 88,
        commentCount: 7,
        likedByMe: false,
        text:
            'If you need product shots before the holiday push, book @amashoots. '
            'She shot my whole refill line in an afternoon.',
        aboutSellerId: 'ama',
      ),
      ...listings.skip(3),
    ];
  }

  Map<String, List<Comment>> _seedComments() {
    final now = DateTime.now();
    return {
      'post_p3': [
        Comment(
          id: 'c1',
          postId: 'post_p3',
          authorId: 'maya',
          createdAt: now.subtract(const Duration(hours: 2)),
          text: 'The blush is softer in person than the photo. Can confirm.',
          likeCount: 12,
        ),
        Comment(
          id: 'c2',
          postId: 'post_p3',
          authorId: 'dee',
          createdAt: now.subtract(const Duration(hours: 1)),
          text: 'Does it run big? I am between sizes on everything.',
          likeCount: 3,
        ),
        Comment(
          id: 'c3',
          postId: 'post_p3',
          authorId: 'holler',
          createdAt: now.subtract(const Duration(minutes: 40)),
          text: 'A touch big, and the buckle takes up the slack.',
          parentId: 'c2',
          likeCount: 5,
        ),
      ],
    };
  }

  List<Purchase> _seedPurchases() {
    final now = DateTime.now();
    return [
      for (final (i, id) in Fx.myPurchases.indexed)
        Purchase(
          id: 'purchase_$id',
          orderId: 'order_${i ~/ 2}',
          productId: id,
          title: Fx.product(id).title,
          purchasedAt: now.subtract(Duration(days: 4 * (i + 1))),
          sellerId: Fx.product(id).sellerId,
          imageUrl: Fx.product(id).imageUrls.isEmpty
              ? null
              : Fx.product(id).imageUrls.first,
          delivered: i > 1,
          // Only the first two are reviewed, which is what the profile badge
          // reads — the prototype decided it from grid position instead.
          reviewed: i < 2,
        ),
    ];
  }

  void dispose() {
    for (final w in [
      people,
      posts,
      comments,
      reviews,
      forums,
      joinedForums,
      threads,
      threadComments,
      chatroom,
      conversations,
      inbox,
      cart,
      purchases,
      recentSearches,
      addresses,
      sending,
      receiving,
    ]) {
      w.dispose();
    }
  }
}
