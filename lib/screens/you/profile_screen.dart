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
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/profile_identity.dart';
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
        centerTitle: true,
        titleSize: 17,
        title: me.handle,
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
            ProfileIdentity(
              person: me,
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        'Edit profile',
                        style: PillStyle.ghost,
                        onPressed: () => context.push('/you/edit'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    PillButton(
                      'Post',
                      icon: Icons.add_rounded,
                      expand: false,
                      onPressed: () => showNewPostSheet(context, ref),
                    ),
                  ],
                ),
              ],
            ),
            const _DirectoryCard(),
            // A seller gets their shop first. The labels are shorter when there
            // are three, so the pill row survives large text.
            SegmentedTabs(
              labels: sellerLike
                  ? const ['Products', 'Posted', 'Bought']
                  : const ['Posted', 'Bought & received'],
              selected: tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
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

/// The littlebluecart.com row, for an account that is joined to it. Nothing
/// at all otherwise: the door is in Edit profile.
class _DirectoryCard extends ConsumerWidget {
  const _DirectoryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final link = ref.watch(directoryLinkProvider).value;
    if (link == null || !link.linked) return const SizedBox.shrink();
    String plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: LbmCard(
        child: ListRow(
          leading: Icon(Icons.storefront_outlined, color: c.ink3),
          title: const Text('Little Blue Cart directory'),
          subtitle: Text(
            '${plural(link.listingCount, 'listing')} · '
            '${plural(link.orderCount, 'website order')}',
          ),
          trailing: Icon(Icons.chevron_right_rounded, size: 22, color: c.ink3),
          onTap: () => context.push('/you/directory'),
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
