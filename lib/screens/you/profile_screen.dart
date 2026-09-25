import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/filter_chips.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/composers.dart';
import '../../widgets/directory_storefront.dart';
import '../../widgets/screen.dart';
import '../../widgets/seller_drafts.dart';
import '../../widgets/seller_products_grid.dart';
import '../../widgets/sheets.dart';
import '../../widgets/skeleton.dart';
import '../market/results_screen.dart';

/// Your own profile: the Instagram layout, remapped.
///
/// The envelope opens messages and the overflow button opens shipping, which
/// is where package and tracking information lives.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.openBought = false});

  /// Open on the Bought tab: the landing for someone who came through the
  /// "I've bought on Little Blue Market" door.
  final bool openBought;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Null until the person picks one, so the first tab can depend on
  /// whether they are a seller (Bought is the third tab then, the second
  /// otherwise).
  int? _tab;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final unread = ref
        .watch(inboxProvider)
        .value
        ?.fold<int>(0, (sum, conversation) => sum + conversation.unread);

    if (me == null) {
      return const LbmScreen(
        appBar: LbmAppBar(showBack: false, centerTitle: true, title: 'You'),
        child: IdentitySkeleton(),
      );
    }

    // A business joined to the directory gets the seller layout too: its
    // Products tab is the listing's photos and what it sells on its website.
    final directoryLinked =
        ref.watch(directoryLinkProvider).value?.linked ?? false;
    final sellerLike = me.isSeller || directoryLinked;
    final tab = _tab ?? (widget.openBought ? (sellerLike ? 2 : 1) : 0);

    return LbmScreen(
      appBar: LbmAppBar(
        showBack: false,
        titleSize: 22,
        title: 'You',
        actions: [
          CircleIconButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Notifications',
            badge: ref.watch(unreadNotificationsProvider) > 0,
            onPressed: () => context.push('/you/notifications'),
          ),
          CircleIconButton(
            icon: Icons.mail_outline_rounded,
            tooltip: 'Messages',
            badge: (unread ?? 0) > 0,
            onPressed: () => context.push('/you/messages'),
          ),
          CircleIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Edit profile',
            onPressed: () => context.push('/you/edit'),
          ),
        ],
      ),
      // Pull to refresh re-reads every grid. The products one matters most:
      // right after a shop is claimed the backend takes a few seconds to
      // attribute the catalog, and a cached empty answer would otherwise
      // stick until the next launch.
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(sellerProductsProvider(me.id));
          ref.invalidate(postsByProvider(me.id));
          ref.invalidate(purchasesProvider);
          if (me.isSeller) {
            // The pull side of approval. Errors are not worth a card here;
            // the chips simply stay as they were.
            try {
              await ref.read(sellerRepositoryProvider).refreshListings();
            } on RepositoryException {
              // Left to the next pull.
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _YouIdentity(person: me),
            _YouStats(person: me),
            // One quiet prompt, and only when there is something waiting.
            const _ReviewBanner(),
            if (sellerLike)
              _QuietRow(
                icon: Icons.storefront_outlined,
                title: 'Your shop',
                subtitle: 'Listings, what is under review, sales',
                onTap: () => context.push('/you/sell'),
              )
            else
              _QuietRow(
                icon: Icons.add_business_outlined,
                title: 'Got something to sell?',
                subtitle: 'Apply to open a shop',
                onTap: () => context.push('/you/sell'),
              ),
            const SizedBox(height: 6),
            // A seller gets their shop first. The labels are shorter when there
            // are three, so the row survives large text.
            FilterChips(
              items: sellerLike
                  ? const [
                      ('products', 'Products'),
                      ('posts', 'Posts'),
                      ('bought', 'Bought'),
                    ]
                  : const [('posts', 'Posts'), ('bought', 'Bought')],
              selected: (sellerLike
                  ? ['products', 'posts', 'bought']
                  : ['posts', 'bought'])[tab],
              onSelect: (key) => setState(() {
                _tab = (sellerLike
                    ? ['products', 'posts', 'bought']
                    : ['posts', 'bought']).indexOf(key);
              }),
            ),
            const SizedBox(height: 12),
            // The tab now actually switches the grid. It was tracked and ignored.
            // Market products first, the directory's after: a directory
            // business that later joins the Market keeps its website-link
            // products; Shopify simply takes the top of the tab.
            switch ((sellerLike, tab)) {
              (true, 0) => Column(
                children: [
                  if (directoryLinked)
                    DirectoryPhotoStrip(ownerUid: me.id, own: true),
                  if (me.isSeller) ...[
                    const SellerDraftsPanel(),
                    SellerProductsGrid(sellerId: me.id, own: true),
                  ],
                  if (directoryLinked)
                    DirectoryProductsGrid(
                      ownerUid: me.id,
                      own: true,
                      heading: me.isSeller ? 'Sold on your website' : null,
                    ),
                  // The same tab a visitor sees, so what you check here is
                  // what they get. Your pending listings are in it too.
                  if (directoryLinked)
                    DirectoryListings(ownerUid: me.id, own: true),
                ],
              ),
              (true, 1) || (false, 0) => _PostedGrid(personId: me.id),
              _ => const _PurchasesGrid(),
            },
            const Puff(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// Who you are, quietly.
///
/// No ring round the avatar, no points, no level, no streak: none of those
/// exist in this product and drawing them was the busiest part of the old
/// screen (Grace, 2026-09-25, "make it quieter").
class _YouIdentity extends StatelessWidget {
  const _YouIdentity({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(person, size: AvatarSize.lg),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  person.name.isEmpty ? 'Your profile' : person.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LbmText.display.copyWith(fontSize: 22, color: c.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (person.handle.isNotEmpty) person.handle,
                    if (person.cityState.isNotEmpty) person.cityState,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LbmText.pinMeta.copyWith(
                    fontSize: 12.5,
                    color: c.ink2,
                  ),
                ),
                if (person.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TagChips(
                    person.tags,
                    onTap: (tag) => context.goToTag(tag),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Four numbers, and only ones this system holds.
class _YouStats extends ConsumerWidget {
  const _YouStats({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final inCart = ref.watch(cartCountProvider);
    final posts = ref.watch(postsByProvider(person.id)).value;
    final reviews = posts?.whereType<ReviewPost>().length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: LbmRadius.cardR,
          boxShadow: c.shadowSoft,
        ),
        child: Row(
          children: [
            Expanded(
              child: _YouStat(value: '${person.purchases}', label: 'Bought'),
            ),
            Expanded(
              child: person.isSeller
                  // A seller's own number is what they have sold. Gross, and
                  // the label says so.
                  ? _YouStat(
                      value: person.grossSalesLabel,
                      label: 'Total sales',
                    )
                  : _YouStat(value: '$inCart', label: 'In cart'),
            ),
            Expanded(
              child: _YouStat(
                value: reviews == null ? '—' : '$reviews',
                label: 'Reviews',
              ),
            ),
            Expanded(
              child: _YouStat(value: '${person.posts}', label: 'Posts'),
            ),
          ],
        ),
      ),
    );
  }
}

class _YouStat extends StatelessWidget {
  const _YouStat({required this.value, required this.label});

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

/// The one banner on this screen: something you bought is waiting to be
/// reviewed.
///
/// Nothing about shipping, nothing about orders. Shipturtle owns those and
/// the app does not pretend to.
class _ReviewBanner extends ConsumerWidget {
  const _ReviewBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final purchases = ref.watch(purchasesProvider).value ?? const <Purchase>[];
    final waiting = [for (final p in purchases) if (p.canReview) p];
    if (waiting.isEmpty) return const SizedBox.shrink();

    final first = waiting.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: LbmCard(
        padding: const EdgeInsets.all(10),
        onTap: () => context.push('/you/purchases'),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              child: SizedBox(
                width: 36,
                height: 36,
                child: ColoredBox(
                  color: c.skyWash,
                  child: first.imageUrl == null || first.imageUrl!.isEmpty
                      ? Icon(Icons.star_rounded, size: 18, color: c.accent)
                      : ProductPhoto(
                          url: first.imageUrl!,
                          cacheWidth: 110,
                          fallback: ColoredBox(color: c.skyMist),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                waiting.length == 1
                    ? 'One thing you bought is waiting for a review'
                    : '${waiting.length} things you bought are waiting for '
                          'a review',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LbmText.pinMeta.copyWith(
                  fontSize: 12.5,
                  color: c.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            LbmChip('Rate', accent: true, fontSize: 12.5),
          ],
        ),
      ),
    );
  }
}

/// A single quiet row: an icon, two lines, and a chevron.
class _QuietRow extends StatelessWidget {
  const _QuietRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: LbmCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.skyDeep),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LbmText.pinTitle.copyWith(
                      fontSize: 14,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LbmText.pinMeta.copyWith(color: c.ink2),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.ink3),
          ],
        ),
      ),
    );
  }
}

class _PostedGrid extends ConsumerWidget {
  const _PostedGrid({required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(postsByProvider(personId));

    return LbmAsync<List<Post>>(
      posts,
      skeleton: const GridSkeleton(count: 6),
      onRetry: () => ref.invalidate(postsByProvider(personId)),
      isEmpty: (posts) => posts.isEmpty,
      empty: const LbmEmpty(
        title: 'Nothing posted yet',
        body: 'Your listings, reviews and shoutouts land here.',
      ),
      data: (posts) => _Grid(
        count: posts.length,
        builder: (i) {
          final post = posts[i];
          final productId = post.subjectProductId;
          if (productId == null) {
            return _TextCell(
              post: post,
              onTap: () => context.goToPost(post.id),
            );
          }
          return _ProductCell(
            productId: productId,
            badge: post is ReviewPost ? 'Review' : null,
            onTap: () => context.goToPost(post.id),
          );
        },
      ),
    );
  }
}

class _PurchasesGrid extends ConsumerWidget {
  const _PurchasesGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchases = ref.watch(purchasesProvider);

    return LbmAsync<List<Purchase>>(
      purchases,
      skeleton: const GridSkeleton(count: 6),
      isEmpty: (purchases) => purchases.isEmpty,
      empty: const LbmEmpty(
        title: 'Nothing bought yet',
        body: 'What you buy shows here, ready to review.',
      ),
      data: (purchases) => _Grid(
        count: purchases.length,
        builder: (i) {
          final purchase = purchases[i];
          return _ProductCell(
            productId: purchase.productId,
            // Data, not grid position. The prototype badged the first two
            // cells of the second tab regardless of what they were.
            badge: purchase.reviewed
                ? 'Reviewed'
                : (purchase.delivered ? 'Received' : null),
            // A purchase is something you can review, not only something you
            // can look at again.
            onTap: () => showPurchaseSheet(context, purchase),
          );
        },
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.count, required this.builder});

  final int count;
  final Widget Function(int index) builder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 7,
          crossAxisSpacing: 7,
        ),
        itemCount: count,
        itemBuilder: (context, i) => builder(i),
      ),
    );
  }
}

class _ProductCell extends ConsumerWidget {
  const _ProductCell({
    required this.productId,
    required this.onTap,
    this.badge,
  });

  final String productId;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productProvider(productId));
    return LbmAsync<Product>(
      product,
      skeleton: const LbmSkeleton.block(height: double.infinity),
      errorBuilder: (_, _) => const LbmSkeleton.block(height: double.infinity),
      data: (product) => GridCell(product: product, badge: badge, onTap: onTap),
    );
  }
}

/// A shoutout has no product art, so it shows its own words.
class _TextCell extends StatelessWidget {
  const _TextCell({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = switch (post) {
      final ShoutoutPost s => s.text,
      final DirectoryPost d => d.title,
      final CartPost cart =>
        '🛒 ${cart.itemCount} ${cart.itemCount == 1 ? 'thing' : 'things'}'
            '${cart.caption == null ? '' : '\n${cart.caption}'}',
      _ => '',
    };
    return LbmCard(
      color: c.skyMist,
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Center(
        child: Text(
          text,
          maxLines: 4,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: LbmText.xtiny.copyWith(color: c.ink2, height: 1.45),
        ),
      ),
    );
  }
}

/// What you can do with something you bought: review it, or open it.
Future<void> showPurchaseSheet(BuildContext context, Purchase purchase) {
  return showLbmSheet(context, (sheetContext) {
    final c = sheetContext.c;
    // Shipping lives in Shipturtle and the store's emails, not here, so an
    // undelivered purchase simply says when it was ordered.
    final status = purchase.reviewed
        ? 'Reviewed'
        : purchase.delivered
        ? 'Received ${purchase.age} ago'
        : 'Ordered ${purchase.age} ago';
    return LbmSheet(
      children: [
        Text(
          purchase.title,
          style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
        ),
        const SizedBox(height: 4),
        Text(status, style: LbmText.tiny.copyWith(color: c.ink2)),
        const SizedBox(height: 14),
        if (purchase.canReview) ...[
          PillButton(
            'Write a review',
            onPressed: () {
              Navigator.of(sheetContext).pop();
              showLbmSheet(
                context,
                (_) => ReviewComposer(initialPurchaseId: purchase.id),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        PillButton(
          'View product',
          style: PillStyle.ghost,
          onPressed: () {
            Navigator.of(sheetContext).pop();
            context.goToProduct(purchase.productId);
          },
        ),
      ],
    );
  });
}
