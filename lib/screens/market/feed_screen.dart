import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/post_card.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/tips.dart';
import 'collection_screen.dart';

/// The marketplace feed.
///
/// Rounded cards floating on soft blue rather than an edge-to-edge grid: a
/// search pill and Near me at the top, initiative hashtags below, then goods,
/// services, reviews and shoutouts in one chronological stream.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final isGuest = ref.watch(isGuestProvider);
    final filters = ref.watch(searchFiltersProvider);
    final tags = ref.watch(popularTagsProvider);
    final feed = ref.watch(feedProvider);

    return LbmScreen(
      appBar: Container(
        color: c.paper,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SearchPill(
                    label: 'Search goods, services, #tags',
                    onTap: () => context.push('/market/search'),
                  ),
                ),
                const SizedBox(width: 10),
                // Shares one SearchFilters with the results screen, so the
                // toggle here and the chips there cannot drift apart.
                NearMeButton(
                  active: filters.nearMe,
                  onTap: () =>
                      ref.read(searchFiltersProvider.notifier).toggleNearMe(),
                ),
                const SizedBox(width: 8),
                CircleIconButton(
                  icon: Icons.shopping_bag_outlined,
                  tooltip: 'Your cart',
                  badge: ref.watch(cartCountProvider) > 0,
                  onPressed: () => context.goToCart(),
                ),
              ],
            ),
            const SizedBox(height: 11),
            SizedBox(
              height: 32,
              child: LbmAsync<List<TagCount>>(
                tags,
                skeleton: const ChipRailSkeleton(),
                errorBuilder: (_, _) => const SizedBox.shrink(),
                data: (tags) => ListView.separated(
                  scrollDirection: Axis.horizontal,
                  // Was hardcoded to 6 against an 8-entry list, which would
                  // have thrown a RangeError the moment the real query returned
                  // fewer.
                  itemCount: tags.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 7),
                  itemBuilder: (context, i) => LbmChip(
                    tags[i].tag,
                    style: ChipStyle.initiative,
                    onTap: () => context.goToResults(tags[i].tag),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(feedProvider),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            if (isGuest) const GuestBanner(),
            // The store's real taxonomy. Hidden until collections are mirrored.
            const CollectionRail(),
            // Once: why there is no heart. Then: anything delivered and
            // waiting for a review.
            const CartTipCard(),
            const ReviewPromptCard(),
            LbmAsync<List<Post>>(
              feed,
              skeleton: const PostCardSkeleton(),
              onRetry: () => ref.invalidate(feedProvider),
              isEmpty: (posts) => posts.isEmpty,
              empty: const LbmEmpty(
                title: 'Nothing posted yet',
                body: 'When sellers list something nearby, it shows up here.',
              ),
              data: (posts) => Column(
                children: [
                  for (final post in posts)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: PostCard(post),
                    ),
                  const Puff(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 26),
                    child: Text(
                      "That's everything new.\nTry a hashtag to keep going.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.6,
                        color: c.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
