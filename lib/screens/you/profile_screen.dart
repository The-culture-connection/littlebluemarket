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
import '../../widgets/screen.dart';
import '../../widgets/seller_drafts.dart';
import '../../widgets/seller_products_grid.dart';
import '../../widgets/skeleton.dart';
import '../market/results_screen.dart';

/// Your own profile: the Instagram layout, remapped.
///
/// The envelope opens messages and the overflow button opens shipping, which
/// is where package and tracking information lives.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int _tab = 0;

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

    return LbmScreen(
      appBar: LbmAppBar(
        showBack: false,
        centerTitle: true,
        titleSize: 17,
        title: me.handle,
        actions: [
          CircleIconButton(
            icon: Icons.mail_outline_rounded,
            tooltip: 'Messages',
            badge: (unread ?? 0) > 0,
            onPressed: () => context.push('/you/messages'),
          ),
          CircleIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'Packages and shipping',
            onPressed: () => context.push('/you/shipping'),
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
            // A seller gets their shop first. The labels are shorter when there
            // are three, so the pill row survives large text.
            SegmentedTabs(
              labels: me.isSeller
                  ? const ['Products', 'Posted', 'Bought']
                  : const ['Posted', 'Bought & received'],
              selected: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            // The tab now actually switches the grid. It was tracked and ignored.
            switch ((me.isSeller, _tab)) {
              (true, 0) => Column(
                children: [
                  const SellerDraftsPanel(),
                  SellerProductsGrid(sellerId: me.id, own: true),
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
            onTap: () => context.goToProduct(purchase.productId),
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
