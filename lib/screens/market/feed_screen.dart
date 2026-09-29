import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/feed_item.dart';
import '../../models/models.dart';
import '../../state/feed_items.dart';
import '../../state/providers.dart';
import '../../state/location.dart';
import '../../state/notifications_ui.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/directory_listing_card.dart';
import '../../widgets/filter_chips.dart';
import '../../widgets/hero_banner.dart';
import '../../widgets/masonry.dart';
import '../../widgets/pins/announcement_pin.dart';
import '../../widgets/pins/cart_pin.dart';
import '../../widgets/pins/chat_pin.dart';
import '../../widgets/pins/directory_pin.dart';
import '../../widgets/pins/makers_rail.dart';
import '../../widgets/pins/donation_nudge_pin.dart';
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

/// Which way into the feed is showing.
///
/// Following was here too and is gone (Grace, 2026-09-25): with tags not yet
/// followable it could only ever filter by people, which on a young market
/// is an empty screen most of the time.
enum _Tab { forYou, nearMe }

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _controller = ScrollController();

  /// Which tab is showing is *derived*, not held here.
  ///
  /// Near me is one question asked from three places: this tab, the row on
  /// the search screen, and the chip on the results screen. While the tab
  /// was a `setState` field, the search screen could turn the filter on and
  /// send you to the Market, where the tab was still on For you and nothing
  /// looked as though it had happened (Grace, 2026-09-28). One flag, read by
  /// everything, is the only arrangement where they cannot disagree.
  _Tab get _tab =>
      ref.read(searchFiltersProvider).nearMe ? _Tab.nearMe : _Tab.forYou;

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

  /// Near me is a different question ("what is close"), asked of the
  /// catalogue rather than of the post stream, so the tab only ever moves by
  /// moving the flag. Turning it on can fail — there has to be somewhere to
  /// measure from — and when it does the flag stays off and so does the tab,
  /// which is the right outcome: an empty Near me grid explains nothing.
  void _selectTab(int index) {
    final next = _Tab.values[index];
    if (next == _tab) return;
    if (next == _Tab.nearMe) {
      toggleNearMe(context, ref);
    } else {
      ref.read(searchFiltersProvider.notifier).toggleNearMe();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isGuest = ref.watch(isGuestProvider);
    // Watched, not read: the search screen can turn Near me on from another
    // route, and this screen has to redraw on the way back to it.
    final tab = ref.watch(searchFiltersProvider).nearMe
        ? _Tab.nearMe
        : _Tab.forYou;

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
              labels: const ['For you', 'Near me'],
              selected: tab.index,
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
        child: switch (tab) {
          _Tab.nearMe => _NearMeGrid(controller: _controller),
          _Tab.forYou => _Grid(controller: _controller, isGuest: isGuest),
        },
      ),
    );
  }
}

/// The grid.
class _Grid extends ConsumerWidget {
  const _Grid({required this.controller, required this.isGuest});

  final ScrollController controller;
  final bool isGuest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(feedItemsProvider);
    final ui = ref.watch(notificationsUiProvider);
    final filter = ref.watch(feedFilterProvider);

    final header = <Widget>[
      SliverToBoxAdapter(
        child: FilterChips(
          items: FeedFilter.chips,
          selected: filter,
          onSelect: ref.read(feedFilterProvider.notifier).select,
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 10)),
      // The day's news: one banner, always the same size, scrolling with the
      // grid rather than pinned above it.
      const SliverToBoxAdapter(child: HeroBanner()),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
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
      data: (shown) {
        if (shown.isEmpty) {
          return CustomScrollView(
            controller: controller,
            slivers: [
              ...header,
              const SliverFillRemaining(
                hasScrollBody: false,
                child: LbmEmpty(
                  title: 'Nothing posted yet',
                  body: 'When sellers list something nearby, it shows up here.',
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
                for (final item in shown)
                  _GrowIn(
                    key: ValueKey('grow:${item.key}'),
                    active: ui.fresh.contains(item.key),
                    onDone: () => ref
                        .read(notificationsUiProvider.notifier)
                        .settled(item.key),
                    child: _pinFor(context, ref, item, ui),
                  ),
              ],
              wide: [for (final item in shown) isFullWidth(item)],
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
}

/// One pin per kind. Exhaustive on purpose: a new [FeedItem] is a compile
/// error here rather than a hole in the grid.
Widget _pinFor(
  BuildContext context,
  WidgetRef ref,
  FeedItem item,
  NotificationsUiState ui,
) => switch (item) {
  ProductItem i => ProductPin(
    key: ValueKey(i.key),
    item: i,
    hop: ui.fresh.contains(i.key),
  ),
  ReviewItem i => ReviewPin(key: ValueKey(i.key), item: i),
  CartItem i => CartPin(
    key: ValueKey(i.key),
    item: i,
    onAddAll: () => addManyToCart(context, ref, [
      for (final line in i.post.items) line.productId,
    ]),
  ),
  ShoutoutItem i => ShoutoutPin(key: ValueKey(i.key), item: i),
  DirectoryItem i => DirectoryPin(key: ValueKey(i.key), item: i),
  ThreadItem i => ThreadPin(
    key: ValueKey(i.key),
    item: i,
    newCount: ui.threadNew[i.thread.id] ?? 0,
    onTap: () {
      ref.read(notificationsUiProvider.notifier).seenThread(i.thread.id);
      context.go('/community/thread/${i.thread.id}');
    },
  ),
  ChatItem i => ChatPin(key: ValueKey(i.key), item: i),
  // Announcements are the banner above the grid, never a pin in it.
  AnnouncementItem i => AnnouncementPin(key: ValueKey(i.key), item: i),
  // The chip-in nudge is its own pin: sage, and it carries a number read
  // from funding/{month} rather than a fixed line. No hop: it arrives on
  // its own cadence rather than because something just happened.
  NudgeItem i when i.nudge == NudgeKind.chipIn => DonationNudgePin(
    key: ValueKey(i.key),
    onTap: () => _openNudge(context, ref, i),
    onDismiss: () =>
        ref.read(dismissedNudgesProvider.notifier).dismiss(i.dismissKey),
  ),
  NudgeItem i => NudgePin(
    key: ValueKey(i.key),
    item: i,
    hop: ui.fresh.contains(i.key),
    onTap: () => _openNudge(context, ref, i),
    onDismiss: () =>
        ref.read(dismissedNudgesProvider.notifier).dismiss(i.dismissKey),
  ),
  MakersRailItem i => MakersRail(key: ValueKey(i.key), item: i),
};
void _openNudge(BuildContext context, WidgetRef ref, NudgeItem item) {
  switch (item.nudge) {
    case NudgeKind.reviewDelivered:
      // The list of what they bought, not the one product: somebody being
      // prompted to review usually has more than one thing waiting, and the
      // product page is about buying it again.
      context.go('/you/purchases');
    case NudgeKind.sayHi:
      context.go('/community');
    case NudgeKind.forumActivity:
      context.go('/community/forums');
    case NudgeKind.chipIn:
      context.go('/you/chip-in');
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
    // Directory businesses too, and they are most of the answer: a product
    // takes its point from its seller's profile city and almost no vendor
    // has typed one, while a directory listing carries the town the website
    // holds for it (Grace, 2026-09-28). Watched beside the products rather
    // than gated with them, so a slow or empty catalogue cannot hide them.
    final businesses =
        ref.watch(nearbyBusinessesProvider(filters)).value ?? const [];
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
        if (products.isEmpty && businesses.isEmpty) {
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
                      'the whole Market. Something counts as nearby once its '
                      'shop or its directory listing says what town it is in.',
                ),
              ),
            ],
          );
        }

        return CustomScrollView(
          controller: controller,
          slivers: [
            ...header,
            if (products.isNotEmpty)
              ...LbmMasonry.slivers(
                children: [
                  for (final product in products)
                    _NearbyPin(key: ValueKey(product.id), product: product),
                ],
                bottom: businesses.isEmpty ? 24 : 8,
              ),
            if (businesses.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: SectionHead('Businesses near you'),
              ),
              SliverList.builder(
                itemCount: businesses.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: DirectoryListingCard(
                    key: ValueKey('near_${businesses[i].id}'),
                    listing: businesses[i],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
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

/// A pin that arrived while the feed was up grows in from the top: past its
/// height with a half-degree lean, back, and settled, the way the mockup's
/// drop pin lands. Always in the tree around every pin, so a pin whose
/// arrival is announced a moment after it appears still gets it, and the
/// pin inside is never rebuilt from scratch when the growing stops.
class _GrowIn extends StatefulWidget {
  const _GrowIn({
    super.key,
    required this.active,
    required this.onDone,
    required this.child,
  });

  final bool active;
  final VoidCallback onDone;
  final Widget child;

  @override
  State<_GrowIn> createState() => _GrowInState();
}

class _GrowInState extends State<_GrowIn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    // The grow, then time for the button's hop to finish before the pin is
    // told it is no longer new.
    duration: LbmMotion.grow + LbmMotion.hop,
    value: 1,
  );

  static final _scaleY = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: 1.06), weight: 60),
    TweenSequenceItem(tween: Tween(begin: 1.06, end: .98), weight: 20),
    TweenSequenceItem(tween: Tween(begin: .98, end: 1), weight: 20),
  ]);
  static final _lean = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: -2, end: .6), weight: 60),
    TweenSequenceItem(tween: Tween(begin: .6, end: -.3), weight: 20),
    TweenSequenceItem(tween: Tween(begin: -.3, end: 0), weight: 20),
  ]);

  double get _growEnd =>
      LbmMotion.grow.inMicroseconds / _controller.duration!.inMicroseconds;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(_GrowIn old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _start();
  }

  void _start() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        widget.onDone();
        return;
      }
      _controller.forward(from: 0).whenComplete(() {
        if (mounted) widget.onDone();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = (_controller.value / _growEnd).clamp(0.0, 1.0);
        if (t >= 1) return child!;
        return Opacity(
          opacity: (t * 2.5).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.topCenter,
            transform: Matrix4.identity()
              ..rotateZ(_lean.transform(t) * 3.141592653589793 / 180)
              ..scaleByDouble(1, _scaleY.transform(t), 1, 1),
            child: child,
          ),
        );
      },
    );
  }
}
