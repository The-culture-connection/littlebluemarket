import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/feed_item.dart';
import '../models/models.dart';
import '../router/nav.dart';
import '../state/feed_tab.dart';
import '../state/providers.dart';
import '../state/tags.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/masonry.dart';
import '../widgets/skeleton.dart';
import '../widgets/pins/product_pin.dart';
import '../widgets/pins/review_pin.dart';
import '../widgets/pins/cart_pin.dart';
import '../widgets/pins/shoutout_pin.dart';
import '../widgets/primitives.dart';

/// The feed, narrowed to the people and tags this person follows.
///
/// In its own file rather than inside `feed_screen.dart`: this phase is
/// being built in a parallel worktree and that screen is the one the other
/// session is most likely to be in, so the insertion there is a `switch`
/// arm and everything else is here.
///
/// The empty state is the point of the whole tab. Following was removed in
/// the redesign because it could only filter by people and that was a blank
/// screen on a young market; putting it first again is only defensible if
/// somebody who follows nothing is offered a way out of it rather than
/// shown a void.
class FollowingGrid extends ConsumerWidget {
  const FollowingGrid({super.key, this.controller});

  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(followedPeoplePostsProvider);
    final products = ref.watch(followedTagProductsProvider);

    // A followed maker whose listing is also under a followed tag would
    // otherwise arrive twice, once as their post and once as the product.
    // The post wins: it says who put it up.
    final posted = {
      for (final post in posts)
        if (post is ListingPost) post.product.id,
    };

    if (posts.isEmpty && products.isEmpty) {
      // Still asking. An empty state shown to somebody who follows twenty
      // makers is the app calling them wrong, so it waits instead.
      if (ref.watch(followingLoadingProvider)) {
        return const GridSkeleton(count: 6);
      }
      return _Empty(controller: controller);
    }

    return CustomScrollView(
      controller: controller,
      slivers: LbmMasonry.slivers(
        children: [
          for (final post in posts) ?pinFor(post),
          // What the tags you follow have on the market. Products rather
          // than posts because that is where a hashtag lives here.
          for (final product in products)
            if (!posted.contains(product.id))
              ProductPin(
                key: ValueKey('tag_${product.id}'),
                item: ProductItem(
                  // The same standing-in listing the tag page builds: a
                  // pin is drawn from a post, and a product that nobody
                  // posted about still belongs under its own hashtag.
                  ListingPost(
                    id: 'tag_${product.id}',
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
        bottom: 24,
      ),
    );
  }

  /// The same pins the main grid draws. Listings, reviews, carts and
  /// shoutouts are what a person posts; a thread or a chat moment is not
  /// somebody you follow, so neither appears here.
  static Widget? pinFor(Post post) => switch (post) {
    ListingPost p => ProductPin.of(
      p,
      key: ValueKey(p.id),
      proof: p.product.saveCount >= ProductItem.proofThreshold,
    ),
    ReviewPost p => ReviewPin.of(p, key: ValueKey(p.id)),
    CartPost p => CartPin.of(p, key: ValueKey(p.id)),
    ShoutoutPost p => ShoutoutPin.of(p, key: ValueKey(p.id)),
    _ => null,
  };
}

/// Nothing followed yet, with four ways to fix that in one tap.
class _Empty extends ConsumerWidget {
  const _Empty({this.controller});

  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tags = ref.watch(popularTagsProvider).value ?? const [];
    final followed = ref.watch(followedTagsProvider).value ?? const <String>{};

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
      children: [
        Icon(Icons.group_outlined, size: 34, color: c.ink3),
        const SizedBox(height: 12),
        Text(
          'Nothing yet',
          textAlign: TextAlign.center,
          style: LbmText.display.copyWith(fontSize: 20, color: c.ink),
        ),
        const SizedBox(height: 6),
        Text(
          'Follow a maker or a #tag and it lands here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: c.ink2),
        ),
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in tags.take(4))
              LbmChip(
                tagLabel(tag.tag),
                style: followed.contains(tagKey(tag.tag))
                    ? ChipStyle.on
                    : ChipStyle.quiet,
                // Follows on the spot rather than opening the tag page: the
                // person is here because this tab is empty, and a tap that
                // navigates away leaves it empty.
                onTap: () => ref
                    .read(socialRepositoryProvider)
                    .setFollowingTag(tag.tag, on: true),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Center(
          child: PillButton(
            'Shop the Market',
            style: PillStyle.ghost,
            expand: false,
            onPressed: () => context.goToResults(''),
          ),
        ),
      ],
    );
  }
}
