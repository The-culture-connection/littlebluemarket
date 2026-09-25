import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/feed_item.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/feed_items.dart';
import '../../state/providers.dart';
import '../../state/location.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/filter_chips.dart';
import '../../widgets/masonry.dart';
import '../../widgets/pins/announcement_pin.dart';
import '../../widgets/pins/cart_pin.dart';
import '../../widgets/pins/chat_pin.dart';
import '../../widgets/pins/directory_pin.dart';
import '../../widgets/pins/makers_rail.dart';
import '../../widgets/pins/nudge_pin.dart';
import '../../widgets/pins/product_pin.dart';
import '../../widgets/pins/review_pin.dart';
import '../../widgets/pins/shoutout_pin.dart';
import '../../widgets/pins/thread_pin.dart';
import '../../widgets/post_card.dart' show addManyToCart;
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart' show Puff;
import '../../widgets/screen.dart';
import '../../widgets/sheets.dart' show showGateSheet;
import '../../widgets/skeleton.dart';
import '../../widgets/tips.dart';
import '../../widgets/unverified_banner.dart';

/// The marketplace feed.
///
/// A two-column photo grid where the picture is the card, and where the
/// market's other kinds of content sit in the same columns: reviews, posted
/// carts, forum questions, the open chatroom, announcements. Community and
/// Market used to be two apps that shared a tab bar; this is the one screen
/// where the consequences of everything anyone does show up.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

/// Which of the three ways into the feed is showing.
enum _Tab { forYou, nearMe, following }

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _controller = ScrollController();
  var _tab = _Tab.forYou;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _controller.removeListener(_maybeLoadMore);
    _controller.dispose();
    super.dispose();
  }

  /// Fetches the next page once four fifths of the way down, so the grid is
  /// already longer by the time the bottom would have arrived.
  void _maybeLoadMore() {
    if (_tab != _Tab.forYou) return;
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels < position.maxScrollExtent * 0.8) return;
    ref.read(feedPagingProvider.notifier).loadMore();
  }

  Future<void> _refresh() async {
    ref.read(feedPagingProvider.notifier).reset();
    ref
      ..invalidate(feedProvider)
      ..invalidate(hotThreadsProvider)
      ..invalidate(chatMomentProvider)
      ..invalidate(nearbySellersProvider);
  }

  void _selectTab(int index) {
    final next = _Tab.values[index];
    if (next == _tab) return;
    setState(() => _tab = next);
    // Near me is a different question ("what is close"), asked of the
    // catalogue rather than of the post stream, so the toggle the search
    // screen shares has to agree with the tab.
    final filters = ref.read(searchFiltersProvider);
    if (next == _Tab.nearMe && !filters.nearMe) {
      toggleNearMe(context, ref);
    } else if (next != _Tab.nearMe && filters.nearMe) {
      ref.read(searchFiltersProvider.notifier).toggleNearMe();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isGuest = ref.watch(isGuestProvider);

    return LbmScreen(
      appBar: Container(
        color: c.paper,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchPill(
              label: 'Search goods, services, #tags',
              onTap: () => context.push('/market/search'),
            ),
            const SizedBox(height: 4),
            TopTabs(
              labels: const ['For you', 'Near me', 'Following'],
              selected: _tab.index,
              onChanged: _selectTab,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      bottom: isGuest
          ? GuestJoinBar(onJoin: () => showGateSheet(context))
          : null,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: switch (_tab) {
          _Tab.nearMe => _NearMeGrid(controller: _controller),
          _Tab.forYou || _Tab.following => _Grid(
            controller: _controller,
            isGuest: isGuest,
            following: _tab == _Tab.following,
          ),
        },
      ),
    );
  }
}

/// The grid itself: For you, and Following, which is the same grid with the
/// posts narrowed to people this person follows.
class _Grid extends ConsumerWidget {
  const _Grid({
    required this.controller,
    required this.isGuest,
    required this.following,
  });

  final ScrollController controller;
  final bool isGuest;
  final bool following;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(feedItemsProvider);
    final filter = ref.watch(feedFilterProvider);
    final followed = ref.watch(followedPeopleProvider).value ?? const <String>{};

    final header = <Widget>[
      SliverToBoxAdapter(
        child: FilterChips(
          items: FeedFilter.chips,
          selected: filter,
          onSelect: ref.read(feedFilterProvider.notifier).select,
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 10)),
      // A member whose address is not confirmed: the two buttons that fix it,
      // before anything refuses them for it.
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: UnverifiedBanner(),
        ),
      ),
    ];

    return LbmAsync<List<FeedItem>>(
      items,
      skeleton: const PostCardSkeleton(),
      onRetry: () => ref.invalidate(feedProvider),
      data: (all) {
        final shown = following ? _onlyFollowed(all, followed) : all;

        if (shown.isEmpty) {
          return CustomScrollView(
            controller: controller,
            slivers: [
              ...header,
              SliverFillRemaining(
                hasScrollBody: false,
                child: following
                    ? const LbmEmpty(
                        title: 'Nobody yet',
                        body:
                            'Follow a maker and their posts land here. '
                            'Tap any avatar to start.',
                      )
                    : const LbmEmpty(
                        title: 'Nothing posted yet',
                        body:
                            'When sellers list something nearby, it shows up '
                            'here.',
                      ),
              ),
            ],
          );
        }

        return CustomScrollView(
          controller: controller,
          slivers: [
            ...header,
            ...LbmMasonry.slivers(
              children: [for (final item in shown) _pinFor(context, ref, item)],
              wide: [for (final item in shown) item.isWide],
            ),
            SliverToBoxAdapter(child: _TheEnd(guest: isGuest)),
            // The tab bar is a real bottom bar rather than something floating
            // over the grid, so the scroll area already ends above it; this
            // is breathing room, not clearance.
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }

  /// Posts by people this person follows, keeping everything that is not a
  /// post: the announcement, the chat, the rail.
  ///
  /// Tags are the other half of Following and land with the tag pages; until
  /// then this is people only, which is the half that has a source today.
  List<FeedItem> _onlyFollowed(List<FeedItem> items, Set<String> followed) => [
    for (final item in items)
      if (switch (item) {
        ProductItem i => followed.contains(i.post.authorId),
        ReviewItem i => followed.contains(i.post.authorId),
        CartItem i => followed.contains(i.post.authorId),
        ShoutoutItem i => followed.contains(i.post.authorId),
        DirectoryItem i => followed.contains(i.post.authorId),
        _ => false,
      })
        item,
  ];
}

/// One pin per kind. Exhaustive on purpose: a new [FeedItem] is a compile
/// error here rather than a hole in the grid.
Widget _pinFor(BuildContext context, WidgetRef ref, FeedItem item) =>
    switch (item) {
      ProductItem i => ProductPin(key: ValueKey(i.key), item: i),
      ReviewItem i => ReviewPin(key: ValueKey(i.key), item: i),
      CartItem i => CartPin(
        key: ValueKey(i.key),
        item: i,
        onAddAll: () => addManyToCart(
          context,
          ref,
          [for (final line in i.post.items) line.productId],
        ),
      ),
      ShoutoutItem i => ShoutoutPin(key: ValueKey(i.key), item: i),
      DirectoryItem i => DirectoryPin(key: ValueKey(i.key), item: i),
      ThreadItem i => ThreadPin(key: ValueKey(i.key), item: i),
      ChatItem i => ChatPin(key: ValueKey(i.key), item: i),
      AnnouncementItem i => AnnouncementPin(
        key: ValueKey(i.key),
        item: i,
        onTap: () => _openAnnouncement(context, ref, i),
      ),
      NudgeItem i => NudgePin(
        key: ValueKey(i.key),
        item: i,
        onTap: () => _openNudge(context, ref, i),
        onDismiss: () =>
            ref.read(dismissedNudgesProvider.notifier).dismiss(i.dismissKey),
      ),
      MakersRailItem i => MakersRail(key: ValueKey(i.key), item: i),
    };

void _openAnnouncement(
  BuildContext context,
  WidgetRef ref,
  AnnouncementItem item,
) {
  // The guest hero is the cart tip wearing an announcement's clothes, and
  // there is no announcement route behind it.
  if (item.announcement.id == cartTipId) {
    showCartTipOnce(context, ref);
    return;
  }
  final route = item.announcement.route;
  if (route.isNotEmpty) context.go(route);
}

void _openNudge(BuildContext context, WidgetRef ref, NudgeItem item) {
  switch (item.nudge) {
    case NudgeKind.reviewDelivered:
      final purchase = item.payload;
      if (purchase is Purchase) context.goToProduct(purchase.productId);
    case NudgeKind.sayHi:
      context.go('/community');
    case NudgeKind.forumActivity:
      context.go('/community/forums');
  }
}

/// The bottom of the grid.
class _TheEnd extends StatelessWidget {
  const _TheEnd({required this.guest});

  final bool guest;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Column(
        children: [
          const Puff(),
          const SizedBox(height: 6),
          Text(
            "That's everything new",
            textAlign: TextAlign.center,
            style: LbmText.tiny.copyWith(
              color: c.ink2,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!guest) ...[
            const SizedBox(height: 10),
            PillButton(
              'Go see Community',
              style: PillStyle.ghost,
              small: true,
              expand: false,
              onPressed: () => context.go('/community'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Near me: the listings closest to the person, in the same grid.
///
/// A catalogue question rather than a filter over the post stream. The feed
/// carries the twenty most recent posts of every kind, and a distance filter
/// over twenty posts usually leaves nothing; the catalogue is the right thing
/// to ask "what is near me", and it answers with something to buy.
class _NearMeGrid extends ConsumerWidget {
  const _NearMeGrid({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final filters = ref.watch(searchFiltersProvider);
    final nearby = ref.watch(nearbyProductsProvider(filters));
    final where = filters.origin?.label ?? 'you';

    final header = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Text(
            'Within ${Fmt.distanceMiles(filters.radiusMiles)} of $where',
            style: LbmText.tiny.copyWith(
              color: c.ink2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: FilterChips(
          items: [
            for (final miles in const [5.0, 10.0, 25.0, 50.0])
              (miles.toString(), Fmt.distanceMiles(miles)),
          ],
          selected: filters.radiusMiles.toString(),
          onSelect: (value) => ref
              .read(searchFiltersProvider.notifier)
              .setRadius(double.parse(value)),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 10)),
    ];

    return LbmAsync<List<Product>>(
      nearby,
      skeleton: const GridSkeleton(count: 6),
      onRetry: () => ref.invalidate(nearbyProductsProvider(filters)),
      data: (products) {
        if (products.isEmpty) {
          return CustomScrollView(
            controller: controller,
            slivers: [
              ...header,
              SliverFillRemaining(
                hasScrollBody: false,
                child: LbmEmpty(
                  title:
                      'Nothing within '
                      '${Fmt.distanceMiles(filters.radiusMiles)}',
                  body:
                      'Try a wider circle, or switch back to For you to see '
                      'the whole Market. A listing only counts as nearby once '
                      'its shop has filled in a city.',
                ),
              ),
            ],
          );
        }

        return CustomScrollView(
          controller: controller,
          slivers: [
            ...header,
            ...LbmMasonry.slivers(
              children: [
                for (final product in products)
                  _NearbyPin(key: ValueKey(product.id), product: product),
              ],
              bottom: 24,
            ),
          ],
        );
      },
    );
  }
}

/// A catalogue product as a pin.
///
/// Near me answers with listings rather than posts, so there is no
/// [ListingPost] to wrap; the pin is built from the product itself.
class _NearbyPin extends ConsumerWidget {
  const _NearbyPin({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProductPin(
      item: ProductItem(
        ListingPost(
          id: 'nearby_${product.id}',
          authorId: product.sellerId,
          createdAt: DateTime.now(),
          tags: product.tags,
          likeCount: 0,
          commentCount: 0,
          likedByMe: false,
          product: product,
        ),
        proof: product.saveCount >= ProductItem.proofThreshold,
      ),
    );
  }
}

/// Everyone this viewer follows, for the Following tab.
final followedPeopleProvider = StreamProvider<Set<String>>((ref) {
  if (ref.watch(isGuestProvider)) return Stream.value(const {});
  return ref.watch(socialRepositoryProvider).watchFollowedPeople();
});
