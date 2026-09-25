import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/feed_item.dart';
import '../models/models.dart';
import 'promos.dart';
import 'providers.dart';
import 'session.dart';
import 'tips.dart';

/// Which kinds the person has narrowed the grid to.
abstract final class FeedFilter {
  static const all = 'all';
  static const product = 'product';
  static const review = 'review';
  static const cart = 'cart';
  static const forum = 'forum';
  static const chat = 'chat';
  static const community = 'community';

  /// The chips, in the order they are drawn.
  static const chips = <(String, String)>[
    (all, 'All'),
    (product, 'Products'),
    (review, 'Reviews'),
    (cart, 'Carts'),
    (forum, 'Forums'),
    (chat, 'Chat'),
  ];
}

/// Everything [assembleFeed] needs, gathered in one place.
///
/// A plain value rather than a pile of Riverpod reads, so the recipe can be
/// tested by handing it fixed inputs. The rules below are the difference
/// between a feed and a list, and they are worth being able to check without
/// booting an app.
@immutable
class FeedInputs {
  const FeedInputs({
    this.posts = const [],
    this.hotThreads = const [],
    this.forumNames = const {},
    this.joinedForums = const {},
    this.chatMoment,
    this.announcement,
    this.promo,
    this.announcementSeen = false,
    this.nearbySellers = const [],
    this.purchases = const [],
    this.isGuest = false,
    this.cartTipSeen = false,
    this.isNewMember = false,
    this.dismissedNudges = const {},
    this.filter = FeedFilter.all,
  });

  final List<Post> posts;
  final List<ForumThread> hotThreads;

  /// Forum id to name, for a thread pin's kicker.
  final Map<String, String> forumNames;

  /// The forums this person is in, so a pin can say "Joined".
  final Set<String> joinedForums;

  final ChatMoment? chatMoment;

  /// The newest announcement this viewer is in the audience for.
  final Announcement? announcement;

  /// The live promo, for the hero's photograph.
  final Promo? promo;

  /// Whether [announcement] predates the last time the bell was opened.
  final bool announcementSeen;

  final List<Person> nearbySellers;
  final List<Purchase> purchases;
  final bool isGuest;

  /// Whether "adding to the cart is the like" has been explained yet.
  final bool cartTipSeen;

  /// Somebody who has not bought anything or posted anything.
  ///
  /// The plan asks for "profile created under seven days ago", and there is
  /// no such field: [Person] carries no creation date and neither does the
  /// session. Rather than invent one, this asks the question the nudge
  /// actually cares about — has this person done anything yet — which the
  /// profile does answer.
  final bool isNewMember;

  /// [NudgeItem.dismissKey]s this phone has been told to forget.
  final Set<String> dismissedNudges;

  final String filter;
}

/// How many posts go by before something that is not a post is slotted in.
const _postsBetweenBreaks = 3;

/// Threads are the most interruptive thing in the grid; more than a few per
/// page and the Market stops being the Market.
const _maxThreadsPerPage = 3;

/// Turns the sources into the order the grid is drawn in.
///
/// Pure, and deliberately so: the rules that keep a feed from reading as
/// noise are rules about *sequence*, and sequence is the one thing a stack of
/// providers cannot be asked about directly.
List<FeedItem> assembleFeed(FeedInputs input) {
  final out = <FeedItem>[];

  // The market's own news is not in the grid any more: it is the rotating
  // banner above it, the same size every time. As a pin it took a column's
  // width, came out square, and changed shape depending on whether it had
  // been read. See `widgets/hero_banner.dart`.
  final postItems = [for (final post in input.posts) _itemFor(post)];
  final queue = _interleaved(input);

  var sinceBreak = 0;
  var next = 0;
  for (final item in postItems) {
    out.add(item);
    sinceBreak++;
    if (sinceBreak >= _postsBetweenBreaks && next < queue.length) {
      out.add(queue[next++]);
      sinceBreak = 0;
    }
  }
  // A short page must not swallow the community entirely: whatever did not
  // get a slot goes on the end rather than being dropped.
  while (next < queue.length) {
    out.add(queue[next++]);
  }

  return _onlyKind(_spacedOut(out), input.filter);
}

FeedItem _itemFor(Post post) => switch (post) {
  ListingPost p => ProductItem(
    p,
    proof: p.product.saveCount >= ProductItem.proofThreshold,
  ),
  ReviewPost p => ReviewItem(p),
  CartPost p => CartItem(p),
  ShoutoutPost p => ShoutoutItem(p),
  DirectoryPost p => DirectoryItem(p),
};

/// The things that go between the posts, in the order they are used up.
List<FeedItem> _interleaved(FeedInputs input) {
  final queue = <FeedItem>[];

  final nudge = _nudge(input);
  if (nudge != null) queue.add(nudge);

  // Guests are bounced off every community route, so a thread or a chat pin
  // would be an invitation to a locked door.
  final threads = input.isGuest
      ? const <ForumThread>[]
      : input.hotThreads.take(_maxThreadsPerPage).toList();

  ThreadItem threadItem(ForumThread t) => ThreadItem(
    t,
    forumName: input.forumNames[t.forumId],
    joined: input.joinedForums.contains(t.forumId),
  );

  var i = 0;
  if (i < threads.length) queue.add(threadItem(threads[i++]));

  final moment = input.chatMoment;
  if (!input.isGuest && moment != null) queue.add(ChatItem(moment));

  if (input.nearbySellers.isNotEmpty) {
    queue.add(MakersRailItem(input.nearbySellers));
  }

  while (i < threads.length) {
    queue.add(threadItem(threads[i++]));
  }

  return queue;
}

/// At most one nudge per page, and never one that has been sent away.
NudgeItem? _nudge(FeedInputs input) {
  if (input.isGuest) return null;

  if (input.isNewMember) {
    const nudge = NudgeItem(NudgeKind.sayHi);
    if (!input.dismissedNudges.contains(nudge.dismissKey)) return nudge;
  }

  for (final purchase in input.purchases) {
    if (!purchase.delivered || !purchase.canReview) continue;
    final nudge = NudgeItem(
      NudgeKind.reviewDelivered,
      id: purchase.id,
      payload: purchase,
    );
    if (input.dismissedNudges.contains(nudge.dismissKey)) continue;
    return nudge;
  }
  return null;
}

/// Two of a kind in a row read as a section, and a feed is not sections.
///
/// Products are the exception: a run of photographs is the grid working, and
/// spacing them out would mean shuffling the newest listings out of order for
/// no reason anyone could see.
bool _clashes(FeedItem a, FeedItem b) =>
    a.runtimeType == b.runtimeType && a is! ProductItem;

/// Reorders as little as possible to keep two of a kind apart.
///
/// Runs before the filter, not after: narrowing the grid to one kind is the
/// person asking for a run of that kind, and holding items back then would
/// just be losing them.
List<FeedItem> _spacedOut(List<FeedItem> items) {
  if (items.length < 2) return items;

  final pending = [...items];
  final out = <FeedItem>[pending.removeAt(0)];
  while (pending.isNotEmpty) {
    var pick = pending.indexWhere((item) => !_clashes(out.last, item));
    // Nothing else fits; take the next one anyway rather than drop it.
    if (pick < 0) pick = 0;
    out.add(pending.removeAt(pick));
  }
  return out;
}

List<FeedItem> _onlyKind(List<FeedItem> items, String filter) {
  if (filter == FeedFilter.all) return items;
  return [
    for (final item in items)
      if (_passes(item, filter)) item,
  ];
}

bool _passes(FeedItem item, String filter) => switch (filter) {
  FeedFilter.product => item is ProductItem || item is DirectoryItem,
  FeedFilter.review => item is ReviewItem,
  FeedFilter.cart => item is CartItem,
  FeedFilter.forum => item is ThreadItem,
  FeedFilter.chat => item is ChatItem,
  FeedFilter.community =>
    item is ThreadItem || item is ChatItem || item is ShoutoutItem,
  _ => true,
};

// --------------------------------------------------------------- providers

final feedFilterProvider = NotifierProvider<_FeedFilterNotifier, String>(
  _FeedFilterNotifier.new,
);

class _FeedFilterNotifier extends Notifier<String> {
  @override
  String build() => FeedFilter.all;

  void select(String filter) => state = filter;
}

/// The busiest threads across every forum, for the pins in the Market feed.
final hotThreadsProvider = StreamProvider<List<ForumThread>>((ref) {
  if (ref.watch(isGuestProvider)) return Stream.value(const []);
  return ref.watch(socialRepositoryProvider).watchHotThreads();
});

/// What the open room looks like right now.
final chatMomentProvider = StreamProvider<ChatMoment>((ref) {
  if (ref.watch(isGuestProvider)) return Stream.value(const ChatMoment());
  return ref.watch(messagingRepositoryProvider).watchChatMoment();
});

/// Sellers for the rail. Not sorted by distance; see the repository.
final nearbySellersProvider = FutureProvider<List<Person>>((ref) {
  if (ref.watch(isGuestProvider)) return Future.value(const []);
  return ref.watch(profileRepositoryProvider).nearbySellers();
});

/// Nudges this phone has been told to stop showing, with their week's grace.
final dismissedNudgesProvider =
    NotifierProvider<DismissedNudges, Set<String>>(DismissedNudges.new);

class DismissedNudges extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Kept in memory for now. The plan's seven-day TTL in
  /// `shared_preferences` lands with the rest of the nudge plumbing; until
  /// then a dismissal lasts the session, which is the safe direction to be
  /// wrong in (it comes back, rather than never coming back).
  void dismiss(String key) => state = {...state, key};
}

/// Extra pages of posts, appended to the live first page by `loadMore`.
@immutable
class FeedPaging {
  const FeedPaging({
    this.extra = const [],
    this.cursor,
    this.loading = false,
    this.done = false,
  });

  final List<Post> extra;
  final String? cursor;
  final bool loading;

  /// The backend has no more to give.
  final bool done;

  FeedPaging copyWith({
    List<Post>? extra,
    String? cursor,
    bool? loading,
    bool? done,
  }) => FeedPaging(
    extra: extra ?? this.extra,
    cursor: cursor ?? this.cursor,
    loading: loading ?? this.loading,
    done: done ?? this.done,
  );
}

final feedPagingProvider = NotifierProvider<FeedPagingNotifier, FeedPaging>(
  FeedPagingNotifier.new,
);

class FeedPagingNotifier extends Notifier<FeedPaging> {
  @override
  FeedPaging build() => const FeedPaging();

  /// Fetches the next page and appends it.
  ///
  /// The first page stays a live stream; only the tail is paged. That way a
  /// new post still appears at the top without re-fetching everything below
  /// it, and scrolling never resets what has been loaded.
  Future<void> loadMore() async {
    if (state.loading || state.done) return;
    state = state.copyWith(loading: true);
    try {
      final page = await ref
          .read(socialRepositoryProvider)
          .feedPage(cursor: state.cursor);
      state = FeedPaging(
        extra: [...state.extra, ...page.items],
        cursor: page.cursor,
        done: !page.hasMore || page.isEmpty,
      );
    } on Object {
      // Leave what is already loaded alone; the next scroll tries again.
      state = state.copyWith(loading: false);
    }
  }

  /// Pull to refresh drops the tail: it was assembled against a first page
  /// that no longer exists.
  void reset() => state = const FeedPaging();
}

/// The grid, assembled.
final feedItemsProvider = Provider<AsyncValue<List<FeedItem>>>((ref) {
  final posts = ref.watch(feedProvider);
  final isGuest = ref.watch(isGuestProvider);
  final paging = ref.watch(feedPagingProvider);

  return posts.whenData((live) {
    final me = ref.watch(meProvider);
    final announcements = ref.watch(announcementsProvider).value ?? const [];
    final prefs = ref.watch(notificationPrefsProvider).value;
    final seenAt = prefs?.announcementsSeenAt;
    final announcement = announcements.isEmpty ? null : announcements.first;
    final forums = ref.watch(forumsProvider).value ?? const [];

    // Ids seen on the live page win, so a post that also came back in a
    // fetched page is not drawn twice.
    final seen = {for (final post in live) post.id};
    final all = [
      ...live,
      for (final post in paging.extra)
        if (seen.add(post.id)) post,
    ];

    return assembleFeed(
      FeedInputs(
        posts: all,
        hotThreads: ref.watch(hotThreadsProvider).value ?? const [],
        forumNames: {for (final forum in forums) forum.id: forum.title},
        joinedForums: const {},
        chatMoment: ref.watch(chatMomentProvider).value,
        announcement: announcement,
        promo: ref.watch(allPromosProvider).value?.firstOrNull,
        announcementSeen:
            announcement != null &&
            seenAt != null &&
            !announcement.createdAt.isAfter(seenAt),
        nearbySellers: ref.watch(nearbySellersProvider).value ?? const [],
        purchases: ref.watch(purchasesProvider).value ?? const [],
        isGuest: isGuest,
        cartTipSeen: ref.watch(tipsProvider).contains(Tips.cartIsTheLike),
        isNewMember: me != null && me.purchases == 0 && me.posts == 0,
        dismissedNudges: ref.watch(dismissedNudgesProvider),
        filter: ref.watch(feedFilterProvider),
      ),
    );
  });
});
