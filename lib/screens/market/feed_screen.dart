import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../state/location.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/post_card.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/tips.dart';
import '../../widgets/unverified_banner.dart';
import 'collection_screen.dart';
import 'directory_browse_screen.dart';
import 'results_screen.dart';

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
                  onTap: () => toggleNearMe(context, ref),
                ),
                // No cart icon here any more: CartLayer floats one over
                // every screen, and two on the feed was one too many.
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
            // A member whose address is not confirmed: the two buttons that
            // fix it, before anything refuses them for it.
            const UnverifiedBanner(),
            // The store's real taxonomy. Hidden until collections are mirrored.
            const CollectionRail(),
            // And littlebluecart.com's, the same shape, one chip per
            // directory category. Hidden until the public sync has run.
            const DirectoryRail(),
            // Once: why there is no heart. Then: anything delivered and
            // waiting for a review.
            const CartTipCard(),
            const ReviewPromptCard(),
            // Near me replaces the stream rather than filtering it: see
            // NearMeShelf.
            if (filters.isGeoConstrained)
              NearMeShelf(filters: filters)
            else
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

/// What Near me shows: the listings closest to the person, nearest first.
///
/// The toggle used to flip a flag that only the search screen read, so
/// tapping it on the Market changed nothing whatsoever — which is what
/// "the nearby feature is not working" meant (Grace's testers, 2026-09-23).
///
/// A grid of listings rather than a filtered post stream. The feed carries
/// the twenty most recent posts of every kind, and a distance filter over
/// twenty posts usually leaves nothing; the catalogue is the right thing to
/// ask "what is near me", and it answers with something to buy.
class NearMeShelf extends ConsumerWidget {
  const NearMeShelf({super.key, required this.filters});

  final SearchFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final nearby = ref.watch(nearbyProductsProvider(filters));
    final where = filters.origin?.label ?? 'you';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
          child: Text(
            'Within ${Fmt.distanceMiles(filters.radiusMiles)} of $where',
            style: LbmText.tiny.copyWith(
              color: c.ink2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final miles in const [5.0, 10.0, 25.0, 50.0])
                LbmChip(
                  Fmt.distanceMiles(miles),
                  style: miles == filters.radiusMiles
                      ? ChipStyle.on
                      : ChipStyle.quiet,
                  onTap: () =>
                      ref.read(searchFiltersProvider.notifier).setRadius(miles),
                ),
              LbmChip(
                'Turn off',
                style: ChipStyle.plain,
                onTap: () =>
                    ref.read(searchFiltersProvider.notifier).toggleNearMe(),
              ),
            ],
          ),
        ),
        LbmAsync<List<Product>>(
          nearby,
          skeleton: const GridSkeleton(count: 6),
          onRetry: () => ref.invalidate(nearbyProductsProvider(filters)),
          isEmpty: (items) => items.isEmpty,
          empty: LbmEmpty(
            title:
                'Nothing within '
                '${Fmt.distanceMiles(filters.radiusMiles)}',
            body:
                'Try a wider circle, or turn Near me off to see the whole '
                'Market. A listing only counts as nearby once its shop has '
                'filled in a city.',
          ),
          data: (items) => Padding(
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
              itemCount: items.length,
              itemBuilder: (context, i) => GridCell(
                product: items[i],
                badge: items[i].price,
                onTap: () => context.goToProduct(items[i].id),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
