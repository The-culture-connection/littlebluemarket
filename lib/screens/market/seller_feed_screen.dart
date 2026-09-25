import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/feed_item.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/directory_storefront.dart';
import '../../widgets/filter_chips.dart';
import '../../widgets/masonry.dart';
import '../../widgets/pins/product_pin.dart';
import '../../widgets/primitives.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/screen.dart';
import '../../widgets/sheets.dart';
import '../../widgets/skeleton.dart';

/// The public view of a profile.
///
/// Same layout as your own, minus the add-post button and shipping. One Message
/// button, and no Follow — there is no follow relationship in the product at
/// all.
class SellerFeedScreen extends ConsumerStatefulWidget {
  const SellerFeedScreen({super.key, required this.personId});

  final String personId;

  @override
  ConsumerState<SellerFeedScreen> createState() => _SellerFeedScreenState();
}

class _SellerFeedScreenState extends ConsumerState<SellerFeedScreen> {
  int _tab = 0;

  static const _tabKeys = ['shop', 'reviews', 'about'];
  String get _tabKey => _tabKeys[_tab];
  static int _indexOf(String key) => _tabKeys.indexOf(key).clamp(0, 2);

  @override
  Widget build(BuildContext context) {
    final person = ref.watch(personProvider(widget.personId));
    // A directory business shows a storefront the way a Market seller does:
    // the listing's photos, then what it sells on its own website.
    final hasDirectory = ref.watch(
      hasDirectoryStorefrontProvider(widget.personId),
    );

    return LbmScreen(
      appBar: LbmAppBar(
        title: switch (person.value?.handle) {
          null || '' => 'Profile',
          final handle => handle,
        },
        actions: [
          CircleIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More',
            onPressed: () {
              final p = person.value;
              if (p == null) return;
              showMoreSheet(
                context,
                ref,
                subjectUid: p.id,
                subjectName: p.name,
                subjectHandle: p.handle,
              );
            },
          ),
        ],
      ),
      child: LbmAsync<Person>(
        person,
        skeleton: const IdentitySkeleton(),
        onRetry: () => ref.invalidate(personProvider(widget.personId)),
        data: (person) => ListView(
          padding: EdgeInsets.zero,
          children: [
            _MakerHeader(
              person: person,
              canNotify:
                  !person.unclaimed &&
                  ref.watch(currentUidProvider) != person.id,
            ),
            // A buyer has no shop, so they get one tab rather than an empty
            // one. The first tab is the shop's **products**, and used to be
            // labelled "Posted", which put a grid of products under a word
            // that means something else and directly under a "Posts" count
            // that disagreed with it: a shop showing "1 Posts" above twelve
            // product tiles looked plainly broken (Grace, 2026-09-24).
            if (person.isSeller || hasDirectory)
              FilterChips(
                items: const [
                  ('shop', 'Shop'),
                  ('reviews', 'Reviews'),
                  ('about', 'About'),
                ],
                selected: _tabKey,
                onSelect: (key) => setState(() => _tab = _indexOf(key)),
              ),
            const SizedBox(height: 12),
            if ((person.isSeller || hasDirectory) && _tab == 0) ...[
              if (hasDirectory) DirectoryPhotoStrip(ownerUid: person.id),
              if (person.isSeller) _ShopGrid(sellerId: person.id),
              if (hasDirectory)
                DirectoryProductsGrid(
                  ownerUid: person.id,
                  heading: person.isSeller ? 'Sold on their website' : null,
                ),
              // Everything this shop has is on this one tab, so the
              // littlebluecart.com listings belong here too rather than in a
              // band of their own above the tabs, where they read as part of
              // the profile header (Grace, 2026-09-24: a products tab
              // "which will also list directory listings").
              DirectoryListings(ownerUid: person.id),
            ] else if (_tab == 2)
              _About(person: person)
            else
              _ReviewsWritten(personId: person.id),
            const SizedBox(height: 26),
          ],
        ),
      ),
    );
  }
}

/// The top of a maker's board: who they are, then what they are worth
/// knowing, then the two things you can do about it.
///
/// Centred rather than the left-aligned identity block the You hub uses. A
/// shop is a place you arrive at, and the maker is the subject of the screen
/// rather than a row at the top of your own.
class _MakerHeader extends ConsumerWidget {
  const _MakerHeader({required this.person, required this.canNotify});

  final Person person;
  final bool canNotify;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final products = ref.watch(sellerProductsProvider(person.id)).value;
    // Every cart their shelf is sitting in, added up across the page that
    // has loaded. The affinity number on this market.
    final carted = products?.fold<int>(0, (sum, p) => sum + p.saveCount);
    // Counted, not measured off the grid: a shop's products arrive thirty
    // at a time, so a number taken from the first page says 30 for a shop
    // with 214, and a header that disagrees with the tiles under it is the
    // complaint that started this (Grace, 2026-09-24).
    final listings = person.isSeller
        ? ref.watch(sellerProductCountProvider(person.id)).value
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Avatar(person, size: AvatarSize.lg)),
          const SizedBox(height: 10),
          Text(
            person.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: LbmText.display.copyWith(fontSize: 24, color: c.ink),
          ),
          if (person.cityState.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              // Where they are, and nothing about when they joined: a
              // profile carries no creation date, and the mockup's
              // "joined March 2024" would be a number we invented.
              person.cityState,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LbmText.pinMeta.copyWith(fontSize: 12.5, color: c.ink2),
            ),
          ],
          if (person.bio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              person.bio,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: LbmText.tiny.copyWith(height: 1.45, color: c.ink2),
            ),
          ],
          if (person.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Center(
              child: TagChips(
                person.tags,
                onTap: (tag) => context.goToTag(tag),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  'Message',
                  style: PillStyle.ghost,
                  onPressed: () => requireProfile(
                    context,
                    ref,
                    () => context.goToDm(person.id),
                  ),
                ),
              ),
              if (canNotify) ...[
                const SizedBox(width: 8),
                Expanded(child: _NotifyMeButton(personId: person.id)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _MakerStats(person: person, carted: carted, listings: listings),
        ],
      ),
    );
  }
}

/// What a shop is worth knowing at a glance.
///
/// Only numbers this system actually holds. The mockup shows a reply time
/// and a star rating for the shop; neither exists, so neither is drawn.
class _MakerStats extends StatelessWidget {
  const _MakerStats({
    required this.person,
    required this.carted,
    required this.listings,
  });

  final Person person;
  final int? carted;

  /// Null while it is still being counted: a shop with two hundred products
  /// flashing "0" for a moment is worse than one that admits it is counting.
  final int? listings;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: LbmRadius.cardR,
        boxShadow: c.shadowSoft,
      ),
      child: Row(
        children: [
          if (person.isSeller)
            Expanded(
              child: _Stat(
                // Gross, and the label says so: this is what buyers paid,
                // not what the maker took home.
                value: person.grossSalesLabel,
                label: 'Total sales',
              ),
            ),
          if (person.isSeller)
            Expanded(
              child: _Stat(
                value: listings == null ? '—' : Fmt.count(listings!),
                label: 'Listings',
              ),
            ),
          if (person.isSeller)
            Expanded(
              child: _Stat(
                value: carted == null ? '—' : Fmt.count(carted!),
                label: 'Carted',
              ),
            ),
          if (!person.isSeller) ...[
            Expanded(
              child: _Stat(value: '${person.purchases}', label: 'Bought'),
            ),
            Expanded(child: _Stat(value: '${person.posts}', label: 'Posts')),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          child: Text(
            value,
            maxLines: 1,
            style: LbmText.display.copyWith(
              fontSize: 19,
              color: c.ink,
              fontFeatures: kTabularFigures,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LbmText.pinMeta.copyWith(fontSize: 11, color: c.ink2),
        ),
      ],
    );
  }
}

/// The shop's shelf, in the same grid as everywhere else.
class _ShopGrid extends ConsumerWidget {
  const _ShopGrid({required this.sellerId});

  final String sellerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(sellerProductsProvider(sellerId));

    return LbmAsync<List<Product>>(
      products,
      skeleton: const GridSkeleton(count: 4),
      isEmpty: (all) => all.isEmpty,
      empty: const LbmEmpty(
        title: 'Nothing listed yet',
        body: 'When they list something it shows up here.',
        compact: true,
      ),
      data: (all) => LbmMasonry.fixed(
        children: [
          for (final product in all)
            ProductPin(
              key: ValueKey('shop_${product.id}'),
              item: ProductItem(
                ListingPost(
                  id: 'shop_${product.id}',
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
            ),
        ],
      ),
    );
  }
}

/// Everything the profile says in words.
class _About extends StatelessWidget {
  const _About({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: LbmCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              person.bio.isEmpty
                  ? 'They have not written anything about themselves yet.'
                  : person.bio,
              style: LbmText.body.copyWith(color: c.ink2),
            ),
            const SizedBox(height: 12),
            _AboutRow(label: 'Handle', value: person.handle),
            if (person.cityState.isNotEmpty)
              _AboutRow(label: 'Where', value: person.cityState),
            _AboutRow(
              label: 'On the market',
              value: person.isSeller ? 'A maker with a shop' : 'A buyer',
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: LbmText.pinMeta.copyWith(
                fontWeight: FontWeight.w800,
                color: c.ink2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: LbmText.pinMeta.copyWith(fontSize: 12.5, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Follow someone for a push when they post. One tap on, one tap off; the
/// label says which state you are in so the button never needs a tooltip.
class _NotifyMeButton extends ConsumerStatefulWidget {
  const _NotifyMeButton({required this.personId});

  final String personId;

  @override
  ConsumerState<_NotifyMeButton> createState() => _NotifyMeButtonState();
}

class _NotifyMeButtonState extends ConsumerState<_NotifyMeButton> {
  var _busy = false;

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(socialRepositoryProvider)
          .setFollowing(widget.personId, on);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            on
                ? 'You will hear when they post.'
                : 'No more posts from them.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e).body)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final following =
        ref.watch(followingProvider(widget.personId)).value ?? false;
    return PillButton(
      following ? 'Notifying you' : 'Notify me',
      icon: following
          ? Icons.notifications_active_rounded
          : Icons.notifications_none_rounded,
      style: following ? PillStyle.quiet : PillStyle.ghost,
      onPressed: _busy
          ? null
          : () => requireProfile(context, ref, () => _toggle(!following)),
    );
  }
}

class _ReviewsWritten extends ConsumerWidget {
  const _ReviewsWritten({required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(postsByProvider(personId));

    return LbmAsync<List<Post>>(
      posts,
      skeleton: const ListRowSkeleton(rows: 2),
      data: (all) {
        final reviews = all.whereType<ReviewPost>().toList();
        if (reviews.isEmpty) {
          return const LbmEmpty(title: 'No reviews written yet', compact: true);
        }
        return Column(
          children: [
            for (final post in reviews)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: LbmCard(
                  padding: EdgeInsets.zero,
                  onTap: () => context.goToPost(post.id),
                  child: ListRow(
                    leading: Stars(post.rating.toDouble(), size: 12),
                    title: Text(
                      post.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(post.age),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
